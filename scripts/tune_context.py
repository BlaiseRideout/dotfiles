#!/usr/bin/env python3
"""Measure what a model's `fit-ctx` floor in models.ini costs in speed, and suggest the largest floor worth having.

llama-serve runs with `--fit on`: llama.cpp shrinks a model's context (and, for MoE models, moves experts to
the CPU) until it fits VRAM, but never below `fit-ctx`. A bigger floor buys context and costs decode speed once
experts spill, so the right value is per model. This reproduces the hand measurements recorded in models.ini
("128k costs ~10% decode speed at a 16k prompt"):

  1. read the model's exact command line from the router (/models -> status.args: sampling, KV type, --fit-target...)
  2. stop llama-serve (its ExecStop remembers the resident model; starting it again restores it)
  3. for each floor, start a private single-model server with only --fit-ctx changed, feed it a prompt that fills
     --prompt-tokens of context, and record prompt-eval and decode tokens/s
  4. print a table and the largest floor whose decode speed is within --max-cost percent of the lowest floor

The prompt is real prose (the repo's markdown, or --prompt-file), not repeated filler: models with MTP
speculative decoding look unrealistically fast on repetitive text. Only tokens/s reported by the server count.

    scripts/tune_context.py gemma-4-26B                       # id or unique substring of the router's model id
    scripts/tune_context.py Qwen3-Coder --floors 32768 65536 131072 --apply
    scripts/tune_context.py --list

The router must be running when you start (it supplies the model's arguments). stdlib only.
"""
import argparse
import json
import os
import re
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path.home()
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state"))
KEY_FILE = Path(os.environ.get("LLAMA_KEY_FILE", STATE / "llama-serve/api-key"))
SERVICE = os.environ.get("LLAMA_SERVICE", "llama-serve.service")
ROUTER = f"http://127.0.0.1:{os.environ.get('LLAMA_PORT', '9931')}"  # same default as ~/.local/lib/llama.sh
PRESET = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "llama-serve/models.ini"
REPO = Path(__file__).resolve().parent.parent
GLOBAL_FLOOR = 32768


# --- HTTP ---------------------------------------------------------------------------------------

def http(url, body=None, key=None, timeout=60):
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    if key:
        req.add_header("Authorization", f"Bearer {key}")  # never printed or put on a command line
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def router_models():
    key = KEY_FILE.read_text().strip() if KEY_FILE.is_file() else None
    try:
        return http(f"{ROUTER}/models", key=key, timeout=5)["data"]
    except (OSError, KeyError, ValueError) as e:
        sys.exit(f"Router not answering at {ROUTER} ({e}). It supplies each model's arguments; start {SERVICE} first.")


def resolve(models, query):
    hits = [m for m in models if m["id"] == query] or [m for m in models if query.lower() in m["id"].lower()]
    if len(hits) != 1:
        names = "\n  ".join(m["id"] for m in (hits or models))
        sys.exit(f"{'No model' if not hits else 'Several models'} match {query!r}; use one of:\n  {names}")
    return hits[0]


# --- the private server ---------------------------------------------------------------------------

def flag(args, name):
    return args.index(name) if name in args else -1


def set_flag(args, name, value):
    i = flag(args, name)
    if i < 0:
        args += [name, str(value)]
    else:
        args[i + 1] = str(value)


def drop_flag(args, name, takes_value):
    i = flag(args, name)
    if i >= 0:
        del args[i:i + (2 if takes_value else 1)]


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def server_args(router_args, floor, port):
    """The router's own command line for this model, with a private port and the floor under test."""
    args = list(router_args)
    set_flag(args, "--port", port)
    set_flag(args, "--fit-ctx", floor)
    drop_flag(args, "--sleep-idle-seconds", True)  # must stay resident for the whole measurement
    drop_flag(args, "--metrics", False)
    return args


class Server:
    """Context manager: runs the server with its log in a temp file (a pipe nobody reads would fill and stall it)."""

    def __init__(self, args, port):
        self.args, self.base = args, f"http://127.0.0.1:{port}"
        self.log = tempfile.NamedTemporaryFile("w+", prefix="tune-ctx-", suffix=".log")

    def __enter__(self):
        self.proc = subprocess.Popen(self.args, stdout=self.log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        return self

    def __exit__(self, *exc):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        self.log.close()
        time.sleep(2)  # let the driver hand the VRAM back before the next load

    def tail(self, n=15):
        self.log.flush()
        self.log.seek(0)
        return "".join(self.log.readlines()[-n:])

    def wait_ready(self, timeout):
        start = time.time()
        while time.time() - start < timeout:
            if self.proc.poll() is not None:
                raise RuntimeError(f"server exited with {self.proc.returncode}:\n{self.tail()}")
            try:
                with urllib.request.urlopen(f"{self.base}/health", timeout=2) as r:
                    if r.status == 200:
                        return
            except OSError:
                pass  # 503 while loading, refused before it binds
            time.sleep(1)
        raise RuntimeError(f"server not ready after {timeout}s:\n{self.tail()}")

    def n_ctx(self):
        try:
            return http(f"{self.base}/props", timeout=10)["default_generation_settings"]["n_ctx"]
        except (OSError, KeyError, ValueError):
            return None


# --- the prompt -------------------------------------------------------------------------------------

def corpus(prompt_file):
    paths = [Path(prompt_file)] if prompt_file else sorted(
        p for p in REPO.rglob("*.md") if ".git" not in p.parts and "node_modules" not in p.parts)
    text = "\n\n".join(p.read_text(errors="replace") for p in paths)
    if len(text) < 1000:
        sys.exit("Not enough prose to build a prompt from; pass --prompt-file.")
    return text


def build_prompt(base, text, target):
    """Text that the server's own tokenizer counts as ~target tokens (repeats the corpus if it is shorter)."""
    count = lambda s: len(http(f"{base}/tokenize", {"content": s}, timeout=120)["tokens"])
    while len(text) < target * 8:
        text += "\n\n" + text
    chars = target * 4
    for _ in range(3):
        n = count(text[:chars])
        chars = max(1, int(chars * target / n))
    body = text[:chars]
    return ("Here are some project notes.\n\n" + body +
            "\n\n---\nWrite a long, detailed review of the notes above: what is well done, what is unclear, and "
            "what you would change, section by section.")


# --- measuring ---------------------------------------------------------------------------------------

def measure(base, prompt, gen_tokens, runs):
    chat = f"{base}/v1/chat/completions"
    http(chat, {"messages": [{"role": "user", "content": "Say hi."}], "max_tokens": 8, "cache_prompt": False},
         timeout=600)  # warm-up: CUDA graphs, allocator
    pp, tg, short = [], [], False
    for _ in range(runs):
        r = http(chat, {"messages": [{"role": "user", "content": prompt}], "max_tokens": gen_tokens,
                        "cache_prompt": False}, timeout=1800)
        t = r.get("timings")
        if not t or not t.get("predicted_per_second"):
            raise RuntimeError("the server's response has no timings; cannot measure")
        pp.append(t["prompt_per_second"])
        tg.append(t["predicted_per_second"])
        short |= t["predicted_n"] < gen_tokens // 2
    return statistics.median(pp), statistics.median(tg), short


def tune(model, floors, a):
    args0 = model["status"]["args"]
    if flag(args0, "--ctx-size") >= 0 or flag(args0, "-c") >= 0:
        print(f"{model['id']}: the preset pins --ctx-size, so fit-ctx has no effect. Skipped.")
        return None
    current = int(args0[flag(args0, "--fit-ctx") + 1]) if flag(args0, "--fit-ctx") >= 0 else GLOBAL_FLOOR
    print(f"\n{model['id']}\n  current fit-ctx {current}; floors {floors}; prompt ~{a.prompt_tokens} tokens; "
          f"{a.gen_tokens} generated; median of {a.runs}")
    print(f"  {'floor':>8} | {'n_ctx':>8} | {'prompt t/s':>10} | {'decode t/s':>10} | {'vs lowest':>9}")
    text, prompt, results = corpus(a.prompt_file), None, []
    for floor in floors:
        port = free_port()
        try:
            with Server(server_args(args0, floor, port), port) as s:
                s.wait_ready(a.load_timeout)
                n_ctx = s.n_ctx()
                if prompt is None:
                    target = a.prompt_tokens
                    if n_ctx and target + a.gen_tokens + 512 > n_ctx:
                        target = n_ctx - a.gen_tokens - 512
                        print(f"  (prompt shortened to {target} tokens to fit the first floor's {n_ctx} context)")
                    prompt = build_prompt(s.base, text, target)
                pp, tg, short = measure(s.base, prompt, a.gen_tokens, a.runs)
        except (RuntimeError, OSError, ValueError, KeyError) as e:
            print(f"  {floor:>8} | FAILED: {str(e).strip()[:600]}")
            break
        base_tg = results[0][3] if results else tg
        results.append((floor, n_ctx, pp, tg))
        note = "  (short generation: speed is noisy)" if short else ""
        print(f"  {floor:>8} | {n_ctx or '?':>8} | {pp:>10.1f} | {tg:>10.1f} | {tg / base_tg * 100:>8.0f}%{note}",
              flush=True)
    if not results:
        return None
    best = results[0]
    for r in results:  # largest floor within budget, stopping at the first one that is too costly
        if r[3] >= results[0][3] * (1 - a.max_cost / 100):
            best = r
        else:
            break
    print(f"  -> fit-ctx = {best[0]}  ({best[3]:.1f} vs {results[0][3]:.1f} tok/s at the {results[0][0]} floor, "
          f"budget {a.max_cost:g}% slower; decode at a ~{a.prompt_tokens // 1000}k prompt)")
    if best[0] == current:
        print("  already the current value")
    return model["id"], best, results[0]


# --- models.ini ----------------------------------------------------------------------------------------

def apply_floor(path, model_id, value):
    """Set `fit-ctx` in the model's [section] (adding the line, or the section). Comments are left alone."""
    lines = path.read_text().splitlines()
    head = f"[{model_id}]"
    try:
        start = lines.index(head)
    except ValueError:
        lines += ["", head, f"fit-ctx = {value}"]
        path.write_text("\n".join(lines) + "\n")
        return "added section"
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    for i in range(start + 1, end):
        if re.match(r"\s*fit-ctx\s*=", lines[i]):
            lines[i] = f"fit-ctx = {value}"
            path.write_text("\n".join(lines) + "\n")
            return "updated"
    # after the section's last setting, not its trailing comments (those belong to the next section's header)
    last = max((i for i in range(start + 1, end) if re.match(r"\s*[^#\s][^=]*=", lines[i])), default=start)
    lines.insert(last + 1, f"fit-ctx = {value}")
    path.write_text("\n".join(lines) + "\n")
    return "added line"


# --- the service ------------------------------------------------------------------------------------------

def systemctl(*args):
    return subprocess.run(["systemctl", "--user", *args], capture_output=True, text=True)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("model", nargs="*", help="router model id, or a unique substring of it (see --list)")
    p.add_argument("--list", action="store_true", help="list the router's model ids and their fit-ctx")
    p.add_argument("--floors", type=int, nargs="+",
                   help=f"fit-ctx values to try (default: {GLOBAL_FLOOR} doubling up to the model's maximum context)")
    p.add_argument("--prompt-tokens", type=int, default=16384, help="prompt size to measure at (default 16384)")
    p.add_argument("--gen-tokens", type=int, default=256, help="tokens to generate per run (default 256)")
    p.add_argument("--runs", type=int, default=2, help="measured runs per floor; the median counts (default 2)")
    p.add_argument("--max-cost", type=float, default=10, metavar="PCT",
                   help="accept a floor up to this %% slower than the lowest one (default 10)")
    p.add_argument("--prompt-file", help="text to build the prompt from (default: the repo's markdown files)")
    p.add_argument("--load-timeout", type=int, default=600, help="seconds to wait for a server to load (default 600)")
    p.add_argument("--apply", action="store_true", help=f"write the recommended fit-ctx into {PRESET}")
    p.add_argument("--preset", type=Path, default=PRESET, help="models.ini to update with --apply")
    p.add_argument("--yes", action="store_true", help=f"don't ask before stopping {SERVICE}")
    a = p.parse_args()

    models = router_models()
    if a.list or not a.model:
        print(f"{'fit-ctx':>8}  {'max ctx':>8}  model id")
        for m in models:
            ia = m["status"].get("args", [])
            i = flag(ia, "--fit-ctx")
            print(f"{ia[i + 1] if i >= 0 else '-':>8}  {m.get('context_length') or '?':>8}  {m['id']}")
        return
    chosen = [resolve(models, q) for q in a.model]

    if systemctl("is-active", "--quiet", SERVICE).returncode != 0:
        sys.exit(f"{SERVICE} is not an active user service; this script stops and restarts it around the run.")
    if not a.yes:
        if not sys.stdin.isatty():
            sys.exit("Not a terminal; pass --yes to let this stop and restart the router.")
        if input(f"This stops {SERVICE} (clients lose the router for a few minutes; the resident model is\n"
                 f"reloaded afterwards). Continue? [y/N] ").strip().lower() != "y":
            return

    def on_term(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, on_term)  # so a kill still restarts the router
    print(f"Stopping {SERVICE}...")
    systemctl("stop", SERVICE)
    time.sleep(3)
    try:
        for m in chosen:
            ceiling = m.get("context_length") or 131072
            floors = a.floors or sorted({f for f in
                                         [GLOBAL_FLOOR * 2 ** k for k in range(8)] if f <= ceiling} | {ceiling})
            floors = [f for f in floors if f >= 1024]
            r = tune(m, floors, a)
            if r and a.apply:
                model_id, best, _ = r
                print(f"  {a.preset}: {apply_floor(a.preset, model_id, best[0])} fit-ctx = {best[0]}")
    except KeyboardInterrupt:
        print("\nInterrupted.")
    finally:
        print(f"Starting {SERVICE} (it reloads the model that was resident"
              f"{', with the new fit-ctx values' if a.apply else ''})...")
        res = systemctl("start", SERVICE)
        if res.returncode != 0:
            print(f"Could not start {SERVICE}: {res.stderr.strip()}", file=sys.stderr)


if __name__ == "__main__":
    main()

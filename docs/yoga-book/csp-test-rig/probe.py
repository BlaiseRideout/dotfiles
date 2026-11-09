"""probe.py [--env KEY=VAL ...] [--runs N] [--wait S]: launch CSP, wait for the start-up splash, sample CPU,
click 'Doodle mode' with the virtual mouse and record whether the splash went away.
Prints one line per run: run, t_splash, cpu%, responsive."""
import argparse, json, os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(__file__))
import inputrig

APP = "com.usebottles.bottles"
APPROACH = False


def clients():
    out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout
    return [c for c in json.loads(out) if "exe" in c["class"]]


def splash():
    for c in clients():
        if c["title"] == "" and c["size"][0] >= 1000 and c["mapped"]:
            return c
    return None


def main_win():
    for c in clients():
        if c["title"] == "CLIP STUDIO PAINT":
            return c


def wine_pid():
    for p in subprocess.run(["pgrep", "-f", "CLIPStudioPaint"], capture_output=True, text=True).stdout.split():
        try:
            env = open("/proc/%s/environ" % p, "rb").read().split(b"\0")
        except OSError:
            continue
        if any(e.startswith(b"WINEPREFIX=") for e in env):
            return int(p)


def cpu(pid, secs=4):
    def tick():
        f = open("/proc/%d/stat" % pid).read().split()
        return int(f[13]) + int(f[14])
    a = tick(); time.sleep(secs); b = tick()
    return round((b - a) / os.sysconf("SC_CLK_TCK") / secs * 100, 1)


def threads(pid, secs=3):
    def snap():
        d = {}
        for t in os.listdir("/proc/%d/task" % pid):
            try:
                f = open("/proc/%d/task/%s/stat" % (pid, t)).read()
                name = f[f.index("(") + 1:f.rindex(")")]
                rest = f[f.rindex(")") + 2:].split()
                d[t] = (name, int(rest[11]) + int(rest[12]))
            except OSError:
                pass
        return d
    a = snap(); time.sleep(secs); b = snap()
    out = []
    for t, (name, v) in b.items():
        if t in a:
            out.append((round((v - a[t][1]) / os.sysconf("SC_CLK_TCK") / secs * 100), name, t))
    out.sort(reverse=True)
    return [o for o in out if o[0] >= 3][:5]


TRACE_FILTER = '.'
TRACE = None   # (debug string, log path) to run Wine directly with tracing
DATA = os.path.expanduser("~/.var/app/com.usebottles.bottles/data")
ENVFILE = "csp-env.sh"
PREFIX = "CSP-wine11"


def launch_traced(debug, logpath):
    exe = subprocess.run("find '%s/bottles/bottles/%s/drive_c/Program Files' -iname CLIPStudioPaint.exe | head -1" % (DATA, PREFIX),
                         shell=True, capture_output=True, text=True).stdout.strip()
    script = os.path.join(DATA, "trace-run.sh")
    open(script, "w").write(
        ". %s/%s\nexport WINEDEBUG='%s'\nexport TRACE_FILTER='%s'\ncd \"$(dirname '%s')\"\n"
        "\"$WINE\" '%s' 2>&1 | grep --line-buffered -E \"$TRACE_FILTER\" > '%s'\n" % (DATA, ENVFILE, debug, TRACE_FILTER, exe, exe, logpath))
    subprocess.Popen(["flatpak", "run", "--command=sh", APP, script], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def launch(extra_env):
    subprocess.run(["flatpak", "kill", APP], capture_output=True)
    time.sleep(3)
    if TRACE:
        return launch_traced(*TRACE)
    env = dict(os.environ)
    env.update(extra_env)
    subprocess.Popen([os.path.expanduser("~/.local/bin/clip-studio-paint")], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


xstate_log = []


def run_once(i, extra_env, wait, click_rel=(883, 468)):
    launch(extra_env)
    t0 = time.time()
    while time.time() - t0 < 90 and not splash():
        time.sleep(1)
    s = splash()
    if not s:
        print(i, "no-splash", flush=True)
        return None
    ts = time.time() - t0
    time.sleep(wait)
    pid = wine_pid()
    c = cpu(pid) if pid else -1
    hot = threads(pid) if pid else []
    nwin = len([w for w in clients() if w["size"][0] > 1])
    s = splash()
    resp = None
    tclose = None
    clicks = 0
    focus = None
    if s:
        m = inputrig.Mouse()
        x, y = s["at"][0] + click_rel[0], s["at"][1] + click_rel[1]
        aw = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True).stdout
        try:
            a = json.loads(aw); focus = (a.get("class"), a.get("title"), a.get("size"))
        except Exception:
            pass
        xs = subprocess.run([os.path.join(os.path.dirname(os.path.abspath(__file__)), "xstate")],
                            capture_output=True, text=True).stdout
        xstate_log.append(xs)
        for clicks in range(1, 4):
            m.click(x, y, hold=0.15, approach=APPROACH)
            t1 = time.time()
            while time.time() - t1 < 6 and splash():
                time.sleep(0.5)
            if splash() is None:
                tclose = round(time.time() - t1, 1)
                break
        resp = splash() is None
        m.close()
    print(json.dumps({"run": i, "t_splash": round(ts, 1), "cpu": c, "responsive": resp, "clicks": clicks, "t_close": tclose, "focus_before": focus, "hot_threads": hot, "n_windows": nwin}), flush=True)
    return resp


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--wait", type=float, default=15)
    ap.add_argument("--approach", action="store_true")
    ap.add_argument("--env", action="append", default=[])
    a = ap.parse_args()
    APPROACH = a.approach
    extra = dict(e.split("=", 1) for e in a.env)
    res = [run_once(i, extra, a.wait) for i in range(a.runs)]
    ok = sum(1 for r in res if r)
    print("summary: %d/%d responsive" % (ok, len(res)), flush=True)
    subprocess.run(["flatpak", "kill", APP], capture_output=True)

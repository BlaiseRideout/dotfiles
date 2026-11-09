"""webflags.py NAME 'FLAGS': run Try-for-free with these WebView2 flags (direct env only), up to 5 attempts
until the click lands, then score whether the right-hand panel shows real content."""
import sys, os, time, re, subprocess, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
from PIL import Image
D = os.path.expanduser("~/.var/app/com.usebottles.bottles/data"); S = os.path.dirname(os.path.abspath(__file__))
name, flags = sys.argv[1], sys.argv[2]
prefix = sys.argv[3] if len(sys.argv) > 3 else "CSP-wine11"
B = D + "/bottles/bottles/" + prefix + "/drive_c"
orig = open(D + "/csp-env.sh.orig").read()
orig = re.sub(r"^export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=.*$",
              "export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='%s --enable-logging --v=0 --log-file=C:/wv2.log'" % flags, orig, flags=re.M)
orig = "\n".join(l for l in orig.split("\n") if not l.startswith("export LD_PRELOAD="))
if prefix != "CSP-wine11":
    orig = orig.replace("CSP-wine11", prefix)
open(D + "/csp-env-flags.sh", "w").write(orig + "\n")
probe.ENVFILE = "csp-env-flags.sh"; probe.PREFIX = prefix
probe.TRACE_FILTER = "LBUTTONDOWN dispatched"; probe.TRACE = ("-all,+message", D + "/trace_flags.log")

def score(path):
    im = Image.open(path).convert("L").crop((1500, 420, 2600, 1560))
    px = im.getdata(); n = len(px); bright = sum(1 for p in px if p > 170)
    return round(100.0 * bright / n, 2)

for a in range(5):
    try: os.remove(B + "/wv2.log")
    except OSError: pass
    probe.launch({})
    t0 = time.time()
    while time.time() - t0 < 60 and not probe.splash(): time.sleep(1)
    time.sleep(22)
    s = probe.splash(); m = inputrig.Mouse()
    m.click(s["at"][0] + 883, s["at"][1] + 468, hold=0.15, approach=True)
    time.sleep(28); m.close()
    txt = open(D + "/trace_flags.log", errors="replace").read()
    good = bool(re.search(r"LBUTTONDOWN dispatched\s+wp=00000001 lp=01d3036f", txt))
    path = "%s/wf_%s_%d.png" % (S, name, a)
    subprocess.run(["grim", "-o", "eDP-1", path])
    print(json.dumps({"flags": name, "attempt": a, "click": "good" if good else "missed", "panel_bright_pct": score(path)}), flush=True)
    if good: break
subprocess.run(["flatpak", "kill", probe.APP], capture_output=True)

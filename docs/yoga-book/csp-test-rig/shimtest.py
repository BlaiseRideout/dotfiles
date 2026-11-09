"""shimtest.py PREFIX ENVFILE LABEL [ATTEMPTS]: Try-for-free test in a test prefix; reports click landing, wv2.log
keep-alive events, shim log activity, and a panel brightness score."""
import sys, os, time, re, subprocess, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
from PIL import Image
import numpy as np
D = os.path.expanduser("~/.var/app/com.usebottles.bottles/data"); S = os.path.dirname(os.path.abspath(__file__))
prefix, envfile, label = sys.argv[1], sys.argv[2], sys.argv[3]
attempts = int(sys.argv[4]) if len(sys.argv) > 4 else 5
B = D + "/bottles/bottles/" + prefix + "/drive_c"
probe.PREFIX = prefix; probe.ENVFILE = envfile
probe.TRACE_FILTER = "LBUTTONDOWN dispatched"; probe.TRACE = ("-all,+message", D + "/trace_shimtest.log")

def score(path):
    a = np.asarray(Image.open(path).convert("L").crop((1500, 420, 2600, 1560)))
    return round(100.0 * float((a > 170).sum()) / a.size, 2)

for a in range(attempts):
    for f in ("wv2.log", "dcomp-csp.log"):
        try: os.remove(B + "/" + f)
        except OSError: pass
    probe.launch({})
    t0 = time.time()
    while time.time() - t0 < 90 and not probe.splash(): time.sleep(1)
    time.sleep(24)
    shot0 = "%s/st_%s_%d_before.png" % (S, label, a); subprocess.run(["grim", "-o", "eDP-1", shot0])
    s = probe.splash()
    if not s:
        print(json.dumps({"attempt": a, "result": "no splash"}), flush=True); continue
    m = inputrig.Mouse()
    m.click(s["at"][0] + 883, s["at"][1] + 468, hold=0.15, approach=True)
    time.sleep(30); m.close()
    txt = open(D + "/trace_shimtest.log", errors="replace").read()
    good = bool(re.search(r"LBUTTONDOWN dispatched\s+wp=00000001 lp=01d3036f", txt))
    path = "%s/st_%s_%d.png" % (S, label, a); subprocess.run(["grim", "-o", "eDP-1", path])
    try: wv = open(B + "/wv2.log", errors="replace").read()
    except OSError: wv = ""
    adds = re.findall(r"/(\d{6}\.\d+):[^\n]*AddKeepAlive\(Default, kBrowserWindow", wv)
    rms = re.findall(r"/(\d{6}\.\d+):[^\n]*RemoveKeepAlive\(Default, kBrowserWindow", wv)
    try: sl = open(B + "/dcomp-csp.log", errors="replace").read()
    except OSError: sl = ""
    print(json.dumps({"attempt": a, "click": "good" if good else "missed", "panel_bright_pct": score(path),
                      "webview_adds": len(adds), "webview_removes": len(rms), "shim_log_lines": sl.count("\n")}), flush=True)
    if good: break
subprocess.run(["flatpak", "kill", probe.APP], capture_output=True)

"""wvtest.py LABEL ATTEMPTS: Try-for-free web view test. Deletes wv2.log first so only this run counts.
Prints per attempt: whether a WebView2 browser started, keep-alive lifetimes, and saves the panel crop."""
import sys, os, time, re, subprocess, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
D = os.path.expanduser("~/.var/app/com.usebottles.bottles/data"); import probe as _p
PFX = sys.argv[3] if len(sys.argv) > 3 else "CSP-wine11"
_p.PREFIX = PFX; _p.ENVFILE = "csp-env-test.sh" if PFX != "CSP-wine11" else "csp-env.sh"
B = D + "/bottles/bottles/" + PFX + "/drive_c"
S = os.path.dirname(os.path.abspath(__file__))
label, n = sys.argv[1], int(sys.argv[2])
probe.TRACE_FILTER = "."; probe.TRACE = ("-all", D + "/trace_wvtest.log")
res = []
for a in range(n):
    try: os.remove(B + "/wv2.log")
    except OSError: pass
    probe.launch({})
    t0 = time.time()
    while time.time() - t0 < 60 and not probe.splash(): time.sleep(1)
    time.sleep(22)
    s = probe.splash()
    m = inputrig.Mouse()
    m.click(s["at"][0] + 883, s["at"][1] + 468, hold=0.15, approach=True)
    time.sleep(25); m.close()
    try: txt = open(B + "/wv2.log", errors="replace").read()
    except OSError: txt = ""
    adds = [float(x) for x in re.findall(r"/(\d{6}\.\d+):[^\n]*AddKeepAlive\(Default, kBrowserWindow", txt)]
    rms = [float(x) for x in re.findall(r"/(\d{6}\.\d+):[^\n]*RemoveKeepAlive\(Default, kBrowserWindow", txt)]
    subprocess.run(["grim", "-o", "eDP-1", "%s/wv_%s_%d.png" % (S, label, a)])
    r = {"label": label, "attempt": a, "webview_started": bool(adds), "adds": adds, "removes": rms,
         "alive_after_25s": bool(adds) and len(rms) < len(adds) or (bool(adds) and "Shutdown" not in txt)}
    res.append(r); print(json.dumps(r), flush=True)
subprocess.run(["flatpak", "kill", probe.APP], capture_output=True)

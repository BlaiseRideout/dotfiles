import sys, os, time, re, subprocess; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
D = os.path.expanduser("~/.var/app/com.usebottles.bottles/data")
probe.PREFIX = "CSP-shimtest"; probe.ENVFILE = sys.argv[1]; label = sys.argv[2]
probe.TRACE_FILTER = "NtCreateUserProcess|LBUTTONDOWN dispatched"
probe.TRACE = ("-all,+process,+message", D + "/trace_pv_%s.log" % label)
for attempt in range(8):
    probe.launch({})
    t0 = time.time()
    while time.time() - t0 < 90 and not probe.splash(): time.sleep(1)
    time.sleep(24)
    s = probe.splash(); m = inputrig.Mouse()
    m.click(s["at"][0] + 883, s["at"][1] + 468, hold=0.15, approach=True); time.sleep(22); m.close()
    L = D + "/trace_pv_%s.log" % label
    txt = open(L, errors="replace").read().split("\n")
    idx = [i for i, l in enumerate(txt) if re.search(r"LBUTTONDOWN dispatched\s+wp=00000001 lp=01d3036f", l)]
    if idx:
        after = txt[idx[0]:]
        n = sum(1 for l in after if "NtCreateUserProcess" in l and "msedgewebview2" in l)
        subprocess.run(["grim", "-o", "eDP-1", "%s/pv_%s.png" % (os.path.dirname(os.path.abspath(__file__)), label)])
        print("variant", label, "attempt", attempt, "good click; msedgewebview2 processes created after click:", n, flush=True); break
    print("variant", label, "attempt", attempt, "missed", flush=True)
subprocess.run(["flatpak", "kill", probe.APP], capture_output=True)

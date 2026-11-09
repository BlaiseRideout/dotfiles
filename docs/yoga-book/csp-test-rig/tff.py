"""tff.py PREFIX ENVFILE LABEL [--privacy] [--wait N]: launch traced, click Try for free, screenshot the splash."""
import sys, os, time, re, subprocess; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
D = os.path.expanduser("~/.var/app/com.usebottles.bottles/data"); S = os.path.dirname(os.path.abspath(__file__))
prefix, envfile, label = sys.argv[1:4]; wait = 30
if "--wait" in sys.argv: wait = int(sys.argv[sys.argv.index("--wait") + 1])
log = D + "/trace_%s.log" % label
probe.PREFIX = prefix; probe.ENVFILE = envfile
probe.TRACE_FILTER = os.environ.get("TFF_FILTER", "dcomp|NtCreateUserProcess|LBUTTONDOWN dispatched|err:|page fault|nhandled")
probe.TRACE = (os.environ.get("TFF_DEBUG", "err+all,fixme+all,+dcomp,+process,+message"), log)
def shot(name):
    s = probe.splash()
    if s: subprocess.run(["grim", "-g", "%d,%d %dx%d" % (s["at"][0], s["at"][1], s["size"][0], s["size"][1]), "%s/tff_%s_%s.png" % (S, label, name)])
    return s
def click(x, y, w):
    s = probe.splash(); m = inputrig.Mouse(); m.click(s["at"][0] + x, s["at"][1] + y, hold=0.15, approach=True); time.sleep(w); m.close()
for attempt in range(6):
    probe.launch({})
    t0 = time.time()
    while time.time() - t0 < 90 and not probe.splash(): time.sleep(1)
    time.sleep(24)
    if not probe.splash(): print("no splash"); continue
    if "--privacy" in sys.argv: click(883, 688, 8)
    shot("before"); click(883, 468, wait)
    txt = open(log, errors="replace").read()
    if re.search(r"LBUTTONDOWN dispatched\s+wp=00000001 lp=01d3036f", txt):
        shot("after"); print("attempt", attempt, "good click"); break
    print("attempt", attempt, "missed")
if "--keep" not in sys.argv: subprocess.run(["flatpak", "kill", probe.APP], capture_output=True)

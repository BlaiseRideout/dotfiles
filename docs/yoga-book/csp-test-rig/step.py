"""step.py X Y OUT [WAIT]: glide-click at splash-relative X,Y, wait, screenshot the splash to OUT."""
import sys, os, time, subprocess; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
x, y, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]; wait = float(sys.argv[4]) if len(sys.argv) > 4 else 8
s = probe.splash()
if x >= 0:
    m = inputrig.Mouse(); m.click(s["at"][0] + x, s["at"][1] + y, hold=0.15, approach=True); time.sleep(wait); m.close()
s = probe.splash()
if not s: print("no splash"); sys.exit()
subprocess.run(["grim", "-g", "%d,%d %dx%d" % (s["at"][0], s["at"][1], s["size"][0], s["size"][1]), out])

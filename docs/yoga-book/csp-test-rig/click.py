"""click.py REL_X REL_Y [n]: glide-click at a position relative to the splash window (logical px)."""
import sys, time
import inputrig, probe
s = probe.splash()
if not s:
    print("no splash window"); sys.exit(1)
x, y = s["at"][0] + int(sys.argv[1]), s["at"][1] + int(sys.argv[2])
m = inputrig.Mouse()
for _ in range(int(sys.argv[3]) if len(sys.argv) > 3 else 1):
    m.click(x, y, hold=0.15, approach=True)
    time.sleep(1.0)
m.close()
print("clicked at", x, y, "splash", s["at"], s["size"])

"""burst.py X Y N LABEL: glide to splash-relative X,Y (no click if N<0... ) then capture N shots 0.4 s apart; print the count of bright pixels in the panel area."""
import sys, os, time, subprocess; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe, inputrig
from PIL import Image
import numpy as np
x, y, n, label = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
click = "--click" in sys.argv
s = probe.splash(); g = "%d,%d %dx%d" % (s["at"][0], s["at"][1], s["size"][0], s["size"][1])
m = inputrig.Mouse()
m.move(s["at"][0] + x - 40, s["at"][1] + y - 40); time.sleep(0.2); m.glide(40, 40); time.sleep(0.1)
if click: m.click(hold=0.15)
out = []
for i in range(n):
    p = "burst_%s_%02d.png" % (label, i); subprocess.run(["grim", "-g", g, p])
    a = np.asarray(Image.open(p).convert("L").crop((430, 120, 1180, 820)))
    out.append(int((a > 150).sum())); time.sleep(0.4)
m.close(); print(out)

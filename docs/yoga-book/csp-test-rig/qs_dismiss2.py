import sys, time
import inputrig, evdev.ecodes as e
from qs_lib import *
tag = sys.argv[1]
pen = inputrig.Pen(); m = inputrig.Mouse(); k = inputrig.Keyboard(); time.sleep(1.0)
def P(name): return pills(shot("qd2_%s_%s.png" % (tag, name)))
try:
    stroke(pen, 300, 2.0, x0=400); time.sleep(1.2)
    print("hold stroke (pill)    :", P("pill"))
    time.sleep(8)
    print("+8 s                  :", P("wait8"))
    stroke(pen, 520, 0, x0=560); time.sleep(1.5)
    print("+ plain pen stroke    :", P("plain"))
    pen.hover(2 * 900, 700, n=30); time.sleep(1.0)
    print("+ pen hovering away   :", P("hover"))
    k._tap(e.KEY_ESC); time.sleep(1.2)
    print("+ Escape              :", P("esc"))
    # canvas pan with the hand tool: hold space and drag with the pen
    k.ui.write(e.EV_KEY, e.KEY_SPACE, 1); k.ui.syn(); time.sleep(0.3)
    pts = inputrig.smooth([(2 * 800, 600), (2 * 700, 640)], steps=10)
    pen.stroke(pts, pressure=1500); pen.lift(0.3)
    k.ui.write(e.EV_KEY, e.KEY_SPACE, 0); k.ui.syn(); time.sleep(1.5)
    print("+ pan canvas (space+pen):", P("pan"))
    time.sleep(20)
    print("+ 20 s                :", P("wait20"))
    pen.leave()
finally:
    pen.close(); m.close(); k.close()

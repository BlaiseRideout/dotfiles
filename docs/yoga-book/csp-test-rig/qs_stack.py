import sys, time
import inputrig
from qs_lib import *
tag = sys.argv[1]
pen = inputrig.Pen(); time.sleep(1.0)
try:
    print("start             :", pills(shot("st_%s_start.png" % tag)))
    for i, y0 in enumerate((300, 470, 640)):
        stroke(pen, y0, 2.0, x0=360 + 30 * i); time.sleep(1.2)
        print("hold stroke %d at y=%d:" % (i + 1, y0), pills(shot("st_%s_%d.png" % (tag, i + 1))))
    stroke(pen, 300, 0, x0=520); time.sleep(1.5)
    print("plain stroke       :", pills(shot("st_%s_plain.png" % tag)))
    pen.leave()
finally:
    pen.close()

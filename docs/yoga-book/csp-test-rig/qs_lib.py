import os, time, subprocess
import inputrig
from PIL import Image
import numpy as np
REGION = (560, 240, 2300, 1300)     # canvas area in screenshot pixels
_T = np.asarray(Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "pill_template.png")).convert("L")).astype(np.float64)

def shot(name):
    subprocess.run(["grim", "-o", "eDP-1", name]); return name

def _ncc(img, tpl):
    H, W = img.shape; h, w = tpl.shape
    t = tpl - tpl.mean(); tn = np.sqrt((t ** 2).sum())
    # sliding sums via integral images
    def box(a):
        c = a.cumsum(0).cumsum(1); c = np.pad(c, ((1, 0), (1, 0)))
        return c[h:, w:] - c[:-h, w:] - c[h:, :-w] + c[:-h, :-w]
    s1 = box(img); s2 = box(img * img)
    n = h * w
    var = s2 - s1 * s1 / n
    from numpy.fft import rfft2, irfft2
    shp = (H + h, W + w)
    corr = irfft2(rfft2(img, shp) * np.conj(rfft2(t, shp)), shp)[:H - h + 1, :W - w + 1]
    den = np.sqrt(np.maximum(var[:H - h + 1, :W - w + 1], 1e-9)) * tn
    return corr / den

def pills(path, thresh=0.80):
    img = np.asarray(Image.open(path).convert("L").crop(REGION)).astype(np.float64)
    m = _ncc(img, _T)
    out = []
    mm = m.copy()
    for _ in range(6):
        i = np.unravel_index(np.argmax(mm), mm.shape)
        if mm[i] < thresh: break
        out.append((int(i[1]) + REGION[0], int(i[0]) + REGION[1], round(float(mm[i]), 2)))
        y, x = i; mm[max(0, y - 60):y + 60, max(0, x - 90):x + 90] = -1
    return out

def stroke(pen, y0, hold, x0=380):
    pts = inputrig.smooth([(2 * x0, y0), (2 * (x0 + 70), y0 + 30), (2 * (x0 + 140), y0 + 5), (2 * (x0 + 220), y0 + 40)], steps=14)
    pen.stroke(pts, pressure=2200)
    if hold:
        pen.hold(hold, pressure=1800)
    pen.lift(0.4)

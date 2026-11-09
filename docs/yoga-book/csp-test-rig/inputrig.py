"""Synthetic input for CSP testing: a virtual mouse (clicks at the Hyprland cursor) and a
virtual pen tablet (pressure, proximity, hold-still jitter) mapped to one panel.

All coordinates are Hyprland logical screen pixels of the output the pen is bound to
(eDP-1: 1440x900 at scale 2).
"""
import random
import subprocess
import time

import evdev
import evdev.ecodes as e

OUTPUT = "eDP-1"
OUT_W, OUT_H = 1440, 900
AX = 32767          # tablet axis range 0..AX
PMAX = 4095


def hypr(cmd):
    return subprocess.run(["hyprctl", "dispatch", cmd], capture_output=True, text=True).stdout.strip()


def repl(lua):
    return subprocess.run(["hyprctl", "repl", lua], capture_output=True, text=True).stdout.strip()


class Mouse:
    def __init__(self):
        self.ui = evdev.UInput({e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT],
                                e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL, e.REL_WHEEL_HI_RES]}, name="claude-virtual-mouse")
        time.sleep(0.5)

    def move(self, x, y):
        hypr('hl.dsp.cursor.move({ x = %d, y = %d })' % (x, y))
        time.sleep(0.05)
        # a one-unit wiggle so the compositor notices focus changes under the cursor
        self.ui.write(e.EV_REL, e.REL_X, 1); self.ui.write(e.EV_REL, e.REL_X, -1); self.ui.syn()
        time.sleep(0.05)

    def glide(self, dx, dy, steps=10, dt=0.02):
        """Relative motion in small steps, like a hand."""
        sx = sy = 0
        for i in range(1, steps + 1):
            tx, ty = round(dx * i / steps), round(dy * i / steps)
            self.ui.write(e.EV_REL, e.REL_X, tx - sx)
            self.ui.write(e.EV_REL, e.REL_Y, ty - sy)
            self.ui.syn()
            sx, sy = tx, ty
            time.sleep(dt)

    def click(self, x=None, y=None, hold=0.08, approach=False):
        if x is not None and approach:
            hypr('hl.dsp.cursor.move({ x = %d, y = %d })' % (x - 40, y - 12))
            time.sleep(0.2)
            self.glide(40, 12)
            time.sleep(0.25)
        elif x is not None:
            self.move(x, y)
        self.ui.write(e.EV_KEY, e.BTN_LEFT, 1); self.ui.syn()
        time.sleep(hold)
        self.ui.write(e.EV_KEY, e.BTN_LEFT, 0); self.ui.syn()
        time.sleep(0.1)

    def wheel(self, notches):
        for _ in range(abs(notches)):
            sgn = 1 if notches > 0 else -1
            self.ui.write(e.EV_REL, e.REL_WHEEL_HI_RES, 120 * sgn)
            self.ui.write(e.EV_REL, e.REL_WHEEL, sgn)
            self.ui.syn(); time.sleep(0.15)

    def close(self):
        self.ui.close()


class Pen:
    NAME = "claude-virtual-pen"

    def __init__(self):
        cap = {
            e.EV_KEY: [e.BTN_TOOL_PEN, e.BTN_TOUCH, e.BTN_STYLUS, e.BTN_STYLUS2],
            e.EV_ABS: [
                (e.ABS_X, evdev.AbsInfo(0, 0, AX, 0, 0, 100)),
                (e.ABS_Y, evdev.AbsInfo(0, 0, AX, 0, 0, 100)),
                (e.ABS_PRESSURE, evdev.AbsInfo(0, 0, PMAX, 0, 0, 0)),
                (e.ABS_DISTANCE, evdev.AbsInfo(0, 0, 255, 0, 0, 0)),
                (e.ABS_TILT_X, evdev.AbsInfo(0, -64, 63, 0, 0, 57)),
                (e.ABS_TILT_Y, evdev.AbsInfo(0, -64, 63, 0, 0, 57)),
            ],
        }
        self.ui = evdev.UInput(cap, name=self.NAME, vendor=0x4321, product=0x8765,
                               input_props=[e.INPUT_PROP_DIRECT])
        time.sleep(1.0)
        # bind to the panel the way yoga.lua binds the real digitisers
        repl("hl.device({ name = '%s', output = '%s' })" % (self.NAME, OUTPUT))
        time.sleep(0.5)
        self.x = self.y = 0
        self.prox = False
        self.touching = False

    def _ax(self, sx, sy):
        return (max(0, min(AX, int(sx / OUT_W * AX))), max(0, min(AX, int(sy / OUT_H * AX))))

    def _send(self, sx, sy, pressure=0, dist=None):
        ax, ay = self._ax(sx, sy)
        w = self.ui.write
        if not self.prox:
            w(e.EV_KEY, e.BTN_TOOL_PEN, 1)
            self.prox = True
        w(e.EV_ABS, e.ABS_X, ax)
        w(e.EV_ABS, e.ABS_Y, ay)
        w(e.EV_ABS, e.ABS_PRESSURE, int(pressure))
        w(e.EV_ABS, e.ABS_DISTANCE, 0 if pressure > 0 else (dist if dist is not None else 40))
        w(e.EV_ABS, e.ABS_TILT_X, 0)
        w(e.EV_ABS, e.ABS_TILT_Y, 0)
        touching = pressure > 0
        if touching != self.touching:
            w(e.EV_KEY, e.BTN_TOUCH, 1 if touching else 0)
            self.touching = touching
        self.ui.syn()
        self.x, self.y = sx, sy

    def hover(self, sx, sy, n=5, dt=0.01):
        for _ in range(n):
            self._send(sx, sy, 0)
            time.sleep(dt)

    def stroke(self, pts, pressure=2000, dt=0.008):
        """Draw through (x, y) points: pen goes down at the first, up after the last."""
        self.hover(*pts[0], n=3)
        for i, (x, y) in enumerate(pts):
            p = pressure * (0.4 + 0.6 * min(i, len(pts) - 1 - i, 10) / 10)
            self._send(x, y, max(p, 200))
            time.sleep(dt)

    def hold(self, seconds, pressure=1800, dt=0.008, jitter=0.15):
        """Stay put with the sensor noise a real pen reports (tiny position/pressure wobble)."""
        t_end = time.time() + seconds
        x, y = self.x, self.y
        while time.time() < t_end:
            self._send(x + random.uniform(-jitter, jitter), y + random.uniform(-jitter, jitter),
                       max(200, pressure + random.randint(-25, 25)))
            time.sleep(dt)

    def lift(self, hover_for=0.3):
        self._send(self.x, self.y, 0, dist=20)
        self.hover(self.x, self.y, n=int(hover_for / 0.01))

    def leave(self):
        if self.prox:
            self.ui.write(e.EV_KEY, e.BTN_TOOL_PEN, 0)
            self.ui.write(e.EV_ABS, e.ABS_PRESSURE, 0)
            self.ui.syn()
            self.prox = False
            self.touching = False

    def close(self):
        self.leave()
        time.sleep(0.2)
        self.ui.close()


def smooth(points, steps=12):
    out = []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        for i in range(steps):
            t = i / steps
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    out.append(points[-1])
    return out


class Keyboard:
    """Virtual US-layout keyboard: type(text), press(key)."""
    _plain = {c: getattr(e, "KEY_" + c.upper()) for c in "abcdefghijklmnopqrstuvwxyz"}
    _digits = {str(i): getattr(e, "KEY_%d" % i) for i in range(10)}
    _punct = {" ": e.KEY_SPACE, "-": e.KEY_MINUS, "=": e.KEY_EQUAL, "[": e.KEY_LEFTBRACE, "]": e.KEY_RIGHTBRACE,
              ";": e.KEY_SEMICOLON, "'": e.KEY_APOSTROPHE, ",": e.KEY_COMMA, ".": e.KEY_DOT, "/": e.KEY_SLASH,
              "\\": e.KEY_BACKSLASH, "`": e.KEY_GRAVE, "\t": e.KEY_TAB, "\n": e.KEY_ENTER}
    _shifted = {"!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
                "_": "-", "+": "=", "{": "[", "}": "]", ":": ";", '"': "'", "<": ",", ">": ".", "?": "/", "|": "\\", "~": "`"}

    def __init__(self):
        keys = list(self._plain.values()) + list(self._digits.values()) + list(self._punct.values()) + \
            [e.KEY_LEFTSHIFT, e.KEY_ESC, e.KEY_BACKSPACE, e.KEY_LEFTCTRL, e.KEY_A, e.KEY_DOWN, e.KEY_UP]
        self.ui = evdev.UInput({e.EV_KEY: sorted(set(keys))}, name="claude-virtual-keyboard")
        time.sleep(0.6)

    def _tap(self, code, shift=False, dt=0.02):
        if shift:
            self.ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1); self.ui.syn()
        self.ui.write(e.EV_KEY, code, 1); self.ui.syn(); time.sleep(dt)
        self.ui.write(e.EV_KEY, code, 0); self.ui.syn()
        if shift:
            self.ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0); self.ui.syn()
        time.sleep(dt)

    def type(self, text, dt=0.03):
        for ch in text:
            if ch in self._shifted:
                base = self._shifted[ch]
                code = self._digits.get(base) or self._punct[base]
                self._tap(code, True, dt)
            elif ch.isupper() and ch.lower() in self._plain:
                self._tap(self._plain[ch.lower()], True, dt)
            elif ch in self._plain:
                self._tap(self._plain[ch], False, dt)
            elif ch in self._digits:
                self._tap(self._digits[ch], False, dt)
            else:
                self._tap(self._punct[ch], False, dt)

    def press(self, code):
        self._tap(code)

    def close(self):
        self.ui.close()


# --- Dvorak: the compositor applies the user's layout (us/dvorak) to uinput keys, so to produce a character we
# press the QWERTY-position key that yields it in Dvorak.
_QWERTY_ROWS = [
    ("`1234567890-=", "`1234567890[]"), ("qwertyuiop[]\\", "',.pyfgcrl/=\\"),
    ("asdfghjkl;'", "aoeuidhtns-"), ("zxcvbnm,./", ";qjkxbmwvz"),
]
_SHIFT_DV = {"`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
             "[": "{", "]": "}", "'": '"', ",": "<", ".": ">", "/": "?", "=": "+", "\\": "|", "-": "_", ";": ":"}


def dvorak_map():
    """char -> (qwerty char whose keycode to press, shift?)"""
    m = {" ": (" ", False), "\t": ("\t", False), "\n": ("\n", False)}
    for qrow, drow in _QWERTY_ROWS:
        for q, d in zip(qrow, drow):
            m[d] = (q, False)
            if d.isalpha():
                m[d.upper()] = (q, True)
            elif d in _SHIFT_DV:
                m[_SHIFT_DV[d]] = (q, True)
    return m


_DV = dvorak_map()


def _qwerty_code(ch):
    if ch in Keyboard._plain: return Keyboard._plain[ch]
    if ch in Keyboard._digits: return Keyboard._digits[ch]
    return Keyboard._punct[ch]


def type_dvorak(kb, text, dt=0.04):
    for ch in text:
        q, shift = _DV[ch]
        kb._tap(_qwerty_code(q), shift, dt)

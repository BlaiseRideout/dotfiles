#!/usr/bin/env python3
"""palm-sim: yoga/bin/yoga-palm against synthetic touch-controller reports.

No hardware, no Hyprland: reports are built in the controller's real 57-byte layout (docs/yoga-book/
palm.md) and fed to the detector with a virtual clock; the actuator is a recording stub. The
traffic patterns are the ones measured on the unit (a fingertip arrives every 8 ms frame; a palm
drops most frames; a palm's contacts jump).

  python3 yoga/tests/palm-sim.py
"""
import importlib.machinery
import importlib.util
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "yoga", "bin"))
loader = importlib.machinery.SourceFileLoader("yoga_palm", os.path.join(ROOT, "yoga", "bin", "yoga-palm"))
spec = importlib.util.spec_from_loader("yoga_palm", loader)
palm = importlib.util.module_from_spec(spec)
loader.exec_module(palm)

FRAME = 1 / 125
fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print("    FAIL: " + msg)


def touch_report(rid, contacts, scan=0):
    """contacts: [(id, x, y)] touching; the rest of the 10 slots hold a stale contact, as seen."""
    b = bytearray(57)
    b[0] = rid
    for k in range(10):
        o = 1 + 5 * k
        if k < len(contacts):
            cid, x, y = contacts[k]
            b[o] = 1 | 2 | (cid << 3)         # tip, confident, contact id
        else:
            x, y = 4191, 5183                  # stale: tip bit still set, but beyond the contact count
            b[o] = 1 | 2 | ((k + 1) << 3)
        b[o + 1], b[o + 2], b[o + 3], b[o + 4] = x & 255, x >> 8, y & 255, y >> 8
    b[51:55] = scan.to_bytes(4, "little")
    b[55] = len(contacts)
    return bytes(b)


def lift_report(rid):
    b = bytearray(touch_report(rid, []))
    b[55] = 0
    return bytes(b)


def pen_report(rid, in_range):
    return bytes([rid, 0x20 if in_range else 0x00] + [0] * 20)


class World:
    def __init__(self):
        self.t = 100.0
        self.calls = []
        self.d = palm.Daemon(apply=lambda node, on: (self.calls.append((round(self.t, 3), node, on)),
                                                     "suppressed" if on else "released")[1])
        self.rng = random.Random(7)

    def step(self, dt=FRAME):
        self.t += dt
        self.d.sync(self.t)

    def feed(self, buf):
        self.d.feed(self.t, buf)

    def run(self, secs, report=None, rate=1.0):
        """Advance secs in frames; every frame yields report(frame index) with probability rate."""
        n = int(secs / FRAME)
        for i in range(n):
            if report and self.rng.random() < rate:
                r = report(i)
                for b in (r if isinstance(r, list) else [r]):
                    self.feed(b)
            self.step()

    def state(self, node):
        return self.d.applied[node]


def finger(rid=48, x=5000, y=3000, moving=False):
    return lambda i: touch_report(rid, [(1, x + (i * 12 % 600 if moving else 0), y + (i * 7 % 300 if moving else 0))])


def scenario(name, fn):
    before = fails
    w = World()
    fn(w)
    print(f"  {'ok  ' if fails == before else 'FAIL'} {name}")


def s_finger_still(w):
    w.run(3, finger())
    check(not w.state("top"), "a fingertip held still is never suppressed")
    check(not w.calls, "no call to Hyprland at all")


def s_finger_moving(w):
    w.run(3, finger(moving=True))
    check(not w.state("top") and not w.calls, "a moving fingertip (700-unit frames) is never suppressed")


def s_finger_lossy(w):
    w.run(3, finger(), rate=0.89)       # the lowest density a finger showed
    check(not w.calls, "a fingertip at 0.89 of the frames is not suppressed")


def s_two_fingers(w):
    w.run(2, lambda i: touch_report(48, [(1, 3000 + i % 40, 3000), (2, 6000 - i % 40, 3500)]))
    check(not w.calls, "a two-finger gesture is not suppressed")


def s_palm_sparse_still(w):
    # measured: 13 reports/s, two contacts flickering
    w.run(2, lambda i: touch_report(48, [(1, 5700, 3000), (2, 6400, 3300)]), rate=0.10)
    check(w.state("top"), "a still palm (0.1 of the frames) is suppressed")
    check(not w.state("bottom"), "...only on its own node")
    t0 = w.calls[0][0] - 100.0
    check(t0 < 0.5, f"...within half a second of landing (took {t0:.2f}s)")


def s_palm_sparse_moving(w):
    w.run(2, lambda i: touch_report(48, [(1, 4000 + i * 9 % 2000, 3000), (2, 5000, 3300)]), rate=0.46)
    check(w.state("top"), "a moving palm (0.46 of the frames, measured 58/s) is suppressed")


def s_whole_hand(w):
    w.run(2, lambda i: touch_report(48, [(k + 1, 2800 + k * 800, 900 + k * 800) for k in range(5)]), rate=0.02)
    check(w.state("top"), "a whole hand (2 reports/s) is suppressed")


def s_teleport(w):
    # full rate, but the contact jumps 13 cm between two frames (the palm splitting into blobs)
    pos = [(5000, 3000)] * 12 + [(5100, 3000)] * 3 + [(5000 + 3000, 3000)]
    for i, (x, y) in enumerate(pos):
        w.feed(touch_report(48, [(1, x, y)]))
        w.step()
    check(w.state("top"), "a 3000-unit jump in one frame suppresses at once, before the density window is full")


def s_jump_other_ids(w):
    # two fingers far apart that swap slots are two ids, not one contact teleporting
    for i in range(30):
        w.feed(touch_report(48, [(1, 1000, 1000), (2, 9000, 5000)] if i % 2 else [(2, 9000, 5000), (1, 1000, 1000)]))
        w.step()
    check(not w.calls, "contacts changing slots do not count as a jump")


def s_stale_slots(w):
    # the controller leaves stale contacts (tip bit set) past the contact count: ignored
    b = touch_report(48, [(1, 5000, 3000)])
    check(len(palm.parse_touch(b)) == 1, "only the first <count> slots are read")
    check(palm.parse_touch(lift_report(48)) == [], "a report with count 0 is a lift")


def s_release_after_hold(w):
    w.run(1, lambda i: touch_report(48, [(1, 5700, 3000)]), rate=0.1)
    check(w.state("top"), "palm on")
    w.feed(lift_report(48))
    w.run(0.4)
    check(w.state("top"), "still off 0.4 s after the lift (hold is 0.6 s)")
    w.run(0.5)
    check(not w.state("top"), "back on after the hold")
    check([c[2] for c in w.calls] == [True, False], "exactly one off and one on")


def s_finger_during_hold(w):
    w.run(1, lambda i: touch_report(48, [(1, 5700, 3000)]), rate=0.1)
    w.feed(lift_report(48))
    w.run(0.3)
    w.run(1.0, finger())                    # a real finger lands right after the palm
    check(w.state("top"), "a finger touching within the hold stays swallowed (the hold runs from the last touch)")
    w.feed(lift_report(48))
    w.run(1.0)
    check(not w.state("top"), "and the node comes back once nothing touches")


def s_silent_palm(w):
    # reports stop without a lift report: released after the (longer) silence timeout, never stuck
    w.run(1, lambda i: touch_report(48, [(1, 5700, 3000)]), rate=0.1)
    w.run(1.0)
    check(w.state("top"), "a palm that goes quiet for 1 s without a lift is still off")
    w.run(4.5)
    check(not w.state("top"), "released after the silence timeout, never stuck off")


def s_whole_hand_steady(w):
    w.run(5, lambda i: touch_report(48, [(k + 1, 2800 + k * 800, 900 + k * 800) for k in range(5)]), rate=0.012)
    check([c[2] for c in w.calls] == [True], "a whole hand reporting once or twice a second stays off, without flicker")


def s_pen(w):
    w.feed(pen_report(20, True))
    w.step()
    check(w.state("top") and not w.state("bottom"), "pen in range on the top stylus suppresses the top touchscreen")
    for _ in range(40):
        w.feed(pen_report(20, True))
        w.run(0.05)
    check(w.state("top"), "stays off while the pen keeps reporting")
    w.feed(pen_report(20, False))
    w.run(0.3)
    check(w.state("top"), "still off inside the tail")
    w.run(0.5)
    check(not w.state("top"), "back on after the tail")


def s_pen_watchdog(w):
    w.feed(pen_report(40, True))
    w.run(1.0)
    check(w.state("bottom"), "bottom pen in range suppresses the bottom touchscreen")
    w.run(1.5)
    check(not w.state("bottom"), "a pen that stops reporting is taken as gone after the watchdog (never stuck)")


def s_pen_off(w):
    old = palm.USE_PEN
    palm.USE_PEN = False
    try:
        w.feed(pen_report(20, True))
        w.run(0.5)
        check(not w.calls, "YOGA_PALM_PEN=0: the pen does nothing")
    finally:
        palm.USE_PEN = old


def s_retry(w):
    answers = ["error: no socket", "error: no socket", "suppressed"]
    w.d.apply = lambda node, on: (w.calls.append((w.t, node, on)), answers.pop(0) if answers else "released")[1]
    w.run(3.0, lambda i: pen_report(20, True), rate=0.05)
    check(len([c for c in w.calls if c[2]]) >= 3, "a failed call is retried")
    check(w.state("top"), "...until it takes")


def s_reassert(w):
    w.d.apply = lambda node, on: (w.calls.append((w.t, node, on)), "suppressed" if on else "released")[1]
    for _ in range(80):
        w.feed(pen_report(20, True))
        w.run(0.1)
    ons = [c for c in w.calls if c[2]]
    check(len(ons) >= 1 + 8 // 5, "suppression is asserted again every few seconds (a config reload resets Hyprland's side)")


def s_dry(w):
    w.d.dry = True
    w.feed(pen_report(20, True))
    w.run(0.5)
    check(not w.calls, "--dry never calls Hyprland")


def s_confidence(w):
    b = bytearray(touch_report(48, [(1, 5000, 3000)]))
    b[1] &= ~2                                      # firmware clears the confidence bit
    w.feed(bytes(b))
    w.step()
    check(w.state("top"), "if the firmware ever clears the confidence flag, that is a palm")


def s_tap_then_finger_lift_reports(w):
    for x in (2000, 6000, 9000):
        w.run(0.2, finger(x=x))
        w.feed(lift_report(48))
        w.run(0.5)
    check(not w.calls, "taps with their lift reports never trigger anything")


def s_sparse_hand_no_lift(w):
    # a whole hand reporting about twice a second, no lift reports: caught by the density
    for _ in range(5):
        w.feed(touch_report(48, [(k + 1, 2800 + k * 800, 900 + k * 800) for k in range(5)]))
        w.run(0.5)
    check(w.state("top"), "reports 0.5 s apart, repeatedly, are a palm")
    check([c[2] for c in w.calls] == [True], "...switched off once, no flicker")


def s_resting_palm(w):
    # the measured palm: a few reports as it lands, silence while it rests, a few as it peels off
    w.run(0.03, lambda i: touch_report(48, [(1, 5700, 3000), (2, 6400, 3300)]))
    w.run(3.0)
    check(w.state("top"), "a palm that went silent after landing is still covered 3 s later")
    w.run(0.03, lambda i: touch_report(48, [(1, 5700, 3000)]))
    w.feed(lift_report(48))
    w.run(0.4)
    check(w.state("top"), "...and its peel-off reports and lift are covered too (the hold runs from the lift)")
    w.run(0.4)
    check(not w.state("top"), "...then released 0.6 s after the lift")


def s_burst_palm(w):
    # bursts of full-rate frames separated by dropouts: judged at each burst's start
    for _ in range(6):
        w.run(0.25, lambda i: touch_report(48, [(1, 5700 + i % 30, 3000), (2, 6400, 3300)]))
        w.run(0.15)
    check(w.state("top"), "a palm that reports in bursts with dropouts between is caught")


def s_measured_session(w):
    # the shapes of a real dry run: 5 taps of 7-11 reports, then 3- and 5-finger swipes of 30-60
    # reports, every one ending with its lift report. None of it may switch anything off.
    for n in (9, 11, 10, 8, 7):
        for i in range(n):
            w.feed(touch_report(48, [(1, 5000 + i, 3000)]))
            w.step()
        w.feed(lift_report(48))
        w.run(0.6)
    for fingers, n in ((3, 30), (3, 42), (5, 55), (5, 61)):
        for i in range(n):
            w.feed(touch_report(48, [(k + 1, 2000 + k * 1500 + i * 20, 2000 + k * 300) for k in range(fingers)]))
            w.step()
        w.feed(lift_report(48))
        w.run(0.6)
    check(not w.calls, "taps and 3/5-finger swipes, each with its lift report, never switch the touchscreen off")


def s_pen_parse(w):
    check(palm.parse_pen(pen_report(20, True)) is True and palm.parse_pen(pen_report(40, False)) is False, "pen parse")
    check(palm.parse_pen(pen_report(48, True)) is None and palm.parse_touch(pen_report(20, True)) is None, "other ids ignored")
    check(palm.parse_touch(b"\x30\x00") is None, "a short report is ignored")


def s_two_panels(w):
    w.run(1, lambda i: [touch_report(48, [(1, 5700, 3000)])] * (i % 10 == 0) + [touch_report(56, [(1, 5000, 3000)])])
    check(w.state("top") and not w.state("bottom"), "a palm on one panel does not stop the other (a finger on the bottom works)")


def main():
    print("palm-sim")
    for name, fn in list(globals().items()):
        if name.startswith("s_"):
            scenario(fn.__name__[2:].replace("_", " "), fn)
    print("palm ok" if fails == 0 else f"palm: {fails} failed")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Yoga Book 9i hardware survey helper (Task 1, steps that need hands).

Standard library only. Run it on the Yoga itself.

  yoga-survey.py snapshot            one-shot dump of every signal we know about
  yoga-survey.py identify            dim each eDP panel in turn: which one is top?
  yoga-survey.py postures [name..]   record sensor readings per posture
  yoga-survey.py dock                watch for keyboard dock/undock signals
  sudo yoga-survey.py events [-t S] [-n NAME ..] [--live]
                                     mini evtest: needs root (or the input group)

Results go to ./survey-output/ next to this script (override with the
YOGA_SURVEY_OUT environment variable). Nothing here writes to the system
except `identify`, which briefly dims one backlight and restores it.
"""
import argparse
import glob
import math
import os
import re
import select
import statistics
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

OUT = Path(os.environ.get("YOGA_SURVEY_OUT", Path(__file__).resolve().parent / "survey-output"))
IIO = Path("/sys/bus/iio/devices")


def sh(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + r.stderr).strip()
    except Exception as e:  # noqa: BLE001
        return f"<{e}>"


def rd(path, default=None):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def stamp():
    return time.strftime("%H:%M:%S") + f".{int(time.time() * 1000) % 1000:03d}"


# ---------------------------------------------------------------- IIO sensors

def iio_map():
    """label -> sysfs dir. Labels: accel<N>, gyro<N>, hinge, als (N = HID sensor instance)."""
    out = {}
    for d in sorted(IIO.glob("iio:device*")):
        name = rd(d / "name", "?")
        inst = re.search(r"HID-SENSOR-[^.]+\.(\d+)\.auto", str(d.resolve()))
        n = inst.group(1) if inst else d.name
        if name == "accel_3d":
            out[f"accel{n}"] = d
        elif name == "gyro_3d":
            out[f"gyro{n}"] = d
        elif name == "hinge":
            out["hinge"] = d
        elif name == "als":
            out["als"] = d
    return out


def fnum(path):
    v = rd(path)
    try:
        return float(v)
    except (TypeError, ValueError):
        return float("nan")


def sample(m):
    """label -> list of floats. accel m/s^2, gyro rad/s, hinge degrees, als lux-ish."""
    s = {}
    for lab, d in m.items():
        if lab.startswith("accel"):
            sc = fnum(d / "in_accel_scale")
            s[lab] = [fnum(d / f"in_accel_{a}_raw") * sc for a in "xyz"]
        elif lab.startswith("gyro"):
            sc = fnum(d / "in_anglvel_scale")
            s[lab] = [fnum(d / f"in_anglvel_{a}_raw") * sc for a in "xyz"]
        elif lab == "hinge":
            # in_angl_scale is pi/180 and the values are degrees, so report raw
            s[lab] = [fnum(d / f"in_angl{i}_raw") for i in range(3)]
        elif lab == "als":
            s[lab] = [fnum(d / "in_illuminance_raw") * fnum(d / "in_illuminance_scale")]
    return s


def vec_angle(a, b):
    na, nb = math.dist(a, (0, 0, 0)), math.dist(b, (0, 0, 0))
    if not na or not nb:
        return float("nan")
    c = sum(x * y for x, y in zip(a, b)) / (na * nb)
    return math.degrees(math.acos(max(-1, min(1, c))))


def tilt_x(v):
    """Angle of gravity about the X axis (the hinge axis, by assumption), degrees."""
    return math.degrees(math.atan2(v[2], v[1]))


def collect(m, n=20, hz=10):
    rows = []
    for _ in range(n):
        rows.append(sample(m))
        time.sleep(1 / hz)
    mean = {k: [statistics.fmean(r[k][i] for r in rows) for i in range(len(rows[0][k]))] for k in rows[0]}
    sd = {k: [statistics.pstdev([r[k][i] for r in rows]) for i in range(len(rows[0][k]))] for k in rows[0]}
    return rows, mean, sd


# ------------------------------------------------------------------ snapshot

def input_names():
    names = []
    for blk in Path("/proc/bus/input/devices").read_text().split("\n\n"):
        mm = re.search(r'N: Name="(.*)"', blk)
        h = re.search(r"H: Handlers=(.*)", blk)
        if mm:
            names.append((mm.group(1), h.group(1).strip() if h else ""))
    return names


def dock_state():
    """Everything cheap that might change when the keyboard docks."""
    st = {}
    st["input devices"] = "\n".join(f"{n}  [{h}]" for n, h in input_names())
    st["emulated touchpad present"] = str(any("Emulated Touchpad" in n or "Touchpad" in n for n, _ in input_names() if "INGENIC" in n))
    st["yb9 module"] = sh("lsmod | grep -E 'yb9|ymc'") or "(not loaded)"
    st["keyboard_position"] = sh("cat /sys/bus/wmi/drivers/lenovo_yb9_kbdock/*/keyboard_position 2>&1 | head -3")
    st["usb 17ef:6161"] = sh("for i in /sys/bus/usb/devices/3-6:*; do echo $i $(cat $i/bInterfaceClass) $(basename $(readlink $i/driver) 2>/dev/null); done")
    st["hid report descriptor sizes"] = sh("for d in /sys/bus/hid/devices/0003:17EF:6161.*; do echo $(basename $d) $(wc -c < $d/report_descriptor) $(md5sum < $d/report_descriptor | cut -c1-8); done")
    ps = []
    for p in sorted(glob.glob("/sys/class/power_supply/*")):
        ps.append(f"{os.path.basename(p)}: status={rd(p + '/status')} online={rd(p + '/online')} cap={rd(p + '/capacity')}")
    st["power_supply"] = "\n".join(ps)
    st["acpi gpe/sci counters"] = sh("cd /sys/firmware/acpi/interrupts && grep -H . gpe* sci sci_not 2>/dev/null | awk -F'[: ]+' '$2!=0' | head -8")
    st["bluetooth"] = sh("rfkill list bluetooth | grep -i soft; bluetoothctl devices 2>&1 | head -5")
    st["sw bits (SW= lines)"] = sh("grep -B8 '^B: SW=' /proc/bus/input/devices | grep -E '^N:|^B: SW='")
    m = iio_map()
    s = sample(m)
    st["hinge deg (hinge,screen,keyboard)"] = str(s.get("hinge"))
    st["als"] = str(s.get("als"))
    for k in sorted(s):
        if k.startswith("accel"):
            st[k] = str([round(x, 2) for x in s[k]])
    return st


def cmd_snapshot(_a):
    OUT.mkdir(parents=True, exist_ok=True)
    f = OUT / f"snapshot-{time.strftime('%Y%m%d-%H%M%S')}.txt"
    lines = []
    for k, v in dock_state().items():
        lines.append(f"## {k}\n{v}\n")
    lines.append("## hyprctl monitors\n" + sh("hyprctl monitors all | grep -E '^Monitor|scale|transform'"))
    f.write_text("\n".join(lines))
    print("\n".join(lines))
    print(f"\n[written to {f}]")


# ------------------------------------------------------------------ identify

def cmd_identify(_a):
    """Dim each eDP panel's backlight for 3 s so you can say which is on top."""
    OUT.mkdir(parents=True, exist_ok=True)
    answers = []
    bls = {}
    for b in glob.glob("/sys/class/backlight/*"):
        bls[os.path.basename(b)] = os.path.basename(os.path.realpath(b + "/device"))
    print("Backlight -> connector:", bls)
    for dev, conn in sorted(bls.items(), key=lambda kv: kv[1]):
        input(f"\nPress Enter, then watch which screen goes DARK for 3 s ({dev} = {conn})... ")
        sh(f"brightnessctl -d {dev} -s set 1%")
        try:
            time.sleep(3)
        finally:
            sh(f"brightnessctl -d {dev} -r")
        a = input("Which screen was it (top/bottom)? ").strip()
        answers.append(f"{conn} ({dev}) = {a}")
    (OUT / "identify.txt").write_text("\n".join(answers) + "\n")
    print("\n".join(answers))
    print("Tell the agent (or edit hardware.md): which eDP is top.")


# ------------------------------------------------------------------- postures

POSTURES = {
    "laptop": "LAPTOP: bottom screen flat on a table, top screen open about 100-110 degrees (like a laptop). Keep it still.",
    "laptop-90": "LAPTOP-90: same, but top screen about 90 degrees (upright).",
    "flat": "FLAT: fully open 180 degrees, both screens facing up, lying flat on a table, hinge nearest you... then leave it.",
    "flat-rot90": "FLAT-ROT90: still flat at 180 degrees, but turn the whole device 90 degrees on the table (hinge on your left).",
    "tent": "TENT: stand it like a tent, hinge up (angle about 300), on a table, standing on its two long edges.",
    "tablet-bottom-up": "TABLET (bottom-up): fold fully back to 360 degrees, lying on a table with the BOTTOM screen facing up.",
    "tablet-top-up": "TABLET (top-up): fold fully back to 360 degrees, lying on a table with the TOP screen facing up.",
    "book": "BOOK: open to 180 degrees and hold it upright like a book you are reading, hinge vertical on the left of the screens.",
    "book-flipped": "BOOK-FLIPPED: as BOOK, but rotate it 180 degrees in your hands (hinge now on the right).",
    "closed": "CLOSED: close it completely and lay it flat (external monitors may take over; that is fine).",
}


def fmt(v, p=2):
    return "[" + ", ".join("nan" if math.isnan(x) else f"{x:.{p}f}" for x in v) + "]"


def cmd_postures(a):
    OUT.mkdir(parents=True, exist_ok=True)
    m = iio_map()
    print("Sensors:", {k: v.name for k, v in m.items()})
    names = a.names or list(POSTURES)
    txt = OUT / "postures.txt"
    csvf = OUT / "postures.csv"
    new = not csvf.exists()
    with txt.open("a") as t, csvf.open("a") as c:
        if new:
            c.write("time,posture,label,v0,v1,v2\n")
        t.write(f"\n=== run {time.strftime('%F %T')}  sensors={ {k: v.name for k, v in m.items()} }\n")
        for n in names:
            if n not in POSTURES:
                print("unknown posture", n, "(known:", ", ".join(POSTURES), ")")
                continue
            print("\n" + POSTURES[n])
            r = input("Hold it still, then press Enter (s = skip)... ").strip()
            if r.lower() == "s":
                continue
            time.sleep(0.5)
            rows, mean, sd = collect(m)
            lid = sh("cat /proc/acpi/button/lid/*/state")
            acc = sorted(k for k in mean if k.startswith("accel"))
            lines = [f"--- {n}   lid: {lid}"]
            for k in sorted(mean):
                lines.append(f"{k:9s} mean {fmt(mean[k])}  sd {fmt(sd[k], 3)}")
            if len(acc) == 2:
                lines.append(
                    f"angle between {acc[0]} and {acc[1]} gravity vectors: {vec_angle(mean[acc[0]], mean[acc[1]]):.1f} deg;"
                    f" tilt about X: {tilt_x(mean[acc[0]]):.1f} / {tilt_x(mean[acc[1]]):.1f} deg"
                )
            lines.append("your hinge-angle estimate (deg): " + (input("Your estimate of the hinge angle in degrees (Enter to skip)? ").strip() or "-"))
            for ln in lines:
                print(ln)
                t.write(ln + "\n")
            for r_ in rows:
                for k, v in r_.items():
                    c.write(f"{time.time():.3f},{n},{k}," + ",".join(f"{x:.6f}" for x in v) + "\n")
    print(f"\n[written to {txt} and {csvf}]")


# ----------------------------------------------------------------------- dock

class Watchers:
    def __init__(self):
        OUT.mkdir(parents=True, exist_ok=True)
        self.procs, self.files = [], []
        self.stop = threading.Event()

    def spawn(self, cmd, name):
        f = open(OUT / name, "a", buffering=1)
        self.files.append(f)
        self.procs.append(subprocess.Popen(cmd, shell=True, stdout=f, stderr=subprocess.STDOUT, text=True))

    def mark(self, msg):
        line = f"\n##### {stamp()} MARK {msg}\n"
        for f in self.files:
            f.write(line)

    def poll(self):
        f = open(OUT / "dock-poll.log", "a", buffering=1)
        self.files.append(f)
        last = {}
        while not self.stop.is_set():
            cur = dock_state()
            for k, v in cur.items():
                if k in last and last[k] != v:
                    f.write(f"{stamp()} CHANGED {k}\n  was: {last[k]}\n  now: {v}\n")
            last = cur
            self.stop.wait(0.3)

    def start(self):
        self.spawn("journalctl -k -f -n0 -o short-precise", "dock-kernel.log")
        self.spawn("udevadm monitor --kernel --udev --property", "dock-udev.log")
        if shutil_which("acpi_listen"):
            self.spawn("acpi_listen", "dock-acpi.log")
        self.th = threading.Thread(target=self.poll, daemon=True)
        self.th.start()

    def close(self):
        self.stop.set()
        for p in self.procs:
            p.terminate()
        for f in self.files:
            f.close()


def shutil_which(x):
    return any(os.access(os.path.join(p, x), os.X_OK) for p in os.environ.get("PATH", "").split(":"))


DOCK_STEPS = [
    ("detached-1", "Keyboard AWAY from the device (at least 30 cm), still powered/awake. Press Enter when ready."),
    ("docked-near-hinge", "Place the keyboard ON the bottom screen, as far toward the HINGE as it will sit (position A). Let it snap. Press Enter ~3 s after it snaps."),
    ("docked-front", "Slide it to the FRONT edge of the bottom screen (position B, leaving the upper strip of the screen uncovered). Press Enter ~3 s after it settles."),
    ("docked-near-hinge-2", "Slide it back to the hinge end (position A) once more. Press Enter after it settles."),
    ("lifted-off", "Lift the keyboard off completely (do not move the laptop). Press Enter ~3 s later."),
    ("docked-laptop-posture", "Put the Yoga in LAPTOP posture (top screen ~100 degrees, bottom flat), then dock the keyboard at position A. Press Enter after it settles."),
    ("detached-laptop-posture", "Same posture, lift the keyboard off. Press Enter after ~3 s."),
]


def cmd_dock(a):
    w = Watchers()
    w.start()
    states = {}
    try:
        print("Watchers running; logs in", OUT)
        print("TIP: in another terminal run `sudo", sys.argv[0], "events -t 600 --live -n INGENIC Lenovo` to catch raw input events.")
        for key, text in DOCK_STEPS:
            if a.only and key not in a.only:
                continue
            print("\n" + text)
            w.mark(f"before {key}")
            r = input("Enter (s = skip)... ").strip()
            if r.lower() == "s":
                continue
            w.mark(f"after {key}")
            time.sleep(1)
            states[key] = dock_state()
    finally:
        w.close()
    path = OUT / "dock-states.txt"
    prev = None
    with path.open("a") as f:
        f.write(f"\n=== run {time.strftime('%F %T')}\n")
        for key, st in states.items():
            f.write(f"\n--- {key}\n")
            for k, v in st.items():
                if prev is None or prev.get(k) != v:
                    f.write(f"[{k}]\n{v}\n")
            prev = st
    print(f"\n[state diffs in {path}; raw logs dock-kernel.log dock-udev.log dock-poll.log]")


# --------------------------------------------------------------------- events

EVT = struct.Struct("llHHi")
NAMES = {
    (3, 0x00): "ABS_X", (3, 0x01): "ABS_Y", (3, 0x18): "ABS_PRESSURE", (3, 0x1A): "ABS_TILT_X",
    (3, 0x1B): "ABS_TILT_Y", (3, 0x28): "ABS_MISC", (3, 0x2F): "ABS_MT_SLOT", (3, 0x35): "ABS_MT_POSITION_X",
    (3, 0x36): "ABS_MT_POSITION_Y", (3, 0x39): "ABS_MT_TRACKING_ID", (3, 0x3A): "ABS_MT_PRESSURE",
    (1, 0x110): "BTN_LEFT", (1, 0x111): "BTN_RIGHT", (1, 0x14A): "BTN_TOUCH", (1, 0x140): "BTN_TOOL_PEN",
    (1, 0x141): "BTN_TOOL_RUBBER", (1, 0x14B): "BTN_STYLUS", (1, 0x14C): "BTN_STYLUS2",
    (1, 0x145): "BTN_TOOL_FINGER", (1, 0x14D): "BTN_TOOL_DOUBLETAP", (1, 0x14E): "BTN_TOOL_TRIPLETAP",
    (5, 0x00): "SW_LID", (5, 0x01): "SW_TABLET_MODE", (4, 0x04): "MSC_SCAN", (4, 0x05): "MSC_TIMESTAMP",
}


def find_devices(parts):
    devs = []
    for blk in Path("/proc/bus/input/devices").read_text().split("\n\n"):
        mm = re.search(r'N: Name="(.*)"', blk)
        h = re.search(r"Handlers=.*?(event\d+)", blk)
        if mm and h and any(p.lower() in mm.group(1).lower() for p in parts):
            devs.append((mm.group(1), f"/dev/input/{h.group(1)}"))
    return devs


def cmd_events(a):
    devs = find_devices(a.name or ["INGENIC"])
    if a.switches:
        for blk in Path("/proc/bus/input/devices").read_text().split("\n\n"):
            if re.search(r"^B: SW=", blk, re.M):
                mm = re.search(r'N: Name="(.*)"', blk)
                h = re.search(r"Handlers=.*?(event\d+)", blk)
                if mm and h:
                    devs.append((mm.group(1), f"/dev/input/{h.group(1)}"))
    fds, stats, first = {}, {}, {}
    for name, path in devs:
        try:
            fds[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = name
        except OSError as e:
            print(f"cannot open {path} ({name}): {e}  -> run with sudo", file=sys.stderr)
    if not fds:
        sys.exit(1)
    print("listening on:", ", ".join(sorted(set(fds.values()))), f"for {a.t}s ... touch / draw / dock now")
    end = time.time() + a.t
    while time.time() < end:
        r, _, _ = select.select(list(fds), [], [], 0.2)
        for fd in r:
            try:
                data = os.read(fd, EVT.size * 64)
            except BlockingIOError:
                continue
            for off in range(0, len(data) - EVT.size + 1, EVT.size):
                _, _, t, c, v = EVT.unpack_from(data, off)
                if t == 0:
                    continue
                nm = fds[fd]
                first.setdefault(nm, time.time())
                s = stats.setdefault(nm, {}).setdefault((t, c), [0, v, v])
                s[0] += 1
                s[1], s[2] = min(s[1], v), max(s[2], v)
                if a.live:
                    print(f"{stamp()} {nm:50s} {NAMES.get((t, c), f'type{t}/code{c:#x}'):22s} {v}")
    print("\n=== summary (count, min, max) ===")
    for nm in sorted(stats, key=lambda n: first[n]):
        print(f"{nm}   (first event at +{first[nm] - (end - a.t):.2f}s)")
        for (t, c), (n, lo, hi) in sorted(stats[nm].items()):
            print(f"   {NAMES.get((t, c), f'type{t}/code{c:#x}'):22s} n={n:6d} min={lo} max={hi}")
    if not stats:
        print("no events seen")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("snapshot").set_defaults(f=cmd_snapshot)
    sub.add_parser("identify").set_defaults(f=cmd_identify)
    sp = sub.add_parser("postures")
    sp.add_argument("names", nargs="*", help="subset of: " + ", ".join(POSTURES))
    sp.set_defaults(f=cmd_postures)
    sd = sub.add_parser("dock")
    sd.add_argument("--only", nargs="*", help="step keys: " + ", ".join(k for k, _ in DOCK_STEPS))
    sd.set_defaults(f=cmd_dock)
    se = sub.add_parser("events")
    se.add_argument("-t", type=float, default=15, help="seconds to listen")
    se.add_argument("-n", "--name", nargs="*", help="device-name substrings (default INGENIC)")
    se.add_argument("--live", action="store_true", help="print every event")
    se.add_argument("--switches", action="store_true", help="also listen on every device with a SW_ bitmap")
    se.set_defaults(f=cmd_events)
    a = p.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()

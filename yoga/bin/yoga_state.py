#!/usr/bin/env python3
"""yoga_state: the ONE definition of the Yoga's effective state.

Imported by yoga-posture (the authority: it computes and publishes the state),
by yoga-touchpad and yoga-bottom-reserve (consumers), and run as a small command by
the shell scripts yoga-osk and yoga-osk-lockwatch:

  python3 -I yoga_state.py show            # the published state, and whether it is fresh
  python3 -I yoga_state.py get want.osk_allowed   # one value (bool -> 1/0); exit 3 if no fresh state
  python3 -I yoga_state.py osk-allowed     # exit 0: the on-screen keyboard may be shown; 1: refused (reason on stdout)
  python3 -I yoga_state.py keyboard        # exit 0 and the name when a USB keyboard is connected, else exit 1

Model and invariants: docs/yoga-book/state-machine.md. Nothing here touches the
session; the pure functions (DockTracker, Hold, derive) are what yoga/tests/state-sim.py drives.

Environment overrides (tests, other machines): YOGA_DOCK_FILE (the keyboard_position
file), YOGA_STATE_FILE (the published state), XDG_RUNTIME_DIR.
"""
import glob
import json
import os
import socket
import sys
import time
from pathlib import Path

# =============================================================================
# THE constants. Everything that times a dock or keyboard transition lives here.
# =============================================================================
# keyboard_position passes through 0 for ~1 s while the keyboard is slid between
# position 1 and 2 (and a detach reads 0 for good). A non-zero reading is believed at
# once; "detached" is believed only after 0 has been read this long.
DOCK_DEBOUNCE_S = 1.5
# ...but the keyboard is nearly always docked at position 1 (near the hinge) and taken off
# from there, so a 0 that follows position 1 is believed after this much shorter time: three
# consecutive 4 Hz reads of 0 (~0.5 s). The price is that a deliberate slide 1 -> 2 now shows
# as a brief undock (the on-screen keyboard may flash up) before 2 is read. A slide 2 -> 1,
# or a detach from 2, still gets the full DOCK_DEBOUNCE_S.
DOCK_DEBOUNCE_FROM_1_S = 0.4
# The on-screen keyboard's layer disappears for a moment when wvkbd is restarted (mode
# change) and the bars/workspaces must not bounce with it: "visible" is held this long
# after the layer was last seen.
OSK_HOLD_S = 1.0
# A published state older than this (or whose daemon is gone) is not believed; consumers
# then compute the same thing locally from the same functions (Consumer below).
STALE_S = 3.0
FALLBACK_MIN_S = 0.25   # a consumer computing the state itself samples sysfs/Hyprland at most this often

STATE_VERSION = 1
DEFAULT_PANELS = {"top": {"on": True, "transform": 0}, "bottom": {"on": True, "transform": 0}}


def runtime_dir():
    return Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")


def state_path():
    return Path(os.environ.get("YOGA_STATE_FILE") or runtime_dir() / "yoga" / "state.json")


def fold_guard_path():
    return runtime_dir() / "yoga" / "folded"


# =============================================================================
# Inputs
# =============================================================================
def dock_path():
    p = os.environ.get("YOGA_DOCK_FILE")
    if p:
        return p
    g = glob.glob("/sys/bus/wmi/devices/E7F300FA-*/keyboard_position")
    return g[0] if g else None


def read_dock_raw():
    """0 detached, 1 near the hinge, 2 at the front edge; None when unreadable."""
    p = dock_path()
    if not p:
        return None
    try:
        v = int(Path(p).read_text().split()[0])
    except (OSError, ValueError, IndexError):
        return None
    return v if v in (0, 1, 2) else None


def hypr_env():
    env = dict(os.environ)
    rt = runtime_dir() / "hypr"
    sig = env.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig and (rt / sig).is_dir():
        return env
    best = None
    for d in rt.glob("*/hyprland.lock"):
        try:
            os.kill(int(d.read_text().split()[0]), 0)
        except (OSError, ValueError, IndexError):
            continue
        t = d.stat().st_mtime
        if best is None or t > best[0]:
            best = (t, d.parent.name)
    if best:
        env["HYPRLAND_INSTANCE_SIGNATURE"] = best[1]
    return env


def hypr_json(what):
    """Query Hyprland's command socket directly (no hyprctl fork); None if unreachable."""
    sig = hypr_env().get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return None
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    try:
        s.connect(str(runtime_dir() / "hypr" / sig / ".socket.sock"))
        s.sendall(f"j/{what}".encode())
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        return json.loads(buf)
    except (OSError, ValueError):
        return None
    finally:
        s.close()


# A wired keyboard the user can type on without the on-screen one: any USB keyboard, but not
# the touch controller's own HID keyboard interface (17ef:6161, the same USB device as the
# touchscreens) and not virtual ones (keyd, ydotool, the daemons' uinput devices all sit
# under /devices/virtual/input/). Bluetooth keyboards do NOT count: the dock keyboard is one,
# it is already handled by the dock position (docked refuses the OSK, merely connected does
# not), and a connected Bluetooth keyboard off the dock should still allow the OSK. Read
# from /proc/bus/input/devices, so no root and no extra dependency. Opt out with the file
# ~/.config/yoga/osk-with-keyboard (the on-screen keyboard then ignores USB keyboards).
IGNORED_KBD_IDS = {"17ef:6161"}


def external_keyboard(devices_file="/proc/bus/input/devices"):
    """Name of a connected USB keyboard, or None."""
    cfg = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    if (cfg / "yoga" / "osk-with-keyboard").exists():
        return None
    try:
        text = Path(os.environ.get("YOGA_INPUT_DEVICES", devices_file)).read_text()
    except OSError:
        return None
    for block in text.strip().split("\n\n"):
        bus = vid = pid = name = sysfs = handlers = ev = ""
        for line in block.splitlines():
            if line.startswith("I:"):
                f = dict(kv.split("=", 1) for kv in line[3:].split() if "=" in kv)
                bus, vid, pid = f.get("Bus", ""), f.get("Vendor", ""), f.get("Product", "")
            elif line.startswith("N: Name="):
                name = line[8:].strip('"')
            elif line.startswith("S: Sysfs="):
                sysfs = line[9:]
            elif line.startswith("H: Handlers="):
                handlers = line[12:]
            elif line.startswith("B: EV="):
                ev = line[6:].strip()
        if bus != "0003" or "kbd" not in handlers.split():
            continue
        if f"{vid}:{pid}" in IGNORED_KBD_IDS or "/devices/virtual/input/" in sysfs:
            continue
        try:
            if not int(ev, 16) & (1 << 0x14):      # EV_REP: real keyboards autorepeat, media-key pads do not
                continue
        except ValueError:
            continue
        return name
    return None


def osk_visible():
    """True while wvkbd has a layer surface (it destroys it on hide). False when Hyprland
    cannot be asked."""
    d = hypr_json("layers")
    if not isinstance(d, dict):
        return False
    for mon in d.values():
        for items in mon.get("levels", {}).values():
            for it in items:
                if it.get("namespace") == "wvkbd":
                    return True
    return False


# =============================================================================
# The debounces
# =============================================================================
class DockTracker:
    """keyboard_position -> the effective dock position `eff`.

    Non-zero: believed at once. 0: believed only after DOCK_DEBOUNCE_S of 0 (a slide
    2 -> 0 -> 1 therefore reads as 2 -> 1 and never as "undocked"); when the position
    before the 0 was 1 only DOCK_DEBOUNCE_FROM_1_S (the usual undock, which must be quick,
    so a slide 1 -> 2 does show as a short undock). The first reading is believed at once. An unreadable file keeps the last reading (right after a resume the
    dock's WMI query fails for a while, and counting that as "detached" raised the on-screen
    keyboard over a docked keyboard); with no reading yet it counts as 0."""

    def __init__(self, debounce=None, initial=None):
        # an explicit `debounce` applies to both positions (tests, tools)
        self.debounce = DOCK_DEBOUNCE_S if debounce is None else debounce
        self.debounce_from_1 = DOCK_DEBOUNCE_FROM_1_S if debounce is None else debounce
        self.raw = None
        self.eff = initial
        self.zero_since = None

    def update(self, raw, now):
        if raw is None:
            raw = self.raw if self.raw is not None else 0
        self.raw = raw
        if self.raw != 0 or self.eff is None:
            self.eff, self.zero_since = self.raw, None
        else:
            if self.zero_since is None:
                self.zero_since = now
            wait = self.debounce_from_1 if self.eff == 1 else self.debounce
            if self.eff != 0 and now - self.zero_since >= wait:
                self.eff = 0
        return self.eff


class Hold:
    """Rising edge at once, falling edge after `hold` seconds of False."""

    def __init__(self, hold=None):
        self.hold = OSK_HOLD_S if hold is None else hold
        self.value = False
        self.last_true = None

    def update(self, raw, now):
        if raw:
            self.value, self.last_true = True, now
        elif self.value and (self.last_true is None or now - self.last_true >= self.hold):
            self.value = False
        return self.value


# =============================================================================
# The derived state: a pure function of the inputs
# =============================================================================
def screens_of(posture, panels):
    """"dual": both panels lit; "single": exactly one (tent, tablet); "none": lid closed."""
    if posture == "closed":
        return "none"
    n = sum(1 for p in ("top", "bottom") if panels[p]["on"])
    return {2: "dual", 1: "single"}.get(n, "none")


def derive(dock_eff, osk_held, posture, panels):
    """-> the decisions every consumer shares. dock_eff 0/1/2, osk_held bool (debounced
    visibility of the on-screen keyboard)."""
    screens = screens_of(posture, panels)
    dual = screens == "dual"
    docked = bool(dock_eff)
    b = panels["bottom"]
    return {
        "screens": screens,
        # the on-screen keyboard may be shown: never while the physical keyboard is docked
        "osk_allowed": (not docked) and screens != "none",
        # the bottom screen's workspaces live on the top screen
        "reserved": dual and (docked or bool(osk_held)),
        # the bottom screen's bar is hidden (the on-screen keyboard starts at its top edge)
        "bar_hidden": dual and bool(osk_held),
        # the virtual touchpad may grab the bottom screen at all (the strip is chosen by
        # yoga-touchpad: dock1/dock2 when docked, osk under the on-screen keyboard)
        "touchpad_ok": dual and b["on"] and b["transform"] == 0 and posture not in ("tablet", "tent"),
    }


# =============================================================================
# Publishing and reading the state
# =============================================================================
def write_json_atomic(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data, sort_keys=True))
    os.replace(tmp, path)


def pid_alive(pid):
    try:
        return pid > 0 and os.path.exists(f"/proc/{int(pid)}")
    except (TypeError, ValueError):
        return False


def read_state(path=None, now=None, stale_s=None):
    """-> the published state (dict) if it was written by a live daemon within STALE_S,
    else None."""
    now = time.monotonic() if now is None else now
    try:
        st = json.loads(Path(path or state_path()).read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(st, dict) or st.get("v") != STATE_VERSION:
        return None
    try:
        age = now - float(st["mono"])
    except (KeyError, TypeError, ValueError):
        return None
    if age > (STALE_S if stale_s is None else stale_s) or age < -1.0:
        return None
    if not pid_alive(st.get("pid")):
        return None
    st["age"] = age
    return st


def dig(d, dotted, default=None):
    for k in dotted.split("."):
        if not isinstance(d, dict) or k not in d:
            return default
        d = d[k]
    return d


class Consumer:
    """What a consumer sees: the daemon's state if there is a fresh one, otherwise the
    same state computed locally (sysfs + Hyprland) with the same trackers and `derive`.
    The posture is then assumed to be the plain laptop one, which is what yoga/hypr/yoga.lua
    does when the daemon is gone."""

    def __init__(self, osk_probe=None, state_file=None):
        self.osk_probe = osk_probe or osk_visible
        self.state_file = state_file
        self.dock = DockTracker()
        self.hold = Hold()
        self.last = None
        self.source = "none"
        self.fb_at = -1e9

    def get(self, now=None):
        now = time.monotonic() if now is None else now
        st = read_state(self.state_file, now)
        if st is not None:
            self.source = "daemon"
            # keep the local trackers where the daemon is, so a failover does not jump
            self.dock.eff, self.dock.raw, self.dock.zero_since = st["dock"]["eff"], st["dock"]["raw"], None
            self.hold.value = bool(dig(st, "osk.held"))
            self.hold.last_true = now if self.hold.value else None
            self.last = st
            return st
        if self.source == "fallback" and self.last is not None and now - self.fb_at < FALLBACK_MIN_S:
            return self.last        # Hyprland is asked at most this often
        self.fb_at = now
        raw = read_dock_raw()
        self.dock.update(raw, now)
        vis = bool(self.osk_probe())
        held = self.hold.update(vis, now)
        panels = json.loads(json.dumps(DEFAULT_PANELS))
        want = derive(self.dock.eff, held, "laptop", panels)
        self.source = "fallback"
        self.last = {"v": STATE_VERSION, "source": "fallback", "pid": None, "dock": {"raw": raw, "eff": self.dock.eff},
                     "posture": "laptop", "panels": panels, "screens": want["screens"],
                     "osk": {"visible": vis, "held": held}, "want": want, "age": None}
        return self.last


# =============================================================================
# Command line (for the shell scripts)
# =============================================================================
def _fmt(v):
    if isinstance(v, bool):
        return "1" if v else "0"
    if v is None:
        return ""
    return str(v)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "show"
    if cmd == "show":
        st = read_state()
        if st is None:
            print(f"no fresh state at {state_path()} (daemon not running or stalled)")
            return 3
        print(json.dumps(st, indent=2, sort_keys=True))
        return 0
    if cmd == "get" and len(argv) > 2:
        st = read_state()
        if st is None:
            return 3
        v = dig(st, argv[2])
        print(_fmt(v) if not isinstance(v, (dict, list)) else json.dumps(v))
        return 0
    if cmd == "osk-allowed":
        # fresh state: its decision. Otherwise the plain rule on the raw dock file.
        st = read_state()
        if st is not None:
            ok = bool(dig(st, "want.osk_allowed"))
            if not ok:
                print("the keyboard is docked" if dig(st, "dock.eff") else "no screen is lit")
                return 1
        elif read_dock_raw():
            print("the keyboard is docked")
            return 1
        kb = external_keyboard()
        if kb:
            print(f"a USB keyboard is connected: {kb}")
            return 1
        return 0
    if cmd == "keyboard":
        kb = external_keyboard()
        if kb:
            print(kb)
        return 0 if kb else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

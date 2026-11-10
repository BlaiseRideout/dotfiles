#!/usr/bin/env python3
"""state-sim: replay the Yoga's keyboard / on-screen keyboard / posture interactions against a
FAKE world and assert the invariants of docs/yoga-book/state-machine.md.

Nothing here touches the real session: a temporary XDG_RUNTIME_DIR and HOME, the dock sysfs file
replaced by a temp file (YOGA_DOCK_FILE), hyprctl / wvkbd / pgrep / notify-send / noctalia
replaced by stubs first in PATH, uinput, systemd-inhibit and the real Hyprland socket never
opened. It does not grab a touchscreen (yoga-touchpad runs with dry=True).

  python3 yoga/tests/state-sim.py            # everything
  python3 yoga/tests/state-sim.py -k slide   # scenarios whose name contains "slide"
  python3 yoga/tests/state-sim.py -v         # also print each scenario's event log

Part 1 (virtual clock): the real yoga_state, yoga-posture Daemon, yoga-touchpad Daemon and
yoga-bottom-reserve Watcher, driven tick by tick at their real cadences, with a world model for
the compositor and the on-screen keyboard. The invariants are checked after every tick.
Part 2 (real time, ~15 s): the real bash scripts yoga-osk and yoga-osk-lockwatch against stubs.
Part 3: yoga/hypr/yoga.lua against a stub `hl` (yoga/tests/yoga-lua-test.lua): the fold guard of the
lid switch, and "reserved only with both panels lit".
"""
import argparse
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import threading
import time

ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", ".."))
BIN = os.environ.get("YOGA_SIM_BIN") or os.path.join(ROOT, "yoga", "bin")   # (a mutated copy, to see the tests fail)
CSV = os.path.join(ROOT, "docs", "yoga-book", "survey-output", "postures.csv")

# ---- isolated environment, before anything is imported ------------------------------------------
TMP = tempfile.mkdtemp(prefix="yoga-sim-")
RUN = os.path.join(TMP, "run")
os.makedirs(RUN)
os.environ.update({
    "XDG_RUNTIME_DIR": RUN, "HOME": os.path.join(TMP, "home"), "XDG_CONFIG_HOME": os.path.join(TMP, "config"),
    "YOGA_DOCK_FILE": os.path.join(TMP, "keyboard_position"), "YOGA_STATE_FILE": os.path.join(RUN, "yoga", "state.json"),
    "YOGA_TOUCHPAD_CONFIG": os.path.join(TMP, "none.toml"),
    # no connected Bluetooth/USB keyboard unless a test writes one (else this machine's own would refuse the OSK)
    "YOGA_INPUT_DEVICES": os.path.join(TMP, "input-devices"),
})
open(os.environ["YOGA_INPUT_DEVICES"], "w").close()
os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
sys.path.insert(0, BIN)
import yoga_state   # noqa: E402

REAL = {"monotonic": time.monotonic, "sleep": time.sleep, "time": time.time}


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    loader.exec_module(mod)
    return mod


posture = load("yoga_posture_mod", os.path.join(BIN, "yoga-posture"))
touchpad = load("yoga_touchpad_mod", os.path.join(BIN, "yoga-touchpad"))
reserve = load("yoga_reserve_mod", os.path.join(BIN, "yoga-bottom-reserve"))
for m in (posture, touchpad, reserve):
    m.log = lambda *a, **k: None          # the scenarios print what matters themselves


class Failures(list):
    pass


FAILS = Failures()
CHECKS = [0]


def check(cond, msg):
    CHECKS[0] += 1
    if not cond:
        FAILS.append(msg)
        print(f"    FAIL: {msg}")
    return cond


# =============================================================================================
# Part 1: virtual clock + world
# =============================================================================================
class Clock:
    t = 1000.0


clock = Clock()


class FakeSensors:
    """What Sensors would return: one fixed (top, bottom) pair, set by the scenario."""
    frozen = (False, False)

    def __init__(self, sim):
        self.sim = sim
        self.dirs = True

    def read(self):
        return None if self.sim.sensors_dead else self.sim.vec

    def discover(self):
        return True

    def describe(self):
        return "fake"


class World:
    """The compositor, the on-screen keyboard and what the consumers did to them."""

    def __init__(self, sim):
        self.sim = sim
        self.osk = False
        self.osk_mode = None
        self.mods = False              # a latched modifier on the (emulated) virtual keyboard
        self.reserved = False          # Lua: yoga_bottom_reserved
        self.bar_hidden = False
        self.dock_hidden = False
        self.layout = {"top": True, "bottom": True, "posture": "laptop"}
        self.suspended = False
        self.events = []
        self.violations = []
        self.user_shows = 0
        self.shows = 0

    def log(self, ev):
        self.events.append((round(clock.t - self.sim.t0, 2), ev))

    def dual(self):
        return self.layout["top"] and self.layout["bottom"]

    # -- what the scripts call -------------------------------------------------------------
    def hide_osk(self):
        was = self.osk
        if was:
            self.osk = False
            self.mods = False               # the patched wvkbd releases on hide
            self.log("osk-hide")
        return was

    def user_show(self):
        """yoga-osk show: refused while not allowed (the state, else the raw dock file)."""
        self.user_shows += 1
        st = yoga_state.read_state()
        if st is not None:
            ok = bool(st["want"]["osk_allowed"])
            screens = st["screens"]
        else:
            ok = not yoga_state.read_dock_raw()
            screens = "dual" if self.dual() else "single"
        if not ok:
            self.log("osk-show-refused")
            return False
        self.shows += 1
        self.osk = True
        self.osk_mode = "float" if screens == "single" else "dock"
        self.log(f"osk-show({self.osk_mode})")
        return True

    def tap_shift(self):
        if self.osk:
            self.mods = True

    def apply_layout(self, code):
        m = re.search(r'posture = "(\w+)".*top = \{ on = (\w+).*bottom = \{ on = (\w+)', code)
        post, top, bottom = m.group(1), m.group(2) == "true", m.group(3) == "true"
        if self.osk:
            self.violations.append(f"t={clock.t - self.sim.t0:.2f}: layout {post} applied under a visible on-screen keyboard")
        if (not (top and bottom)) and self.reserved:
            self.reserved = False           # yoga_set_posture releases first (yoga.lua)
            self.log("reserved->False (lua, before the panel goes off)")
        self.layout = {"top": top, "bottom": bottom, "posture": post}
        self.log(f"layout:{post}")
        return True, "ok"

    def repl(self, code, dry=False, timeout=8):
        if "yoga_panel_outputs" in code:
            return True, "eDP-1,eDP-2"
        return self.apply_layout(code)

    def set_reserved(self, on):
        if on == self.reserved:
            return "unchanged"
        if not self.dual():
            return "both panels are not on"
        self.reserved = on
        self.log(f"reserved->{on}")
        return "reserved" if on else "released"

    def set_bar(self, hidden):
        if hidden != self.bar_hidden:
            self.bar_hidden = hidden
            self.log(f"bar-{'hide' if hidden else 'show'}")
        return True

    def set_dock(self, hidden):
        if hidden != self.dock_hidden:
            self.dock_hidden = hidden
            self.log(f"dock-{'hide' if hidden else 'show'}")
        return True

    def reload(self):
        self.log("hyprland-reload")
        self.reserved = False
        self.bar_hidden = False
        self.sim.events.pending = True
        self.sim.grace_until = clock.t + (1.2 if self.sim.reserve_events else 10.5)


class FakeEvents:
    pending = False

    def poll(self, timeout):
        hit, self.pending = self.pending, False
        return hit

    def connect(self, now):
        pass


class Sim:
    def __init__(self, name, dock=0, post="laptop", reserve_events=True):
        self.name = name
        self.t0 = clock.t
        self.vec = SAMPLES[post]
        self.lid = False
        self.sensors_dead = False
        self.dock_ref = DockRef()
        self.osk_ref = HoldRef()
        self.world = World(self)
        self.events = FakeEvents()
        self.reserve_events = reserve_events
        self.set_dock(dock)
        # patch the outside world
        yoga_state.osk_visible = lambda: self.world.osk
        posture.lid_closed = lambda: self.lid
        posture.hypr_repl = self.world.repl
        reserve.apply_reserved = self.world.set_reserved
        reserve.apply_bar = self.world.set_bar
        reserve.apply_dock = self.world.set_dock
        reserve.apply_notifs = lambda hidden: True
        reserve.hide_osk = self.world.hide_osk
        touchpad.source_info = self._no_device
        self.start_daemon()
        self.td = touchpad.Daemon(touchpad.load_config(), dry=True)
        self.watch = reserve.Watcher(consumer=yoga_state.Consumer(osk_probe=lambda: self.world.osk), events=self.events)
        self.next_t = clock.t
        self.next_td = self.next_rs = clock.t
        self.osk_visible_since_docked = None
        self.grace_until = 0.0

    @staticmethod
    def _no_device(path):
        raise OSError("sim: no touchscreen")

    # -- the daemon under test -----------------------------------------------------------------
    def start_daemon(self):
        try:
            os.unlink(os.environ["YOGA_STATE_FILE"])
        except OSError:
            pass
        d = posture.Daemon(dry=True, switch=False, osk=True)
        d.sensors = FakeSensors(self)
        d.osk.hide_sync = lambda wait=0.8: self.world.hide_osk()
        d.osk.hide = lambda: self.world.hide_osk()
        self.daemon = d
        self.daemon_up = True
        self.next_t = clock.t
        self.daemon.next_fast = 0.0

    def stop_daemon(self):
        self.daemon.unpublish()
        self.daemon_up = False

    # -- inputs ----------------------------------------------------------------------------------
    def set_dock(self, v):
        with open(os.environ["YOGA_DOCK_FILE"], "w") as f:
            f.write(f"{v}\n")
        self.dock_ref.set(v, clock.t)
        self.mark()

    def set_posture(self, name):
        self.vec = SAMPLES[name]
        self.mark()

    def mark(self):
        self.last_input = clock.t

    # -- time ------------------------------------------------------------------------------------
    def run(self, seconds, dt=0.05):
        end = clock.t + seconds
        while clock.t < end - 1e-9:
            clock.t += dt
            now = clock.t
            if self.daemon_up:
                if now >= self.next_t:
                    self.daemon.step(now)
                    if self.daemon.want is not None and self.daemon.want != self.daemon.applied:
                        self.daemon.try_apply(now, self.daemon.committed[0], self.daemon.committed[0], self.daemon.committed)
                    self.next_t = now + 0.4
                if now >= self.daemon.next_fast:
                    self.daemon.next_fast = now + posture.FAST_PERIOD_S
                    self.daemon.fast(now)
            if now >= self.next_td:
                self.next_td = now + 0.2
                self.td.poll_inputs(now)
                self.td.apply(now)
            if now >= self.next_rs:
                self.next_rs = now + reserve.TICK_S
                self.watch.tick(now, reassert=self.events.poll(0))
            self.invariants(now)

    # -- invariants ------------------------------------------------------------------------------
    def invariants(self, now):
        w, dr = self.world, self.dock_ref
        eff = dr.eff(now)
        held = self.osk_ref.update(w.osk, now)
        # N1 no on-screen keyboard while docked, beyond the time to put it away
        if eff and w.osk:
            self.osk_visible_since_docked = self.osk_visible_since_docked or now
            if now - self.osk_visible_since_docked > 0.8:
                w.violations.append(f"t={now - self.t0:.2f}: on-screen keyboard visible {now - self.osk_visible_since_docked:.1f} s while docked")
        else:
            self.osk_visible_since_docked = None
        # N2 no modifier latched while hidden
        if w.mods and not w.osk:
            w.violations.append(f"t={now - self.t0:.2f}: modifier latched with the on-screen keyboard hidden")
        # settled invariants (inputs unchanged for a while)
        if now - self.last_input > 2.5 and now - self.osk_ref.changed_at > 2.5 and now > self.grace_until:
            dual = w.dual()
            posture_now = w.layout["posture"]
            want_res = dual and (bool(eff) or held)
            if self.daemon_up or True:
                if w.reserved != want_res:
                    w.violations.append(f"t={now - self.t0:.2f}: reserved={w.reserved}, expected {want_res} (dual {dual}, dock_eff {eff}, osk held {held})")
                if w.bar_hidden != (dual and held):
                    w.violations.append(f"t={now - self.t0:.2f}: bar_hidden={w.bar_hidden}, expected {dual and held}")
                if w.dock_hidden != want_res:
                    w.violations.append(f"t={now - self.t0:.2f}: dock_hidden={w.dock_hidden}, expected {want_res} (it follows the reservation)")
                tp_ok = (dual and w.layout["bottom"] and posture_now not in ("tablet", "tent", "book"))
                want_tp = tp_ok and (eff in (1, 2) or (eff == 0 and held))
                if bool(self.td.active) != bool(want_tp):
                    w.violations.append(f"t={now - self.t0:.2f}: touchpad active={bool(self.td.active)}, expected {bool(want_tp)} "
                                        f"(dock_eff {eff}, osk {held}, layout {posture_now})")
                if self.td.active and eff in (1, 2) and self.td.active.key != f"dock{eff}":
                    w.violations.append(f"t={now - self.t0:.2f}: strip {self.td.active.key} with the keyboard at {eff}")
                if self.td.active and eff == 0 and self.td.active.key != "osk":
                    w.violations.append(f"t={now - self.t0:.2f}: strip {self.td.active.key} while undocked")
        if w.suspended:
            w.violations.append(f"t={now - self.t0:.2f}: SUSPENDED")

    def events_between(self, a, b=None):
        return [e for t, e in self.world.events if t >= a and (b is None or t <= b)]

    def now(self):
        return round(clock.t - self.t0, 2)


class DockRef:
    """The reference model of the debounce, written independently of yoga_state.DockTracker."""

    def __init__(self):
        self.raw = None
        self.eff_v = None
        self.zero_at = None

    def set(self, v, t):
        self.raw = v
        if v != 0:
            self.eff_v, self.zero_at = v, None
        elif self.zero_at is None:
            self.zero_at = t
            if self.eff_v is None:
                self.eff_v = 0

    def eff(self, now):
        if self.raw == 0 and self.eff_v and self.zero_at is not None and now - self.zero_at >= (0.4 if self.eff_v == 1 else 1.5):
            self.eff_v = 0
        return self.eff_v or 0


class HoldRef:
    def __init__(self):
        self.val = False
        self.last = None
        self.changed_at = -99.0

    def update(self, vis, now):
        old = self.val
        if vis:
            self.val, self.last = True, now
        elif self.val and now - self.last >= 1.0:
            self.val = False
        if self.val != old:
            self.changed_at = now
        if vis != getattr(self, "_v", None):
            self._v = vis
            self.changed_at = now
        return self.val


# survey samples -> one (top, bottom) pair per posture
_sec, _lids = posture.load_survey(CSV)
SAMPLES = {k: (v[0][1], v[0][2]) for k, v in _sec.items()}
SAMPLES["tablet"] = SAMPLES["tablet-bottom-up"]
SAMPLES["tablet-top"] = SAMPLES["tablet-top-up"]


# =============================================================================================
# the scenarios
# =============================================================================================
SCENARIOS = []


def scenario(f):
    SCENARIOS.append(f)
    return f


def finish(sim):
    seen = {}
    for v in sim.world.violations:
        key = re.sub(r"t=[0-9.]+: |[0-9.]+ s while", "", v)
        seen.setdefault(key, [v, 0])[1] += 1
    for v, n in seen.values():
        check(False, f"{sim.name}: {v}" + (f"  (x{n} ticks)" if n > 1 else ""))
    CHECKS[0] += 1
    sim.world.violations.clear()


@scenario
def dock_undock_osk_hidden():
    """Dock and undock with the on-screen keyboard hidden."""
    s = Sim("dock_undock_osk_hidden")
    s.run(3)
    check(not s.td.active and not s.world.reserved, "nothing active at rest")
    s.set_dock(1)
    s.run(1.0)
    check(s.td.active and s.td.active.key == "dock1", "touchpad on with the dock1 strip within 1 s of docking")
    check(s.world.reserved, "bottom workspaces reserved while docked")
    check(not s.world.bar_hidden, "the bar is not hidden by a docked keyboard (no on-screen keyboard)")
    s.run(5)
    s.set_dock(0)
    s.run(0.2)
    check(s.td.active and s.world.reserved, "still docked 0.2 s after position 1 reads 0")
    s.run(0.8)
    check(not s.td.active and not s.world.reserved, "released within 1 s of 0 after position 1 (debounce 0.4 s)")
    finish(s)
    return s


@scenario
def dock_with_osk_dock_mode():
    """Dock with the on-screen keyboard shown (dock mode): hide first, no bounce of reserved or bar."""
    s = Sim("dock_with_osk_dock_mode")
    s.run(2)
    s.world.user_show()
    s.world.tap_shift()                      # a latched Shift, the bug that killed the gestures
    s.run(3)
    check(s.td.active and s.td.active.key == "osk" and s.world.reserved and s.world.bar_hidden,
          "undocked + keyboard up: osk strip, reserved, bar hidden")
    n0 = len(s.world.events)
    t_dock = s.now()
    s.set_dock(1)
    s.run(4)
    ev = [e for _, e in s.world.events[n0:]]
    check(ev[:1] == ["osk-hide"], f"the first thing on docking is hiding the on-screen keyboard (got {ev})")
    check("reserved->False" not in ev and "reserved->True" not in ev, f"reserved workspaces do not bounce (events {ev})")
    check(ev.count("bar-show") == 1 and "bar-hide" not in ev, f"the bar comes back once and does not flap ({ev})")
    check(s.td.active and s.td.active.key == "dock1", "touchpad switched from the osk strip to dock1")
    check(not s.world.osk and not s.world.mods, "keyboard hidden and no modifier latched")
    hides = [t for t, e in s.world.events if e == "osk-hide"]
    check(hides and hides[0] - t_dock <= 0.6, f"hidden within 0.6 s of the dock ({hides})")
    s.world.user_show()
    s.run(1)
    check(not s.world.osk, "show is refused while docked")
    finish(s)
    return s


@scenario
def dock_with_osk_float_mode():
    """Tablet posture, floating on-screen keyboard, then the keyboard docks."""
    s = Sim("dock_with_osk_float_mode", post="tablet")
    s.run(3)
    check(s.world.layout["posture"] == "tablet" and not s.world.dual(), "tablet: one panel lit")
    s.world.user_show()
    check(s.world.osk_mode == "float", "single screen: floating mode")
    s.run(2)
    check(not s.world.reserved and not s.world.bar_hidden and not s.td.active, "single screen: nothing reserved, no strip")
    s.set_dock(2)
    s.run(2)
    check(not s.world.osk, "docking hides the floating keyboard too")
    check(not s.world.reserved and not s.td.active, "docked in a tablet posture: still single screen, nothing reserved")
    finish(s)
    return s


@scenario
def slide_2_0_1():
    """Sliding the keyboard from position 2 to 1 passes through 0 for about a second: the full debounce holds."""
    s = Sim("slide_2_0_1", dock=2)
    s.run(3)
    check(s.td.active and s.td.active.key == "dock2", "dock2 strip")
    n0 = len(s.world.events)
    s.set_dock(0)
    s.run(1.0)
    s.world.user_show()                      # someone taps the OSK button in the gap
    s.set_dock(1)
    s.run(4)
    ev = [e for _, e in s.world.events[n0:]]
    check(s.td.active and s.td.active.key == "dock1", "strip changed dock2 -> dock1 without going off")
    check("osk-show-refused" in ev and not s.world.osk, f"the on-screen keyboard cannot appear in the gap ({ev})")
    check("reserved->False" not in ev, f"no reserve bounce in the slide ({ev})")
    check(s.daemon.dock.eff == 1, "effective dock never read 0")
    finish(s)
    return s


@scenario
def slide_1_0_2():
    """Sliding from 1 to 2 is the trade for a quick undock: it shows as a short undock, then settles on 2."""
    s = Sim("slide_1_0_2", dock=1)
    s.run(3)
    s.set_dock(0)
    s.run(1.0)
    s.set_dock(2)
    s.run(4)
    check(s.daemon.dock.eff == 2, "settles on position 2")
    check(s.td.active and s.td.active.key == "dock2", "strip ends on dock2")
    check(not s.world.osk and s.world.reserved, "no on-screen keyboard left over, bottom screen reserved")
    finish(s)
    return s


@scenario
def slide_slow():
    """A slide whose 0 lasts longer than the debounce counts as undock + dock."""
    s = Sim("slide_slow", dock=1)
    s.run(3)
    s.set_dock(0)
    s.run(2.0)
    check(s.daemon.dock.eff == 0, "0 for 2 s is believed")
    s.world.user_show()
    check(s.world.osk, "the keyboard may be shown once it is believed detached")
    s.run(2)
    s.set_dock(2)
    s.run(2)
    check(not s.world.osk and s.td.active and s.td.active.key == "dock2", "re-dock hides it and switches to dock2")
    finish(s)
    return s


@scenario
def posture_changes_with_osk():
    """Posture changes with the on-screen keyboard up: hidden first, never raised by the change."""
    s = Sim("posture_changes_with_osk")
    s.run(3)
    shows = s.world.shows
    s.world.user_show()
    s.run(3)
    n0 = len(s.world.events)
    s.set_posture("tent")
    s.run(4)
    ev = [e for _, e in s.world.events[n0:]]
    check(ev and ev[0] == "osk-hide" and "layout:tent" in ev and ev.index("osk-hide") < ev.index("layout:tent"),
          f"laptop -> tent hides the keyboard before the panels change ({ev})")
    check(not s.world.osk and s.world.shows == shows + 1, "not raised by the posture change")
    check(not s.world.reserved and not s.world.bar_hidden and not s.td.active, "tent: nothing reserved, no bar hidden, no strip")
    s.world.user_show()
    check(s.world.osk_mode == "float", "in a tent the keyboard floats")
    s.run(2)
    n0 = len(s.world.events)
    s.set_posture("laptop")
    s.run(4)
    ev = [e for _, e in s.world.events[n0:]]
    check(ev[:1] == ["osk-hide"] and not s.world.osk, f"tent -> laptop hides the floating keyboard first ({ev})")
    s.world.user_show()
    check(s.world.osk_mode == "dock", "back to two screens: dock mode")
    s.run(3)
    check(s.td.active and s.td.active.key == "osk" and s.world.reserved and s.world.bar_hidden, "two-screen osk state restored")
    finish(s)
    return s


@scenario
def posture_changes_docked():
    """Docked: laptop -> tablet -> laptop; reserved only with both panels, touchpad only upright."""
    s = Sim("posture_changes_docked", dock=1)
    s.run(3)
    check(s.world.reserved and s.td.active, "docked laptop: reserved + strip")
    s.set_posture("tablet")
    s.run(4)
    check(not s.world.reserved and not s.td.active, "tablet: released before the bottom panel went off, no strip")
    ev = [e for _, e in s.world.events]
    i, j = ev.index("reserved->False (lua, before the panel goes off)"), ev.index("layout:tablet")
    check(i < j, "released first (in yoga_set_posture), then the layout changed")
    s.set_posture("laptop")
    s.run(4)
    check(s.world.reserved and s.td.active and s.td.active.key == "dock1", "laptop again: reserved + strip back")
    s.set_posture("book")
    s.run(4)
    check(not s.td.active, "book mode: the bottom panel is rotated, no strip")
    s.set_posture("laptop")
    s.run(4)
    finish(s)
    return s


@scenario
def lid_closed_and_fold_glitch():
    """A real close commits `closed`; the lid sensor tripping in the fold never does."""
    s = Sim("lid_closed_and_fold_glitch", post="tent")
    s.run(3)
    check(s.daemon.committed[0] == "tent", "tent")
    s.lid = True                              # the false trip in the stand
    s.run(4)
    check(s.daemon.committed[0] == "tent" and s.daemon.last.opening >= posture.LID_GLITCH_ABOVE,
          f"a lid 'closed' in the tent does not close anything (posture {s.daemon.committed[0]})")
    s2 = Sim("lid_real_close", post="laptop")
    s2.run(3)
    s2.lid = True
    s2.set_posture("closed")
    s2.run(3)
    st = yoga_state.read_state()
    check(st and st["posture"] == "closed" and st["screens"] == "none" and not st["want"]["osk_allowed"],
          "a real close: screens none, on-screen keyboard not allowed")
    finish(s)
    finish(s2)
    return s


@scenario
def fold_guard_file():
    """The fold guard file (read by yoga.lua) names a live pid, and goes away."""
    d = posture.Daemon(dry=True, switch=False, osk=False)
    p = yoga_state.fold_guard_path()
    d.set_fold_guard(True)
    check(p.exists() and int(p.read_text()) == os.getpid(), "guard written with our pid")
    d.set_fold_guard(False)
    check(not p.exists(), "guard removed")


@scenario
def sensors_frozen_and_dead():
    """A frozen accelerometer falls back to the live half; unreadable sensors do not stop the dock logic."""
    s = Sim("sensors_frozen_and_dead", post="laptop")
    s.run(3)
    FakeSensors.frozen = (True, False)
    s.run(2)
    st = yoga_state.read_state()
    check(st and st["sensors"] == "frozen-top" and st["posture"] in ("laptop", "flat"), f"frozen top: {st and (st['sensors'], st['posture'])}")
    FakeSensors.frozen = (False, False)
    s.sensors_dead = True
    s.run(2)
    s.world.user_show()
    s.run(2)
    s.set_dock(1)
    s.run(3)
    st = yoga_state.read_state()
    check(st and st["sensors"] == "unreadable", "sensors unreadable is published")
    check(not s.world.osk and s.td.active and s.td.active.key == "dock1" and s.world.reserved,
          "with the sensors dead the dock still hides the keyboard and drives the touchpad and the reserve")
    s.sensors_dead = False
    s.run(2)
    finish(s)
    return s


@scenario
def daemon_restart():
    """The posture daemon restarts while docked with the keyboard up (a show raced the dock)."""
    s = Sim("daemon_restart", dock=1)
    s.run(3)
    n0 = len(s.world.events)
    s.stop_daemon()
    s.run(5)                                  # consumers fall back to computing the state themselves
    check(s.watch.c.source == "fallback" and s.td.consumer.source == "fallback", "consumers use their fallback")
    check(s.world.reserved and s.td.active and s.td.active.key == "dock1", "same outcome without the daemon")
    s.world.osk = True                       # force a visible keyboard under the dock (the invariant breaks)
    s.run(1.0)
    check(not s.world.osk, "the fallback reserve watcher puts it away")
    s.start_daemon()
    s.run(3)
    check(s.watch.c.source == "daemon" and s.td.consumer.source == "daemon", "back on the daemon's state")
    ev = [e for _, e in s.world.events[n0:]]
    check("reserved->False" not in ev, f"reserved did not bounce across the restart ({ev})")
    finish(s)
    return s


@scenario
def hyprland_reload():
    """A config reload resets the Lua side; the reserve and the bar are asserted again."""
    s = Sim("hyprland_reload")
    s.run(2)
    s.world.user_show()
    s.run(3)
    check(s.world.reserved and s.world.bar_hidden, "up")
    s.world.reload()
    s.run(1.0)
    check(s.world.reserved and s.world.bar_hidden, "re-asserted within 1 s of the reload event")
    s.reserve_events = False
    s.world.reload()
    s.events.pending = False                  # a reload whose event was missed
    s.run(11)
    check(s.world.reserved and s.world.bar_hidden, "re-asserted by the 10 s timer without the event")
    s.world.hide_osk()
    s.run(3)
    finish(s)
    return s


@scenario
def resume_from_suspend():
    """Resume: the keyboard was undocked while asleep, the sensors come back late."""
    s = Sim("resume_from_suspend", dock=1)
    s.run(3)
    s.set_dock(0)                             # undocked during the sleep: the first reading after resume
    s.sensors_dead = True
    s.run(2.0)
    s.sensors_dead = False
    s.run(2)
    check(s.daemon.dock.eff == 0 and not s.world.reserved and not s.td.active, "released after the debounce")
    st = yoga_state.read_state()
    check(st is not None, "state fresh after resume (ages use the monotonic clock, which does not run in sleep)")
    finish(s)
    return s


@scenario
def osk_restart_flicker():
    """The keyboard's layer vanishes for under a second (wvkbd restarted in another mode): no bar or reserve bounce."""
    s = Sim("osk_restart_flicker")
    s.run(2)
    s.world.user_show()
    s.run(3)
    n0 = len(s.world.events)
    s.world.osk = False
    s.run(0.6)
    s.world.osk = True
    s.run(3)
    ev = [e for _, e in s.world.events[n0:]]
    check(not ev, f"a 0.6 s gap in the layer changes nothing ({ev})")
    finish(s)
    return s


@scenario
def stale_state_files():
    """A state file left by a dead or stalled daemon, or from a previous boot, is not believed."""
    path = os.environ["YOGA_STATE_FILE"]
    base = {"v": 1, "pid": os.getpid(), "mono": clock.t, "dock": {"raw": 1, "eff": 1}, "want": {}}
    def put(**kw):
        d = dict(base, **kw)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump(d, f)
    put()
    check(yoga_state.read_state() is not None, "fresh state is read")
    put(pid=999999)
    check(yoga_state.read_state() is None, "dead pid: ignored")
    put(mono=clock.t - 10)
    check(yoga_state.read_state() is None, "older than STALE_S: ignored")
    put(mono=clock.t + 5000)
    check(yoga_state.read_state() is None, "from the future (previous boot): ignored")
    put(v=99)
    check(yoga_state.read_state() is None, "other version: ignored")
    with open(path, "w") as f:
        f.write("{not json")
    check(yoga_state.read_state() is None, "garbage: ignored")
    os.unlink(path)


@scenario
def external_keyboard_detection():
    """A USB keyboard (not the touch controller's, not a virtual one) refuses the on-screen keyboard; a Bluetooth one does not."""
    path = os.environ["YOGA_INPUT_DEVICES"]
    def blk(bus, vid, pid, name, sysfs, handlers, ev):
        return (f"I: Bus={bus} Vendor={vid} Product={pid} Version=0000\nN: Name=\"{name}\"\nS: Sysfs={sysfs}\n"
                f"H: Handlers={handlers}\nB: EV={ev}\n")
    at = blk("0011", "0001", "0001", "AT keyboard", "/devices/platform/i8042/input/input3", "sysrq kbd event3", "120013")
    keyd = blk("0003", "0fac", "0ade", "keyd virtual keyboard", "/devices/virtual/input/input21", "sysrq kbd event18", "120003")
    ctl = blk("0003", "17ef", "6161", "INGENIC controller keyboard", "/devices/pci/usb3/3-6/input/input35", "sysrq kbd event9", "12001f")
    pad = blk("0003", "046d", "c31c", "media pad", "/devices/pci/usb3/3-5/input/input40", "kbd event30", "13")
    bt = blk("0005", "17ef", "616a", "Dock keyboard", "/devices/virtual/misc/uhid/0005/input/input23", "sysrq kbd event20", "12001f")
    usb = blk("0003", "046d", "c31c", "USB keyboard", "/devices/pci/usb3/3-1/input/input41", "sysrq kbd event31", "120013")
    def put(*b):
        with open(path, "w") as f:
            f.write("\n".join(b))
    put(at, keyd, ctl, pad)
    check(yoga_state.external_keyboard() is None, "built-in, virtual, controller and key-pad devices do not count")
    put(at, keyd, ctl, bt)
    check(yoga_state.external_keyboard() is None, "a connected Bluetooth (uhid) keyboard does not count (only the dock position does)")
    put(at, usb)
    check(yoga_state.external_keyboard() == "USB keyboard", "a USB keyboard counts")
    cfg = os.path.join(os.environ["XDG_CONFIG_HOME"], "yoga")
    os.makedirs(cfg, exist_ok=True)
    open(os.path.join(cfg, "osk-with-keyboard"), "w").close()
    check(yoga_state.external_keyboard() is None, "~/.config/yoga/osk-with-keyboard opts out")
    os.unlink(os.path.join(cfg, "osk-with-keyboard"))
    put()


@scenario
def one_debounce_constant():
    """The dock debounce is defined once; nothing else times the dock."""
    pat = re.compile(r"debounce\s*=\s*[0-9]|DEBOUNCE\w*\s*=\s*[0-9]|dock_debounce")
    hits = []
    for n in os.listdir(BIN):
        p = os.path.join(BIN, n)
        if os.path.isfile(p):
            try:
                txt = open(p).read()
            except UnicodeDecodeError:
                continue
            for i, ln in enumerate(txt.splitlines(), 1):
                if pat.search(ln) and not ln.lstrip().startswith("#"):
                    hits.append(f"{n}:{i}: {ln.strip()}")
    allowed = [h for h in hits if h.startswith("yoga_state.py") or "DEBOUNCE_S = 0.5" in h]
    check(len(allowed) == len(hits), f"only yoga_state.py defines the dock debounce (others: {[h for h in hits if h not in allowed]})")
    raw = [n for n in os.listdir(BIN) if os.path.isfile(os.path.join(BIN, n)) and "E7F300FA" in open(os.path.join(BIN, n), errors="ignore").read()]
    check(sorted(raw) == ["yoga-osk", "yoga_state.py"], f"only yoga_state.py (and yoga-osk's no-helper fallback) read keyboard_position: {raw}")


# =============================================================================================
# Part 2: the bash scripts, real time, stubs
# =============================================================================================
STUB_PY = {
    "hyprctl": textwrap.dedent('''\
        #!/usr/bin/env python3
        import sys, os, json
        d = os.environ["STUB_DIR"]
        a = sys.argv[1:]
        if a[:2] == ["layers", "-j"]:
            lv = {"2": [{"namespace": "wvkbd"}]} if os.path.exists(d + "/visible") else {}
            print(json.dumps({"eDP-2": {"levels": lv}}))
        elif a[:2] == ["monitors", "-j"]:
            print(json.dumps([{"name": "eDP-1", "description": "Samsung Display Corp. 0x4167", "disabled": False},
                              {"name": "eDP-2", "description": "Samsung Display Corp. 0x4182", "disabled": False}]))
        '''),
    "wvkbd-stub": textwrap.dedent('''\
        #!/usr/bin/env python3
        import signal, os, sys, ctypes
        ctypes.CDLL(None).prctl(15, b"wvkbd-stub", 0, 0, 0)    # pgrep -x matches the comm name
        d = os.environ["STUB_DIR"]
        def log(m):
            with open(d + "/wvkbd.log", "a") as f:
                f.write(m + "\\n")
        log("start " + " ".join(sys.argv[1:]))
        def show(*_):
            open(d + "/visible", "w").close(); log("show")
        def hide(*_):
            try: os.unlink(d + "/visible")
            except OSError: pass
            log("hide")
        def term(*_):
            log("TERM: released modifiers")
            hide(); sys.exit(0)
        signal.signal(signal.SIGUSR2, show); signal.signal(signal.SIGUSR1, hide)
        signal.signal(signal.SIGTERM, term)
        while True: signal.pause()
        '''),
    "pgrep": textwrap.dedent('''\
        #!/bin/sh
        case "$*" in
          *hyprlock*) [ -e "$STUB_DIR/locked" ]; exit $? ;;
        esac
        exec /usr/bin/pgrep "$@"
        '''),
    "notify-send": "#!/bin/sh\nexit 0\n",
    "noctalia": "#!/bin/sh\nexit 0\n",
}


class Feeder(threading.Thread):
    """Keeps a published state fresh (a stand-in for the posture daemon)."""

    def __init__(self, path):
        super().__init__(daemon=True)
        self.path = path
        self.state = {"v": 1, "pid": os.getpid(), "dock": {"raw": 0, "eff": 0}, "posture": "laptop", "screens": "dual",
                      "panels": {"top": {"on": True, "transform": 2}, "bottom": {"on": True, "transform": 0}},
                      "epoch": 1, "osk": {"visible": False, "held": False},
                      "want": {"osk_allowed": True, "reserved": False, "bar_hidden": False, "touchpad_ok": True, "screens": "dual"}}
        self.go = True
        self.lock = threading.Lock()

    def set(self, **kw):
        with self.lock:
            for k, v in kw.items():
                self.state[k] = v
            self.write()

    def write(self):
        d = dict(self.state, mono=REAL["monotonic"](), seq=0)
        yoga_state.write_json_atomic(self.path, d)

    def run(self):
        while self.go:
            with self.lock:
                self.write()
            REAL["sleep"](0.5)


def part2(verbose):
    sd = os.path.join(TMP, "stub")
    os.makedirs(sd)
    for name, body in STUB_PY.items():
        p = os.path.join(sd, name)
        with open(p, "w") as f:
            f.write(body)
        os.chmod(p, 0o755)
    env = dict(os.environ, STUB_DIR=sd, PATH=sd + ":" + os.environ["PATH"], YOGA_OSK_WVKBD="wvkbd-stub",
               YOGA_OSK_BIN=BIN, YOGA_OSK_OUTPUT="")
    env.pop("YOGA_OSK_OUTPUT")
    osk = os.path.join(BIN, "yoga-osk")
    feeder = Feeder(os.environ["YOGA_STATE_FILE"])
    feeder.set()
    feeder.start()

    def sh(*args, **kw):
        return subprocess.run(list(args), env=dict(env, **kw.pop("env", {})), capture_output=True, text=True, timeout=60)

    def stubs():
        return subprocess.run(["pgrep", "-c", "-x", "-u", str(os.getuid()), "wvkbd-stub"], capture_output=True, text=True).stdout.strip()

    def wlog():
        try:
            return open(sd + "/wvkbd.log").read()
        except OSError:
            return ""

    def reset():
        subprocess.run(["pkill", "-KILL", "-x", "-u", str(os.getuid()), "wvkbd-stub"])
        for n in ("visible", "wvkbd.log", "locked"):
            try:
                os.unlink(f"{sd}/{n}")
            except OSError:
                pass
        try:
            os.unlink(os.path.join(RUN, "yoga-osk.mode"))
        except OSError:
            pass
        REAL["sleep"](0.2)

    print("part 2: bash scripts against stubs")
    try:
        reset()
        sh(osk, "show")
        check(os.path.exists(sd + "/visible") and stubs() == "1", "B1 yoga-osk show: one keyboard, visible")
        check("--top" in wlog() and "--fixed" in wlog(), "B1 dock mode arguments (--top --fixed)")
        sh(osk, "hide")
        check(not os.path.exists(sd + "/visible"), "B1 hide")

        # refusals
        feeder.set(dock={"raw": 1, "eff": 1}, want=dict(feeder.state["want"], osk_allowed=False))
        sh(osk, "show")
        check(not os.path.exists(sd + "/visible"), "B2 show refused while the state says docked")
        sh(osk, "toggle")
        check(not os.path.exists(sd + "/visible"), "B2 toggle refused while docked")
        r = sh(osk, "show", env={"YOGA_OSK_FORCE": "1"})
        check(os.path.exists(sd + "/visible"), "B2 YOGA_OSK_FORCE=1 overrides")
        sh(osk, "hide")

        # stale state: fall back to the raw dock file
        feeder.go = False
        REAL["sleep"](0.7)
        os.unlink(os.environ["YOGA_STATE_FILE"])
        open(os.environ["YOGA_DOCK_FILE"], "w").write("2\n")
        sh(osk, "show")
        check(not os.path.exists(sd + "/visible"), "B3 no state: raw dock file 2 refuses")
        open(os.environ["YOGA_DOCK_FILE"], "w").write("0\n")
        sh(osk, "show")
        check(os.path.exists(sd + "/visible"), "B3 no state: raw dock file 0 allows")
        sh(osk, "hide")
        feeder = Feeder(os.environ["YOGA_STATE_FILE"])
        feeder.set()
        feeder.start()

        # mode switch: a dock-mode keyboard is stopped (TERM, so it releases modifiers) when the screens change
        reset()
        sh(osk, "show")
        feeder.set(screens="single", posture="tablet",
                   panels={"top": {"on": False, "transform": 2}, "bottom": {"on": True, "transform": 0}},
                   want=dict(feeder.state["want"], osk_allowed=True, screens="single"))
        sh(osk, "hide")
        sh(osk, "show")
        log = wlog()
        check("TERM: released modifiers" in log, "B4 the dock-mode keyboard is ended with SIGTERM, not killed")
        check("--non-exclusive" in log.splitlines()[-2] + log.splitlines()[-1] + log, "B4 float mode started")
        check(open(os.path.join(RUN, "yoga-osk.mode")).read().strip() == "float:eDP-2", "B4 float on the lit (bottom) panel")
        check(stubs() == "1" and os.path.exists(sd + "/visible"), "B4 exactly one keyboard, visible")
        feeder.set(screens="dual", posture="laptop", panels={"top": {"on": True, "transform": 2}, "bottom": {"on": True, "transform": 0}},
                   want=dict(feeder.state["want"], screens="dual"))
        sh(osk, "hide")

        # two callers at once
        reset()
        ps = [subprocess.Popen([osk, "show"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for _ in range(4)]
        for p in ps:
            p.wait(timeout=40)
        check(stubs() == "1", f"B5 four concurrent shows start exactly one keyboard (found {stubs()})")
        check(wlog().count("start ") == 1, "B5 one start in the log")

        # stop
        sh(osk, "stop")
        check(stubs() == "0" and "TERM" in wlog(), "B6 stop ends it gracefully")

        # a dock that races the show
        reset()
        def flip():
            REAL["sleep"](0.3)
            feeder.set(dock={"raw": 1, "eff": 1}, want=dict(feeder.state["want"], osk_allowed=False))
        feeder.set(dock={"raw": 0, "eff": 0}, want=dict(feeder.state["want"], osk_allowed=True))
        th = threading.Thread(target=flip)
        th.start()
        sh(osk, "show")
        th.join()
        check(not os.path.exists(sd + "/visible"), "B7 a dock during `show` puts the keyboard away again")
        feeder.set(dock={"raw": 0, "eff": 0}, want=dict(feeder.state["want"], osk_allowed=True))

        # lock watcher
        reset()
        lw = subprocess.Popen([os.path.join(BIN, "yoga-osk-lockwatch")], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            REAL["sleep"](1.5)
            open(sd + "/locked", "w").close()
            deadline = REAL["monotonic"]() + 8
            while REAL["monotonic"]() < deadline and not os.path.exists(sd + "/visible"):
                REAL["sleep"](0.2)
            check(os.path.exists(sd + "/visible"), "B8 lock appears, undocked: keyboard shown over it")
            sh(osk, "hide")
            REAL["sleep"](2.5)
            check(not os.path.exists(sd + "/visible"), "B8 hiding it by hand stays hidden")
            sh(osk, "hide")
            feeder.set(epoch=feeder.state["epoch"] + 1)        # a posture/panel change (which hid it)
            deadline = REAL["monotonic"]() + 6
            while REAL["monotonic"]() < deadline and not os.path.exists(sd + "/visible"):
                REAL["sleep"](0.2)
            check(os.path.exists(sd + "/visible"), "B8 a posture change while locked brings it back")
            feeder.set(dock={"raw": 1, "eff": 1}, want=dict(feeder.state["want"], osk_allowed=False))
            sh(osk, "hide")                                    # (yoga-posture would)
            feeder.set(epoch=feeder.state["epoch"] + 1)
            REAL["sleep"](3.5)
            check(not os.path.exists(sd + "/visible"), "B8 docked while locked: stays away")
            feeder.set(dock={"raw": 0, "eff": 0}, want=dict(feeder.state["want"], osk_allowed=True))
            deadline = REAL["monotonic"]() + 6
            while REAL["monotonic"]() < deadline and not os.path.exists(sd + "/visible"):
                REAL["sleep"](0.2)
            check(os.path.exists(sd + "/visible"), "B8 undocked while locked: shown again")
            os.unlink(sd + "/locked")
            deadline = REAL["monotonic"]() + 6
            while REAL["monotonic"]() < deadline and os.path.exists(sd + "/visible"):
                REAL["sleep"](0.2)
            check(not os.path.exists(sd + "/visible"), "B8 unlock puts it away")
        finally:
            lw.terminate()
            lw.wait(timeout=5)
    finally:
        feeder.go = False
        subprocess.run(["pkill", "-KILL", "-x", "-u", str(os.getuid()), "wvkbd-stub"])


def part3():
    """yoga.lua against a stub `hl`: the lid guard and "reserved only with both panels lit"."""
    print("part 3: yoga.lua with a stubbed hl")
    lua = shutil.which("lua5.4") or shutil.which("luajit") or shutil.which("lua")
    if not lua:
        print("  skipped: no lua interpreter")
        return
    rt = os.path.join(TMP, "lua-run")
    os.makedirs(rt)
    p = subprocess.run([lua, os.path.join(ROOT, "yoga", "tests", "yoga-lua-test.lua"), ROOT], capture_output=True, text=True,
                       env=dict(os.environ, XDG_RUNTIME_DIR=rt), timeout=60)
    print("  " + (p.stdout + p.stderr).strip().replace("\n", "\n  "))
    check(p.returncode == 0, "yoga-lua-test.lua")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-k", default="")
    ap.add_argument("-v", action="store_true")
    ap.add_argument("--part", choices=["1", "2", "3", "all"], default="all")
    args = ap.parse_args()
    try:
        if args.part in ("2", "all") and not args.k:
            part2(args.v)
        if args.part in ("3", "all") and not args.k:
            part3()
        if args.part in ("1", "all"):
            time.monotonic = lambda: clock.t
            time.sleep = lambda s: setattr(clock, "t", clock.t + s)
            time.time = lambda: 1.7e9 + clock.t
            print("part 1: virtual clock")
            for sc in SCENARIOS:
                if args.k and args.k not in sc.__name__:
                    continue
                before = len(FAILS)
                sim = sc()
                ok = len(FAILS) == before
                print(f"  {'ok  ' if ok else 'FAIL'} {sc.__name__}: {sc.__doc__}")
                if args.v and isinstance(sim, Sim):
                    for t, e in sim.world.events:
                        print(f"        {t:6.2f}  {e}")
            time.monotonic, time.sleep, time.time = REAL["monotonic"], REAL["sleep"], REAL["time"]
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    print(f"\n{CHECKS[0]} checks, {len(FAILS)} failed")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())

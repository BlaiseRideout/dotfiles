# Virtual touchpad on the bottom screen

The firmware has no touchpad: there is no "Emulated Touchpad" device, docked or not. `yoga/bin/yoga-touchpad`
builds one in software.

## How it works

While the keyboard is docked (or the on-screen keyboard is up) the daemon grabs the bottom touchscreen
(`EVIOCGRAB` on `/dev/input/yoga-touch-bottom`) and routes each touch by where it **starts**:

- inside the uncovered strip: to a uinput multitouch touchpad ("Yoga Virtual Touchpad"), so libinput gives you
  acceleration, tap-to-click, two-finger scroll and gestures;
- inside the button bar along the strip's front edge (see below): `BTN_LEFT` / `BTN_RIGHT` on that same touchpad;
- anywhere else: to a uinput touchscreen with the real one's ranges ("Yoga Virtual Touchscreen Bottom"), which
  `yoga.lua` binds to the bottom panel, so the rest of the screen keeps working.

A touch stays where it started until it lifts. The kernel releases the grab if the daemon dies.

**The controller drops off USB three times in the first minute after boot** ([hardware.md](hardware.md)). The
daemon rides that out: it lifts any held touch, closes only the real node, and keeps the virtual devices (so
Hyprland keeps its bindings), the active strip and the outline on screen, then takes the grab again as soon as
`/dev/input/yoga-touch-bottom` is back (~1 s; log: `grabbed ... again after N s`). It starts over (deactivate,
retry) only if the node does not return within 30 s or comes back with other ranges.

Needs `python-evdev`, `/dev/uinput` and the touch node accessible to your user (`yoga/udev/62-yoga-touchpad.rules`).

## CLI

```
yoga-touchpad status | on | off | auto | toggle | log [-f]
yoga-touchpad selftest        # scripted multitouch scenarios, no hardware touched
yoga-touchpad simulate        # fake fingers through the router
```
Bind: **SUPER+ALT+t** toggles. `on`/`off`/`toggle` set a manual override that **stays until you run `yoga-touchpad auto`** (it survives docking and posture changes); `status` shows it as `forced off`/`forced on`. Emergency: `systemctl --user stop yoga-touchpad` or `yoga-touch recover`.

## Mouse buttons

The front 8% of the screen's height of every strip (its high-y end, the edge nearest you in all poses) is a bar of
two buttons, marked on the outline by a line and a divider: **left** of the middle is `BTN_LEFT`, **right** of it
`BTN_RIGHT`. The pad is the rest of the strip. A finger that starts in the bar holds its button until that finger
lifts (sliding off changes nothing), so a thumb can hold the left button while another finger drags on the pad. Two
fingers on one button keep it down until both lift. Held buttons are released on every path that lifts touches
(strip change, USB drop, `SYN_DROPPED`, shutdown).

It is **one device**: the buttons are keys on "Yoga Virtual Touchpad" itself (the pad advertises `BTN_LEFT` and
`BTN_RIGHT`; `INPUT_PROP_BUTTONPAD` stays off). libinput therefore sees an ordinary touchpad with physical buttons,
not a clickpad, and tap-to-click, tap-and-drag, natural scrolling and the rest are the system's touchpad settings
(Hyprland's `input.touchpad.*`, per device with `hl.device`) like on any other touchpad. libinput's own default for a
pad with a left button is tapping off, but Hyprland sets `tap_to_click` itself (true unless you changed it).

## When it is active and where the strip is

| Situation | Strip (fraction of the screen, y = 0 at the hinge) |
|---|---|
| keyboard near the hinge (`keyboard_position` 1) | the front part, y 0.615-1.0 (the keyboard edge measures ~0.63 and a finger centre reads ~5 mm short of the real edge) |
| keyboard at the front edge (2) | near the hinge, y 0.06-0.45 (starts below the bar) |
| on-screen keyboard visible, undocked | y 0.475-1.0 (keyboard + pad fill the screen) |
| forced on, nothing else | front strip |

Suspended in tablet/tent (one screen), when the bottom panel is off or rotated (book), or when `touchpad_ok`
is false in the shared state ([state-machine.md](state-machine.md)).

## Tuning (`~/.config/yoga-touchpad.toml`)

```toml
[strip.dock1]          # also dock2, osk, manual
x = [0.0, 1.0]
y = [0.60, 1.0]
[panel]
invert_x = false       # if the digitiser origin is not the panel's top-left in laptop pose
invert_y = false
[pad]
advertise_left_button = false   # BTN_LEFT without the button bar (the bar advertises both buttons itself)
[buttons]
enabled = true         # false: the whole strip is the pad again
height = 0.08          # of the screen's height; capped at half the strip
split = 0.5            # where left ends and right begins, as a fraction of the strip's width
```

Full width keeps palm rejection at the pad's edges. Measure your strip by dragging a finger along the keyboard
edge in `yoga-touchpad log -f` or with an evdev reader on the node (finger-centre readings sit ~5 mm short of
the real edge).

## Gestures on the pad

hyprgrass only sees touchscreens, so `yoga/hypr/touch.lua` binds the same multi-finger swipes as Hyprland's own
touchpad gestures (`hl.gesture`, fed by libinput from the virtual touchpad). They fire once when the swipe is
recognised (no live following): **3 fingers left/right** = workspace step (the book-pair step in book pose),
**4 fingers left/right/up/down** = move the window (same handlers as the touchscreen: `yoga_win_swipe`,
`yoga_win_to_monitor`), **5 fingers up** = window switcher. Not ported: pinches (libinput pinches take two fingers)
and the 3-finger hold-and-drag. Each swipe is logged in `gesture.log` as `touchpad N-finger swipe <dir>`. If libinput
never reports 5-finger swipes the 5-finger bind simply does nothing.

## Pitfalls

- **Cursor looks backwards on the top panel**: that is the hardware cursor plane, not the pad ([display.md](display.md)).
- No physical click exists: the clicks are the button bar and tap-to-click on the pad (a system setting, on by
  default in Hyprland).
- Gestures bound to three fingers on the bottom screen share the digitiser with this daemon; they work docked
  because three-finger touches outside the strip are forwarded to the virtual touchscreen. A finger that lands
  in the strip goes to the pad.
- The state it follows comes from `yoga-posture`; without a fresh state file it computes the same thing itself.
- `yoga-touchpad-indicator` draws the strip outline, with the button bar (a line above it and a divider, no labels), on the bottom screen (a layer surface).

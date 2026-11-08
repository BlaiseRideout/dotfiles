# Virtual touchpad on the bottom screen

The firmware has no touchpad: there is no "Emulated Touchpad" device, docked or not. `yoga/bin/yoga-touchpad`
builds one in software.

## How it works

While the keyboard is docked (or the on-screen keyboard is up) the daemon grabs the bottom touchscreen
(`EVIOCGRAB` on `/dev/input/yoga-touch-bottom`) and routes each touch by where it **starts**:

- inside the uncovered strip: to a uinput multitouch touchpad ("Yoga Virtual Touchpad"), so libinput gives you
  acceleration, tap-to-click, two-finger scroll and gestures;
- anywhere else: to a uinput touchscreen with the real one's ranges ("Yoga Virtual Touchscreen Bottom"), which
  `yoga.lua` binds to the bottom panel, so the rest of the screen keeps working.

A touch stays where it started until it lifts. The kernel releases the grab if the daemon dies.

Needs `python-evdev`, `/dev/uinput` and the touch node accessible to your user (`yoga/udev/62-yoga-touchpad.rules`).

## CLI

```
yoga-touchpad status | on | off | auto | toggle | log [-f]
yoga-touchpad selftest        # scripted multitouch scenarios, no hardware touched
yoga-touchpad simulate        # fake fingers through the router
```
Bind: **SUPER+ALT+t** toggles. `on`/`off`/`toggle` set a manual override that **stays until you run `yoga-touchpad auto`** (it survives docking and posture changes); `status` shows it as `forced off`/`forced on`. Emergency: `systemctl --user stop yoga-touchpad` or `yoga-touch recover`.

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
advertise_left_button = false   # no BTN_LEFT: libinput then enables tap-to-click
```

Full width keeps palm rejection at the pad's edges. Measure your strip by dragging a finger along the keyboard
edge in `yoga-touchpad log -f` or with an evdev reader on the node (finger-centre readings sit ~5 mm short of
the real edge).

## Pitfalls

- **Cursor looks backwards on the top panel**: that is the hardware cursor plane, not the pad ([display.md](display.md)).
- No physical click exists, so there is no button; tap-to-click is the click.
- Gestures bound to three fingers on the bottom screen share the digitiser with this daemon; they work docked
  because three-finger touches outside the strip are forwarded to the virtual touchscreen. A finger that lands
  in the strip goes to the pad.
- The state it follows comes from `yoga-posture`; without a fresh state file it computes the same thing itself.
- `yoga-touchpad-indicator` draws the strip outline on the bottom screen (a layer surface).

# Posture daemon (`yoga-posture`)

Reads both accelerometers, works out the hinge angle and posture, and lays out the panels through Hyprland.
Also the single authority for the dock state ([state-machine.md](state-machine.md)).

## Postures

| Posture | Rule | Layout |
|---|---|---|
| `laptop` | default (opening below ~255, hinge horizontal) | stacked, both on |
| `flat` | 180 +-10 degrees, both halves horizontal | stacked, both on |
| `book` | gravity along the hinge on both halves (opened like a book, held upright) | both portrait, side by side |
| `tent` | opening 255 or more | panel facing you on, rotated; the other off |
| `tablet` | opening 335 or more (out under 300) | the panel facing up on; the other off |
| `closed` | lid switch | panels off |

Hysteresis and a 0.5 s debounce on the whole layout. Tent and tablet report `SW_TABLET_MODE` through a
virtual evdev switch ("Yoga Posture Tablet Mode Switch"). The keyboard dock never does.

## Sensors and the angle

- The two `accel_3d` devices are found by HID instance (**19 = top, 20 = bottom**), not by `iio:deviceN`.
- `opening = 180 - (atan2(y,z)_top - atan2(y,z)_bottom)`, unwrapped over time so "almost closed" and "back to
  back" are told apart from history. Gravity along the hinge (book) holds the last angle.
- **2.5 Hz, sequential reads.** Faster polling (10 Hz, threads) froze one accelerometer: identical raw values,
  the other sensor fine. Measured: a cycle every 0.16 s froze it, 0.27 s mostly worked, 0.3 s+ was fine.
- **Reviving:** a frozen half is unbound and bound again (`ACCEL_DRIVER` bind / unbind: what `modprobe -r hid_sensor_accel_3d && modprobe hid_sensor_accel_3d` does for all sensors) once it has been frozen about 8 s, at most every 30 s. That needs write access to the driver's files, which `yoga/udev/65-yoga-accel-revive.rules` gives group `wheel` (ansible/yoga.yaml installs it); without it the journal says `cannot revive ...` once. Not polling: the stall happened with the daemon stopped, the gyros of both halves kept reporting, and a reload fixed it at once.
- A frozen half (unchanged 5 s while the other moves) falls back to "assume the hinge is flat"; it recovers by
  itself. Exception: with the hinge last seen at tent angle or more (255+), the opening is held instead, because the
  top sensor tends to freeze right after folding back and the fallback turned tent/tablet into laptop. The hold ends when the half that still reports lies flat (|z| >= 0.95) for 3 s (`FOLD_HOLD_FLAT_*`): a frozen sensor may never revive (seen: ten minutes through a fold and an unfold), and an unfold to a laptop on a desk could not otherwise be seen. Cost: a tablet lying flat on a table with the top sensor frozen drops to laptop; `SUPER+ALT+p` forces it back. Reloading `hid_sensor_accel_3d` (root) also revives it.
- The `hinge` IIO device reads 0; gyros are unused.
- **Resume:** the sensor hub wakes slowly and the fallback would flip to "flat" and hide the on-screen keyboard.
  The daemon detects a resume and holds posture changes for 10 s (`RESUME_GRACE_S`).
- **Fold guard:** while the hinge is above `LID_GLITCH_ABOVE` or in tent/tablet it holds logind's lid inhibitor,
  because the lid switch can read "closed" when folded back.

## Gyros

The two `gyro_3d` devices (HID instances 22 = lid, 23 = base, in the same order as the accelerometers) have the
hinge as their X axis, so *top X rate minus bottom X rate* is how fast the hinge opens or closes; the movement of the
whole machine cancels. At 2.5 Hz that cannot be integrated into a reliable angle, but it says that, and roughly how
far and which way, the hinge moved, which keeps working when an accelerometer is stuck:

- **Sign:** which way the rate turns the opening is learnt while both accelerometers work (rate against the change of
  the accelerometer opening, 40 degrees of agreement; `yoga-posture status` shows `sign +1 / -1 / not learnt`). Fix it in
  `~/.config/yoga-posture.json` with `{"HINGE_SIGN": 1}` (or -1).
- **Held fold with a frozen sensor:** with the sign known, the opening is dead reckoned from the hold's start (the
  classifier follows it, so tent -> tablet works), and the hold ends once it falls below about 240 degrees. Without a
  sign, hinge travel of 30 degrees since the sensor froze ends it.
- **Revive:** the same 30 degrees of travel while a half is frozen revives that sensor at once.

## Panel rotation

`transform = (physical quarter turns + PANEL_OFFSET) % 4`. `PANEL_OFFSET` is `{top: 0, bottom: 0}` with the
kernel flag doing the top panel's mounting flip (it was top 2 before). Quarter turns: right edge up = 1, upside
down = 2, left edge up = 3 (iio-sensor-proxy convention). If a panel is a quarter turn the wrong way, swap 1/3 in
`QUAD_OF_ORIENTATION`. Book mode: `BOOK_BOTTOM_LEFT_WHEN = "right-up"` (checked: the bottom panel is the left
one when the right edge is up).

## CLI and binds

```
yoga-posture status                 # live state
yoga-posture force laptop|flat|book|tent|tablet|tent-top|tablet-bottom|book-left|book-right [...:0-3]
yoga-posture auto | reset | cycle | flip-tent
yoga-posture log [-f]  | once | replay <csv> | apply <spec> --revert 15
yoga-posture daemon [--dry-run] [--no-switch] [--no-osk] [--debug]
```
**SUPER+ALT+f** flip tent/tablet panel, **SUPER+ALT+p** cycle, **SUPER+ALT+SHIFT+p** reset to laptop (works locked).
Without the script: `hyprctl repl 'return yoga_set_posture(nil)'`. Overrides:
`~/.config/yoga-posture.json` (e.g. `{"DEBOUNCE_S": 0.8, "TENT_FACING_DEFAULT": "top"}`).

## How Hyprland is driven

`yoga_set_posture(spec)` in `yoga/hypr/yoga.lua` (through `hyprctl repl`) sets monitor rules, enables/disables a
panel, rebinds touch devices (`yoga_apply_devices()`) and moves workspaces. Never use iio-hyprland or
iio-sensor-proxy next to it. Hyprland 0.57's Lua config is why it's `hyprctl repl`/`eval`, not `keyword`.

## Sensor frames (for porting to another unit)

Both halves share the X (hinge) axis; Y is the screen normal in laptop pose. Per-posture raw recordings and the
replay file are in `survey-output/postures.*`; `yoga-posture replay` runs the classifier on them.

## Unverified

Tablet/tent rotation directions on the top panel, and book mode turned the other way (derived by symmetry).
The way to check is to `force` each posture and look; `reset` undoes anything.

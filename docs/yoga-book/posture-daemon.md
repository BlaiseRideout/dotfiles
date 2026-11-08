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
- A frozen half (unchanged 5 s while the other moves) falls back to "assume the hinge is flat"; it recovers by
  itself. Reloading `hid_sensor_accel_3d` (root) also revives it.
- The `hinge` IIO device reads 0; gyros are unused.
- **Resume:** the sensor hub wakes slowly and the fallback would flip to "flat" and hide the on-screen keyboard.
  The daemon detects a resume and holds posture changes for 10 s (`RESUME_GRACE_S`).
- **Fold guard:** while the hinge is above `LID_GLITCH_ABOVE` or in tent/tablet it holds logind's lid inhibitor,
  because the lid switch can read "closed" when folded back.

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

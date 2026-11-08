# Palm rejection

`yoga-palm` switches a touchscreen off while a palm, or the pen, is on it. There is no sensitivity setting in
libinput or Hyprland to tune instead: see "What the controller gives us".

## What the controller gives us

The touch interface (USB `17ef:6161`, interface 3, the one `hid-multitouch` drives) sends reports in a 57-byte
layout, one per 8 ms frame (125 Hz): the report id (`48` = Touchscreen Top, `56` = Bottom), 10 contact slots of
5 bytes (tip + confidence + contact id in one byte, X, Y), a scan time, a contact count, one vendor byte.
Measured on the unit (`yoga/tests/palm-probe.py` repeats the rate measurement; reports are exactly 57 bytes, nothing hidden):

- **No size, no pressure.** The descriptor has no `Width`, `Height`, `TouchMajor` or `Pressure` for touch. A
  contact is a point. A driver patch cannot expose data the controller never sends.
- **The firmware's palm flag is useless.** `Confidence` stayed 1 for a fingertip, a flat palm and a whole hand.
- **The vendor HID channels** (`hidraw6`, `hidraw8`) are silent while touching. They are probably request-driven;
  they were not written to (the controller already drops off USB three times per boot).
- **How the contacts arrive does differ.** The controller scans at a constant 8 ms, but with a palm on the glass it
  skips most frames:

  | Contact | Reports/s | Contacts | Largest step in one frame |
  |---|---|---|---|
  | Fingertip, still | 111 | 1 | 0 |
  | Fingertip, moving | 118 | 1 | 701 units (~18 mm) |
  | Flat palm, still | 13 | 2 | 5118 (~13 cm) |
  | Flat palm, moving | 58 | 2 | 1198 |
  | Whole hand | 1-2 | 5 | |

  (X/Y units: 11440 x 7148 per panel, about 38 per mm. One trial each: tune on real use, below.)
- Only the first `contact count` slots are valid. The rest hold the previous hand, tip bit included.

The evdev nodes cannot show this: the kernel drops a report that repeats the last positions, and a still fingertip
repeats them 111 times a second.

## What it does

`yoga-palm` reads the raw reports (`/dev/input/yoga-touch-raw`, a hidraw node made readable for the seat's user by
`yoga/udev/64-yoga-palm.rules`), keeps a detector per node, and calls `yoga_set_touch_suppressed(node, on)` in
`yoga/hypr/yoga.lua` through `hyprctl repl`. That function disables the node's touchscreen (for the bottom node
also the virtual touchscreen that carries its touches, [touchpad.md](touchpad.md)) and is honoured by every later
`yoga_apply_devices()`, so a posture change cannot switch it back on. The pen nodes are never touched.

A node goes off when any of these holds:

| Rule | Default | Meaning |
|---|---|---|
| Density | < 0.6 of the frames arrive | after a contact has been watched for 160 ms; a finger measured 0.89-0.95 |
| Jump | > 1500 units in one frame | one contact id teleporting; the fastest finger measured 700. Acts at once |
| Firmware flag | `Confidence` = 0 | never seen, but honoured |
| Pen | the stylus on that node is in range | reports `InRange`; off while hovering and 600 ms after it leaves |

The density rule runs on a timer, not just when a report arrives, because a resting palm is a contact that
*stops* reporting: in a dry run, a palm gave a few reports as it landed, nothing while it rested, and a few more
with the lift report as it peeled off. (A first version judged only on arrival and never saw it. Every ordinary
contact in the same run, 11 taps and swipes, sent its lift report, so silence with no lift is the palm's signature.)

It stays off until the node's last contact lifted 600 ms ago (the hold runs from the lift report, so a palm's
peel-off reports are covered), or, if reports just stop without a lift report, for 5 s: a resting palm is silent, so
this is how long it is covered. A finger touching in that time is swallowed too.
While the pen is near a panel that panel's touch does not work: that is the price of drawing with a hand on the glass.

The bottom touchpad strip is `yoga-touchpad`'s ([touchpad.md](touchpad.md)); it grabs the real node, so nothing here
changes it.

## Tuning

Dry run first: it decides and logs but never touches Hyprland (works as root too, if the udev rule is not in yet):

```
yoga-palm watch --dry --log
```

`--log` prints, five times a second per node with a contact down, the contact count, how long it has been down, the
density and the biggest jump, and notes `lift report after N reports` (the controller sent the lift) or `reports resumed
after Ns without a lift report` (it did not). **Touch the top panel and check the line says `top`** (the node-to-report-id order is
read from the descriptor's order, not measured per unit; if the panels are swapped, change `TOUCH_IDS` and `PEN_IDS`
at the top of `yoga/bin/yoga-palm`). Rest your palm, then a finger, then a pinch and a 5-finger swipe (hyprgrass),
and set the thresholds from what you see. For the service:

```
systemctl --user edit yoga-palm
[Service]
Environment=YOGA_PALM_DENSITY=0.5
```

| Variable | Default | Raise it to... |
|---|---|---|
| `YOGA_PALM_DENSITY` | 0.6 | reject more (a lossy finger gets caught at 0.8+) |
| `YOGA_PALM_WINDOW_MS` | 160 | wait longer before judging (fewer false alarms, slower) |
| `YOGA_PALM_JUMP` | 1500 | tolerate faster fingers; 0 turns the check off |
| `YOGA_PALM_HOLD_MS` | 600 | keep the node off longer after a lift |
| `YOGA_PALM_SILENCE_MS` | 5000 | same, when no lift report came (a resting palm is silent) |
| `YOGA_PALM_PEN` | 1 | 0 = no pen rule |
| `YOGA_PALM_PEN_TAIL_MS` | 600 | the pen rule's hold after the pen leaves |

Not measured: a 5-finger gesture with fingertips (the whole-hand figure above is a flat hand). If hyprgrass
gestures start getting swallowed, lower `YOGA_PALM_DENSITY` first.

## Safety

- On SIGTERM the daemon switches the touchscreens back on, and `ExecStopPost` runs `yoga-palm reset` for a crash; a config reload resets
  Hyprland's side, and the daemon asserts a suppression again every 5 s.
- `yoga-touch recover` (SUPER+CTRL+SHIFT+Escape) stops `yoga-palm`. Start it again with
  `systemctl --user start yoga-palm`.
- A pen that stops reporting while "in range" is taken as gone after 2 s; a node never stays off for longer than a
  touch or pen report plus the hold.
- `yoga-palm status`, `yoga-palm reset`.
- The controller dropping off USB (three times after boot): the daemon releases both nodes and waits for it.

## Tests

`python3 yoga/tests/palm-sim.py` replays the measured patterns as synthetic 57-byte reports through the detector and
the daemon's actuator logic (finger, palm, whole hand, teleports, pen, release, retry). `lua yoga/tests/yoga-lua-test.lua`
(run by `state-sim.py`) covers `yoga_set_touch_suppressed`.

## Install

`yoga-palm` is linked and the unit wanted by `yoga/nix/module.nix` (`home-manager switch`); the udev rule is installed
by `ansible/yoga.yaml` (`ansible-playbook setup.yaml`). By hand:

```
sudo cp yoga/udev/64-yoga-palm.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=hidraw --action=change
ls -l /dev/input/yoga-touch-raw          # the symlink, and getfacl shows your user
```

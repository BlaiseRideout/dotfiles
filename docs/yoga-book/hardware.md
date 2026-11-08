# Hardware facts (Yoga Book 9 13IMU9, DMI `83FF`)

Reference sheet. Measured on one machine (BIOS `NVCN28WW` 10/01/2025, kernel 7.3, Hyprland 0.57.1).

## Identity

| | |
|---|---|
| `product_name` / family | `83FF` / `Yoga Book 9 13IMU9` (board `LNVNB161216`) |
| CPU, GPU | Core Ultra 7 155U; Meteor Lake iGPU. Both `xe` and `i915` load; **`i915` drives the panels** |
| Sleep | `s2idle` only (ACPI supports S0/S4/S5, no S3) |

## Panels

| | Hyprland name | Description (use this, not the port) | Backlight |
|---|---|---|---|
| top | `eDP-1` | `Samsung Display Corp. 0x4167` | `intel_backlight` |
| bottom | `eDP-2` | `Samsung Display Corp. 0x4182` | `card1-eDP-2-backlight` |

2880x1800 OLED, **60 Hz only** (no 120 Hz mode, no VRR), scale 2 gives 1440x900 logical. The top panel is
mounted upside down (the DRM property says "Normal", so tell the kernel with `video=eDP-1:panel_orientation=upside_down`).
Both backlights are `raw`, max 400.

## Touch and pen: one USB device, four nodes

`17ef:6161`, "INGENIC Gadget Serial and keyboard", USB `3-6`. Hyprland shows the nodes lower-cased and hyphenated
(`ingenic-gadget-serial-and-keyboard-touchscreen-top`):

| Node | Type | Range |
|---|---|---|
| Touchscreen Top / Bottom | touch, 10 contacts | X 0-11440, Y 0-7148 (native: x 0 left, **y 0 at the hinge edge**) |
| Stylus Top / Bottom | tablet | X 0-28598, Y 0-17874, pressure 0-4095, tilt +-9000 |

- There is **no "Emulated Touchpad"**, not even when docked. The virtual touchpad is software ([touchpad.md](touchpad.md)).
- The top digitiser reports user-oriented coordinates; the panel is mounted rotated, so the top node needs no
  rotation while the panel is "upright".
- **The controller drops off USB three times, 20 s apart, in the first minute after every boot.** Anything that
  attaches to its devices should wait for that to finish.
- Pen pressure reaches libinput on both nodes; Krita shows it on both screens.
- Other interfaces on the same device: a CDC serial port (`ttyACM0`), a HID keyboard, vendor HID channels
  (unread). Stylus batteries show up as `hid-ingenic-battery-*`.

## Keyboard

Bluetooth only (`Yoga Book 9 Bluetooth KB`, USB id `17ef:616a`); its USB-C port only charges. Dock state is
a WMI value, not an input device, and is read through the DKMS driver ([kbdock.md](kbdock.md)):
`keyboard_position` 0 away, 1 near the hinge, 2 at the front edge.

## Sensors (Intel sensor hub, IIO)

| Device | Notes |
|---|---|
| two `accel_3d` | HID instances **19 = top (lid) half, 20 = bottom (base) half**. Identify them by that instance, never by `iio:deviceN` (numbers change) |
| two `gyro_3d` | not used |
| `hinge` | reads 0 on all channels, including `keyboard`: useless |
| `als` | ambient light, raw x 0.001; low readings, not calibrated |

Gravity lies on Y in the laptop pose and the hinge axis is X. No mount matrices exist anywhere; they are derived
([posture-daemon.md](posture-daemon.md)). Do not enable `iio-sensor-proxy` next to the posture daemon.

**Do not poll the accelerometers faster than about 3 Hz**: at ~6 Hz one of them freezes (identical raw values).

## Firmware and WMI

- Dock: WMI event GUID `806BD2A2-177B-481D-BFB5-3BA0BB4A2285` (notify `EB`, ACPI `WM10`/`GMZN`) and data block
  `E7F300FA-21CD-4003-ADAC-2696135982E6` (`BKBD`). Same as the Gen 10; only the DMI check differs.
- `lenovo-ymc` cannot bind (its GUID is absent), so nothing else reports tablet mode.
- Audio: Realtek ALC287 (codec SSID `17aa:38f8`) with two TI **TAS2781** amps on `i2c-TIAS2781:00`, behind SOF.
- Camera: IR and RGB nodes (`video0`-`video3`).
- Battery: `charge_types` (`Fast`/`Standard`/`Long_Life`) and `conservation_mode` exist; root-writable.

## Harmless firmware noise

`ACPI BIOS Error ... AE_NOT_FOUND` (`NBIX`, `MXTP`, `PNOT`, `FCHG`), `AE_ALREADY_EXISTS` on USB `_UPC`,
`UCSI: Invalid num_connectors 131`, `lenovo_wmi_gamezone ... platform_profile probe failed`, `intel-hid ...
failed to enable HID power button`, `igen6_edac` warnings. None needs action.

## Surveying a similar machine

`yoga-survey.py` (stdlib Python, in this directory) records devices, sensors per posture and dock signals;
its raw output from this machine is in `survey-output/`. `0001-lenovo-yb9-kbdock-add-83FF.patch` is the
upstream patch for the dock driver (tested on 83FF, not yet sent).

# Troubleshooting

Symptom, cause, fix. Everything here happened during the first bring-up.

## Boot

| Symptom | Cause | Fix |
|---|---|---|
| Spinner for up to ~20 s before the logo and greeter; `journalctl -b -k` shows `GSC proxy component didn't bind within the expected timeout` | i915 waits for `mei_gsc_proxy`, which the initramfs lacks, and the wait can only time out; it holds up the switch to the real root | `/etc/mkinitcpio.conf.d/yoga-gsc.conf` adds `mei_me mei_gsc_proxy` (ansible, `yoga.yaml`); `systemd-analyze` should then show an initrd well under 5 s |

## Display and orientation

| Symptom | Cause | Fix |
|---|---|---|
| Top panel upside down in the session after adding `video=eDP-1:panel_orientation=upside_down` | Hyprland applies the kernel's orientation; `transform = 2` flips it again | `panels.top.transform = 0`, `PANEL_OFFSET` top 0 in `yoga-posture`, `touch.top_offset = 0` |
| Cursor upside down / moves backwards on the top panel | hardware cursor plane isn't rotated | `cursor.no_hardware_cursors = 1` (set by `yoga.start()`) |
| Boot console/GRUB menu upside down | kernel doesn't know the mounting | the `video=` flag (section 2 of [install.md](install.md)) |
| Only 60 Hz offered | firmware/EDID advertises one mode on both panels | nothing to do; the rules use `highrr` and pick 120 Hz if it ever appears |
| Wrong panel treated as "top" | connector order differs | swap `panels.top.desc` / `panels.bottom.desc` in `yoga/hypr/config.lua` |
| Screen flashes/re-modesets when a window goes fullscreen | `send_content_type`, then `cm_auto_hdr` | both off in `render` |
| Brightness keys move one panel | two backlights (`intel_backlight`, `card1-eDP-2-backlight`) | the keys call `.config/hypr/brightness.sh` (steps all, floor 2 %) |
| Lock screen background upside down on top panel | only when the panel is rotated by a Hyprland `transform` (hyprlock doesn't undo the screencopy transform); fine with the kernel flag | `scripts/lock.sh` captures upright images for panels with transform != 0 (Yoga only) |

## Touch, pen, gestures

| Symptom | Cause | Fix |
|---|---|---|
| Touch lands rotated after a posture change | Hyprland doesn't rotate touch devices with the output | `touch.follows_panel = true`; `rotation_sense = -1` (portrait was a half turn off with 1) |
| Touch/pen on the wrong panel | mapping by device name | `touch.swap = true` |
| Gestures dead after a boot | touch controller re-enumerates 3 times in the first minute | `yoga-touch load` waits for 25 s of stability, then reloads; by hand: `hyprctl reload` |
| Gestures dead, nothing else wrong | a modifier is held (gestures bind with none): latched Shift on the OSK, or keyd | `yoga-osk hide`; restart `wvkbd-yoga`; `sudo keyd reload` |
| Gestures dead after a Hyprland update | plugin built against the old headers | `yoga-touch update` (log out and in first) |
| Three-finger (and other multi-finger) gestures dead while single touches work, then fine later | not reproduced. Seen right after toggling the virtual touchpad off/on and forcing a posture with fingers on the bottom screen (the touchpad daemon had just released its grab mid-touch). The digitiser reports up to 5 contacts, a synthetic swipe through a virtual touchscreen worked in tent and laptop, and a device vanishing mid-touch did not break it | `hyprctl reload`; if it recurs, note what you did in the previous minute (touchpad toggle, dock/undock, posture force) |
| Hyprland re-parses the config in a loop | `hl.plugin.load()` called from the config | never; load from outside (`yoga-touch`, `hyprpm`) |
| Touch locked up by a plugin | bad plugin | **SUPER+CTRL+SHIFT+Escape** or `yoga-touch recover` (TTY/SSH); `yoga-touch enable` to retry |
| Bottom screen dead while docked | virtual touchpad grabbed it | `systemctl --user stop yoga-touchpad` (the kernel drops the grab if it dies) |
| Pen pressure | works in Krita on both panels | for Wine apps see [clip-studio.md](clip-studio.md) |
| A touchscreen stops answering for a moment, or while the pen is near | `yoga-palm` switched it off (palm or pen rule) | by design; `yoga-palm watch --dry --log` shows why; thresholds in [palm.md](palm.md). Stuck: `yoga-palm reset` |
| Palm gets through / fingers get ignored | thresholds | [palm.md](palm.md), tuning |

## Keyboard dock and touchpad

| Symptom | Cause | Fix |
|---|---|---|
| `keyboard_position` file missing | stock driver rejects `83FF` | the DKMS copy ([install.md](install.md) step 3); `dkms status` |
| `modprobe: Module not found` right after a pacman upgrade | the running kernel's `/lib/modules` was replaced | reboot |
| Two `lenovo-yb9-kbdock` entries in `dkms status`, install fails "already installed" | hyphenated `PACKAGE_VERSION` | use `7.3.1.1`; `dkms remove` the mis-named one; the ansible task cleans up |
| Dock reads 0 for a second while sliding the keyboard | firmware reports "off" between positions | normal; consumers debounce 1.5 s |
| Dock unreadable for ~30 s after resume | WMI call fails while waking | the tracker keeps the last value |
| Virtual touchpad doesn't appear when the keyboard is docked | a manual override is set: `yoga-touchpad status` says `mode off (forced off)` (from `yoga-touchpad off`/`toggle` or **SUPER+ALT+t**) and it survives dock changes and postures | `yoga-touchpad auto` |
| Touchpad strip on the wrong side | digitiser origin | `[panel] invert_y = true` in `~/.config/yoga-touchpad.toml` |
| Touchpad fine in tests, moves cursor backwards on one panel | software vs hardware cursor | see "Cursor" above |

## Posture and sensors

| Symptom | Cause | Fix |
|---|---|---|
| Wrong posture, or "accelerometer frozen" in the log | sensors polled too fast (>3 Hz) freeze one | the daemon polls at 2.5 Hz; reloading `hid_sensor_accel_3d` (root) revives a frozen one |
| Posture jumps to "flat" right after resume | sensor hub wakes slowly | 10 s resume grace is built in |
| Book mode screens in the wrong order | which panel is left depends on the way the device is turned | `BOOK_BOTTOM_LEFT_WHEN = "right-up"` |
| Lid closed while folded back suspends | lid reads closed falsely when folded | fold guard holds the lid inhibitor (`LID_GLITCH_ABOVE`) |
| On-screen keyboard shown over a docked keyboard | dock read as 0 after resume | fixed (`DockTracker` keeps the last value) |

## Audio, power, Bluetooth

| Symptom | Cause | Fix |
|---|---|---|
| Thin, quiet, no bass; `tas2781 ... Firmware is NULL` | missing `TAS2XXX38F8.bin` | [platform.md](platform.md) |
| Bass there, then gone after a pause | amps lose their DSP program when power-saving | `Speaker Force Firmware Load` = on (`yoga-audio-levels.service`) |
| Volume slider only changes treble | hardware mixer controls `Speaker` only | WirePlumber `api.alsa.soft-mixer = true` |
| Keyboard won't reconnect / screens don't wake | Bluetooth controller autosuspends | udev rule `63-yoga-bluetooth.rules` |
| Bluetooth "blocked" | soft-blocked on a fresh install | `rfkill unblock bluetooth; bluetoothctl power on` |
| Low suspend residency (~2 %) | external hubs/monitors, BIOS `\_SB.PEPD` errors | measure bare; BIOS update is the real fix; there is no S3 |

## Boot and Secure Boot

| Symptom | Cause | Fix |
|---|---|---|
| "Access Denied" on the kernel with Secure Boot on | kernel unsigned (signing hook didn't run) | boot with Secure Boot off or Windows; `sudo yoga-sign-kernels`; check before every reboot: `--check` |
| rEFInd shows no kernel entry | rEFInd can't pair kernel and initramfs (name has no digits) | explicit entries from `setup.sh` (`yoga-linux.conf`) |
| `yoga-linux.conf` has the old command line | it's generated from `/proc/cmdline` | change the line, re-run `sudo yoga/secureboot/setup.sh` |
| Out-of-tree module "signature and/or required key missing" | Secure Boot off (no MOK keys loaded) | expected; with it on the module loads |

## Ansible

| Symptom | Cause | Fix |
|---|---|---|
| "failed at splitting arguments" in a `shell:` task | an unbalanced `'` in a comment inside the script | no apostrophes in free-form `shell:` text |
| Task fails after a kernel upgrade in the same run | `modprobe` for the old kernel | the playbook skips it when the module is loaded; reboot |
| `--syntax-check` passes but the run fails | included task files are not loaded by it | run it, or parse with `python -c shlex...` for shell blocks |

## Not a bug

- `ACPI BIOS Error ... AE_NOT_FOUND` (`NBIX`, `PNOT`, `_UPC` already exists): firmware noise.
- `UCSI: Invalid num_connectors 131`, `gamezone platform_profile probe failed`, `intel-hid ... power button`: harmless.
- Login screen: cursor upside down on the top panel is the hardware cursor (software cursor via greetd env, see login.md); touch works only because the greeter is pinned to the top panel (login.md).
- Login screen top panel upside down: remove the `transforms` line from `/var/lib/noctalia-greeter/greeter.toml` (ansible leaves it empty), then reboot.
- `noctalia-greeter`: `Atomic commit failed: Device or resource busy` on the eDPs: login still works.
- `intel_pstate`/`xe` loaded but `i915` drives the panels.

# Lenovo Yoga Book 9i (13IMU9) on Linux: Hyprland setup

Everything needed to run the **Yoga Book 9 13IMU9** (DMI product `83FF`, Core Ultra 7 155U, two 13.3"
OLED touchscreens, detachable Bluetooth keyboard) on **Arch/CachyOS with Hyprland**: both screens, touch
and pen, the keyboard dock, a virtual touchpad, posture (laptop/book/tent/tablet) handling, gestures,
an on-screen keyboard, working speakers, Secure Boot.

The code is in [`../../yoga/`](../../yoga/README.md); these pages say how to use it and what bites.
The long investigation log from the first bring-up (measurements, dead ends) is kept outside this repo.

## What you need

| | |
|---|---|
| Machine | Yoga Book 9 **13IMU9 / 83FF**. The Gen 8 (13IRU8) and Gen 10 (83KJ) differ: other IDs, other firmware |
| OS | Arch or CachyOS, **kernel 7.3 or newer** (the dock driver needs its WMI API; the 6.18 LTS cannot build it) |
| Compositor | **Hyprland 0.57.x configured in Lua** (`hyprland.lua`). The module uses `hl.*` APIs |
| Shell | Noctalia (bar, launcher, greeter). Other shells work if you drop `yoga/noctalia/host.toml` |
| Optional | Home Manager (links the scripts), Ansible (system side), rEFInd + shim (Secure Boot) |

## What you get

| Feature | Where | Doc |
|---|---|---|
| Both panels stacked, correct rotation, brightness on both | `yoga/hypr/` | [display.md](display.md) |
| Touch and pen on the right panel, pressure verified in Krita | `yoga/hypr/yoga.lua` | [display.md](display.md) |
| Keyboard dock detection (off / at hinge / at front edge) | DKMS module | [kbdock.md](kbdock.md) |
| Virtual touchpad on the bottom screen while docked | `yoga-touchpad` | [touchpad.md](touchpad.md) |
| Laptop / book / tent / tablet from the hinge angle | `yoga-posture` | [posture-daemon.md](posture-daemon.md), [state-machine.md](state-machine.md) |
| Gestures, on-screen keyboard, lock screen | hyprgrass, wvkbd | [touch-ux.md](touch-ux.md) |
| Palm rejection (palm or pen on a touchscreen switches it off) | `yoga-palm` | [palm.md](palm.md) |
| Speakers with bass, power, suspend, Bluetooth | ansible, WirePlumber | [platform.md](platform.md) |
| Secure Boot with rEFInd + shim | `yoga/secureboot/` | [secureboot.md](secureboot.md) |
| Greeter on both panels, login without the keyboard | ansible | [login.md](login.md) |
| IR face unlock (lock screen, login) | ansible + `howdy add` | [faceunlock.md](faceunlock.md) |
| Home-row mods on the Bluetooth keyboard | keyd | [homerow-mods.md](homerow-mods.md) |
| Steam, Clip Studio Paint (Wine) | pacman, Bottles | [steam.md](steam.md), [clip-studio.md](clip-studio.md) |

## Start here

1. [install.md](install.md): the order that works, with the root steps marked.
2. [troubleshooting.md](troubleshooting.md): symptom, cause, fix, for everything that went wrong the first time.
3. [hardware.md](hardware.md): the facts about the machine (IDs, sensors, devices) if you want to adapt it.

## The ten mistakes worth avoiding

1. **Setting `transform = 2` on the top panel *and* the kernel flag** `video=eDP-1:panel_orientation=upside_down`.
   Pick the kernel flag; Hyprland honours it and the panel is then `transform = 0`. Both = upside down again.
2. **Leaving the hardware cursor on.** With the flag, the hardware cursor plane is not rotated: the cursor is
   upside down and mirrored on the top panel. `cursor.no_hardware_cursors = 1` fixes it.
3. **A DKMS version with a hyphen** (`7.3.1-1`): pacman's dkms hook splits the directory name at the last
   hyphen and registers a second, wrongly named module. Use `7.3.1.1`.
4. **Polling the accelerometers faster than about 3 Hz.** The sensor hub freezes one of them. Poll at 2.5 Hz.
5. **Loading hyprgrass in the first minute after boot.** The touch controller drops off USB three times, 20 s
   apart. `yoga-touch load` waits it out and reloads once.
6. **Counting on Hyprland to rotate touch devices.** It doesn't; each touch/pen node needs its own transform
   (`touch.follows_panel`), and the top digitiser reports user-oriented coordinates.
7. **Missing amp firmware** (`TAS2XXX38F8.bin`): speakers are thin and quiet without it. Then turn on
   `Speaker Force Firmware Load` or the bass drops out, and use software volume or the slider only moves treble.
8. **Rebooting with an unsigned kernel under Secure Boot.** After any kernel update run
   `sudo yoga-sign-kernels --check` first.
9. **Trusting `modprobe` right after a kernel upgrade in the same session.** The running kernel's
   `/lib/modules` is gone until you reboot.
10. **Trying S3 suspend, `acpi=noirq` or `acpi_osi=!`.** The machine has only s2idle and it works; those
    options trade a working system for guesses.

## Status

Used daily: panels, touch, pen, dock, touchpad, postures, gestures, on-screen keyboard, Secure Boot.
Speaker firmware loads and bass works (by ear, one session). The lock screen is upright on the top panel with the
kernel flag; the greeter needs no extra transform (it double-flipped with one). Cold-boot gestures work. Not
verified: Steam games, Clip Studio Paint install, the greeter's touch input and top-panel orientation after the
`transforms` removal, deep suspend (hardware sleep is about 2 %), the ambient light sensor.

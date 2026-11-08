# Install, in the order that works

Steps marked **(root)** need sudo. Steps without it are user-level. Check each step before the next; most
failures later come from a skipped earlier one.

`ansible/yoga.yaml` does the root side on a host named **`yoga-linux`** (it is skipped on any other
hostname). Without that hostname, run the matching commands by hand, listed under each step.

## 0. Before you start

- Kernel 7.3+, Hyprland 0.57.x with a **Lua** config, Noctalia (or your own bar), `git`, `python-evdev`.
- Keep a second way in: an SSH server (`yoga_sshd`) or a USB keyboard. Touch and the Bluetooth keyboard are
  your only input otherwise, and a bad plugin can take touch away (`yoga-touch recover`, below).
- Bluetooth is soft-blocked on a fresh install: `rfkill unblock bluetooth; bluetoothctl power on`, then pair,
  `trust` and `connect` the keyboard (`Yoga Book 9 Bluetooth KB`). Trust it, or it will not reconnect at login.

## 1. Get the tree

```
git clone <your dotfiles>  ~/.dotfiles          # the yoga/ directory is self-contained
```

Everything Yoga-specific is under `yoga/`. It is only activated on a machine that looks like a Yoga
(DMI `Yoga Book 9`, or both panels' EDID descriptions, or the touch device name), so it is harmless elsewhere.

## 2. Kernel command line: rotate the top panel (root)

The top panel is mounted upside down. Tell the kernel, so the boot console and the framebuffer are upright
and Hyprland handles the rest:

```
video=eDP-1:panel_orientation=upside_down
```

- **rEFInd** (this setup): `yoga/secureboot/setup.sh` adds it to the generated entries (`\EFI\refind\yoga-linux.conf`).
- **GRUB**: append it to `GRUB_CMDLINE_LINUX_DEFAULT`, then `grub-mkconfig -o /boot/grub/grub.cfg` (ansible does this).
- `eDP-1` is the top panel (`Samsung Display Corp. 0x4167`). Connector names follow probe order; check with
  `hyprctl monitors all`.

Then in `yoga/hypr/config.lua` keep `panels.top.transform = 0`. **Do not** also rotate it in Hyprland.

## 3. Dock driver and udev (root)

The in-tree `lenovo-yb9-kbdock` only accepts the Gen 10 (`83KJ`). `yoga/kbdock-dkms/` is the same driver with
`83FF` added, built by DKMS (CachyOS kernels are clang: the Makefile adds `LLVM=1`).

```
sudo pacman -S --needed dkms linux-cachyos-headers
sudo cp -r yoga/kbdock-dkms /usr/src/lenovo-yb9-kbdock-7.3.1.1     # version = PACKAGE_VERSION, no hyphen
sudo dkms install lenovo-yb9-kbdock/7.3.1.1
sudo cp yoga/udev/6*.rules /etc/udev/rules.d/ && sudo udevadm control --reload-rules
sudo modprobe lenovo-yb9-kbdock
cat /sys/bus/wmi/devices/E7F300FA-*/keyboard_position      # 0 away, 1 near hinge, 2 at front edge
```

The udev rules keep the dock's tablet-mode switch away from libinput (only the posture daemon may report
tablet mode), give your user `/dev/uinput` and the touch node, and keep the Bluetooth controller out of USB
autosuspend (otherwise the sleeping keyboard cannot reconnect and the screens never wake).
Bump `PACKAGE_VERSION` whenever you change the `.c` file. The LTS kernel (6.18) cannot build the driver.

## 4. Hyprland side

1. Copy the loader from `.config/hypr/hyprland.lua` (search for `yoga`): it reads
   `$YOGA_DIR/hypr/config.lua`, and if the machine is a Yoga loads `hypr/yoga.lua`, which `hyprland.lua` then
   calls through hooks. Nothing breaks if the tree is missing.
2. Edit `yoga/hypr/config.lua`: panel descriptions, scale (2), the `docked` layout for your external monitors.
3. Put `render.send_content_type = false` and `render.cm_auto_hdr = 0` in your config (fullscreen on the OLED
   panels otherwise forces a visible re-modeset).
4. Reload and check: `hyprctl reload; hyprctl configerrors` (empty is good). Do not run
   `Hyprland --verify-config` on a live config: it executes it.

## 5. Scripts and services (Home Manager)

`yoga/nix/module.nix` links the scripts into `~/.local/bin`, the user services into
`~/.config/systemd/user`, the Noctalia host file and the WirePlumber rule. Import it and set `yoga.enable = true`.
New files must be `git add`ed before `home-manager switch --flake ~/.dotfiles`. Without Home Manager, symlink
`yoga/bin/*` and `yoga/systemd/*.service` yourself and `systemctl --user enable --now` the services.

Needs `python-evdev` (root: `pacman -S python-evdev`) and the `uinput` module loaded at boot.

## 6. Touch gestures and on-screen keyboard

```
sudo pacman -S --needed hyprpm cmake glm        # cmake: glm ships no pkg-config file, meson finds it via cmake
hyprpm update
hyprpm add https://github.com/horriblename/hyprgrass
hyprpm enable hyprgrass
yoga/wvkbd/build.sh                             # patched on-screen keyboard (Dvorak, hide clears Shift)
```

`yoga-touch load` (run by `hyprland.start`) loads the plugin. **Rebuild after every Hyprland update:**
`yoga-touch update`. Panic button: **SUPER+CTRL+SHIFT+Escape**, or `yoga-touch recover` from a TTY/SSH.

## 7. Audio (root once)

The speaker amps need `TAS2XXX38F8.bin`. It is not in `linux-firmware`. A copy extracted from the Windows
driver is in <https://github.com/andrewgodwin/lenovo-yoga-book-9> (`firmware/`; sha256 `2192a34b...fb763`).

```
sudo install -D -m 0644 TAS2XXX38F8.bin /usr/lib/firmware/updates/TAS2XXX38F8.bin     # or ansible -e yoga_amp_firmware=...
sudo reboot
```

Check `journalctl -b -k | grep tas2781` has no "firmware" errors. The WirePlumber rule (software volume) and
`yoga-audio-levels.service` (fixed hardware levels, force-load on) come with the Home Manager module.
Keep the volume moderate: the tuning is a community file.

## 8. Optional

- **Secure Boot** with rEFInd + shim: [secureboot.md](secureboot.md). Do it with Secure Boot **off** first.
- **Greeter on both panels**: [login.md](login.md) (ansible writes `greeter.toml`).
- **Home-row mods**: [homerow-mods.md](homerow-mods.md).
- **Steam / Clip Studio Paint**: [steam.md](steam.md), [clip-studio.md](clip-studio.md).
- **Charge limit**: `ansible-playbook setup.yaml -K -e yoga_charge_limit=true`.

## 9. Verify

```
yoga-platform-status              # amp, Bluetooth, power, suspend, light sensor, cameras
yoga-posture status               # angle, posture, layout, dock, sensors ok
yoga-touchpad status              # ON while the keyboard is docked
python3 -I yoga/bin/yoga_state.py show
dkms status                       # one lenovo-yb9-kbdock line, "installed" for the running kernel
```

Then, in person: dock the keyboard (touchpad notification, strip on the bottom screen), fold the lid back
(tablet layout), three-finger swipe sideways (workspaces), play a sound with the USB DAC unplugged.

## After kernel or Hyprland updates

- Kernel: `sudo yoga-sign-kernels --check` (if Secure Boot is on), `dkms status`, **reboot** before touching modules.
- Hyprland: `yoga-touch update` after logging in again.

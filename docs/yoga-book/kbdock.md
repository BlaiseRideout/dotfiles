# Keyboard dock detection

The firmware knows whether the magnetic Bluetooth keyboard is on the bottom screen and where. Linux 7.3 has a
driver for it (`lenovo-yb9-kbdock`) but it only accepts the Gen 10 (`83KJ`). The Gen 9 exposes the same WMI
objects, so the fix is one line: add `83FF` to the driver's DMI table.

## What is installed

| Piece | Where |
|---|---|
| Driver source (Linux 7.3.1 `yb9-kbdock.c` + `83FF`) | `yoga/kbdock-dkms/` (DKMS package `lenovo-yb9-kbdock`, installs to `updates/dkms`, shadows the in-tree module) |
| udev rules | `yoga/udev/61-yoga-dock-switch.rules` (`LIBINPUT_IGNORE_DEVICE=1` on the dock's tablet-mode switch, `/dev/input/yoga-kbdock` symlink) |
| Test script | `yoga/kbdock-test.sh` (root; loads the module and logs `keyboard_position` through dock/undock steps) |
| Upstream patch | `0001-lenovo-yb9-kbdock-add-83FF.patch` (tested on 83FF; not sent) |

Install steps: [install.md](install.md) section 3.

## Reading it

`/sys/bus/wmi/devices/E7F300FA-21CD-4003-ADAC-2696135982E6-*/keyboard_position`:

| Value | Keyboard |
|---|---|
| 0 | away, lifted, or between positions |
| 1 | docked near the hinge |
| 2 | docked at the front edge |

Sliding between 1 and 2 passes through 0 for about a second. **Debounce 0 for 1.5 s before treating it as
undocked.** Every read runs an ACPI method, so exactly one process (`yoga-posture`, 4 Hz) reads it and publishes
`$XDG_RUNTIME_DIR/yoga/state.json` for the others ([state-machine.md](state-machine.md)). Right after a resume
the read fails for ~30 s; the tracker keeps the last value.

## Keep the dock out of tablet mode

The driver reports `SW_TABLET_MODE` (detached = tablet). Tablet mode here follows the hinge, not the
keyboard, so the udev rule makes libinput ignore that switch and the posture daemon is the only source.

## Pitfalls

- **DKMS version without a hyphen** (`7.3.1.1`). The pacman dkms hook splits `/usr/src/<name>-<version>` at the
  last hyphen; `7.3.1-1` registered a second module `lenovo-yb9-kbdock-7.3.1`/`1`, and a later install failed
  with "already installed (unversioned module)". The ansible task removes that duplicate.
- **CachyOS kernels are clang/ThinLTO**: a gcc build is rejected; the Makefile adds `LLVM=1` when `.config` says clang.
- **Secure Boot**: the module must be signed with a trusted key ([secureboot.md](secureboot.md)); the dkms
  signing drop-in uses the same key as the kernel.
- **Kernels below 7.3** cannot build it (WMI `notify_new`/`min_event_size`); `BUILD_EXCLUSIVE_KERNEL` skips them.
- **Reboot after a kernel upgrade** before `modprobe`: the running kernel's module directory is gone.
- The hinge sensor's `keyboard` channel stays 0; it is no help.
- Retest after kernel updates; if upstream changes `yb9-kbdock.c`, diff it against our copy. When upstream adds
  `83FF`, remove the DKMS package.

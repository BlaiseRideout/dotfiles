# Login screen, bootloader, disk unlock

## Greeter

Login is `greetd` with `noctalia-greeter`, which runs its own wlroots compositor and draws a login view per
output. Left alone it lays out all outputs in one synthetic row and logs many `Atomic commit failed: Device or
resource busy` on the eDPs (login still works). `ansible/yoga.yaml` writes
`/var/lib/noctalia-greeter/greeter.toml` (owned by `greeter`) for the Yoga:

```toml
[output]
name = "eDP-1"                        # yoga_greeter_pin: only the top panel shows the login screen
scales = "eDP-1:2; eDP-2:2"
```

- Apply: `ansible-playbook setup.yaml -K`, then `sudo systemctl restart greetd` (ends the session) or reboot.
  Undo: delete `greeter.toml`, restart greetd.
- **No transform for the top panel.** The kernel flag `panel_orientation=upside_down` already flips it and the
  greeter's compositor honours it; adding `transforms = "eDP-1:180"` double-flips the login screen (seen).
  `yoga_greeter_transforms` is therefore empty.
- **Cursor upside down on the top panel:** the hardware cursor plane isn't rotated by the kernel flag. Ansible
  wraps the greetd command in `env WLR_NO_HARDWARE_CURSORS=1` (`/etc/greetd/config.toml`). Not yet verified on
  screen.
- **Touch on the login screen:** the greeter's compositor maps every touch device to the whole output layout
  and has no per-device setting; only a **pinned** output (`[output].name`) gets touch mapped to it. With both
  panels lit, taps landed in the wrong place. So the login screen is pinned to the top panel (the one in view with
  the keyboard docked) and the bottom panel stays dark: set `yoga_greeter_pin: ""` for both panels (touch then
  misfires). Not yet verified on screen: if taps on the top panel are still mirrored, tell whoever maintains this
  (the digitiser orientation vs. the greeter's transform is the open question).
- Touch taps elements but **doesn't move the cursor** on the login screen: the greeter takes wl_touch events directly
  and doesn't emulate a pointer. Expected, not a bug.
- The login screen has **no on-screen keyboard** (no layer-shell or virtual-keyboard support in its compositor).
  Keep the Bluetooth keyboard paired, or use a USB one.

## Keyboard at the login screen

The keyboard is Bluetooth. **Pair and trust it once** (`bluetoothctl pair/trust/connect`, no root) so it
reconnects before login; `bluetooth.service` and `AutoEnable=true` are set by the playbook. Keep the controller
out of USB autosuspend (`63-yoga-bluetooth.rules`) or the sleeping keyboard can't reconnect. Fallbacks if it
isn't connected: any wired USB keyboard, or SSH/TTY (Ctrl+Alt+F2 needs a keyboard).

## Bootloader

- **Secure Boot ON:** rEFInd via shim on the Windows ESP, not GRUB ([secureboot.md](secureboot.md)).
- Otherwise GRUB 2 (CachyOS) on the Linux ESP; `GRUB_DEFAULT=0`. Windows stays reachable from the firmware menu
  (`sudo efibootmgr -n <Windows entry> && reboot` for one boot).
- The firmware boot menu is Fn+F12 / the Novo button [assumed].
- Disk unlock: root is plain btrfs, no LUKS, so there is no passphrase prompt to type on a touch-only boot.
  If you add LUKS, plan TPM unlock: the Bluetooth keyboard is not available that early.

## If `Atomic commit failed` bothers you

Hypotheses in order: layout churn (fixed by the explicit `greeter.toml`), direct scan-out
(`WLR_SCENE_DISABLE_DIRECT_SCANOUT=1` in the greeter command), PSR (`i915.enable_psr=0`, costs battery), pinning
the greeter to one panel. Count: `journalctl -u greetd -b | grep -c 'Atomic commit failed'`. Hyprland itself shows
none on the same panels.

# Secure Boot with rEFInd + shim + a local key

## Chain of trust

```
firmware db (Microsoft UEFI CA)  ->  shimx64.efi          on the Windows ESP, \EFI\refind\
shim MOK list (your key)         ->  rEFInd (grubx64.efi) + btrfs_x64.efi driver, signed with the local key
rEFInd                           ->  /boot/vmlinuz-*       on the btrfs root, signed with the local key
kernel                           ->  DKMS modules (lenovo-yb9-kbdock), signed with the same key
```

One key pair (`/etc/refind.d/keys/refind_local.{key,crt}`, "Locally-generated rEFInd key") signs everything, and
its certificate is enrolled in shim's MOK once. The kernel does not lock itself down with Secure Boot on here
(`lockdown` stays `[none]`), so modules are checked by signature but not enforced.

## Why rEFInd and manual entries

GRUB would need a signed GRUB and a signed config story. rEFInd already exists on the Windows ESP, and an
EFI-stub kernel only needs its own signature. rEFInd pairs a kernel with its initramfs by the digits in the file
name; `vmlinuz-linux-cachyos` has none, so autodetection fails. `yoga/secureboot/setup.sh` therefore writes
explicit entries to `\EFI\refind\yoga-linux.conf` (one per `/boot/vmlinuz-*`, with microcode, its own initramfs and
**the running kernel's command line plus `video=eDP-1:panel_orientation=upside_down`**), included from
`refind.conf`. The `@` in `\@\boot\...` is the btrfs default subvolume.

## Order (everything with Secure Boot OFF; ON last)

```
sudo yoga/secureboot/setup.sh --dry-run        # as a user too: shows what it would do
sudo dd if=/dev/disk/by-partuuid/<windows-esp> of=~/win-esp.img bs=1M   # back up the Windows ESP (260 MB)
sudo yoga/secureboot/setup.sh                  # idempotent; installs sbsigntools/refind/mokutil, signs kernels,
                                               # installs the pacman hook, points DKMS at the key, writes entries
sudo efibootmgr                                # make the rEFInd-via-shim entry (shimx64.efi) first in BootOrder
reboot; pick "CachyOS (linux-cachyos)"         # still Secure Boot OFF; verify, then
firmware setup -> Secure Boot: Enabled         # (turn on "Allow Microsoft 3rd party UEFI CA" if the BIOS has it)
mokutil --sb-state; mokutil --test-key /etc/refind.d/keys/refind_local.cer
```
If `--test-key` says it isn't enrolled: `sudo mokutil --import /etc/refind.d/keys/refind_local.cer`, set a one-time
password, finish in MokManager at the next boot. Keep the GRUB entry (its way back) and Windows in `BootOrder`.

## After every kernel update

`/etc/pacman.d/hooks/99-sign-kernel.hook` runs `/usr/local/sbin/yoga-sign-kernels`, signing every
`/boot/vmlinuz-*` not signed by your key (atomic rename, mode 0644). **Always check before rebooting:**

```
sudo yoga-sign-kernels --check        # exit 0 = every kernel signed by our key
```
Why: mkinitcpio overwrites `/boot/vmlinuz-*` with an unsigned kernel and keeps no old copy; pacman only warns when
a PostTransaction hook fails; and if `sbsigntools` is missing the hook is skipped silently. Secure Boot ON +
unsigned kernel = "Access Denied" and the only way back is Secure Boot off (or Windows from the F12 menu).
Not covered by signatures: the initramfs and the kernel command line (the usual shim + rEFInd trade-off).

## If it will not boot

1. Firmware setup (Novo / Fn+F2), **turn Secure Boot off**: the GRUB entry boots as before.
2. Or boot **Windows Boot Manager** from the F12 menu (Microsoft-signed).
3. From Linux: `sudo yoga/secureboot/setup.sh --revert` (removes hook, DKMS drop-in, rEFInd block and entries,
   restores the previous btrfs driver; keys stay). Backups: `/root/yoga-secureboot-backup/<time>/` and
   `EFI\refind\refind.conf.bak-<time>` on the ESP.
4. Entry fails with Secure Boot **off**: a path problem (initrd/root); edit the options in rEFInd (F2/Insert).
5. With it on: shim "Security Violation" on rEFInd = cert not in MOK; kernel "Access Denied" = unsigned or wrong
   key (`--check`); no btrfs entries = driver unsigned; boots Windows directly = firmware didn't find shim
   (`efibootmgr`); a very old shim can be revoked in `dbx`: replace it with a current Fedora/Ubuntu `shimx64.efi`.

## Windows and BitLocker

Changing the Secure Boot state changes TPM PCR 7, which triggers a BitLocker recovery prompt if Windows uses it.
Have the recovery key, or suspend BitLocker, before toggling. (On the original machine Windows was plain NTFS.)

## Verified

Booted through shim with Secure Boot on; `mokutil --sb-state` enabled; the kernel and the dock module loaded with
no verification failures; `yoga-sign-kernels --check` passed; the pacman hook signed the real 7.3.3 kernel update
(both kernels signed by the local key, checked after it and again before a reboot).

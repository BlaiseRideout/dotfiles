#!/usr/bin/env bash
# Secure Boot setup for the Yoga Book 9i (hostname yoga-linux): rEFInd on the Windows
# ESP boots the CachyOS kernels from the btrfs root directly; everything in the chain is
# signed with the "Locally-generated rEFInd key" (refind_local), trusted through shim's MOK.
# Full explanation, order of steps and recovery: docs/yoga-book/secureboot.md
#
#   sudo yoga/secureboot/setup.sh --dry-run     show what would happen, change nothing
#   sudo yoga/secureboot/setup.sh               do it (idempotent; run again any time)
#   sudo yoga/secureboot/setup.sh --revert      undo the ESP/hook/DKMS changes (keys stay)
#
# Options
#   --dry-run          change nothing (the Windows ESP is only mounted read-only)
#   --key-src DIR      where refind_local.key/.crt are if /etc/refind.d/keys has none yet
#                      (default: look on the mounted Windows drive, then mount it read-only)
#   --hide-grub        hide the rEFInd menu entry for the GRUB on the CachyOS ESP (do this
#                      once Secure Boot is on: that GRUB is unsigned and cannot start then)
#   --hide-ubuntu      hide the stale \EFI\ubuntu entry on the Windows ESP in the rEFInd menu
#                      (only hides it: nothing is deleted; the firmware entry stays too)
#   --dkms-own-key     keep DKMS' own key (/var/lib/dkms/mok.*) instead of refind_local;
#                      you then must also `mokutil --import /var/lib/dkms/mok.pub`
#   --revert           remove what this script added (see the end of this file)
#
# What it does NOT do, on purpose: toggle Secure Boot, run refind-install, touch the
# firmware boot order or the MOK database, reboot, or write the private key anywhere
# except /etc/refind.d/keys (0600, root).
#
# Everything it changes outside this repo is listed in the summary it prints; the Windows
# ESP files it replaces are first copied to /root/yoga-secureboot-backup/<time>/.
set -euo pipefail

# ----- the facts this machine was set up with (verified 2026-11-06 unless noted) -------------
WIN_ESP_PARTUUID=2ea490bf-c083-4b14-8015-87155363e178   # nvme0n1p1, "EFI system partition", holds Windows + rEFInd
GRUB_ESP_PARTUUID=13613d4f-a859-44a1-82e3-f9b8b571c70a  # nvme0n1p6, the CachyOS ESP (GRUB), /boot/efi
WIN_DATA_PARTUUID=9cf64562-dcbf-4b3f-930c-c25a38f92ae7  # nvme0n1p3, Windows-SSD (NTFS), where the old keys were found
EXPECT_CERT_SHA1=01:55:87:57:99:7D:61:4F:61:1E:42:91:F5:2F:E0:30:9D:EA:95:26   # refind_local.crt

# Test hooks (used to try the script as a normal user inside `unshare -Urm` on a scratch tree):
#   SB_DEST=dir  prefix for everything written under /etc and /usr/local     ESP_DIR=dir  use this instead of mounting the ESP
#   SB_TEST=1    skip pacman and dkms     SB_BOOT=dir  instead of /boot     SB_REFIND_SHARE=dir  instead of /usr/share/refind
DEST=${SB_DEST:-}
BOOT=${SB_BOOT:-/boot}
RSHARE=${SB_REFIND_SHARE:-/usr/share/refind}
KEYDIR=$DEST/etc/refind.d/keys
KEY=$KEYDIR/refind_local.key
CRT=$KEYDIR/refind_local.crt
CER=$KEYDIR/refind_local.cer           # DER copy, the form MokManager / mokutil want
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BACKUP_ROOT=${SB_DEST:-}/root/yoga-secureboot-backup
MARK_BEGIN='# >>> yoga-secureboot (managed by yoga/secureboot/setup.sh, edit there) >>>'
MARK_END='# <<< yoga-secureboot <<<'

DRY=0; HIDE_GRUB=0; HIDE_UBUNTU=0; DKMS_OWN=0; REVERT=0; KEY_SRC=""
while [ $# -gt 0 ]; do
	case $1 in
		--dry-run) DRY=1 ;;
		--hide-grub) HIDE_GRUB=1 ;;
		--hide-ubuntu) HIDE_UBUNTU=1 ;;
		--dkms-own-key) DKMS_OWN=1 ;;
		--revert) REVERT=1 ;;
		--key-src) KEY_SRC=${2:?--key-src needs a directory}; shift ;;
		-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
	esac
	shift
done

# ----- helpers -------------------------------------------------------------------------------
say()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; WARNINGS+=("$*"); }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
WARNINGS=()
# run a changing command, or just show it in --dry-run
run() { if [ "$DRY" = 1 ]; then printf '    [dry-run] %s\n' "$*"; else "$@"; fi; }

TMPDIRS=(); MOUNTS=()
cleanup() {
	local m d
	for m in "${MOUNTS[@]:-}"; do [ -n "$m" ] && umount "$m" 2>/dev/null || true; done
	for d in "${TMPDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" || true; done
}
trap cleanup EXIT
mktmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/yoga-sb.XXXXXX"); TMPDIRS+=("$d"); echo "$d"; }

if [ "$(id -u)" != 0 ]; then
	[ "$DRY" = 1 ] || die "run as root (sudo $0 ...). --dry-run works without root but can only look at less."
	warn "not root: --dry-run will skip everything that needs root (mounting the ESP, reading /boot/vmlinuz hooks, ...)"
fi
IS_ROOT=0; [ "$(id -u)" = 0 ] && IS_ROOT=1

# ----- 0. sanity: right machine, right state -------------------------------------------------
say "0. Checking the machine"
[ "$(hostname)" = yoga-linux ] || die "this is for yoga-linux (hostname is $(hostname))"
[ -d /sys/firmware/efi ] || die "not booted in UEFI mode"
note "Secure Boot right now: $(od -An -tu1 -j4 -N1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | sed 's/ *1/ON/;s/ *0/off/')  (this script never changes it)"
[ "$REVERT" = 1 ] || command -v pacman >/dev/null || die "pacman not found"

# ----- revert --------------------------------------------------------------------------------
revert() {
	say "Reverting (keys in $KEYDIR and signed kernels are left alone: harmless)"
	run rm -f "$DEST/etc/pacman.d/hooks/99-sign-kernel.hook" "$DEST/etc/dkms/framework.conf.d/yoga-secureboot.conf"
	note "removed the pacman hook and the DKMS signing drop-in (rebuild DKMS modules to get DKMS' own key back: dkms autoinstall)"
	[ "$IS_ROOT" = 1 ] || { warn "not root, cannot touch the ESP"; return; }
	mount_win_esp
	local conf=$ESP/EFI/refind/refind.conf
	if [ -f "$conf" ] && grep -qF "$MARK_BEGIN" "$conf"; then
		strip_block "$conf"
		note "removed the managed block from refind.conf"
	fi
	run rm -f "$ESP/EFI/refind/yoga-linux.conf"
	# restore the driver this script replaced (oldest backup holds the original), else remove ours
	local first orig=""; first=$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | head -n1 || true)
	[ -n "$first" ] && [ -f "$first/drivers_x64/btrfs_x64.efi" ] && orig=$first/drivers_x64/btrfs_x64.efi
	if [ -n "$orig" ]; then run cp -f "$orig" "$ESP/EFI/refind/drivers_x64/btrfs_x64.efi"; note "restored the original btrfs driver from $orig"
	elif [ -f "$ESP/EFI/refind/drivers_x64/btrfs_x64.efi" ]; then
		run rm -f "$ESP/EFI/refind/drivers_x64/btrfs_x64.efi"; note "removed the btrfs driver this script installed"
	fi
	[ "$DRY" = 1 ] || sync
	say "Reverted. Secure Boot must be OFF (it is a firmware setting) for the old GRUB-first boot to work."
	exit 0
}

# ----- Windows ESP mount ---------------------------------------------------------------------
ESP=""
mount_win_esp() {
	[ -n "$ESP" ] && return
	if [ -n "${ESP_DIR:-}" ]; then ESP=$ESP_DIR; note "TEST: using $ESP instead of mounting the ESP"; return; fi
	local dev=/dev/disk/by-partuuid/$WIN_ESP_PARTUUID
	[ -b "$dev" ] || die "Windows ESP $dev not found"
	[ "$(blkid -s TYPE -o value "$dev")" = vfat ] || die "$dev is not vfat"
	local mp; mp=$(mktmp)
	local opts=rw; [ "$DRY" = 1 ] && opts=ro
	if command -v fsck.fat >/dev/null; then
		fsck.fat -n "$dev" >/dev/null 2>&1 || warn "fsck.fat -n reports problems on the Windows ESP (a Windows hibernate / fast-startup can leave it dirty). Boot Windows, fully shut down (shutdown /s /t 0), and run this again if the mount below misbehaves."
	fi
	mount -t vfat -o "$opts,shortname=winnt,umask=0077" "$dev" "$mp" || die "cannot mount the Windows ESP"
	MOUNTS+=("$mp"); ESP=$mp
	[ -f "$ESP/EFI/Microsoft/Boot/bootmgfw.efi" ] || die "$dev has no EFI/Microsoft/Boot/bootmgfw.efi: not the Windows ESP, refusing"
	[ -d "$ESP/EFI/refind" ] || die "$dev has no EFI/refind: rEFInd is not installed there, refusing"
	note "Windows ESP mounted ($opts) at $ESP, $(df -k --output=avail "$ESP" | tail -n1 | tr -d ' ') KiB free"
}

strip_block() { # strip_block FILE: delete the managed block (markers included) in place
	local f=$1 t; t=$(mktemp)
	awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 ~ /\r$/ {sub(/\r$/,"")} $0==b {skip=1} !skip {print} $0==e {skip=0}' "$f" > "$t"
	[ "$DRY" = 1 ] && { rm -f "$t"; return; }
	cat "$t" > "$f"; rm -f "$t"
}

[ "$REVERT" = 1 ] && revert

# ----- 1. packages ---------------------------------------------------------------------------
say "1. Packages: sbsigntools (sbsign/sbverify), refind (its btrfs driver + docs ONLY, never refind-install), mokutil"
missing=()
[ -n "${SB_TEST:-}" ] || for p in sbsigntools refind mokutil efibootmgr; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ "${#missing[@]}" -gt 0 ]; then
	note "missing: ${missing[*]}"
	if [ "$IS_ROOT" = 1 ]; then run pacman -S --needed --noconfirm "${missing[@]}"; else note "[dry-run, not root] pacman -S --needed ${missing[*]}"; fi
else
	note "all installed"
fi
if [ "$DRY" = 1 ] && [ "${#missing[@]}" -gt 0 ]; then
	warn "dry-run: ${missing[*]} not installed, so the signing/verification steps below are only described"
	CAN_SIGN=0
else
	CAN_SIGN=1
fi

# ----- 2. the key pair -----------------------------------------------------------------------
say "2. Signing key pair -> $KEYDIR"
src_key=""; src_crt=""
if [ -r "$KEY" ] && [ -r "$CRT" ] || { [ "$IS_ROOT" = 0 ] && [ -e "$KEY" ]; }; then
	src_key=$KEY; src_crt=$CRT; note "already installed"
else
	cands=()
	[ -n "$KEY_SRC" ] && cands+=("$KEY_SRC")
	for d in /run/media/*/Windows-SSD/Users/*/Downloads/refind-bin-*; do [ -d "$d" ] && cands+=("$d"); done
	if [ "${#cands[@]}" = 0 ] && [ "$IS_ROOT" = 1 ] && [ -b /dev/disk/by-partuuid/$WIN_DATA_PARTUUID ]; then
		wm=$(mktmp); if mount -o ro /dev/disk/by-partuuid/$WIN_DATA_PARTUUID "$wm" 2>/dev/null; then
			MOUNTS+=("$wm"); for d in "$wm"/Users/*/Downloads/refind-bin-*; do [ -d "$d" ] && cands+=("$d"); done; fi
	fi
	for d in "${cands[@]:-}"; do
		[ -r "$d/refind_local.key" ] && [ -r "$d/refind_local.crt" ] && { src_key=$d/refind_local.key; src_crt=$d/refind_local.crt; break; }
	done
	[ -n "$src_key" ] || die "refind_local.key / refind_local.crt not found (looked in /etc/refind.d/keys and the Windows drive). Pass --key-src DIR. Without the key nothing can be signed."
	note "found them in $(dirname "$src_key")"
fi
if [ -r "$src_key" ] && [ -r "$src_crt" ]; then
	if ! diff -q <(openssl x509 -in "$src_crt" -noout -pubkey) <(openssl pkey -in "$src_key" -pubout) >/dev/null 2>&1; then
		die "$src_key does not match $src_crt (or the key is passphrase-protected: dkms and this script need it unencrypted)"
	fi
	openssl x509 -in "$src_crt" -noout -checkend $((90*86400)) >/dev/null || warn "the certificate expires within 90 days"
	fp=$(openssl x509 -in "$src_crt" -noout -fingerprint -sha1 | cut -d= -f2)
	note "key matches cert; $(openssl x509 -in "$src_crt" -noout -subject), $(openssl x509 -in "$src_crt" -noout -enddate), SHA1 $fp"
	[ "$fp" = "$EXPECT_CERT_SHA1" ] || warn "certificate fingerprint is not the one this setup was written for ($EXPECT_CERT_SHA1): is it the key that is enrolled in MOK?"
	if [ "$src_key" != "$KEY" ]; then
		run install -d -m 0755 "$DEST/etc/refind.d"
		run install -d -m 0700 "$KEYDIR"
		run install -m 0600 "$src_key" "$KEY"
		run install -m 0644 "$src_crt" "$CRT"
	fi
	if [ -r "$CRT" ]; then run sh -c "openssl x509 -in '$CRT' -outform DER -out '$CER' && chmod 0644 '$CER'"; else note "[dry-run] would write the DER copy $CER"; fi
fi
SIGN_KEY=$KEY; SIGN_CRT=$CRT; [ -r "$KEY" ] || { SIGN_KEY=$src_key; SIGN_CRT=$src_crt; }
if [ "$IS_ROOT" = 1 ] && [ -r "$KEY" ]; then
	[ "$(stat -c %a "$KEY")" = 600 ] && [ "$(stat -c %U "$KEY")" = root ] || warn "$KEY is not root:0600"
fi

# ----- 3. install the signing script, hook, DKMS drop-in -------------------------------------
say "3. Kernel signing: /usr/local/sbin/yoga-sign-kernels + pacman hook (runs after mkinitcpio's 90- hook)"
SIGNER=$DEST/usr/local/sbin/yoga-sign-kernels
run install -D -m 0755 "$REPO/yoga-sign-kernels" "$SIGNER"
run install -D -m 0644 "$REPO/99-sign-kernel.hook" "$DEST/etc/pacman.d/hooks/99-sign-kernel.hook"
if [ "$IS_ROOT" = 1 ] && [ "$CAN_SIGN" = 1 ]; then
	say "3b. Signing the kernels now"
	if [ "$DRY" = 1 ]; then SB_KEY=$SIGN_KEY SB_CRT=$SIGN_CRT "$REPO/yoga-sign-kernels" --check || true
	else SB_KEY=$SIGN_KEY SB_CRT=$SIGN_CRT "$SIGNER"; fi
fi

# ----- 4. kernel modules (DKMS) --------------------------------------------------------------
say "4. DKMS module signing"
if [ "$DKMS_OWN" = 1 ]; then
	note "keeping DKMS' own key; MOK import needed: mokutil --import /var/lib/dkms/mok.pub"
	run rm -f "$DEST/etc/dkms/framework.conf.d/yoga-secureboot.conf"
elif [ -r "$CRT" ] || [ "$DRY" = 1 ]; then
	run install -D -m 0644 "$REPO/dkms-signing.conf" "$DEST/etc/dkms/framework.conf.d/yoga-secureboot.conf"
	if [ "$IS_ROOT" = 1 ] && command -v dkms >/dev/null && [ "$DRY" = 0 ] && [ -z "${SB_TEST:-}" ]; then
		# rebuild every installed module so it is re-signed with the new key
		while IFS= read -r line; do
			m=${line%%/*}; rest=${line#*/}; v=${rest%%,*}; k=$(echo "$rest" | cut -d, -f2 | tr -d ' ')
			echo "$line" | grep -q ': installed' || continue
			note "re-signing $m $v for $k"
			dkms remove -m "$m" -v "$v" -k "$k" >/dev/null 2>&1 || true
			dkms install -m "$m" -v "$v" -k "$k" || warn "dkms install of $m for $k failed"
		done < <(dkms status)
	else
		note "[dry-run/no dkms] would rebuild installed DKMS modules (lenovo-yb9-kbdock) so they are signed with refind_local"
	fi
fi

# ----- 5. Windows ESP: btrfs driver, rEFInd config ------------------------------------------
say "5. Windows ESP (rEFInd): signed btrfs driver + boot entries"
if [ "$IS_ROOT" = 0 ]; then
	note "[dry-run, not root] would mount PARTUUID $WIN_ESP_PARTUUID, back up refind.conf and drivers_x64/, install a signed btrfs_x64.efi, write EFI/refind/yoga-linux.conf and a managed block in refind.conf"
else
mount_win_esp
TS=$(date +%Y%m%d-%H%M%S); BK=$BACKUP_ROOT/$TS
if [ "$DRY" = 0 ]; then
	install -d -m 0700 "$BK/drivers_x64"
	cp -a "$ESP/EFI/refind/refind.conf" "$BK/refind.conf" 2>/dev/null || true
	cp -a "$ESP/EFI/refind/drivers_x64/." "$BK/drivers_x64/" 2>/dev/null || true
	cp -a "$ESP/EFI/refind/refind.conf" "$ESP/EFI/refind/refind.conf.bak-$TS" 2>/dev/null || true
	(cd "$ESP" && find EFI -maxdepth 3 | sort) > "$BK/esp-listing.txt"
	note "backups in $BK (and EFI/refind/refind.conf.bak-$TS on the ESP)"
fi

# 5a. btrfs driver, signed
SRC_DRV=$RSHARE/drivers_x64/btrfs_x64.efi
DST_DRV=$ESP/EFI/refind/drivers_x64/btrfs_x64.efi
if [ -f "$SRC_DRV" ] && [ "$CAN_SIGN" = 1 ]; then
	w=$(mktmp)
	sbsign --key "$SIGN_KEY" --cert "$SIGN_CRT" --output "$w/btrfs_x64.efi" "$SRC_DRV" >/dev/null 2>&1
	sbverify --cert "$SIGN_CRT" "$w/btrfs_x64.efi" >/dev/null 2>&1 || die "signed btrfs driver does not verify"
	if [ -f "$DST_DRV" ] && sbverify --cert "$SIGN_CRT" "$DST_DRV" >/dev/null 2>&1; then
		note "btrfs driver already on the ESP and signed by our key"
	else
		run install -d "$ESP/EFI/refind/drivers_x64"
		run install -m 0755 "$w/btrfs_x64.efi" "$DST_DRV"
		note "installed signed btrfs_x64.efi (refind package $(pacman -Q refind 2>/dev/null | cut -d" " -f2 || true); the rEFInd on the ESP must be the same 0.14.x)"
	fi
else
	warn "cannot sign the btrfs driver ($SRC_DRV or sbsigntools missing)"
fi
# the key as a file MokManager can enroll from disk, only needed should the MOK entry turn out to be missing
run install -D -m 0644 "$CER" "$ESP/EFI/refind/keys/refind_local.cer" 2>/dev/null || true

# 5b. kernel entries. Manual stanzas, NOT refind_linux.conf: rEFInd matches an initramfs to
#     a kernel by the digits in the file name, and "vmlinuz-linux-cachyos" has none, so it can
#     neither find initramfs-linux-cachyos.img nor tell the two kernels' initramfs apart.
root_src=$(findmnt -no SOURCE /)               # /dev/nvme0n1p5[/@]
root_dev=${root_src%%[*}; root_sub=${root_src#*[}; root_sub=${root_sub%]}; root_sub=${root_sub#/}
BTRFS_PARTUUID=""
for l in /dev/disk/by-partuuid/*; do [ "$(readlink -f "$l")" = "$(readlink -f "$root_dev")" ] && BTRFS_PARTUUID=${l##*/}; done
[ -n "$BTRFS_PARTUUID" ] || die "no PARTUUID for $root_dev"
# rEFInd's btrfs driver shows the DEFAULT subvolume as the volume root, same as GRUB does, so the
# kernel path has a "@" prefix when the default is the top level (which is what GRUB's BOOT_IMAGE=/@/boot/... says).
if dsub=$(btrfs subvolume get-default / 2>/dev/null); then
	default_sub=$(echo "$dsub" | sed -n 's/.*path \(.*\)$/\1/p'); default_sub=${default_sub#<FS_TREE>/}
	if [ -z "$default_sub" ]; then PFX=$root_sub                  # default subvolume = top level: rEFInd sees /@/boot
	elif [ "$default_sub" = "$root_sub" ]; then PFX=""            # default subvolume = @: rEFInd sees /boot
	else die "btrfs default subvolume '$default_sub' is neither the top level nor '$root_sub'; set PFX by hand in this script"; fi
else
	bi=$(tr ' ' '\n' < /proc/cmdline | sed -n 's/^BOOT_IMAGE=//p'); bi=${bi//\\//}
	[ -n "$bi" ] || die "cannot read the btrfs default subvolume and /proc/cmdline has no BOOT_IMAGE"
	d=${bi%/vmlinuz-*}; d=${d%/boot}; PFX=${d#/}; default_sub="(from BOOT_IMAGE=$bi)"
fi
BP=${PFX:+\\$PFX}\\boot                                      # \@\boot  (EFI path separators)
LP=${PFX:+/$PFX}/boot                                         # /@/boot
note "btrfs root partition $root_dev (PARTUUID $BTRFS_PARTUUID), / is subvol '${root_sub}', default subvol '${default_sub:-<top level>}' => rEFInd path $LP"
OPTS=${OPTIONS:-$(tr ' ' '\n' < /proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=' | paste -sd' ')}
# The top panel is mounted upside down: tell the kernel so the boot console and the framebuffer
# before Hyprland (plymouth, greeter fallback) are the right way up. Same word as GRUB's cmdline
# (ansible/yoga.yaml). Skipped if the command line already has a video=eDP-1 word.
# Check afterwards that Hyprland does not flip the panel a second time (docs/yoga-book/display.md §5).
YOGA_VIDEO_ARG=${YOGA_VIDEO_ARG-video=eDP-1:panel_orientation=upside_down}
if [ -n "$YOGA_VIDEO_ARG" ] && ! echo " $OPTS " | grep -q ' video=eDP-1:'; then OPTS="$OPTS $YOGA_VIDEO_ARG"; fi
echo " $OPTS " | grep -q ' root=' || die "no root= in /proc/cmdline"
echo " $OPTS " | grep -q ' rootflags=subvol=' || warn "kernel cmdline has no rootflags=subvol=...; fine only if the root is the btrfs default subvolume"
ucode=""
for u in intel-ucode amd-ucode; do [ -f "$BOOT/$u.img" ] && ucode="$ucode initrd=$BP\\$u.img"; done

inc=$(mktmp)/yoga-linux.conf
{
	echo "# Generated by yoga/secureboot/setup.sh, do not edit (re-run the script). Included from refind.conf."
	echo "# Manual stanzas because rEFInd cannot pair these kernels with their initramfs on its own."
	n=0
	for k in "$BOOT"/vmlinuz-*; do
		[ -f "$k" ] || continue
		pb=${k##*/vmlinuz-}
		if [ ! -f "$BOOT/initramfs-$pb.img" ]; then echo "# skipped $pb: no $BOOT/initramfs-$pb.img" >&2; continue; fi
		n=$((n+1))
		echo
		echo "menuentry \"CachyOS ($pb)\" {"
		echo "    icon /EFI/refind/icons/os_arch.png"
		echo "    volume $BTRFS_PARTUUID"
		echo "    loader $LP/vmlinuz-$pb"
		echo "    options \"$OPTS$ucode initrd=$BP\\initramfs-$pb.img\""
		if [ -f "$BOOT/initramfs-$pb-fallback.img" ]; then
			echo "    submenuentry \"Boot with the fallback initramfs\" {"
			echo "        options \"$OPTS$ucode initrd=$BP\\initramfs-$pb-fallback.img\""
			echo "    }"
		fi
		echo "    submenuentry \"Boot to a text console\" {"
		echo "        add_options \"systemd.unit=multi-user.target\""
		echo "    }"
		echo "}"
	done
	[ "$n" -gt 0 ] || { echo "no kernels with an initramfs found in $BOOT" >&2; exit 1; }
} > "$inc" || die "could not generate the kernel entries"
run install -m 0755 "$inc" "$ESP/EFI/refind/yoga-linux.conf"

# 5c. refind.conf: one managed block at the end (replaced on every run)
conf=$ESP/EFI/refind/refind.conf
[ -f "$conf" ] || die "$conf missing"
dont="$BTRFS_PARTUUID:@/boot,$BTRFS_PARTUUID:boot"       # rEFInd's own scan of the btrfs boot dir would add broken (initrd-less) duplicates
[ "$HIDE_GRUB" = 1 ] && dont="$dont,$GRUB_ESP_PARTUUID:EFI/cachyos"
[ "$HIDE_UBUNTU" = 1 ] && dont="$dont,$WIN_ESP_PARTUUID:EFI/ubuntu"
blk=$(mktmp)/block
{
	echo "$MARK_BEGIN"
	echo "dont_scan_dirs +,$dont"
	echo "default_selection \"CachyOS (linux-cachyos)\""
	echo "include yoga-linux.conf"
	echo "$MARK_END"
} > "$blk"
if [ "$DRY" = 1 ]; then
	note "[dry-run] would (re)write this block at the end of EFI/refind/refind.conf:"; sed 's/^/        /' "$blk"
	note "[dry-run] and write EFI/refind/yoga-linux.conf:"; sed 's/^/        /' "$inc"
else
	strip_block "$conf"
	sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$conf" 2>/dev/null || true     # drop trailing blank lines
	{ echo; cat "$blk"; } >> "$conf"
	grep -c . "$conf" >/dev/null || die "refind.conf ended up empty"
	sync
fi
if grep -nE '^\s*(scan_driver_dirs|scanfor)\b' "$conf" | grep -v '^\s*[0-9]*:\s*#' >/dev/null 2>&1; then
	warn "refind.conf sets scan_driver_dirs/scanfor: check it still loads EFI/refind/drivers_x64 and scans the ESPs"
fi

# ----- 6. verification summary --------------------------------------------------------------
say "6. Verification (sbverify against $SIGN_CRT)"
verify() { # verify FILE
	local f=$1
	if [ ! -f "$f" ]; then printf '    %-58s missing\n' "$f"; return; fi
	if sbverify --cert "$SIGN_CRT" "$f" >/dev/null 2>&1; then printf '    %-58s OK signed by refind_local\n' "${f#$ESP}"
	elif sbverify --list "$f" 2>&1 | grep -q 'No signature table'; then printf '    %-58s UNSIGNED\n' "${f#$ESP}"
	else printf '    %-58s signed by another key: %s\n' "${f#$ESP}" "$(sbverify --list "$f" 2>&1 | sed -n 's/^ - subject: //p' | head -n1)"; fi
}
if [ "$CAN_SIGN" = 1 ]; then
	for f in "$BOOT"/vmlinuz-*; do verify "$f"; done
	verify "$DST_DRV"
	for f in EFI/refind/grubx64.efi EFI/refind/refind_x64.efi; do verify "$ESP/$f"; done
	if [ -f "$ESP/EFI/refind/shimx64.efi" ]; then
		if sbverify --cert "$RSHARE/keys/microsoft-uefica-public.crt" "$ESP/EFI/refind/shimx64.efi" >/dev/null 2>&1; then
			printf '    %-58s OK signed by Microsoft UEFI CA 2011 (firmware db has it)\n' /EFI/refind/shimx64.efi
		else printf '    %-58s NOT verifiable against the Microsoft UEFI CA 2011 (2023-CA-only shim, or damaged): check by hand\n' /EFI/refind/shimx64.efi; fi
	fi
fi
for m in $(dkms status 2>/dev/null | sed -n 's|^\([^/]*\)/.*: installed.*|\1|p' | sort -u); do
	printf '    DKMS %-30s signer: %s\n' "$m" "$(modinfo -F signer "$(echo "$m" | tr - _)" 2>/dev/null || echo '(not loadable by name, check by hand)')"
done
if [ "$DRY" = 0 ]; then
	echo; echo "    EFI/refind/refind.conf, managed block:"
	awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{p=1} p{print "        " $0} $0==e{p=0}' "$conf"
fi
fi   # IS_ROOT

# ----- 7. what is left for a human -----------------------------------------------------------
bo=$(efibootmgr 2>/dev/null | sed -n 's/^BootOrder: //p')
neworder="0005,$(echo "$bo" | tr ',' '\n' | grep -vx 0005 | paste -sd,)"
say "7. Left for you (in this order; docs/yoga-book/secureboot.md has the reasoning)"
cat <<EOF
  1. MOK: refind_local.cer is already enrolled (you said so; mokutil cannot confirm it from this boot, which
     did not go through shim). Nothing to import. Step 4 checks it; if it turns out NOT to be there, queue it:
         sudo mokutil --import /etc/refind.d/keys/refind_local.cer      (one-time password, MokManager at next boot)
  2. Make rEFInd (via shim, Boot0005) the first thing the firmware tries, keeping GRUB second:
         sudo efibootmgr -o ${neworder:-0005,0008}
  3. Reboot (Secure Boot still OFF). rEFInd should appear. Pick "CachyOS (linux-cachyos)".
  4. Once booted that way, confirm the chain's trust data (all read-only):
         mokutil --sb-state            # SecureBoot disabled (still)
         mokutil --test-key /etc/refind.d/keys/refind_local.cer   # "is already enrolled"
         cat /proc/cmdline             # has initrd=..., and no BOOT_IMAGE=/@/boot (that was GRUB)
         sudo /usr/local/sbin/yoga-sign-kernels --check
  5. Only after 4 works: reboot into the firmware setup (Fn+F2 / Novo button), turn Secure Boot ON,
     boot rEFInd again. If you now want the dead GRUB entry out of the rEFInd menu:
         sudo $0 --hide-grub
  6. Check: mokutil --sb-state (enabled); cat /sys/kernel/security/lockdown; modinfo -F signer lenovo_yb9_kbdock;
     the keyboard dock still works. Windows: BitLocker recovery key at hand BEFORE step 5.
  Way back at any point: firmware setup -> Secure Boot OFF, then pick the GRUB entry (F12 menu "cachyos"),
  or Windows. Undo the files with:  sudo $0 --revert
EOF
if [ "${#WARNINGS[@]}" -gt 0 ]; then say "Warnings"; printf '  ! %s\n' "${WARNINGS[@]}"; fi
[ "$DRY" = 1 ] && say "dry-run: nothing was changed."
exit 0

# Platform: audio, Bluetooth, suspend, power

`yoga-platform-status` (from `yoga/bin/`, user level) prints amp firmware errors, Bluetooth, power profile,
battery, suspend counters, ambient light and cameras. `yoga-platform-status als` / `sleep` run just those.

## Audio: speakers and bass

Two paths: the Realtek ALC287 `Speaker` output (treble) and two TI **TAS2781** smart amps (bass, `DAC2`).
The kernel already has the quirk for this machine (SSID `17aa:38f8`) and binds `i2c-TIAS2781:00`. What is
missing is the amp's tuning file, which the driver asks for as `TAS2XXX38F8.bin`; without it the amps run at
reset defaults (thin, quiet, no bass) and the journal says `Firmware is NULL` at every playback.

**1. Firmware.** `linux-firmware` has files for other SSIDs, not `38F8`. A copy extracted from the Windows driver
is in <https://github.com/andrewgodwin/lenovo-yoga-book-9> (`firmware/TAS2XXX38F8.bin`, 36628 bytes, sha256
`2192a34b9b38b12c3a0d1c21c82dbff6374ceef61c1cb439141b9f58a66fb763`, TI licence file alongside). Do **not** reuse the
Gen 8 file (`TAS2XXX3881.bin`): different tuning can mis-set the speaker-protection limits.

```
sudo install -D -m 0644 TAS2XXX38F8.bin /usr/lib/firmware/updates/TAS2XXX38F8.bin
sudo reboot       # or unbind/bind i2c-TIAS2781:00 under /sys/bus/i2c/drivers/tas2781-hda
```
`updates/` is searched first and no package owns it, so `linux-firmware` upgrades keep it. Or run the playbook
with `-e yoga_amp_firmware=/path/TAS2XXX38F8.bin`. Check: `yoga-platform-status` says "no firmware errors",
`journalctl -b -k | grep tas2781` has no load errors, and `Speaker Program Id` / `Profile Id` ALSA controls exist.

**2. Make the bass stay: `Speaker Force Firmware Load` = on.** With it off the amps lose their DSP program
once they power-save, and the bass disappears even though the firmware loaded. It reloads the program at each
playback start (and resets `Speaker Analog Volume` to its default).

**3. Make the slider move both paths: software volume.** By default the volume control only drives `Speaker`
(treble). The WirePlumber rule `api.alsa.soft-mixer = true` for the card (`alsa_card.pci-0000_00_1f.3-*`) makes the slider
software, leaving the hardware levels fixed. Fix the balance with `Speaker Playback Volume` 81 and `DAC2 Playback
Volume` 87 (treble about 4.5 dB below the bass; a taste, not a measurement).

Both 2 and 3 are done at login by the Home Manager module: the WirePlumber rule
(`~/.config/wireplumber/wireplumber.conf.d/99-yoga-software-volume.conf`) and `yoga-audio-levels.service`
(sets force-load on, Speaker 81, DAC2 87; no root and no `alsactl store` needed). Restart WirePlumber after
adding the rule: `systemctl --user restart wireplumber`.

Keep the volume moderate: the calibration is community-made and untested near full volume. Other knobs if it is
still wrong: `Bass Speaker Playback Switch`, the `CALI_DATA` EFI variable (a `tas2781_apply_calib: V1 CRC error`
line would mean the calibration blob is rejected), `sof-firmware` (installed; the DSP boots).

## Bluetooth

Soft-blocked on a fresh install: `rfkill unblock bluetooth; bluetoothctl power on`. Pair, **trust** and connect
the keyboard. `bluetooth.service` enabled and `AutoEnable=true` (the playbook). The controller (Intel
`8087:0033`) must stay out of USB autosuspend (`63-yoga-bluetooth.rules`) or the sleeping keyboard cannot reconnect.
Dual-boot: pairing keys differ per OS; `yoga/bt-import-windows-keys.py` imports Windows' keys.

## Suspend

`s2idle` only: ACPI supports S0/S4/S5, so `mem_sleep_default=deep` cannot work. Suspend and resume work (many
cycles, including hours-long ones). Hardware-sleep residency is low (~2 % in the first measurement, with a hub,
monitors and a DAC attached). To measure bare: unplug everything, then
`yoga-platform-status sleep > before; sudo rtcwake -m freeze -s 300; yoga-platform-status sleep > after`; the
`hw_sleep` and `SLP_S0` lines should grow ~300 s. Then `/sys/kernel/debug/pmc_core/*` as root, or Intel's S0ix
selftest tool.

Firmware noise on every resume (`\_SB.PEPD._DSM`, `NBIX`) is a BIOS bug; a BIOS update is the only fix.
**Do not** apply: `acpi=noirq` (breaks suspend), `acpi_osi=!` (changes firmware behaviour, backlight and WMI;
only worth trying one-off if resume hangs), `pci=hpiosize=0` (no sign it's needed here). Right after resume the
sensor hub is slow: see [posture-daemon.md](posture-daemon.md).

## Power profiles and battery

- `power-profiles-daemon` works on the Ideapad `platform_profile` (low-power/balanced/performance); the playbook
  enables it at boot. No `tlp`/`tuned`/`thermald` next to it.
- Charge cap: `charge_types` (`Standard`/`Long_Life`) and `conservation_mode`, root-writable.
  `-e yoga_charge_limit=true` installs a service that sets `Long_Life`. Off by default.
- No battery-aware profile switching is wired.

## Other

- Ambient light sensor reads (raw x 0.001); low values, auto-brightness is not wired.
- IR camera: `/dev/video2` (GREY 640x360), emitter strobes by itself. Face unlock: [faceunlock.md](faceunlock.md).
- Shutdown LED and USB 3 after a cold boot: unchecked.

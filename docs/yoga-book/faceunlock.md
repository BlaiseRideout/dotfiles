# IR face unlock (Howdy Next)

Face unlock for the lock screen (hyprlock) and the login screen (greetd). The password always stays as the
fallback. Not for sudo (a deliberate choice: any process that triggers sudo would start a face scan).

## What was found

- The IR camera is `/dev/video2` (`Integrated Camera: Integrated I`, **GREY 640x360**, 15/30 fps); `video0` is
  the RGB one, `video1`/`video3` are metadata nodes. Only the RGB nodes get `/dev/v4l/by-id/` links, so Howdy is
  pointed at the by-path name `pci-0000:00:14.0-usb-0:8:1.2-video-index0`.
- **The IR emitter needs no enabling tool.** It strobes by itself while the node streams: roughly every 4th frame
  is lit (mean ~5-9, peak 251) and the rest are black (mean 1). `linux-enable-ir-emitter` is not needed. Howdy
  throws away dark frames (`[video] dark_threshold`) and keeps the lit ones; the default threshold of 75 is too
  strict for a strobing camera (see Tune / debug).
- Package: **`howdy-next`** (AUR, C++ rewrite, OpenCV 5 from the repo, no dlib/Python). Its models are fetched against pinned SHA-256 sums.
  `howdy download-models` fails on this network (see below), so `yoga/bin/yoga-howdy-models` does the same fetch. It is a small project (6 AUR votes), so this is a trust
  decision: you are installing a PAM module. The original `howdy` needs `python-dlib` from the AUR and
  Python-version patches.

## Install

```bash
# first run on a fresh machine: no PAM lines yet (nothing is enrolled)
cd ~/.dotfiles/ansible && ansible-playbook setup.yaml -K -e yoga_faceunlock_pam=false   # builds howdy-next, models, config
sudo howdy test        # live IR preview: your face should be boxed
sudo howdy add         # enrol a face (look at the camera; add 2-3 in different light)
ansible-playbook setup.yaml -K                                                       # now with the PAM lines (the default)
```

Keep a root shell open (`sudo -i`) while PAM is being changed. The PAM lines are `auth sufficient pam_howdy.so`,
inserted before the password line in `/etc/pam.d/hyprlock` and `/etc/pam.d/greetd`. Skip all of it with
`-e yoga_faceunlock=false`.

**Model download pitfall.** `howdy download-models` exits 1 with "Failed to download model" and no reason: the
`github.com/.../raw/...` link redirects git-LFS files to `media.githubusercontent.com`, which failed the TLS
handshake here ("wrong version number", over IPv4 and IPv6; `github.com` and `raw.githubusercontent.com` were
fine). `yoga-howdy-models` asks the git-LFS API for a `github-cloud.githubusercontent.com` link instead and checks
the SHA-256, so the files are the same ones. By hand: `sudo ~/.dotfiles/yoga/bin/yoga-howdy-models`.

## Behaviour and limits

- **Lock screen:** Howdy runs first, for up to `[video] timeout` seconds (4 by default). If it doesn't recognise
  you the password prompt appears only after that. Lower the timeout if that is annoying.
- **Login screen:** the packaged greeter (v1.7.0) only starts PAM when you press Enter with a password typed, so the
  camera stays dark until then. Upstream PR #183 adds `[auth] auto_start_pam`, which starts PAM when the password
  step appears (the camera lights up at once; a password typed meanwhile is queued and used if the face doesn't
  match). Until it ships, `yoga/greeter/build-greeter.sh` builds the pinned PR on top of upstream main (the compositor
  is unchanged between v1.7.0 and that main, so it pairs with the packaged one), ansible copies the result to `/usr/local/lib/yoga/noctalia-greeter` and
  greetd runs it (`NOCTALIA_GREETER_BIN` in `/etc/greetd/config.toml`). Needs `nlohmann-json` and `stb` (pacman,
  done by ansible). **Off by default** since it broke the login screen on 2026-11-07; opt in with
  `-e yoga_greeter_pr183=true`. **Cause of the 2026-11-07 failure (fixed, retry untested):** the binary looks for its
  assets next to itself and otherwise in the build tree under `$HOME`, which the `greeter` user can't read; it threw
  on start and greetd gave up after five restarts (black screen with a pointer, then an empty console). Ansible now
  links `/usr/local/lib/yoga/assets` to the packaged assets, and greetd starts the greeter through
  `yoga/greeter/noctalia-greeter-session`, a pre-flight that falls back to the packaged greeter (logged as
  `yoga-greeter` in the journal) if the binary, its assets or its libraries aren't usable as the greeter user.
  If it ever loops again: Ctrl+Alt+F2 or SSH, and `journalctl -b -u greetd -t noctalia-greeter`. Pins are in the script; a moved PR stops the build until you review it. **Once #183 is in the
  packaged greeter: delete the build tasks, the script and the `NOCTALIA_GREETER_BIN` part.**
  The greeter's status line ("Waiting for fingerprint reader..." in #183) is changed to "Looking for your face..." by a `sed` in the build script. A face login does not unlock the keyring (it needs the password), so apps asking for it prompt
  once. The greeter is pinned to the top panel; the camera is on the top bezel.
- Howdy skips the scan with the lid closed (`abort_if_lid_closed`) and over SSH (`abort_if_ssh`).
- IR is hard to fool with a photo or screen but it is still weaker than a password. Similar faces can pass.

## Tune / debug

- Config: `/etc/howdy/config.ini` (`[video] device_path`, `timeout`, `dark_threshold`; `[face] sface_threshold`
  sets how close a match must be: see `man howdy.ini` for its direction). `sudo howdy config` opens it.
- Quiet failures: `journalctl -b -t pam_howdy`.
- `howdy add` says "All frames were too dark; check dark_threshold": the default 75 rejects everything because
  the strobed IR frames are mostly black. Measured here: black frames 100 % in the darkest brightness bin, lit
  frames 91-98 %, so `dark_threshold = 99.5` (set by ansible). By hand: `sudo howdy config`, `[video]`.
- `howdy add` says "No face detected" with the camera streaming: the lit IR frames are dim and the face finder
  (Yunet) scores them 0.7-0.87 against a default cut-off of 0.8845. `[face] yunet_score_threshold = 0.65` (ansible)
  fixes it; this only decides "is that a face", not whose (that is `sface_threshold`). Sitting closer and looking
  straight in helps; frames are lit only every 4th frame.
- Every scan still fails with "no light": check the IR node still strobes
  (`v4l2-ctl -d /dev/video2 --stream-mmap --stream-count=20 --stream-to=ir.raw`, then look for frames with a high max).
- Turn it off without touching PAM: `[core] disabled = true`. Remove it: delete the `pam_howdy.so` lines from
  `/etc/pam.d/hyprlock` and `/etc/pam.d/greetd`.

## Status

Not yet tested on the hardware: the build, enrolment, the recognition rate in the dark, and the greetd path.

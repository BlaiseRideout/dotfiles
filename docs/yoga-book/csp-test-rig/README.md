# Clip Studio Paint test rig (unattended troubleshooting, 2026-11-08/09)

Synthetic input and probes used to reproduce CSP-under-Wine bugs without a human. Not installed anywhere; run from this
directory. Needs `python3` with `evdev` and `Pillow`/`numpy`, `grim`, `hyprctl`, and write access to `/dev/uinput`
(an ACL gives the user access). Details and findings: `../clip-studio.md`.

- `inputrig.py`: `Mouse` (clicks, wheel; **use `click(..., approach=True)`**: a teleported cursor click is ignored by the
  splash, which needs a real hover first), `Pen` (virtual tablet bound to eDP-1 with `hl.device`: strokes with pressure,
  `hold()` with sensor jitter, `lift()`, `leave()`), `Keyboard` + `type_dvorak()` (the compositor applies the user's Dvorak
  layout to uinput keys, so type through `type_dvorak`).
- `probe.py`: launch CSP, wait for the splash, glide-click, record success (`--approach`); `launch_traced` runs Wine
  directly with the bottle's environment (`csp-env.sh`, copied from `/proc/<wine pid>/environ`, minus `LD_LIBRARY_PATH`)
  and a filtered `WINEDEBUG` (Bottles hides Wine's stderr).
- `to_doodle.py` / `to_canvas_login.py`: get from a fresh launch to the canvas (retries the frozen splash).
- `qs_lib.py`, `qs_stack.py`, `qs_dismiss2.py`, `pill_template.png`: Quick Shape "Edit" pill detector (template matching) and
  the stacking / dismissal tests.
- `wvtest.py`, `webflags.py`, `shimtest.py`, `procvariant.py`: "Try for free" web-panel tests (WebView2 keep-alive log, flag matrix, shim recipes in a bottle copy, process-launch check).
- `tff.py`, `step.py`, `burst.py`: the tests behind the `dcomp` fix: launch traced and click Try for free; click a splash-relative
  point and screenshot the splash wherever it is; burst-capture after a click to catch blank frames.
- `csp.sh`: small helpers (launch, kill, window list, screenshot).

Scripts assume the splash and canvas layout of the Yoga Book's eDP-1 (1440x900 logical, scale 2) and the CSP-wine11 bottle.

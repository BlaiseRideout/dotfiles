# Clip Studio Paint under Wine (Bottles)

**Status: not installed or tried.** Celsys' installer and a licence/trial are needed. What is prepared and verified
is the platform underneath. Native pen pressure is confirmed (Krita on both screens), so any failure is Wine's.

## Prepared

- Bottles (Flatpak, per user): `flatpak --user install com.usebottles.bottles`, with read-only access to
  `~/Downloads`: `flatpak override --user --filesystem=xdg-download:ro com.usebottles.bottles`. **`~/Downloads`
  must exist.**
- `csp-bottle.sh wine11|baseline` (this directory) creates the bottles; `bottles-install-components.py` installs a
  named runner/DXVK/vkd3d. About 3-8 minutes and 1.5-3 GB.
- Bottle **`CSP-wine11`**: runner `kron4ek-wine-11.20-staging-amd64` (wow64), DXVK 2.5.2, vkd3d-proton 2.14.1,
  Windows 8.1, `sync: ntsync`, `wayland: false` (Xwayland), `cjkfonts`. Bottle **`CSP-baseline`**: `caffe-9.2`
  (Wine 9.2: probably too old for current CSP) for comparison.

## Verified underneath

Wine 11.20 runs in the Bottles sandbox; NTSync works (`/dev/ntsync`, `WINENTSYNC=1`); Vulkan sees the Arc iGPU;
Xwayland exposes both pens as XInput2 tablets with pressure, tilt and eraser valuators (`xinput list`).

## Install and test

```
cd ~/.dotfiles/docs/yoga-book
./csp-bottle.sh install ~/Downloads/<installer>.exe CSP-wine11     # or "Run executable" in Bottles
```
If the installer wants runtimes: Dependencies -> `vcredist2019`/`2022`, `corefonts`, `webview2` (for the
login/Hub panel). Add `CLIPStudioPaint.exe` as a program. Log in through CSP's own Help menu, not the Hub, if the
Hub is blank.

Pen: File -> Preferences -> Tablet. Try **Wintab** first (Xwayland has the valuators), then **Tablet PC**. Test
pressure on a soft brush, eraser end, tilt, cursor alignment, on **both panels**, and hover (does it draw while
hovering? A Hyprland/Wine bug reported on older versions). If neither gives pressure, check
`xinput test-xi2 --root | grep -E "RawMotion|Pressure"` over an X11 window: values changing there but not in CSP
means Wine/CSP; stuck at 0 means Hyprland/Xwayland.

## Things to expect

| Symptom | Try |
|---|---|
| Popups/menus close early, dialogs behind the window | Bottles virtual desktop (`virtual_desktop:true`, 2560x1600); a Hyprland float rule for class `clipstudiopaint.exe` |
| Lag resizing panels or switching brushes | hide brush/tool panels; toggle GPU acceleration |
| Blurry UI | Xwayland upscales; `custom_dpi:192` plus `xwayland { force_zero_scaling = true }` (global) |
| First start stalls | `WINEDLLOVERRIDES=mscoree=d` is set to skip the Mono dialog. Do not add `mshtml=d`: the setup's "Try for free" page needs Gecko and otherwise spins at ~70% CPU, looking frozen |
| White window on first launch | DXVK lacks `CreateSwapChainForComposition`, which CSP's Chromium panels use: `bottles-cli edit -b CSP-wine11 --params dxvk:false` |
| WebView2 | `webview2` dependency installer fails under Wine 11.20 (exit 2); not needed once DXVK is off |
| Wayland driver (`wayland:true`) | Wine's Wayland driver has no tablet support: expect no pressure |

Notes: CSP needs a recent Wine (11.19+ reported; 11.0 not enough); `bottles-cli new --runner X` silently falls
back to defaults instead of downloading X (the script installs components first); `bottles-cli edit --win win81`
hangs (the script uses `winecfg -v win81`). Fallbacks if pressure never works: Krita natively, a patched Wintab
(the CSP5-for-Wine / CSP_Linux projects), or CSP on Windows. Sources: github.com/taron-sys/CSP5-for-Wine,
github.com/SMB-Chan/CSP_Linux, WineHQ bugs 53052, 53642, 58463.

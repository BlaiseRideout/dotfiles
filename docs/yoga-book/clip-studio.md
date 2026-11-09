# Clip Studio Paint under Wine (Bottles)

**Status: installed in `CSP-wine11` (trial), pen pressure works** with the preload shim below. Native pen
pressure was confirmed first (Krita on both screens), so failures are on the Wine side.

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

Pen: File -> Preferences -> Tablet. **Wintab** is the mode that works (Tablet PC is greyed out under Wine);
set **operate with whole tablet** or x lands at half scale (see the table). Pressure also needs the
`xinput-no-close.so` shim, which `yoga/bin/clip-studio-paint` builds and preloads (table below). Test
pressure on a soft brush, eraser end, tilt, cursor alignment, on **both panels**, and hover (does it draw while
hovering? A Hyprland/Wine bug reported on older versions). If neither gives pressure, check
`xinput test-xi2 --root | grep -E "RawMotion|Pressure"` over an X11 window: values changing there but not in CSP
means Wine/CSP; stuck at 0 means Hyprland/Xwayland.

## Things to expect

| Symptom | Try |
|---|---|
| Popups/menus close early, dialogs behind the window | Bottles virtual desktop (`virtual_desktop:true`, 2560x1600); a Hyprland float rule for class `clipstudiopaint.exe` |
| Every menu/drop-down has its own border, shadow and blur | Wine popups are untitled floating XWayland windows: the `wine-popups-undecorated` rule in `.config/hypr/hyprland.lua` strips them (matches class `*.exe`, empty title). The same rule sets `no_focus`: those popups are managed windows, so with `follow_mouse = 1` Hyprland focused each popup as it opened and refocused the editor as the pointer left it, and Wine closed the menu on that focus loss (menus vanished on hover). A rule can't match on size, so every untitled Wine window is never focused; the splash, its login pages and typing still work |
| Ugly or mismatched UI text | `winetricks -q corefonts tahoma` in the bottle (Tahoma is Wine's "MS Shell Dlg"); `cjkfonts` for Japanese |
| Start-up splash ("Doodle mode" / "View plans") ignores clicks and hover; Tab does nothing, but CSP's own close button works | Seen after the Roaming `CELSYS`, `CELSYS_EN`, `CELSYSUserData` folders were wiped to retest sign-up. Focus and Xwayland input were fine (checked with `xinput test-xi2 --root`). Restoring the saved folders from before the wipe brought the splash back to life; why is not known. Keep a copy of those three folders before resetting them. The splash also freezes on some launches (about 1 in 3 in testing, including when started from the launcher): it draws but ignores clicks and Tab, no extra window is needed to cause it, and retrying clicks never helps, so quit it and relaunch. The window handler in `.config/hypr/hyprland.lua` gives the splash keyboard focus (so the close keybind works on it) and keeps all of CSP's windows on the editor's workspace, because Hyprland opens each new window on whichever workspace is active and switching workspaces during start-up split them |
| Strokes are constant width: no pressure, though Xwayland sends it (`xinput test-xi2 --root` shows pressure) and CSP's Tablet setting is Wintab | WineHQ bug 59772: wine-staging 11.x calls `XCloseDevice`, which deletes the XInput 1 event selection Wine's Wintab made, so Wintab logs one pen event (`WINEDEBUG=+wintab32`, `motion_event`) and then none. Fix: `docs/yoga-book/xinput-no-close.c`, a `LD_PRELOAD` shim that overrides `dlsym` (Wine looks `XCloseDevice` up with `dlsym` on a `dlopen`ed libXi, so a plain preloaded `XCloseDevice` is not picked up). The launcher builds it into the Flatpak's `data/csp-shims/` and passes it with `flatpak run --env=LD_PRELOAD=`. Bottles runs Wine with `Limit_System_Environment: true`, so the bottle's `Inherited_Environment_Variables` list needs `LD_PRELOAD` (the only bottle.yml change; started from Bottles' own UI there is no shim and no pressure). Bottles hides Wine's stderr, so to trace, run Wine directly with the env from `/proc/<wine pid>/environ`. Likely not needed on a non-staging runner |
| Pen x lands at about half the real position, y right | Xwayland's stylus axes span the whole X screen (2880x900, the two panels side by side) but Wine reports a 1440-px system width. Set CSP's Tablet preference to **operate with whole tablet**, which fixed it |
| Quick Shape launcher bars (Ellipse / Circle / polygon, "Edit") stay on the canvas after the hold-still shape appears; with the d2d1 patch below only the newest stays; dragging the bar's handle leaves a trail of copies; they flicker when the canvas moves and ignore touch; a normal stroke followed by moving the canvas clears them (repaint) | **Unsolved.** Works around it: turn Quick Shape / its launcher off in Preferences -> Tool (Config.sqlite `Tool`: `OptionQuickShapeEnabled`, `OptionQuickShapeLauncherEnabled`, `OptionQuickShapeTimeMillisecond` = 700 ms hold). Not caused by: pen events (same with the pressure shim off; Xwayland sends no XInput 1 proximity events, but that is not the cause), Hyprland windows, separate Wine windows (a `+win` trace shows no window creation or layered-window update while bars appear and move; CSP only makes a few 1x1 transparent layered helpers at start-up), or Windows 10 vs 8.1 (CSP alone as win81 behaves the same and warns about an unsupported OS). The bars are CSP's own overlay painted into its main window, and the old position is not repainted when they hide or move. Leads: Wine logs `d2d_device_context_DrawImage Unhandled composite mode 0xb` (BOUNDED_SOURCE_COPY) from the start-up window's animation, so that one is not the bars' trigger. `docs/yoga-book/wine-patches/d2d1-source-copy.patch` implements the copy modes (built from Wine 11.20 source, installed as the runner's `d2d1.dll`, original kept as `d2d1.dll.orig`); its effect on the bars is unproven, since the cases with and without it were not compared cleanly. CSP presents with `Present1` and dirty rects, which Wine ignores (`Ignored present parameters` in the log), so a swap-chain/back-buffer problem under wined3d (DXVK is off) is the next suspect |
| Lag resizing panels or switching brushes | hide brush/tool panels; toggle GPU acceleration |
| Blurry UI | Xwayland upscales; `custom_dpi:192` plus `xwayland { force_zero_scaling = true }` (global) |
| First start stalls | `WINEDLLOVERRIDES=mscoree=d` is set to skip the Mono dialog. Do not add `mshtml=d`: the setup's "Try for free" page needs Gecko and otherwise spins at ~70% CPU, looking frozen |
| White window on first launch | DXVK lacks `CreateSwapChainForComposition`, which CSP's Chromium panels use: `bottles-cli edit -b CSP-wine11 --params dxvk:false` |
| WebView2 | `webview2` dependency installer fails under Wine 11.20 (exit 2); not needed once DXVK is off |
| Wayland driver (`wayland:true`) | Wine's Wayland driver has no tablet support: expect no pressure |

## Next steps: Quick Shape bars that stay on screen

Do these in order; each changes one thing. Keep a backup of anything you touch in the bottle or runner, and note
which test you are on, because the start-up splash freezes on about 1 launch in 3 (more often under heavy
tracing): quit and relaunch rather than counting that as a result.

1. **Clean A/B of the `d2d1` patch.** Copy `d2d1.dll.orig` over `d2d1.dll` in
   `~/.var/app/com.usebottles.bottles/data/bottles/runners/kron4ek-wine-11.20-staging-amd64/lib/wine/x86_64-windows/`,
   start CSP from the launcher, do three hold-still strokes and note whether older bars stack up. Then put the
   patched DLL back (rebuild with `wine-patches/d2d1-source-copy.patch` on Wine 11.20 source; `nix shell
   nixpkgs#pkgsCross.mingwW64.stdenv.cc`, `configure --enable-win64 --without-x ...`, `make
   dlls/d2d1/x86_64-windows/d2d1.dll`, then `x86_64-w64-mingw32-strip`) and repeat. Keep it only if stacking
   differs; otherwise restore the original and delete the patch.
2. **Read how CSP presents.** Run Wine directly (Bottles hides Wine's stderr) with the bottle's environment copied
   from `/proc/<wine pid>/environ` (drop `LD_LIBRARY_PATH` and `WINE`), `LD_PRELOAD` set to the shim, and
   `WINEDEBUG=err+all,+dxgi` (add `+d3d` for Present). Look at the swap chain description (swap effect, buffer
   count), the `Present1` dirty rectangles and scroll rectangles, and whether the main window is one swap chain.
   If it is a flip-model chain with dirty rectangles, the bars fit a back buffer that is not preserved between
   presents: stale bars, trails and flicker, cleared by a full repaint.
3. **Try DXVK for CSP's main window only.** DXVK is off for the whole bottle because its panels need
   `CreateSwapChainForComposition`. Use per-application overrides (`HKCU\Software\Wine\AppDefaults\...\DllOverrides`,
   as `msedgewebview2.exe` already has for `dcomp`) rather than the bottle-wide setting, so WebView2 keeps wined3d.
   Test on a **duplicate** of the bottle (Bottles -> Duplicate), not the working one.
4. **Compare another runner on a duplicate bottle:** a non-staging Wine 11.x (the staging patch behind the
   pressure bug may touch other things), or Proton/GE. The pressure shim is only needed on staging.
5. **If a cause is found**, check Wine's bug tracker and file one with the trace (CSP's Quick Shape launcher over
   Wine 11.20). The notes above already cover what is ruled out.
6. **Fallback:** Preferences -> Tool -> turn off Quick Shape or its launcher (close CSP first if editing
   `Config.sqlite`: `Tool.OptionQuickShapeEnabled` and `OptionQuickShapeLauncherEnabled`).

Notes: CSP needs a recent Wine (11.19+ reported; 11.0 not enough); `bottles-cli new --runner X` silently falls
back to defaults instead of downloading X (the script installs components first); `bottles-cli edit --win win81`
hangs (the script uses `winecfg -v win81`). Fallbacks if pressure never works: Krita natively, a patched Wintab
(the CSP5-for-Wine / CSP_Linux projects), or CSP on Windows. Sources: github.com/taron-sys/CSP5-for-Wine,
github.com/SMB-Chan/CSP_Linux, WineHQ bugs 53052, 53642, 58463.

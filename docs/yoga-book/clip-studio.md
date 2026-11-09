# Clip Studio Paint under Wine (Bottles)

**Status: installed in `CSP-wine11` (trial), pen pressure works** with the preload shim below. Native pen
pressure was confirmed first (Krita on both screens), so failures are on the Wine side. **The in-app web pages (Try for
free / sign-up panel, the welcome dialog) work since 2026-11-09** with the patched `dcomp.dll` (section below).

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
| Quick Shape launcher bars (Ellipse / Circle / polygon, "Edit") stay on the canvas after the hold-still shape appears; with the d2d1 patch below only the newest stays; dragging the bar's handle leaves a trail of copies; they flicker when the canvas moves and ignore touch; a normal stroke followed by moving the canvas clears them (repaint) | **Unsolved.** Works around it: turn Quick Shape / its launcher off in Preferences -> Tool (Config.sqlite `Tool`: `OptionQuickShapeEnabled`, `OptionQuickShapeLauncherEnabled`, `OptionQuickShapeTimeMillisecond` = 700 ms hold). Not caused by: pen events (same with the pressure shim off; Xwayland sends no XInput 1 proximity events, but that is not the cause), Hyprland windows, separate Wine windows (a `+win` trace shows no window creation or layered-window update while bars appear and move; CSP only makes a few 1x1 transparent layered helpers at start-up), or Windows 10 vs 8.1 (CSP alone as win81 behaves the same and warns about an unsupported OS). The bars are CSP's own overlay painted into its main window, and the old position is not repainted when they hide or move. Leads: Wine logs `d2d_device_context_DrawImage Unhandled composite mode 0xb` (BOUNDED_SOURCE_COPY) from the start-up window's animation, so that one is not the bars' trigger. `docs/yoga-book/wine-patches/d2d1-source-copy.patch` implements the copy modes (built from Wine 11.20 source, installed as the runner's `d2d1.dll`, original kept as `d2d1.dll.orig`; **keep it installed**); **Verified with the synthetic pen (A/B, three hold-stroke tests):** with the original `d2d1.dll` a second pill appears and the old one stays (they stack); with the patched one the old pill is cleared when the next appears, so only the newest remains. Remaining: that newest pill is never dismissed by time (tested up to 30 s), a plain pen stroke, pen hover away, the pen leaving sensor range, Escape, or a mouse wheel scroll; **only panning the canvas (space + drag) clears it**, as reported. It is not a DirectComposition visual (a `+dcomp` trace of a pill appearing shows only `Commit`), so it is drawn into an existing overlay surface. Untested idea: the hide may be driven by a Wintab proximity-out that Wine never receives (Xwayland's stylus has no proximity class, no XInput 1 `ProximityIn/Out`), which a shim could synthesise. It did **not** fix the start-up splash's "Try for free" button (tested on a clean appdata, patched DLL loaded; CSP sat at about 57% CPU, and an earlier trace of the idle splash showed thousands of `dxgi_surface_GetDC` / d2d GDI-interop `CopyFromBitmap` calls, so the splash may be in a busy render loop that starves input). CSP presents with `Present1` and dirty rects, which Wine ignores (`Ignored present parameters` in the log), so a swap-chain/back-buffer problem under wined3d (DXVK is off) is the next suspect |
| Lag resizing panels or switching brushes | hide brush/tool panels; toggle GPU acceleration |
| Blurry UI | Xwayland upscales; `custom_dpi:192` plus `xwayland { force_zero_scaling = true }` (global) |
| First start stalls | `WINEDLLOVERRIDES=mscoree=d` is set to skip the Mono dialog. Do not add `mshtml=d`: the setup's "Try for free" page needs Gecko and otherwise spins at ~70% CPU, looking frozen |
| White window on first launch | DXVK lacks `CreateSwapChainForComposition`, which CSP's Chromium panels use: `bottles-cli edit -b CSP-wine11 --params dxvk:false` |
| WebView2 | `webview2` dependency installer fails under Wine 11.20 (exit 2); not needed once DXVK is off |
| Wayland driver (`wayland:true`) | Wine's Wayland driver has no tablet support: expect no pressure |

## Known-good configuration (2026-11-08, before the unattended troubleshooting session)

Pen pressure and the pen offset work; the Quick Shape bars, the "Try for free" button and the splash freeze do not.
Snapshot of everything below: `~/.var/app/com.usebottles.bottles/data/bottles/csp-known-good-20261108/` (reflink
copies of the whole bottle and the runner, the shim, a `MANIFEST.sha256`); **`./restore.sh` there puts it all back**
and moves the modified copies aside. The Roaming appdata (logged in, trial) is in the bottle snapshot and in
`csp-appdata-before-d2d1-trial-test-20261108/`.

- Runner `kron4ek-wine-11.20-staging-amd64`, with `d2d1.dll` replaced by the patched build
  (`wine-patches/d2d1-source-copy.patch`; original is `d2d1.dll.orig`, sha in the manifest). Effect unproven.
  (Since 2026-11-09 `dcomp.dll` is patched too and the bottle's WebView2 settings changed: see the next section. The
  snapshot and its `restore.sh` are the state before that.)
- `bottle.yml`: `Windows: win10`; `dxvk: false`, `vkd3d: true`, `renderer: gl`, `sync: ntsync`, `wayland: false`,
  `custom_dpi: 96`, `virtual_desktop: false`; `Limit_System_Environment: true` with `LD_PRELOAD` in
  `Inherited_Environment_Variables`; `Environment_Variables`: `DXVK_CONFIG_FILE`, `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`
  (`--no-sandbox --in-process-gpu --enable-logging --v=0 ...`), `WINEDEBUG: -all`, `WINEDLLOVERRIDES: mscoree=d`.
  Installed: vcredist2022, gecko, mono, core fonts.
- Registry (user.reg): `AppDefaults\msedgewebview2.exe\DllOverrides` `dcomp=native,builtin`; global `d3d10core`,
  `d3d11` etc. `native,builtin` (Bottles leaves the DXVK ones; Bottles' launch env forces `d3d8-d3d11,dxgi=b`).
- Launcher `yoga/bin/clip-studio-paint` (commit 8c7990e) builds `xinput-no-close.so` and passes `LD_PRELOAD`.
- CSP: Tablet = Wintab, "operate with whole tablet"; Quick Shape on, launcher on, 700 ms.
- Launch recipe Bottles uses (copy from `/proc/<wine pid>/environ`): `WINEARCH=win64`, `WINEPREFIX`, `WINENTSYNC=1`,
  `WINEDLLOVERRIDES=mscoree=d;d3d8,d3d9,d3d10core,d3d11,dxgi=b;winemenubuilder=''`, `DXVK_CONFIG_FILE`, `WEBVIEW2_*`,
  `LD_PRELOAD`.

## Sessions (accounts): `csp-profiles`

A session is the three folders `CELSYS`, `CELSYS_EN` and `CELSYSUserData` in the bottle's
`drive_c/users/blaise/AppData/Roaming` (login, licence state, preferences, workspace). `csp-profiles`
(`yoga/bin/csp-profiles`, a terminal menu) keeps several and moves the chosen one into the bottle; the others wait in
`~/.var/app/com.usebottles.bottles/data/bottles/csp-profiles/CSP-wine11/<id>/`. **n** makes an empty one (CSP then
runs its first-time setup, logged out) for when a session breaks, **d** copies one as a backup, **x** moves one to
`.trash/` there. It shows the account of each from `LoginInfo.sqlite`. Also `csp-profiles list | switch NAME |
new LABEL | add LABEL DIR`. Set up on 2026-11-09 with `blaise@blaiserideout.com`, `blaiserideout@gmail.com` (from
`csp-appdata-account1-after-menu-test-20261108`) and a logged-out fresh one (from
`csp-appdata-fresh-instance-d2d1-test-20261108`); the older `csp-appdata-*` folders are untouched.

## In-app web pages (Try for free, welcome dialog): fixed 2026-11-09 with a patched `dcomp.dll`

CSP 5.1.5 hosts these WebView2 pages through a DirectComposition visual shared between CSP and the browser process,
which wine-staging 11.20 only stubs. `wine-patches/dcomp-shared-visual.patch` implements it (the patch's header says
how it works and how to build it). What is installed:

- **Runner:** `lib/wine/x86_64-windows/dcomp.dll` of `kron4ek-wine-11.20-staging-amd64` is the patched build; the
  original is `dcomp.dll.orig` next to it (copy it back to undo).
- **Bottle:** `user.reg` `AppDefaults\msedgewebview2.exe\DllOverrides` `dcomp` is `builtin` (was `native,builtin`, which
  loaded the CSPenguin shim still lying in the WebView2 folder; that shim is no longer used). `bottle.yml`
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` is `--no-sandbox --in-process-gpu` (**`--in-process-gpu` is required** by the
  patch; the logging flags are gone because `--enable-logging` opened a console window). The files from before are
  `user.reg.before-dcomp-20261109` and `bottle.yml.before-dcomp-20261109` in the bottle.
- **Hyprland:** WebView2 keeps the browser's real windows open but fully transparent (`_NET_WM_WINDOW_OPACITY = 0`), a
  hint Hyprland ignores, so they covered the page as black boxes. The `window.open` handler in
  `.config/hypr/hyprland.lua` moves them to the never-shown `special:wine-hidden` workspace
  (`.config/hypr/x-all-transparent.sh`, needs `xprop`). CSP forwards mouse input to the page itself.

Verified in a logged-out copy of the bottle: Try for free shows the three cards (30 days free, 3 months free, Doodle
mode) over the splash art, they react to clicks, "Get started for free" leads to the native log-in / Create account
page, Doodle mode's "Try now" opens the editor, and the welcome dialog ("July 2026 Update") draws. **Not tested:**
logging in after "Get started for free" (it would have spent the trial on a throwaway account), typing into a web page,
and web pop-up windows. Seen once: the panel drew empty for a few seconds after the first click on a card.
Still there with or without the patch: white 640x400 boxes (CSP's and the Hub's WebView host windows) on some launches.
"View plans" opens the Clip Studio hub (`CLIPStudio.exe`), which now draws its frame instead of a blank window.

How the protocol goes, for the next Wine update: the host calls `QueryInterface` for `{d14b6158-...}`
(`IDCompositionDesktopDevicePartner`), `CreateSharedResource(IID_IDCompositionVisual)` and `OpenSharedResourceHandle`;
the browser gets the duplicated handle and calls the third partner method with `IID_IDCompositionTarget`, then
`CreateScaleTransform` and `CreateSurfaceFromHwnd` on its own (transparent, layered) top-level window, whose content the
GPU thread composes with ordinary `CreateTargetForHwnd` targets on a child window.
`COREWEBVIEW2_FORCED_HOSTING_MODE=COREWEBVIEW2_HOSTING_MODE_WINDOW_TO_WINDOW` does not avoid this.

### Findings before the fix (2026-11-08/09)

The click works (about 5 launches in 6; the sixth is the splash freeze below). The splash switches to a layout
with **Back** and **Continue offline** and an empty right-hand panel. That has been the case since CSP was installed
under Wine, so today's workarounds are not the cause.
- **Ruled out by A/B:** the pressure shim (`LD_PRELOAD`), the patched `d2d1.dll` (same result with the original
  restored), and Chromium flags in `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`: `--disable-gpu`,
  `--disable-gpu-compositing`, `--disable-direct-composition`, `--disable-features=DirectComposition,...`.
  DXVK for `msedgewebview2.exe` only (registry `AppDefaults` overrides on a copy of the bottle, Wine's own D3D for CSP)
  also leaves it blank.
- **What happens:** `WebView2` starts (browser, renderers, network and storage utilities) as soon as the click lands.
  `wv2.log` (`--v=1`) shows two embedded browser instances started about 0.2 s apart; the first is shut down within
  about 0.2 s (`RemoveKeepAlive(kBrowserWindow)`), the second sometimes lives on but nothing is ever drawn, and
  there is no request to any Celsys page (the net log only has `config.edge.skype.com`, and DNS in the sandbox is fine).
  CSP itself reaches Celsys fine (`abt.clip-studio.com/api/variant?...startup_activation_transition` returns 200).
- **Probable cause:** right after a good click Wine logs (only then; never in runs where the click is lost)
  `dcomp:device_QueryInterface Returning undocumented interface {d14b6158-c3fa-4bce-9c1f-b61d8665eab0}` and twice
  `dcomp:desktop_device_CreateSharedResource ..., riid {4d93059d-097b-4651-9a60-f0f25116e2f3} ... stub!`
  (`4d93059d-...` is `IDCompositionVisual`). Wine-staging's `dcomp` (device, visual and target stubs, `Commit`
  semi-stub) has no `CreateSharedResource`, which WebView2's composition hosting needs to share a visual with its
  browser process, so the web view is abandoned. Vanilla Wine's `dcomp` is only `E_NOTIMPL` stubs, so the fix has to
  come from staging's `dcomp` patch set plus an implementation of that call (and something that actually presents the
  browser's output), or from the `dcomp.dll` shim of CSP5-for-Wine / CSP_Linux loaded in **CSP's own process** with
  DXVK. An earlier attempt (shim in every process, DXVK on) left CSP's own window white or stopped WebView2 starting,
  so that combination still needs a careful test.
- **Shim recipes tried (2026-11-09), in a reflink copy of the bottle with the appdata cleared:** CSP5-for-Wine
  (DXVK for every process, the patched `dcomp.dll` in `system32`, the CSP folder and the WebView2 folder, global
  `dcomp=native,builtin`, its WebView2 flags, dxvk.conf) and CSP_Linux (shim in `system32` only, `CLIPStudioPaint.exe`
  win81, `msedgewebview2.exe` win7, esync/fsync, `--disable-gpu-compositing`). Both repos use the same shim: upstream
  CSPenguin-Installer `dcomp_csp.cpp` (pinned commit 868d022, sha256 `e516fd33...`) plus csp5's `dcomp-csp-linux.patch`
  ("csp-linux rev2"); it builds with the nix mingw toolchain (`-static`, `-L<mcfgthread lib dir>`) to the same size as the
  `dcomp.dll` already in the WebView2 folder. Neither starts the sign-up panel: **no `msedgewebview2.exe` process is ever
  created after the click** when the shim is in CSP's process (0 processes; shim in CSP + Wine's own D3D also gives 0;
  Wine's own `dcomp` + DXVK gives 12), and the panel stays blank. Adding the private ordinals (1017-1042) to the shim as
  logging stubs changed nothing (CSP never calls them). Upstream's shims target the Hub (`CLIPStudio.exe`) and CSP 5.0.4/5.1.4;
  the 5.1.5 editor splash hosts WebView2 in a different way (it needs `IDCompositionDeviceUnknown::CreateSharedResource` /
  `OpenSharedResourceHandle`, and staging's `Unknown1(handle, iid, out)` on the browser side, i.e. a visual shared **across
  processes**, which staging only does within one process: `DCompositionCreateSharedVisualHandle` returns a fake `0xdeadbee1`).
  Fixing it properly means implementing that cross-process shared visual (a Wine `dcomp` patch for the host side plus the
  matching browser-side handling in the shim, which would map the handle to the host's window and draw there).
- **What works today:** the splash's **Log in** page is native (not WebView2): email, password, Apple and Google
  buttons, and **Create account**, which opens `accounts.clip-studio.com/app/register` in the default browser
  (a normal web sign-up with a reCAPTCHA badge). **Tested end to end with a disposable mailbox (mail.tm API):** Send
  email, the "Register your new Clip Studio account" mail arrives within seconds (link
  `accounts.clip-studio.com/app/register/profile?token=...&device_env=win_pc`; open it with `xdg-open`), the profile
  page wants a password and a birthdate, then "Sign up completed" with an "Open Clip Studio Paint" button (a custom URL
  scheme; the host has no handler for it). Logging into CSP with that account through the native login form works, but
  the splash then shows "Plan list: No plans found." with only "Activation code" and "Serial number", so **a web-created
  account does not start the trial** and the in-app "Try for free" panel is the only route. A trial-capable flow would
  need that WebView2 panel (or whatever the `clipstudio:` handoff does) to work.
- **Virtual keyboard note:** the compositor applies the user's Dvorak layout to a uinput keyboard, so typing needs
  the key positions that give each character in Dvorak (typing `csp...` with QWERTY codes arrived as `jol...`).

## Other trial / first-run bugs seen (2026-11-09)

- After a login, the one-time **"Setting up... Please do not launch other Clip Studio applications"** dialog appears over a
  still-blank main window, and a **blank white welcome dialog** (486x727, a WebView2 panel that never draws) sits on top of the
  canvas until its X is clicked.
- On the "Try for free" panel, **Continue offline** does nothing visible (the button disappears, the panel stays blank).
- The web sign-up's final **Open Clip Studio Paint** button needs a `clipstudio:`-style URL handler on the host; none is
  registered. After a restart the splash showed "Try for free" again for a throwaway account that had logged in, so the
  login did not stick across a restart in that bottle state (not investigated).
- The splash freeze rate varied a lot in one session (1 of 8 launches up to 2 of 3).
- The input rig and the tests are in `csp-test-rig/` (see its README).

## Splash freeze ("Doodle mode" ignores clicks): findings from the unattended session (2026-11-08), to resume later

How it was measured: a virtual mouse/pen made with python-evdev on `/dev/uinput` (the ACL gives the user access;
a virtual tablet bound with `hl.device({ name = ..., output = "eDP-1" })`) drives the splash. **A teleported cursor
click never registers: the splash needs a real hover first.** The virtual mouse must glide in with small relative
moves (about 10 steps over 40 px, then a pause) before pressing; with that, a click works first time. Without it
the first click is eaten and sometimes none work, which looked like the freeze.

With gliding clicks the real freeze still happens in about 10-25% of launches (3 of 12, 1 of 8, 2 of 10 ...), also
when Wine is started directly (not through Bottles), so it is not Bottles.
- **Not different** between frozen and healthy launches: CPU (about 57%: the UI thread about 39% plus
  `wined3d_cs` about 15%, from the splash's animation), per-thread CPU, the X window tree and stacking, X input focus,
  the pointer's X position, Hyprland's window list, and the X events Wine gets (`+event`: the same `ButtonPress` /
  `ButtonRelease` on the same X window both times). Waiting 60 s before the click changes nothing.
- **Different** at the Windows-message level (`WINEDEBUG=+message,+win`): in a healthy run `WM_LBUTTONDOWN` goes to
  the splash host window (client position (879, 467), the Doodle button) and CSP reacts. In a frozen run it goes to
  another window of the same class (`{742DEA58-ED6B-...}`, e.g. `0x10092`) at client position (479, 199), which
  `DefWindowProc` ignores. That window is a **640x400 child at (400, 268)** (`SetWindowPos ... 400,268 (640x400)`,
  then `SetParent` into the splash host) that stays on top of the button; in healthy runs it never gets that geometry
  and is re-parented elsewhere. Hover still works because mouse moves reach the page by another path.
  This is the "invisible 640x400 WebView host windows" the Hyprland handler already knows about.
- Reading: a race in CSP's WebView2 hosting at start-up leaves a default-size (640x400) host child over the splash
  when the page's bounds are set late. Ideas not yet tried: a tiny Windows helper (built with the nix mingw
  compiler) that finds that window and hides or moves it once the splash is up, started by the launcher; checking
  `sync: esync/fsync` (ntsync is on); fewer WebView2 flags (`--enable-logging --v=0 ...` are logging overhead).
- Tools used (rebuild from this description): `inputrig.py` (virtual mouse and pen), `probe.py` (launch, wait for the
  splash, glide-click Doodle mode, record success), and a launcher that runs Wine directly with the bottle's
  environment copied from `/proc/<wine pid>/environ`.

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

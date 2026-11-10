# Touch gestures, on-screen keyboard, launcher, lock screen

Files: `yoga/hypr/touch.lua` (gestures and binds), `yoga/bin/yoga-touch` (plugin control and rescue),
`yoga/bin/yoga-osk` (keyboard), `yoga/bin/yoga-launcher`, `yoga/wvkbd/` (patched keyboard), `scripts/lock.sh`.

## Install

See [install.md](install.md) section 6: `hyprpm update; hyprpm add https://github.com/horriblename/hyprgrass;
hyprpm enable hyprgrass`, packages `hyprpm cmake glm` (cmake is needed because Arch's `glm` ships no pkg-config
file), then `yoga/wvkbd/build.sh`.

## How the plugin loads (read once)

1. `hyprland.start` runs `yoga-touch load`, which runs `hyprpm reload -n`.
2. Loading a plugin makes Hyprland reload the config by itself; on that second pass `hl.plugin.hyprgrass`
   exists and `touch.lua` registers the gestures. Without the plugin only the rescue bind and the keyboard exist.
3. **Never call `hl.plugin.load()` from the config**: every reload loads again and the config re-parses in a
   loop. Load from outside only.
4. At boot the touch controller reconnects three times over the first minute; `load` therefore waits until the
   device has been stable for 25 s and then does one `hyprctl reload` (only when uptime is under 3 minutes).
5. `hyprctl plugin unload` wants the plugin's **path**; `yoga-touch recover` finds it from `/proc/<pid>/maps`.

## Safety net

- **SUPER+CTRL+SHIFT+Escape** (locked bind), or `yoga-touch recover` from a TTY/SSH: stops the touchpad daemon,
  unloads every plugin, reloads, hides the keyboard, resets the submap, and keeps plugins off until
  `yoga-touch enable`. `yoga-touch disable` keeps them off at every login.
- Crash-loop guard: `load` writes `~/.local/state/yoga-touch/loading` and removes it 20 s later; if Hyprland dies
  inside that window the next login refuses to load.
- Keep SSH (`yoga_sshd`) or a USB keyboard as a second way in.

## After a Hyprland update

Plugins are built against exact headers. Log out and in, then `yoga-touch update` (= `hyprpm update` + load).
If the build fails, hyprgrass has no pin for that Hyprland yet; `yoga-touch disable` and use plain Hyprland.

## Gestures

Settings: `sensitivity = 4.0`, `long_press_delay = 400`, `edge_margin = 30` (logical px), swipe cancel ratio 0.15.
Edges are the edges **as the user sees them after rotation**.

| Gesture | Action |
|---|---|
| Swipe up from the bottom edge | show the dock for 10 s (hides when an app starts or is picked, or on the same swipe again; `yoga-dock-peek`) |
| Eight-finger tap | toggle the on-screen keyboard |
| Swipe right from the left edge | launcher (`yoga-launcher apps`) |
| Swipe left from the right edge | control center |
| Two fingers down from the top edge | close the window |
| Three fingers sideways | switch workspace (live). Book pose: slides the two-screen pair one slot (left = next); a Lua gesture in touch.lua takes over from the built-in swipe, which finds no neighbours there. Tablet and tent keep the live swipe: entering them lands on a workspace with windows (the nearest below, else above) so it has neighbours |
| Five fingers up | window switcher |
| Three-finger hold, drag | move the window |
| Hold on a border/gap | resize |
| Three-finger pinch (apart) / (together) | fullscreen / leave fullscreen, or float toggle |
| Three-finger tap | float toggle |
| Four fingers left/right | window to next/previous workspace. Book pose, no external monitor: towards the other screen = window to that screen; away from it (left on the left screen, right on the right) = slide both screens one slot along the workspace list, taking the window along. A slot is a workspace with windows; a block of empty ones counts as two (one per screen) |
| Four fingers up/down | window to the screen above/below |

Edit the table in `touch.lua`; `hyprctl reload` applies it.

Things that bit:
- **Gestures bind with no modifier, so they stop while any modifier is held.** A latched Shift on the on-screen
  keyboard (fixed: it clears on hide) or on keyd's virtual keyboard (`sudo keyd reload`) kills them.
- **Gesture log:** `~/.local/state/yoga-touch/gesture.log` records the 3-finger book swipes (start / end with the summed delta) and the 4-finger swipes, to tell "the gesture never arrived" from "it arrived and did nothing".
- **Pinch after any swipe:** every swipe handler calls `yoga_swipe_mark()` and a pinch within 1.5 s of one is ignored, not only after a workspace change (a book swipe at the end of the list, or a window sent to the other screen, changes none and the drift toggled the window's floating state).
- **Pinch after a swipe:** the fingers drift together at the end of a three-finger swipe and read as a pinch. A
  guard ignores a pinch within a second of a workspace change (`~/.local/state/yoga-touch/pinch.log` says why).
  hyprgrass names the pinch directions opposite to what you would think on this screen.
- **Rotation:** touch devices get their panel's transform with `rotation_sense = 1`; in portrait the 5-finger
  gestures were inverted before that.

## On-screen keyboard (wvkbd, patched)

squeekboard was tried and dropped: it always opens on the first output and cannot hide. `wvkbd` 0.21 plus
`yoga/wvkbd/yoga.patch`:
- standard laptop layout in **Dvorak** (keycodes sent so that shortcuts also match a Dvorak OS layout; assumes
  US Dvorak), Fn layer with F1-F10 on the number keys, a **Hide** key, `--top` docking, `--output NAME`
  (stock wvkbd measured the wrong screen and looped on non-default monitors), latched modifiers cleared on hide.
- `yoga-osk toggle|show|hide|start|status|move`. Starts hidden from `hyprland.start`, on the bottom panel,
  a third of the panel's logical width high (480 px of 1440: its 5 rows of 15 key-units then have square keys),
  at the top of that screen so the front part is free for the virtual touchpad.
- While it is up (dual screen) the bottom screen's bar is hidden and **notification toasts are kept off that screen**
  (`yoga-bottom-reserve` sets Noctalia's `notification.monitors` to the other output and back to `[]` after; off with
  `YOGA_RESERVE_HIDE_NOTIFS=0`).
- **Autocorrect** (`autocorrect.h` in the patch): the keyboard keeps the letters typed since the last word break and,
  at a space, Enter or `. , ; ! ? )`, replaces an unknown word (3+ letters, 4+ before a period) by the most frequent
  dictionary word one edit away (`teh` -> `the`, `dont` -> `don't`). **Backspace right after a correction undoes it**
  and adds the word to `~/.config/yoga/autocorrect-known.txt`. It leaves alone words with digits/symbols in the token
  (paths, URLs), `ALLCAPS`/`camelCase`, anything typed with Ctrl/Alt/Super held, and a buffer older than 5 s or
  after an arrow/layer key. **Toggle: the `Auto` key** (lit when on) **or `yoga-osk autocorrect on|off|toggle|status`**
  (state in `~/.config/yoga/autocorrect`, kept across restarts); turn it off for a terminal. The dictionary
  (`~/.local/share/yoga/autocorrect-words.txt`, 47k words from hermitdave/FrequencyWords) is generated by
  `yoga/wvkbd/build.sh` (`make-wordlist.py`); without it the keyboard works, only without autocorrect.
- **Never auto-shows** (not even in tablet mode: it used to cover the screen). Shown by gesture, bar button,
  **SUPER+ALT+k**, or the lock screen. In dock mode: keyboard + touchpad on the bottom screen; in tablet/tent
  (one screen): a floating keyboard (`move` key relocates it).
- It refuses to show while the physical keyboard is **docked** or a **USB keyboard** is connected
  (`python3 -I yoga/bin/yoga_state.py keyboard` prints which). The Bluetooth keyboard connected but off the dock
  does **not** block it, so the OSK works with the keyboard in your lap or on a desk. The controller's own HID
  keyboard and virtual keyboards (keyd) don't count. To keep the OSK usable with a USB keyboard attached:
  `touch ~/.config/yoga/osk-with-keyboard`.
  The login screen has no on-screen keyboard (its compositor has no layer-shell or virtual-keyboard support).

## Launcher, clipboard, window switcher

Noctalia's panels hold a focus grab that closes on any touch outside them, so tapping the on-screen keyboard
closes the launcher before you can type. While the keyboard is up, `yoga-launcher` opens **fuzzel** instead
(no grab); otherwise Noctalia's panels. `yoga-launch` puts focus back on the monitor you were using before it
runs the app, so apps open on that screen. SUPER+d, SUPER+v, SUPER+Tab and the swipes use it.

## Lock screen

- The keyboard can be used over the lock screen (`above_lock = 2` layer rule). `yoga-osk-lockwatch` raises it
  when hyprlock appears and the keyboard is undocked, and after a resume waits 6 s before showing a fresh one.
- `scripts/lock.sh` on a Yoga: the password box only on the top panel when both are lit. It also feeds hyprlock
  upright `grim` screenshots for any panel rotated by a Hyprland transform; with the kernel flag the top panel's
  transform is 0, the stock background is upright (checked), and that part is dormant.
- Not confirmed: that the lock-screen keyboard takes touch right after a resume.

## Bars, workspaces

- The keyboard button is on the laptop panels' bars only (a Noctalia monitor section replaces the whole bar, so
  `yoga.bar_extra` generates `~/.cache/noctalia/primary.toml`).
- With the bottom screen reserved for the keyboard it holds a named workspace `kbd` (no number), so Hyprland
  never auto-numbers it; CTRL+left/right step through the workspaces that have windows, with one stop in each gap between them, and open a new one past the last.

## Not verified

Portrait touch on the top panel, five-finger directions in portrait, typing into fuzzel with the on-screen
keyboard end to end, the lock screen on a real lock/unlock, the keyboard's Move key.

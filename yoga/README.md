# Yoga Book 9i on Linux

Everything specific to the Lenovo Yoga Book 9i (13IMU9, two OLED touchscreens and
a detachable Bluetooth keyboard) in one tree. The tree has no path into the rest
of the dotfiles except the two hand-over points below, so it can be split into its
own repository (`git subtree split --prefix=yoga`). Machines that are not a Yoga
do not link, load or run anything in it. The write-ups (what was measured, why) are
in `docs/yoga-book/`.

## Layout

| Path | What |
|---|---|
| `bin/` | The scripts, linked into `~/.local/bin`: `yoga-posture` (hinge angle and orientation to panel layout, tablet-mode switch), `yoga-touchpad` (virtual touchpad on the bottom screen) and `yoga-touchpad-indicator`, `yoga-osk` and `yoga-osk-lockwatch` (on-screen keyboard, also over the lock screen), `yoga-touch` (hyprgrass plugin control and the rescue command), `yoga-bottom-reserve`, `yoga-palm` (palm rejection), `yoga-launcher` and `yoga-launch`, `yoga-platform-status`, `clip-studio-paint`. `yoga_state.py` is not linked: it is the shared model (dock debounce, derived state, the state file) imported by the Python daemons and run by the shell ones, found next to the script's real path |
| `systemd/` | The user services (the five daemons, plus `yoga-audio-levels`: fixed speaker levels and amp force-load at login), started with the graphical session |
| `tests/` | `state-sim.py` (the simulator for the dock / on-screen keyboard / posture interactions, safe to run on the live machine) and `yoga-lua-test.lua` (the module against a stub `hl`) |
| `hypr/` | The Hyprland side: `config.lua` (the tunables), `yoga.lua` (the module), `touch.lua` (gestures, keyboard binds, rescue bind; loaded by the module) |
| `noctalia/host.toml` | The Yoga's Noctalia bar |
| `nix/module.nix` | Home Manager module that links all of the above, plus the WirePlumber software-volume rule |
| `kbdock-dkms/`, `udev/`, `wvkbd/`, `keyd/`, `secureboot/`, `kbdock-test.sh`, `bt-import-windows-keys.py` | System side, installed by `ansible/yoga.yaml` (kernel module for the keyboard dock, udev rules, the patched on-screen keyboard, Secure Boot signing). They live here already and `ansible/yoga.yaml` reaches them as `{{ playbook_dir }}/../yoga/...`; the playbook itself is still in `ansible/` |

Scripts find their siblings through their own real path (`readlink -f $0`), so they
work from the checkout as well as through the links.

## How it is wired

1. **Home Manager** (`nix/module.nix`): `home/hosts/yoga-linux.nix` imports it and sets
   `yoga.enable = true`. Options: `yoga.sourceDir` (the checkout of this tree,
   default `~/.dotfiles/yoga`), `yoga.noctalia.linkHost`, `yoga.clipStudio.enable`.
   It links `bin/*` into `~/.local/bin`, the services into `~/.config/systemd/user`
   (plus the `graphical-session.target.wants` links), `noctalia/host.toml` as
   `~/.config/noctalia/host.toml`, and installs the Clip Studio Paint launcher entry.
   Links point into the checkout, so edits apply without a rebuild. New files must
   be `git add`ed before `home-manager switch --flake ~/.dotfiles` (flakes only see
   tracked files).
2. **Hyprland** (`.config/hypr/hyprland.lua`): between the desk monitors' rules and the
   catch-all rule it reads `$YOGA_DIR` (default `~/.dotfiles/yoga`)`/hypr/config.lua`,
   which is a plain table and runs no code. Only if `detect` in it matches does it
   load `hypr/yoga.lua`, in a `pcall`, and keep the result in the global `yoga`. A
   missing tree, a broken `config.lua` or `yoga.lua` just means no `yoga` (plus a
   notification when the files exist but fail); the shared config never depends on it.
3. **System**: `ansible/yoga.yaml` (gated on the hostname `yoga-linux`).

### Is this a Yoga? (`detect` in `hypr/config.lua`)

Any one of: the DMI product family or name (works at the first config load, when
Hyprland has not created monitors or opened input devices yet), both panels'
EDID descriptions among the monitors, or a touch device named
`ingenic-gadget-serial-and-keyboard-touchscreen*`. `YOGA_FORCE=1` skips the check
(nested Hyprland, tests).

## The module interface

`hypr/yoga.lua` returns `function(host) ... return yoga end`. hyprland.lua passes
the `host` table:

| Field | |
|---|---|
| `host.dir`, `host.config` | this tree, and `config.lua`'s table |
| `host.is_laptop(m)`, `host.is_tv(m)`, `host.is_desk_monitor(m)` | the shared config's classifiers of monitors |
| `host.place_workspaces(keep_view)`, `host.focus_ws(id)`, `host.ws_step(delta, move)` | its workspace functions |

and the module returns the `yoga` table that hyprland.lua calls into. Each hook is
optional for the shared side (`yoga_hook(name, ...)`: a missing hook does nothing,
an erroring one is caught and reported once):

| Hook | Called | Does |
|---|---|---|
| `yoga.rank(m)` | `place_workspaces`, sorting the laptop panels | 1 top panel, 2 bottom panel, nil otherwise |
| `yoga.retarget(target)` | `place_workspaces`, after the roles are assigned | while the bottom screen is reserved for the keyboard, replaces it by the top panel in `target[1..10]` |
| `yoga.ws_skip(ws)`, `yoga.ws_grow()` | `ws_step` (CTRL+left/right, CTRL+SHIFT+left/right, the five-finger window moves) | skip a workspace that is on the reserved bottom screen; true: "next" on the last populated workspace opens the next number (no limit) |
| `yoga.bar_extra(primary)` | `set_bar_primary` | text appended to `~/.cache/noctalia/primary.toml` (the bars' widget lists) |
| `yoga.lid_changed(closed)` | the lid switch binds | true when handled (panels off/on, nothing in a fold); false: the shared config suspends on close |
| `yoga.before_bind()` | start of every `bind()` | puts the focus back on the monitor you were on if a touch moved it to the reserved screen |
| `yoga.apply_devices()` | after `hl.config` | binds the touch and pen devices to their panels (also called on a posture change) |
| `yoga.start()` | last line | loads `touch.lua` |
| `yoga.launcher_cmd` | SUPER+d, v, minus, Tab | set by `touch.lua`; a launcher the on-screen keyboard can type into (nil: Noctalia's panels) |

The module registers its own Hyprland event handlers (monitor added/removed, config
reloaded, monitor focused, `hyprland.start`) and its monitor rules, and keeps the
globals the scripts call through `hyprctl repl`/`hyprctl eval`:
`yoga_set_posture(spec)`, `yoga_panel_outputs()`, `yoga_set_reserved(on)`,
`yoga_bottom_reserved`, `yoga_focus_back()`, `yoga_win_step(delta)`,
`yoga_win_to_monitor(dir)`, `yoga_apply_devices()`.

State outside the process: `$XDG_RUNTIME_DIR/yoga/state.json` (the effective state, below),
`$XDG_RUNTIME_DIR/yoga/folded` (the posture daemon's pid while the hinge is folded back: the lid must
not suspend or darken the panels), `$XDG_RUNTIME_DIR/yoga-posture/layout.lua` (the last
posture, valid only while the daemon that wrote it runs), `~/.local/state/yoga-touch/`
(the plugin switch), `~/.cache/noctalia/primary.toml`.

## One authority for the dock and the keyboard state

yoga-posture is the only reader of the keyboard dock (`keyboard_position`; override the file with
`YOGA_DOCK_FILE`). It debounces it once (`DOCK_DEBOUNCE_S`, `yoga_state.py`), watches whether the
on-screen keyboard's layer exists, derives what follows (is the on-screen keyboard allowed, are the
bottom screen's workspaces reserved, is its bar hidden, may the touchpad grab) and publishes that as
`$XDG_RUNTIME_DIR/yoga/state.json` four times a second. yoga-touchpad, yoga-bottom-reserve, yoga-osk
and yoga-osk-lockwatch read it, and compute the same thing themselves with the same code when there
is no fresh file (daemon down, crashed, stalled for 3 s). The explicit model, the invariants and
every transition: `docs/yoga-book/state-machine.md`. `python3 -I yoga/bin/yoga_state.py show` prints
the live state.

## Hardware assumptions (all in `hypr/config.lua`)

- Panels are matched by EDID description (`Samsung Display Corp. 0x4167` top,
  `0x4182` bottom), never by connector name; the top one is mounted rotated 180
  degrees; scale 2 (1440x900 logical). "Top" was derived from the hardware survey and has held
  up in use (touch lands on the right panel, gestures follow it once `touch.top_offset = 2` was
  set); swap the descriptions in `config.lua` if a unit differs.
- Touch and pen are one USB device (17ef:6161, `ingenic-gadget-serial-and-keyboard-*`)
  with a node per panel; they follow their panel's transform.
- The docked reference layout (`docked`) is the owner's two monitors from kanshi's
  `kens-triple` profile. Edit or empty it.
- The Noctalia bar lists name widgets defined in `noctalia/host.toml` and the shared
  `bar-button` plugin (which stays in `.local/share/noctalia/plugins`: the desktop uses it too)
  and the Yoga's own `yoga-battery` plugin (`noctalia/plugins/`, a fork of the desktop's `zmk-battery`).

## Using it from another setup

Today this tree expects the surrounding dotfiles for: the flake and `home/lib.nix`
conventions only as an example (the module does not import them), the shared
`hyprland.lua` loader and hooks, `.config/hypr/window-switcher.sh` (used by
`yoga-launcher`) and `hypr/brightness.sh`, and Noctalia as the shell. Another user
can: add `imports = [ <this tree>/nix/module.nix ]; yoga.enable = true;
yoga.sourceDir = "<path to this tree>";` to a Home Manager configuration, copy the
loader block and the `yoga_hook` calls from `hyprland.lua` (search for `yoga`), and
edit `hypr/config.lua`.

## Testing without the session

`python3 yoga/tests/state-sim.py` replays the dock / on-screen keyboard / posture scenarios (slides,
docking with the keyboard up, posture changes, fold glitch, daemon restarts, reloads, resume, lock
screen) against the real code with a fake dock file and stubbed `hyprctl`/`wvkbd`, and checks the
invariants; it touches nothing of the session.

Do not run `Hyprland --verify-config` (it executes the config, including `systemctl
suspend`). `hyprctl reload` followed by `hyprctl configerrors` (blank is fine) is the
check on the live session. A plain `lua`/`luajit` with a stubbed `hl` table can load
`hyprland.lua` with `HOME`, `XDG_RUNTIME_DIR` and `YOGA_DIR` pointed elsewhere;
`YOGA_DIR=/nonexistent` is the "no Yoga module" path.

## Where the write-ups are (`docs/yoga-book/`)

Start with `docs/yoga-book/README.md` (what you need, the ten mistakes worth avoiding), then `install.md`
(the order that works) and `troubleshooting.md` (symptom, cause, fix). The long investigation log from the
first bring-up is kept outside this repo.

| File | Covers |
|---|---|
| `install.md`, `troubleshooting.md` | ordered setup steps; everything that went wrong the first time |
| `hardware.md` | machine facts: panels, touch/pen nodes, sensors, WMI, firmware noise |
| `display.md` | panel layout and rotation (kernel flag, software cursor), touch/pen mapping, brightness, bars |
| `kbdock.md` | the keyboard dock kernel module (DKMS), udev rules |
| `posture-daemon.md`, `state-machine.md` | `yoga-posture` and the shared dock / keyboard / posture state |
| `touchpad.md` | the virtual touchpad |
| `touch-ux.md` | hyprgrass gestures, the on-screen keyboard, launcher, lock screen |
| `login.md`, `secureboot.md`, `platform.md`, `homerow-mods.md` | greeter, Secure Boot signing, audio/suspend/power, keyd |
| `steam.md`, `clip-studio.md` | games and Clip Studio Paint |

Outside the tree: `scripts/lock.sh` builds a hyprlock config with upright screenshot backgrounds for
the rotated top panel on a Yoga (and is the stock lock everywhere else); `ansible/yoga.yaml` holds
the system side; `.config/hypr/hyprland.lua` sets `render.send_content_type = false` for everyone.

## Rolling back this layout

`git mv` the directories back (`bin/*` to `.local/bin`, `systemd/*` to
`.config/systemd/user`, `noctalia/host.toml` to `.config/noctalia/hosts/yoga-linux.toml`),
restore the old `home/hosts/yoga-linux.nix` and `hyprland.lua` from version control or
a backup, `git add`, and `home-manager switch --flake ~/.dotfiles`.

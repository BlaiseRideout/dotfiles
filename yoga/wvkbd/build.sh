#!/usr/bin/env bash
# Build wvkbd v0.21 with the Yoga patch and install it as ~/.local/bin/wvkbd-yoga.
#
# yoga.patch changes the upstream "mobintl" layout:
#   - the main layers (portrait and landscape) become a standard laptop layout in
#     Dvorak: number row, Tab row, Caps/home row with Enter, Shift row, then
#     Hide Esc Fn Ctrl Super Alt Space AltGr and the arrow keys. A key types what it
#     shows (wvkbd uploads its own keymap, so the OS-level layout is not applied).
#     "Fn" is the stock symbols/numbers layer.
#   - --top: dock to the top edge of the output (the Yoga puts the keyboard there so the
#     front of the bottom screen is free for the virtual touchpad)
#   - Dvorak positions: the system layout is Dvorak, and the compositor maps the keycodes
#     of a virtual keyboard through it for its keybindings, so each key sends the keycode
#     of the physical key that carries its character in Dvorak, and the latin keymap
#     wvkbd uploads is the matching permutation (identical to us(dvorak) on those keys,
#     checked with libxkbcommon), so typing and shortcuts agree. Shifted , . / are
#     standard (< > ?).
#   - a Move key and --fixed: the floating single-screen keyboard can jump between the
#     bottom and top edge (SIGRTMIN+1, the Move key) to uncover text boxes; --fixed (the
#     docked two-screen mode) ignores it
#   - latched modifiers are RELEASED (key-up of the held modifier key, then an empty modifier
#     state) whenever the keyboard goes away: on hide (e.g. the physical keyboard docked), when the
#     compositor closes the surface, on SIGTERM/SIGINT/SIGHUP (yoga-osk stop, a restart in another
#     mode) and on a normal exit. A Shift left latched otherwise stays down session-wide and
#     silently kills every hyprgrass gesture (they bind with no modifier)
#   - a Hide key (new key type; sends itself SIGUSR1, show again with SIGUSR2),
#     also on the Fn layer
#   - --output NAME / $WVKBD_OUTPUT, so it opens on the bottom panel instead of on
#     whatever monitor the compositor picks (also fixes wvkbd's size probe, which
#     otherwise measures a different monitor and loops forever)
#
# Needs: git make gcc pkgconf wayland pango cairo libxkbcommon (no root, no scdoc:
# only the binary is built, not the man page). Re-run after editing yoga.patch.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest=${1:-$HOME/.local/bin/wvkbd-yoga}
tag=v0.21
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git clone -q --depth 1 --branch "$tag" https://github.com/jjsullivan5196/wvkbd.git "$work/wvkbd"
cd "$work/wvkbd"
git apply "$here/yoga.patch"
make -j"$(nproc)" wvkbd-mobintl
mkdir -p "$(dirname "$dest")"
install -m755 wvkbd-mobintl "$dest.new"
mv -f "$dest.new" "$dest"
echo "installed $dest"

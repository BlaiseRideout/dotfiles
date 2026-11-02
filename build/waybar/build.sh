#!/bin/sh
# Build Waybar into a private prefix, checked out at an unreleased master commit
# (pinned in ansible/setup.yaml) because the tray's ignore-list isn't in 0.15.0 yet. Ubuntu
# 24.04 ships 0.9.24, which lacks it too. fmt, spdlog and gtk-layer-shell are
# newer than Ubuntu's, so meson downloads and builds them as subprojects.
# Wayland comes from the private prefix built for Sway (build/sway/build.sh
# in the dotfiles); the system has no libwayland-dev.
#
# Needs: sudo apt install libgtkmm-3.0-dev libjsoncpp-dev libsigc++-2.0-dev \
#   libdbusmenu-gtk3-dev libpulse-dev libxkbregistry-dev
#
# Optional features are off apart from the ones the config uses (tray,
# pulseaudio, backlight via udev). Re-run to rebuild.
set -eu

SRC=${SRC:-$HOME/.local/src/waybar}   # the Waybar checkout
PREFIX=${PREFIX:-$HOME/.local/opt/waybar}
SWAY=${SWAY:-$HOME/.local/opt/sway}

export PKG_CONFIG_PATH="$SWAY/lib/pkgconfig:$SWAY/share/pkgconfig"
export LDFLAGS="-Wl,-rpath,$SWAY/lib"

# Waybar master also enumerates the "leds" subsystem for keyboard backlights, with
# no filter, so on a desktop the backlight module latches onto Caps Lock and
# similar LEDs and shows a bogus "0%". Backlights proper are unaffected.
sed -i '/udev_enumerate_add_match_subsystem(enumerate.get(), "leds");/d' \
  "$SRC/src/util/backlight_backend.cpp"

rm -rf "$SRC/build"
meson setup "$SRC/build" "$SRC" --prefix="$PREFIX" --buildtype=release \
  -Dauto_features=disabled -Dtests=disabled -Dman-pages=disabled -Dsystemd=disabled \
  -Ddbusmenu-gtk=enabled -Dpulseaudio=enabled -Dlibudev=enabled -Dlibevdev=enabled
ninja -C "$SRC/build"
ninja -C "$SRC/build" install

echo "==> installed $("$PREFIX/bin/waybar" --version)"

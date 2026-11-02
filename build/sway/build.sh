#!/bin/sh
# Build Sway 1.11 (first release with explicit sync, linux-drm-syncobj-v1,
# which NVIDIA needs to avoid flicker) and the libraries it needs that are
# newer than Ubuntu 24.04's, into a private prefix. Binaries carry an rpath to
# the prefix, so nothing else on the system loads these libraries.
#
#   wayland 1.24.0   (wlroots needs >= 1.23.1; Ubuntu has 1.22)
#   libinput 1.26.2  (sway needs >= 1.26; Ubuntu has 1.25)
#   pixman 0.46.4    (wlroots needs >= 0.43; Ubuntu has 0.42)
#   wlroots 0.19.3
#   sway 1.11
#
# Re-run to rebuild, e.g. after a system library update.
set -eu

SRC=${SRC:-$HOME/.local/src/sway-1.11}   # holds the wayland, libinput, pixman, wlroots and sway checkouts
PREFIX=${PREFIX:-$HOME/.local/opt/sway}

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export LDFLAGS="-Wl,-rpath,$PREFIX/lib"
export PATH="$PREFIX/bin:$PATH"

build() {
  name=$1; shift
  echo "==> $name"
  rm -rf "$SRC/$name/build"
  meson setup "$SRC/$name/build" "$SRC/$name" \
    --prefix="$PREFIX" --libdir=lib --buildtype=release "$@"
  ninja -C "$SRC/$name/build"
  ninja -C "$SRC/$name/build" install
}

build wayland -Ddocumentation=false -Dtests=false

build libinput -Dudev-dir="$PREFIX/lib/udev" -Ddebug-gui=false \
  -Dtests=false -Ddocumentation=false -Dlibwacom=true

build pixman -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled

build wlroots -Drenderers=gles2 -Dbackends=drm,libinput -Dxwayland=enabled \
  -Dexamples=false -Dsession=enabled

build sway -Dsd-bus-provider=libsystemd -Dtray=enabled -Dman-pages=enabled \
  -Dzsh-completions=false -Dbash-completions=false -Dfish-completions=false

echo "==> installed $("$PREFIX/bin/sway" --version)"

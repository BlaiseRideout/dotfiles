#!/bin/bash
# Build noctalia-greeter with upstream PR #183 ("start fingerprint auth without pressing Enter",
# [auth].auto_start_pam) merged in, as an UNPRIVILEGED user. Prints the binary's path.
# ansible/yoga.yaml copies it to /usr/local/lib/yoga/ and points greetd at it
# (docs/yoga-book/faceunlock.md). Delete this whole mechanism once #183 is in the packaged greeter.
#
# Why: the greeter starts PAM (so Howdy, so the IR emitter) only when Enter is pressed. #183 starts it
# when the password step appears. The installed package is v1.7.0; main is 7 commits past it and does
# not touch protocols/ or src/compositor/, so this greeter binary runs under the packaged compositor
# (the session script picks the greeter with $NOCTALIA_GREETER_BIN).
#
# Pinned: a moved PR (force-push) stops the build instead of silently building different code.
# Build deps (pacman): nlohmann-json stb, plus what the greeter package already needs.
set -eu
REPO=https://github.com/noctalia-dev/noctalia-greeter.git
BASE=74dd931bf9b8f3bd9c1852a95ed87e70e7317b1e     # upstream main, 2026-11-08 (v1.7.0 + 7 commits)
PR=183
PR_HEAD=7ff5ae89fbbe5cc8a1c2994ac9500f4d64caf57b
work=${YOGA_GREETER_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/yoga-greeter}
pins="$BASE+pr$PR@$PR_HEAD+face-text"
out=$work/build/noctalia-greeter

if [ -x "$out" ] && [ "$(cat "$work/pins" 2>/dev/null)" = "$pins" ]; then echo "$out"; exit 0; fi

mkdir -p "$work"
[ -d "$work/src/.git" ] || git clone -q "$REPO" "$work/src"
cd "$work/src"
git fetch -q origin "pull/$PR/head"
[ "$(git rev-parse FETCH_HEAD)" = "$PR_HEAD" ] || { echo "PR #$PR moved ($(git rev-parse FETCH_HEAD)); review it, then update PR_HEAD in $0" >&2; exit 1; }
git checkout -q -f -B yoga-autostart "$BASE"
git -c user.name=yoga -c user.email=yoga@localhost merge -q --no-edit "$PR_HEAD"
# #183 is written for a fingerprint reader; the Yoga has an IR camera (Howdy), so say so.
sed -i 's/Waiting for fingerprint reader\.\.\./Looking for your face.../' src/greeter/greeter_surface.cpp
grep -q 'Looking for your face' src/greeter/greeter_surface.cpp || { echo "status text not found in greeter_surface.cpp; update the sed in $0" >&2; exit 1; }
rm -rf "$work/build"
meson setup "$work/build" --prefix=/usr --buildtype=release >&2
ninja -C "$work/build" noctalia-greeter >&2
echo "$pins" > "$work/pins"
echo "$out"

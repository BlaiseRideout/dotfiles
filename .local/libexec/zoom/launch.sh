#!/bin/sh
# Native Wayland keeps the sharing controls clickable. On NVIDIA, Mesa's full
# OpenGL renderer avoids corrupt icons/text without losing the share preview.
# Qt's software backend loses the preview, so do not use QT_QUICK_BACKEND here.
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    for vendor in /usr/share/glvnd/egl_vendor.d/50_mesa.json /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json; do
        if [ -f "$vendor" ]; then
            export __EGL_VENDOR_LIBRARY_FILENAMES="$vendor"
            export LIBGL_ALWAYS_SOFTWARE=true
            break
        fi
    done
fi
for binary in /usr/bin/zoom /usr/local/bin/zoom /opt/zoom/ZoomLauncher "$HOME/.nix-profile/bin/zoom"; do
    if [ -x "$binary" ]; then exec "$binary" "$@"; fi
done
echo 'Zoom is not installed.' >&2
exit 127

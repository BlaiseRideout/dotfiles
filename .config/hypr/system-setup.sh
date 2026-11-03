#!/bin/sh
# System setup for the Hyprland session (everything that needs root). Run after
# `home-manager switch`, and again after every NVIDIA driver update:
#
#   sudo ~/.config/hypr/system-setup.sh            set up
#   sudo ~/.config/hypr/system-setup.sh --remove   undo all of it
#
# 1. GPU drivers for Nix programs: Home Manager's non-nixos-gpu-setup links
#    /run/opengl-driver and adds *_nix_gpu.json EGL platform files to
#    /etc/egl/egl_external_platform.d (seen by apt programs too).
# 2. The "Hyprland (NVIDIA)" login session, running ~/.config/hypr/hyprland-session.
# 3. hyprlock's PAM service. hyprlock comes from Nix, and Nix's PAM can't load
#    Ubuntu's modules (common-auth requires pam_ecryptfs), so it only gets
#    pam_unix.
# 4. Nix's pam_unix checks passwords through /run/wrappers/bin/unix_chkpwd (a
#    NixOS path), so that points at Ubuntu's setgid helper.
#
# ~/scripts/lock.sh falls back to swaylock until 3 and 4 are in place.
set -eu

[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
user=${SUDO_USER:?Run with sudo from your own account}
home=$(getent passwd "$user" | cut -d: -f6)

session=/usr/share/wayland-sessions/hyprland-nvidia.desktop
pam=/etc/pam.d/hyprlock
chkpwd_conf=/etc/tmpfiles.d/hyprlock-unix-chkpwd.conf

if [ "${1:-}" = --remove ]; then
  rm -fv "$session" "$pam" "$chkpwd_conf" /run/wrappers/bin/unix_chkpwd
  rmdir /run/wrappers/bin /run/wrappers 2>/dev/null || true
  rm -fv /etc/tmpfiles.d/non-nixos-gpu.conf /nix/var/nix/gcroots/non-nixos-gpu.conf \
    /etc/egl/egl_external_platform.d/*_nix_gpu.json /run/opengl-driver
  exit 0
fi

# 1
"$home/.nix-profile/bin/non-nixos-gpu-setup"

# 2
cat > "$session" <<EOF
[Desktop Entry]
Name=Hyprland (NVIDIA)
Comment=Hyprland from Nix; config in ~/.config/hypr
Exec=$home/.config/hypr/hyprland-session
Type=Application
DesktopNames=Hyprland
EOF

# 3
cat > "$pam" <<'EOF'
# hyprlock from Nix (see ~/.config/hypr/system-setup.sh). Nix's PAM can't load
# Ubuntu's modules, so only pam_unix, which checks the password through
# /run/wrappers/bin/unix_chkpwd.
auth required pam_unix.so
EOF

# 4
cat > "$chkpwd_conf" <<'EOF'
# Ubuntu's unix_chkpwd where Nix's pam_unix looks for it (for hyprlock; see
# ~/.config/hypr/system-setup.sh)
d  /run/wrappers     0755 root root -
d  /run/wrappers/bin 0755 root root -
L+ /run/wrappers/bin/unix_chkpwd - - - - /usr/sbin/unix_chkpwd
EOF
systemd-tmpfiles --create "$chkpwd_conf"

echo "Done. Check that hyprlock will accept your password:"
echo "  nix run nixpkgs#pamtester -- hyprlock $user authenticate"

# The desktop on Linux Mint 22 (Ubuntu 24.04): nhuto.nix plus the workarounds
# for what Ubuntu lacks or ships too old, kept here so other installs (CachyOS)
# don't get them.
#
# Hyprland and its apps come from Nix, as Ubuntu 24.04 has no Hyprland. Nix-
# built GUI programs can't see the system's GPU drivers, so
# targets.genericLinux.gpu builds a matching copy for /run/opengl-driver.
# After switching, run
#   sudo ~/.dotfiles/build/hyprland/system-setup.sh
# which links the drivers and adds the login session (build/hyprland/
# hyprland-session) and hyprlock's PAM setup. Again after every NVIDIA driver
# update, with a new nvidia.version/sha256 below.
{ pkgs, lib, ... }:
let
  portal = pkgs.xdg-desktop-portal-hyprland;
in
{
  imports = [ ./nhuto.nix ];

  home.packages = with pkgs; [
    fzf                 # Ubuntu's is 0.44: the shells' `fzf --zsh` and clipboard.sh need newer
    hyprland            # Hyprland, hyprctl, start-hyprland
    hyprland-guiutils   # its "app not responding" and update dialogs
    hyprpaper           # wallpapers
    hypridle            # idle: lock, screens off
    hyprlock            # lock screen (needs system-setup.sh's PAM service)
    grimblast           # screenshots (hyprwm/contrib; grimshot only knows Sway)
    fuzzel              # launcher (newer than Ubuntu's 1.9)
    cliphist            # clipboard history ($mod+v)
  ];

  targets.genericLinux.gpu.enable = true;
  # It must match the installed driver exactly. After a driver update: set the
  # new version, get its hash with
  #   nix store prefetch-file https://download.nvidia.com/XFree86/Linux-x86_64/<version>/NVIDIA-Linux-x86_64-<version>.run
  # switch, then rerun system-setup.sh.
  targets.genericLinux.gpu.nvidia = {
    enable = true;
    version = "610.57.04";
    sha256 = "sha256-suk1xmuDuwDAyFe8jg7g/VLekoa0DJzB7sKafOfrEW0=";
  };
  # The driver is unfree; allow just it
  targets.genericLinux.gpu.packages = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = pkg: lib.getName pkg == "nvidia-x11";
    config.nvidia.acceptLicense = true;
  };

  # hyprland.lua starts the polkit agent from here (Home Manager doesn't link libexec)
  home.file.".local/libexec/hyprpolkitagent".source =
    "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";

  # Screen sharing: the system xdg-desktop-portal finds backends in
  # ~/.local/share/xdg-desktop-portal/portals and starts them over D-Bus. The
  # packaged D-Bus file hands off to a systemd unit, which isn't installed, so
  # start the portal directly instead. Under Sway, sway-portals.conf keeps wlr.
  xdg.dataFile."xdg-desktop-portal/portals/hyprland.portal".source =
    "${portal}/share/xdg-desktop-portal/portals/hyprland.portal";
  xdg.dataFile."dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.impl.portal.desktop.hyprland
    Exec=${portal}/libexec/xdg-desktop-portal-hyprland
  '';
}

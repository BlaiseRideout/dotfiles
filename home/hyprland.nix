# Hyprland, next to Sway (which stays the default session), with the Hypr apps:
# hyprpaper, hypridle, hyprlock, hyprpolkitagent and xdg-desktop-portal-hyprland.
# Their configs are in .config/hypr. Plus fuzzel (.config/fuzzel) as the launcher
# for apps, commands, windows and cliphist's clipboard history.
#
# Ubuntu 24.04 has no Hyprland package, so it comes from Nix. Nix-built GUI
# programs can't see the system's GPU drivers, so targets.genericLinux.gpu
# builds a matching copy of them for /run/opengl-driver. After switching, run
#   sudo ~/.config/hypr/system-setup.sh
# which links the drivers and adds the login session and hyprlock's PAM setup.
# Again after every NVIDIA driver update, with new
# targets.genericLinux.gpu.nvidia.version/sha256 in the host file.
{ pkgs, dotfilesLink, ... }:
let
  portal = pkgs.xdg-desktop-portal-hyprland;
in
{
  dotfiles.configDirs = [ "hypr" "fuzzel" ];

  targets.genericLinux.gpu.enable = true;

  home.packages = with pkgs; [
    hyprland            # Hyprland, hyprctl, start-hyprland
    hyprland-guiutils   # its "app not responding" and update dialogs
    hyprpaper           # wallpapers
    hypridle            # idle: lock, screens off
    hyprlock            # lock screen (needs system-setup.sh's PAM service)
    grimblast           # screenshots (hyprwm/contrib; grimshot only knows Sway)
    fuzzel              # launcher: apps, commands, windows, clipboard (newer than Ubuntu's 1.9)
    cliphist            # clipboard history ($mod+v; `cliphist list` in a terminal)
  ];

  # FSearch's look, in the sandbox config dir of its Flatpak so only it gets it
  # (the stylesheet explains)
  home.file.".var/app/io.github.cboxdoerfer.FSearch/config/gtk-3.0/gtk.css".source =
    dotfilesLink ".config/fsearch/gtk.css";

  # GTK 3's stylesheet, for every GTK 3 app (the file explains). Just the file:
  # ~/.config/gtk-3.0 also holds GTK's bookmarks.
  xdg.configFile."gtk-3.0/gtk.css".source = dotfilesLink ".config/gtk-3.0/gtk.css";

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
  xdg.configFile."xdg-desktop-portal/hyprland-portals.conf".source =
    dotfilesLink ".config/xdg-desktop-portal/hyprland-portals.conf";
}

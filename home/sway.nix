# Machines running the Sway desktop (desktop and laptop).
# Sway itself, Waybar and the other graphical programs come from apt or the
# self-built prefixes in ~/.local/opt (see ansible/setup.yaml): Nix-built GUI
# programs can't find the NVIDIA/Mesa drivers on a non-NixOS system.
{ pkgs, dotfilesLink, ... }:
{
  dotfiles.configDirs = [
    "sway"
    "waybar"
    "kanshi"
    "kitty"
    "mako"
    "wofi"
    "udiskie"
  ];

  # Tray and app icons (blueman, T3 Code)
  xdg.dataFile."icons/hicolor".source = dotfilesLink ".local/share/icons/hicolor";

  xdg.configFile."environment.d/gtk.conf".source =
    dotfilesLink ".config/environment.d/gtk.conf";

  # Waybar icons and the backlight glyphs
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    font-awesome_6
    meslo-lgs-nf
  ];
}

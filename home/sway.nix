# Machines running the Sway desktop (desktop and laptop).
# Sway itself, Waybar and the other graphical programs come from the distro
# (or, on nhuto-Mint, the self-built prefixes in ~/.local/opt; see
# ansible/setup.yaml): Nix-built GUI programs can't find the NVIDIA/Mesa
# drivers on a non-NixOS system.
{ pkgs, dotfilesLink, ... }:
{
  imports = [ ./zoom.nix ];
  dotfiles.configDirs = [
    "sway"
    "waybar"
    "kanshi"
    "kitty"
    "mako"
    "wofi"
    "udiskie"
  ];

  # CopyQ's theme in the window colours. Only the theme is linked: the rest of
  # ~/.config/copyq is CopyQ's own settings and clipboard history
  xdg.configFile."copyq/themes/wm.ini".source = dotfilesLink ".config/copyq/themes/wm.ini";

  # Tray and app icons (blueman, T3 Code)
  xdg.dataFile."icons/hicolor".source = dotfilesLink ".local/share/icons/hicolor";

  # Waybar icons and the backlight glyphs
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    font-awesome_6
    meslo-lgs-nf
  ];
}

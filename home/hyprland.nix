# Hyprland's configs, on any distro: Hyprland itself, hyprpaper, hypridle,
# hyprlock and the hyprtoolkit apps (.config/hypr), fuzzel as the launcher for
# apps, commands and windows (.config/fuzzel), and the portal choice. The
# programs come from the distro; on nhuto-Mint (Ubuntu has no Hyprland) from
# Nix instead, see home/hosts/nhuto-Mint.nix.
{ dotfilesLink, ... }:
{
  imports = [ ./zoom.nix ];
  dotfiles.configDirs = [ "hypr" "fuzzel" ];

  # FSearch's look, in the sandbox config dir of its Flatpak so only it gets it
  # (the stylesheet explains)
  home.file.".var/app/io.github.cboxdoerfer.FSearch/config/gtk-3.0/gtk.css".source =
    dotfilesLink ".config/fsearch/gtk.css";

  # GTK 3's stylesheet, for every GTK 3 app (the file explains). Just the file:
  # ~/.config/gtk-3.0 also holds GTK's bookmarks.
  xdg.configFile."gtk-3.0/gtk.css".source = dotfilesLink ".config/gtk-3.0/gtk.css";

  # Which portal backends Hyprland sessions use
  xdg.configFile."xdg-desktop-portal/hyprland-portals.conf".source =
    dotfilesLink ".config/xdg-desktop-portal/hyprland-portals.conf";
}

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

  # GTK 4 and portal apps (Nautilus, file pickers) and hyprland.lua's cursor read
  # these gsettings, not settings.ini; on CachyOS they start as adw-gtk3-dark,
  # Adwaita and the "default" cursor. Same theme, icons and cursor as the
  # settings.ini files (ansible/setup.yaml installs all three), plus RGB
  # subpixel text like fontconfig's (see sway.nix).
  dconf.settings."org/gnome/desktop/interface" = {
    gtk-theme = "Orchis-Pink-Dark";
    icon-theme = "Flatery-Pink-Dark";
    cursor-theme = "Bibata-Modern-Ice";
    cursor-size = 24;
    color-scheme = "prefer-dark";
    font-antialiasing = "rgba";
    font-hinting = "slight";
    font-rgba-order = "rgb";
  };

  # The X11 / fallback cursor for programs that read neither gsettings nor
  # hyprland.lua's XCURSOR_THEME
  home.file.".icons/default/index.theme".text = ''
    [Icon Theme]
    Name=Default
    Comment=Default Cursor Theme
    Inherits=Bibata-Modern-Ice
  '';
}

# Noctalia, the shell on Hyprland machines: the config (dotfiles.toml and the
# files it includes, layered over CachyOS's own config.toml, which stays local),
# the palette, the flat tray icons and the shared plugins. Machine-specific bar
# widgets and their plugins go in .config/noctalia/hosts/<host>.toml, linked as
# noctalia/host.toml by the host's module (see home/hosts/nhuto.nix).
{ dotfilesLink, ... }:
{
  xdg.configFile."noctalia/dotfiles.toml".source = dotfilesLink ".config/noctalia/dotfiles.toml";
  xdg.configFile."noctalia/dotfiles".source = dotfilesLink ".config/noctalia/dotfiles";
  xdg.configFile."noctalia/palettes/Waybar.json".source = dotfilesLink ".config/noctalia/palettes/Waybar.json";
  xdg.configFile."systemd/user/noctalia-flat-tray.service".source =
    dotfilesLink ".config/systemd/user/noctalia-flat-tray.service";
  xdg.configFile."systemd/user/graphical-session.target.wants/noctalia-flat-tray.service".source =
    dotfilesLink ".config/systemd/user/noctalia-flat-tray.service";
  xdg.dataFile = builtins.listToAttrs (map
    (name: { name = "noctalia/plugins/${name}"; value.source = dotfilesLink ".local/share/noctalia/plugins/${name}"; })
    [ "bar-button" "media" ]) // {
      "noctalia/tray-icons".source = dotfilesLink ".local/share/noctalia/tray-icons";
    };
}

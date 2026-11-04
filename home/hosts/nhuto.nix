# The desktop (RTX 4080, local LLM server), whatever the distro: imported by
# nhuto-Mint.nix (Linux Mint) and used as is by the CachyOS install.
{ dotfilesLink, ... }:
{
  dotfiles.configDirs = [ "llama-serve" ];

  xdg.configFile."systemd/user/llama-serve.service".source =
    dotfilesLink ".config/systemd/user/llama-serve.service";
  xdg.configFile."systemd/user/default.target.wants/llama-serve.service".source =
    dotfilesLink ".config/systemd/user/llama-serve.service";

  # The service's restore hook, and the tools wired to the router (local-llama notes)
  home.file = builtins.listToAttrs (map
    (name: { name = ".local/bin/${name}"; value.source = dotfilesLink ".local/bin/${name}"; })
    [ "llama-state" "opencode-llama-sync" "sbx-llama" ]);

  # Noctalia (CachyOS's shell): the config (dotfiles.toml and the files it
  # includes, layered over CachyOS's own config.toml, which stays local), the
  # palette, and the llama.cpp and ZMK battery meter plugins
  xdg.configFile."noctalia/dotfiles.toml".source = dotfilesLink ".config/noctalia/dotfiles.toml";
  xdg.configFile."noctalia/dotfiles".source = dotfilesLink ".config/noctalia/dotfiles";
  xdg.configFile."noctalia/palettes/Waybar.json".source = dotfilesLink ".config/noctalia/palettes/Waybar.json";
  xdg.dataFile = builtins.listToAttrs (map
    (name: { name = "noctalia/plugins/${name}"; value.source = dotfilesLink ".local/share/noctalia/plugins/${name}"; })
    [ "llama-meter" "zmk-battery" ]);
}

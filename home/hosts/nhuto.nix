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
    [ "llama-ask" "llama-current-model" "llama-key" "llama-state" "opencode" "opencode-llama-sync" "sbx-llama" ])
    // {
      # Pi starts on the model the router already has loaded (see the extension for the rules)
      ".pi/agent/extensions/llama-current-model.ts".source =
        dotfilesLink ".pi/agent/extensions/llama-current-model.ts";
      # Shared helpers the tools above source (port detection, resident model, last-model path)
      ".local/lib/llama.sh".source = dotfilesLink ".local/lib/llama.sh";
    };

  # Noctalia (CachyOS's shell): the config (dotfiles.toml and the files it
  # includes, layered over CachyOS's own config.toml, which stays local), the
  # palette, and the llama.cpp and ZMK battery meter plugins
  xdg.configFile."noctalia/dotfiles.toml".source = dotfilesLink ".config/noctalia/dotfiles.toml";
  xdg.configFile."noctalia/dotfiles".source = dotfilesLink ".config/noctalia/dotfiles";
  xdg.configFile."noctalia/palettes/Waybar.json".source = dotfilesLink ".config/noctalia/palettes/Waybar.json";
  xdg.configFile."systemd/user/noctalia-flat-tray.service".source =
    dotfilesLink ".config/systemd/user/noctalia-flat-tray.service";
  xdg.configFile."systemd/user/graphical-session.target.wants/noctalia-flat-tray.service".source =
    dotfilesLink ".config/systemd/user/noctalia-flat-tray.service";
  xdg.dataFile = builtins.listToAttrs (map
    (name: { name = "noctalia/plugins/${name}"; value.source = dotfilesLink ".local/share/noctalia/plugins/${name}"; })
    [ "bar-button" "llama-meter" "media" "zmk-battery" ]) // {
      "noctalia/tray-icons".source = dotfilesLink ".local/share/noctalia/tray-icons";
    };
}

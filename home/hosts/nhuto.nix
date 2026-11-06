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

  # Noctalia's desktop extras: the llama.cpp and ZMK battery meters, and the
  # bar layout and plugin list that use them
  imports = [ ../noctalia.nix ];
  xdg.configFile."noctalia/host.toml".source = dotfilesLink ".config/noctalia/hosts/nhuto.toml";
  xdg.dataFile = builtins.listToAttrs (map
    (name: { name = "noctalia/plugins/${name}"; value.source = dotfilesLink ".local/share/noctalia/plugins/${name}"; })
    [ "llama-meter" "zmk-battery" ]);
}

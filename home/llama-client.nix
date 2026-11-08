# Use the desktop's llama.cpp router (nhuto, HTTPS on the tailnet) instead of a local one: opencode and Pi plus the
# llama-* helpers, pointed at LLAMA_URL. The API key is not in the repo: copy it once with
#   ssh nhuto 'cat ~/.local/state/llama-serve/api-key' > ~/.local/state/llama-serve/api-key && chmod 600 $_
# then `opencode-llama-sync` writes opencode's model list; Pi discovers models itself (~/.pi/agent/auth.json).
{ dotfilesLink, ... }:
{
  home.file = builtins.listToAttrs (map
    (name: { name = ".local/bin/${name}"; value.source = dotfilesLink ".local/bin/${name}"; })
    [ "llama-ask" "llama-current-model" "opencode" "opencode-llama-sync" ])
    // {
      ".pi/agent/extensions/llama-current-model.ts".source =
        dotfilesLink ".pi/agent/extensions/llama-current-model.ts";
      ".local/lib/llama.sh".source = dotfilesLink ".local/lib/llama.sh";
    };

  xdg.configFile."environment.d/llama-remote.conf".source =
    dotfilesLink ".config/environment.d/llama-remote.conf";
}

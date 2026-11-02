# Desktop only: RTX 4080, local LLM server
{ dotfilesLink, ... }:
{
  dotfiles.configDirs = [ "llama-serve" ];

  xdg.configFile."systemd/user/llama-serve.service".source =
    dotfilesLink ".config/systemd/user/llama-serve.service";
  xdg.configFile."systemd/user/default.target.wants/llama-serve.service".source =
    dotfilesLink ".config/systemd/user/llama-serve.service";

  # This PC's theme override (gitignored)
  xdg.configFile."environment.d/zz-local.conf".source =
    dotfilesLink ".config/environment.d/zz-local.conf";
}

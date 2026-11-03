# Desktop only: RTX 4080, local LLM server
{ pkgs, lib, dotfilesLink, ... }:
{
  dotfiles.configDirs = [ "llama-serve" ];

  xdg.configFile."systemd/user/llama-serve.service".source =
    dotfilesLink ".config/systemd/user/llama-serve.service";
  xdg.configFile."systemd/user/default.target.wants/llama-serve.service".source =
    dotfilesLink ".config/systemd/user/llama-serve.service";

  # Nix programs (Hyprland) get this copy of the NVIDIA driver; it must match
  # the installed driver exactly. After a driver update: set the new version,
  # get its hash with
  #   nix store prefetch-file https://download.nvidia.com/XFree86/Linux-x86_64/<version>/NVIDIA-Linux-x86_64-<version>.run
  # switch, then run the `sudo .../non-nixos-gpu-setup` that the switch prints.
  targets.genericLinux.gpu.nvidia = {
    enable = true;
    version = "610.57.04";
    sha256 = "sha256-suk1xmuDuwDAyFe8jg7g/VLekoa0DJzB7sKafOfrEW0=";
  };
  # The driver is unfree; allow just it
  targets.genericLinux.gpu.packages = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = pkg: lib.getName pkg == "nvidia-x11";
    config.nvidia.acceptLicense = true;
  };

  # This PC's theme override (gitignored)
  xdg.configFile."environment.d/zz-local.conf".source =
    dotfilesLink ".config/environment.d/zz-local.conf";
}

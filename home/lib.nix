# Helpers for linking files from the repo checkout (not copies in the Nix
# store), so they stay editable in place, like the old hand-made symlinks.
{ config, lib, ... }:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in {
  options.dotfiles = {
    configDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Folders in .dotfiles/.config to link into ~/.config.";
    };
    homeFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths in .dotfiles to link to the same path under ~.";
    };
  };

  config = {
    xdg.configFile = lib.genAttrs config.dotfiles.configDirs
      (dir: { source = link ".config/${dir}"; });

    home.file = lib.genAttrs config.dotfiles.homeFiles
      (path: { source = link path; });

    # Used by the modules for one-off links
    _module.args.dotfilesLink = link;
  };
}

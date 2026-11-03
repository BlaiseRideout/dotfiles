# Shared by every machine: shell, editors, tmux, powerline, ssh, scripts.
{ lib, pkgs, username, dotfilesLink, ... }:
{
  imports = [ ./lib.nix ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";   # leave as is; see `man home-configuration.nix`

  # targets.genericLinux is left off: it adds an environment.d file changing
  # XDG_DATA_DIRS and locale paths for the whole session, plus a GPU-driver shim,
  # which only matter for graphical programs from Nix; those come from apt here.

  programs.home-manager.enable = true;
  programs.man.enable = false;   # keep the system man, not a Nix copy in front of it

  # A current fzf (Ubuntu 24.04's is 0.44): the shells' key bindings come from
  # `fzf --zsh` / `fzf --bash`, and hypr/clipboard.sh's vim keys need 0.59+
  home.packages = [ pkgs.fzf ];

  dotfiles.homeFiles = [
    ".profile"
    ".bashrc"
    ".zshrc"
    ".tmux.conf"
    ".vimrc"
    ".vim/colors"
    ".Xresources"
    ".Xmodmap"
    ".ssh/config"
    ".ssh/authorized_keys"
  ];

  # Linked per file, so ~/scripts can also hold scripts that aren't in the repo.
  # A new script needs a switch (and `git add`) before it's linked.
  home.file = lib.mapAttrs'
    (name: _: lib.nameValuePair "scripts/${name}" { source = dotfilesLink "scripts/${name}"; })
    (builtins.readDir ../scripts);

  dotfiles.configDirs = [
    "nvim"
    "powerline"   # used by the zsh, bash and tmux prompts
    "feh"
    "gsimplecal"
  ];

  # environment.d is linked per file so a machine can add its own
  # (e.g. a gitignored zz-local.conf, linked from hosts/<host>.nix)
  xdg.configFile."environment.d/ssh-agent.conf".source =
    dotfilesLink ".config/environment.d/ssh-agent.conf";

  # User units are linked rather than generated, so they can still be edited
  # in place (then `systemctl --user daemon-reload`). The wants link enables it.
  xdg.configFile."systemd/user/ssh-agent.service".source =
    dotfilesLink ".config/systemd/user/ssh-agent.service";
  xdg.configFile."systemd/user/default.target.wants/ssh-agent.service".source =
    dotfilesLink ".config/systemd/user/ssh-agent.service";
}

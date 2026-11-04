# Shared by every machine: shell, editors, tmux, powerline, ssh, scripts.
{ config, lib, username, dotfilesLink, ... }:
{
  imports = [ ./lib.nix ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";   # leave as is; see `man home-configuration.nix`

  # targets.genericLinux is left off: it adds an environment.d file changing
  # XDG_DATA_DIRS and locale paths for the whole session, plus a GPU-driver shim,
  # which only matter for graphical programs from Nix; those come from the
  # distro (except on nhuto-Mint, see home/hosts/nhuto-Mint.nix).

  programs.home-manager.enable = true;
  programs.man.enable = false;   # keep the system man, not a Nix copy in front of it

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

  # GTK's theme, icons and font: the files in the repo, so nwg-look (which writes
  # through the links) edits them in place. ansible/setup.yaml installs the
  # Orchis-Pink-Dark theme and Flatery-Pink-Dark icons these name.
  xdg.configFile."gtk-3.0/settings.ini".source = dotfilesLink ".config/gtk-3.0/settings.ini";
  xdg.configFile."gtk-4.0/settings.ini".source = dotfilesLink ".config/gtk-4.0/settings.ini";
  # libadwaita apps (Nautilus) read gtk-4.0/gtk.css: it imports Orchis-Pink-Dark and adds tweaks.
  # The dark file and images are the theme's own, as Orchis's `install.sh -l` links them.
  xdg.configFile."gtk-4.0/gtk.css".source = dotfilesLink ".config/gtk-4.0/gtk.css";
  xdg.configFile."gtk-4.0/gtk-dark.css".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.themes/Orchis-Pink-Dark/gtk-4.0/gtk-dark.css";
  xdg.configFile."gtk-4.0/assets".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.themes/Orchis-Pink-Dark/gtk-4.0/assets";

  # environment.d is linked per file so a machine can add its own
  # (e.g. a gitignored file linked from hosts/<host>.nix)
  xdg.configFile."environment.d/ssh-agent.conf".source =
    dotfilesLink ".config/environment.d/ssh-agent.conf";

  # User units are linked rather than generated, so they can still be edited
  # in place (then `systemctl --user daemon-reload`). The wants link enables it.
  xdg.configFile."systemd/user/ssh-agent.service".source =
    dotfilesLink ".config/systemd/user/ssh-agent.service";
  xdg.configFile."systemd/user/default.target.wants/ssh-agent.service".source =
    dotfilesLink ".config/systemd/user/ssh-agent.service";
}

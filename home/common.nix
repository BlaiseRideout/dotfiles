# Shared by every machine: shell, editors, tmux, powerline, ssh, scripts.
{ config, lib, pkgs, username, dotfilesLink, ... }:
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

  # sshd's StrictModes refuses an authorized_keys that is group/world-writable,
  # as is any directory above it. The link points into this checkout, which a
  # umask of 002 leaves 664/775, so drop the write bits on every switch.
  home.activation.sshStrictModes = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    for p in "$HOME/.dotfiles" "$HOME/.dotfiles/.ssh" "$HOME/.dotfiles/.ssh/authorized_keys"; do
      if [ -e "$p" ]; then
        run chmod go-w "$p"
      fi
    done
  '';

  # Linked per file, so ~/scripts can also hold scripts that aren't in the repo.
  # A new script needs a switch (and `git add`) before it's linked.
  home.file = lib.mapAttrs'
    (name: _: lib.nameValuePair "scripts/${name}" { source = dotfilesLink "scripts/${name}"; })
    (builtins.readDir ../scripts) // {
      # Keep the editable .zshrc; Nix supplies the framework and plugins.
      ".local/share/zsh/oh-my-zsh".source = "${pkgs.oh-my-zsh}/share/oh-my-zsh";
      ".local/share/zsh/autosuggestions".source = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
      ".local/share/zsh/syntax-highlighting".source = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
    };

  dotfiles.configDirs = [
    "nvim"
    "powerline"   # used by the zsh, bash and tmux prompts
    "feh"
    "gsimplecal"
  ];

  # Own names for the user dirs instead of xdg-user-dirs' capitalized defaults.
  # Templates and Public are unused: pointing them at $HOME is how xdg-user-dirs
  # says "none", and creates nothing. nhuto and nhuto-Mint have the rest as links
  # into /mnt/files, made by hand; createDirectories skips anything that is
  # already a link, so only the other machines get real folders.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/.desktop";
    documents = "${config.home.homeDirectory}/documents";
    download = "${config.home.homeDirectory}/downloads";
    music = "${config.home.homeDirectory}/audio";
    pictures = "${config.home.homeDirectory}/images";
    projects = "${config.home.homeDirectory}/prog";
    publicShare = config.home.homeDirectory;
    templates = config.home.homeDirectory;
    videos = "${config.home.homeDirectory}/videos";
  };

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

  # Qt apps use the Orchis Kvantum theme that ansible/setup.yaml installs (OrchisPinkDark);
  # just this file, since the theme folders next to it come from the playbook.
  xdg.configFile."Kvantum/kvantum.kvconfig".source = dotfilesLink ".config/Kvantum/kvantum.kvconfig";
  xdg.configFile."environment.d/qt-theme.conf".source =
    dotfilesLink ".config/environment.d/qt-theme.conf";

  # git's global ignore list. Just the file: ~/.config/git/config stays local
  xdg.configFile."git/ignore".source = dotfilesLink ".config/git/ignore";

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

  # Daily FSearch index update (fsearch -u). The timers.target link enables it.
  xdg.configFile."systemd/user/fsearch-update.service".source =
    dotfilesLink ".config/systemd/user/fsearch-update.service";
  xdg.configFile."systemd/user/fsearch-update.timer".source =
    dotfilesLink ".config/systemd/user/fsearch-update.timer";
  xdg.configFile."systemd/user/timers.target.wants/fsearch-update.timer".source =
    dotfilesLink ".config/systemd/user/fsearch-update.timer";
}

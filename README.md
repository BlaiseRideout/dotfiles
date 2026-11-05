dotfiles
========

Dotfiles and scripts I use, linked into place by [Home Manager](https://github.com/nix-community/home-manager).

New machine (Linux Mint / Ubuntu, or CachyOS / Arch):

    sudo apt install ansible git       # Mint / Ubuntu
    sudo pacman -S ansible git         # CachyOS / Arch
    git clone --recursive https://github.com/BlaiseRideout/dotfiles.git ~/.dotfiles
    cd ~/.dotfiles/ansible
    ansible-playbook setup.yaml                      # Sway
    ansible-playbook setup.yaml -e hyprland=true     # ...plus Hyprland (default on nhuto, nhuto-Mint)
    ansible-playbook setup.yaml -e desktop=openbox   # Openbox + tint2
    ansible-playbook setup.yaml -e apps=false        # skip the desktop apps (GIMP, Spotify, VS Code, ...)
    ansible-playbook setup.yaml -e build_sway=true   # apt: self-built Sway 1.11 + Waybar (default on nhuto-Mint)

This installs the distro's packages (apt or pacman, whichever is there), Nix
and the Home Manager config for this machine (`<user>@<hostname>` in
`flake.nix`, or `-e hm_config=<name>`). The Ubuntu workarounds (Hyprland from
Nix, the self-built Sway) are only on by default for nhuto-Mint.

Layout:

- `flake.nix`: one Home Manager config per machine
- `home/common.nix`: every machine (shell, vim/nvim, tmux, powerline, ssh, scripts)
- `home/sway.nix`, `home/hyprland.nix`, `home/openbox.nix`: per desktop
- `home/hosts/<hostname>.nix`: per machine (`nhuto-Mint.nix` holds the Ubuntu workarounds)
- `build/`: the self-built Sway 1.11 and Waybar, and the Nix Hyprland session (Mint only)
- `ansible/setup.yaml`: system setup

Linked files point into this checkout, so edits take effect without a rebuild.
After changing a `.nix` file: `home-manager switch --flake ~/.dotfiles`
(new files must be `git add`ed first, or Nix won't see them).

Zsh uses Oh My Zsh with the existing Powerline prompt. Home Manager supplies
Oh My Zsh, zsh-autosuggestions and zsh-syntax-highlighting; `.zshrc` stays editable.

- Gray suggestions come from history, then completion: Right/End accepts them;
  Alt-Right accepts a word.
- Type part of a command and press Up/Down (or Ctrl-P/Ctrl-N) to search history.
- Ctrl-R opens fzf history search; Ctrl-Y opens the existing file picker.
- Tab offers grouped, case-insensitive completion; commands are highlighted as you type.
- History keeps 100,000 entries shared across shells. Start a command with a space
  to leave it out of saved history.

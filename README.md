dotfiles
========

Dotfiles and scripts I use, linked into place by [Home Manager](https://github.com/nix-community/home-manager).

New machine (Linux Mint / Ubuntu):

    sudo apt install ansible git
    git clone --recursive https://github.com/BlaiseRideout/dotfiles.git ~/.dotfiles
    cd ~/.dotfiles/ansible
    ansible-playbook setup.yaml                      # Sway
    ansible-playbook setup.yaml -e build_sway=true   # Sway, plus self-built Sway 1.11 + Waybar (NVIDIA)
    ansible-playbook setup.yaml -e desktop=openbox   # Openbox + tint2
    ansible-playbook setup.yaml -e apps=false        # skip the desktop apps (GIMP, Spotify, VS Code, ...)

This installs the apt packages, Nix and the Home Manager config for this
machine (`<user>@<hostname>` in `flake.nix`, or `-e hm_config=<name>`).

Layout:

- `flake.nix`: one Home Manager config per machine
- `home/common.nix`: every machine (shell, vim/nvim, tmux, powerline, ssh, scripts)
- `home/sway.nix`, `home/openbox.nix`: per desktop
- `home/hosts/<hostname>.nix`: per machine
- `build/`: build scripts for the self-built Sway 1.11 and Waybar
- `ansible/setup.yaml`: system setup

Linked files point into this checkout, so edits take effect without a rebuild.
After changing a `.nix` file: `home-manager switch --flake ~/.dotfiles`
(new files must be `git add`ed first, or Nix won't see them).

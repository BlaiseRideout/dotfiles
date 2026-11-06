{
  description = "Blaise's dotfiles (Home Manager)";

  # Apply with:  home-manager switch --flake ~/.dotfiles
  # That picks the configuration named "$USER@$(hostname)"; pass
  # --flake ~/.dotfiles#<name> to choose one explicitly (e.g. on a new machine).
  #
  # Configs are linked out of the store (see home/lib.nix), so editing a file in
  # ~/.dotfiles takes effect immediately; a switch is only needed when a .nix
  # file changes. New .nix files must be `git add`ed before Nix can see them.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      mkHome = { username, modules }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = { inherit username; };
          modules = [ ./home/common.nix ] ++ modules;
        };
    in {
      homeConfigurations = {
        # Desktop on Linux Mint 22: Sway and Hyprland on NVIDIA, with the
        # Ubuntu workarounds (home/hosts/nhuto-Mint.nix)
        "blaise@nhuto-Mint" = mkHome {
          username = "blaise";
          modules = [ ./home/sway.nix ./home/hyprland.nix ./home/hosts/nhuto-Mint.nix ];
        };

        # The same desktop on CachyOS: the programs come from its packages
        "blaise@nhuto" = mkHome {
          username = "blaise";
          modules = [ ./home/sway.nix ./home/hyprland.nix ./home/hosts/nhuto.nix ];
        };

        # Yoga Book 9i (13IMU9) on CachyOS: the desktop's Hyprland + Noctalia
        # setup (sway.nix too, for the scripts, kitty and fonts it shares),
        # without the llama.cpp server
        "blaise@yoga-linux" = mkHome {
          username = "blaise";
          modules = [ ./home/sway.nix ./home/hyprland.nix ./home/noctalia.nix ./home/hosts/yoga-linux.nix ];
        };

        # Laptop: Sway. Rename to "<user>@<hostname>" so a bare
        # `home-manager switch --flake ~/.dotfiles` finds it.
        laptop = mkHome {
          username = "blaise";
          modules = [ ./home/sway.nix ];
        };

        # Openbox + tint2
        "blaise@uhnet" = mkHome {
          username = "blaise";
          modules = [ ./home/openbox.nix ];
        };
      };
    };
}

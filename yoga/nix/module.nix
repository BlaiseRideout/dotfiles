# Home Manager module for the Lenovo Yoga Book 9i (13IMU9): links the Yoga's
# scripts, user services and Noctalia host file from this tree into the home
# directory. Nothing is copied: the links point into the checkout, so the files
# stay editable in place.
#
#   imports = [ ./yoga/nix/module.nix ];
#   yoga.enable = true;
#
# What it does not do: the Hyprland side (yoga/hypr/ is found and loaded by
# hyprland.lua itself), the system side (kernel module, udev rules, wvkbd build,
# Secure Boot: ansible/yoga.yaml) or the packages (see yoga/README.md).
{ config, lib, ... }:
let
  cfg = config.yoga;
  link = path: config.lib.file.mkOutOfStoreSymlink "${cfg.sourceDir}/${path}";

  # yoga/bin, linked into ~/.local/bin
  scripts = [
    "yoga-osk"                # on-screen keyboard (wvkbd) toggle; docs/yoga-book/touch-ux.md
    "yoga-osk-lockwatch"      # shows it over the lock screen
    "yoga-lock-face"          # face rescan when the locked screen wakes from idle; docs/yoga-book/faceunlock.md
    "yoga-touch"              # hyprgrass plugin control + rescue (`yoga-touch recover`)
    "yoga-posture"            # posture daemon + CLI; docs/yoga-book/posture-daemon.md
    "yoga-touchpad"           # virtual touchpad daemon + CLI; docs/yoga-book/touchpad.md
    "yoga-touchpad-indicator" # outline of the touchpad strip on the bottom screen
    "yoga-bottom-reserve"     # moves the bottom screen's workspace away while the keyboard is up
    "yoga-palm"               # palm rejection for the touchscreens; docs/yoga-book/palm.md
    "yoga-dock-peek"          # shows Noctalia's dock for a moment (swipe up from the bottom edge)
    "yoga-launcher"           # launcher the on-screen keyboard can type into
    "yoga-launch"             # its fuzzel --launch-prefix
    "yoga-platform-status"    # platform health in one screen; docs/yoga-book/platform.md
  ] ++ lib.optional cfg.clipStudio.enable "clip-studio-paint";

  # yoga/systemd, linked into ~/.config/systemd/user and wanted by the graphical
  # session like the Noctalia tray unit
  services = [
    "yoga-posture"
    "yoga-touchpad"
    "yoga-osk-lockwatch"
    "yoga-touchpad-indicator"
    "yoga-bottom-reserve"
    "yoga-palm"
    "yoga-audio-levels"
  ];
in
{
  options.yoga = {
    enable = lib.mkEnableOption "the Lenovo Yoga Book 9i support (scripts, user services, Noctalia host file)";

    sourceDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.dotfiles/yoga";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.dotfiles/yoga"'';
      description = ''
        Absolute path of the checkout of this tree (the folder holding bin/,
        systemd/, hypr/, ...). Links point there, outside the Nix store. The Hyprland
        module (hypr/yoga.lua) looks for the tree at ~/.dotfiles/yoga, or at
        $YOGA_DIR.
      '';
    };

    noctalia.linkHost = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Link noctalia/host.toml as ~/.config/noctalia/host.toml (the Yoga's bar:
        no GPU gauges, battery, brightness, keyboard battery, on-screen keyboard
        button). Turn off where the host file is provided elsewhere.
      '';
    };

    clipStudio.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Clip Studio Paint (Bottles, docs/yoga-book/clip-studio.md) in the launcher
        menu: the entry runs clip-studio-paint, which finds the exe in the
        CSP-wine11 bottle.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.listToAttrs (map (name: {
      name = ".local/bin/${name}";
      value.source = link "bin/${name}";
    }) scripts);

    xdg.configFile =
      lib.listToAttrs (map (name: {
        name = "systemd/user/${name}.service";
        value.source = link "systemd/${name}.service";
      }) services)
      // lib.listToAttrs (map (name: {
        name = "systemd/user/graphical-session.target.wants/${name}.service";
        value.source = link "systemd/${name}.service";
      }) services)
      // lib.optionalAttrs cfg.noctalia.linkHost {
        "noctalia/host.toml".source = link "noctalia/host.toml";
      }
      // {
        # Software volume for the speakers: with the hardware mixer the volume slider only moved
        # the treble path ("Speaker"), not the bass amps ("DAC2"). With soft-mixer the two hardware
        # levels stay fixed (yoga-audio-levels.service sets them) and the slider scales both. From
        # https://github.com/andrewgodwin/lenovo-yoga-book-9 (wireplumber/); docs/yoga-book/platform.md.
        "wireplumber/wireplumber.conf.d/99-yoga-software-volume.conf".text = ''
          monitor.alsa.rules = [
            {
              matches = [
                { device.name = "~alsa_card.pci-0000_00_1f.3.*" }
              ]
              actions = {
                update-props = {
                  api.alsa.soft-mixer = true
                }
              }
            }
          ]
        '';
      };

    # The Yoga's battery gauges, a plugin of its own (the desktop uses zmk-battery)
    xdg.dataFile = lib.optionalAttrs cfg.noctalia.linkHost {
      "noctalia/plugins/yoga-battery".source = link "noctalia/plugins/yoga-battery";
    } // lib.optionalAttrs cfg.clipStudio.enable {
      "applications/clip-studio-paint.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Clip Studio Paint
        GenericName=Digital Painting
        Comment=Clip Studio Paint, run with Bottles (Wine)
        Exec=${config.home.homeDirectory}/.local/bin/clip-studio-paint
        Icon=applications-graphics
        Terminal=false
        Categories=Graphics;2DGraphics;RasterGraphics;
        Keywords=drawing;painting;manga;comic;csp;celsys;
        StartupNotify=true
      '';
    };
  };
}

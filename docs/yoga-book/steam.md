# Steam

## Packages (`ansible/yoga.yaml`, switch `yoga_gaming`)

```
sudo pacman -S --needed steam cachyos-gaming-meta gamescope mangohud lib32-mangohud \
    vulkan-intel lib32-vulkan-intel
```

- `[multilib]` must be enabled (`steam` and the `lib32-*` packages). The 32-bit Intel Vulkan stack was already
  installed.
- **`proton-cachyos` is not a package.** `cachyos-gaming-meta` pulls `proton-cachyos-slr` (built for the Steam
  Linux Runtime; the one to use), `wine-cachyos-opt`, `umu-launcher`, `winetricks`, `protontricks`, `vulkan-tools`.
  Together about 2.5 GB. `proton-cachyos-native` also exists.
- If pacman stops on `/usr/lib/modules-load.d/ntsync.conf` (both `cachyos-settings` and `wine`'s `ntsync-autoload`
  ship it): `sudo pacman -S --needed --overwrite /usr/lib/modules-load.d/ntsync.conf wine` once.
- `gamemode` is left out on purpose; see the power profile below.
- NTSync works: `/dev/ntsync` exists, loaded at boot by `cachyos-settings`.

## Setup

1. Start Steam from the menu and log in.
2. Settings -> Compatibility: Steam Play for all titles, default tool **proton-cachyos-slr**.
3. If the UI is tiny or blurry (scale 2): `STEAM_FORCE_DESKTOPUI_SCALING=2 steam`.
4. Leave shader pre-caching on (Intel iGPU shader compiles are the main stutter source).

## Power profile while gaming

`power-profiles-daemon` is the profile manager; `game-performance` (from `cachyos-settings`) sets `performance`
for a game via a launch option: `game-performance %command%`. Whether the EC lets `performance` stick on battery
is unchecked.

## Which panel games open on

Not implemented. A window rule on Steam's game class (`steam_app_*`) to the top panel's workspace is the obvious
way; the snippet was drafted but not applied. Games on the bottom screen while the keyboard is docked would be
under the keyboard.

## Not verified

No game has been run. A 32-bit Vulkan smoke test (`vkcube32`) would settle the `lib32-vulkan-intel` path;
suspend during a game and sustained thermals are untested.

# The Yoga Book 9i (13IMU9): dual touchscreen, detachable Bluetooth keyboard.
# Everything Yoga-specific lives in yoga/ (README.md there); this host only
# switches its Home Manager module on. Host-specific overrides (a different
# checkout path, no Clip Studio launcher, ...) would go here as yoga.* options.
{ ... }:
{
  imports = [ ../../yoga/nix/module.nix ../llama-client.nix ];
  yoga.enable = true;
}

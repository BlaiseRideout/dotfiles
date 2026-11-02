# The Openbox + tint2 machine
{ ... }:
{
  dotfiles.configDirs = [
    "openbox"
    "tint2"
  ];

  dotfiles.homeFiles = [
    ".autostart.sh"   # run from openbox/autostart
  ];
}

# Keep Zoom's generated config writable; manage only these two platform keys.
{ config, lib, pkgs, dotfilesLink, ... }:
{
  home.activation.zoomWayland = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python ${dotfilesLink "scripts/configure-zoom.py"}
  '';
  home.file.".local/bin/zoom".source = dotfilesLink "scripts/zoom.sh";
  # The session may search /usr/share before Nix's profile. A local override
  # ensures meeting links and app launchers use the wrapper on those systems too.
  xdg.dataFile."applications/Zoom.desktop".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.profileDirectory}/share/applications/Zoom.desktop";
  xdg.desktopEntries.Zoom = {
    name = "Zoom Workplace";
    comment = "Zoom Video Conference";
    exec = "${config.home.homeDirectory}/scripts/zoom.sh %U";
    icon = "Zoom";
    terminal = false;
    categories = [ "Network" "VideoConference" ];
    mimeType = [ "x-scheme-handler/zoommtg" "x-scheme-handler/zoomus"
      "x-scheme-handler/tel" "x-scheme-handler/callto"
      "x-scheme-handler/zoomphonecall" "x-scheme-handler/zoomphonesms"
      "x-scheme-handler/zoomcontactcentercall" "application/x-zoom" ];
    settings.StartupWMClass = "Zoom";
  };
}

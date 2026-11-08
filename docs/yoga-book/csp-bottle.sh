#!/usr/bin/env bash
# Create a Bottles bottle for Clip Studio Paint (Flatpak Bottles, user install).
# Recipe from docs/yoga-book/clip-studio.md. Safe to re-run: it skips what exists.
#
#   ./csp-bottle.sh baseline                 # tasks.md starting point: caffe-9.2, DXVK 2.5.2, vkd3d-proton 2.14.1
#   ./csp-bottle.sh wine11                   # kron4ek Wine 11.20 staging, NTSync, DXVK 2.5.2, vkd3d-proton 2.14.1
#   ./csp-bottle.sh wine11 NAME RUNNER       # your own bottle name / runner (see `list-runners`)
#   ./csp-bottle.sh list-runners             # runners Bottles can download (catalog is cached after first use)
#   ./csp-bottle.sh install PATH_TO_CSP_SETUP.exe [BOTTLE]
#
# Nothing here needs root. The installer is not included: it is Celsys' own
# (a licence is needed to use the app past the trial), download it yourself.
set -euo pipefail

APP=com.usebottles.bottles
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
cli() { flatpak run --command=bottles-cli "$APP" "$@"; }

want_flatpak() {
  flatpak --user info "$APP" >/dev/null 2>&1 && return
  flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak --user install --noninteractive flathub "$APP"
}

# Wine inside the Bottles sandbox cannot see the home directory. Give it read-only
# access to ~/Downloads so the installer can be started from there.
sandbox_access() {
  flatpak override --user --filesystem=xdg-download:ro "$APP"
}

# bottles-cli cannot fetch a named runner/DXVK/vkd3d (it falls back to its newest defaults),
# so install them first with the Bottles ComponentManager.
fetch_components() { # runner
  flatpak run --filesystem="$HERE":ro --command=python3 "$APP" "$HERE/bottles-install-components.py" \
    "runner:$1" dxvk:dxvk-2.5.2 vkd3d:vkd3d-proton-2.14.1
}

make_bottle() { # name runner
  local name=$1 runner=$2
  fetch_components "$runner"
  if cli list bottles 2>/dev/null | grep -qx -- "- $name"; then
    echo "bottle $name exists, leaving it"
  else
    cli new --bottle-name "$name" --environment application --arch win64 \
        --runner "$runner" --dxvk dxvk-2.5.2 --vkd3d vkd3d-proton-2.14.1
  fi
  # Without this, the first wineboot after `new` opens a Wine Mono installer dialog that
  # never finishes inside the sandbox and hangs `edit` (seen with Wine 11.20). CSP does not
  # need Mono. It DOES need mshtml (Wine's embedded Gecko): with mshtml disabled the setup's
  # "Try for free" page loops on a failed HTMLDocument COM create at ~70% CPU and looks frozen.
  cli edit -b "$name" --env-var 'WINEDLLOVERRIDES=mscoree=d'
  # Windows 8.1: Windows 10 may crash CSP at start (tasks.md). `bottles-cli edit --win` hangs
  # in its own wineboot here (Wine 11.20 in the sandbox), so set it with the runner's winecfg
  # and record it in bottle.yml.
  local data=~/.var/app/$APP/data/bottles
  flatpak run --command=sh "$APP" -c "export WINEPREFIX='$data/bottles/$name' \
      WINEDLLOVERRIDES='mscoree,mshtml=d;winemenubuilder.exe=d' WINEDEBUG=-all; \
      '$data/runners/$runner/bin/wine' winecfg -v win81"
  sed -i 's/^Windows: .*/Windows: win81/' "$data/bottles/$name/bottle.yml"
  # NTSync needs /dev/ntsync (module ntsync; it exists here, mode 0666) and a runner built with it
  cli edit -b "$name" --params sync:ntsync
  # Plain Xwayland first. Flip to Wine's Wayland driver only to compare:
  #   bottles-cli edit -b NAME --params wayland:true
  cli edit -b "$name" --params wayland:false
  # DXVK/vkd3d on; CSP's own canvas does not use them, only its UI/WebView parts might
  cli edit -b "$name" --params dxvk:true
  cli edit -b "$name" --params vkd3d:true
  # The CJK fonts CSP wants for Japanese UI text and brush names (~15 downloads, a few minutes).
  # bottles-cli's own `shell` runs Windows commands, so call the Flatpak's winetricks directly.
  flatpak run --command=sh "$APP" -c "export WINEPREFIX='$data/bottles/$name' \
      WINE='$data/runners/$runner/bin/wine' WINESERVER='$data/runners/$runner/bin/wineserver' \
      WINEDLLOVERRIDES='mscoree,mshtml=d;winemenubuilder.exe=d' WINEDEBUG=-all; \
      winetricks -q cjkfonts" || echo "cjkfonts failed: install it from Bottles > bottle > Dependencies"
}

case ${1:-} in
  baseline) want_flatpak; sandbox_access; make_bottle "${2:-CSP-baseline}" "${3:-caffe-9.2}" ;;
  wine11)   want_flatpak; sandbox_access; make_bottle "${2:-CSP-wine11}"   "${3:-kron4ek-wine-11.20-staging-amd64}" ;;
  list-runners)
    f=$(ls ~/.var/app/$APP/data/bottles/temp/repositories/components/*/catalog.yml 2>/dev/null | head -1 || true)
    [ -n "$f" ] || { cli list components >/dev/null 2>&1 || true
                     f=$(ls ~/.var/app/$APP/data/bottles/temp/repositories/components/*/catalog.yml | head -1); }
    grep -E '^(caffe|soda|kron4ek-wine|wine-ge|sys)[A-Za-z0-9._-]*:' "$f" | tr -d : | head -80 ;;
  install)
    exe=${2:?path to the Celsys installer, e.g. ~/Downloads/CSPInstaller.exe}
    bottle=${3:-CSP-wine11}
    # The installer is a Celsys web installer or full .exe; run the setup in the bottle
    cli run -b "$bottle" -e "$exe" ;;
  *) sed -n 2,12p "$0"; exit 1 ;;
esac

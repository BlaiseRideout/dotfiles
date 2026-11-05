#!/bin/sh
# Starts Noctalia with an asset bundle whose bar media widget has no "Nothing
# Playing" label: the text is a translation string with no setting, and an
# empty string shows the key instead, so it's a single space. The bundle is
# symlinks to the packaged assets plus patched translation files, rebuilt on
# every start so package updates carry through. The control center's, the lock
# screen's and the desktop widgets' own "Nothing Playing" are untouched.

src=/usr/share/noctalia/assets
dst=${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/assets

if [ -d "$src/translations" ] && command -v python3 >/dev/null 2>&1; then
  rm -rf "$dst"
  mkdir -p "$dst/translations"
  for f in "$src"/*; do
    [ "${f##*/}" = translations ] || ln -s "$f" "$dst/"
  done
  python3 - "$src/translations" "$dst/translations" <<'PY'
import json, os, sys
src, dst = sys.argv[1:]
for name in os.listdir(src):
    path = os.path.join(src, name)
    if not name.endswith(".json"):
        os.symlink(path, os.path.join(dst, name))
        continue
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    media = data.get("bar", {}).get("widgets", {}).get("media", {})
    if "nothing-playing" in media:
        media["nothing-playing"] = " "
    with open(os.path.join(dst, name), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
PY
  NOCTALIA_ASSETS_DIR=$dst
  export NOCTALIA_ASSETS_DIR
fi

exec noctalia "$@"

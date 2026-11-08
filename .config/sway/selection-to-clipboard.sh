#!/bin/sh
# Copy highlighted text (the primary selection) to the clipboard, like
# `autocutsel -selection PRIMARY` did under Cinnamon. wl-paste runs the copy
# step each time the selection changes; skip empty selections so clearing a
# highlight doesn't wipe the clipboard. Skipped too while the clipboard holds
# an image, so highlighting text doesn't replace a copied image either.
#
# Powerline glyphs (U+E0A0-U+E0D7: the prompt/statusline separators, branch
# symbol and friends) are stripped from copied text, non-breaking spaces become
# ordinary spaces, and trailing whitespace is trimmed from each line (console
# text is padded out to the window width). That happens on the way from the
# selection to the clipboard (--copy), and again on the clipboard itself
# (--clean), which catches copies that never touch the primary selection:
# ctrl+shift+c in kitty, tmux's OSC 52 copy, and so on.

# Byte-wise so it doesn't depend on the locale: U+E0A0-E0BF is EE 82 A0-BF,
# U+E0C0-E0D7 is EE 83 80-97, and a non-breaking space (U+00A0) is C2 A0.
# Non-breaking spaces become ordinary ones (the prompt pads its lines with
# them, and they break pasted commands), then trailing spaces and tabs are
# trimmed. That order lets "branch <glyph>   " lose the padding behind a glyph.
clean_text() {
  LC_ALL=C sed -e "$(printf 's/\356\202[\240-\277]//g')" \
    -e "$(printf 's/\356\203[\200-\227]//g')" \
    -e "$(printf 's/\302\240/ /g')" \
    -e "$(printf 's/[ \t]*$//')"
}

# Leave a copied image alone: Firefox's right-click > Copy Image also selects
# the image, which sets the primary selection to some HTML-ish text and would
# otherwise replace the image in the clipboard.
clipboard_has_image() {
  wl-paste --list-types 2>/dev/null | grep -q '^image/'
}

case $1 in
  --copy)
    tmp=$(mktemp) || exit 1
    clean_text >"$tmp"
    # Look for the image only now that stdin has been read: the application
    # can be slow to hand over its selection, and an image copied in the
    # meantime must not be replaced.
    [ -s "$tmp" ] && ! clipboard_has_image && wl-copy <"$tmp"
    rm -f "$tmp"
    exit 0
    ;;
  --clean)
    raw=$(mktemp) || exit 1
    tmp=$(mktemp) || exit 1
    cat >"$raw"
    clean_text <"$raw" >"$tmp"
    # Only rewrite when something was stripped: wl-copy changes the clipboard,
    # which runs this again, and that second pass finds nothing to do.
    if [ -s "$tmp" ] && ! cmp -s "$raw" "$tmp" && ! clipboard_has_image; then
      wl-copy <"$tmp"
    fi
    rm -f "$raw" "$tmp"
    exit 0
    ;;
esac

wl-paste --type text --watch "$0" --clean &
clean=$!
trap 'kill "$clean" 2>/dev/null' EXIT INT TERM
wl-paste --primary --type text --watch "$0" --copy

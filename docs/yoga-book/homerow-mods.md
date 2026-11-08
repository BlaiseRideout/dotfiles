# Home-row mods on the Bluetooth keyboard

The keyboard runs stock firmware, so mod-taps are done on the host with [keyd](https://github.com/rvaiya/keyd).
Only the device in `[ids]` (`17ef:616a`) is grabbed; other keyboards (e.g. ZMK boards with the mods in firmware)
are left alone. Skip this if you don't want it (`-e yoga_homerow_mods=false`).

## Install

```
sudo pacman -S keyd
sudo install -Dm644 yoga/keyd/yoga-bt-kb.conf /etc/keyd/yoga-bt-kb.conf
sudo systemctl enable --now keyd          # after edits: sudo keyd reload
```
Stop it any time with `sudo systemctl stop keyd`. Check a config: `keyd check <file>`; watch: `sudo keyd monitor`.
`yoga-bt-kb.conf` is generated: edit `yoga/keyd/gen.py` and run `python3 yoga/keyd/gen.py > yoga/keyd/yoga-bt-kb.conf`.

## The mods (positional, so the OS layout doesn't matter)

| | Left | Right |
|---|---|---|
| Top row | Q alt, W gui, E ctrl, R shift | U shift, I ctrl, O gui, P alt |
| Home row | A gui, S alt, D shift, F ctrl | J ctrl, K shift, L alt, ; gui |

Hold timings follow the ZMK keymap except shift 160 ms (raised for false holds), alt/ctrl 165, gui 200.
`overloadt` = tap-preferred. **Quick-tap:** tap then press again within 165 ms gives the plain key, so holding
repeats the letter and fast doubles (`ee`, `ll`) don't become modifiers.

## Thumb layers

| Hold | Layer | Tap |
|---|---|---|
| space (175 ms) | NUM: symbols on the top row, digits on the home row (mods still work), more symbols below | space |
| capslock (150 ms) | NAV: page/home/end, arrows, media keys, tab switching | caps lock |

Keycodes assume an OS in Dvorak, as `hyprland.lua` has it.

## Pitfall

A key held when the keyboard docks or disconnects can leave keyd's virtual keyboard with Shift down, which
kills the touch gestures. `sudo keyd reload` (or tapping and releasing Shift) clears it; adding yourself to the
`keyd` group lets `keyd reload` run without sudo.

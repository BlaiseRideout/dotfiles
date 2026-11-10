# Display layout, touch and pen mapping, brightness

All Hyprland-side logic is in `yoga/hypr/yoga.lua`; the values you may need to change are in
`yoga/hypr/config.lua`. Panels are matched by EDID description, never by connector name.

## The settings that matter (`config.lua`)

| Key | Value | Meaning |
|---|---|---|
| `panels.top.desc` / `bottom.desc` | `Samsung Display Corp. 0x4167` / `0x4182` | which panel is physically on top (swap if yours differs) |
| `panels.top.transform` | **`0`** | the mounting flip is done by the kernel flag; **do not set 2** |
| `panels.scale` | `2` | 1440x900 logical per panel (1.5 gives 1920x1200) |
| `touch.follows_panel` | `true` | give each touch/pen node its panel's current transform |
| `touch.top_offset` | `0` | extra turn for the top digitiser (was 2 while the panel transform was 2) |
| `touch.rotation_sense` | `1` | device transforms turn the same way as monitor transforms (-1 inverted all touches in book mode) |
| `touch.swap` | `false` | set true if "Touchscreen Top" turns out to be on the bottom panel |

## Rotation: kernel flag, no Hyprland transform

Add `video=eDP-1:panel_orientation=upside_down` to the kernel command line. The boot console is then upright and
Hyprland rotates the top panel itself, so its monitor rule has `transform = 0`.

Consequences, all handled in this tree:

- **Cursor:** the hardware cursor plane is not rotated, so on the top panel the cursor was drawn upside down
  and positioned mirrored (a touchpad then seemed to move it backwards on both axes). `yoga.start()` sets
  `cursor.no_hardware_cursors = 1`.
- **Posture daemon:** `PANEL_OFFSET` is 0 for both panels, so a rotated panel gets the same transform number.
- **Touch:** unchanged in effect (panel 0 + offset 0 = device 0 in the laptop pose).
- **Lock screen:** with the kernel flag the stock hyprlock background is upright on the top panel (checked).
  `scripts/lock.sh` still has a workaround for panels with a Hyprland transform other than 0 (upright `grim`
  captures as backgrounds); it is dormant now and only matters if you rotate in Hyprland instead of the kernel.
- If you drop the kernel flag you must restore all four settings (transform 2, offset 2, `PANEL_OFFSET` top 2,
  hardware cursor).

## Layouts

- **Standalone:** top panel at 0,0, bottom at 0,900 (logical), a vertical stack. Workspaces 1-8 and the full bar
  on the top panel, 9 and 10 on the bottom.
- **Docked to monitors:** the stack stays at the left, externals follow in a row, ordered by connector. The
  example `docked` list in `config.lua` is the owner's two monitors: replace or empty it. Hyprland's
  `position = "auto"` drifts when panels move, so `yoga_layout()` places unknown monitors itself.
- **Clamshell:** lid closed with an external monitor turns the panels off (no suspend); closed with none suspends.
- Posture changes (book, tent, tablet) go through `yoga_set_posture()` ([posture-daemon.md](posture-daemon.md)).

## Touch and pen mapping

- The four digitiser nodes are bound to their panel by `hl.device({name, output})`. Hyprland does **not** rotate a
  touch device when its output rotates, so with `follows_panel` each node also gets the panel's transform (turned
  by `rotation_sense`). Both mappings are checked in laptop pose; portrait/book poses were adjusted by trying
  (the 5-finger gestures were inverted until `rotation_sense = -1`).
- Disabling a dark panel's nodes (`enabled = false`) is accepted; stylus nodes may ignore it.
- Palm rejection: `yoga-palm` ([palm.md](palm.md)).

## Brightness

Two backlights, so plain `brightnessctl` moves one. `.config/hypr/brightness.sh up|down` steps every backlight
by 5 % (floor 2 %: an OLED shouldn't switch off) and shows the Noctalia OSD. No kernel parameters are needed
(do not add `acpi_osi=!`/`acpi_backlight`: not needed here and they change much more than backlights).

## Bars

Noctalia's full bar follows `primary` (written to `~/.cache/noctalia/primary.toml` by `hyprland.lua`); the Yoga's
widgets (battery, brightness, on-screen keyboard button, keyboard battery, no GPU gauge) are in
`yoga/noctalia/host.toml`. While the bottom screen is reserved for the keyboard its bar is hidden and its
workspaces move to the top panel (`yoga-bottom-reserve`).

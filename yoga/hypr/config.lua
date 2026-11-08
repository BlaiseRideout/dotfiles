-- Tunables of the Yoga Book 9i Hyprland module (yoga.lua, touch.lua). A plain
-- table, no code runs here: edit this file, not the module. hyprland.lua reads it
-- first (everywhere, to decide whether this machine is a Yoga) and loads the module
-- only if `detect` matches; see yoga/README.md.
--
-- FIX HERE if the screens come up wrong. Everything that depends on a fact we
-- couldn't check from software is in this one file:
--   * Wrong panel is upside down / the stack is the wrong way round: swap the two
--     descriptions in `panels` (the top panel is the one that gets its transform
--     and the "Touchscreen/Stylus Top" devices).
--   * The top panel isn't upside down (or is, and the bottom one too): change the
--     panels' `transform` (0 normal, 1 90, 2 180, 3 270).
--   * Touch/pen on the top screen lands on the bottom one, or is mirrored: see
--     `touch` below.
-- Notes and what was verified: docs/yoga-book/display.md.

return {
    -- Is this machine a Yoga Book 9i? True when any of these holds. The DMI name is
    -- what works at the first config load, when Hyprland has not created its
    -- monitors or opened its input devices yet; the panels and the digitiser cover
    -- later reloads and a DMI string that differs between BIOS versions.
    detect = {
        dmi = { product_family = { "Yoga Book 9 13IMU9" }, product_name = { "83FF" } },
        panels = true,   -- both panel descriptions below among the monitors
        touch = true,    -- a touch device named touch.device_prefix .. "touchscreen..."
    },

    -- Two 2880x1800 OLED panels, one above the other. Matched by EDID description
    -- (not eDP-1/eDP-2, which is only probe order).
    panels = {
        top    = { desc = "Samsung Display Corp. 0x4167", transform = 0 },   -- eDP-1 at the time of writing; "top" is assumed, see display.md. Mounted rotated 180 degrees, which the kernel knows (video=eDP-1:panel_orientation=upside_down) and Hyprland applies itself: do NOT add 2 here
        bottom = { desc = "Samsung Display Corp. 0x4182", transform = 0 },   -- eDP-2
        scale = 2,                          -- 2880x1800 on 13.3 inches: 1440x900 logical
        logical_w = 1440, logical_h = 900,
    },

    -- Monitors the Yoga is docked with that get a rule of their own: kanshi's
    -- "kens-triple" profile (.config/kanshi/config). As there the laptop is on the
    -- left and these follow to the right; dx is relative to the right edge of the
    -- laptop pair (1440 logical for the laptop posture; it moves with the posture),
    -- y is absolute. Keyed by EDID description; nothing happens unless connected.
    docked = {
        { desc = "Ancor Communications Inc ASUS PB278 FCLMTF170535", mode = "2560x1440@60", dx = 0,    y = 0,   transform = 3 },
        { desc = "Monoprice.Inc 34CHR",                              mode = "3440x1440@60", dx = 1440, y = 768, transform = 0 },
    },

    -- Touch and pen: each digitizer node goes to the panel it is on (by the
    -- descriptions above). The kernel names the nodes "Touchscreen Top/Bottom" and
    -- "Stylus Top/Bottom" (USB 17ef:6161, one device); Hyprland shows them
    -- lower-cased and hyphenated.
    touch = {
        device_prefix = "ingenic-gadget-serial-and-keyboard-",
        -- set true if "Touchscreen Top" turns out to be the touch layer of the
        -- physically bottom panel (decided by tapping, display.md)
        swap = false,
        -- extra per-device rotation (0-7, like the monitor transform), only if
        -- touch or pen lands rotated/mirrored on a panel; nil leaves it alone
        -- (then follows_panel decides)
        transform_top = nil, transform_bottom = nil,
        pen_transform_top = nil, pen_transform_bottom = nil,
        -- Hyprland does NOT rotate a touch device with its output (it only rotates
        -- a device by the device's own `transform`: setTouchDeviceConfigs applies it
        -- as a libinput calibration matrix), so in portrait the touch, and the window
        -- drags that follow the finger (hyprgrass warps the pointer to the raw touch
        -- position), came out rotated. true: every touch and pen node gets its
        -- panel's current transform, like a digitiser mounted with its panel should.
        -- This also rotates the top panel's touch by its native 180 in the laptop
        -- posture (it was left unrotated before; if that turns out inverted, set
        -- transform_top = 0).
        follows_panel = true,
        -- The top panel is mounted rotated 180 degrees (panels.top.transform = 2), but
        -- its digitiser reports user-oriented coordinates, not coordinates rotated
        -- with the panel (seen: every gesture inverted on the top screen with
        -- follows_panel alone). So with follows_panel, the devices on the top panel
        -- get (panel transform + top_offset) % 4: 0 in the laptop posture, and the
        -- matching swapped values in portrait. The bottom panel's devices get the
        -- panel's transform as is. The fixed per-device transforms below win over
        -- both. Verified on the hardware in the laptop posture (the top screen's
        -- gestures are right with this; portrait is not checked on the top panel).
        top_offset = 0,   -- was 2 while panels.top.transform was 2; the panel transform now excludes the mounting flip
        -- Which way the device transform turns relative to the monitor's: 1 = the same
        -- number, -1 = the opposite quarter turn (1 <-> 3; 0 and 2 are unaffected).
        -- Checked in the side-by-side portrait pose: with 1 every gesture came out
        -- inverted (a half turn off), so the touch devices need the opposite sense.
        rotation_sense = -1,
        -- the virtual touchscreen made by yoga-touchpad (docs/yoga-book/touchpad.md)
        -- carries the bottom panel's touches outside the touchpad strip: same panel,
        -- same transform (named without the prefix)
        virtual_bottom = "yoga-virtual-touchscreen-bottom",
    },

    -- Noctalia's bar widget lists, written into ~/.cache/noctalia/primary.toml next
    -- to the primary's `match` (hyprland.lua set_bar_primary, yoga.bar_extra). The
    -- on-screen keyboard button belongs on the laptop panels' bars and nowhere else,
    -- and a section that matches a monitor replaces its whole bar, so the lists
    -- depend on which monitor is primary: when a laptop panel is, its full bar
    -- carries osk ("OSK" below marks where); when an external monitor is (docked),
    -- the full bar does not and each laptop panel gets a plain bar with osk. The
    -- widgets are defined in yoga/noctalia/host.toml.
    bar = {
        -- Side-by-side (book) pose with a laptop panel as primary: split the full bar
        -- across the two screens: the left screen's bar gets the start widgets
        -- (launcher, workspaces, system monitors, ...) and the right screen's bar the
        -- end widgets (tray, volume, clock, ...), which on one 900-px-wide portrait screen
        -- would not fit together anyway. false = the normal full bar + plain bar.
        book_split = true,
        -- The glyph a workspace without an icon is shown as in the bar's workspace widget (the
        -- circle, as workspaces 4-8 have in hyprland.lua)
        workspace_dot = "\u{f111}",
        full_start = { "launcher", "workspaces", "sysmon_cpu_temp", "sysmon_cpu", "sysmon_3",
                       "laptop_battery", "zmk", "media_player" },
        full_end = { "fsearch", "tray", "bluetooth", "network", "volume",
                     "brightness", "caffeine", "notifications", "OSK", "clock", "session" },
        plain = { start = { "workspaces" }, center = { "active_window" },
                  end_ = { "fsearch", "tray", "osk", "clock" } },
    },
}

-- Touch UX for the Yoga Book 9i: hyprgrass gestures, the on-screen keyboard
-- and the plugin rescue bind. Loaded by yoga.lua (yoga.start(), the last thing
-- hyprland.lua does, in a pcall, so an error here can never break the main
-- config) and only does anything on a machine with the Yoga's touchscreen.
-- Called with the module table and the host table (yoga.lua):
--   local yoga, host = ...
-- Notes: docs/yoga-book/touch-ux.md.
--
-- How the plugin gets in: hyprland.start runs `yoga-touch load` (hyprpm reload);
-- loading a plugin makes Hyprland reload the config, and that second pass finds
-- hl.plugin.hyprgrass and registers the gestures below. Without the plugin (not
-- built yet, hyprpm missing, the switch set by `yoga-touch recover`) only the
-- rescue bind and the keyboard exist. Never call hl.plugin.load from here:
-- every reload would load it again, and the loop was seen (reloads in a burst).
--
-- Rescue, whatever state the touch is in: SUPER+CTRL+SHIFT+Escape (or
-- `yoga-touch recover` from a TTY / SSH): unloads every plugin, reloads this
-- config, hides the keyboard and keeps plugins off until `yoga-touch enable`.

local yoga, host = ...
local home = os.getenv("HOME")
-- The scripts are linked into ~/.local/bin by yoga/nix/module.nix; until
-- `home-manager switch` has run, use the checkout (yoga/bin) so the rescue bind
-- still works
local bin = os.getenv("YOGA_TOUCH_BIN") or (home .. "/.local/bin")
if not io.open(bin .. "/yoga-touch", "r") then bin = host.dir .. "/bin" end
local state_dir = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/yoga-touch"

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- No hardware gate here: this file is only loaded by yoga.start(), i.e. when yoga.lua
-- found a Yoga Book (DMI strings at the first load, panels or digitiser later). A gate on
-- the digitiser device used to live here, but at the first config load of a session Hyprland
-- has not opened its input devices yet, so it failed at every boot and nothing below ran
-- (no hyprland.start hook, so no plugin load and no keyboard; seen).

local function warn(text)
    hl.notification.create({ text = "yoga-touch: " .. text, timeout = 6000 })
end
local function try(what, fn)
    local ok, err = pcall(fn)
    if not ok then warn(what .. ": " .. tostring(err)) end
end

local function sh(cmd) return hl.dsp.exec_cmd(cmd) end
local osk = bin .. "/yoga-osk"
-- The launcher, clipboard history and window switcher: fuzzel while the on-screen keyboard
-- is up (a tap on the keyboard closes Noctalia's panels, which hold a focus grab), the
-- panels otherwise. See yoga/bin/yoga-launcher; hyprland.lua's SUPER+d, SUPER+v,
-- SUPER+minus and SUPER+Tab (through yoga.launcher_cmd) and the swipes below run it.
yoga.launcher_cmd = bin .. "/yoga-launcher"
local touch = bin .. "/yoga-touch"

-- The rescue. Locked, so it also works with the lock screen up.
hl.bind("SUPER + CTRL + SHIFT + Escape", sh(touch .. " recover"),
        { locked = true, description = "Yoga: unload plugins and reset input" })

-- The on-screen keyboard can be used from the lock screen: above_lock = 2 draws
-- wvkbd's layer above the session lock and lets it take input (its keys are virtual
-- keyboard presses, which the lock screen receives like any other). yoga-osk-lockwatch
-- (a user service) shows it when hyprlock appears; the bind below also works locked.
try("above-lock keyboard rule", function()
    hl.layer_rule({ name = "yoga-osk-above-lock", match = { namespace = "^wvkbd$" }, above_lock = 2 })
end)

-- On-screen keyboard from the keyboard side as well ($mod+k is KeePassXC)
hl.bind("SUPER + ALT + k", sh(osk .. " toggle"), { locked = true, description = "Yoga: on-screen keyboard" })

-- Posture daemon controls (yoga/bin/yoga-posture, docs/yoga-book/posture-daemon.md).
-- SUPER+ALT+f: in tent or tablet, use the other panel. SUPER+ALT+p: force the
-- next posture (laptop, book, tent, tablet, then back to automatic).
-- SUPER+ALT+SHIFT+p: reset both panels to the plain laptop layout, whatever
-- the daemon is doing (locked, so it works on the lock screen).
local posture = bin .. "/yoga-posture"
hl.bind("SUPER + ALT + f", sh(posture .. " flip-tent"), { description = "Yoga: tent/tablet, use the other panel" })
hl.bind("SUPER + ALT + p", sh(posture .. " cycle"), { description = "Yoga: force the next posture" })
hl.bind("SUPER + ALT + SHIFT + p", sh(posture .. " reset"),
        { locked = true, description = "Yoga: reset panels to the laptop layout" })

-- Virtual touchpad (yoga/bin/yoga-touchpad, docs/yoga-book/touchpad.md):
-- SUPER+ALT+t toggles it on/off by hand; it otherwise follows the keyboard dock.
local touchpad = bin .. "/yoga-touchpad"
hl.bind("SUPER + ALT + t", sh(touchpad .. " toggle"), { description = "Yoga: virtual touchpad on/off" })

hl.on("hyprland.start", function()
    -- wvkbd in the background (a no-op until yoga/wvkbd/build.sh has been run), then the plugins
    hl.exec_cmd("command -v wvkbd-yoga >/dev/null && " .. osk .. " start")
    hl.exec_cmd(touch .. " load")
end)

-- Gestures: only with the plugin loaded and the switch off
local hg = hl.plugin.hyprgrass
if not hg or exists(state_dir .. "/plugins.off") then return end

try("config", function()
    hl.config({
        plugin = {
            hyprgrass = {
                sensitivity = 4.0,             -- the plugin's advice for tablet-size screens
                long_press_delay = 400,
                resize_on_border_long_press = true,
                edge_margin = 30,              -- logical px (60 physical at scale 2): bezel-friendly
            },
        },
        gestures = { workspace_swipe_cancel_ratio = 0.15 },
    })
end)

-- Edge swipes (from the screen's own edge, as the user sees it after rotation)
-- bottom edge, up: the dock (a finger cannot hover the edge to bring it up; yoga-dock-peek).
-- The keyboard has the eight-finger tap below, the bar's button and SUPER+ALT+k. Run from the
-- checkout, so it works before home-manager has linked it.
try("dock edge swipe", function()
    hg.bind({ pattern = { kind = "edge", origin = "down", direction = "up" },
              action = sh(host.dir .. "/bin/yoga-dock-peek") })
end)
try("launcher edge swipe", function()   -- left edge, right: launcher
    hg.bind({ pattern = { kind = "edge", origin = "left", direction = "right" },
              action = sh(yoga.launcher_cmd .. " apps") })
end)
try("control center edge swipe", function()   -- right edge, left: control center
    hg.bind({ pattern = { kind = "edge", origin = "right", direction = "left" },
              action = sh("noctalia msg panel-toggle control-center") })
end)
try("close edge swipe", function()   -- top edge, down with two fingers: close the window
    hg.bind({ pattern = { kind = "edge", origin = "up", direction = "down", fingers = 2 },
              action = hl.dsp.window.close() })
end)

-- Swipes and holds
-- Three fingers sideways: workspaces. Normally Hyprland's own live workspace swipe, which only
-- knows the neighbours of the workspace on the touched screen, so in book pose (the two
-- screens as a two-wide window onto the workspace list, yoga.lua) it did nothing. There a Lua
-- gesture takes its place: the swipe's distance decides, then the pair slides one slot (left =
-- next, like the live swipe). yoga_set_posture swaps the two with yoga_touch_ws_gesture.
-- A swipe's fingers drift together as they lift, which is read as a pinch (see the pinches
-- below). A swipe that does not change the active workspace (the book pair at either end of
-- the list, a window sent to the other screen, the 4-finger swipes) gets no help from the
-- workspace.active guard there, so every swipe handler also calls this, and a pinch is ignored
-- around it just the same. (That toggled the moved window's floating state, seen.)
local swipe_epoch, swipe_recent = 0, false
function yoga_swipe_mark()
    swipe_epoch = swipe_epoch + 1
    swipe_recent = true
    hl.timer(function() swipe_recent = false end, { timeout = 1500, type = "oneshot" })
end
local WS_PATTERN = { kind = "swipe", fingers = 3, direction = "horizontal" }
local BOOK_SWIPE_MIN = 30   -- the swipe's summed delta (the plugin's units: 300 = a screen width / 1)
local ws_book = false
local book_dx = 0
local book_ws_action = {
    start = function(e) book_dx = 0; yoga_swipe_mark(); if yoga_glog then yoga_glog("3-finger swipe start fingers=" .. tostring(e.fingers)) end end,
    update = function(e) book_dx = book_dx + ((e.delta and e.delta.x) or 0) end,
    finish = function(e)
        local dx = book_dx
        book_dx = 0
        yoga_swipe_mark()
        if yoga_glog then yoga_glog(string.format("3-finger swipe end dx=%.1f cancelled=%s", dx, tostring(e.cancelled))) end
        if e.cancelled or math.abs(dx) < BOOK_SWIPE_MIN then return end
        local delta = dx < 0 and 1 or -1
        if yoga_book_step and yoga_book_step(delta, false) then return end
        if yoga_host_ws_step then yoga_host_ws_step(delta) end   -- an external monitor came along
    end,
}
function yoga_touch_ws_gesture(book)
    book = book and true or false
    if book == ws_book then return "unchanged" end
    local ok, err = pcall(hg.gesture, { pattern = WS_PATTERN, action = "unset" })
    if not ok then return "unset failed: " .. tostring(err) end
    ok, err = pcall(hg.gesture, { pattern = WS_PATTERN, action = book and book_ws_action or "workspace" })
    if not ok then
        pcall(hg.gesture, { pattern = WS_PATTERN, action = "workspace" })
        ws_book = false
        return "failed: " .. tostring(err)
    end
    ws_book = book
    return book and "book" or "workspace"
end
try("workspace swipe", function()
    hg.gesture({ pattern = WS_PATTERN, action = "workspace" })
    -- a reload (or the plugin loading late) while in book pose
    if yoga_lua_ws_swipe and yoga_lua_ws_swipe() then yoga_touch_ws_gesture(true) end
end)
-- Eight fingers tapping: the on-screen keyboard (an unmistakable tap, for when the bar
-- button and the bottom-edge swipe are out of reach)
try("osk eight-finger tap", function()
    hg.bind({ pattern = { kind = "tap", fingers = 8 }, action = sh(osk .. " toggle") })
end)
try("window switcher", function()   -- five fingers up: window switcher
    hg.bind({ pattern = { kind = "swipe", fingers = 5, direction = "up" },
              action = sh(yoga.launcher_cmd .. " windows") })
end)
try("window drag", function()   -- three-finger hold, then drag: move the window
    hg.bind({ pattern = { kind = "longpress", fingers = 3 }, action = hl.dsp.window.drag(), mouse = true })
end)

-- Pinches, with three fingers (four also work): pinch OUT = fullscreen, pinch IN = leave
-- fullscreen, or, on a window that is not fullscreen, toggle floating.
-- A three-finger workspace swipe ends with the fingers drifting together, which is read as a
-- pinch in: the window on the workspace just switched to was toggled (seen twice). That was
-- first dodged by moving the pinches to four fingers; now a pinch is simply ignored when the
-- active workspace changes within a second before it or 0.3 s after it (the swipe's own
-- switch can land on either side of the stray pinch), so three-finger pinches work again.
-- The pinch acts only after that 0.3 s.
local ws_epoch, ws_recent = 0, false
hl.on("workspace.active", function(ws)
    if io.open((os.getenv("HOME") or "") .. "/.local/state/yoga-touch/pinch-debug") then
        local f = io.open((os.getenv("HOME") or "") .. "/.local/state/yoga-touch/pinch.log", "a")
        if f then f:write(os.date("%H:%M:%S "), "workspace.active ", tostring(type(ws) == "table" and ws.id or ws), "\n"); f:close() end
    end
    ws_epoch = ws_epoch + 1
    ws_recent = true
    hl.timer(function() ws_recent = false end, { timeout = 1000, type = "oneshot" })
end)
-- Called as `hyprctl eval 'yoga_pinch("out")'` (like yoga_win_step below: plain Lua function
-- actions of hg.bind are not validated, a command is the proven way to run code from a gesture)
local pinch_log = (os.getenv("HOME") or "") .. "/.local/state/yoga-touch/pinch.log"
local function plog(msg)   -- what each recognised pinch did, for finding out why one did not
    local f = io.open(pinch_log, "a")
    if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end
function yoga_pinch(dir)
    local e, early = ws_epoch, ws_recent
    local se, searly = swipe_epoch, swipe_recent
    hl.timer(function()
        if searly or se ~= swipe_epoch then
            plog(dir .. ": ignored, a swipe " .. (searly and "just before" or "just after"))
            return
        end
        if early or e ~= ws_epoch then
            plog(dir .. ": ignored, workspace changed " .. (early and "just before" or "just after"))
            return   -- a workspace swipe's drift, not a pinch
        end
        local w = hl.get_active_window()
        if not w then plog(dir .. ": no active window"); return end
        plog(dir .. ": " .. tostring(w.class) .. " fullscreen=" .. tostring(w.fullscreen) .. " floating=" .. tostring(w.floating))
        if dir == "out" then          -- fullscreen
            if w.fullscreen == 0 then hl.dispatch(hl.dsp.window.fullscreen()) end
        elseif w.fullscreen ~= 0 then -- in: leave fullscreen
            hl.dispatch(hl.dsp.window.fullscreen())
        else                          -- in, not fullscreen: floating
            hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
        end
    end, { timeout = 300, type = "oneshot" })
end
for _, fingers in ipairs({ 3, 4 }) do
    -- hyprgrass's "pinchin" is the fingers moving apart on this machine (as it was when the
    -- pinches were first swapped, section 16 of touch-ux.md): a physical pinch OUT is "pinchin"
    try("pinch out " .. fingers, function()
        hg.bind({ pattern = { kind = "pinch", fingers = fingers, direction = "pinchin" },
                  action = sh("hyprctl eval 'yoga_pinch(\"out\")'") })
    end)
    try("pinch in " .. fingers, function()
        hg.bind({ pattern = { kind = "pinch", fingers = fingers, direction = "pinchout" },
                  action = sh("hyprctl eval 'yoga_pinch(\"in\")'") })
    end)
end
-- Four fingers swipe the focused window to another workspace or screen (side by side in book
-- pose: left / right = the screen on that side): left = the next
-- workspace, right = the previous (wrapping, following the window); up / down = the
-- screen above / below (down is skipped while the bottom screen is reserved for the
-- keyboard).
try("move window to next workspace", function()
    hg.bind({ pattern = { kind = "swipe", fingers = 4, direction = "left" },
              action = sh("hyprctl eval 'yoga_win_swipe(\"left\")'") })
end)
try("move window to previous workspace", function()
    hg.bind({ pattern = { kind = "swipe", fingers = 4, direction = "right" },
              action = sh("hyprctl eval 'yoga_win_swipe(\"right\")'") })
end)
try("move window to the screen above", function()
    hg.bind({ pattern = { kind = "swipe", fingers = 4, direction = "up" },
              action = sh("hyprctl eval 'yoga_win_to_monitor(\"u\")'") })
end)
try("move window to the screen below", function()
    hg.bind({ pattern = { kind = "swipe", fingers = 4, direction = "down" },
              action = sh("hyprctl eval 'yoga_win_to_monitor(\"d\")'") })
end)

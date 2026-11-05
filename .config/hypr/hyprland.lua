-- Hyprland config, ported from ~/.config/sway/config. On nhuto-Mint, Hyprland
-- comes from Nix and is "Hyprland (NVIDIA)" in GDM (build/hyprland/).
--
-- Hyprland 0.57. Reference: the stubs in share/hypr/stubs/hl.meta.lua of the
-- Hyprland install (~/.nix-profile or /usr) and https://wiki.hypr.land.
-- Check this file without a running session:
--   Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
-- Hyprland reloads it on save. `hyprctl eval '<lua>'` runs code in this file's
-- Lua state, which is how the scripts and bars call the functions below.
--
-- Hypr apps rather than the Sway ones: hyprpaper (wallpapers), hypridle and
-- hyprlock (idle and lock; lock.sh), hyprpolkitagent (admin prompts),
-- xdg-desktop-portal-hyprland (screen sharing) and grimblast (screenshots).
-- Their configs are next to this file. fuzzel (.config/fuzzel) is the launcher
-- for apps, commands and windows, replacing wofi and Sway's kitty + fzf
-- launcher; the clipboard history (cliphist, replacing CopyQ) is fzf in kitty.
-- Noctalia replaces Waybar, hyprpaper, mako and the polkit agent where it's
-- installed (see AUTOSTART); kitty and the rest stay as on Sway.
--
-- Tiling is left to Hyprland's own layouts (dwindle, or master/scrolling per
-- workspace with $mod+m) rather than Sway's manual splits, so splith/splitv/
-- toggle split ($mod+m/v/period on Sway), focus parent ($mod+Escape), stacking
-- ($mod+o) and equalize_split.py ($mod+=) aren't carried over, nor the
-- "[XWayland]" title prefix. autotiling.py isn't needed; center_single.py is built in
-- (layout.single_window_aspect_ratio).

local home = os.getenv("HOME")
local mod = "SUPER"
-- Dvorak home row, like vim's hjkl
local left, down, up, right = "h", "t", "n", "s"
local term = "kitty"
local swaydir = home .. "/.config/sway"
local hyprdir = home .. "/.config/hypr"


------------------
---- MONITORS ----
------------------

-- Same layout as kanshi's "default" profile. Monitors are matched by
-- description (make, model, serial) rather than by port.
local G95C = "desc:Samsung Electric Company Odyssey G95C HNTY301994"
local AOC  = "desc:AOC 24G15N AP15338Z04043"
-- The TV's serial changes with its HDMI input, so match make and model only
local TV   = "desc:Samsung Electric Company SAMSUNG "

hl.monitor({ output = G95C, mode = "5120x1440@239.76", position = "0x100", scale = 1 })
hl.monitor({ output = AOC,  mode = "1920x1080@180",    position = "5120x0", scale = 1, transform = 3 })
-- Anything else (laptop panel, other desks): its preferred mode, placed to the right
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

local function is_tv(m)
    return (m.description or ""):find("^Samsung Electric Company SAMSUNG ") ~= nil
end

local function is_laptop(m)
    return (m.name or ""):find("^eDP") ~= nil
end

-- The TV starts off so the G95C gets its 240Hz mode first (the driver rejects
-- 240Hz while the TV is lit); tv-autotoggle.sh turns it on through tv_set()
-- once the TV answers on the network. A config reload keeps its current state.
local tv_on = false
for _, m in ipairs(hl.get_monitors() or {}) do
    if is_tv(m) then tv_on = true end
end
local function tv_rule(output, on)
    hl.monitor({ output = output, mode = "1920x1080@60", position = "6200x0", scale = 1, disabled = not on })
end
tv_rule(TV, tv_on)

-- A TV that's off at login sends no EDID: it shows up as an HDMI port with no
-- description, lit at 1024x768 but never drawing a frame, which hangs anything
-- waiting on every output (grim). Keep that port off too, by name, until
-- tv-autotoggle.sh sees the TV on the network.
local tv_port = nil
local tv_wanted = tv_on   -- last tv_set(); a port it turned on stays on
local function catch_blind_tv()
    if tv_wanted then return end
    for _, m in ipairs(hl.get_monitors() or {}) do
        if (m.name or ""):find("^HDMI%-A%-") and (m.description or "") == "" then
            tv_port = m.name
            tv_rule(tv_port, false)
        end
    end
end
catch_blind_tv()
hl.on("monitor.added", catch_blind_tv)

function tv_set(on)
    tv_wanted = on
    tv_rule(TV, on)
    if tv_port then tv_rule(tv_port, on) end
end


--------------------
---- WORKSPACES ----
--------------------

-- Workspaces by role, as in kanshi/move_workspaces.sh:
--   primary   (largest external monitor): 1-8
--   secondary (next external monitor):    9
--   tertiary  (laptop panel, else TV):    10
-- A missing role falls through (9 to the tertiary or primary, 10 to the
-- secondary or primary). Re-run whenever a monitor comes or goes.
-- keep_view: put back what each monitor was showing; otherwise end on 1 with
-- 9 and 10 visible, as at login.
local function focus_ws(id)
    hl.dispatch(hl.dsp.focus({ workspace = id }))
end

-- Noctalia uses workspace names for its icon labels; numeric IDs and binds stay the same.
local workspace_icons = { "", "", "", "", "", "", "", "", "", "" }

-- Noctalia shows the full bar only on the primary monitor (noctalia/dotfiles/
-- bar.toml). It includes this file, which names that monitor, and reloads when
-- it changes, like Waybar's launch.sh following kanshi/primary_output.sh.
-- Only rewritten when the primary changes, since every write reloads the bar.
local bar_primary_file = home .. "/.cache/noctalia/primary.toml"
local function set_bar_primary(name)
    local text = "# Written by hypr/hyprland.lua: the primary monitor, which gets the full bar\n"
        .. "[bar.default.monitor.primary]\nmatch = \"" .. name .. "\"\n"
    local f = io.open(bar_primary_file, "r")
    local old = f and f:read("a")
    if f then f:close() end
    if old == text then return end
    os.execute("mkdir -p " .. home .. "/.cache/noctalia")
    f = io.open(bar_primary_file, "w")
    if not f then return end
    f:write(text)
    f:close()
end

function place_workspaces(keep_view)
    local mons = hl.get_monitors() or {}
    local externals, tertiaries = {}, {}
    for _, m in ipairs(mons) do
        if is_laptop(m) then
            table.insert(tertiaries, 1, m)   -- laptop panel before the TV
        elseif is_tv(m) then
            table.insert(tertiaries, m)
        else
            table.insert(externals, m)
        end
    end
    table.sort(externals, function(a, b) return a.width * a.height > b.width * b.height end)

    local primary = externals[1] or tertiaries[1]
    if not primary then return end
    local secondary = externals[2]
    local tertiary = tertiaries[1]
    if tertiary == primary then tertiary = tertiaries[2] end

    set_bar_primary(primary.name)

    local target = {}
    for i = 1, 8 do target[i] = primary end
    target[9]  = secondary or tertiary or primary
    target[10] = tertiary or secondary or primary

    local shown, focused = {}, nil
    if keep_view then
        for _, m in ipairs(mons) do
            if m.active_workspace and not m.focused then
                table.insert(shown, m.active_workspace.id)
            end
        end
        local a = hl.get_active_workspace()
        focused = a and a.id
    end

    for i = 1, 10 do
        -- Repeating a rule for the same workspace replaces its monitor
        local t = target[i]
        hl.workspace_rule({
            workspace = tostring(i), monitor = t.name, default_name = workspace_icons[i],
        })
        local ws = hl.get_workspace(i)
        if ws then
            hl.dispatch(hl.dsp.workspace.rename({ workspace = i, name = workspace_icons[i] }))
        end
        if ws and ws.monitor and ws.monitor.name ~= target[i].name then
            hl.dispatch(hl.dsp.workspace.move({ workspace = i, monitor = target[i].name }))
        end
    end

    if keep_view then
        for _, id in ipairs(shown) do focus_ws(id) end
        if focused then focus_ws(focused) end
    else
        focus_ws(10)
        focus_ws(9)
        focus_ws(1)
    end
end

-- A lone tiled window on an ultrawide is at most 2:1 and centered (like
-- center_single.py on Sway). Hyprland's single_window_aspect_ratio is global,
-- so it stays off (vertical monitors fill the screen) and the cap is made with
-- side gaps on the workspace instead, added while it has exactly one tiled window.
local GAP = 5
local lone_gaps = {}   -- workspace id -> side gap currently applied

local function workspace_gaps(id)
    local side = lone_gaps[id] or GAP
    return { top = GAP, bottom = GAP, left = side, right = side }
end

local function update_lone_windows()
    for id = 1, 10 do
        local ws = hl.get_workspace(id)
        local m = ws and ws.monitor
        local want = GAP
        if m and m.width >= 2 * m.height then
            local tiled
            local n = 0
            for _, w in ipairs(ws:get_windows() or {}) do
                if w.mapped and not w.floating and not w.hidden then
                    n = n + 1
                    tiled = w
                end
            end
            if n == 1 and tiled.fullscreen == 0 then
                -- Window width is the monitor's, less the side gaps and borders
                local h = tiled.size.y
                local border = 5
                want = math.max(GAP, math.floor((m.width - 2 * h) / 2) - border)
            end
        end
        if (lone_gaps[id] or GAP) ~= want then
            lone_gaps[id] = want
            hl.workspace_rule({ workspace = tostring(id), gaps_out = workspace_gaps(id) })
        end
    end
end

-- Events fire before the state changes, so look again once it has settled
local lone_timer
local function schedule_lone_update()
    if lone_timer then return end
    lone_timer = hl.timer(function() lone_timer = nil; update_lone_windows() end,
                          { timeout = 50, type = "oneshot" })
end
for _, ev in ipairs({ "window.open", "window.close", "window.move_to_workspace",
                      "window.update_state", "workspace.active", "monitor.focused",
                      "workspace.move_to_monitor" }) do
    hl.on(ev, schedule_lone_update)
end
-- A reload clears the workspace rules, gaps included
hl.on("config.reloaded", function() lone_gaps = {}; schedule_lone_update() end)

hl.on("monitor.added",   function() place_workspaces(true) end)
hl.on("monitor.removed", function() place_workspaces(true) end)
-- A reload clears the workspace rules; put them back
hl.on("config.reloaded", function() place_workspaces(true) end)

-- Previous/next workspace by number, wrapping 10 <-> 1 (swayworkspace.sh)
local function ws_step(delta, move)
    local ws = hl.get_active_workspace()
    local id = (ws and ws.id and ws.id > 0) and ws.id or 1
    local n = (id - 1 + delta) % 10 + 1
    if move then
        hl.dispatch(hl.dsp.window.move({ workspace = n }))   -- and follow it
    else
        focus_ws(n)
    end
end


-------------------
---- SCRATCHPAD ---
-------------------

-- FSearch and T3 Code, kept running and shown or hidden from a key or Waybar's
-- buttons (sway/scratchpad-app.sh on Sway). FSearch lives in its own special
-- workspace, which shows over the current one; T3 Code is hidden in one and
-- brought back tiled. scratch_toggle() does nothing where an app isn't installed.
-- Whether a shell command succeeds. Not os.execute: Hyprland reaps its child
-- processes itself, so os.execute never gets the exit status and always fails
local function succeeds(cmd)
    local p = io.popen(cmd .. " >/dev/null 2>&1 && echo ok")
    if not p then return false end
    local out = p:read("*l")
    p:close()
    return out == "ok"
end

local apps = {
    fsearch = {
        class   = "io.github.cboxdoerfer.FSearch",
        title   = "^FSearch",   -- the main window; its dialogs share the class
        launch  = "flatpak run io.github.cboxdoerfer.FSearch",
        overlay = true,
        installed = function()
            return succeeds("flatpak info io.github.cboxdoerfer.FSearch")
        end,
    },
    t3code = {
        class   = "com.t3tools.T3Code",
        title   = "",
        launch  = home .. "/.local/bin/t3code",
        overlay = false,
        installed = function()
            return succeeds("test -x " .. home .. "/.local/bin/t3code")
        end,
    },
}
local pending_show = {}   -- apps launched by a toggle, to show once their window opens

local function app_matches(app, w)
    return w.class == app.class and (w.title or ""):find(app.title) ~= nil
end

local function find_window(app)
    for _, w in ipairs(hl.get_windows() or {}) do
        if app_matches(app, w) then return w end
    end
end

local function sel(w) return "address:" .. w.address end

-- Size an overlay window to fit the focused monitor (the G95C is 5120 wide, the AOC 1080)
local function fit_overlay(w)
    local m = hl.get_active_monitor()
    if not m then return end
    local mw, mh = m.width / m.scale, m.height / m.scale
    if m.transform % 2 == 1 then mw, mh = mh, mw end
    hl.dispatch(hl.dsp.window.resize({ x = math.min(1600, math.floor(mw * 0.9)),
                                       y = math.min(1000, math.floor(mh * 0.8)), window = sel(w) }))
    hl.dispatch(hl.dsp.window.center({ window = sel(w) }))
end

local function hide(name, w)
    hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. name, follow = false, window = sel(w) }))
end

local function show(name, w)
    local app = apps[name]
    if app.overlay then
        local special = hl.get_active_special_workspace()
        if not (special and special.name == "special:" .. name) then
            hl.dispatch(hl.dsp.workspace.toggle_special(name))
        end
        fit_overlay(w)
    else
        local ws = hl.get_active_workspace()
        hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws.id), window = sel(w) }))
    end
    hl.dispatch(hl.dsp.focus({ window = sel(w) }))
end

function scratch_toggle(name)
    local app = apps[name]
    if not app or not app.installed() then return end
    local w = find_window(app)
    if not w then
        pending_show[name] = true
        hl.exec_cmd(app.launch)
    elseif w.workspace and w.workspace.name == "special:" .. name then
        if app.overlay and w.workspace.visible and w.active then
            hl.dispatch(hl.dsp.workspace.toggle_special(name))   -- shown and focused: hide
        else
            show(name, w)
        end
    elseif w.active or (not app.overlay and w.visible and w.workspace
            and hl.get_active_workspace()
            and w.workspace.name == hl.get_active_workspace().name) then
        -- Moving to the bar can move keyboard focus away from T3. A tiled
        -- scratchpad app already visible here should still toggle closed.
        hide(name, w)
    else
        hl.dispatch(hl.dsp.focus({ window = sel(w) }))
    end
end

hl.on("window.open", function(w)
    for name, app in pairs(apps) do
        if pending_show[name] and app_matches(app, w) then
            pending_show[name] = nil
            show(name, w)
        end
    end

    -- Another app's window opening while an overlay is shown (FSearch's "Open
    -- folder" starting Nemo) lands on the overlay's special workspace, tiled
    -- under it. Put it on the workspace underneath and hide the overlay.
    -- The app's own dialogs and its file chooser (the GTK portal) stay with it.
    local ws = w.workspace and w.workspace.name or ""
    for name, app in pairs(apps) do
        if app.overlay and ws == "special:" .. name and w.class ~= app.class
            and w.class ~= "xdg-desktop-portal-gtk" then
            local below = hl.get_active_workspace()
            if below then
                hl.dispatch(hl.dsp.window.move({ workspace = below.id, follow = false, window = sel(w) }))
            end
            hl.dispatch(hl.dsp.workspace.toggle_special(name))
            hl.dispatch(hl.dsp.focus({ window = sel(w) }))
        end
    end
end)

-- T3 Code's minimize button hides it (on Sway this needs t3code-minimize-hook.py)
hl.on("window.minimize", function(w, minimized)
    if w and minimized and w.class == apps.t3code.class then
        hide("t3code", w)
    end
end)

-- Started hidden at login: FSearch's main window goes straight to its special workspace
hl.window_rule({
    name  = "fsearch-hidden",
    match = { class = "^io\\.github\\.cboxdoerfer\\.FSearch$", title = "^FSearch" },
    workspace = "special:fsearch silent",
    float = true,
    rounding = 12,   -- like fuzzel (fuzzel.ini)
})


---------------------
---- AUTOSTART ------
---------------------

-- Distro login sessions need not inherit systemd's environment.d variables.
-- Set this before launching any applications so they share the user agent.
local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
if runtime_dir then
    hl.env("SSH_AUTH_SOCK", runtime_dir .. "/ssh-agent.socket")
end

local function exec(cmd) hl.exec_cmd(cmd) end

hl.on("hyprland.start", function()
    exec("systemctl --user start ssh-agent.service")
    -- Portals and D-Bus-started apps read these; the systemd user session can
    -- outlive a Sway or Cinnamon login and keep their values
    exec("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE;"
         .. " dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE;"
         .. " systemctl --user unset-environment SWAYSOCK I3SOCK")   -- left from a Sway login

    place_workspaces(false)

    -- XWayland's resource database starts empty; nvim's xresources theme reads
    -- its colors from it
    exec("xrdb -merge " .. home .. "/.Xresources")

    -- Noctalia (CachyOS's shell, .config/noctalia) is the bar, and also draws
    -- the wallpapers (wallpaper.toml), shows notifications and asks for admin
    -- passwords. Without it (nhuto-Mint): hyprpaper, the Hypr polkit agent
    -- (the distro's, or Nix's linked by home/hosts/nhuto-Mint.nix), and mako,
    -- which D-Bus starts on the first notification. No bar there.
    if succeeds("command -v noctalia") then
        exec(home .. "/scripts/noctalia.sh")
    else
        exec("hyprpaper")
        exec("for a in " .. home .. "/.local/libexec/hyprpolkitagent /usr/lib/hyprpolkitagent/hyprpolkitagent"
             .. " /usr/libexec/hyprpolkitagent; do [ -x \"$a\" ] && exec \"$a\"; done")
    end
    exec("hypridle")
    -- Holds an idle inhibitor during video calls, so they don't lock or blank the screens
    exec(hyprdir .. "/call-inhibit.sh")
    -- Clipboard history for $mod+v (clipboard.sh). CopyQ stays Sway's: its
    -- autostart entry has NotShowIn=Hyprland
    exec("wl-paste --type text --watch cliphist store")
    exec("wl-paste --type image --watch cliphist store")
    -- The TV stays "connected" when off, so follow its network state instead
    exec(swaydir .. "/tv-autotoggle.sh")

    exec("dex --autostart --environment Hyprland")
    exec("command -v mintupdate-launcher >/dev/null && exec mintupdate-launcher")   -- Mint's updates
    exec("udiskie --no-tray")
    exec(swaydir .. "/selection-to-clipboard.sh")
    if apps.fsearch.installed() then exec(apps.fsearch.launch) end
end)


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- The cursor GTK apps use (gsettings' cursor-theme and cursor-size), for
-- Hyprland's own cursor and the apps started from here (XWayland, Qt). Without
-- XCURSOR_THEME Hyprland falls back to its built-in cursor (also without
-- the right XCURSOR_PATH: build/hyprland/hyprland-session sets it for Nix's
-- Hyprland). Re-read on every
-- reload ($mod+Shift+r, or saving this file), so after changing the cursor in
-- the GTK settings a reload applies it; apps already open keep the old one.
local function gsetting(key)
    local p = io.popen("gsettings get org.gnome.desktop.interface " .. key .. " 2>/dev/null")
    if not p then return "" end
    local value = p:read("*l") or ""
    p:close()
    return (value:gsub("^'(.*)'$", "%1"))
end
local cursor_theme, cursor_size = gsetting("cursor-theme"), gsetting("cursor-size")
if cursor_theme ~= "" then
    hl.env("XCURSOR_THEME", cursor_theme)
    hl.env("XCURSOR_SIZE", cursor_size ~= "" and cursor_size or "24")
    local function apply_cursor()
        hl.exec_cmd("hyprctl setcursor '" .. cursor_theme .. "' " .. (cursor_size ~= "" and cursor_size or "24"))
    end
    hl.on("hyprland.start", apply_cursor)
    hl.on("config.reloaded", apply_cursor)
end

-- Sway's colours: pink focused border, dark grey otherwise; 5px borders and gaps.
-- Rounded corners, unlike Sway
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 5,
        border_size = 5,
        col = {
            active_border   = "rgb(d18ea6)",
            inactive_border = "rgb(222222)",
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 6,   -- like the GTK theme's, and hyprtoolkit.conf's rounding_large
        shadow   = { enabled = false },
        blur     = { enabled = false },
    },
    group = {
        col = {
            border_active   = "rgb(d18ea6)",
            border_inactive = "rgb(222222)",
        },
        groupbar = {
            font_size = 11,
            col = { active = "rgb(ce3e60)", inactive = "rgb(5f676a)" },
        },
    },
    animations = { enabled = true },
    -- Splits follow the window's shape (wider than tall: side by side), and are
    -- worked out again when windows come and go
    dwindle = { preserve_split = false },
    -- Lone windows on ultrawides are capped with gaps instead (update_lone_windows)
    render = {
        -- Don't tell the monitor a fullscreen window's content type (game,
        -- video...): changing it takes a modeset, and the screens went blank
        -- and came back whenever T3 Code (or anything) went fullscreen
        send_content_type = false,
    },
    misc = {
        -- If hyprlock ever dies, a new one can take over the lock (e.g. from a
        -- TTY: hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("hyprlock")')
        allow_session_lock_restore = true,
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
    },
    binds = {
        -- Focus left/right moves between tabs first, like Sway's tabbed layout
        movefocus_cycles_groupfirst = true,
    },
    input = {
        kb_layout  = "us",
        kb_variant = "dvorak",
        repeat_delay = 200,
        repeat_rate  = 50,
        follow_mouse = 1,
    },
})

-- Hyprland's default animations
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, damping = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  spring = "easy",   style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })


----------------------
---- WINDOW RULES ----
----------------------

hl.window_rule({
    -- Ignore apps asking to be maximized (Hyprland's recommended default)
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland (Hyprland's default config)
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- clipboard.sh's picker: centered over everything, rounded like fuzzel
hl.window_rule({
    name  = "clipboard-picker",
    match = { class = "^clipboard-picker$" },
    float = true,
    size = "1400 800",
    center = true,
    rounding = 12,
})

-- File pickers for Flatpak apps (FSearch's "add folder") come from the GTK
-- portal, a separate app, so Hyprland doesn't float them as dialogs. Tiled,
-- they'd open under the floating app that asked for them. No size: each
-- dialog picks its own (GTK remembers the file chooser's); a fixed one also
-- hit the other portal dialogs, like "Open with", which drew at the wrong size.
hl.window_rule({
    name  = "portal-file-chooser",
    match = { class = "^xdg-desktop-portal-gtk$" },
    float = true,
    center = true,
})

hl.window_rule({
    name  = "spotify",
    match = { class = "^Spotify$" },
    workspace = "10",
})


---------------------
---- KEYBINDINGS ----
---------------------

local function bind(keys, action, opts) hl.bind(mod .. " + " .. keys, action, opts) end
local function run(cmd) return hl.dsp.exec_cmd(cmd) end

-- Basics
bind("Return", run(term))
hl.bind("CTRL + SHIFT + Escape", run(term .. " btop"))   -- task manager, like Windows
-- x-www-browser is Debian's; elsewhere the default browser's .desktop entry
bind("w", run([[command -v x-www-browser >/dev/null && exec x-www-browser; exec gtk-launch "$(xdg-settings get default-web-browser)"]]))
bind("e", run("xdg-open ~"))   -- default folder handler (Nemo)
bind("k", run("keepassxc"))
bind("q", hl.dsp.window.close())
bind("x", hl.dsp.window.close())
-- Noctalia's launcher panel (apps; the same key again closes it) and run-launcher.sh (fuzzel) for commands
local function fuzzel(cmd) return run("pkill -x fuzzel || " .. cmd) end
bind("d", run("noctalia msg panel-toggle launcher"))
bind("u", function() scratch_toggle("fsearch") end)   -- search files: show or hide FSearch

-- Escape dismisses FSearch's main window. Disable the binding everywhere
-- else so other apps and FSearch dialogs keep their normal Escape handling.
local fsearch_escape = hl.bind("Escape", function()
    scratch_toggle("fsearch")
end, { description = "Hide FSearch" })
local function update_fsearch_escape()
    local w = hl.get_active_window()
    fsearch_escape:set_enabled(w ~= nil and app_matches(apps.fsearch, w))
end
hl.on("window.active", update_fsearch_escape)
hl.on("window.title", update_fsearch_escape)
hl.on("window.class", update_fsearch_escape)
update_fsearch_escape()
bind("r", fuzzel(hyprdir .. "/run-launcher.sh"))
-- Clipboard history: Noctalia's clipboard panel
bind("v", run("noctalia msg panel-toggle clipboard"))
-- Noctalia can only dismiss them all
bind("BackSpace", run("makoctl dismiss || noctalia msg notification-clear-active"))
bind("SHIFT + BackSpace", run("makoctl dismiss -a || noctalia msg notification-clear-active"))
bind("l", run("~/scripts/lock.sh"))
bind("SHIFT + r", hl.dsp.reload_config())
bind("SHIFT + q", run("noctalia msg panel-toggle session"))   -- same dialog as the bar's power icon

-- Drag windows with $mod + left mouse button, resize with $mod + right
bind("mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind("mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Focus, move and resize, with the home row or the arrow keys
for _, keys in ipairs({ { left, down, up, right }, { "left", "down", "up", "right" } }) do
    local dirs = { "left", "down", "up", "right" }
    local grow = { { -10, 0 }, { 0, 10 }, { 0, -10 }, { 10, 0 } }
    for i, key in ipairs(keys) do
        bind(key,             hl.dsp.focus({ direction = dirs[i] }))
        bind("SHIFT + " .. key, hl.dsp.window.move({ direction = dirs[i] }))
        if keys[1] == left then
            bind("ALT + " .. key, hl.dsp.window.resize({ x = grow[i][1], y = grow[i][2], relative = true }), { repeating = true })
        end
    end
end

-- Workspaces
for i = 1, 10 do
    local key = i % 10   -- 10 is on the 0 key
    bind(key,              hl.dsp.focus({ workspace = i }))
    bind("SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end
for _, k in ipairs({ { left, "left" }, { right, "right" } }) do
    local delta = k[2] == "left" and -1 or 1
    for _, key in ipairs(k) do
        bind("CTRL + " .. key,         function() ws_step(delta, false) end)
        bind("CTRL + SHIFT + " .. key, function() ws_step(delta, true) end)
    end
end
bind("SHIFT + greater", hl.dsp.workspace.move({ monitor = "r" }))
bind("SHIFT + less",    hl.dsp.workspace.move({ monitor = "l" }))

-- Layout. Hyprland tiles on its own (no manual splits as on Sway): dwindle by
-- default, and $mod+m switches the current workspace between Hyprland's
-- layouts. $mod+comma groups windows into tabs.
local layouts = { "dwindle", "master", "scrolling" }
local ws_layout = {}   -- workspace id -> layout picked with $mod+m
bind("m", function()
    local ws = hl.get_active_workspace()
    if not ws or not ws.id then return end
    local current = ws_layout[ws.id] or ws.tiled_layout or layouts[1]
    local nxt = layouts[1]
    for i, name in ipairs(layouts) do
        if name == current then nxt = layouts[i % #layouts + 1] end
    end
    ws_layout[ws.id] = nxt
    hl.workspace_rule({ workspace = tostring(ws.id), layout = nxt })
    hl.notification.create({ text = "Layout: " .. nxt, timeout = 1500 })
end)
bind("comma",  hl.dsp.group.toggle())
bind("f",      hl.dsp.window.fullscreen())
bind("SHIFT + space", hl.dsp.window.float({ action = "toggle" }))
-- Swap focus between tiled and floating windows
bind("space", function()
    local w = hl.get_active_window()
    if w and w.floating then
        hl.dispatch(hl.dsp.window.cycle_next({ tiled = true }))
    else
        hl.dispatch(hl.dsp.window.cycle_next({ floating = true }))
    end
end)

-- Scratchpad: a special workspace shown over the current one
-- Toggles: a window in the scratchpad comes back to the workspace underneath, any other goes in
bind("SHIFT + minus", run([[
  if [ "$(hyprctl -j activewindow | jq -r '.workspace.name')" = "special:scratchpad" ]; then
    ws=$(hyprctl -j monitors | jq '.[] | select(.focused) | .activeWorkspace.id')
    hyprctl -q dispatch "hl.dsp.window.move({ workspace = $ws })"
  else
    hyprctl -q dispatch 'hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })'
  fi]]))
bind("CTRL + minus",  hl.dsp.workspace.toggle_special("scratchpad"))
-- Pick any window (scratchpad included) from a list
bind("minus", run("noctalia msg panel-toggle launcher /win"))   -- Noctalia's launcher, windows provider
bind("Tab", run("noctalia msg window-switcher"))   -- Noctalia's switcher overlay

-- Media and brightness keys, also while locked
local media = {
    XF86AudioRaiseVolume  = "pactl set-sink-volume @DEFAULT_SINK@ +5%",
    XF86AudioLowerVolume  = "pactl set-sink-volume @DEFAULT_SINK@ -5%",
    XF86AudioMute         = "pactl set-sink-mute @DEFAULT_SINK@ toggle",
    XF86AudioMicMute      = "pactl set-source-mute @DEFAULT_SOURCE@ toggle",
    XF86MonBrightnessUp   = "brightnessctl set +5%",
    XF86MonBrightnessDown = "brightnessctl set 5%-",
    XF86AudioPlay         = "playerctl play-pause",
    XF86AudioNext         = "playerctl next",
    XF86AudioPrev         = "playerctl previous",
}
for key, cmd in pairs(media) do
    local repeating = key:find("Volume") ~= nil or key:find("Brightness") ~= nil
    hl.bind(key, run(cmd), { locked = true, repeating = repeating })
end

-- Screenshots (area, window, screen) to ~/images/screenshots and the clipboard
local shot = [[grimblast copysave %s "$(xdg-user-dir PICTURES)/screenshots/Screenshot_from_$(date +%%Y-%%m-%%d_%%H-%%M-%%S).png"]]
hl.bind("Print",         run(shot:format("area")))
hl.bind("SHIFT + Print", run(shot:format("active")))
hl.bind("CTRL + Print",  run(shot:format("output")))

-- Laptop lid
hl.bind("switch:on:Lid Switch", run("systemctl suspend"), { locked = true })

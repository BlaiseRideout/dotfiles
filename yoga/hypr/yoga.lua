-- Hyprland module for the Lenovo Yoga Book 9i (13IMU9): panel layout and postures,
-- the docked layout, lid handling, the bottom screen reserved for the keyboard,
-- touch and pen mapping, the Noctalia bar lists. Loaded by hyprland.lua only when
-- Yoga hardware is present (yoga/README.md), in a pcall, so a mistake here can never
-- break the main config. Tunables: config.lua. Notes: docs/yoga-book/ (display.md,
-- posture-daemon.md, touchpad.md, touch-ux.md).
--
-- The file returns a function; hyprland.lua calls it once, with its host table:
--   host.dir               the yoga/ checkout
--   host.config            config.lua's table
--   host.is_laptop(m), host.is_tv(m)       monitor classifiers of the shared config
--   host.is_desk_monitor(m)                a monitor with a fixed rule of its own there
--   host.place_workspaces(keep_view), host.focus_ws(id), host.ws_step(delta, move)
--                          the shared config's workspace functions (set up before
--                          this module needs them)
-- and it fills the global `yoga` table, which the shared config calls into at fixed
-- points. Every hook is optional on the shared side (a missing or broken module
-- just means no hook), and all are documented in yoga/README.md:
--   yoga.before_bind()              start of every keybinding: undo a focus move onto the reserved screen
--   yoga.rank(m)                    1 top panel, 2 bottom panel, nil any other monitor
--   yoga.retarget(target)           workspace placement: change target[i] (monitor tables) for the reserved screen
--   yoga.ws_skip(ws)                workspace stepping: leave the reserved screen's workspace out
--   yoga.bar_extra(primary)         extra text for ~/.cache/noctalia/primary.toml
--   yoga.lid_changed(closed)        lid switch; true when handled here (else the shared config suspends on close)
--   yoga.apply_devices()            bind the touch and pen devices to their panels (after hl.config)
--   yoga.start()                    end of the config: loads touch.lua (gestures, binds)
--   yoga.launcher_cmd               set by touch.lua: the launcher the on-screen keyboard can type into
-- The module also keeps the globals that the scripts reach through `hyprctl repl`
-- / `hyprctl eval`: yoga_set_posture, yoga_panel_outputs, yoga_set_reserved,
-- yoga_bottom_reserved, yoga_focus_back, yoga_win_step, yoga_win_to_monitor,
-- yoga_apply_devices, yoga_set_touch_suppressed.

return function(host)
    local cfg = host.config
    local YOGA_TOP_DESC    = cfg.panels.top.desc
    local YOGA_BOTTOM_DESC = cfg.panels.bottom.desc
    local YOGA_TOP_TRANSFORM    = cfg.panels.top.transform
    local YOGA_BOTTOM_TRANSFORM = cfg.panels.bottom.transform
    local YOGA_SCALE = cfg.panels.scale
    local YOGA_LOGICAL_W, YOGA_LOGICAL_H = cfg.panels.logical_w, cfg.panels.logical_h

    local M = {}

    -- Posture. The posture daemon (yoga/bin/yoga-posture, docs/yoga-book/
    -- posture-daemon.md) decides which panels are lit, how each is rotated and how
    -- they are arranged, and hands that to yoga_set_posture() below through
    -- `hyprctl repl`. Everything else (the docked layout, workspaces, clamshell)
    -- stays here: yoga_layout() just asks yoga_plan() where the panels go.
    --   spec = { posture = "tablet", arrange = "stack" | "row_top_left" |
    --            "row_bottom_left", pid = <daemon pid>,
    --            top = { on = bool, transform = 0-3 }, bottom = { same } }
    -- No spec (nil, the default) is the laptop posture: both panels on, stacked,
    -- at the panels' configured transforms. The last spec is kept in
    -- $XDG_RUNTIME_DIR/yoga-posture/layout.lua so a config reload keeps it, but
    -- only while the daemon that wrote it (pid) is alive: a dead daemon can never
    -- leave a panel switched off. Never both panels off.
    local YOGA_POSTURE_FILE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/yoga-posture/layout.lua"
    local YOGA_ARRANGE = { stack = true, row_top_left = true, row_bottom_left = true }
    local yoga_posture = nil

    local function yoga_clean_posture(spec)
        if type(spec) ~= "table" or not YOGA_ARRANGE[spec.arrange] then return nil end
        local function panel(p, rest)
            if type(p) ~= "table" then return nil end
            local t = tonumber(p.transform) or rest
            return { on = p.on ~= false, transform = math.floor(t) % 4 }
        end
        local top, bottom = panel(spec.top, YOGA_TOP_TRANSFORM), panel(spec.bottom, YOGA_BOTTOM_TRANSFORM)
        if not top or not bottom or (not top.on and not bottom.on) then return nil end
        return { posture = tostring(spec.posture or "?"), arrange = spec.arrange,
                 top = top, bottom = bottom, pid = tonumber(spec.pid) }
    end

    do
        local ok, spec = pcall(dofile, YOGA_POSTURE_FILE)
        if ok and type(spec) == "table" and tonumber(spec.pid) then
            local alive = io.open("/proc/" .. math.floor(tonumber(spec.pid)) .. "/cmdline", "r")
            if alive then
                alive:close()
                yoga_posture = yoga_clean_posture(spec)
            end
        end
    end

    -- Where each panel goes relative to the top-left corner of the pair, and the
    -- size of the pair, in logical pixels. A rotated panel is 900 wide and 1440
    -- tall; a panel that is off takes no room.
    local function yoga_plan(spec)
        spec = spec or { arrange = "stack",
                         top = { on = true, transform = YOGA_TOP_TRANSFORM },
                         bottom = { on = true, transform = YOGA_BOTTOM_TRANSFORM } }
        local order = (spec.arrange == "row_bottom_left") and { "bottom", "top" } or { "top", "bottom" }
        local vertical = spec.arrange == "stack"
        local plan, at, pw, ph = {}, 0, 0, 0
        for _, name in ipairs(order) do
            local p = spec[name]
            local w, h = YOGA_LOGICAL_W, YOGA_LOGICAL_H
            if p.transform % 2 == 1 then w, h = h, w end
            local entry = { on = p.on, transform = p.transform, x = 0, y = 0 }
            if p.on then
                if vertical then entry.y = at; at = at + h else entry.x = at; at = at + w end
                pw, ph = math.max(pw, w), math.max(ph, h)
            end
            plan[name] = entry
        end
        if vertical then ph = at else pw = at end
        return plan, pw, ph
    end
    local yoga_plan0, yoga_pw0 = yoga_plan(yoga_posture)

    -- One rule per panel. Mode "highrr" takes the highest refresh rate at the
    -- native size: only 60Hz is offered today, so this is 60 until a 120Hz mode
    -- ever shows up.
    local function yoga_rule(desc, x, y, transform, disabled)
        hl.monitor({
            output = "desc:" .. desc, mode = "highrr", position = x .. "x" .. y,
            scale = YOGA_SCALE, transform = transform, disabled = disabled or false,
        })
    end
    -- Standalone layout: top panel above bottom panel, and also the docked one
    -- except next to the desk's own monitors (yoga_layout, below); other postures
    -- come from the daemon (yoga_plan).
    yoga_rule(YOGA_TOP_DESC,    yoga_plan0.top.x,    yoga_plan0.top.y,    yoga_plan0.top.transform,    not yoga_plan0.top.on)
    yoga_rule(YOGA_BOTTOM_DESC, yoga_plan0.bottom.x, yoga_plan0.bottom.y, yoga_plan0.bottom.transform, not yoga_plan0.bottom.on)

    -- The Yoga's docked reference layout: kanshi's "kens-triple" profile
    -- (.config/kanshi/config), the two monitors Blaise docks it with (config.lua,
    -- `docked`). As there the laptop is on the left and the monitors follow to the
    -- right. Their x is relative to the right edge of the laptop pair (dx), which is
    -- 1440 for the laptop posture and moves with the posture (yoga_layout
    -- re-issues the rules when it does). These rules match nothing unless those
    -- monitors are connected.
    local DOCKED = cfg.docked or {}
    local function docked_rule(k, pair_w)
        hl.monitor({ output = "desc:" .. k.desc, mode = k.mode, position = (pair_w + k.dx) .. "x" .. k.y,
                     scale = 1, transform = k.transform })
    end
    for _, k in ipairs(DOCKED) do docked_rule(k, yoga_pw0) end

    -- 1 for the Yoga's top panel, 2 for its bottom one, nil for any other monitor
    local function yoga_rank(m)
        local d = m.description or ""
        if d == YOGA_TOP_DESC then return 1 end
        if d == YOGA_BOTTOM_DESC then return 2 end
        return nil
    end
    M.rank = yoga_rank

    local function logical_size(m)
        local w, h = m.width / m.scale, m.height / m.scale
        if m.transform % 2 == 1 then w, h = h, w end
        return w, h
    end

    local function yoga_panels()
        local top, bottom
        for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
            local r = yoga_rank(m)
            if r == 1 then top = m elseif r == 2 then bottom = m end
        end
        return top, bottom
    end

    local function external_monitors()
        local out = {}
        for _, m in ipairs(hl.get_monitors() or {}) do
            if not host.is_laptop(m) then table.insert(out, m) end
        end
        return out
    end

    -- How far below its place the bottom panel is parked while it is reserved (see
    -- keep_cursor_off_bottom). Logical pixels; far more than one pointer event can move.
    local RESERVED_AWAY = 10000

    local lid_closed = false
    do
        local p = io.popen("cat /proc/acpi/button/lid/*/state 2>/dev/null")
        if p then
            lid_closed = (p:read("*a") or ""):find("closed") ~= nil
            p:close()
        end
    end

    -- The docked monitor's entry in config.lua (`docked`) if m is one
    local function docked_of(m)
        local d = m.description or ""
        for _, k in ipairs(DOCKED) do
            if d == k.desc then return k end
        end
        return nil
    end

    -- Folded back (tablet, tent: in a stand, say) the lid sensor can read "closed" without the lid
    -- being closed (see yoga-posture's LID_GLITCH_ABOVE). Never suspend or switch the panels off
    -- for that: this runs on every config load and every monitor change as well as on the lid
    -- event itself, and a config load while the sensor read "closed" in the stand suspended the
    -- machine (also from `Hyprland --verify-config`, which runs the config).
    -- The posture daemon commits a posture 0.5 s after the sensors show it, but the lid sensor
    -- can trip right at the start of the fold: it also leaves $XDG_RUNTIME_DIR/yoga/folded (its
    -- pid) while the hinge is at or above its LID_GLITCH_ABOVE or the posture is tent/tablet, and
    -- that counts here at once. Only while that pid lives, so a dead daemon cannot leave it set.
    local YOGA_FOLD_FILE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/yoga/folded"
    local function yoga_fold_guard()
        local f = io.open(YOGA_FOLD_FILE, "r")
        if not f then return false end
        local pid = tonumber(f:read("*l") or "")
        f:close()
        if not pid then return false end
        local alive = io.open("/proc/" .. math.floor(pid) .. "/cmdline", "r")
        if alive then alive:close() return true end
        return false
    end
    local function yoga_folded()
        if yoga_posture ~= nil and (yoga_posture.posture == "tablet" or yoga_posture.posture == "tent") then
            return true
        end
        return yoga_fold_guard()
    end

    -- Standalone and docked layouts. Standalone (no other monitor): the two panels
    -- stacked, top panel on top (the rules above). Docked (any non-eDP monitor
    -- connected): the same stack on the left and the monitors to its right, as in
    -- kanshi's kens-triple (the `docked` rules). With the lid closed and a monitor
    -- connected, the panels are turned off instead of suspending (clamshell);
    -- closing the lid with no monitor, or unplugging the last one with the lid
    -- closed, suspends as on any laptop. Does nothing when the Yoga's panels aren't
    -- there.
    --
    -- Monitors with a rule of their own in the shared config keep it: the docked
    -- pair above and the desk's G95C, AOC and TV. With the desk's monitors the pair
    -- goes below the largest one, centered, because those rules put a monitor at
    -- 0,100 where the panels would otherwise be; with anything else the panels stay
    -- at the left as in kens. Any other external would be placed by the catch-all's
    -- "auto", which follows wherever the panels happen to be and so moves whenever
    -- they do; those are laid out here instead, in a row from the right edge of what
    -- is already placed (the panels or the fixed monitors), sorted by connector
    -- name, top-aligned.
    local function yoga_layout()
        local top, bottom = yoga_panels()
        if not top or not bottom then return end
        local ext = external_monitors()
        -- forget a "closed" that was read in the fold, so it cannot come back when the posture changes
        if lid_closed and yoga_folded() then lid_closed = false end
        local lid = lid_closed
        if lid and #ext == 0 then
            hl.exec_cmd("systemctl suspend")
            return
        end
        local clamshell = lid
        local panels, pw = yoga_plan(yoga_posture)
        local x, y = 0, 0
        if #ext > 0 then
            -- plan: where every external will be (x, y, logical size)
            local plan, managed, desk = {}, {}, false
            local edge = pw   -- right edge of everything placed so far
            for _, m in ipairs(ext) do
                local w, h = logical_size(m)
                local k = docked_of(m)
                if k then
                    -- next to the laptop pair, wherever the posture made its right edge
                    local px = pw + k.dx
                    table.insert(plan, { m = m, x = px, y = k.y, w = w, h = h })
                    if m.x ~= px or m.y ~= k.y then docked_rule(k, pw) end
                    edge = math.max(edge, px + w)
                elseif host.is_desk_monitor(m) then
                    table.insert(plan, { m = m, x = m.x, y = m.y, w = w, h = h })
                    desk = true
                    edge = math.max(edge, m.x + w)
                else
                    table.insert(managed, m)
                end
            end
            if desk then edge = 0 end
            table.sort(managed, function(a, b) return a.name < b.name end)
            for _, m in ipairs(managed) do
                local w, h = logical_size(m)
                local px, py = math.floor(edge), 0
                table.insert(plan, { m = m, x = px, y = py, w = w, h = h })
                if m.x ~= px or m.y ~= py then
                    hl.monitor({ output = m.name, mode = "preferred", position = px .. "x" .. py, scale = "auto",
                                 transform = m.transform })
                end
                edge = edge + w
            end
            if desk then
                local main = plan[1]
                for _, p in ipairs(plan) do
                    if p.w * p.h > main.w * main.h then main = p end
                end
                x = math.floor(main.x + (main.w - pw) / 2)
                y = math.floor(main.y + main.h)
            end
        end
        -- the bottom panel, while it is reserved for the keyboard, sits out of the pointer's reach
        local away = yoga_bottom_reserved and panels.top.on and panels.bottom.on and not clamshell
        local function apply(m, desc, p, off)
            local want_on = p.on and not clamshell
            local px, py = x + p.x, y + p.y + (off or 0)
            if want_on then
                if m.enabled and m.x == px and m.y == py and m.transform == p.transform then return end
            elseif not m.enabled then
                return
            end
            yoga_rule(desc, px, py, p.transform, not want_on)
        end
        -- The panels that stay lit first, so there is never a moment with none
        for _, lit in ipairs({ true, false }) do
            if (panels.top.on and not clamshell) == lit then apply(top, YOGA_TOP_DESC, panels.top) end
            if (panels.bottom.on and not clamshell) == lit then apply(bottom, YOGA_BOTTOM_DESC, panels.bottom, away and RESERVED_AWAY or 0) end
        end
    end

    -- Events fire before the monitor list has settled, so look again shortly after
    local yoga_timer
    local function schedule_yoga_layout()
        if yoga_timer then return end
        yoga_timer = hl.timer(function() yoga_timer = nil; yoga_layout() end,
                              { timeout = 300, type = "oneshot" })
    end
    hl.on("monitor.added",   schedule_yoga_layout)
    hl.on("monitor.removed", schedule_yoga_layout)
    hl.on("config.reloaded", schedule_yoga_layout)
    schedule_yoga_layout()

    -- Lid switch. With a monitor connected the lid just turns the panels off or on.
    -- Returns true when it did the handling; false means the Yoga's panels aren't
    -- there and the shared config suspends on close, as on any laptop.
    function M.lid_changed(closed)
        -- Folded back (tablet, tent: in a stand, say) the lid sensor can trip without the
        -- lid being closed; do not turn the panels off or suspend for it. The posture daemon
        -- (yoga-posture) knows the hinge angle and says which posture this is.
        if closed and yoga_folded() then return true end
        lid_closed = closed
        local top = yoga_panels()
        if top then
            yoga_layout()
            return true
        end
        return false
    end

    -- The connector names of the top and bottom panels, for yoga-posture (which
    -- starts the on-screen keyboard on the right one)
    function yoga_panel_outputs()
        local top, bottom = yoga_panels()
        if not top or not bottom then return "", "" end
        return top.name, bottom.name
    end

    -- Called by the posture daemon (yoga-posture) through `hyprctl repl`; see
    -- Posture above. nil goes back to the plain laptop layout. Returns a short
    -- description of what it did, which hyprctl prints.
    function yoga_set_posture(spec)
        local clean = yoga_clean_posture(spec)
        if spec ~= nil and not clean then return "rejected: bad posture spec" end
        -- "reserved" (the bottom screen's workspaces on the top screen) only exists with both
        -- panels lit: hand them back while the bottom panel is still there, before one goes off
        if clean and not (clean.top.on and clean.bottom.on) and yoga_bottom_reserved then
            pcall(yoga_set_reserved, false)
        end
        yoga_posture = clean
        if clean then
            local f = io.open(YOGA_POSTURE_FILE, "w")
            if f then
                f:write(string.format(
                    "return { posture = %q, arrange = %q, pid = %d,\n  top = { on = %s, transform = %d },\n"
                    .. "  bottom = { on = %s, transform = %d } }\n",
                    clean.posture, clean.arrange, clean.pid or 0,
                    tostring(clean.top.on), clean.top.transform, tostring(clean.bottom.on), clean.bottom.transform))
                f:close()
            end
        else
            os.remove(YOGA_POSTURE_FILE)
        end
        local top = yoga_panels()
        if not top then return "no yoga panels" end
        yoga_layout()
        yoga_apply_devices()
        if host.refresh_bar then host.refresh_bar() end   -- the bar lists depend on the posture (book split)
        return "ok " .. (clean and clean.posture or "default")
    end

    -- The bars' widget lists, written into primary.toml next to the primary's
    -- `match` (see config.lua, `bar`). Nothing on a machine without both panels.
    local BAR = cfg.bar
    function M.bar_extra(primary)
        local top, bottom = yoga_panels()
        if not (top and bottom) then return "" end
        local function list(t, drop_osk, keep_osk)
            local q = {}
            for _, w in ipairs(t) do
                if w == "OSK" then
                    if keep_osk then table.insert(q, '"osk"') end
                else
                    table.insert(q, '"' .. w .. '"')
                end
            end
            return "[ " .. table.concat(q, ", ") .. " ]"
        end
        local primary_is_laptop = (primary == top.name or primary == bottom.name)
        -- Side by side (book) with a laptop panel as primary: the start widgets on the left
        -- screen's bar, the end widgets on the right screen's (config.lua, bar.book_split)
        if BAR.book_split ~= false and primary_is_laptop and yoga_posture and yoga_posture.posture == "book"
            and yoga_posture.top.on and yoga_posture.bottom.on then
            local left = (yoga_posture.arrange == "row_bottom_left") and bottom or top
            local function role(m)
                if m == left then
                    return "start = " .. list(BAR.full_start) .. "\ncenter = [ ]\nend = [ ]\n"
                end
                return "start = [ ]\ncenter = [ ]\nend = " .. list(BAR.full_end, false, true) .. "\n"
            end
            local out = role(primary == top.name and top or bottom)
            for _, e in ipairs({ { "yoga_top", top }, { "yoga_bottom", bottom } }) do
                if e[2].name ~= primary then
                    out = out .. "\n[bar.default.monitor." .. e[1] .. "]\nmatch = \"" .. e[2].name .. "\"\n" .. role(e[2])
                end
            end
            return out
        end
        local out = "start = " .. list(BAR.full_start) .. "\n"
            .. "end = " .. list(BAR.full_end, false, primary_is_laptop) .. "\n"
        -- top before bottom, so the text is the same every time (pairs() order is not)
        for _, e in ipairs({ { "yoga_top", top }, { "yoga_bottom", bottom } }) do
            local id, m = e[1], e[2]
            if m.name ~= primary then
                out = out .. "\n[bar.default.monitor." .. id .. "]\nmatch = \"" .. m.name .. "\"\n"
                    .. "start = " .. list(BAR.plain.start) .. "\n"
                    .. "center = " .. list(BAR.plain.center) .. "\n"
                    .. "end = " .. list(BAR.plain.end_) .. "\n"
            end
        end
        return out
    end

    -- true while the bottom screen is taken by the physical keyboard or the
    -- on-screen keyboard. Set by yoga_set_reserved() (below), called from
    -- yoga/bin/yoga-bottom-reserve; reset by a config reload, which that script
    -- notices within a few seconds and re-applies.
    yoga_bottom_reserved = false

    -- Workspace placement while the bottom panel is reserved for the keyboard
    -- (yoga_set_reserved): whatever would live on it lives on the top panel instead.
    -- target[i] is the monitor of workspace i (1-10).
    function M.retarget(target)
        local both = yoga_posture == nil or (yoga_posture.top.on and yoga_posture.bottom.on)
        if yoga_bottom_reserved and both then
            local yt, yb = yoga_panels()
            if yt and yb then
                for i = 1, 10 do
                    if target[i].name == yb.name then target[i] = yt end
                end
            end
        end
    end

    -- Workspace stepping (the shared ws_step): the screen carrying the keyboard is not part of
    -- the ring
    function M.ws_skip(w)
        if not yoga_bottom_reserved then return false end
        local _, bottom = yoga_panels()
        return bottom ~= nil and w.monitor ~= nil and w.monitor.name == bottom.name
    end

    -- Free the Yoga's bottom screen for the keyboard: its workspace(s) move to the top
    -- panel, which keeps showing the workspace it was showing, and the focus ends up
    -- where it started (unless it was on a workspace that moved: then on the top panel's
    -- own). With on == false they move back and the bottom panel shows what it showed.
    -- Does nothing unless both panels are lit (tent, tablet, closed lid: nothing to free).
    local RESERVED_WS = "kbd"   -- the bottom screen's own workspace while it carries the keyboard
    local yoga_reserved_moved   -- { ids = { ... }, active = id } of what moved to the top panel

    -- The pointer stays off the reserved bottom screen: it is covered by the docked keyboard
    -- or by the full-height on-screen keyboard and the touchpad strip, so a cursor there is
    -- hidden under them or drawn over the keys. While yoga_bottom_reserved, yoga_layout()
    -- parks that panel RESERVED_AWAY logical px below where it belongs, so no pointer motion
    -- can reach it (Hyprland keeps the pointer inside the union of the monitors; a gap of
    -- one pixel would not do, a relative move jumps over it). Touch is unaffected: it is
    -- mapped to the panel itself, not to its place in the layout. This is only for a pointer
    -- that is already on the bottom screen when the reservation starts: put it on the
    -- nearest point of the top panel before the panel moves away.
    -- Only dual-screen: the floating tablet-mode keyboard (one lit panel) never reserves,
    -- so there the pointer goes wherever it likes.
    local function keep_cursor_off_bottom()
        local top, bottom = yoga_panels()
        if not (top and bottom and top.enabled and bottom.enabled) then return end
        local c = hl.get_cursor_pos()
        if not c then return end
        local bw, bh = logical_size(bottom)
        if c.x < bottom.x or c.x >= bottom.x + bw or c.y < bottom.y or c.y >= bottom.y + bh then return end
        local tw, th = logical_size(top)
        local x = math.max(top.x, math.min(c.x, top.x + tw - 1))
        local y = math.max(top.y, math.min(c.y, top.y + th - 1))
        hl.dispatch(hl.dsp.cursor.move({ x = x, y = y }))
    end

    function yoga_set_reserved(on)
        on = on and true or false
        if on == yoga_bottom_reserved then return "unchanged" end
        local top, bottom = yoga_panels()
        if not (top and bottom and top.enabled and bottom.enabled) then return "both panels are not on" end
        local focused = hl.get_active_workspace()
        local focused_id = focused and focused.id
        local top_active = top.active_workspace and top.active_workspace.id

        if on then
            local ids = {}
            for _, ws in ipairs(hl.get_workspaces() or {}) do
                if ws.id and ws.id > 0 and ws.monitor and ws.monitor.name == bottom.name then
                    table.insert(ids, ws.id)
                end
            end
            yoga_reserved_moved = { ids = ids, active = bottom.active_workspace and bottom.active_workspace.id }
            keep_cursor_off_bottom()
            yoga_bottom_reserved = true
            yoga_layout()   -- park the panel out of the pointer's reach
            -- Give the bare screen a workspace of its own first. Left to itself Hyprland makes it
            -- the next free number (11, 12, ...), a new one each time, and those turned up in the
            -- bar and in the workspace keys. A named workspace has no number, so it is neither.
            hl.workspace_rule({ workspace = "name:" .. RESERVED_WS, monitor = bottom.name,
                                default_name = cfg.bar.workspace_dot or "", persistent = false })
            hl.dispatch(hl.dsp.focus({ workspace = "name:" .. RESERVED_WS }))
            host.place_workspaces("none")   -- the numbered rules now point 9 and 10 at the top panel
            for _, id in ipairs(ids) do
                local ws = hl.get_workspace(id)
                if ws and ws.monitor and ws.monitor.name ~= top.name then
                    hl.dispatch(hl.dsp.workspace.move({ workspace = id, monitor = top.name }))
                end
            end
            -- the top panel keeps what it showed
            if top_active and hl.get_workspace(top_active) then host.focus_ws(top_active) end
            local moved = false
            for _, id in ipairs(ids) do if id == focused_id then moved = true end end
            if focused_id and not moved and focused_id ~= top_active and hl.get_workspace(focused_id) then
                host.focus_ws(focused_id)
            end
            return "reserved"
        end

        yoga_bottom_reserved = false
        yoga_layout()       -- and back in its place
        local st = yoga_reserved_moved
        yoga_reserved_moved = nil
        host.place_workspaces("none")   -- rules back to the bottom panel for 9 and 10
        if st then
            for _, id in ipairs(st.ids) do
                local ws = hl.get_workspace(id)
                if ws and ws.monitor and ws.monitor.name ~= bottom.name then
                    hl.dispatch(hl.dsp.workspace.move({ workspace = id, monitor = bottom.name }))
                end
            end
            -- show what was showing, unless that was one of the empty workspaces Hyprland
            -- makes for a bare monitor: then the first one with windows in it
            local function nwin(id)
                local w = hl.get_workspace(id)
                return w and (w.windows or 0) or -1
            end
            local show
            if st.active and nwin(st.active) > 0 then show = st.active end
            if not show then
                for _, id in ipairs(st.ids) do
                    if nwin(id) > 0 then show = id break end
                end
            end
            show = show or (st.active and nwin(st.active) >= 0 and st.active or nil)
            if not show then
                -- nothing of its own: the numbered workspace its rule points at (9 or 10)
                for _, id in ipairs({ 10, 9 }) do
                    local w = hl.get_workspace(id)
                    if not w or (w.monitor and w.monitor.name == bottom.name) then show = id break end
                end
            end
            if show then host.focus_ws(show) end
            -- the top panel and the focus as they were
            if top_active and hl.get_workspace(top_active) then host.focus_ws(top_active) end
            if focused_id and hl.get_workspace(focused_id) then host.focus_ws(focused_id) end
        end
        return "released"
    end

    -- While the bottom panel is reserved for the keyboard, touching it (a tap on the
    -- on-screen keyboard or the touchpad strip) must not take the focus: Hyprland moves the
    -- active monitor to whichever one a touch lands on, so a shortcut typed on the virtual
    -- keyboard (SUPER+something that starts an app) would open the app on the bottom screen,
    -- under the touchpad. Put the focus straight back on the monitor it was on, so apps open
    -- on the workspace you are working on and the text box keeps its keyboard focus.
    local yoga_last_focus_monitor
    hl.on("monitor.focused", function()
        local focused
        for _, m in ipairs(hl.get_monitors() or {}) do
            if m.focused then focused = m end
        end
        if not focused then return end
        local _, bottom = yoga_panels()
        if yoga_bottom_reserved and bottom and focused.name == bottom.name then
            if yoga_last_focus_monitor and yoga_last_focus_monitor ~= bottom.name then
                hl.dispatch(hl.dsp.focus({ monitor = yoga_last_focus_monitor }))
            end
        else
            yoga_last_focus_monitor = focused.name
        end
    end)

    -- Called at the start of every keybinding (yoga.before_bind): a shortcut typed on the
    -- on-screen keyboard arrives right after the touch that moved the focus to the bottom
    -- screen, before the handler above has had its say, and would act on the bottom screen's
    -- workspace (switch to its neighbours, start apps on it). While the bottom screen is
    -- reserved, make sure the focus is on the monitor you were on before acting.
    function yoga_focus_back()
        if not yoga_bottom_reserved or not yoga_last_focus_monitor then return end
        local focused
        for _, m in ipairs(hl.get_monitors() or {}) do
            if m.focused then focused = m end
        end
        local _, bottom = yoga_panels()
        if focused and bottom and focused.name == bottom.name and yoga_last_focus_monitor ~= bottom.name then
            hl.dispatch(hl.dsp.focus({ monitor = yoga_last_focus_monitor }))
        end
    end
    M.before_bind = yoga_focus_back

    -- For the touch gestures (touch.lua): send the focused window to the next or
    -- previous workspace (following it), or to the screen above or below, from the monitor
    -- you were working on (not the bottom screen reserved for the keyboard, which is also
    -- never a destination while it is reserved)
    function yoga_win_step(delta)
        yoga_focus_back()
        host.ws_step(delta, true)
    end
    function yoga_win_to_monitor(dir)
        yoga_focus_back()
        if dir == "d" and yoga_bottom_reserved then return end
        hl.dispatch(hl.dsp.window.move({ monitor = dir }))
    end

    -- Touch and pen: each digitizer node goes to the panel it is on, by the same
    -- descriptions the monitor rules use, so a swap in config.lua moves the touch and
    -- pen mapping with it. Matching by device name means nothing happens on other
    -- machines. Mapping a device to a panel also follows that panel's transform
    -- (check this after changing a transform). The posture daemon rotates the panels,
    -- so touch and pen must rotate with them: see touch.follows_panel in config.lua.
    do
        local T = cfg.touch
        local prefix = T.device_prefix
        -- device, the panel it sits on, the fixed extra transform
        local top_panel, bottom_panel = "top", "bottom"
        if T.swap then top_panel, bottom_panel = bottom_panel, top_panel end
        -- 5th field: the node whose palm suppression (yoga_set_touch_suppressed) switches the
        -- device off. It names the digitiser node ("top" = Touchscreen Top), not the panel:
        -- yoga-palm sees the raw reports of each node. The virtual touchscreen carries the
        -- bottom node's touches (yoga-touchpad grabs the real one), so it follows "bottom".
        local map = {
            { "touchscreen-top",    top_panel,    T.transform_top,        nil, "top" },
            { "touchscreen-bottom", bottom_panel, T.transform_bottom,     nil, "bottom" },
            { "stylus-top",         top_panel,    T.pen_transform_top },
            { "stylus-bottom",      bottom_panel, T.pen_transform_bottom },
            -- the virtual touchscreen made by yoga-touchpad: same panel, same
            -- transform; a 4th field replaces the name prefix
            { T.virtual_bottom, bottom_panel, T.transform_bottom, "", "bottom" },
        }
        -- Palm suppression: yoga/bin/yoga-palm (docs/yoga-book/palm.md) switches a touchscreen
        -- node off while it sees a palm or the pen near it. Kept here, not just applied once, so
        -- a posture change (yoga_apply_devices) cannot switch a suppressed node back on.
        yoga_touch_suppressed = {}
        local descs = { top = YOGA_TOP_DESC, bottom = YOGA_BOTTOM_DESC }
        -- Devices are bound by connector name (eDP-1...), looked up from the
        -- description here, because that is what the device setting is known to
        -- accept; "desc:..." is the fallback if the panel isn't up yet
        local function output_of(desc)
            for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
                if m.description == desc then return m.name end
            end
            return "desc:" .. desc
        end
        -- Called after the config's own settings (yoga.apply_devices) and by
        -- yoga_set_posture. A device whose panel is off is switched off with it (the
        -- hand holding a tablet rests on the back panel's digitiser); the rest stay
        -- bound to their panel.
        local function apply_device(d, plan)
            local panel = plan[d[2]]
            local spec = { name = (d[4] or prefix) .. d[1], output = output_of(descs[d[2]]),
                           enabled = panel.on and not (d[5] and yoga_touch_suppressed[d[5]]) }
            if d[3] ~= nil then
                spec.transform = d[3]
            elseif T.follows_panel then
                -- the top panel's digitiser is not rotated with its panel (config.lua, top_offset)
                local offset = (d[2] == "top") and (T.top_offset or 0) or 0
                spec.transform = (panel.transform + offset) % 4
                if (T.rotation_sense or 1) < 0 then spec.transform = (4 - spec.transform) % 4 end
            end
            hl.device(spec)
        end
        function yoga_apply_devices()
            local plan = yoga_plan(yoga_posture)
            for _, d in ipairs(map) do apply_device(d, plan) end
            -- the virtual touchpad made by yoga-touchpad: natural (inverted) two-finger
            -- scrolling, for this pad only (a global input.natural_scroll would flip the
            -- mice too)
            hl.device({ name = "yoga-virtual-touchpad", natural_scroll = true })
        end
        M.apply_devices = yoga_apply_devices

        -- Called by yoga-palm through `hyprctl repl`: node = "top" | "bottom", on = true to
        -- switch that node's touchscreen (and, for "bottom", the virtual touchscreen) off. Only
        -- the touchscreens are touched, each re-applied with its full spec like
        -- yoga_apply_devices does. Answers "suppressed", "released" or "unchanged".
        function yoga_set_touch_suppressed(node, on)
            if node ~= "top" and node ~= "bottom" then return "error: node must be top or bottom" end
            on = on and true or false
            if (yoga_touch_suppressed[node] or false) == on then return "unchanged" end
            yoga_touch_suppressed[node] = on or nil
            local plan = yoga_plan(yoga_posture)
            for _, d in ipairs(map) do
                if d[5] == node then apply_device(d, plan) end
            end
            return on and "suppressed" or "released"
        end
    end

    -- Touch UX (hyprgrass gestures, the on-screen keyboard, the rescue bind), last,
    -- when the shared config has defined everything it binds to. A failure there
    -- must not take the rest down.
    function M.start()
        -- The kernel flags the top panel as mounted upside down (video=eDP-1:panel_orientation=
        -- upside_down) and Hyprland rotates the picture for it, but the hardware cursor plane is
        -- not rotated: the cursor was drawn upside down and mirrored, so the touchpad seemed to
        -- move it backwards on both axes (top panel only). A software cursor is rotated with the
        -- picture. Cost: a little CPU on cursor moves.
        local ok_c, err_c = pcall(hl.config, { cursor = { no_hardware_cursors = 1 } })
        if not ok_c then hl.notification.create({ text = "yoga: software cursor: " .. tostring(err_c), timeout = 8000 }) end
        local path = host.dir .. "/hypr/touch.lua"
        local chunk, err = loadfile(path)
        if chunk then
            local ok
            ok, err = pcall(chunk, M, host)
            if ok then return end
        end
        hl.notification.create({ text = "yoga/hypr/touch.lua: " .. tostring(err), timeout = 8000 })
    end

    return M
end

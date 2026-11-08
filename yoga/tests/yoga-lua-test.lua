-- Loads yoga/hypr/yoga.lua against a stub `hl` and checks the lid guard and the
-- "reserved only with both panels" rule, and the palm suppression switch. Run by state-sim.py (lua5.4 / luajit).
-- Needs XDG_RUNTIME_DIR to be a scratch directory (the guard file is read from it).
local root = assert(arg[1], "usage: yoga-lua-test.lua <repo root>")
local rt = assert(os.getenv("XDG_RUNTIME_DIR"))
local fails = 0
local function check(cond, msg)
    if not cond then fails = fails + 1; print("    FAIL: " .. msg) end
end

local cfg = dofile(root .. "/yoga/hypr/config.lua")
local cmds, dispatched, rules, devices = {}, {}, {}, {}
local monitors = {
    { name = "eDP-1", description = cfg.panels.top.desc, width = 2880, height = 1800, scale = 2, transform = 2,
      x = 0, y = 0, enabled = true, focused = true, active_workspace = { id = 1 } },
    { name = "eDP-2", description = cfg.panels.bottom.desc, width = 2880, height = 1800, scale = 2, transform = 0,
      x = 0, y = 900, enabled = true, focused = false, active_workspace = { id = 9 } },
}
local workspaces = { { id = 1, monitor = monitors[1], windows = 1 }, { id = 9, monitor = monitors[2], windows = 0 } }
hl = setmetatable({
    get_monitors = function() return monitors end,
    get_workspaces = function() return workspaces end,
    get_workspace = function(id) for _, w in ipairs(workspaces) do if w.id == id then return w end end end,
    get_active_workspace = function() return workspaces[1] end,
    exec_cmd = function(c) table.insert(cmds, c) end,
    monitor = function(r) table.insert(rules, r) end,
    on = function() end, timer = function(fn) return fn end, device = function(spec) table.insert(devices, spec) end, config = function() end,
    dispatch = function(d) table.insert(dispatched, d) end,
    notification = { create = function() end },
    dsp = { workspace = { move = function(t) return { move = t } end }, focus = function(t) return { focus = t } end,
            window = { move = function(t) return t end } },
}, { __index = function() return function() end end })

local host = {
    config = cfg,
    is_laptop = function(m) return m.name:match("^eDP") ~= nil end,
    is_tv = function() return false end, is_desk_monitor = function() return false end,
    place_workspaces = function() end, focus_ws = function() end, ws_step = function() end,
}
local setup = dofile(root .. "/yoga/hypr/yoga.lua")
local M = setup(host)

local function suspended()
    for _, c in ipairs(cmds) do if c:find("systemctl suspend", 1, true) then return true end end
    return false
end
local function guard(pid)
    os.execute("mkdir -p " .. rt .. "/yoga")
    local f = assert(io.open(rt .. "/yoga/folded", "w"))
    if pid then f:write(pid .. "\n") end
    f:close()
end

-- 1. no guard, no other monitor: closing the lid suspends (the stub sees it)
cmds = {}
M.lid_changed(true)
check(suspended(), "sanity: a lid close with no guard suspends")
M.lid_changed(false)

-- 2. guard naming a live pid (this process's parent shell is alive; use pid 1)
cmds = {}
guard(1)
local handled = M.lid_changed(true)
check(handled == true, "lid_changed returns true (handled) while the fold guard is up")
check(not suspended(), "the fold guard stops the suspend")

-- 3. a guard whose pid is gone is not believed
cmds = {}
guard(999999)
M.lid_changed(true)
check(suspended(), "a stale guard (dead pid) does not block a real close")
M.lid_changed(false)

-- 4. garbage guard
cmds = {}
guard(nil)
M.lid_changed(true)
check(suspended(), "an empty guard file does not block")
M.lid_changed(false)
os.remove(rt .. "/yoga/folded")

-- 5. going to one panel hands the reserved workspaces back first
yoga_bottom_reserved = true
local before = #dispatched
local ans = yoga_set_posture({ posture = "tablet", arrange = "stack", pid = 1,
    top = { on = false, transform = 2 }, bottom = { on = true, transform = 0 } })
check(yoga_bottom_reserved == false, "yoga_set_posture(single) releases the reserved bottom screen (" .. tostring(ans) .. ")")

-- 6. reserved is not applied to the workspace placement while one panel is off
local target = {}
for i = 1, 10 do target[i] = monitors[2] end
M.retarget(target)
local moved = false
for i = 1, 10 do if target[i] ~= monitors[2] then moved = true end end
yoga_bottom_reserved = true
M.retarget(target)
for i = 1, 10 do if target[i] ~= monitors[2] then moved = true end end
check(not moved, "retarget leaves the targets alone with a panel off")

-- 7. palm suppression (yoga-palm): switches one touchscreen node off, and keeps it off across
-- a posture change, until released
local function last_enabled(name)
    for i = #devices, 1, -1 do
        if devices[i].name == name then return devices[i].enabled end
    end
end
local prefix = cfg.touch.device_prefix
yoga_set_posture(nil)   -- back to the laptop posture (test 5 left a single-panel one)
devices = {}
check(yoga_set_touch_suppressed("top", true) == "suppressed", "suppress top answers 'suppressed'")
check(last_enabled(prefix .. "touchscreen-top") == false, "the top touchscreen is switched off")
check(last_enabled(prefix .. "stylus-top") == nil, "the pen is left alone (only touchscreens are touched)")
check(last_enabled(prefix .. "touchscreen-bottom") == nil, "the bottom touchscreen is not touched by a top suppression")
check(yoga_set_touch_suppressed("top", true) == "unchanged", "suppressing twice is a no-op")
devices = {}
yoga_apply_devices()
check(last_enabled(prefix .. "touchscreen-top") == false, "a posture/device re-apply keeps the suppressed node off")
check(last_enabled(prefix .. "touchscreen-bottom") == true, "... and the other node stays on")
devices = {}
check(yoga_set_touch_suppressed("bottom", true) == "suppressed", "suppress bottom")
check(last_enabled(prefix .. "touchscreen-bottom") == false, "the bottom touchscreen is switched off")
check(last_enabled(cfg.touch.virtual_bottom) == false, "... and so is the virtual touchscreen carrying its touches")
check(yoga_set_touch_suppressed("top", false) == "released", "release top")
check(last_enabled(prefix .. "touchscreen-top") == true, "the top touchscreen is back on")
yoga_set_touch_suppressed("bottom", false)
check(last_enabled(cfg.touch.virtual_bottom) == true, "the virtual touchscreen is back on")
check(tostring(yoga_set_touch_suppressed("left", true)):find("error", 1, true), "an unknown node is refused")
-- a node whose panel is off stays off after a release
yoga_set_posture({ posture = "tablet", arrange = "stack", pid = 1,
    top = { on = false, transform = 2 }, bottom = { on = true, transform = 0 } })
yoga_set_touch_suppressed("top", true)
yoga_set_touch_suppressed("top", false)
check(last_enabled(prefix .. "touchscreen-top") == false, "releasing the palm hold does not light a panel that is off")

print(fails == 0 and "lua ok" or ("lua: " .. fails .. " failed"))
os.exit(fails == 0 and 0 or 1)

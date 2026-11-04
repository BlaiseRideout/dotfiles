--!nonstrict
-- Reads the keyboard halves with levels.sh every poll_interval and publishes a
-- snapshot under "zmk" for the bar widgets. Sends a notification when a half drops
-- to low_threshold or below, again at critical_threshold, and re-arms once it is
-- back above low_threshold + 5 (as zmk-battery.sh did).

local SNAPSHOT_KEY = "zmk"
local COMMAND_KEY = "zmk_command"
local HYSTERESIS = 5
local LABELS = { "L", "R" }

local running = false
local lastRun = 0
local alertState = {} -- "<device>-<label>" -> "ok" | "low" | "critical"

local function intConfig(key, fallback)
	return tonumber(noctalia.getConfig(key)) or fallback
end

local function checkAlert(half)
	local low = intConfig("low_threshold", 20)
	local critical = intConfig("critical_threshold", 10)
	local level = half.level
	local id = half.device .. "-" .. half.label
	local previous = alertState[id] or "ok"
	local state = previous
	if level <= critical then
		state = "critical"
	elseif level <= low then
		state = "low"
	elseif level > low + HYSTERESIS then
		state = "ok"
	end
	alertState[id] = state
	-- Once per crossing; recovering from critical to low doesn't notify again
	if state == previous or state == "ok" or (previous == "critical" and state == "low") then
		return
	end
	if noctalia.getConfig("notify") == false then
		return
	end
	local subst = { name = half.name, half = half.label, level = tostring(level) }
	if state == "critical" then
		noctalia.notifyError(noctalia.tr("notify.critical_title", subst), noctalia.tr("notify.body", subst))
	else
		noctalia.notify(noctalia.tr("notify.low_title", subst), noctalia.tr("notify.body", subst))
	end
end

local function poll()
	if running then
		return
	end
	running = true
	lastRun = noctalia.nowMs()
	noctalia.runAsync({ "bash", noctalia.pluginDir() .. "/levels.sh" }, function(result)
		running = false
		local halves = {}
		for line in (result.stdout or ""):gmatch("[^\n]+") do
			local device, name, index, level = line:match("^([^\t]+)\t([^\t]*)\t(%d+)\t(%d+)$")
			if device ~= nil then
				local i = tonumber(index) + 1
				local half = {
					device = device,
					name = name,
					label = LABELS[i] or tostring(i),
					-- 0: the central half hasn't heard from this one yet
					level = tonumber(level) ~= 0 and tonumber(level) or nil,
				}
				if half.level ~= nil then
					checkAlert(half)
				end
				table.insert(halves, half)
			end
		end
		noctalia.state.set(SNAPSHOT_KEY, { halves = halves, updatedAt = noctalia.nowMs() })
	end, 15000)
end

-- A click on any widget asks for a fresh reading
noctalia.state.watch(COMMAND_KEY, function(cmd)
	if type(cmd) == "table" and cmd.action == "refresh" then
		poll()
	end
end)

-- `noctalia msg plugin blaise/zmk-battery:poller all refresh`
function onIpc(event, _payload)
	if event == "refresh" then
		poll()
	end
end

-- Tick every few seconds and read once the interval has passed, so a changed
-- poll_interval applies without a restart
noctalia.setUpdateInterval(5000)

function update()
	if noctalia.nowMs() - lastRun >= intConfig("poll_interval", 60) * 1000 then
		poll()
	end
end

poll()

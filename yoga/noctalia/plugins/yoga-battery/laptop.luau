--!nonstrict
-- The laptop's battery as a small gauge like the CPU/RAM ones: a battery glyph and a
-- vertical level bar, no number (the percentage and state are in the tooltip). The
-- glyph switches to the charging one while plugged in and charging; the bar goes
-- pink at low_threshold and red at critical_threshold unless it is charging.
-- Click is bound in the host config (opens the control center's Power tab).
-- Hidden on a machine without a battery. Drawn from the poller's "laptop" snapshot.

local SNAPSHOT_KEY = "laptop"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or {}

-- Same pixel arithmetic as the keyboard meter: the 12-unit track is 15px at the
-- bar's 1.25 scale, whole-pixel fills only.
local PX = 1.25
local function fillHeight(fraction)
	return math.round(12 * PX * fraction) / PX
end

local function render()
	local level = snapshot.level
	if level == nil then
		barWidget.setVisible(false)
		return
	end
	barWidget.setVisible(true)

	local status = snapshot.status or ""
	local charging = status == "Charging"
	local low = tonumber(noctalia.getConfig("low_threshold")) or 20
	local critical = tonumber(noctalia.getConfig("critical_threshold")) or 10
	local isCritical = not charging and level <= critical
	local isLow = not charging and level <= low
	local color = isCritical and "error" or (isLow and "primary" or "#ffffff")

	local fraction = math.clamp(level / 100, 0, 1)
	local bar = ui.column({
		width = 4,
		height = 12,
		justify = "end",
		fill = "#ffffff4d",
		radius = 2,
	}, fraction > 0 and {
		ui.box({
			width = 4,
			height = fillHeight(fraction),
			fill = color,
			radius = 2,
		}),
	} or {})

	local glyph = charging and "battery-charging" or "battery-4"
	barWidget.render(ui.row({ gap = 4, align = "center" }, {
		ui.glyph({ name = glyph, color = color }),
		bar,
	}))
	barWidget.setTooltip({
		{ key = "Battery", value = `{level}%` },
		{ key = "Status", value = status ~= "" and status or noctalia.tr("tooltip.unknown") },
	})
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

render()

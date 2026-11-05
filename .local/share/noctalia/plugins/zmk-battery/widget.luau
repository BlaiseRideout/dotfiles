--!nonstrict
-- A keyboard glyph followed by a vertical level bar per half, drawn from
-- the poller's snapshot. Pink at low_threshold, red at critical_threshold;
-- white above those thresholds, and an empty bar for a half
-- the central hasn't heard from. Hidden while no ZMK keyboard is connected. The
-- percentages are in the tooltip, or next to the bars with show_value. A click
-- reads the levels again.

local SNAPSHOT_KEY = "zmk"
local COMMAND_KEY = "zmk_command"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or { halves = {} }

local function render()
	local halves = snapshot.halves or {}
	if #halves == 0 then
		barWidget.setVisible(false)
		return
	end
	barWidget.setVisible(true)

	local low = tonumber(noctalia.getConfig("low_threshold")) or 20
	local critical = tonumber(noctalia.getConfig("critical_threshold")) or 10
	local anyLow = false
	local anyCritical = false
	local leftBars, rightBars, values, rows = {}, {}, {}, {}
	for _, half in ipairs(halves) do
		local level = half.level
		local isLow = level ~= nil and level <= low
		local isCritical = level ~= nil and level <= critical
		anyLow = anyLow or isLow
		anyCritical = anyCritical or isCritical
		local levelFraction = level ~= nil and math.clamp(level / 100, 0, 1) or 0
		local bars = half.label == "R" and rightBars or leftBars
		table.insert(bars, ui.column({
			key = half.device .. half.label,
			width = 4,
			height = 12,
			justify = "end",
			fill = level ~= nil and "#ffffff4d" or "error/0.3",
			radius = 2,
		}, levelFraction > 0 and {
			ui.box({
				width = 4,
				height = 12 * levelFraction,
				fill = isCritical and "error" or (isLow and "primary" or "#ffffff"),
				radius = 2,
			}),
		} or {}))
		local text = level ~= nil and `{level}%` or "--"
		table.insert(values, text)
		local value = level ~= nil and text or noctalia.tr("tooltip.unknown")
		table.insert(rows, { key = `{half.name} ({half.label})`, value = value })
	end

	local color = anyCritical and "error" or (anyLow and "primary" or "#ffffff")
	local bars = {}
	for _, bar in ipairs(leftBars) do
		table.insert(bars, bar)
	end
	for _, bar in ipairs(rightBars) do
		table.insert(bars, bar)
	end
	local children = {
		ui.glyph({ name = "keyboard", color = color }),
		ui.row({ gap = 2, align = "center" }, bars),
	}
	if noctalia.getConfig("show_value") then
		table.insert(children, ui.label({ text = table.concat(values, " "), color = color }))
	end

	barWidget.render(ui.row({ gap = 4, align = "center" }, children))
	barWidget.setTooltip(rows)
end

function onClick()
	noctalia.state.set(COMMAND_KEY, { action = "refresh", at = noctalia.nowMs() })
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

render()

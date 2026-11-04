--!nonstrict
-- A keyboard glyph and one thin level bar per half (left above right), drawn from
-- the poller's snapshot. Red at low_threshold or below; an empty bar for a half
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
	local anyLow = false
	local bars, values, rows = {}, {}, {}
	for _, half in ipairs(halves) do
		local level = half.level
		local isLow = level ~= nil and level <= low
		anyLow = anyLow or isLow
		table.insert(bars, ui.progress({
			key = half.device .. half.label,
			progress = level ~= nil and level / 100 or 0,
			fill = isLow and "error" or "primary",
			track = level ~= nil and "on_surface_variant/0.2" or "error/0.3",
			width = 18,
			height = 3,
			radius = 1.5,
		}))
		local text = level ~= nil and `{level}%` or "--"
		table.insert(values, text)
		local value = level ~= nil and text or noctalia.tr("tooltip.unknown")
		table.insert(rows, { key = `{half.name} ({half.label})`, value = value })
	end

	local children = {
		ui.glyph({ name = "keyboard", size = 14, color = anyLow and "error" or nil }),
		ui.column({ gap = 2, justify = "center" }, bars),
	}
	if noctalia.getConfig("show_value") then
		table.insert(children, ui.label({ text = table.concat(values, " "), color = anyLow and "error" or nil }))
	end

	local container = barWidget.isVertical() and ui.column or ui.row
	barWidget.render(container({ gap = 5, align = "center" }, children))
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

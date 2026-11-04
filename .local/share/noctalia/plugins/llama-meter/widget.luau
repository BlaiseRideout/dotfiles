--!nonstrict
-- A robot glyph and a small level bar for the token rate (full at max_rate t/s),
-- drawn from the poller's snapshot. Bright while generating, dimmer for the last
-- request's rate, dimmest for the lifetime average; an empty bar while reading the
-- prompt. Hidden while no model is loaded. The numbers are in the tooltip, or next
-- to the bar with show_value.

local SNAPSHOT_KEY = "llama"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or { visible = false }

local FILL = {
	generating = "primary",
	prefill = "primary",
	last = "primary/0.7",
	idle = "on_surface_variant/0.6",
}

local function render()
	if not snapshot.visible then
		barWidget.setVisible(false)
		return
	end
	barWidget.setVisible(true)

	local maxRate = tonumber(noctalia.getConfig("max_rate")) or 100
	local rate = snapshot.rate
	local level = 0
	if type(rate) == "number" and snapshot.state ~= "prefill" then
		level = math.clamp(rate / maxRate, 0, 1)
	end
	local busy = snapshot.state == "generating" or snapshot.state == "prefill"

	local children = {
		ui.glyph({ name = "robot", size = 14, color = busy and "primary" or nil }),
		ui.progress({
			progress = level,
			fill = FILL[snapshot.state] or "primary",
			track = "on_surface_variant/0.2",
			width = 22,
			height = 5,
			radius = 2.5,
		}),
	}
	if noctalia.getConfig("show_value") then
		-- Whole tokens/s; three dots while there's no number yet
		local text = (type(rate) == "number" and snapshot.state ~= "prefill") and `{math.floor(rate + 0.5)} t/s`
			or "··· t/s"
		table.insert(children, ui.label({ text = text }))
	end

	local container = barWidget.isVertical() and ui.column or ui.row
	barWidget.render(container({ gap = 5, align = "center" }, children))
	barWidget.setTooltip(snapshot.rows)
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

render()

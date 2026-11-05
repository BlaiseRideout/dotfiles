--!nonstrict
-- A robot glyph and a vertical token-rate bar, full at max_rate t/s.
-- Empty unless generating; historical rates remain in the tooltip.

local SNAPSHOT_KEY = "llama"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or { visible = false }

local FILL = {
	generating = "primary",
	prefill = "primary",
	last = "primary/0.7",
	idle = "on_surface_variant/0.6",
}

-- The bar draws at 1.25 physical pixels per layout unit (bar scale 1.25 x
-- widget scale 1.0, see meters.toml), so the 12-unit track is 15px. A fill of
-- any other height lands on a fractional pixel and pokes out past the track's
-- bottom edge; whole-pixel fills match the built-in sysmon gauges.
local PX = 1.25
local function fillHeight(fraction)
	return math.round(12 * PX * fraction) / PX
end

local function render()
	if not snapshot.visible then
		barWidget.setVisible(false)
		return
	end
	barWidget.setVisible(true)

	local maxRate = tonumber(noctalia.getConfig("max_rate")) or 100
	local rate = snapshot.rate
	local level = 0
	if type(rate) == "number" and snapshot.state == "generating" then
		level = math.clamp(rate / maxRate, 0, 1)
	end
	local busy = snapshot.state == "generating" or snapshot.state == "prefill"

	local children = {
		ui.glyph({ name = "robot", color = busy and "primary" or nil }),
		ui.column({
			width = 4,
			height = 12,
			justify = "end",
			fill = "#ffffff4d",
			radius = 2,
		}, level > 0 and {
			ui.box({ width = 4, height = fillHeight(level), fill = FILL[snapshot.state] or "primary", radius = 2 }),
		} or {}),
	}
	if noctalia.getConfig("show_value") then
		-- Whole tokens/s; three dots while there's no number yet
		local text = (type(rate) == "number" and snapshot.state ~= "prefill") and `{math.floor(rate + 0.5)} t/s`
			or "··· t/s"
		table.insert(children, ui.label({ text = text }))
	end

	local container = barWidget.isVertical() and ui.column or ui.row
	barWidget.render(container({ gap = 4, align = "center" }, children))
	barWidget.setTooltip(snapshot.rows)
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

render()

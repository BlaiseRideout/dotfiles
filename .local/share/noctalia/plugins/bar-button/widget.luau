--!nonstrict
-- A glyph and/or a bold label, sized by settings (see plugin.toml). The label is
-- centred on its ink (the letters themselves, not the line box) so it sits on the
-- same centre line as the glyphs around it. Clicks are bound in bar.toml.

local glyph = noctalia.getConfig("glyph")
local label = noctalia.getConfig("label")
local tooltip = noctalia.getConfig("tooltip")

local children = {}
if type(glyph) == "string" and glyph ~= "" then
	table.insert(
		children,
		ui.glyph({ name = glyph, size = tonumber(noctalia.getConfig("glyph_size")) or 16 })
	)
end
if type(label) == "string" and label ~= "" then
	table.insert(
		children,
		ui.label({
			text = label,
			fontSize = tonumber(noctalia.getConfig("font_size")) or 14,
			fontWeight = "bold",
			baseline = "inkCentered",
		})
	)
end

local container = barWidget.isVertical() and ui.column or ui.row
barWidget.render(container({ gap = 4, align = "center" }, children))
if type(tooltip) == "string" and tooltip ~= "" then
	barWidget.setTooltip(tooltip)
end

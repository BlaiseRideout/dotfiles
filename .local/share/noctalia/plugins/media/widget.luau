--!nonstrict
-- A music note and "title - artist" for the active MPRIS player (via playerctl), or a
-- crossed-out note on its own when no player is running. Read once a second. Clicks are
-- bound in bar.toml ([widget.<name>.actions]).

local POLL_MS = 1000
local SEPARATOR = "\t"

local running = false
local shown = nil -- the last text drawn, to skip identical redraws

local function truncate(text, max)
	-- Cut on characters, not bytes, so a multi-byte title isn't split mid-character
	if utf8.len(text) == nil or utf8.len(text) <= max then
		return text
	end
	return text:sub(1, (utf8.offset(text, max) or max + 1) - 1) .. "…"
end

local function render(status, title, artist)
	local key = `{status}|{title}|{artist}`
	if key == shown then
		return
	end
	shown = key

	local present = status ~= nil
	local children = { ui.glyph({ name = present and "music" or "music-off" }) }
	local rows = nil
	if present then
		local text = title
		if artist ~= "" then
			text = title ~= "" and `{title} - {artist}` or artist
		end
		if text ~= "" then
			local max = tonumber(noctalia.getConfig("max_chars")) or 40
			table.insert(children, ui.label({ text = truncate(text, max) }))
		end
		rows = {
			{ key = noctalia.tr("tooltip.title"), value = title ~= "" and title or "-" },
			{ key = noctalia.tr("tooltip.artist"), value = artist ~= "" and artist or "-" },
			{ key = noctalia.tr("tooltip.status"), value = noctalia.tr("tooltip." .. status) },
		}
	end

	local container = barWidget.isVertical() and ui.column or ui.row
	barWidget.render(container({ gap = 4, align = "center" }, children))
	barWidget.setTooltip(rows or noctalia.tr("tooltip.nothing"))
end

local function poll()
	if running then
		return
	end
	running = true
	local launched = noctalia.runAsync({
		"playerctl",
		"metadata",
		"--format",
		`\{\{status\}\}{SEPARATOR}\{\{title\}\}{SEPARATOR}\{\{artist\}\}`,
	}, function(result)
		running = false
		local line = (result.stdout or ""):match("^[^\n]*")
		if result.exitCode == 0 and line ~= nil and line ~= "" then
			local status, title, artist = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
			render(status, title or "", artist or "")
		else
			-- Exit 1 with no output: "No players found"
			render(nil, "", "")
		end
	end)
	if not launched then
		running = false
	end
end

noctalia.setUpdateInterval(POLL_MS)

function update()
	poll()
end

render(nil, "", "")
poll()

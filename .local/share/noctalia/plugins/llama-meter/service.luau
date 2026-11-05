--!nonstrict
-- Polls the llama.cpp router once a second and publishes a snapshot under "llama" for
-- the bar widgets. Same logic as ~/.config/waybar/llama.sh. The router keeps /slots
-- and /metrics per model, so every loaded model is sampled and summed.

local SNAPSHOT_KEY = "llama"
local FAILS_BEFORE_HIDING = 3 -- failed polls in a row before the meter disappears
local STALE_MS = 5000 -- noctalia.http has no timeout: give up on a poll after this
local DOWN_POLL_MS = 10000 -- once hidden by failures, retry this often (each failure logs a warning)

-- Poll bookkeeping
local generation = 0 -- bumped per poll; callbacks from an abandoned poll are dropped
local inFlight = false
local startedAt = 0
local fails = 0
local lastSnapshot = nil

-- Rate state, as in llama.sh
local prevN = {} -- "model|slot" -> n_decoded at the previous poll
local prevT = noctalia.nowMs()
local active = false -- a request was running at the previous poll
local lastRate = nil -- rate of the last finished request
local lastAt = 0
local idleTok, idleSec = 0, 0 -- counters when last seen idle

local function baseUrl()
	local url = noctalia.getConfig("base_url") or "http://127.0.0.1:9931"
	return (url:gsub("/+$", ""))
end

-- The router's API key is read from the file `llama-key` manages (never stored in the plugin or the repo), so
-- every request carries it; re-read on each poll so a rotated key is picked up.
local function authHeaders()
	local path = noctalia.getConfig("api_key_file")
	if path == nil or path == "" then
		local home = noctalia.getenv("HOME")
		if home == nil or home == "" then
			return nil
		end
		path = home .. "/.local/state/llama-serve/api-key"
	end
	local ok, body = pcall(noctalia.readFile, path)
	if not ok or type(body) ~= "string" then
		return nil
	end
	local key = body:gsub("%s+", "")
	if key == "" then
		return nil
	end
	return { Authorization = "Bearer " .. key }
end

local function get(url, callback)
	noctalia.http({ url = url, headers = authHeaders() }, callback)
end

local function publish(snapshot)
	noctalia.state.set(SNAPSHOT_KEY, snapshot)
end

local function hide()
	lastSnapshot = nil
	publish({ visible = false })
end

local function round1(x)
	return math.floor(x * 10 + 0.5) / 10
end

-- Prometheus text -> the four counters llama.sh reads
local function parseMetrics(body)
	local m = { tok = 0, sec = 0, ptok = 0, psec = 0 }
	for line in (body or ""):gmatch("[^\n]+") do
		local name, value = line:match("^(%S+)%s+(%S+)")
		value = tonumber(value)
		if value ~= nil then
			if name == "llamacpp:tokens_predicted_total" then
				m.tok = value
			elseif name == "llamacpp:tokens_predicted_seconds_total" then
				m.sec = value
			elseif name == "llamacpp:prompt_tokens_total" then
				m.ptok = value
			elseif name == "llamacpp:prompt_seconds_total" then
				m.psec = value
			end
		end
	end
	return m
end

-- All responses for one poll are in: work out the rates and publish
local function compute(loaded, slots, metrics)
	local now = noctalia.nowMs()
	local liveTok, busy, prefill = 0, 0, 0
	local cur = {}
	for _, model in ipairs(loaded) do
		for _, slot in ipairs(slots[model] or {}) do
			if slot.is_processing then
				busy += 1
				local nt = slot.next_token
				local n = 0
				if type(nt) == "table" and type(nt[1]) == "table" then
					n = tonumber(nt[1].n_decoded) or 0
				end
				local k = model .. "|" .. tostring(slot.id)
				cur[k] = n
				if prevN[k] ~= nil and n >= prevN[k] then
					liveTok += n - prevN[k]
				end
				if n == 0 then
					prefill += 1
				end
			end
		end
	end
	prevN = cur

	local tokTotal, secTotal, ptok, psec = 0, 0, 0, 0
	for _, model in ipairs(loaded) do
		local m = metrics[model]
		if m then
			tokTotal += m.tok
			secTotal += m.sec
			ptok += m.ptok
			psec += m.psec
		end
	end

	local dt = (now - prevT) / 1000
	if dt <= 0.05 then
		dt = 1
	end
	prevT = now

	local avg = secTotal > 0 and round1(tokTotal / secTotal) or nil
	local pavg = psec > 0 and round1(ptok / psec) or nil

	local state, rate, nowLine
	if busy > 0 then
		active = true
		if liveTok > 0 then
			rate = round1(liveTok / dt)
			state = "generating"
			nowLine = `{rate} t/s`
		else
			state = "prefill"
			nowLine = noctalia.tr("tooltip.prefill")
		end
	else
		if active then
			-- A request just finished: its rate is the counters' delta since we last saw it idle
			if secTotal - idleSec > 0 and tokTotal - idleTok > 0 then
				lastRate = round1((tokTotal - idleTok) / (secTotal - idleSec))
			end
			lastAt = now
			active = false
		end
		idleTok, idleSec = tokTotal, secTotal
		nowLine = noctalia.tr("tooltip.idle")
		local hold = (tonumber(noctalia.getConfig("hold_seconds")) or 15) * 1000
		if lastRate ~= nil and now - lastAt < hold then
			state, rate = "last", lastRate
		else
			state, rate = "idle", avg
		end
	end

	local rows = {
		{ key = noctalia.tr("tooltip.models"), value = table.concat(loaded, ", ") },
		{ key = noctalia.tr("tooltip.now"), value = nowLine },
	}
	if lastRate ~= nil then
		table.insert(rows, { key = noctalia.tr("tooltip.last"), value = `{lastRate} t/s` })
	end
	if avg ~= nil then
		table.insert(rows, { key = noctalia.tr("tooltip.average"), value = `{avg} t/s` })
	end
	if pavg ~= nil then
		table.insert(rows, { key = noctalia.tr("tooltip.prompt"), value = `{pavg} t/s` })
	end
	table.insert(rows, { key = noctalia.tr("tooltip.busy"), value = tostring(busy) })

	lastSnapshot = { visible = true, state = state, rate = rate, rows = rows }
	publish(lastSnapshot)
end

local function failed()
	-- A busy server can miss a poll; keep the last reading up on a brief failure, since
	-- hiding the meter shifts everything beside it
	fails += 1
	prevN = {}
	active = false
	if fails <= FAILS_BEFORE_HIDING and lastSnapshot ~= nil then
		publish(lastSnapshot)
	else
		hide()
	end
end

local function poll()
	local now = noctalia.nowMs()
	if inFlight and now - startedAt < STALE_MS then
		return
	end
	if fails > FAILS_BEFORE_HIDING and now - startedAt < DOWN_POLL_MS then
		return
	end
	generation += 1
	local mine = generation
	inFlight = true
	startedAt = now
	local base = baseUrl()

	get(base .. "/models", function(res)
		if mine ~= generation then
			return
		end
		local data = res.ok and res.status == 200 and noctalia.json.decode(res.body or "") or nil
		if type(data) ~= "table" or type(data.data) ~= "table" then
			inFlight = false
			failed()
			return
		end
		fails = 0

		local loaded = {}
		for _, model in ipairs(data.data) do
			if type(model.status) == "table" and model.status.value == "loaded" then
				table.insert(loaded, model.id)
			end
		end
		if #loaded == 0 then
			inFlight = false
			prevN = {}
			active = false
			hide()
			return
		end

		-- /slots and /metrics for each loaded model; compute once all have answered
		local slots, metrics = {}, {}
		local pending = #loaded * 2
		local function done()
			pending -= 1
			if pending == 0 and mine == generation then
				inFlight = false
				compute(loaded, slots, metrics)
			end
		end
		for _, model in ipairs(loaded) do
			local q = `?model={noctalia.string.urlEncode(model)}&autoload=false`
			get(base .. "/slots" .. q, function(r)
				local decoded = r.ok and r.status == 200 and noctalia.json.decode(r.body or "") or nil
				slots[model] = type(decoded) == "table" and decoded or {}
				done()
			end)
			get(base .. "/metrics" .. q, function(r)
				metrics[model] = parseMetrics(r.ok and r.status == 200 and r.body or "")
				done()
			end)
		end
	end)
end

-- `noctalia msg plugin blaise/llama-meter:poller all dump` logs the current snapshot
function onIpc(event, _payload)
	if event == "dump" then
		noctalia.log("llama-meter: " .. (noctalia.json.encode(lastSnapshot or { visible = false }) or "?"))
	end
end

noctalia.setUpdateInterval(1000)

function update()
	poll()
end

poll()

--- Read-only comparison of the player-built world. These digests contain no entity ids.
-- A fresh snapshot is required for every category: a failed read never reuses old evidence.
local actions = require("/mp_probe/actions.lua")
local fingerprint = { VERSION = 1, QUANTUM = 0.001, MAX_RECORDS = 100000,
	MAX_ITEMS = 65536, MAX_DEPTH = 24,
	FIELDS = { construction = "hcon", edge = "hedge", line = "hline", vehicle = "hveh" } }

local function finite(n)
	assert(type(n) == "number" and n == n and math.abs(n) < math.huge, "non-finite fingerprint number")
	return n
end

local function rounded(n)
	n = finite(n)
	if n == 0 then return 0 end -- negative zero has the same geometry
	-- Integers, including modular slot keys and random seeds, retain their exact value.
	if n == math.floor(n) then return n end
	local q = fingerprint.QUANTUM
	local v = n < 0 and math.ceil(n / q - 0.5) or math.floor(n / q + 0.5)
	return v == 0 and 0 or v * q
end

--- Canonical data text; bounded per record rather than across an entire large world.
function fingerprint.canonical(value)
	local seen, items = {}, 0
	local function put(v, depth)
		items = items + 1
		assert(items <= fingerprint.MAX_ITEMS and depth <= fingerprint.MAX_DEPTH, "fingerprint record limit")
		local t = type(v)
		if t == "boolean" then return v and "y" or "n" end
		if t == "number" then return "d" .. string.format("%.17g", rounded(v)) .. ";" end
		if t == "string" then return "s" .. #v .. ":" .. v end
		assert(t == "table" and not seen[v], "unsupported or cyclic fingerprint value")
		seen[v] = true
		local keys = {}
		for k in pairs(v) do
			assert(type(k) == "number" or type(k) == "string", "unsupported fingerprint key")
			if type(k) == "number" then finite(k) end
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then return type(a) < type(b) end
			return a < b
		end)
		local parts = { "t" .. #keys .. ":" }
		for _, k in ipairs(keys) do
			-- Numeric keys are identities, not measured values, and must not be rounded.
			parts[#parts + 1] = type(k) == "number" and ("d" .. string.format("%.17g", k) .. ";") or put(k, depth + 1)
			parts[#parts + 1] = put(v[k], depth + 1)
		end
		seen[v] = nil
		return table.concat(parts)
	end
	return put(value, 0)
end

--- Two independent modular accumulators. Products stay below 2^53 on Lua number builds.
local function hash(text)
	local a, b = 2166136261, 2246822519
	for i = 1, #text do
		local c = text:byte(i)
		a = (a * 131 + c) % 4294967291
		b = (b * 137 + c) % 4294967279
	end
	return string.format("%08x%08x", a, b)
end

local function sorted(values)
	table.sort(values, function(a, b) return fingerprint.canonical(a) < fingerprint.canonical(b) end)
	return values
end

local function negate(v)
	return { x = -finite(v.x), y = -finite(v.y), z = -finite(v.z) }
end

local function vector(v)
	assert(type(v) == "table", "world vector unreadable")
	finite(v.x); finite(v.y); finite(v.z)
	return v
end

local function matrix(m)
	assert(type(m) == "table" and #m == 4, "world transformation unreadable")
	for _, col in ipairs(m) do vector(col); finite(col.w) end
	return m
end

local function edge(ref)
	assert(ref.kind == "edge" and type(ref.roadTemplate) == "string" and type(ref.roadStyle) == "string",
		"edge resource unreadable")
	vector(ref.position0); vector(ref.position1); vector(ref.tangent0); vector(ref.tangent1)
	local forward = { position0 = ref.position0, position1 = ref.position1,
		tangent0 = ref.tangent0, tangent1 = ref.tangent1,
		roadTemplate = ref.roadTemplate, roadStyle = ref.roadStyle }
	local reverse = { position0 = ref.position1, position1 = ref.position0,
		tangent0 = negate(ref.tangent1), tangent1 = negate(ref.tangent0),
		roadTemplate = ref.roadTemplate, roadStyle = ref.roadStyle }
	if fingerprint.canonical(reverse) < fingerprint.canonical(forward) then return reverse, true end
	return forward, false
end

local function reference(ref)
	assert(type(ref) == "table", "missing world reference")
	if ref.kind == "construction" then
		assert(type(ref.fileName) == "string" and type(ref.transf) == "table", "construction reference unreadable")
		return { kind = ref.kind, fileName = ref.fileName, transf = matrix(ref.transf) }
	elseif ref.kind == "station" or ref.kind == "depot" then
		assert(type(ref.index) == "number" and ref.index >= 1 and ref.index == math.floor(ref.index), "child index unreadable")
		return { kind = ref.kind, parent = reference(ref.parent), index = ref.index }
	elseif ref.kind == "street_station" then
		assert(type(ref.name) == "string", "street station name unreadable")
		return { kind = ref.kind, position = vector(ref.position), name = ref.name }
	elseif ref.kind == "line" then
		assert(type(ref.name) == "string", "line reference unreadable")
		return { kind = ref.kind, name = ref.name }
	end
	error("unsupported world reference " .. tostring(ref.kind), 0)
end

local function stop(entry)
	local target = assert(entry.target, "missing line stop target")
	assert(type(target.stations) == "table" and type(target.station) == "number"
		and target.station == math.floor(target.station), "line stop station unreadable")
	finite(entry.terminal)
	assert(type(entry.stopConfig) == "table" and type(entry.alternativeTerminals) == "table"
		and type(entry.waypoints) == "table", "line stop configuration unreadable")
	local stations, selected = {}, nil
	for i, ref in ipairs(target.stations) do stations[i] = reference(ref) end
	if #stations == 0 then
		assert(target.station == -1 and entry.terminal == -1, "unreadable deleted line stop")
		selected = { deleted = true }
	else
		selected = assert(stations[target.station + 1], "invalid line station index")
	end
	local alternatives = {}
	for i, alt in ipairs(entry.alternativeTerminals or {}) do
		finite(alt.terminal)
		alternatives[i] = { station = assert(stations[alt.station + 1], "invalid alternative station index"),
			terminal = alt.terminal }
	end
	local waypoints = {}
	for i, w in ipairs(entry.waypoints or {}) do
		if w.edge then
			finite(w.index); finite(w.param)
			local e, reversed = edge(w.edge)
			waypoints[i] = { edge = e, index = w.index, param = reversed and (1 - finite(w.param)) or w.param, tag = w.tag }
		else waypoints[i] = { pos = vector(w.pos), tag = w.tag } end
	end
	return { station = selected, group = sorted(stations), terminal = entry.terminal,
		loadMode = entry.loadMode, minWaitingTime = entry.minWaitingTime, maxWaitingTime = entry.maxWaitingTime,
		maxAdditionalWaitingTime = entry.maxAdditionalWaitingTime, stopConfig = entry.stopConfig,
		alternativeTerminals = sorted(alternatives), waypoints = waypoints }
end

--- Normalize the persistent fields captured by actions.lua; never include movement or local ids.
function fingerprint.normalize(kind, record)
	if kind == "construction" then
		assert(type(record.data.fileName) == "string" and type(record.data.transf) == "table"
			and type(record.data.params) == "table" and type(record.data.name) == "string", "construction unreadable")
		return { fileName = record.data.fileName, transf = matrix(record.data.transf), params = record.data.params, name = record.data.name }
	elseif kind == "edge" then
		return edge(record.ref)
	elseif kind == "line" then
		assert(type(record.name) == "string" and type(record.color) == "table"
			and type(record.data.stops) == "table", "line unreadable")
		local stops = {}
		for i, entry in ipairs(record.data.stops) do stops[i] = stop(entry) end
		return { name = record.name, color = vector(record.color), stops = stops,
			customFilters = record.data.customFilters, reservationPriority = record.data.reservationPriority }
	elseif kind == "vehicle" then
		assert(type(record.name) == "string" and type(record.config) == "table"
			and type(record.userStopped) == "boolean" and type(record.autoDeparture) == "boolean", "vehicle unreadable")
		return { name = record.name, config = record.config, userStopped = record.userStopped,
			autoDeparture = record.autoDeparture, line = record.line and reference(record.line) or nil }
	end
	error("unsupported fingerprint category", 0)
end

--- A sorted multiset: ids and enumeration order do not matter, but duplicate records still count.
function fingerprint.digest(kind, records)
	local values = {}
	for _, record in pairs(records) do
		assert(#values < fingerprint.MAX_RECORDS, "fingerprint world limit")
		values[#values + 1] = hash(fingerprint.canonical(fingerprint.normalize(kind, record)))
	end
	table.sort(values)
	return "h" .. fingerprint.VERSION .. "_" .. hash(kind .. ":" .. #values .. ":" .. table.concat(values, ":"))
end

local function short(path)
	return (tostring(path):match("([^/]+)$")) or tostring(path)
end

local function v3(v)
	return string.format("%.3f,%.3f,%.3f", rounded(v.x), rounded(v.y), rounded(v.z))
end

local function part(value)
	return hash(fingerprint.canonical(value)):sub(1, 8)
end

--- One readable line per normalized record, enough to see which of its fields two games disagree
-- on; fields too long for a line appear as the first 8 digits of their own hash.
function fingerprint.describe(kind, n)
	if kind == "construction" then
		local m = n.transf
		return string.format("%s at %s name %s params %s turn %s", short(n.fileName), v3(m[4]), n.name,
			part(n.params), part({ m[1], m[2], m[3] }))
	elseif kind == "edge" then
		return string.format("%s/%s %s > %s tangents %s / %s", short(n.roadTemplate), short(n.roadStyle),
			v3(n.position0), v3(n.position1), v3(n.tangent0), v3(n.tangent1))
	elseif kind == "line" then
		return string.format("%s, %d stops %s, color %s, rest %s", n.name, #n.stops, part(n.stops), v3(n.color),
			part({ n.customFilters, n.reservationPriority }))
	elseif kind == "vehicle" then
		return string.format("%s on %s, config %s, stopped %s, auto %s", n.name, n.line and tostring(n.line.name) or "-",
			part(n.config), tostring(n.userStopped), tostring(n.autoDeparture))
	end
	return kind
end

--- The records of one category as { h = record hash (as in fingerprint.digest), d = description },
-- sorted by hash. For finding out which records two games disagree on (main.world_send).
function fingerprint.list(env, kind)
	local out = {}
	local records = actions.snapshot(env, kind)
	for _, record in pairs(records) do
		local ok, n = pcall(fingerprint.normalize, kind, record)
		if ok then
			local ok_d, d = pcall(fingerprint.describe, kind, n)
			out[#out + 1] = { h = hash(fingerprint.canonical(n)), d = ok_d and d or ("description unreadable: " .. tostring(d):sub(1, 60)) }
		else
			out[#out + 1] = { h = "unreadable", d = tostring(n):sub(1, 80) }
		end
	end
	table.sort(out, function(a, b) return a.h < b.h end)
	return out
end

function fingerprint.values(env)
	local out, failed = {}, {}
	local kinds = {}
	-- v32: the account (loan) is an action kind, but money and loan have their own checks.
	for _, kind in ipairs(actions.KINDS) do if fingerprint.FIELDS[kind] then kinds[#kinds + 1] = kind end end
	for _, kind in ipairs(kinds) do
		local field = fingerprint.FIELDS[kind]
		local ok, digest = pcall(function()
			local engine, ct, read_failed = env.api.engine, env.api.type.ComponentType, false
			-- A local proxy observes even errors swallowed by capture's optional-name fallback.
			-- It does not replace or mutate any engine function, nor retain earlier records.
			local audited = setmetatable({ getComponent = function(id, component)
				local read_ok, value = pcall(function()
					local v = engine.getComponent(id, component)
					if v ~= nil and component == ct.NAME then
						assert(type(v.name) == "string", "unreadable entity name")
					elseif v ~= nil and component == ct.CONSTRUCTION then
						local _ = v.params_native -- observing an unreadable native param table is not a fallback
					end
					return v
				end)
				if not read_ok then read_failed = true; error(value, 0) end
				return value
			end }, { __index = engine })
			local api = setmetatable({ engine = audited }, { __index = env.api })
			local audited_env = setmetatable({ api = api }, { __index = env })
			local records, unreadable = actions.snapshot(audited_env, kind) -- deliberately no previous snapshot
			assert(unreadable == 0 and not read_failed, "unreadable world records")
			return fingerprint.digest(kind, records)
		end)
		if ok then out[field] = digest else failed[#failed + 1] = field end
	end
	return out, failed
end

return fingerprint

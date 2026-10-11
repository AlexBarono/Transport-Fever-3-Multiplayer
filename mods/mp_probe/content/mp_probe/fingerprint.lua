--- Read-only comparison of the player-built world. These digests contain no entity ids.
-- A fresh snapshot is required for every category: a failed read never reuses old evidence.
local actions = require("/mp_probe/actions.lua")
local build = require("/mp_probe/build.lua")
local fingerprint = { VERSION = 1, QUANTUM = 0.001, MAX_RECORDS = 100000,
	MAX_ITEMS = 65536, MAX_DEPTH = 24,
	FIELDS = { construction = "hcon", edge = "hedge", line = "hline", vehicle = "hveh",
		position = "hpos", cargo = "hcargo", town = "htown" } }
local MOVING = { position = true, cargo = true, town = true }

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
		local out = { kind = ref.kind, parent = reference(ref.parent) }
		if ref.kind == "station" and ref.tag ~= nil then
			finite(ref.tag); assert(ref.tag == math.floor(ref.tag), "station tag unreadable")
			out.tag = ref.tag -- unique within this construction, stable across child reordering
		else out.index = ref.index end
		return out
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
	local function terminal(index, tag)
		finite(index)
		if tag == nil then return index end
		finite(tag); assert(tag == math.floor(tag), "terminal tag unreadable")
		return { tag = tag } -- unique within the actual station, independent of terminal order
	end
	for i, alt in ipairs(entry.alternativeTerminals or {}) do
		finite(alt.terminal)
		alternatives[i] = { station = assert(stations[alt.station + 1], "invalid alternative station index"),
			terminal = terminal(alt.terminal, alt.terminalTag) }
	end
	local waypoints = {}
	for i, w in ipairs(entry.waypoints or {}) do
		if w.edge then
			finite(w.index); finite(w.param)
			local e, reversed = edge(w.edge)
			waypoints[i] = { edge = e, index = w.index, param = reversed and (1 - finite(w.param)) or w.param, tag = w.tag }
		else waypoints[i] = { pos = vector(w.pos), tag = w.tag } end
	end
	return { station = selected, group = sorted(stations), terminal = terminal(entry.terminal, entry.terminalTag),
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
	elseif MOVING[kind] then
		return record -- already copied and validated by the same-tick capture below
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
	return "h" .. (MOVING[kind] and 2 or fingerprint.VERSION) .. "_" .. hash(kind .. ":" .. #values .. ":" .. table.concat(values, ":"))
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
	elseif kind == "position" then
		if n.depot then return n.vehicle.name .. " in depot " .. part(n.depot) end
		return string.format("%s on %s at %s speed %.1f", n.vehicle.name, n.vehicle.line or "-", v3(n.position), n.speed)
	elseif kind == "cargo" then
		if n.scope == "coverage" then return "cargo coverage: " .. n.method end
		if n.scope == "vehicle" then return n.vehicle.name .. " cargo " .. part(n.counts) end
		return n.cargoType .. " source " .. part(n.source) .. " target " .. part(n.target)
	elseif kind == "town" then
		return string.format("%s at %s population/capacity %s sizes %s stocks %s", n.name, v3(n.position),
			part(n.usage), part(n.sizeFactors), part(n.stock))
	end
	return kind
end

--- The records of one category as { h = record hash (as in fingerprint.digest), d = description },
-- sorted by hash. For finding out which records two games disagree on (main.world_send).
function fingerprint.list(env, kind)
	assert(not MOVING[kind], "moving-world details require the original checkpoint snapshot")
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

-- The engine has no paged entity enumeration or historical component reads. Capture a bounded
-- immutable sample on one simulation tick, then hash that data over later updates. A category
-- exceeding any limit stays unknown; partial sets are never published as a world digest.
-- v33: budgets allow a medium map (about 200 vehicles, 2000 cargo items) at most one short hitch
-- per checkpoint (once a minute of game time); 'world scan' in the log shows the real times.
fingerprint.CAPTURE_MAX_MS = 80
fingerprint.CATEGORY_MAX_MS = 30
fingerprint.CAPTURE_MAX_CALLS = 16000
fingerprint.CATEGORY_MAX_CALLS = 6000
fingerprint.STATIC_MAX_RECORDS = 1024
fingerprint.VEHICLE_MAX_RECORDS = 2048
fingerprint.CARGO_MAX_RECORDS = 4096
fingerprint.TOWN_MAX_RECORDS = 256
fingerprint.HASH_MAX_MS = 4
fingerprint.HASH_BYTES_PER_STEP = 65536
fingerprint.HASH_RECORDS_PER_STEP = 256
fingerprint.RECORD_MAX_ITEMS = 2048
fingerprint.RECORD_MAX_BYTES = 65536
fingerprint.DETAIL_MAX_RECORDS = 256
fingerprint.POSITION_QUANTUM = 0.1

local function clock_for(env)
	local fn = env.os and env.os.clock
	if not fn and os then fn = os.clock end
	if fn then
		local ok, n = pcall(fn)
		if ok and type(n) == "number" and n == n then return fn end
	end
end

local function measured(fn)
	return fn and fn() * 1000 or 0
end

local function integer(n)
	finite(n)
	assert(n == math.floor(n) and math.abs(n) <= 9007199254740991, "integer world value unreadable")
	return n
end

local function position(v)
	local q = fingerprint.POSITION_QUANTUM
	local function bin(n) n = finite(n); return math.floor(n / q + 0.5) * q end
	return { x = bin(v.x), y = bin(v.y), z = bin(v.z) }
end

local function bounded_plain(value)
	local items, bytes, active = 0, 0, {}
	local function visit(v, depth)
		items = items + 1
		assert(items <= fingerprint.RECORD_MAX_ITEMS and depth <= fingerprint.MAX_DEPTH, "checkpoint record limit")
		local t = type(v)
		bytes = bytes + (t == "string" and #v or 24)
		assert(bytes <= fingerprint.RECORD_MAX_BYTES, "checkpoint record byte limit")
		if t == "number" then finite(v); return end
		if t == "string" then return end
		if t == "boolean" then return end
		assert(t == "table" and not active[v], "checkpoint value unreadable")
		active[v] = true
		for k, x in pairs(v) do visit(k, depth + 1); visit(x, depth + 1) end
		active[v] = nil
	end
	visit(value, 0)
end

--- Captures plain data only. Native engine calls cannot be preempted; their elapsed time is
-- measured too and immediately invalidates an over-budget category after the call returns.
function fingerprint.begin(env, gt)
	integer(gt)
	local engine, ct, util = env.api.engine, env.api.type.ComponentType, env.api.engine.util
	local clock = clock_for(env)
	local started, category_started, category_calls = measured(clock), 0, 0
	local job = { gt = gt, categories = {}, values = { wgt = gt }, failed = {}, lists = {}, category = 1,
		stats = { capture_ms = 0, calls = 0, records = 0, limited = 0, hash_bytes = 0, steps = 0, clock = clock ~= nil } }
	local category
	local function guard()
		if job.stats.calls >= fingerprint.CAPTURE_MAX_CALLS or job.stats.calls - category_calls >= fingerprint.CATEGORY_MAX_CALLS
			or measured(clock) - started > fingerprint.CAPTURE_MAX_MS
			or measured(clock) - category_started > fingerprint.CATEGORY_MAX_MS then error("checkpoint capture budget", 0) end
	end
	local function call(fn, ...)
		guard(); job.stats.calls = job.stats.calls + 1
		local v = fn(...)
		guard()
		return v
	end
	-- Checkpoints read one immutable engine tick. Shared references (line names,
	-- station groups, ownership) need only one native read during this capture.
	local components, absent = {}, {}
	local function get_component(id, kind)
		local row = components[id]; if not row then row = {}; components[id] = row end
		local c = row[kind]
		if c == nil then c = call(engine.getComponent, id, kind); row[kind] = c or absent end
		return c ~= absent and c or nil
	end
	local function component(id, name, optional)
		local c = get_component(id, assert(ct[name], "component unavailable: " .. name))
		if not optional then assert(c, "world component unreadable: " .. name) end
		return c
	end
	local function ids(name, cap, owned)
		-- TF3 rejects component enumeration for LINE, BASE_EDGE and SIM_CARGO.
		-- Use the systems' complete indexes, or a bounded whole-entity scan for cargo.
		local source
		if name == "LINE" then source = call(engine.system.lineSystem.getLines)
		elseif name == "BASE_EDGE" then
			source = {}; local seen = {}
			for _, edges in pairs(call(engine.system.streetSystem.getNode2SegmentMap)) do
				guard()
				for i = 1, #edges do
					guard(); local id = edges[i]
					if not seen[id] then
						seen[id] = true; source[#source + 1] = id
						assert(#source <= fingerprint.MAX_RECORDS, "checkpoint index limit: " .. name)
					end
				end
			end
		elseif name == "SIM_CARGO" then
			source = {}
			local stock, vehicles = engine.system.simEntityAtStockSystem, engine.system.simEntityAtVehicleSystem
			if stock and stock.getStock2SimEntityMap and vehicles and vehicles.getVehicle2Cargo2SimEntitesMap then
				-- Prefer TF3's native indexes: its generic cargo iterator is
				-- unsupported. Include both stocks and vehicles, deduplicate,
				-- and explicitly label this bounded coverage in the digest.
				local seen, visited = {}, 0
				local function add(list)
					for i = 1, #list do
						guard(); visited = visited + 1
						assert(visited <= fingerprint.CATEGORY_MAX_CALLS, "checkpoint cargo index limit")
						local id = integer(list[i])
						if not seen[id] then
							seen[id] = true
							if component(id, "SIM_CARGO", true) then source[#source + 1] = id end
							assert(#source <= cap, "checkpoint entity limit: SIM_CARGO")
						end
					end
				end
				for _, list in pairs(call(stock.getStock2SimEntityMap)) do guard(); add(list) end
				for _, cargos in pairs(call(vehicles.getVehicle2Cargo2SimEntitesMap)) do
					guard(); for _, list in pairs(cargos) do guard(); add(list) end
				end
				job.stats.cargo_scope = "stocks_and_vehicles"
			else
				local ok, err = pcall(function()
					call(engine.forEachEntityWithComponent, function(id)
						guard(); source[#source + 1] = id
						assert(#source <= cap, "checkpoint entity limit: SIM_CARGO")
					end, assert(ct.SIM_CARGO))
				end)
				if not ok then
					if tostring(err):find("budget", 1, true) or tostring(err):find("limit", 1, true) then error(err, 0) end
					source = {}
					local visited = 0
					call(engine.forEachEntity, function(id)
						visited = visited + 1; guard()
						assert(visited <= fingerprint.CATEGORY_MAX_CALLS, "checkpoint scan limit: SIM_CARGO")
						if engine.entityExists and not call(engine.entityExists, id) then return end
						if component(id, "SIM_CARGO", true) then
							source[#source + 1] = id
							assert(#source <= cap, "checkpoint entity limit: SIM_CARGO")
						end
					end)
				end
			end
		end
		if source then
			assert(#source <= (owned and fingerprint.MAX_RECORDS or cap), "checkpoint entity limit: " .. name)
			local out = {}
			for i = 1, #source do
				guard(); local id = source[i]
				local owner = owned and component(id, "PLAYER_OWNED", true)
				if not owned or (owner and owner.player == util.getPlayer()) then
					out[#out + 1] = id
					assert(#out <= cap, "checkpoint entity limit: " .. name)
				end
			end
			return out
		end
		local filters = owned and { requireOwnedByPlayer = util.getPlayer() } or nil
		local list = call(engine.getEntitiesWithComponent, assert(ct[name], "component unavailable: " .. name), filters)
		assert(list ~= nil and #list <= cap, "checkpoint entity limit: " .. name)
		return list
	end
	local function name_of(id)
		local n = component(id, "NAME", true)
		assert(n == nil or type(n.name) == "string", "world name unreadable")
		return n and n.name or ""
	end
	local function cargo_name(id)
		local name = call(env.api.res.cargoTypeRep.getName, integer(id))
		assert(type(name) == "string" and #name > 0, "cargo resource unreadable")
		return name
	end
	local function vehicle_ref(id)
		local v = component(id, "TRANSPORT_VEHICLE")
		local out = { name = name_of(id), carrier = integer(v.carrier) }
		if v.line and v.line >= 0 then out.line = name_of(v.line) end
		return out
	end
	local function entity_ref(id)
		integer(id)
		if id < 0 then return { missing = true } end
		local box = component(id, "BOUNDING_VOLUME").bbox
		local lo, hi = box.min, box.max
		return { name = name_of(id), position = position({ x = (finite(lo.x) + finite(hi.x)) / 2,
			y = (finite(lo.y) + finite(hi.y)) / 2, z = (finite(lo.z) + finite(hi.z)) / 2 }) }
	end
	local function append(record)
		guard(); bounded_plain(record)
		category.records[#category.records + 1] = record
		job.stats.records = job.stats.records + 1
	end
	local function capture(kind, fn)
		category_started = measured(clock)
		category_calls = job.stats.calls
		category = { kind = kind, field = fingerprint.FIELDS[kind], records = {}, hashes = {}, cursor = 1 }
		local ok, err = pcall(function() guard(); fn(); guard() end)
		if ok then job.categories[#job.categories + 1] = category
		else
			job.failed[#job.failed + 1] = category.field
			job.stats[category.field] = tostring(err):sub(1, 120)
			if tostring(err):find("limit", 1, true) or tostring(err):find("budget", 1, true) then job.stats.limited = job.stats.limited + 1 end
		end
	end
	local function read_time()
		return engine.getComponent(util.getWorld(), assert(ct.GAME_TIME)).gameTime
	end
	local time_ok, before = pcall(read_time)
	if not time_ok or before ~= gt then
		for _, kind in ipairs({ "construction", "line", "vehicle", "edge", "position", "cargo", "town" }) do
			job.failed[#job.failed + 1] = fingerprint.FIELDS[kind]
		end
		job.stats.time_unreadable = true
		return job
	end
	for _, spec in ipairs({ { "construction", "CONSTRUCTION" }, { "line", "LINE" },
		{ "vehicle", "TRANSPORT_VEHICLE" }, { "edge", "BASE_EDGE" } }) do
		capture(spec[1], function()
			local read_failed = false
			local audited_engine = setmetatable({ getComponent = function(id, c)
				local ok, v = pcall(function()
					local value = get_component(id, c)
					if value ~= nil and c == ct.NAME then assert(type(value.name) == "string", "unreadable name") end
					if value ~= nil and c == ct.CONSTRUCTION then
						local params = value.params_native
						if type(params) == "userdata" then params = call(function() return params:asTable() end) end
						if params ~= nil then
							bounded_plain(params) -- reject huge module tables before action capture's wire copy
							local native = value
							value = setmetatable({ params_native = params }, { __index = function(_, k) return native[k] end })
						end
					end
					if value ~= nil and c == ct.TRANSPORT_VEHICLE then
						local config = value.transportVehicleConfig
						assert(#config.vehicles <= 128, "vehicle part limit")
					end
					if value ~= nil and c == ct.LINE then
						assert(#value.stops <= 128, "line stop limit")
						-- Native stopConfig and waypoint values may be userdata in a
						-- plain stops table. actions.read_record converts their documented
						-- fields; validate that plain result rather than rejecting TF3 data.
					end
					return value
				end)
				if not ok then read_failed = true; error(v, 0) end
				return v
			end }, { __index = engine })
			local audited_models = setmetatable({ getName = function(id) return call(env.api.res.modelRep.getName, id) end }, { __index = env.api.res.modelRep })
			local audited_res = setmetatable({ modelRep = audited_models }, { __index = env.api.res })
			local audited_api = setmetatable({ engine = audited_engine, res = audited_res }, { __index = env.api })
			local audited_env = setmetatable({ api = audited_api }, { __index = env })
			for _, id in ipairs(ids(spec[2], fingerprint.STATIC_MAX_RECORDS, true)) do
				guard()
				local record = assert(actions.read_record, "record reader unavailable")(audited_env, id, spec[1])
				assert(not read_failed, "checkpoint component read failed")
				if record then append(record) end
			end
		end)
	end
	capture("position", function()
		for _, id in ipairs(ids("TRANSPORT_VEHICLE", fingerprint.VEHICLE_MAX_RECORDS, true)) do
			local v = component(id, "TRANSPORT_VEHICLE")
			local states = env.api.type.enum and env.api.type.enum.TransportVehicleState
			if v.state == "IN_DEPOT" or (states and states.IN_DEPOT ~= nil and v.state == states.IN_DEPOT) then
				local parent = call(engine.system.streetConnectorSystem.getConstructionEntityForDepot, integer(v.depot))
				local con = component(integer(parent), "CONSTRUCTION")
				local t = assert(build.read_transf(con.transf), "depot transformation unreadable")
				local slot
				for i = 1, #con.depots do if con.depots[i] == v.depot then assert(not slot, "ambiguous depot"); slot = i end end
				append({ vehicle = vehicle_ref(id), depot = { fileName = con.fileName,
					position = position({ x = t[13], y = t[14], z = t[15] }), index = assert(slot, "depot slot unreadable") }, speed = 0 })
			else
				append({ vehicle = vehicle_ref(id), position = position(call(util.vehicle.getPosition, id)),
					speed = finite(call(util.vehicle.getSpeed, id)) })
			end
		end
	end)
	capture("cargo", function()
		for _, id in ipairs(ids("TRANSPORT_VEHICLE", fingerprint.VEHICLE_MAX_RECORDS, true)) do
			local counts, out = call(util.cargo.getNumCargoPerTypeInVehicle, id), {}
			local count = 0
			-- The documented vector is 1-based (cargo id + 1). Accept an explicit 0-based map too.
			local zero_ok, zero = pcall(function() return counts[0] end)
			local base = zero_ok and zero ~= nil and 0 or 1
			local function add(k, n)
				count = count + 1; assert(count <= 256, "cargo type limit")
				assert(integer(n) >= 0, "cargo quantity unreadable")
				if n > 0 then out[cargo_name(integer(k) - base)] = n end
			end
			if type(counts) == "userdata" then
				assert(#counts <= 256, "cargo type limit")
				for k = base, #counts - 1 + base do add(k, counts[k]) end
			else for k, n in pairs(counts) do add(k, n) end
			end
			append({ scope = "vehicle", vehicle = vehicle_ref(id), counts = out })
		end
		for _, id in ipairs(ids("SIM_CARGO", fingerprint.CARGO_MAX_RECORDS, false)) do
			local c = component(id, "SIM_CARGO")
			local r = { scope = "freight", cargoType = cargo_name(c.cargoType), source = entity_ref(c.sourceEntity),
				target = entity_ref(c.targetOrPickupEntity), startTime = integer(c.startTime), pickupTime = integer(c.pickupTime) }
			local on_vehicle = component(id, "SIM_ENTITY_AT_VEHICLE", true)
			if on_vehicle then r.vehicle = vehicle_ref(on_vehicle.vehicle) end
			append(r)
		end
		if job.stats.cargo_scope then append({ scope = "coverage", method = job.stats.cargo_scope }) end
	end)
	capture("town", function()
		for _, id in ipairs(ids("TOWN", fingerprint.TOWN_MAX_RECORDS, false)) do
			local c, ref = component(id, "TOWN"), entity_ref(id)
			assert(type(c.developmentActive) == "boolean", "town development unreadable")
			local r = { name = ref.name, position = ref.position, initial = {}, sizeFactors = {}, usage = {},
				cargoNeeds = {}, stock = {}, developmentActive = c.developmentActive,
				capacityScalingFactor = finite(c.capacityScalingFactor) }
			local usage = call(util.town.getTownCapacityUsage, id)
			for i = 1, 3 do
				r.initial[i], r.sizeFactors[i] = integer(c.initialLandUseCapacities[i]), finite(c.sizeFactors[i])
				r.usage[i] = { used = integer(usage[i].used), capacity = integer(usage[i].capacity) }
				r.cargoNeeds[i] = {}
				for j, need in ipairs(c.cargoNeeds[i]) do
					assert(j <= 256, "town cargo type limit")
					r.cargoNeeds[i][j] = { cargoType = cargo_name(need[1]), amount = finite(need[2]) }
				end
				table.sort(r.cargoNeeds[i], function(a, b) return a.cargoType < b.cargoType end)
			end
			local stock_types = 0
			for cargo, counts in pairs(call(util.town.getTownStockCargo, id)) do
				guard(); stock_types = stock_types + 1
				assert(stock_types <= 256, "town stock type limit")
				r.stock[cargo_name(cargo)] = { integer(counts[1]), integer(counts[2]) }
			end
			append(r)
		end
	end)
	local after_ok, after = pcall(read_time)
	if not after_ok or after ~= gt then
		for _, c in ipairs(job.categories) do job.failed[#job.failed + 1] = c.field end
		job.categories = {}; job.stats.time_unreadable = true
	end
	job.stats.capture_ms = clock and measured(clock) - started or -1
	return job
end

local function stream_hash(text)
	return { text = text, cursor = 1, a = 2166136261, b = 2246822519 }
end

--- Bounded hashing of immutable data. In particular this never reads later vehicle positions,
-- inventories or town populations and labels them with an earlier checkpoint time.
function fingerprint.step(env, job)
	if job.done then return job.values, job.failed, job.stats, job.lists end
	local clock, bytes, records = clock_for(env), 0, 0
	local started = measured(clock)
	job.stats.steps = job.stats.steps + 1
	local function finish_stats()
		job.stats.hash_bytes = job.stats.hash_bytes + bytes
		job.stats.last_step_bytes, job.stats.last_step_records = bytes, records
		job.stats.max_step_ms = math.max(job.stats.max_step_ms or 0, clock and measured(clock) - started or 0)
	end
	while bytes < fingerprint.HASH_BYTES_PER_STEP and records < fingerprint.HASH_RECORDS_PER_STEP do
		if clock and measured(clock) - started >= fingerprint.HASH_MAX_MS then break end
		local c = job.categories[job.category]
		if not c then
			job.done = true
			finish_stats()
			return job.values, job.failed, job.stats, job.lists
		end
		if not c.stream then
			if c.cursor <= #c.records then
				local raw = c.records[c.cursor]
				local ok, n, text = pcall(function()
					bounded_plain(raw)
					local normalized = fingerprint.normalize(c.kind, raw)
					bounded_plain(normalized)
					local encoded = fingerprint.canonical(normalized)
					assert(#encoded <= fingerprint.RECORD_MAX_BYTES, "checkpoint encoded record limit")
					return normalized, encoded
				end)
				if not ok then
					job.failed[#job.failed + 1] = c.field
					job.stats[c.field] = tostring(n):sub(1, 120)
					job.categories[job.category] = { failed = true }
					job.category = job.category + 1
				else
					c.stream, c.normalized = stream_hash(text), n
				end
			else
				table.sort(c.hashes)
				c.stream = stream_hash(c.kind .. ":" .. #c.hashes .. ":" .. table.concat(c.hashes, ":"))
				c.final = true
			end
		end
		if c.stream then
			local s = c.stream
			local last = math.min(#s.text, s.cursor + fingerprint.HASH_BYTES_PER_STEP - bytes - 1)
			for i = s.cursor, last do
				local b = s.text:byte(i)
				s.a, s.b = (s.a * 131 + b) % 4294967291, (s.b * 137 + b) % 4294967279
			end
			bytes = bytes + math.max(0, last - s.cursor + 1)
			s.cursor = last + 1
			if s.cursor > #s.text then
				local h = string.format("%08x%08x", s.a, s.b)
				if c.final then
					job.values[c.field] = "h" .. (MOVING[c.kind] and 2 or fingerprint.VERSION) .. "_" .. h
					local list = c.list or {}
					list.total, list.gt = #c.hashes, job.gt
					list.truncated = #c.hashes > fingerprint.DETAIL_MAX_RECORDS
					job.lists[c.field] = list
					job.category = job.category + 1
					c.records, c.hashes, c.stream, c.normalized = nil, nil, nil, nil
				else
					c.hashes[#c.hashes + 1] = h
					if #c.hashes <= fingerprint.DETAIL_MAX_RECORDS then
						c.list = c.list or {}
						local ok, d = true, c.kind .. " data " .. h
						if #s.text <= 4096 then ok, d = pcall(fingerprint.describe, c.kind, c.normalized) end
						c.list[#c.list + 1] = { h = h, d = ok and d or "record description unavailable" }
					end
					c.records[c.cursor], c.cursor, c.stream, c.normalized = false, c.cursor + 1, nil, nil
					records = records + 1
				end
			end
		end
	end
	finish_stats()
	return nil
end

return fingerprint

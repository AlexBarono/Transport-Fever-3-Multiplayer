-- Read-only world digests against the bundled TF3 API shape, without stable entity ids.
-- Run from the repository root: python tools/run_lua.py tests/run_fingerprint.lua
local original_require, loaded = require, {}
function require(path)
	if path:sub(1, 1) ~= "/" then return original_require(path) end
	if not loaded[path] then loaded[path] = assert(loadfile("mods/mp_probe/content" .. path))() end
	return loaded[path]
end
local wire = require("/mp_probe/wire.lua")
local fingerprint = require("/mp_probe/fingerprint.lua")
local sync = require("/mp_probe/sync.lua")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function copy(v) return wire.copy(v) end
local function xyz(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
local function transform(x)
	return { { x = 1, y = 0, z = 0, w = 0 }, { x = 0, y = 1, z = 0, w = 0 },
		{ x = 0, y = 0, z = 1, w = 0 }, { x = x or 0, y = 20, z = 0, w = 1 } }
end

local function mock(shift, reverse)
	shift = shift or 0
	local m = { entities = {}, reads = 0 }
	local ct = {}
	for _, k in ipairs({ "NAME", "COLOR", "PLAYER_OWNED", "CONSTRUCTION", "LINE", "STATION_GROUP",
		"TRANSPORT_VEHICLE", "BASE_EDGE" }) do ct[k] = k end
	local engine = { util = { getPlayer = function() return 7 end }, system = {} }
	function engine.getComponent(id, c)
		m.reads = m.reads + 1
		if m.fail_name and c == "NAME" and id == (m.fail_name_id or m.ca) then error("name unreadable") end
		local e = assert(m.entities[id], "entity missing")
		return e[c] and copy(e[c])
	end
	function engine.forEachEntityWithComponent(fn, c)
		local ids = {}
		for id, e in pairs(m.entities) do if e[c] then ids[#ids + 1] = id end end
		table.sort(ids, function(a, b) return reverse and a > b or not reverse and a < b end)
		for _, id in ipairs(ids) do
			fn(id)
			if m.fail == c then error("enumeration failed after first entity") end
		end
	end
	engine.system.lineSystem = { getLines = function()
		local out = {}; engine.forEachEntityWithComponent(function(id) out[#out + 1] = id end, "LINE"); return out
	end }
	engine.system.streetSystem = { getNode2SegmentMap = function()
		local out = {}; for id, e in pairs(m.entities) do if e.BASE_EDGE then out[id] = { id, id } end end; return out
	end }
	engine.system.streetConnectorSystem = {
		getConstructionEntityForStation = function(id) return m.parents[id] end,
		getConstructionEntityForDepot = function(id) return m.parents[id] end,
		getConstructionEntityForEdge = function(id) return m.edge_parent and id == m.edgeid and m.ca or -1 end,
	}
	local function base(id, name)
		local e = { NAME = { name = name or "" }, PLAYER_OWNED = { player = 7 } }
		m.entities[id] = e
		return e
	end
	m.ca, m.cb, m.sa, m.sb = 101 + shift, 102 + shift, 301 + shift, 302 + shift
	m.group, m.lineid, m.vid, m.edgeid = 501 + shift, 601 + shift, 701 + shift, 801 + shift
	m.parents = { [m.sa] = m.ca, [m.sb] = m.cb }
	for i, id in ipairs({ m.ca, m.cb }) do
		base(id, i == 1 and "Alpha" or "Beta").CONSTRUCTION = { fileName = "::/station.con",
			transf = transform(i * 100), params = { seed = 1 },
			params_native = { seed = 7, year = 1850, modules = { [1000] = { name = "::/platform.module", variant = 0 } } },
			stations = { i == 1 and m.sa or m.sb }, depots = {} }
	end
	m.entities[m.group] = { STATION_GROUP = { stations = reverse and { m.sb, m.sa } or { m.sa, m.sb } } }
	local function stop(station)
		return { stationGroup = m.group, station = reverse and 1 - station or station, terminal = 0, loadMode = 0,
			minWaitingTime = 0, maxWaitingTime = 10, maxAdditionalWaitingTime = 1,
			stopConfig = { load = { [0] = true }, maxLoad = { [0] = 1 }, forceUnload = false },
			alternativeTerminals = { { station = reverse and station or 1 - station, terminal = 1 } }, waypoints = {} }
	end
	local l = base(m.lineid, "City route")
	l.COLOR = { color = xyz(1, 0.5, 0) }
	l.LINE = { stops = { stop(0), stop(1) }, customFilters = false, reservationPriority = 1,
		vehicleInfo = { transportModes = { [0] = true } } }
	base(m.vid, "Train 1").TRANSPORT_VEHICLE = {
		line = m.lineid, depot = -1, userStopped = false, autoDeparture = true, stopIndex = 0,
		transportVehicleConfig = { vehicleGroups = { 1 }, muFileNames = { "" },
			vehicles = { { part = { modelId = 5 + shift, reversed = false, color = xyz(1, 0.5, 0),
				compartment2loadConfig = { [0] = { loadConfigIndex = 0, cargoTypeId = -1 } } },
				autoLoadConfig = { [0] = true } } } } }
	base(m.edgeid).BASE_EDGE = { position0 = xyz(0, 30), position1 = xyz(100, 35),
		tangent0 = xyz(100, 10), tangent1 = xyz(100, -5),
		roadTemplate = "::/standard.track_template", roadStyle = "::/catenary.track_style" }
	m.env = { api = { engine = engine, type = { ComponentType = ct,
		Mat4f = { cols = function(value, i) return copy(value[i]) end } },
		res = { modelRep = { getName = function(id) assert(id == 5 + shift, "missing model"); return "::/train.mdl" end } } } }
	function m.values()
		local out, unreadable = fingerprint.values(m.env)
		assert(#unreadable == 0, table.concat(unreadable, ","))
		return out
	end
	return m
end
local function same(a, b)
	for _, field in ipairs(sync.HASH_FIELDS) do assert(a[field] == b[field], field) end
end
local function differs(a, b, field)
	assert(a[field] and b[field] and a[field] ~= b[field], field .. " unchanged")
end

test("fresh engine snapshots normalize entity ids, enumeration and station-group order", function()
	local a, b = mock(), mock(10000, true)
	same(a.values(), b.values())
	assert(a.reads > 0 and b.reads > 0)
end)

test("same-count modular station changes are detected using the complete native params", function()
	local m = mock(); local before = m.values()
	m.entities[m.ca].CONSTRUCTION.params_native.modules[2000] = { name = "::/track.module", variant = 2 }
	differs(before, m.values(), "hcon")
end)

test("construction transforms use millimetre bins and retain visible movement", function()
	local m = mock(); local before = m.values()
	m.entities[m.ca].CONSTRUCTION.transf[4].x = 100.0004
	same(before, m.values())
	m.entities[m.ca].CONSTRUCTION.transf[4].x = 100.0006
	differs(before, m.values(), "hcon")
end)

test("track resource, style and curved geometry changes are detected without count differences", function()
	for _, change in ipairs({
		function(e) e.roadTemplate = "::/high_speed.track_template" end,
		function(e) e.roadStyle = "::/no_catenary.track_style" end,
		function(e) e.tangent1.y = 30 end,
		function(e) e.position1.x = 110 end,
	}) do
		local m = mock(); local before = m.values(); change(m.entities[m.edgeid].BASE_EDGE)
		differs(before, m.values(), "hedge")
	end
end)

test("the same edge reversed has the same digest", function()
	local m = mock(); local before = m.values(); local e = m.entities[m.edgeid].BASE_EDGE
	e.position0, e.position1 = e.position1, e.position0
	e.tangent0, e.tangent1 = xyz(-100, 5), xyz(-100, -10)
	same(before, m.values())
end)

test("construction-owned edges and foreign player objects are excluded", function()
	local m = mock(); m.edge_parent = true; local before = m.values()
	m.entities[m.edgeid].BASE_EDGE.roadStyle = "changed internals"
	m.entities[9000] = copy(m.entities[m.ca]); m.entities[9000].PLAYER_OWNED.player = 9
	same(before, m.values())
end)

test("line names, colors, route order, load configuration and selected station are detected", function()
	for _, change in ipairs({
		function(m) m.entities[m.lineid].NAME.name = "New name" end,
		function(m) m.entities[m.lineid].COLOR.color.y = 0.8 end,
		function(m) local s = m.entities[m.lineid].LINE.stops; s[1], s[2] = s[2], s[1] end,
		function(m) m.entities[m.lineid].LINE.stops[1].stopConfig.maxLoad[0] = 0.5 end,
		function(m) m.entities[m.lineid].LINE.stops[1].station = 1 end,
	}) do
		local m = mock(); local before = m.values(); change(m)
		differs(before, m.values(), "hline")
	end
end)

test("unique station and terminal tags survive harbor child and terminal reordering", function()
	local m = mock()
	local records = require("/mp_probe/actions.lua").snapshot(m.env, "line")
	local record = records[tostring(m.lineid)]
	for _, s in ipairs(record.data.stops) do
		for i, ref in ipairs(s.target.stations) do ref.tag = 100 + i end
		s.terminalTag = 700
		for _, alt in ipairs(s.alternativeTerminals) do alt.terminalTag = 800 end
	end
	local before = fingerprint.digest("line", records)
	for _, s in ipairs(record.data.stops) do
		for _, ref in ipairs(s.target.stations) do ref.index = ref.index + 4 end
		s.terminal = s.terminal + 3
		for _, alt in ipairs(s.alternativeTerminals) do alt.terminal = alt.terminal + 5 end
	end
	assert(before == fingerprint.digest("line", records))
	record.data.stops[1].terminalTag = 701
	assert(before ~= fingerprint.digest("line", records), "a different tagged terminal must still differ")
end)

test("moving vehicle stop indexes, positions, depots and derived line modes are ignored", function()
	local m = mock(); local before = m.values()
	local v = m.entities[m.vid].TRANSPORT_VEHICLE
	v.stopIndex, v.position = 1, xyz(300, 800)
	-- A depot is deliberately absent from normalized records even if readable during departure.
	local records = { a = { name = "Train", config = {}, userStopped = false, autoDeparture = true,
		line = { kind = "line", key = "1", name = "Route" }, depot = { arbitrary = 1 }, stopIndex = 0 } }
	local digest = fingerprint.digest("vehicle", records)
	records.a.depot, records.a.stopIndex = { arbitrary = 2 }, 5
	assert(digest == fingerprint.digest("vehicle", records))
	m.entities[m.lineid].LINE.vehicleInfo.transportModes = { [0] = false, [1] = true }
	same(before, m.values())
end)

test("vehicle composition, load configuration, names and user controls are detected", function()
	for _, change in ipairs({
		function(m) m.entities[m.vid].NAME.name = "Express" end,
		function(m) m.entities[m.vid].TRANSPORT_VEHICLE.userStopped = true end,
		function(m) m.entities[m.vid].TRANSPORT_VEHICLE.autoDeparture = false end,
		function(m) m.entities[m.vid].TRANSPORT_VEHICLE.line = -1 end,
		function(m) local c = m.entities[m.vid].TRANSPORT_VEHICLE.transportVehicleConfig; c.vehicles[2] = copy(c.vehicles[1]) end,
		function(m) m.entities[m.vid].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].part.compartment2loadConfig[0].loadConfigIndex = 2 end,
	}) do
		local m = mock(); local before = m.values(); change(m)
		differs(before, m.values(), "hveh")
	end
end)

test("duplicate identical records retain multiplicity", function()
	local r = { a = { data = { fileName = "station", transf = transform(0), params = {}, name = "" } } }
	local one = fingerprint.digest("construction", r)
	r.b = copy(r.a)
	assert(one ~= fingerprint.digest("construction", r))
end)

test("a partially failed enumeration cannot publish a partial or retained equality digest", function()
	local m = mock(); local before = m.values(); assert(before.hcon)
	m.fail = "CONSTRUCTION"
	local values, unreadable = fingerprint.values(m.env)
	assert(values.hcon == nil and values.hline and values.hveh and values.hedge)
	assert(#unreadable == 1 and unreadable[1] == "hcon")
end)

test("one unreadable entity invalidates its complete category and recovers on a fresh read", function()
	local m = mock(); local original = m.values()
	m.entities[m.vid].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].part.modelId = 77
	local values, unreadable = fingerprint.values(m.env)
	assert(values.hveh == nil and values.hcon and #unreadable == 1 and unreadable[1] == "hveh")
	m.entities[m.vid].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].part.modelId = 5
	same(original, m.values())
end)

test("missing persistent resource or control fields are not hashed as equality", function()
	local m = mock()
	m.entities[m.edgeid].BASE_EDGE.roadStyle = nil
	m.entities[m.vid].TRANSPORT_VEHICLE.userStopped = nil
	local values, unreadable = fingerprint.values(m.env)
	assert(values.hedge == nil and values.hveh == nil and values.hline and values.hcon)
	assert(#unreadable == 2)
end)

test("a failed optional-name read cannot masquerade as an unnamed object", function()
	local m = mock(); m.fail_name = true
	local values, unreadable = fingerprint.values(m.env)
	assert(values.hcon == nil and unreadable[1] == "hcon")
end)

test("a swallowed referenced-line name failure also invalidates the vehicle digest", function()
	local m = mock(); m.fail_name, m.fail_name_id = true, m.lineid
	local values = fingerprint.values(m.env)
	assert(values.hline == nil and values.hveh == nil and values.hcon and values.hedge)
end)

test("incomplete construction and malformed geometry do not become comparison evidence", function()
	local m = mock()
	for _, data in ipairs({ { fileName = "station", transf = transform(0), name = "" },
		{ fileName = "station", params = {}, name = "" }, { params = {}, transf = transform(0), name = "" } }) do
		assert(not pcall(fingerprint.digest, "construction", { a = { data = data } }))
	end
	m.entities[m.ca].CONSTRUCTION.params_native, m.entities[m.ca].CONSTRUCTION.params = nil, nil
	m.entities[m.edgeid].BASE_EDGE.position0.x = nil
	local values = fingerprint.values(m.env)
	assert(values.hcon == nil and values.hedge == nil)
end)

test("empty readable categories still have a comparison digest", function()
	local m = mock(); m.entities = {}
	local values = m.values()
	for _, field in ipairs({ "hcon", "hedge", "hline", "hveh" }) do assert(values[field]:match("^h1_%x+$")) end
end)

test("unsupported, non-finite and cyclic data cannot become equality evidence", function()
	for _, v in ipairs({ 0 / 0, math.huge, function() end }) do assert(not pcall(fingerprint.canonical, { v = v })) end
	local cyclic = {}; cyclic.self = cyclic; assert(not pcall(fingerprint.canonical, cyclic))
	assert(fingerprint.canonical({ x = -0.0 }) == fingerprint.canonical({ x = 0.0 }))
end)

test("large record sets remain deterministic and the record budget is enforced", function()
	local a, b = {}, {}
	for i = 1, 5000 do
		local r = { name = "Train " .. i, config = { model = "::/train.mdl" }, userStopped = false, autoDeparture = true }
		a[tostring(i)], b[tostring(10000 - i)] = r, r
	end
	assert(fingerprint.digest("vehicle", a) == fingerprint.digest("vehicle", b))
	local limit = fingerprint.MAX_RECORDS; fingerprint.MAX_RECORDS = 3
	local ok = pcall(fingerprint.digest, "vehicle", a)
	fingerprint.MAX_RECORDS = limit
	assert(not ok)
end)

test("the compact digest fields fit the native checkpoint state limit", function()
	local values = mock().values()
	values.gt, values.money, values.loan, values.date = 120000, -90000000000, 50000000, "2120-12-31"
	values.lines, values.veh, values.st, values.con, values.k = 5000, 50000, 10000, 10000, 123456
	local text = sync.encode(values)
	assert(#text <= 511, #text)
	same(values, sync.decode(text))
end)

test("the record list names the records and the field two games differ in", function()
	local a, b = mock(), mock(10000, true)
	b.entities[b.edgeid].BASE_EDGE.tangent1.y = -5.2
	local la, lb = fingerprint.list(a.env, "edge"), fingerprint.list(b.env, "edge")
	assert(#la == 1 and #lb == 1 and la[1].h ~= lb[1].h)
	assert(la[1].d == "standard.track_template/catenary.track_style 0.000,30.000,0.000 > 100.000,35.000,0.000 " ..
		"tangents 100.000,10.000,0.000 / 100.000,-5.000,0.000", la[1].d)
	assert(lb[1].d:find("100.000,-5.200,0.000", 1, true), lb[1].d)
	-- The same records give the same hashes, whatever their ids.
	local ca, cb = fingerprint.list(a.env, "construction"), fingerprint.list(mock(10000, true).env, "construction")
	assert(#ca == 2 and ca[1].h == cb[1].h and ca[2].h == cb[2].h)
	assert(ca[1].d:find("station.con at ", 1, true) and ca[1].d:find(" params ", 1, true), ca[1].d)
	for _, kind in ipairs({ "line", "vehicle" }) do
		local l = fingerprint.list(a.env, kind)
		assert(#l == 1 and not l[1].d:find("unreadable", 1, true), kind .. ": " .. tostring(l[1] and l[1].d))
	end
end)

local function world_mock(shift, reverse, cargo_id)
	local m = mock(shift, reverse)
	local e, ct = m.env.api.engine, m.env.api.type.ComponentType
	for _, name in ipairs({ "GAME_TIME", "TOWN", "BOUNDING_VOLUME", "SIM_CARGO", "SIM_ENTITY_AT_VEHICLE" }) do ct[name] = name end
	m.gt, m.townid, m.cargoid, m.worldid = 60000, 4001 + (shift or 0), 5001 + (shift or 0), 99001 + (shift or 0)
	cargo_id = cargo_id or 1
	e.util.getWorld = function() return m.worldid end
	m.entities[m.worldid] = { GAME_TIME = { gameTime = m.gt } }
	e.getEntitiesWithComponent = function(c, filters)
		local out = {}
		e.forEachEntityWithComponent(function(id)
			local owner = m.entities[id].PLAYER_OWNED
			if not filters or (owner and owner.player == filters.requireOwnedByPlayer) then out[#out + 1] = id end
		end, c)
		return out
	end
	e.forEachEntity = function(fn)
		local all = {}; for id in pairs(m.entities) do all[#all + 1] = id end
		table.sort(all); for _, id in ipairs(all) do fn(id) end
	end
	local function box(x, y)
		return { bbox = { min = xyz(x - 1, y - 1, 0), max = xyz(x + 1, y + 1, 2) } }
	end
	m.entities[m.ca].BOUNDING_VOLUME, m.entities[m.cb].BOUNDING_VOLUME = box(100, 20), box(200, 20)
	m.positions, m.speeds = { [m.vid] = xyz(151.25, 31.2, 5) }, { [m.vid] = 12.4 }
	m.entities[m.vid].TRANSPORT_VEHICLE.carrier = 2
	e.util.vehicle = { getPosition = function(id) return copy(assert(m.positions[id])) end,
		getSpeed = function(id) return assert(m.speeds[id]) end }
	m.cargo_counts = cargo_id == 1 and { 3, 4 } or { [0] = 3, [cargo_id] = 4 }
	e.util.cargo = { getNumCargoPerTypeInVehicle = function(id) assert(id == m.vid); return copy(m.cargo_counts) end }
	m.env.api.res.cargoTypeRep = { getName = function(id)
		assert(id == 0 or id == cargo_id, "cargo resource missing")
		return id == 0 and "::/passengers.cargo" or "::/coal.cargo"
	end }
	m.entities[m.cargoid] = { SIM_CARGO = { cargoType = cargo_id, sourceEntity = m.ca,
		targetOrPickupEntity = m.cb, startTime = 50000, pickupTime = 55000 },
		SIM_ENTITY_AT_VEHICLE = { vehicle = m.vid } }
	m.entities[m.townid] = { NAME = { name = "City" }, BOUNDING_VOLUME = box(400, 900),
		TOWN = { initialLandUseCapacities = { 100, 50, 40 }, sizeFactors = { 1, 1, 1 }, capacityScalingFactor = 1,
			developmentActive = true, cargoNeeds = { {}, { { cargo_id, 10 } }, {} } } }
	m.town_usage, m.town_stock = { { used = 42, capacity = 100 }, { used = 20, capacity = 50 }, { used = 10, capacity = 40 } }, { [cargo_id] = { 5, 25 } }
	e.util.town = { getTownCapacityUsage = function(id) assert(id == m.townid); return copy(m.town_usage) end,
		getTownStockCargo = function(id) assert(id == m.townid); return copy(m.town_stock) end }
	-- Tests use work bounds; wall-clock thresholds must not make assertions machine-dependent.
	m.env.os = { clock = function() return 0 end }
	return m
end

local function finish(m, job)
	job = job or fingerprint.begin(m.env, m.gt)
	for _ = 1, 10000 do
		local values, unreadable, stats, lists = fingerprint.step(m.env, job)
		if values then return values, unreadable, stats, lists, job end
		assert(job.stats.last_step_bytes <= fingerprint.HASH_BYTES_PER_STEP)
		assert(job.stats.last_step_records <= fingerprint.HASH_RECORDS_PER_STEP)
	end
	error("checkpoint hash did not finish")
end

test("deferred static hashes equal the legacy digest and add exact-tick dynamic categories", function()
	local m = world_mock()
	local before = m.values()
	local values, unreadable, stats, lists = finish(m)
	assert(#unreadable == 0, table.concat(unreadable, ","))
	for _, f in ipairs({ "hcon", "hedge", "hline", "hveh" }) do assert(values[f] == before[f], f) end
	for _, f in ipairs({ "hpos", "hcargo", "htown" }) do assert(values[f]:match("^h2_%x+$") and lists[f].gt == m.gt, f) end
	assert(values.wgt == m.gt and stats.steps > 0 and stats.hash_bytes > 0)
end)

test("positions, cargo allocation and town data do not depend on entity or resource ids", function()
	local a, b = world_mock(), world_mock(10000, true, 7)
	local av, af = finish(a); local bv, bf = finish(b)
	assert(#af == 0 and #bf == 0)
	same(av, bv)
end)

test("moving position and speed changes are detected at a common simulation tick", function()
	local m = world_mock(); local before = finish(m)
	m.positions[m.vid].x = m.positions[m.vid].x + 1
	differs(before, finish(m), "hpos")
	m.speeds[m.vid] = 17
	differs(before, finish(m), "hpos")
end)

test("loaded passenger/freight quantities and global cargo allocations are compared", function()
	local m = world_mock(); local before = finish(m)
	m.cargo_counts[1] = 7
	differs(before, finish(m), "hcargo")
	m.cargo_counts[1] = 3
	m.entities[m.cargoid].SIM_CARGO.targetOrPickupEntity = m.ca
	differs(before, finish(m), "hcargo")
	m.entities[m.cargoid + 1] = copy(m.entities[m.cargoid])
	differs(before, finish(m), "hcargo")
end)

test("town population, growth sizes, development and stored freight changes are detected", function()
	for _, change in ipairs({
		function(m) m.town_usage[1].used = 43 end,
		function(m) m.entities[m.townid].TOWN.sizeFactors[1] = 1.5 end,
		function(m) m.entities[m.townid].TOWN.developmentActive = false end,
		function(m) m.town_stock[1][1] = 9 end,
	}) do
		local m = world_mock(); local before = finish(m); change(m)
		differs(before, finish(m), "htown")
	end
end)

test("later updates hash only immutable original-tick records", function()
	local m = world_mock(); local expected = finish(m)
	local job = fingerprint.begin(m.env, m.gt)
	m.positions[m.vid], m.cargo_counts, m.town_usage = xyz(9999, 8888), { 900, 600 }, { { used = 999, capacity = 999 } }
	m.entities = {} -- any later live component read would now fail
	local actual = finish(m, job)
	same(expected, actual)
	assert(actual.wgt == 60000)
end)

test("capture spanning two different simulation ticks publishes no world hashes", function()
	local m = world_mock(); local original = m.env.api.engine.getComponent; local calls = 0
	m.env.api.engine.getComponent = function(id, c)
		if c == "GAME_TIME" then calls = calls + 1; return { gameTime = calls == 1 and 60000 or 60200 } end
		return original(id, c)
	end
	local values, unreadable, stats = finish(m)
	for _, f in ipairs(sync.HASH_FIELDS) do assert(values[f] == nil, f) end
	assert(#unreadable == #sync.HASH_FIELDS and stats.time_unreadable)
end)

test("unreadable vehicle positions and unknown cargo source remain unknown", function()
	local m = world_mock()
	m.env.api.engine.util.vehicle.getPosition = function() error("position unavailable") end
	m.entities[m.cargoid].SIM_CARGO.sourceEntity = 1234567
	local values = finish(m)
	assert(values.hpos == nil and values.hcargo == nil and values.htown)
end)

test("large-category record limits produce unknown without reading a partial set", function()
	local m = world_mock(); local cap = fingerprint.CARGO_MAX_RECORDS
	fingerprint.CARGO_MAX_RECORDS = 1
	m.entities[m.cargoid + 1] = copy(m.entities[m.cargoid])
	local values, unreadable, stats = finish(m)
	fingerprint.CARGO_MAX_RECORDS = cap
	assert(values.hcargo == nil and values.hpos and stats.limited >= 1)
end)

test("a slow native enumeration invalidates that category after returning", function()
	local m = world_mock(); local elapsed = 0
	m.env.os.clock = function() return elapsed / 1000 end
	local original = m.env.api.engine.getEntitiesWithComponent
	m.env.api.engine.getEntitiesWithComponent = function(c, filters)
		local list = original(c, filters)
		if c == "CONSTRUCTION" then elapsed = elapsed + fingerprint.CATEGORY_MAX_MS + 1 end
		return list
	end
	local values, unreadable, stats = finish(m)
	assert(values.hcon == nil and stats.limited >= 1 and stats.capture_ms >= 5 and values.hpos)
end)

test("large scans share the capture budget so complete later categories stay readable", function()
	local m = world_mock(); local expected = finish(world_mock()); local elapsed, cargo_visits = 0, 0
	m.env.os.clock = function() return elapsed / 1000 end
	for i = 1, 100 do
		m.entities[200000 + i] = copy(m.entities[m.ca])
		m.entities[300000 + i] = { BASE_EDGE = copy(m.entities[m.edgeid].BASE_EDGE) }
	end
	local read = m.env.api.engine.getComponent
	m.env.api.engine.getComponent = function(id, ct)
		if ct == "CONSTRUCTION" or ct == "TOWN" or (ct == "PLAYER_OWNED" and id >= 300000) then elapsed = elapsed + 1 end
		return read(id, ct)
	end
	local enumerate = m.env.api.engine.forEachEntityWithComponent
	m.env.api.engine.forEachEntityWithComponent = function(fn, ct)
		if ct == "SIM_CARGO" then error("Cannot loop over this component type") end
		return enumerate(fn, ct)
	end
	m.env.api.engine.forEachEntity = function(fn)
		for _ = 1, 100000 do
			elapsed, cargo_visits = elapsed + 1, cargo_visits + 1
			fn(m.ca)
		end
	end
	local values, _, stats = finish(m)
	for _, field in ipairs({ "hcon", "hedge", "hcargo" }) do
		assert(not values[field] and stats[field]:find("budget", 1, true), tostring(stats[field]))
	end
	for _, field in ipairs({ "hline", "hveh", "hpos", "htown" }) do assert(values[field] == expected[field], field) end
	assert(cargo_visits > 0 and cargo_visits < 100000)
	assert(stats.capture_ms <= fingerprint.CAPTURE_MAX_MS and stats.calls <= fingerprint.CAPTURE_MAX_CALLS)
end)

test("one uninterruptible native call exceeding the total budget publishes no partial equality", function()
	local m = world_mock(); local elapsed = 0
	m.env.os.clock = function() return elapsed / 1000 end
	local enumerate = m.env.api.engine.getEntitiesWithComponent
	m.env.api.engine.getEntitiesWithComponent = function(ct, filters)
		local ids = enumerate(ct, filters)
		if ct == "CONSTRUCTION" then elapsed = elapsed + fingerprint.CAPTURE_MAX_MS + 1 end
		return ids
	end
	local values, missing, stats = finish(m)
	for _, field in ipairs(sync.HASH_FIELDS) do assert(values[field] == nil, field) end
	assert(#missing == #sync.HASH_FIELDS and stats.calls == 1)
	assert(stats.capture_ms == fingerprint.CAPTURE_MAX_MS + 1)
end)

test("capture and hashing obey hard native-call and byte-work budgets", function()
	local m = world_mock(); local budget = fingerprint.CAPTURE_MAX_CALLS
	fingerprint.CAPTURE_MAX_CALLS = 4
	local values, unreadable, stats = finish(m)
	fingerprint.CAPTURE_MAX_CALLS = budget
	assert(stats.calls <= 4 and #unreadable > 0)
	local bytes, records = fingerprint.HASH_BYTES_PER_STEP, fingerprint.HASH_RECORDS_PER_STEP
	fingerprint.HASH_BYTES_PER_STEP, fingerprint.HASH_RECORDS_PER_STEP = 32, 1
	local result, failed, measured = finish(m)
	fingerprint.HASH_BYTES_PER_STEP, fingerprint.HASH_RECORDS_PER_STEP = bytes, records
	assert(#failed == 0 and result.hpos and measured.steps > 20)
end)

test("oversized single construction params cannot monopolize a hash update", function()
	local m = world_mock()
	local modules = m.entities[m.ca].CONSTRUCTION.params_native.modules
	for i = 1, 3000 do modules[10000 + i] = { name = "::/large.module", variant = i } end
	local values, failed, stats = finish(m)
	assert(values.hcon == nil and stats.limited >= 1 and values.hpos)
end)

test("large diagnostic lists advertise their truncation and keep the true multiset count", function()
	local m = world_mock(); local limit = fingerprint.DETAIL_MAX_RECORDS
	fingerprint.DETAIL_MAX_RECORDS = 1
	local values, unreadable, stats, lists = finish(m)
	fingerprint.DETAIL_MAX_RECORDS = limit
	assert(#unreadable == 0 and values.hcon)
	assert(lists.hcon.total == 2 and lists.hcon.truncated and #lists.hcon == 1)
end)

test("all seven hashes plus exact time and economic checkpoint fit the native state", function()
	local values = finish(world_mock())
	values.gt, values.ck, values.money, values.loan, values.loanmanaged = 60000, 999999, -90000000000, 9999999999, 1
	values.lines, values.veh, values.st, values.con, values.date, values.adj = 99999, 99999, 99999, 99999, "2300-12-31", -90000000000
	assert(#sync.encode(values) <= 511, #sync.encode(values))
end)

test("TF3's non-enumerable components use complete alternative indexes", function()
	local m = world_mock(); local original = m.env.api.engine.getEntitiesWithComponent
	m.env.api.engine.getEntitiesWithComponent = function(c, filters)
		if c == "LINE" or c == "BASE_EDGE" or c == "SIM_CARGO" then error("Cannot loop over this component type") end
		return original(c, filters)
	end
	local baseline = finish(world_mock())
	local actual, missing = finish(m)
	assert(#missing == 0); same(baseline, actual)
	m.entities[m.lineid].NAME.name = "Changed line"
	m.entities[m.edgeid].BASE_EDGE.tangent1.y = 123
	m.entities[m.cargoid].SIM_CARGO.pickupTime = 56000
	local changed = finish(m)
	for _, field in ipairs({"hline","hedge","hcargo"}) do differs(actual,changed,field) end
end)

test("whole-entity cargo scan stops at the call budget and publishes no partial equality", function()
	local m = world_mock(); local called = 0
	local native = m.env.api.engine.forEachEntityWithComponent
	m.env.api.engine.forEachEntityWithComponent = function(fn, ct)
		if ct == "SIM_CARGO" then error("Cannot loop over this component type") end
		return native(fn, ct)
	end
	m.env.api.engine.forEachEntity = function(fn)
		for _ = 1, 100000 do called = called + 1; fn(m.ca) end
	end
	local values, missing, stats = finish(m)
	assert(values.hcargo == nil and values.hedge and values.hline and values.htown)
	assert(stats.calls <= fingerprint.CAPTURE_MAX_CALLS and called < 100000)
end)

test("a failing alternative index never becomes an empty successful world", function()
	local m = world_mock()
	m.env.api.engine.system.lineSystem.getLines = function() error("index unavailable") end
	m.env.api.engine.system.streetSystem.getNode2SegmentMap = function() error("index unavailable") end
	local values = finish(m)
	assert(not values.hline and not values.hedge and values.hcon)
end)

test("public roads do not consume the player-built road record limit", function()
	local m = world_mock(); local original = m.env.api.engine.system.streetSystem.getNode2SegmentMap
	local index = original()
	for i=1,fingerprint.STATIC_MAX_RECORDS+20 do
		local id=200000+i; m.entities[id]={BASE_EDGE=copy(m.entities[m.edgeid].BASE_EDGE)}
		index[id]={id,id}
	end
	m.env.api.engine.system.streetSystem.getNode2SegmentMap=function()return index end
	local values = finish(m); assert(values.hedge and values.hedge==finish(world_mock()).hedge)
end)

test("native one-based cargo vectors need neither pairs nor a valid zero index", function()
	local m = world_mock(); local expected = finish(m)
	local file = assert(io.tmpfile())
	local old = debug.getmetatable(file)
	debug.setmetatable(file, { __len=function()return 2 end,
		__index=function(_,k) if k==0 then error("index out of bounds") end; return ({3,4})[k] end,
		__pairs=function()error("native vector cannot be iterated with pairs")end })
	m.env.api.engine.util.cargo.getNumCargoPerTypeInVehicle=function()return file end
	local actual = finish(m)
	debug.setmetatable(file,old); file:close()
	assert(actual.hcargo and actual.hcargo==expected.hcargo)
end)

test("native stop configuration in a plain stops table remains readable", function()
	local m = world_mock(); local expected = finish(m)
	local c = copy(m.entities[m.lineid].LINE)
	local file = assert(io.tmpfile()); local mt = debug.getmetatable(file)
	local data = c.stops[1].stopConfig
	debug.setmetatable(file, {__index=function(_,k) return data[k] end})
	c.stops[1].stopConfig = file
	local read = m.env.api.engine.getComponent
	m.env.api.engine.getComponent = function(id,ct)
		if id==m.lineid and ct=="LINE" then return c end
		return read(id,ct)
	end
	local values, missing = finish(m)
	debug.setmetatable(file,mt); file:close()
	assert(values.hline and values.hline==expected.hline,table.concat(missing,","))
end)

test("a vehicle in its depot needs no driving position and keeps a semantic depot reference", function()
	local values = {}
	for i,m in ipairs({world_mock(),world_mock(10000,true)}) do
		local depot = m.ca+1000
		m.entities[m.ca].CONSTRUCTION.depots = {depot}; m.parents[depot]=m.ca
		local v = m.entities[m.vid].TRANSPORT_VEHICLE
		v.state,v.depot = "IN_DEPOT",depot; m.positions[m.vid]=nil
		values[i]=finish(m)
		assert(values[i].hpos)
		v.state="EN_ROUTE"; assert(not finish(m).hpos,"missing driving position must stay unreadable")
	end
	assert(values[1].hpos==values[2].hpos)
end)

test("native cargo indexes replace an unsupported iterator and deduplicate freight", function()
	local baseline
	for _,repeated in ipairs({false,true}) do
		local m=world_mock(); local e=m.env.api.engine; local native=e.forEachEntityWithComponent; local probes=0
		e.forEachEntityWithComponent=function(fn,ct)
			if ct=="SIM_CARGO" then probes=probes+1; error("Cannot loop over this component type") end
			return native(fn,ct)
		end
		e.forEachEntity=function()error("whole map must not be scanned")end
		e.system.simEntityAtStockSystem={getStock2SimEntityMap=function()return repeated and {x={m.cargoid,m.cargoid}} or {} end}
		e.system.simEntityAtVehicleSystem={getVehicle2Cargo2SimEntitesMap=function()return {[m.vid]={[1]={m.cargoid}}} end}
		local values,missing,stats,lists=finish(m)
		assert(values.hcargo and values.htown and stats.cargo_scope=="stocks_and_vehicles",table.concat(missing,","))
		assert(probes==0,"available native indexes must avoid the unsupported cargo iterator")
		if baseline then assert(values.hcargo==baseline) else baseline=values.hcargo end
		m.entities[m.cargoid].SIM_CARGO.pickupTime=58000
		differs(values,finish(m),"hcargo")
		e.system.simEntityAtStockSystem.getStock2SimEntityMap=function()error("unreadable native stock index")end
		assert(not finish(m).hcargo,"a failed stock index must not publish vehicle-only equality")
	end
end)

test("long routes use per-stop item bounds and retain the existing complete digest", function()
	local m = world_mock()
	local stops = m.entities[m.lineid].LINE.stops
	for i = 3, 16 do stops[i] = copy(stops[1 + i % 2]) end
	local expected = m.values().hline
	local values, missing = finish(m)
	assert(values.hline and values.hline == expected, table.concat(missing, ","))
	stops[16].stopConfig.maxLoad[0] = 0.25
	differs(values, finish(m), "hline")
end)

test("per-stop line validation retains the total byte and individual item limits", function()
	local m = world_mock()
	local stops = m.entities[m.lineid].LINE.stops
	for i = 3, 128 do stops[i] = copy(stops[1]) end
	local values, _, stats = finish(m)
	assert(not values.hline and stats.hline:find("byte limit", 1, true), tostring(stats.hline))
	m = world_mock()
	local load = m.entities[m.lineid].LINE.stops[1].stopConfig.load
	for i = 1, fingerprint.RECORD_MAX_ITEMS do load[i] = true end
	values, _, stats = finish(m)
	assert(not values.hline and stats.hline:find("record limit", 1, true), tostring(stats.hline))
end)

test("cargo resource lookups are reused only within the original checkpoint", function()
	local m = world_mock(); local reads = {}
	local get = m.env.api.res.cargoTypeRep.getName
	m.env.api.res.cargoTypeRep.getName = function(id)
		reads[id] = (reads[id] or 0) + 1
		return get(id)
	end
	for i = 1, 8 do m.entities[m.cargoid + i] = copy(m.entities[m.cargoid]) end
	assert(finish(m).hcargo)
	assert(reads[0] == 1 and reads[1] == 1)
	assert(finish(m).hcargo)
	assert(reads[0] == 2 and reads[1] == 2, "a later checkpoint must read fresh resources")
end)

test("empty cargo construction bounds use a validated placement anchor without foreign ids", function()
	local results = {}
	for i, m in ipairs({ world_mock(), world_mock(10000, true, 7) }) do
		local native = m.env.api.engine.getComponent
		m.env.api.engine.getComponent = function(id, ct)
			if id == m.ca and ct == "BOUNDING_VOLUME" then
				return { bbox = { min = xyz(math.huge, math.huge, math.huge), max = xyz(-math.huge, -math.huge, -math.huge) } }
			end
			return native(id, ct)
		end
		results[i] = finish(m)
		assert(results[i].hcargo)
		m.entities[m.ca].CONSTRUCTION.transf[4].x = 101
		differs(results[i], finish(m), "hcargo")
		m.entities[m.ca].CONSTRUCTION = nil
		local values, _, stats = finish(m)
		assert(not values.hcargo and stats.hcargo:find("cargo source position unreadable", 1, true), tostring(stats.hcargo))
	end
	assert(results[1].hcargo == results[2].hcargo)
end)

test("invalid cargo timestamps stay unknown and identify the unreadable field", function()
	for _, field in ipairs({ "startTime", "pickupTime" }) do
		for _, invalid in ipairs({ math.huge, -math.huge, 0 / 0 }) do
			local m = world_mock(); local native = m.env.api.engine.getComponent
			local cargo = copy(m.entities[m.cargoid].SIM_CARGO); cargo[field] = invalid
			m.env.api.engine.getComponent = function(id, ct)
				if id == m.cargoid and ct == "SIM_CARGO" then return cargo end
				return native(id, ct)
			end
			local values, _, stats = finish(m)
			assert(not values.hcargo and values.htown and stats.hcargo:find("cargo " .. field .. " unreadable", 1, true), tostring(stats.hcargo))
		end
	end
end)

print(string.format("%d fingerprint tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

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
	for _, field in ipairs(sync.HASH_FIELDS) do assert(values[field]:match("^h1_%x+$")) end
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

print(string.format("%d fingerprint tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

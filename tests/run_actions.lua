-- Additional actions against a mock using TF3's bundled command/type signatures.
-- Run from repository root: python tools/run_lua.py tests/run_actions.lua
local original_require = require
function require(path)
	if path:sub(1, 1) == "/" then return assert(loadfile("mods/mp_probe/content" .. path))() end
	return original_require(path)
end
local wire = require("/mp_probe/wire.lua")
local actions = require("/mp_probe/actions.lua")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function copy(v) return wire.copy(v) end
local function xyz(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
local function transform(x, y)
	return { { x = 1, y = 0, z = 0, w = 0 }, { x = 0, y = 1, z = 0, w = 0 },
		{ x = 0, y = 0, z = 1, w = 0 }, { x = x or 0, y = y or 0, z = 0, w = 1 } }
end
local function mock()
	local m = { entities = {}, sent = {}, next_id = 1000, logs = {} }
	local ct = {}; for _, k in ipairs({ "NAME", "COLOR", "PLAYER_OWNED", "CONSTRUCTION", "LINE",
		"TRANSPORT_VEHICLE", "STATION_GROUP", "BASE_EDGE", "EDGE_OBJECT", "STATION" }) do ct[k] = k end
	local function new() return {} end
	local function proposal() return { streetProposal = {} } end
	local t = { ComponentType = ct, Context = { new = new },
		SimpleProposal = { new = proposal, ConstructionEntity = { new = new } },
		Line = { new = new, Stop = { new = new }, StopConfig = { new = new } },
		LineVehicleInfo = { new = new }, VehiclePart = { new = new }, LoadConfig = { new = new },
		TransportVehiclePart = { new = new }, TransportVehicleConfig = { new = new },
		EdgeId = { new = new }, EdgePos = { new = new }, Waypoint = { new = new },
		StationTerminal = { new = function(s, terminal) return { station = s, terminal = terminal } end },
		Vec3f = { new = xyz }, Vec4f = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end },
		Mat4f = { cols = function(value, i) return copy(value[i]) end,
			new = function(a, b, c, d) return { a, b, c, d } end } }
	local engine = { util = { getPlayer = function() return 7 end }, system = {} }
	function engine.getComponent(id, c)
		assert(m.entities[id], "entity missing")
		-- Copy-on-read like the C++ bindings; a nested assignment must be written back.
		return m.entities[id][c] and copy(m.entities[id][c])
	end
	function engine.forEachEntityWithComponent(fn, c)
		if m.fail == c then error("simulated read failure") end
		for id, e in pairs(m.entities) do if e[c] then fn(id) end end
	end
	engine.system.lineSystem = { getLines = function()
		local list = {}; engine.forEachEntityWithComponent(function(id) list[#list + 1] = id end, "LINE"); return list
	end }
	engine.system.streetSystem = { getNode2SegmentMap = function()
		local map = {}; for id, e in pairs(m.entities) do if e.BASE_EDGE then map[id] = { id } end end; return map
	end }
	engine.system.streetConnectorSystem = {
		getConstructionEntityForDepot = function(id) return m.parents[id] end,
		getConstructionEntityForStation = function(id) return m.parents[id] end,
		getConstructionEntityForEdge = function() return -1 end,
	}
	engine.system.stationGroupSystem = { getStationGroup = function(id) return m.groups[id] end }
	local cmd = {}
	local signatures = { makeLineCreateCmd = 4, makeLineUpdateCmd = 2, makeLineDestroyCmd = 1,
		makeVehicleBuyCmd = 3, makeVehicleReplaceCmd = 2, makeVehicleSellCmd = 1,
		makeVehicleSetLineCmd = 3, makeVehicleSetStoppedByUserCmd = 2, makeVehicleSetManualDepartureCmd = 2,
		makeEntitySetNameCmd = 2, makeEntitySetColorCmd = 2, makeWorldBuildProposalCmd = 4 }
	for name, n in pairs(signatures) do
		cmd[name] = function(...)
			assert(select("#", ...) == n, name .. " signature")
			return { name = name, args = { ... } }
		end
	end
	local function base(id, name)
		m.entities[id] = { NAME = { name = name or "" }, PLAYER_OWNED = { player = 7 } }
		return m.entities[id]
	end
	m.parents, m.groups = {}, {}
	function m.construction(id, x, y, file, params)
		local e = base(id, "Station " .. id)
		e.CONSTRUCTION = { fileName = file or "::/station.con", params = params or { seed = 3, year = 1850, modules = {} },
			transf = transform(x, y), depots = { id + 10000 }, stations = { id + 20000 } }
		m.parents[id + 10000], m.parents[id + 20000], m.groups[id + 20000] = id, id, id + 30000
		m.entities[id + 30000] = { STATION_GROUP = { stations = { id + 20000 } } }
		return e
	end
	-- A street stop: a station without construction that is an edge object (run 19).
	function m.street_stop(id, x, y)
		local e = base(id, "Stop " .. id)
		e.EDGE_OBJECT = { param = 0.5, transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, 2, 1 } }
		e.STATION = { catchmentAreas = { { position = xyz(x, y, 2), radius = 100 } } }
		m.parents[id], m.groups[id] = -1, id + 30000
		m.entities[id + 30000] = { STATION_GROUP = { stations = { id } } }
		return e
	end
	function m.line(id, name, station)
		local e = base(id, name or ("Line " .. id))
		e.COLOR = { color = xyz(1, 0.3, 0.5) }
		e.LINE = { customFilters = true, reservationPriority = 2, vehicleInfo = { transportModes = { [0] = true, [1] = false } }, stops = {} }
		if station then
			e.LINE.stops = { { stationGroup = m.groups[station], station = 0, terminal = 1, loadMode = 2,
				minWaitingTime = 3, maxWaitingTime = 30, maxAdditionalWaitingTime = 5, waypoints = {},
				alternativeTerminals = { { station = 0, terminal = 2 } },
				stopConfig = { load = { [0] = true, [1] = false }, maxLoad = { [0] = 1, [1] = 0.3 },
					forceUnload = true, destroyForConfigChange = false, destroyForRefresh = true } } }
		end
		return e
	end
	function m.config()
		return { vehicles = { { part = { modelId = 5, reversed = true,
			compartment2loadConfig = { [0] = -1 }, color = xyz(0.4, 0.5, 0.6) }, autoLoadConfig = { [0] = true } } },
			vehicleGroups = { 1 }, muFileNames = { "" } }
	end
	function m.vehicle(id, depot, line)
		local e = base(id, "Bus " .. id)
		e.TRANSPORT_VEHICLE = { transportVehicleConfig = m.config(), depot = depot or -1, line = line or -1,
			userStopped = false, autoDeparture = true, stopIndex = 0 }
		return e
	end
	function m.edge(id, x, y)
		local e = base(id)
		e.BASE_EDGE = { position0 = xyz(x, y), position1 = xyz(x + 10, y), tangent0 = xyz(10),
			tangent1 = xyz(10), roadTemplate = "::/small.street_template", roadStyle = "::/old.street" }
		return e
	end
	local function execute(c, callback)
		assert(not m.in_callback, "sendCommand called from a native callback")
		local a, result = c.args, {}
		m.sent[#m.sent + 1] = c
		if m.reject then callback({}, false); return end
		if c.name == "makeWorldBuildProposalCmd" then
			assert(a[4] == false, "remote builds must not be playerInitiated")
			local p = a[1]
			for _, id in ipairs(p.constructionsToRemove or {}) do m.entities[id] = nil end
			for _, id in ipairs(p.streetProposal.edgesToRemove or {}) do m.entities[id] = nil end
			for _, con in ipairs(p.constructionsToAdd or {}) do
				m.next_id = m.next_id + 1
				local e = m.construction(m.next_id, con.transf[4].x, con.transf[4].y, con.fileName, con.params)
				e.CONSTRUCTION.transf, e.NAME.name = copy(con.transf), con.name
				result.resultEntities = { { m.next_id, 1 } }
			end
		elseif c.name == "makeLineCreateCmd" then
			m.next_id = m.next_id + 1; local e = m.line(m.next_id, a[1])
			e.LINE, e.COLOR.color = copy(a[4]), copy(a[2]); result.resultEntity = m.next_id
		elseif c.name == "makeLineUpdateCmd" then m.entities[a[1]].LINE = copy(a[2])
		elseif c.name == "makeLineDestroyCmd" then m.entities[a[1]] = nil
		elseif c.name == "makeVehicleBuyCmd" then
			m.next_id = m.next_id + 1; local e = m.vehicle(m.next_id, a[2])
			e.TRANSPORT_VEHICLE.transportVehicleConfig = copy(a[3]); result.resultVehicleEntity = m.next_id
		elseif c.name == "makeVehicleReplaceCmd" then m.entities[a[1]].TRANSPORT_VEHICLE.transportVehicleConfig = copy(a[2])
		elseif c.name == "makeVehicleSellCmd" then for _, id in ipairs(a[1]) do m.entities[id] = nil end
		elseif c.name == "makeVehicleSetLineCmd" then m.entities[a[1]].TRANSPORT_VEHICLE.line = a[2]
		elseif c.name == "makeVehicleSetStoppedByUserCmd" then m.entities[a[1]].TRANSPORT_VEHICLE.userStopped = a[2]
		elseif c.name == "makeVehicleSetManualDepartureCmd" then m.entities[a[1]].TRANSPORT_VEHICLE.autoDeparture = not a[2]
		elseif c.name == "makeEntitySetNameCmd" then m.entities[a[1]].NAME.name = a[2]
		elseif c.name == "makeEntitySetColorCmd" then m.entities[a[1]].COLOR.color = copy(a[2]) end
		m.in_callback = true
		callback(result, true)
		m.in_callback = false
	end
	cmd.sendCommand = function(c, callback)
		if m.defer then m.pending = { c, callback } else execute(c, callback) end
	end
	function m.complete()
		local p = m.pending; m.pending = nil; execute(p[1], p[2])
	end
	m.env = { api = { type = t, cmd = cmd, engine = engine,
		res = { modelRep = { getName = function(id) assert(id == 5 or id == 77); return "::/bus.mdl" end,
			find = function(name) return name == "::/bus.mdl" and 77 or -1 end } } } }
	local saved = {}
	m.state = { get = function() return copy(saved) end, set = function(_, s) saved = copy(s) end }
	function m.poll()
		local s = m.state:get(); actions.poll(m.env, s, function(msg) m.logs[#m.logs + 1] = msg end); m.state:set(s)
	end
	function m.drain()
		local s, out = m.state:get(), {}
		while true do local line = actions.next_line(s); if not line then break end; out[#out + 1] = assert(actions.decode(line)) end
		m.state:set(s); return out
	end
	function m.replay(action, offset)
		local ok = actions.replay(m.env, copy(action), m.state, "sender", offset or 0,
			function(msg) m.logs[#m.logs + 1] = msg end)
		if not m.defer then m.finish() end
		return ok
	end
	function m.finish()
		while #(m.state:get().action_work or {}) > 0 do
			actions.continue(m.env, m.state, function(msg) m.logs[#m.logs + 1] = msg end)
		end
	end
	return m
end

test("wire preserves nested sparse modular params, booleans, unicode and log control chars", function()
	local v = { name = "Bahnhof ä\n[mp_probe]net send bad\0", modules = { [0] = false, [27001] = { seed = 42 } }, n = 1.23456789 }
	local text = wire.encode(v); assert(not text:find("\n", 1, true)); assert(wire.encode(assert(wire.decode(text))) == text)
end)
test("wire rejects code, malformed/duplicate keys, huge strings, cycles and non-finite numbers", function()
	for _, v in ipairs({ "os.execute('bad')", "t1:s2:zzn", "t999999:", "dnan;", "d1;extra", "t2:s2:61ns2:61y" }) do
		assert(wire.decode(v) == nil, v)
	end
	assert(not pcall(wire.encode, string.rep("a", 17000)))
	local t = {}; t.self = t; assert(not pcall(wire.encode, t)); assert(not pcall(wire.encode, math.huge))
end)
test("loading an existing save only creates baselines", function()
	local m = mock(); m.construction(10, 0, 0); m.line(20); m.vehicle(30, 10010); m.edge(40, 0, 0)
	m.poll(); assert(#m.drain() == 0)
end)
test("construction capture keeps complete modular parameters and transformation", function()
	local m = mock(); m.poll(); m.construction(10, 12, 25, nil, { modules = { [10023] = { variant = 3 } }, seed = 28, year = 1900 })
	m.poll(); local a = m.drain()[1]; assert(a.op == "construction_create")
	assert(a.value.data.params.modules[10023].variant == 3 and a.value.data.transf[4].x == 12)
end)
test("new depot, line and purchased vehicle are queued in dependency order", function()
	local m = mock(); m.poll(); m.construction(10, 0, 0); m.line(20, "A", 20010); m.vehicle(30, 10010, 20)
	m.poll(); local q = m.drain(); assert(#q == 3 and q[1].op == "construction_create" and q[2].op == "line_create" and q[3].op == "vehicle_create")
end)
test("motion, normal stop progression and depot departure do not generate actions", function()
	local m = mock(); local e = m.vehicle(30); m.poll()
	e.TRANSPORT_VEHICLE.stopIndex, e.TRANSPORT_VEHICLE.depot = 12, -1; m.poll(); assert(#m.drain() == 0)
end)
test("failed reads preserve prior baseline and never synthesize sales", function()
	local m = mock(); m.vehicle(30); m.poll(); m.fail = "TRANSPORT_VEHICLE"; m.poll()
	assert(#m.drain() == 0 and m.state:get().actions.snapshots.vehicle["30"])
end)
test("demolition/sale removes dependents before their depot and preserves source refs", function()
	local m = mock(); m.construction(10, 0, 0); m.line(20); m.vehicle(30, 10010); m.edge(40, 0, 0); m.poll()
	m.entities[10], m.entities[20], m.entities[30], m.entities[40] = nil, nil, nil, nil
	m.poll(); local q = m.drain(); assert(q[1].op == "vehicle_remove" and q[2].op == "line_remove" and q[3].op == "edge_remove" and q[4].op == "construction_remove")
end)
test("construction copy binds new local ID and does not echo in next snapshot", function()
	local source, dest = mock(), mock(); source.poll(); source.construction(10, 12, 25); source.poll()
	local action = source.drain()[1]; dest.poll(); dest.replay(action, 40)
	local id = dest.state:get().action_entities["sender:construction:10"]
	assert(id ~= 10 and dest.entities[id].CONSTRUCTION.transf[4].y == 65)
	dest.poll(); assert(#dest.drain() == 0)
	dest.replay({ op = "construction_remove", targets = { action.value.ref } }, 40)
	assert(dest.entities[id] == nil); dest.poll(); assert(#dest.drain() == 0)
end)
test("construction edits use complete replacement and old2new mapping", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.poll(); dest.poll(); source.entities[10].CONSTRUCTION.params.modules[31] = { variant = 2 }; source.poll()
	local a = source.drain()[1]; assert(a.op == "construction_update"); dest.replay(a)
	local p = dest.sent[1].args[1]; assert(p.constructionsToRemove[1] == 91 and p.old2new[91] == 0)
	dest.poll(); assert(#dest.drain() == 0)
end)
test("lines recreate stops, cargo rules, alternatives and differing station entity IDs", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.poll(); dest.poll(); source.line(20, "Passenger", 20010); source.poll(); dest.replay(source.drain()[1])
	local l = dest.entities[1001].LINE; assert(l.stops[1].stationGroup == 30091)
	assert(l.stops[1].stopConfig.load[0] and l.stops[1].stopConfig.maxLoad[1] == 0.3)
	assert(l.stops[1].stopConfig.destroyForConfigChange == false)
	assert(l.stops[1].alternativeTerminals[1].terminal == 2 and l.vehicleInfo.transportModes[0])
	dest.poll(); assert(#dest.drain() == 0)
end)
test("station indexes are remapped when group ordering differs", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); source.construction(11, 22, 25)
	dest.construction(91, 12, 25); dest.construction(92, 22, 25)
	source.entities[30010].STATION_GROUP.stations = { 20010, 20011 }; source.groups[20011] = 30010
	dest.entities[30091].STATION_GROUP.stations = { 20092, 20091 }; dest.groups[20092] = 30091
	source.poll(); dest.poll(); source.line(20, "A", 20010); source.poll(); dest.replay(source.drain()[1])
	assert(dest.entities[1001].LINE.stops[1].station == 1)
	assert(dest.entities[1001].LINE.stops[1].alternativeTerminals[1].station == 1)
end)
test("vehicle buy resolves local depot and model IDs, then applies line and user settings", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.line(20, "A"); dest.line(92, "A"); source.poll(); dest.poll()
	local e = source.vehicle(30, 10010, 20); e.TRANSPORT_VEHICLE.userStopped = true; e.TRANSPORT_VEHICLE.autoDeparture = false
	source.poll(); dest.replay(source.drain()[1]); local v = dest.entities[1001].TRANSPORT_VEHICLE
	assert(dest.sent[1].args[2] == 10091 and v.transportVehicleConfig.vehicles[1].part.modelId == 77)
	assert(v.line == 92 and v.userStopped and not v.autoDeparture)
	dest.poll(); assert(#dest.drain() == 0)
end)
test("street stops travel by position and resolve to the local stop (run 19)", function()
	local source, dest = mock(), mock(); source.street_stop(40, 100, 200); dest.street_stop(77, 100, 300)
	source.poll(); dest.poll(); source.line(20, "Bus", 40); source.poll()
	local out = source.drain(); assert(#out == 1 and out[1].op == "line_create", "line not captured")
	local ref = out[1].value.data.stops[1].target.stations[1]
	assert(ref.kind == "street_station" and ref.position.y == 200 and ref.how == "edge_object")
	dest.replay(out[1], 100)
	assert(dest.entities[1001].LINE.stops[1].stationGroup == 30077, "line not on the local stop")
end)
test("a street stop that is too far away is not taken", function()
	local source, dest = mock(), mock(); source.street_stop(40, 100, 200); dest.street_stop(77, 110, 200)
	source.poll(); dest.poll(); source.line(20, "Bus", 40); source.poll()
	local ok, err = pcall(dest.replay, source.drain()[1], 0)
	assert(not ok and tostring(err):find("street stop near", 1, true), tostring(err))
	assert(#dest.sent == 0)
end)
test("an unreadable line is reported once with its error, not every poll", function()
	local source = mock(); source.poll(); source.line(20, "Broken", 999); source.poll(); source.poll()
	local n = 0
	for _, msg in ipairs(source.logs) do
		if msg:find("unreadable", 1, true) then
			n = n + 1
			assert(msg:find("first: 20:", 1, true), msg)
		end
	end
	assert(n == 1, "logged " .. n .. " times")
end)
test("a bus bought without a line gets no SetLine with -1 (run 19)", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.poll(); dest.poll(); source.vehicle(30, 10010); source.poll(); dest.replay(source.drain()[1])
	for _, c in ipairs(dest.sent) do assert(c.name ~= "makeVehicleSetLineCmd", "SetLine sent") end
	assert(dest.entities[1001].TRANSPORT_VEHICLE.line == -1)
end)
test("vehicle sales use semantic local ID rather than sender ID", function()
	local source, dest = mock(), mock(); source.vehicle(30); dest.vehicle(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll(); source.entities[30] = nil; source.poll(); dest.replay(source.drain()[1])
	assert(dest.sent[1].args[1][1] == 90); dest.poll(); assert(#dest.drain() == 0)
end)
test("vehicle rename/start updates bind same vehicle despite different IDs", function()
	local source, dest = mock(), mock(); source.vehicle(30); dest.vehicle(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll(); source.entities[30].NAME.name = "Express"; source.entities[30].TRANSPORT_VEHICLE.userStopped = true
	source.poll(); dest.replay(source.drain()[1]); assert(dest.entities[90].NAME.name == "Express")
	assert(dest.entities[90].TRANSPORT_VEHICLE.userStopped); dest.poll(); assert(#dest.drain() == 0)
end)
test("ambiguous destructive targets send no command", function()
	local m = mock(); m.line(10, "Duplicate"); m.line(11, "Duplicate"); m.poll()
	assert(not pcall(m.replay, { op = "line_remove", targets = { { kind = "line", key = "99", name = "Duplicate" } } }))
	assert(#m.sent == 0)
end)
test("all demolition targets resolve before any command is sent", function()
	local m = mock(); m.line(10, "A"); m.poll()
	assert(not pcall(m.replay, { op = "line_remove", targets = {
		{ kind = "line", key = "99", name = "A" }, { kind = "line", key = "100", name = "Missing" } } }))
	assert(#m.sent == 0)
end)
test("edge demolition resolves positions, shape and local ID", function()
	local source, dest = mock(), mock(); source.edge(40, 0, 0); dest.edge(90, 0, 0)
	source.poll(); dest.poll(); source.entities[40] = nil; source.poll(); dest.replay(source.drain()[1])
	assert(dest.sent[1].args[1].streetProposal.edgesToRemove[1] == 90); dest.poll(); assert(#dest.drain() == 0)
end)
test("loopback edge demolition uses the road replay's perpendicular offset", function()
	local source, dest = mock(), mock(); source.edge(40, 0, 0); dest.edge(90, -15, 32)
	source.poll(); dest.poll(); local s = dest.state:get(); s.edge_loop_offsets = { ["40"] = { x = -15, y = 32 } }; dest.state:set(s)
	source.entities[40] = nil; source.poll(); dest.replay(source.drain()[1], 40)
	assert(dest.entities[90] == nil)
end)
test("rejected construction keeps baseline and does not bind a nonexistent entity", function()
	local source, dest = mock(), mock(); source.poll(); source.construction(10, 12, 25); source.poll(); dest.poll(); dest.reject = true
	dest.replay(source.drain()[1]); assert(not dest.state:get().action_entities)
	assert(dest.logs[#dest.logs]:find("rejected by game", 1, true))
end)
test("async callback uses current script state rather than a stale captured table", function()
	local source, dest = mock(), mock(); source.poll(); source.construction(10, 12, 25); source.poll(); dest.poll(); dest.defer = true
	dest.replay(source.drain()[1]); local s = dest.state:get(); s.unrelated = 123; dest.state:set(s); dest.complete()
	assert(dest.state:get().unrelated == 123 and dest.state:get().action_entities["sender:construction:10"])
end)
test("missing models or dependencies reject a purchase before sending commands", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); source.poll(); source.vehicle(30, 10010); source.poll()
	assert(not pcall(dest.replay, source.drain()[1])); assert(#dest.sent == 0)
end)
test("unknown protocol versions and operation names are rejected", function()
	assert(actions.decode("A2 t0:") == nil)
	local m = mock(); assert(not pcall(m.replay, { op = "do_anything" })); assert(#m.sent == 0)
end)

test("standalone false values survive field extraction and copying", function()
	assert(wire.copy(false) == false)
	local m = mock(); m.line(20); m.entities[20].LINE.customFilters = false
	assert(actions.snapshot(m.env, "line")["20"].data.customFilters == false)
end)
test("station upgrade replacing its ID is one replacement, rather than overlapping build plus demolition", function()
	local m = mock(); m.construction(10, 12, 25); m.poll(); m.entities[10] = nil
	m.construction(11, 12, 25, nil, { modules = { [99] = { variant = 7 } } }); m.poll()
	local q = m.drain(); assert(#q == 1 and q[1].op == "construction_update")
	assert(q[1].target.key == "10" and q[1].value.ref.key == "11")
end)
test("mixed street graph rewrite cannot send only the destructive half", function()
	local m = mock(); m.edge(40, 0, 0); m.poll(); m.entities[40] = nil; m.edge(41, 0, 0); m.poll()
	assert(#m.drain() == 0 and m.logs[#m.logs]:find("mixed edit", 1, true))
end)
test("line edits and renames apply through separate simulation commands without echoes", function()
	local source, dest = mock(), mock(); source.line(20, "A"); dest.line(90, "A"); source.poll(); dest.poll()
	source.entities[20].LINE.reservationPriority = 7
	source.entities[20].NAME.name = "B"; source.entities[20].COLOR.color = xyz(0.2, 0.6, 0.9)
	source.poll(); dest.replay(source.drain()[1]); assert(#dest.sent == 3)
	assert(dest.entities[90].LINE.reservationPriority == 7 and dest.entities[90].NAME.name == "B")
	assert(dest.entities[90].COLOR.color.x == 0.2); dest.poll(); assert(#dest.drain() == 0)
end)
test("waypoints on streets use destination edge IDs", function()
	local source, dest = mock(), mock(); source.construction(10, 0, 0); dest.construction(91, 0, 0)
	source.edge(40, 0, 0); dest.edge(92, 0, 0); source.poll(); dest.poll()
	local l = source.line(20, "A", 20010).LINE
	l.stops[1].waypoints = { { edgePos = { edgeId = { entity = 40, index = 2 }, param = 0.6 }, tag = 3 } }
	source.poll(); dest.replay(source.drain()[1])
	assert(dest.entities[1001].LINE.stops[1].waypoints[1].edgePos.edgeId.entity == 92)
end)
test("unknown vehicle resources fail before the purchase command", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.poll(); source.vehicle(30, 10010); source.poll(); local a = source.drain()[1]
	a.value.config.vehicles[1].model = "::/missing.mdl"
	assert(not pcall(dest.replay, a) and #dest.sent == 0)
end)
test("incoming actions wait for an asynchronous buy and its follow-up settings", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.poll(); dest.poll(); source.vehicle(30, 10010); source.poll(); local buy = source.drain()[1]
	actions.receive(dest.state, buy, "sender", 0)
	actions.receive(dest.state, { op = "vehicle_remove", targets = { buy.value.ref } }, "sender", 0)
	dest.defer = true; actions.tick(dest.env, dest.state, function() end)
	assert(dest.state:get().action_busy and not actions.has_work(dest.state:get()))
	actions.tick(dest.env, dest.state, function() end); assert(#dest.state:get().action_inbox == 1)
	dest.complete(); dest.defer = false
	while actions.has_work(dest.state:get()) do actions.tick(dest.env, dest.state, function() end) end
	assert(dest.entities[1001] == nil and dest.sent[#dest.sent].name == "makeVehicleSellCmd")
end)
test("main routes A1 lines into persisted simulation work, leaving the B3 parser intact", function()
	local source, dest = mock(), mock(); source.poll(); source.construction(10, 12, 25); source.poll()
	local frame = actions.encode(source.drain()[1])
	assert(loadfile("mods/mp_probe/content/mp_probe/main.script.lua"))(); local main = data()
	local old_api, old_debug = api, debugPrint
	api, debugPrint = dest.env.api, function() end
	local ok, err = pcall(function()
		main.replay_line(dest.env, frame, "sender.1", dest.state, 0)
		assert(#dest.sent == 0 and #dest.state:get().action_inbox == 1)
		main.handleEvent(nil, dest.state, "mp_probe", "mp_probe_replay", "mp_probe_replay", { action_work = true })
		assert(dest.entities[1001] and #dest.state:get().action_inbox == 0)
	end)
	api, debugPrint = old_api, old_debug
	assert(ok, err)
end)
test("an ownership read failure never synthesizes demolition", function()
	local m = mock(); m.construction(10, 0, 0); m.poll()
	local get_component = m.env.api.engine.getComponent
	m.env.api.engine.getComponent = function(id, ct)
		if ct == "PLAYER_OWNED" then error("ownership unavailable") end
		return get_component(id, ct)
	end
	m.poll(); assert(#m.drain() == 0 and m.state:get().actions.snapshots.construction["10"])
end)
test("loading a save clears stale native work and forces new baselines", function()
	local m = mock(); m.poll(); local s = m.state:get()
	s.action_work = { { command = "remove_line", id = 99 } }; s.action_inbox = { { action = { op = "vehicle_remove" } } }
	s.action_busy, s.action_work_requested = true, true; m.state:set(s)
	assert(loadfile("mods/mp_probe/content/mp_probe/main.script.lua"))(); local main = data()
	local old_debug = debugPrint; debugPrint = function() end
	local ok, err = pcall(main.handleEvent, nil, m.state, "", "", "handleLegacy", nil)
	debugPrint = old_debug; assert(ok, err)
	local current = m.state:get(); assert(not current.actions and not current.action_busy and not current.action_work_requested)
	assert(not current.action_work and not current.action_inbox)
end)
test("main dispatch does not overwrite mappings or busy flags from an immediate event", function()
	local source, dest = mock(), mock(); source.poll(); source.construction(10, 12, 25); source.poll(); dest.poll()
	assert(loadfile("mods/mp_probe/content/mp_probe/main.script.lua"))(); local main = data()
	local old_api, old_debug = api, debugPrint; api, debugPrint = dest.env.api, function() end
	local s = dest.state:get()
	s.probe_version, s.subscribed, s.replay_version, s.actions_version = 13, 13, 13, 13
	s.updates = 1; dest.state:set(s)
	local native_send = dest.env.api.cmd.sendCommand
	dest.env.api.cmd.makeScriptingSendEventCmd = function(src, id, name, param)
		return { script = { src, id, name, param } }
	end
	dest.env.api.cmd.sendCommand = function(c, callback)
		if c.script then main.handleEvent(nil, dest.state, c.script[1], c.script[2], c.script[3], c.script[4])
		else native_send(c, callback) end
	end
	local ok, err = pcall(function()
		main.replay_line(dest.env, actions.encode(source.drain()[1]), "sender.1", dest.state, 0)
		main.update(nil, dest.state, 0)
		assert(dest.state:get().action_entities["sender:construction:10"] == 1001)
		assert(not dest.state:get().action_work_requested and not dest.state:get().action_busy)
	end)
	api, debugPrint = old_api, old_debug; assert(ok, err)
end)
test("the installed mod manifest includes every required action module", function()
	local f = assert(io.open("mods/mp_probe/_content.json", "r")); local manifest = f:read("*a"); f:close()
	for _, name in ipairs({ "actions.lua", "wire.lua", "build.lua", "world.lua", "weld.lua", "nodecfg.lua" }) do
		assert(manifest:find('"mp_probe/' .. name .. '"', 1, true), name .. " missing from manifest")
		local file = assert(io.open("mods/mp_probe/content/mp_probe/" .. name, "r")); file:close()
	end
end)

print(string.format("%d action tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

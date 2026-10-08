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
local fixture = assert(loadfile("tests/fixtures/actions_env.lua"))({ wire = wire, actions = actions })
local mock, copy, xyz = fixture.mock, fixture.copy, fixture.xyz

test("wire preserves nested sparse modular params, booleans, unicode and log control chars", function()
	local v = { name = "Bahnhof ä\n[mp_probe]net send bad\0", modules = { [0] = false, [27001] = { seed = 42 } }, n = 1.23456789 }
	local text = wire.encode(v); assert(not text:find("\n", 1, true)); assert(wire.encode(assert(wire.decode(text))) == text)
end)
test("wire rejects code, malformed/duplicate keys, huge strings, cycles and non-finite numbers", function()
	for _, v in ipairs({ "os.execute('bad')", "t1:s2:zzn", "t999999:", "dnan;", "d1;extra", "t2:s2:61ns2:61y" }) do
		assert(wire.decode(v) == nil, v)
	end
	assert(not pcall(wire.encode, string.rep("a", wire.MAX_BYTES)))
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
test("assigning a purchased train preserves its reachable destination stop and user settings", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.line(20, "A"); dest.line(92, "A"); source.poll(); dest.poll()
	local vehicle = source.vehicle(30, 10010).TRANSPORT_VEHICLE
	source.poll(); dest.replay(source.drain()[1])
	-- Stop 0 cannot be reached from this depot; the original UI chose stop 1.
	dest.required_stop = 1
	vehicle.line, vehicle.stopIndex, vehicle.userStopped, vehicle.autoDeparture = 20, 1, true, false
	source.poll(); local q = source.drain()
	assert(#q == 1 and q[1].op == "vehicle_update" and q[1].value.stopIndex == 1)
	local before = #dest.sent; dest.replay(q[1])
	local copied = dest.entities[1001].TRANSPORT_VEHICLE
	assert(copied.line == 92 and copied.stopIndex == 1 and copied.userStopped and not copied.autoDeparture)
	assert(dest.sent[before + 1].name == "makeVehicleSetLineCmd" and dest.sent[before + 1].args[3] == 1)
	assert(dest.sent[before + 2].name == "makeVehicleSetStoppedByUserCmd")
	assert(dest.sent[before + 3].name == "makeVehicleSetManualDepartureCmd")
	dest.poll(); assert(#dest.drain() == 0, "assignment echoed")
	vehicle.stopIndex = 0; source.poll(); assert(#source.drain() == 0, "normal stop progression sent an action")
end)
test("a train bought with an assigned line keeps its stop through persisted follow-up work", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.line(20, "A"); dest.line(92, "A"); source.poll(); dest.poll()
	source.vehicle(30, 10010, 20).TRANSPORT_VEHICLE.stopIndex = 1
	source.poll(); local action = source.drain()[1]
	dest.required_stop, dest.defer = 1, true; dest.replay(action)
	dest.complete(); dest.defer = false; dest.finish()
	local copied = dest.entities[1001].TRANSPORT_VEHICLE
	assert(copied.line == 92 and copied.stopIndex == 1)
end)
test("vehicle line payloads from before v28 retain stop 0 as their fallback", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.line(20, "A"); dest.line(92, "A"); source.poll(); dest.poll()
	source.vehicle(30, 10010, 20); source.poll(); local action = source.drain()[1]
	action.value.stopIndex = nil; dest.required_stop = 0; dest.replay(action)
	assert(dest.entities[1001].TRANSPORT_VEHICLE.line == 92 and dest.entities[1001].TRANSPORT_VEHICLE.stopIndex == 0)
end)
test("rejected vehicle line settings report the target vehicle, line and stop", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.line(20, "A"); dest.line(92, "A"); source.poll(); dest.poll()
	source.vehicle(30, 10010, 20); source.poll(); dest.required_stop = 1; dest.replay(source.drain()[1])
	local message = dest.logs[#dest.logs]
	assert(message:find("line rejected by game (vehicle=1001, line=92, stop=0)", 1, true), message)
	assert(dest.entities[1001].TRANSPORT_VEHICLE.line == -1, "rejected assignment changed the line")
	assert(#dest.state:get().action_work == 0, "dependent settings survived rejection")
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
test("a vehicle update carries only what the receiver compares, and a new train set replaces the vehicle (v26)", function()
	local source, dest = mock(), mock(); source.vehicle(30); dest.vehicle(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll()
	source.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].part.reversed = false
	source.poll(); local q = source.drain(); assert(#q == 1 and q[1].op == "vehicle_update")
	local prev = q[1].previous
	assert(prev.config == nil and prev.config_changed == true and prev.name == "Bus 30" and prev.autoDeparture == true)
	dest.replay(q[1])
	assert(dest.sent[1].name == "makeVehicleReplaceCmd" and dest.sent[1].args[1] == 90)
	assert(dest.entities[90].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].part.reversed == false)
	-- A start/stop alone replaces nothing.
	source.entities[30].TRANSPORT_VEHICLE.userStopped = true; source.poll(); q = source.drain()
	assert(#q == 1 and q[1].previous.config_changed == false)
	local before = #dest.sent; dest.replay(q[1])
	for i = before + 1, #dest.sent do assert(dest.sent[i].name ~= "makeVehicleReplaceCmd", "replaced") end
	assert(dest.entities[90].TRANSPORT_VEHICLE.userStopped)
	-- An update from before v26 still carries the whole previous record.
	local old = copy(q[1]); old.previous = { name = "Bus 30", userStopped = false, autoDeparture = true,
		config = copy(q[1].value.config) }
	before = #dest.sent; dest.replay(old)
	for i = before + 1, #dest.sent do assert(dest.sent[i].name ~= "makeVehicleReplaceCmd", "replaced (old format)") end
end)
test("renaming a line sends the line, not each of its vehicles again (v26)", function()
	local m = mock(); m.line(20, "A"); m.vehicle(30, nil, 20); m.vehicle(31, nil, 20); m.poll()
	m.entities[20].NAME.name = "Express"; m.poll()
	local q = m.drain(); assert(#q == 1 and q[1].op == "line_update", #q .. " actions")
	-- Moving a vehicle to another line is still sent.
	m.line(21, "B"); m.poll(); m.drain()
	m.entities[31].TRANSPORT_VEHICLE.line = 21; m.poll(); q = m.drain()
	assert(#q == 1 and q[1].op == "vehicle_update" and q[1].value.line.key == "21")
end)
test("a vehicle that cannot travel is reported and left out; the others still go and nothing stalls (v26)", function()
	local m = mock(); m.construction(10, 0, 0); m.poll()
	-- Bought and gone from its depot before the poll saw it: the purchase cannot be copied.
	m.vehicle(30); m.vehicle(31, 10010); m.poll()
	local q = m.drain(); assert(#q == 1 and q[1].op == "vehicle_create" and q[1].value.ref.key == "31", #q .. " actions")
	local reported = 0
	for _, msg in ipairs(m.logs) do
		if msg:find("action NOT sent, vehicle Bus 30: left its depot before it was seen", 1, true) then reported = reported + 1 end
	end
	assert(reported == 1, table.concat(m.logs, "\n"))
	-- Reported once, not on every poll.
	m.poll(); m.drain(); local again = 0
	for _, msg in ipairs(m.logs) do if msg:find("action NOT sent, vehicle Bus 30", 1, true) then again = again + 1 end end
	assert(again == 1, again .. " reports")
	-- The snapshot moved on: the next change of either vehicle is sent.
	m.entities[30].NAME.name = "Late"; m.entities[31].TRANSPORT_VEHICLE.userStopped = true; m.poll()
	q = m.drain(); assert(#q == 2 and q[1].op == "vehicle_update" and q[2].op == "vehicle_update", #q .. " actions")
	-- A record too long for the DLL is reported the same way. The mock reads and stores through its
	-- own copy of wire.lua, which gets room for it; the game has no such limit there.
	local limit = wire.MAX_BYTES
	wire.MAX_BYTES = 16000000
	m.entities[31].NAME.name = string.rep("x", limit); m.poll()
	q = m.drain()
	wire.MAX_BYTES = limit
	assert(#q == 0, #q .. " actions")
	assert(m.logs[#m.logs]:find("action NOT sent, vehicle", 1, true) and m.logs[#m.logs]:find("DLL line limit", 1, true), m.logs[#m.logs])
	wire.MAX_BYTES = 16000000
	m.entities[30].TRANSPORT_VEHICLE.userStopped = true; m.poll()
	q = m.drain()
	wire.MAX_BYTES = limit
	assert(#q == 1 and q[1].value.ref.key == "30")
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
test("station demolition keeps the empty local line slot and allows subsequent line edits and renaming", function()
	local source, dest = mock(), mock()
	source.construction(10, 12, 25); source.construction(11, 22, 25)
	dest.construction(91, 12, 25); dest.construction(92, 22, 25)
	source.line(20, "A", 20010); dest.line(90, "A", 20091)
	source.entities[20].LINE.stops[2] = copy(source.entities[20].LINE.stops[1])
	source.entities[20].LINE.stops[2].stationGroup = 30011
	dest.entities[90].LINE.stops[2] = copy(dest.entities[90].LINE.stops[1])
	dest.entities[90].LINE.stops[2].stationGroup = 30092
	source.poll(); dest.poll()
	-- The engine keeps the deleted station's empty group and invalidates its line slot.
	source.entities[10] = nil; source.entities[30010].STATION_GROUP.stations = {}
	source.entities[20].LINE.stops[1].station, source.entities[20].LINE.stops[1].terminal = -1, -1
	source.entities[20].LINE.stops[1].alternativeTerminals = {}
	source.entities[20].NAME.name = "After demolition"
	source.entities[20].LINE.reservationPriority = 7
	source.poll(); local q = source.drain()
	assert(#q == 2 and q[1].op == "line_update" and q[2].op == "construction_remove")
	-- In-game the B5 demolition is sent by the build event before the polled A1 change.
	dest.replay(q[2]); dest.entities[30091].STATION_GROUP.stations = {}
	dest.entities[90].LINE.stops[1].station, dest.entities[90].LINE.stops[1].terminal = -1, -1
	dest.entities[90].LINE.stops[1].alternativeTerminals = {}
	dest.replay(q[1])
	local line = dest.entities[90].LINE
	assert(#line.stops == 2 and line.stops[1].stationGroup == 30091)
	assert(line.stops[1].station == -1 and line.stops[1].terminal == -1)
	assert(line.stops[2].stationGroup == 30092 and line.stops[2].station == 0)
	assert(line.reservationPriority == 7 and dest.entities[90].NAME.name == "After demolition")
	dest.poll(); assert(#dest.drain() == 0, "demolition line update echoed")
end)
test("an incoming deleted line slot cannot erase a valid destination stop", function()
	local source, dest = mock(), mock(); source.construction(10, 12, 25); dest.construction(91, 12, 25)
	source.line(20, "A", 20010); dest.line(90, "A", 20091); source.poll(); dest.poll()
	source.entities[30010].STATION_GROUP.stations = {}
	source.entities[20].LINE.stops[1].station, source.entities[20].LINE.stops[1].terminal = -1, -1
	source.poll(); local ok, err = pcall(dest.replay, source.drain()[1])
	assert(not ok and tostring(err):find("deleted line stop not present", 1, true), tostring(err))
	assert(#dest.sent == 0 and dest.entities[90].LINE.stops[1].station == 0)
end)
test("a missing valid line station still fails instead of becoming a deleted placeholder", function()
	local source, dest = mock(), mock()
	source.construction(10, 12, 25); source.construction(11, 200, 300); dest.construction(91, 12, 25)
	source.line(20, "A", 20010); dest.line(90, "A", 20091); source.poll(); dest.poll()
	source.entities[20].LINE.stops[1].stationGroup = 30011
	source.poll(); local ok, err = pcall(dest.replay, source.drain()[1])
	assert(not ok and tostring(err):find("construction reference not found", 1, true), tostring(err))
	assert(#dest.sent == 0 and dest.entities[90].LINE.stops[1].stationGroup == 30091)
end)
test("transport modes the game fills in after a bus joins the copied line are not sent back (run 24)", function()
	local source, dest = mock(), mock(); dest.poll(); source.poll()
	source.line(20, "A")
	source.poll(); dest.replay(source.drain()[1])
	local id = dest.state:get().action_entities["sender:line:20"]
	assert(id and dest.entities[id], "line copy missing")
	dest.entities[id].LINE.vehicleInfo.transportModes = { [0] = true, [1] = true }
	dest.poll(); assert(#dest.drain() == 0, "line echoed")
	-- A real edit is still sent, and it carries the modes.
	dest.entities[id].LINE.reservationPriority = 9
	dest.poll(); local q = dest.drain()
	assert(#q == 1 and q[1].op == "line_update" and q[1].value.data.vehicleInfo.transportModes[1] == true)
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
local function has_log(m, text)
	for _, msg in ipairs(m.logs) do if msg:find(text, 1, true) then return true end end
	return false
end
local function names(m, from)
	local out = {}
	for i = from or 1, #m.sent do out[#out + 1] = m.sent[i].name end
	return table.concat(out, ",")
end
test("a vehicle sent to the depot to be sold is sent there in the other game; neither game sends the sale (v32)", function()
	local source, dest = mock(), mock(); source.train(30); dest.train(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll()
	local v = source.entities[30].TRANSPORT_VEHICLE; v.state, v.sellOnArrival = 3, true
	source.poll(); local q = source.drain()
	assert(#q == 1 and q[1].op == "vehicle_update" and q[1].events.depot == true, #q .. " actions")
	dest.replay(q[1]); assert(names(dest) == "makeVehicleSendToDepotCmd", names(dest))
	assert(dest.sent[1].args[1] == 90 and dest.sent[1].args[2] == true)
	dest.poll(); assert(#dest.drain() == 0, "sent back")
	-- Both games sell their own vehicle when it arrives; nobody sends the sale.
	source.entities[30], source.entities[530] = nil, nil; source.poll()
	assert(#source.drain() == 0 and has_log(source, "sold on arrival"))
	dest.entities[90], dest.entities[590] = nil, nil; dest.poll(); assert(#dest.drain() == 0)
	-- Sent to the depot by both players: the second order is not given again.
	local a, b = mock(), mock(); a.train(30); b.train(90); b.entities[90].NAME.name = "Bus 30"; a.poll(); b.poll()
	a.entities[30].TRANSPORT_VEHICLE.state = 3; b.entities[90].TRANSPORT_VEHICLE.state = 3
	a.poll(); b.replay(a.drain()[1]); assert(#b.sent == 0 and has_log(b, "depot skipped: already on its way"))
	-- The game shows the trip to the depot a step later: still not sent back.
	local c, d = mock(), mock(); c.train(30); d.train(90); d.entities[90].NAME.name = "Bus 30"; c.poll(); d.poll()
	d.slow_state = true; c.entities[30].TRANSPORT_VEHICLE.state = 3; c.poll(); d.replay(c.drain()[1])
	local w = d.entities[90].TRANSPORT_VEHICLE; w.state, w.sellOnArrival = 3, false
	d.poll(); assert(#d.drain() == 0, "sent back after a late state")
end)
test("a vehicle sent to the depot waits there and goes out again in the other game too (v32)", function()
	local source, dest = mock(), mock(); source.line(20, "A"); dest.line(92, "A")
	source.train(30, 20); dest.train(90, 92); dest.entities[90].NAME.name = "Bus 30"
	source.entities[30].TRANSPORT_VEHICLE.stopIndex = 2
	source.poll(); dest.poll()
	local v, w = source.entities[30].TRANSPORT_VEHICLE, dest.entities[90].TRANSPORT_VEHICLE
	v.state = 3; source.poll(); local q = source.drain(); assert(#q == 1 and q[1].events.depot == false)
	dest.replay(q[1]); assert(dest.sent[1].name == "makeVehicleSendToDepotCmd" and dest.sent[1].args[2] == false)
	-- Arrival is no action; leaving again is.
	v.state = 0; source.poll(); assert(#source.drain() == 0)
	w.state = 0; dest.poll(); assert(#dest.drain() == 0)
	v.state = 1; source.poll(); q = source.drain(); assert(#q == 1 and q[1].events.release, "release not sent")
	local before = #dest.sent; dest.replay(q[1])
	assert(names(dest, before + 1) == "makeVehicleSetLineCmd", names(dest, before + 1))
	local c = dest.sent[#dest.sent]; assert(c.args[1] == 90 and c.args[2] == 92 and c.args[3] == 2)
	w.state = 1; dest.poll(); dest.poll(); assert(#dest.drain() == 0, "sent back")
	-- Not in the depot here: nothing to send out.
	local q2 = copy(q[1]); before = #dest.sent; dest.replay(q2)
	assert(#dest.sent == before and has_log(dest, "release skipped: not waiting in a depot"))
	-- A vehicle sent to the depot that leaves its line on the way gets no SetLine(-1).
	v.state, v.line = 3, -1; source.poll(); q = source.drain(); before = #dest.sent; dest.replay(q[1])
	assert(names(dest, before + 1) == "makeVehicleSendToDepotCmd", names(dest, before + 1))
end)
test("a train turned while driving turns in the other game; a turn at a terminal does not travel (v32)", function()
	local source, dest = mock(), mock(); source.train(30); dest.train(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll()
	source.entities[530].CARRIAGE.reversed = true; source.poll(); local q = source.drain()
	assert(#q == 1 and q[1].events.reverse and not q[1].previous.config_changed, #q .. " actions")
	dest.replay(q[1]); assert(names(dest) == "makeVehicleReverseCmd" and dest.sent[1].args[1] == 90)
	assert(dest.entities[590].CARRIAGE.reversed == true)
	dest.poll(); assert(#dest.drain() == 0, "sent back")
	-- Turning at a terminal is the game's own doing in both games.
	local v = source.entities[30].TRANSPORT_VEHICLE; v.state = 2; source.poll()
	source.entities[530].CARRIAGE.reversed = false; source.poll(); v.state = 1; source.poll()
	assert(#source.drain() == 0, "terminal turn sent")
	-- The receiver's own turn shortly after its reverse is not sent back, a later one is.
	dest.entities[590].CARRIAGE.reversed = false; dest.poll(); assert(#dest.drain() == 0, "quiet turn sent")
	dest.poll(); dest.poll(); dest.entities[590].CARRIAGE.reversed = true; dest.poll()
	q = dest.drain(); assert(#q == 1 and q[1].events.reverse, "later turn not sent")
	-- Road vehicles have no carriages: nothing to compare.
	local bus = mock(); bus.vehicle(40); bus.entities[40].TRANSPORT_VEHICLE.state = 1; bus.poll(); bus.poll()
	assert(#bus.drain() == 0)
end)
test("cargo loaded on automatic loading is no new train set; a manual load config is (run 37)", function()
	local source, dest = mock(), mock(); source.train(30); dest.train(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll()
	local part = source.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].part
	source.entities[30].TRANSPORT_VEHICLE.state = 2
	part.compartment2loadConfig = { [0] = { cargoTypeId = 23, loadConfigIndex = 0 } }
	source.poll(); assert(#source.drain() == 0, "automatic load config sent")
	-- The same cargo slot chosen by hand travels as before.
	source.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].autoLoadConfig = { [0] = false }
	source.poll(); local q = source.drain()
	assert(#q == 1 and q[1].previous.config_changed == true, "manual load config not sent")
	assert(actions.config_key(nil) == nil)
end)
test("a reverse clicked by the player travels also at a station, and the turn after it is not sent again (v35)", function()
	local source, dest = mock(), mock(); source.train(30); dest.train(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll()
	local v = source.entities[30].TRANSPORT_VEHICLE; v.state = 2; source.poll(); assert(#source.drain() == 0)
	local s = source.state:get(); actions.note_reverse(s, 30); source.state:set(s)
	source.poll(); local q = source.drain()
	assert(#q == 1 and q[1].events.reverse and not q[1].previous.config_changed, #q .. " actions")
	dest.replay(q[1]); assert(names(dest) == "makeVehicleReverseCmd" and dest.sent[1].args[1] == 90)
	-- The game turns the train now; that turn is the click and does not travel a second time.
	v.state = 1; source.poll(); source.entities[530].CARRIAGE.reversed = true; source.poll()
	assert(#source.drain() == 0, "the clicked turn was sent twice")
	assert(has_log(source, "action train Bus 30: state AT_TERMINAL -> EN_ROUTE"), "train change not logged")
	assert(not pcall(actions.note_reverse, s, "x"))
end)
test("a timed vehicle command finds its vehicle in both games and is not sent back (v35)", function()
	local source, dest = mock(), mock(); source.train(30); dest.train(90); dest.entities[90].NAME.name = "Bus 30"
	source.poll(); dest.poll()
	local ref = actions.vehicle_ref(source.env, 30)
	assert(ref.kind == "vehicle" and ref.key == "30" and ref.name == "Bus 30")
	assert(actions.vehicle_target(source.env, source.state:get(), ref, true) == 30)
	-- The other game: by name (90), by the same entity of the shared save, by an earlier binding.
	assert(actions.vehicle_target(dest.env, dest.state:get(), ref, false) == 90)
	dest.train(30); dest.entities[30].NAME.name = "Bus 30"
	local ok = pcall(actions.vehicle_target, dest.env, dest.state:get(), { kind = "vehicle", key = "31", name = "Bus 30" }, false)
	assert(not ok, "two vehicles of the same name are ambiguous")
	assert(actions.vehicle_target(dest.env, dest.state:get(), ref, false) == 30, "same entity of the shared save")
	local ds = dest.state:get(); ds.action_entities = { ["peer1:vehicle:30"] = 90 }
	assert(actions.vehicle_target(dest.env, ds, ref, false) == 90, "earlier binding first")
	assert(not pcall(actions.vehicle_target, source.env, source.state:get(), { kind = "vehicle", key = "99" }, true))
	-- Both games stop the train at the same tick: neither poll sends it again.
	local s = source.state:get(); actions.vehicle_command_done(s, 30, "stopped", true); source.state:set(s)
	source.entities[30].TRANSPORT_VEHICLE.userStopped = true; source.poll()
	assert(#source.drain() == 0, "stop sent back")
	s = source.state:get(); actions.vehicle_command_done(s, 30, "reverse"); source.state:set(s)
	source.entities[530].CARRIAGE.reversed = true; source.poll()
	assert(#source.drain() == 0, "turn sent back")
	s = source.state:get(); actions.vehicle_command_done(s, 30, "depot", false); source.state:set(s)
	source.entities[30].TRANSPORT_VEHICLE.state = 3; source.poll()
	assert(#source.drain() == 0, "depot order sent back")
	actions.vehicle_command_done({}, 30, "reverse")
end)
test("a vehicle taken off its line while driving loses its line in the other game too (v32)", function()
	local source, dest = mock(), mock(); source.line(20, "A"); dest.line(92, "A")
	source.train(30, 20); dest.train(90, 92); dest.entities[90].NAME.name = "Bus 30"; source.poll(); dest.poll()
	source.entities[30].TRANSPORT_VEHICLE.line = -1; source.poll(); local q = source.drain()
	assert(#q == 1 and q[1].op == "vehicle_update"); dest.replay(q[1])
	assert(names(dest) == "makeVehicleSetLineCmd" and dest.sent[1].args[2] == -1, names(dest))
	assert(not has_log(dest, "not copied yet"))
end)
test("a loan taken or paid back in one game is booked in the other and not sent back (v32)", function()
	local source, dest = mock(), mock(); source.account(0); dest.account(0); source.poll(); dest.poll()
	assert(#source.drain() == 0, "loading sent the loan")
	source.entities[7].ACCOUNT.loan = 500000; source.poll(); local q = source.drain()
	assert(#q == 1 and q[1].op == "account_update" and q[1].value.loan == 500000)
	dest.replay(q[1]); assert(names(dest) == "makeJournalBookAssetCmd" and dest.sent[1].args[2].amount == 500000)
	assert(dest.entities[7].ACCOUNT.loan == 500000 and has_log(dest, "loan 0 -> 500000"))
	dest.poll(); assert(#dest.drain() == 0, "sent back")
	-- The same line again books nothing.
	dest.replay(q[1]); assert(#dest.sent == 1 and has_log(dest, "is 500000 here already"))
	source.entities[7].ACCOUNT.loan = 200000; source.poll(); dest.replay(source.drain()[1])
	assert(dest.sent[2].args[2].amount == -300000 and dest.entities[7].ACCOUNT.loan == 200000)
	-- An account that cannot be read is neither a change nor a removal.
	source.entities[7] = nil; source.poll(); assert(#source.drain() == 0)
end)
test("run35 automatic monthly loan installment is not transported or booked twice", function()
	local m = mock(); m.account(2833334); m.loan_script(); m.poll()
	m.entities[7].ACCOUNT.loan = 2750001; m.poll()
	assert(#m.drain() == 0 and #m.sent == 0, "automatic loan payment sent as a player action")
end)
local function loan(id)
	return { type = "Small", amount = 3000000, duration = 600000, percentage = 0.05,
		id = id, timesPaid = id and 0 or nil, lastPayDay = id and 0 or nil }
end
test("player loan Obtain uses original script, preserving repayment state and suppressing echo", function()
	local source, dest = mock(), mock(); source.account(0); dest.account(0); source.loan_script(); dest.loan_script()
	source.poll(); dest.poll()
	assert(actions.capture_loan(source.env, source.state, "", "Loan", "Obtain", { loan(), loan() }))
	local q = source.drain(); assert(#q == 1 and q[1].op == "loan_event")
	dest.replay(q[1]); assert(dest.sent[1].name == "makeScriptingSendEventCmd")
	assert(dest.sent[1].args[1] == actions.LOAN_SOURCE and dest.sent[1].args[2] == "Loan")
	assert(dest.entities[8].GAME_SCRIPT.state.obtainedLoans[1].amount == 3000000)
	assert(dest.entities[8].GAME_SCRIPT.state.freeId == 1 and dest.entities[7].ACCOUNT.loan == 3000000)
	assert(actions.capture_loan(dest.env, dest.state, actions.LOAN_SOURCE, "Loan", "Obtain", { loan(), loan() }))
	dest.poll(); assert(#dest.drain() == 0, "replayed loan echoed")
end)
test("player Repay resolves the destination loan id before invoking its original script", function()
	local source, dest = mock(), mock(); source.account(3000000); dest.account(3000000)
	source.loan_script({ loan(2) }, 3); dest.loan_script({ loan(7) }, 8)
	actions.capture_loan(source.env, source.state, "", "Loan", "Repay", { [2] = loan(2) })
	dest.replay(source.drain()[1]); assert(dest.sent[1].args[4][1] == nil and dest.sent[1].args[4][2].id == 7)
	assert(#dest.entities[8].GAME_SCRIPT.state.obtainedLoans == 0)
end)
test("ambiguous, excessive, malformed and ignored loan events fail before a native booking", function()
	local source, dest = mock(), mock(); source.account(0); dest.account(0); source.loan_script(); dest.loan_script()
	assert(not actions.capture_loan(source.env, source.state, "", "Other", "Obtain", { loan(), loan() }))
	local bad = loan(); bad.amount = 0/0
	assert(not pcall(actions.capture_loan, source.env, source.state, "", "Loan", "Obtain", { nil, bad }))
	actions.capture_loan(source.env, source.state, "", "Loan", "Repay", { [2] = loan(2) })
	local action = source.drain()[1]
	dest.loan_script({ loan(7), loan(8) }, 9)
	assert(not pcall(dest.replay, action) and #dest.sent == 0, "ambiguous loan repaid")
	dest.loan_script({ loan(1), loan(2), loan(3), loan(4) }, 5)
	assert(not pcall(dest.replay, { op = "loan_event", value = { name = "Obtain", obtained = loan() } }) and #dest.sent == 0)
	assert(not pcall(dest.replay, { op = "account_update", value = { loan = math.huge } }) and #dest.sent == 0)
end)
test("a loan event rejected by the base script never reports successful completion", function()
	local dest = mock(); dest.account(0); dest.loan_script(); dest.reject_loan_event = true
	local ok, err = pcall(dest.replay, { op = "loan_event", value = { name = "Obtain", obtained = loan() } })
	assert(not ok and tostring(err):find("not applied by original game script", 1, true), tostring(err))
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

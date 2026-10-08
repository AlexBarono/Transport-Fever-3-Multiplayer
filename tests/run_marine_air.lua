-- Ships, aircraft and their modular station/line dependencies against TF3's API.
-- Resources are the names of the shipped water/air construction archives; these
-- are offline command regressions, not a claim that the real engine was launched.
local original_require = require
function require(path)
	if path:sub(1, 1) == "/" then return assert(loadfile("mods/mp_probe/content" .. path))() end
	return original_require(path)
end
local actions = require("/mp_probe/actions.lua")
local fixture = dofile("tests/fixtures/actions_env.lua")
local mock, copy = fixture.mock, fixture.copy
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local HARBOR, AIRPORT = "::/stations/water/harbor_modular.con", "::/stations/air/airport.con"
local SHIP, PLANE = "::/vehicle/ship/dunara_castle/dunara_castle.mdl", "::/vehicle/plane/boeing_737_700/boeing_737_700.mdl"
local function station(m, con, id, tag, terminal_tags)
	m.entities[id] = { STATION = { tag = tag, terminals = {} } }
	for i, terminal in ipairs(terminal_tags) do m.entities[id].STATION.terminals[i] = { tag = terminal } end
	m.parents[id], m.groups[id] = con, con + 30000
end
local function pair(file)
	local source, dest = mock(), mock()
	source.construction(10, 120, 350, file); dest.construction(90, 120, 350, file)
	station(source, 10, 20010, 10, { 100, 200, 300 })
	station(dest, 90, 20090, 10, { 100, 200, 300 })
	return source, dest
end
local function models(m, resource, model_id)
	m.env.api.res.modelRep = { getName = function(id) assert(id == 5 or id == model_id); return resource end,
		find = function(name) return name == resource and model_id or -1 end }
end

test("passenger harbor line preserves water waypoints, height, tags and load rules", function()
	local source, dest = pair(HARBOR)
	local line = source.line(20, "Inselverkehr", 20010).LINE
	line.vehicleInfo.transportModes = { [10] = true, [12] = true }
	line.stops[1].waypoints = { { edgePos = { edgeId = { entity = -1 } }, pos = { x = 700, y = 800, z = 11 }, tag = 42 } }
	source.poll(); dest.poll(); source.entities[20].NAME.name = "Inselverkehr neu"; source.poll()
	local action = source.drain()[1]; action.op = "line_create"; dest.replay(action, 0)
	local out = dest.entities[1001].LINE
	assert(out.vehicleInfo.transportModes[10] and out.vehicleInfo.transportModes[12])
	assert(out.stops[1].waypoints[1].pos.z == 11 and out.stops[1].waypoints[1].tag == 42)
	assert(out.stops[1].stopConfig.forceUnload and out.stops[1].stopConfig.maxLoad[1] == 0.3)
end)
test("air line preserves 3D waypoints and source-selected destination stop", function()
	local source, dest = pair(AIRPORT)
	local line = source.line(20, "Luftfracht", 20010).LINE
	line.vehicleInfo.transportModes = { [9] = true, [11] = true }
	line.stops[1].waypoints = { { pos = { x = 1000, y = 2000, z = 350 }, tag = 9 } }
	source.poll(); dest.poll(); source.entities[20].NAME.name = "Express"; source.poll()
	local action = source.drain()[1]; action.op = "line_create"; dest.replay(action)
	local out = dest.entities[1001].LINE
	assert(out.stops[1].waypoints[1].pos.z == 350 and out.vehicleInfo.transportModes[9])
end)
test("harbor passenger and cargo stations resolve by engine tag after child reorder", function()
	local source, dest = pair(HARBOR)
	station(source, 10, 21010, 20, { 400, 500, 600 }); station(dest, 90, 21090, 20, { 600, 400, 500 })
	source.entities[10].CONSTRUCTION.stations = { 20010, 21010 }
	dest.entities[90].CONSTRUCTION.stations = { 21090, 20090 }
	source.entities[30010].STATION_GROUP.stations = { 20010, 21010 }
	dest.entities[30090].STATION_GROUP.stations = { 21090, 20090 }
	local line = source.line(20, "Güterhafen", 21010).LINE
	line.stops[1].station = 1
	line.stops[1].alternativeTerminals = { { station = 1, terminal = 2 } }
	source.poll(); dest.poll(); source.entities[20].NAME.name = "Fracht"; source.poll()
	local action = source.drain()[1]; action.op = "line_create"; dest.replay(action)
	local stop = dest.entities[1001].LINE.stops[1]
	assert(stop.stationGroup == 30090 and stop.station == 0)
	assert(stop.terminal == 2 and stop.alternativeTerminals[1].terminal == 0)
end)
test("airport terminal reorder maps primary and alternative gates by tag", function()
	local source, dest = pair(AIRPORT)
	dest.entities[20090].STATION.terminals = { { tag = 300 }, { tag = 100 }, { tag = 200 } }
	source.poll(); dest.poll(); source.line(20, "Passenger", 20010); source.poll()
	dest.replay(source.drain()[1]); local stop = dest.entities[1001].LINE.stops[1]
	assert(stop.terminal == 2 and stop.alternativeTerminals[1].terminal == 0)
end)
test("missing or ambiguous modular station tags stop a line before native command", function()
	local source, dest = pair(HARBOR); source.poll(); dest.poll()
	source.line(20, "Water", 20010); source.poll(); local action = source.drain()[1]
	dest.entities[20090].STATION.tag = 99
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
	dest.entities[20090].STATION.tag = 10; station(dest, 90, 21090, 10, { 100, 200, 300 })
	dest.entities[90].CONSTRUCTION.stations[2] = 21090
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
test("missing or duplicate destination gate tags stop a line before native command", function()
	local source, dest = pair(AIRPORT); source.poll(); dest.poll()
	source.line(20, "Air", 20010); source.poll(); local action = source.drain()[1]
	dest.entities[20090].STATION.terminals = { { tag = 100 }, { tag = 300 } }
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
	dest.entities[20090].STATION.terminals = { { tag = 200 }, { tag = 200 }, { tag = 300 } }
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
for _, mode in ipairs({ { "ship", HARBOR, SHIP, 81 }, { "aircraft", AIRPORT, PLANE, 82 } }) do
	test(mode[1] .. " purchase resolves local shipyard/hangar model and assigns source-selected stop", function()
		local source, dest = pair(mode[2]); source.line(20, "Route", 20010); dest.line(92, "Route", 20090)
		local source_depot, dest_depot = 10010, 10090
		if mode[1] == "ship" then
			source.construction(11, 750, 850, "::/depots/water/water_depot.con")
			dest.construction(91, 750, 850, "::/depots/water/water_depot.con")
			source_depot, dest_depot = 10011, 10091
		end
		models(source, mode[3], mode[4]); models(dest, mode[3], mode[4]); source.poll(); dest.poll()
		local v = source.vehicle(30, source_depot, 20).TRANSPORT_VEHICLE
		v.stopIndex, v.userStopped, v.autoDeparture = 1, true, false
		source.poll(); dest.replay(source.drain()[1])
		local out = dest.entities[1001].TRANSPORT_VEHICLE
		assert(dest.sent[1].args[2] == dest_depot and out.transportVehicleConfig.vehicles[1].part.modelId == mode[4])
		assert(out.line == 92 and out.stopIndex == 1 and out.userStopped and not out.autoDeparture)
	end)
	test(mode[1] .. " missing model is rejected before purchasing", function()
		local source, dest = pair(mode[2]); models(source, mode[3], mode[4]); source.poll(); dest.poll()
		source.vehicle(30, 10010); source.poll(); local action = source.drain()[1]
		assert(not pcall(dest.replay, action) and #dest.sent == 0)
	end)
	test(mode[1] .. " modular station extension preserves all slots and old2new binding", function()
		local source, dest = pair(mode[2]); source.poll(); dest.poll()
		local before = copy(source.entities[10].CONSTRUCTION)
		source.entities[10] = nil
		source.construction(11, 120, 350, mode[2], { seed = 51, year = 1950,
			modules = { [0] = { variant = 2 }, [280013] = { fileName = "::/module/terminal.module", params = { length = 300 } } } })
		source.poll(); local action = source.drain()[1]
		assert(action.op == "construction_update" and action.target.key == "10")
		dest.replay(action)
		local proposal = dest.sent[1].args[1]
		assert(proposal.constructionsToRemove[1] == 90 and proposal.old2new[90] == 0)
		assert(proposal.constructionsToAdd[1].params.modules[280013].params.length == 300)
		assert(proposal.constructionsToAdd[1].params.seed == 51 and before.fileName == mode[2])
	end)
end

print(string.format("%d marine/air action tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

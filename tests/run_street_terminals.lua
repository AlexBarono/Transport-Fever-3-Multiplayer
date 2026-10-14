-- Real v60 failure: grouped street stops use terminal 0 but lane tags 4/16/19 differ.
local original_require = require
function require(path)
	if path:sub(1, 1) == "/" then return assert(loadfile("mods/mp_probe/content" .. path))() end
	return original_require(path)
end
local actions = require("/mp_probe/actions.lua")
local fixture = assert(loadfile("tests/fixtures/actions_env.lua"))({ actions = actions })
local mock = fixture.mock
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function pair()
	local source, dest = mock(), mock()
	source.street_stop(10, 100, 200).STATION.terminals = { { tag = 16 } }
	dest.street_stop(90, 100, 200).STATION.terminals = { { tag = 4 } }
	source.poll(); dest.poll()
	return source, dest
end
local function captured(source)
	local line = source.line(20, "Bus Lippstadt", 10).LINE
	line.stops[1].terminal, line.stops[1].alternativeTerminals = 0, {}
	source.poll()
	return source.drain()[1], line
end

test("single street terminal tag 16 maps to local tag 4 by its proven unique terminal", function()
	local source, dest = pair(); local action = captured(source)
	local stop = action.value.data.stops[1]
	assert(stop.singleStreetTerminal == true and stop.terminalTag == nil)
	dest.replay(action)
	assert(dest.entities[1001].LINE.stops[1].terminal == 0 and #dest.sent == 1)
end)
test("grouped opposite sides and alternative street terminals map to the local station order", function()
	local source, dest = pair()
	source.street_stop(11, 102, 200).STATION.terminals = { { tag = 19 } }
	dest.street_stop(91, 102, 200).STATION.terminals = { { tag = 8 } }
	source.entities[30010].STATION_GROUP.stations = { 10, 11 }; source.groups[11] = 30010
	dest.entities[30090].STATION_GROUP.stations = { 91, 90 }; dest.groups[91] = 30090
	local action, line = captured(source)
	line.stops[1].alternativeTerminals = { { station = 1, terminal = 0 } }; source.poll()
	action = source.drain()[1]; action.op = "line_create"
	assert(action.value.data.stops[1].alternativeTerminals[1].singleStreetTerminal == true)
	dest.replay(action); local stop = dest.entities[1001].LINE.stops[1]
	assert(stop.station == 1 and stop.terminal == 0)
	assert(stop.alternativeTerminals[1].station == 0 and stop.alternativeTerminals[1].terminal == 0)
end)
test("native road lane tag changes alone do not emit another line edit", function()
	local source = pair(); captured(source)
	source.entities[10].STATION.terminals[1].tag = 19; source.poll()
	assert(#source.drain() == 0)
end)
test("millimeter street stop transform jitter does not echo another line change", function()
	local source = pair(); captured(source)
	source.entities[10].EDGE_OBJECT.transf[13] = 100.004
	source.entities[10].EDGE_OBJECT.transf[14] = 199.997
	source.poll(); assert(#source.drain() == 0)
end)
test("group reorder keeping the same physical side does not emit another line edit", function()
	local source = pair()
	source.street_stop(11, 102, 200).STATION.terminals = { { tag = 19 } }
	source.entities[30010].STATION_GROUP.stations = { 10, 11 }; source.groups[11] = 30010
	local _, line = captured(source)
	source.entities[30010].STATION_GROUP.stations = { 11, 10 }; line.stops[1].station = 1
	source.poll(); assert(#source.drain() == 0)
end)
test("selecting the opposite physical street side still sends a line edit", function()
	local source = pair()
	source.street_stop(11, 102, 200).STATION.terminals = { { tag = 19 } }
	source.entities[30010].STATION_GROUP.stations = { 10, 11 }; source.groups[11] = 30010
	local _, line = captured(source); line.stops[1].station = 1
	source.poll(); local out = source.drain()
	assert(#out == 1 and out[1].op == "line_update" and out[1].value.data.stops[1].target.station == 1)
end)
test("a destination with two street terminals is rejected before an engine command", function()
	local source, dest = pair(); local action = captured(source)
	dest.entities[90].STATION.terminals = { { tag = 4 }, { tag = 16 } }
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
test("missing destination terminal data is not guessed", function()
	local source, dest = pair(); local action = captured(source)
	dest.entities[90].STATION.terminals = nil
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
test("multi-terminal street stop keeps its actual tag and fails when the destination lacks it", function()
	local source, dest = pair()
	source.entities[10].STATION.terminals = { { tag = 16 }, { tag = 19 } }
	local action = captured(source); local stop = action.value.data.stops[1]
	assert(stop.singleStreetTerminal == nil and stop.terminalTag == 16)
	dest.entities[90].STATION.terminals = { { tag = 4 }, { tag = 19 } }
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
test("old unproven payloads do not silently ignore a missing terminal tag", function()
	local source, dest = pair(); local action = captured(source)
	local stop = action.value.data.stops[1]; stop.singleStreetTerminal, stop.terminalTag = nil, 16
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
test("a modular construction with one terminal still requires its actual tag", function()
	local source, dest = mock(), mock()
	source.construction(10, 100, 200); dest.construction(90, 100, 200)
	source.entities[20010] = { STATION = { terminals = { { tag = 16 } } } }
	dest.entities[20090] = { STATION = { terminals = { { tag = 4 } } } }
	source.poll(); dest.poll()
	local line = source.line(20, "Station", 20010).LINE
	line.stops[1].terminal, line.stops[1].alternativeTerminals = 0, {}
	source.poll(); local action = source.drain()[1]
	assert(action.value.data.stops[1].singleStreetTerminal == nil and action.value.data.stops[1].terminalTag == 16)
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
test("single terminal evidence cannot be applied to a modular station reference", function()
	local source, dest = pair(); local action = captured(source)
	action.value.data.stops[1].target.stations[1].kind = "station"
	assert(not pcall(dest.replay, action) and #dest.sent == 0)
end)
print(string.format("%d street terminal tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

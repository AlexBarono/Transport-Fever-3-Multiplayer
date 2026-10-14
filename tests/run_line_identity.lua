-- Pure snapshot comparisons; no native commands and no real game are used.
local identity = dofile("mods/mp_probe/content/mp_probe/line_identity.lua")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local function street(x, y, z)
	return { kind = "street_station", position = { x = x, y = y, z = z }, how = "edge_object", name = "Markt" }
end
local function line()
	local stops = {
		{ target = { stations = { street(10, 20, 0), street(12, 22, 0) }, station = 0 },
			terminal = 0, terminalTag = 4, singleStreetTerminal = true, loadMode = 1,
			minWaitingTime = 0, maxWaitingTime = 180, maxAdditionalWaitingTime = 60,
			stopConfig = { load = { [1] = true }, maxLoad = { [1] = 0.5 }, forceUnload = false },
			alternativeTerminals = { { station = 1, terminal = 0, terminalTag = 16, singleStreetTerminal = true } },
			waypoints = { { pos = { x = 40, y = 60, z = 0 }, tag = 7 } } },
		{ target = { stations = { street(100, 200, 0) }, station = 0 },
			terminal = 0, terminalTag = 16, singleStreetTerminal = true, loadMode = 1,
			stopConfig = {}, alternativeTerminals = {}, waypoints = {} }
	}
	return { ref = { kind = "line", key = "20", name = "Tram 1" }, name = "Tram 1",
		color = { x = 0.2, y = 0.4, z = 0.6 }, data = { stops = stops,
			vehicleInfo = { transportModes = { [2] = true } }, customFilters = {}, reservationPriority = 1 } }
end
local function compare(change, expected)
	local a = line(); local b = copy(a); change(b, a)
	assert(identity.same(a, b) == expected, "forward comparison")
	assert(identity.same(b, a) == expected, "reverse comparison")
	return a, b
end

test("same full captured line", function() compare(function() end, true) end)
test("derived vehicle transport modes are ignored", function()
	compare(function(b) b.data.vehicleInfo = { transportModes = { [3] = true } } end, true)
end)
test("observed street-position jitter of 0.2 to 4 mm is ignored", function()
	compare(function(b)
		b.data.stops[1].target.stations[1].position.x = 10.0002
		b.data.stops[1].target.stations[1].position.y = 20.004
		b.data.stops[2].target.stations[1].position.z = -0.003
	end, true)
end)
test("one centimetre per coordinate is tolerated", function()
	compare(function(b) b.data.stops[1].target.stations[1].position.z = 0.01 end, true)
end)
test("movement exceeding one centimetre is a change", function()
	compare(function(b) b.data.stops[1].target.stations[1].position.z = 0.01001 end, false)
end)
test("comparison never rounds or mutates the wire record", function()
	local a, b = compare(function(v) v.data.stops[1].target.stations[1].position.x = 10.004 end, true)
	assert(a.data.stops[1].target.stations[1].position.x == 10 and b.data.stops[1].target.stations[1].position.x == 10.004)
end)
test("group reorder maps selected station and alternatives", function()
	compare(function(b)
		local stop = b.data.stops[1]; stop.target.stations[1], stop.target.stations[2] = stop.target.stations[2], stop.target.stations[1]
		stop.target.station, stop.alternativeTerminals[1].station = 1, 0
	end, true)
end)
test("group reorder selecting a different side remains a change", function()
	compare(function(b)
		local group = b.data.stops[1].target.stations; group[1], group[2] = group[2], group[1]
	end, false)
end)
test("changing an alternative station remains a change", function()
	compare(function(b) b.data.stops[1].alternativeTerminals[1].station = 0 end, false)
end)
test("ambiguous street references fail closed even when snapshots are identical", function()
	local a = line(); a.data.stops[1].target.stations[2] = copy(a.data.stops[1].target.stations[1])
	assert(not identity.same(a, copy(a)) and not identity.same(a, a))
end)
test("two nearby indistinguishable candidate matches fail closed", function()
	compare(function(b, a)
		a.data.stops[1].target.stations[2] = street(10.005, 20, 0)
		b.data.stops[1].target.stations[2] = street(10.004, 20, 0)
	end, false)
end)
test("selected station changes are not suppressed", function()
	compare(function(b) b.data.stops[1].target.station = 1 end, false)
end)
test("source-verified single-terminal lane tags are ignored", function()
	compare(function(b) b.data.stops[1].terminalTag = 16; b.data.stops[1].alternativeTerminals[1].terminalTag = 4 end, true)
end)
test("unverified street terminal tags remain strict", function()
	compare(function(b, a) a.data.stops[1].singleStreetTerminal = nil; b.data.stops[1].singleStreetTerminal = nil; b.data.stops[1].terminalTag = 16 end, false)
end)
test("one-sided single-terminal marker does not hide a terminal change", function()
	compare(function(b) b.data.stops[1].singleStreetTerminal = nil; b.data.stops[1].terminalTag = 16 end, false)
end)
test("nonzero terminal indexes remain strict even with an incorrect marker", function()
	compare(function(b, a) a.data.stops[1].terminal = 1; b.data.stops[1].terminal = 1; b.data.stops[1].terminalTag = 16 end, false)
end)
test("alternative terminal tags remain strict without the source marker", function()
	compare(function(b, a)
		a.data.stops[1].alternativeTerminals[1].singleStreetTerminal = nil
		b.data.stops[1].alternativeTerminals[1].singleStreetTerminal = nil; b.data.stops[1].alternativeTerminals[1].terminalTag = 4
	end, false)
end)
test("modular harbor and airport terminal tags remain strict", function()
	compare(function(b, a)
		local ref = { kind = "station", parent = { kind = "construction", fileName = "airport.con", transf = { 1, 2, 3 } }, index = 1, tag = 200 }
		a.data.stops[2].target.stations[1], b.data.stops[2].target.stations[1] = ref, copy(ref)
		b.data.stops[2].terminalTag = 4
	end, false)
end)
test("construction station geometry has no positional tolerance", function()
	compare(function(b, a)
		local ref = { kind = "station", parent = { transf = { 1, 2, 3 } }, index = 1 }
		a.data.stops[2].target.stations[1], b.data.stops[2].target.stations[1] = ref, copy(ref)
		b.data.stops[2].target.stations[1].parent.transf[1] = 1.0002
	end, false)
end)
test("waypoint geometry is exact", function()
	compare(function(b) b.data.stops[1].waypoints[1].pos.x = 40.0002 end, false)
end)
test("stop order remains semantic", function()
	compare(function(b) b.data.stops[1], b.data.stops[2] = b.data.stops[2], b.data.stops[1] end, false)
end)
test("line rename is preserved", function() compare(function(b) b.name = "Tram 2" end, false) end)
test("line color is preserved", function() compare(function(b) b.color.x = 0.2001 end, false) end)
test("stop rename is preserved", function() compare(function(b) b.data.stops[1].target.stations[1].name = "Rathaus" end, false) end)
test("load rules are preserved", function() compare(function(b) b.data.stops[1].stopConfig.maxLoad[1] = 0.6 end, false) end)
test("waiting rules are preserved", function() compare(function(b) b.data.stops[1].maxWaitingTime = 240 end, false) end)
test("filters and route priority are preserved", function() compare(function(b) b.data.reservationPriority = 2 end, false) end)
test("new unknown semantic fields are not discarded", function() compare(function(b) b.data.newSetting = true end, false) end)
test("deleted stops with station and terminal minus one remain readable", function()
	local a = line(); a.data.stops[1] = { target = { stations = {}, station = -1 }, terminal = -1, alternativeTerminals = {} }
	assert(identity.same(a, copy(a)))
end)
test("invalid selected indexes are not interpreted as equivalent", function()
	compare(function(b, a) a.data.stops[1].target.station = 9; b.data.stops[1].target.station = 9 end, false)
end)
test("non-finite street positions fail closed", function()
	compare(function(b) b.data.stops[1].target.stations[1].position.x = math.huge end, false)
end)
test("sparse station arrays fail closed", function()
	compare(function(b) b.data.stops[1].target.stations[4] = street(200, 300, 0) end, false)
end)
test("malformed line inputs return false", function() assert(not identity.same(nil, nil) and not identity.same({}, {})) end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

-- Offline tests for the probe mod against a tiny mock engine.
-- Run from the repository root with any Lua 5.1+ interpreter:  lua tests/run_tests.lua
-- (or: python3 tools/run_lua.py tests/run_tests.lua)

local MOD_ROOT = "mods/mp_probe/content"

-- The game resolves require("/mp_probe/x.lua") inside the mod; map that to files on disk.
local real_require = require
local loaded = {}
function require(name)
	if type(name) == "string" and name:sub(1, 1) == "/" then
		if loaded[name] == nil then
			local chunk = assert(loadfile(MOD_ROOT .. name))
			loaded[name] = chunk()
		end
		return loaded[name]
	end
	return real_require(name)
end

local logged = {}
function debugPrint(...)
	logged[#logged + 1] = table.concat({ ... }, " ")
end

local function load_resource(path)
	data = nil
	assert(loadfile(MOD_ROOT .. path))()
	return data()
end

local failures, passed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

local function contains(lines, needle)
	for _, l in ipairs(lines) do if l:find(needle, 1, true) then return true end end
	return false
end

--- transportModes as the engine hands them out (run 5): keys 0..15, true for the given modes.
local function modes(...)
	local t = {}
	for k = 0, 15 do t[k] = false end
	for _, k in ipairs({ ... }) do t[k] = true end
	return t
end

-- The four lanes of town_old_small (run 5 raw dump): sidewalk, two car lanes, sidewalk.
local function town_old_small_lanes()
	local function lane(width, height, forward, transport_modes, offset)
		return { speed = 11.109999656677, width = width, height = height, forward = forward,
			transportModes = transport_modes, offset = offset }
	end
	return {
		lane(3, 0.15000000596046, false, modes(0, 1), 0.15000000596046),
		lane(5, 0, false, modes(1, 2, 3), -0.5),
		lane(5, 0, true, modes(1, 2, 3), 0.5),
		lane(3, 0.15000000596046, true, modes(0, 1), -0.15000000596046),
	}
end
local TOWN_LANES = "11.11,3,0.15,0,3,0.15|11.11,5,0,0,14,-0.5|11.11,5,0,1,14,0.5|11.11,3,0.15,1,3,-0.15"

-- Street build of run 5 (logs/probe-log-5-mp_probe.txt, "player #1"): 3 new nodes, 2 new segments.
local function run5_street()
	local function node(entity, x, y, z)
		return { entity = entity, comp = { position = { x = x, y = y, z = z } } }
	end
	local function segment(entity, node0, node1, t0, t1)
		return { entity = entity, type = 0, comp = {
			type = 0, node0 = node0, node1 = node1, typeIndex = -1,
			roadType = 1, distance = 0,
			roadTemplate = "::/infrastructure/street/town/town_old_small.street_template",
			roadStyle = "::/infrastructure/street/town/town_old.street",
			tangent0 = { x = t0[1], y = t0[2], z = t0[3] },
			tangent1 = { x = t1[1], y = t1[2], z = t1[3] },
			laneConfigs = town_old_small_lanes(),
		},
		params = { precedenceNode0 = 2, precedenceNode1 = 2 },
		streetEdge = { precedenceNode0 = 2, precedenceNode1 = 2 } }
	end
	return {
		addedNodes = {
			node(51389, -2888.0170898438, -3941.5083007812, 1.6745910644531),
			node(51498, -2818.5432128906, -3887.2819824219, 1.4728393554688),
			node(51458, -2749.0693359375, -3833.0556640625, 1.0032730102539),
		},
		addedSegments = {
			segment(51563, 51389, 51498, { 69.473876953125, 54.226318359375, -0.20175172388554 },
				{ 69.473876953125, 54.226318359375, -0.33565902709961 }),
			segment(51564, 51498, 51458, { 69.473876953125, 54.226318359375, -0.33565902709961 },
				{ 69.47386932373, 54.226329803467, -0.46956634521484 }),
		},
	}
end

local function mock_state()
	local value = nil
	local st = { subscribed = {} }
	st.get = function(_) return value end
	st.set = function(_, v) value = v end
	st.subscribeToEvent = function(self, event) self.subscribed[#self.subscribed + 1] = event end
	return st
end

local probe = require("/mp_probe/probe.lua")
local build = require("/mp_probe/build.lua")

test("capabilities reports present and missing globals", function()
	local env = { _VERSION = "Lua 5.x", io = { open = function() end }, api = { cmd = {} } }
	local lines = probe.capabilities(env)
	assert(contains(lines, "_VERSION: Lua 5.x"))
	assert(contains(lines, "io.open: yes"))
	assert(contains(lines, "io.popen: no"))
	assert(contains(lines, "api.cmd: yes"))
	assert(contains(lines, "api.cmd.sendCommand: no"))
	assert(contains(lines, "socket: no"))
end)

test("capabilities reports a failing require", function()
	local env = { require = function() error("module 'socket' not found") end }
	assert(contains(probe.capabilities(env), "require('socket'): failed"))
end)

test("capabilities write check uses io.open and os.remove", function()
	local written, removed = nil, nil
	local env = {
		io = { open = function(p) return { write = function(_, s) written = s end, close = function() end }, p end },
		os = { remove = function(p) removed = p end },
	}
	local lines = probe.capabilities(env, { try_write = true, write_path = "x.txt" })
	assert(contains(lines, "file write (x.txt): ok"))
	assert(written ~= nil and removed == "x.txt")
end)

test("list walks nested tables, userdata __index and stops at max depth", function()
	local lines = probe.list({ cmd = { sendCommand = function() end }, n = 1 }, "api", 2)
	assert(contains(lines, "api = table"))
	assert(contains(lines, "api.cmd = table"))
	assert(contains(lines, "api.cmd.sendCommand = function"))
	assert(contains(lines, "api.n = number"))
	local shallow = probe.list({ cmd = { sendCommand = function() end } }, "api", 1)
	assert(not contains(shallow, "sendCommand"))
end)

test("list skips metatable fields and non-string keys", function()
	local proxy = { makeLineCreateCmd = {}, __index = function() end, __metatable = false }
	proxy[{}] = {}
	local lines = probe.list({ cmd = proxy }, "api", 3)
	assert(contains(lines, "api.cmd.makeLineCreateCmd = table"))
	assert(not contains(lines, "__index"))
	assert(not contains(lines, "__metatable"))
	assert(#lines == 3, "got " .. #lines)
end)

test("list keeps array entries and shows scalar values", function()
	local lines = probe.list({ { proposal = { addedSegments = { 5 } } }, "x" }, "param", 6)
	assert(contains(lines, "param[1].proposal.addedSegments[1] = number 5"))
	assert(contains(lines, "param[2] = string x"))
end)

test("fields finds known names on objects pairs() cannot enumerate", function()
	-- Simulate C++ userdata: fields only reachable through __index, nothing visible to pairs().
	local function opaque(fields)
		return setmetatable({}, { __index = function(_, k)
			if fields[k] == nil then error("no field " .. tostring(k)) end
			return fields[k]
		end })
	end
	local proposal = opaque({ streetProposal = opaque({ edgesToAdd = { opaque({ entity = -1, type = 0 }) } }) })
	local lines = probe.fields({ proposal, opaque({}), { 45276 }, false }, "param", 6)
	assert(contains(lines, "param[1].streetProposal = table"), table.concat(lines, "\n"))
	assert(contains(lines, "param[1].streetProposal.edgesToAdd = table (#1)"))
	assert(contains(lines, "param[1].streetProposal.edgesToAdd[1].entity = number -1"))
	assert(contains(lines, "param[3][1] = number 45276"))
end)

test("list honours an explicit line budget", function()
	local big = {}
	for i = 1, 50 do big["k" .. i] = i end
	local lines = probe.list(big, "p", 1, nil, 5)
	assert(#lines == 6, "got " .. #lines)
	assert(contains(lines, "truncated at 5 lines"))
end)

test("list survives cycles and truncates long output", function()
	local t = {}
	t.self = t
	probe.list(t, "t", 5)
	local big = {}
	for i = 1, 1000 do big["k" .. i] = i end
	local old = probe.MAX_LINES
	probe.MAX_LINES = 10
	local lines = probe.list(big, "big", 1)
	probe.MAX_LINES = old
	assert(#lines <= 11, "got " .. #lines)
	assert(contains(lines, "truncated"))
end)

local function mock_engine_env(opts)
	opts = opts or {}
	local components = {
		[10] = { gameTime = 42000 },
		[20] = { balance = 5000000 },
		[1] = { stopIndex = 1 }, [2] = { stopIndex = 2 }, [3] = { stopIndex = 4 },
	}
	local counts = { [1] = 3, [2] = 2 }
	return { api = {
		type = { ComponentType = { GAME_TIME = 100, ACCOUNT = 200, TRANSPORT_VEHICLE = 1, STATION = 2 } },
		engine = {
			util = {
				getWorld = function() return 10 end,
				getPlayer = function() return 20 end,
				vehicle = { getPosition = function(v) return { x = v + 0.4, y = 10, z = 0.6 } end },
			},
			system = {
				lineSystem = { getLines = function() return { 7, 8 } end },
				transportVehicleSystem = { getVehicles = function() error("Error decoding argument #2") end },
			},
			getComponent = function(entity, comp)
				if comp == nil then error("bad component type") end
				return components[entity]
			end,
			forEachEntityWithComponent = function(fn, comp)
				if comp == nil then error("bad component type") end
				for i = 1, counts[comp] do fn(i) end
			end,
		},
	} }
end

test("snapshot reads time, money, counts and vehicle positions through api.engine", function()
	local snap = probe.snapshot(mock_engine_env())
	assert(snap.fields.game_time == 42000)
	assert(snap.fields.money == 5000000)
	assert(snap.fields.n_transport_vehicle == 3)
	assert(snap.fields.n_station == 2)
	assert(snap.fields.n_line == 2)
	-- vehicles 1, 2, 3: (1+10+1) + (2+10+1) + (3+10+1) after rounding
	assert(snap.fields.vehicle_pos_sum == 39, tostring(snap.fields.vehicle_pos_sum))
	assert(snap.fields.vehicle_stop_sum == 7, tostring(snap.fields.vehicle_stop_sum))
	assert(snap.errors.n_town ~= nil, "TOWN is not in the mock ComponentType")
	local line = probe.format_snapshot(snap)
	assert(line:find("game_time=42000 money=5000000 n_line=2 n_station=2 n_transport_vehicle=3 vehicle_pos_sum=39 vehicle_stop_sum=7", 1, true), line)
	assert(line:find("n_town=ERR", 1, true), line)
	assert(contains(probe.format_errors(snap), "n_town: "))
end)

test("snapshot without api.engine reports an error", function()
	local snap = probe.snapshot({ game = {} })
	assert(snap.errors.api_engine ~= nil)
end)

test("game script registration points at main.script", function()
	local reg = load_resource("/mp_probe/main.gs.lua")
	assert(reg.updateScript.fileName == "main.script@update")
	assert(reg.handleEventScript.fileName == "main.script@handleEvent")
end)

test("run_probe lists every configured root that exists", function()
	local main = load_resource("/mp_probe/main.script.lua")
	logged = {}
	main.run_probe({ api = { engine = { getComponent = function() end }, cmd = { sendCommand = function() end } } })
	assert(contains(logged, "---- listing api.engine"))
	assert(contains(logged, "api.engine.getComponent = function"))
	assert(contains(logged, "---- listing api.cmd"))
	assert(not contains(logged, "---- listing game.config"))
end)

test("update runs the probe once and snapshots periodically", function()
	local main = load_resource("/mp_probe/main.script.lua")
	main.SNAPSHOT_EVERY = 2
	logged = {}
	local state = mock_state()
	for _ = 1, 4 do main.update(nil, state, 0) end
	local probe_headers, snapshots = 0, 0
	for _, l in ipairs(logged) do
		if l:find("---- capabilities", 1, true) then probe_headers = probe_headers + 1 end
		if l:find("snapshot update=", 1, true) then snapshots = snapshots + 1 end
	end
	assert(probe_headers == 1, "probe ran " .. probe_headers .. " times")
	assert(contains(logged, "---- snapshot errors"), "first snapshot logs its errors")
	local error_headers = 0
	for _, l in ipairs(logged) do
		if l:find("---- snapshot errors", 1, true) then error_headers = error_headers + 1 end
	end
	assert(error_headers == 1, "snapshot errors logged " .. error_headers .. " times")
	assert(snapshots == 2, "snapshots " .. snapshots)
	assert(state:get().probe_version == main.PROBE_VERSION)
	assert(#state.subscribed == 2 and state.subscribed[1] == "onPostBuildProposal", "subscribed once")
	assert(state.subscribed[2] == main.REPLAY_EVENT, "our own replay event is subscribed too")
	assert(contains(logged, "subscribe onPostBuildProposal: ok"))
end)

-- param[4] is the game's own "player build" flag (true for every player build in runs 5-9).
local function player_build_param()
	return { { proposal = run5_street(), toAdd = {} }, {}, { 501 }, true }
end

local function town_build_param()
	return { { proposal = { addedSegments = {}, addedNodes = {} }, toAdd = { { playerEntity = -1 } } }, {}, { 777 }, false }
end

test("is_player_build tells player builds from town builds", function()
	local main = load_resource("/mp_probe/main.script.lua")
	assert(main.is_player_build(player_build_param()))
	assert(main.is_player_build({ { proposal = { addedSegments = {}, addedNodes = {} }, toAdd = { { playerEntity = 3 } } } }))
	assert(not main.is_player_build(town_build_param()))
	assert(not main.is_player_build({ {} }), "malformed param counts as no player build")
	local town_road = player_build_param()
	town_road[4] = false
	assert(not main.is_player_build(town_road), "a town's road is not the player's, even with segments")
end)

test("handleEvent dumps up to BUILD_DUMPS player builds and one town build", function()
	local main = load_resource("/mp_probe/main.script.lua")
	main.BUILD_DUMPS = 2
	logged = {}
	local state = mock_state()
	for _ = 1, 4 do main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param()) end
	for _ = 1, 3 do main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", town_build_param()) end
	local player_dumps, town_dumps = 0, 0
	for _, l in ipairs(logged) do
		if l:find("---- param of onPostBuildProposal player", 1, true) then player_dumps = player_dumps + 1
		elseif l:find("---- param of onPostBuildProposal #", 1, true) then town_dumps = town_dumps + 1 end
	end
	assert(player_dumps == 2, "player dumps " .. player_dumps)
	assert(town_dumps == 1, "town dumps " .. town_dumps)
	assert(contains(logged, "capture player build nodes=3 segments=2 foreign_nodes=0"))
	local stored = 0
	for _, l in ipairs(logged) do if l:find("capture stored for replay", 1, true) then stored = stored + 1 end end
	assert(stored == 4, "every player build is captured, dumped or not: " .. stored)
	local capped = 0
	for _, l in ipairs(logged) do if l:find("dump of onPostBuildProposal", 1, true) then capped = capped + 1 end end
	assert(capped == 3, "timing lines " .. capped)
end)

test("player builds dump the components of the new entities", function()
	local main = load_resource("/mp_probe/main.script.lua")
	logged = {}
	local saved_api = api
	api = { type = { ComponentType = { BASE_EDGE = 1, BASE_NODE = 2 } }, engine = {
		getComponent = function(entity, comp)
			if entity == 501 and comp == 1 then return { node0 = 600, node1 = 601, type = 0 } end
			return nil
		end,
	} }
	main.handleEvent(nil, mock_state(), "", "apply_command", "onPostBuildProposal", player_build_param())
	api = saved_api
	assert(contains(logged, "---- entity 501 BASE_EDGE"), table.concat(logged, "\n"))
	assert(contains(logged, "e501.BASE_EDGE.node0 = number 600"))
	assert(not contains(logged, "entity 501 BASE_NODE"))
end)

test("handleEvent starts counting again for a new probe version", function()
	local main = load_resource("/mp_probe/main.script.lua")
	logged = {}
	local state = mock_state()
	state:set({ seen_events = { ["a.lua|id1|onX"] = true }, seen_events_version = main.PROBE_VERSION - 1 })
	main.handleEvent(nil, state, "a.lua", "id1", "onX", {})
	main.handleEvent(nil, state, "a.lua", "id1", "onX", {})
	assert(contains(logged, "name=onX #1"))
	assert(not contains(logged, "name=onX #2"))
end)

test("handleEvent logs each event type once", function()
	local main = load_resource("/mp_probe/main.script.lua")
	logged = {}
	local state = mock_state()
	main.handleEvent(nil, state, "a.lua", "id1", "onX", {})
	main.handleEvent(nil, state, "a.lua", "id1", "onX", {})
	main.handleEvent(nil, state, "a.lua", "id1", "onY", {})
	local events = 0
	for _, l in ipairs(logged) do
		if l:find("event src=", 1, true) then events = events + 1 end
	end
	assert(events == 2, "logged " .. events .. " events")
	assert(contains(logged, "---- param of onX"))
end)

test("bridge_tick logs outgoing lines and only changed incoming values", function()
	local main = load_resource("/mp_probe/main.script.lua")
	logged = {}
	local value = nil
	local env = { os = { getenv = function(name) return name == "TF3MP_IN" and value or nil end } }
	main.bridge_tick(env, 1)
	value = "hello 1"
	main.bridge_tick(env, 2)
	main.bridge_tick(env, 3)
	assert(contains(logged, "bridge out seq=3"))
	assert(contains(logged, "bridge in TF3MP_IN=nil"))
	local hellos = 0
	for _, l in ipairs(logged) do if l:find("TF3MP_IN=hello 1", 1, true) then hellos = hellos + 1 end end
	assert(hellos == 1, "logged " .. hellos)
end)

test("capabilities reports whether os.getenv sees the environment", function()
	local lines = probe.capabilities({ os = { getenv = function() return "C:\\x" end } })
	assert(contains(lines, "os.getenv('PATH'): length 4"))
end)


test("serialize turns a captured street into one line with placeholder ids", function()
	local line, info = build.serialize(run5_street())
	assert(info.nodes == 3 and info.segments == 2, info.nodes .. "/" .. info.segments)
	assert(info.foreign_nodes == 0, "all three nodes are new")
	assert(line:sub(1, 2) == "B4", line)
	assert(line:find("n-1;-2888.017,-3941.508,1.675", 1, true), line)
	assert(line:find("s-1;0;-1;-2;", 1, true), line)
	assert(line:find("s-2;0;-2;-3;", 1, true), line)
	assert(not line:find("51389", 1, true), "engine ids must not travel")
	assert(line:find(" t1;::/infrastructure/street/town/town_old_small.street_template;::/infrastructure/street/town/town_old.street;" .. TOWN_LANES .. " ", 1, true), line)
	assert(line:find("s-2;0;-2;-3;69.474,54.226,-0.336;69.474,54.226,-0.47;-1;1;0;1;2,2;2,2", 1, true), line)
	local _, templates = line:gsub("town_old_small", "")
	assert(templates == 1, "the template and its lanes are written once")
	assert(#line < 600, "a street build fits in a short line: " .. #line)
end)

test("serialize names nodes the player connected to by their position", function()
	local proposal = run5_street()
	proposal.addedNodes = { proposal.addedNodes[1] }
	local positions = { [51498] = { x = 10, y = 20, z = 1 }, [51458] = { x = 30, y = 40, z = 2 } }
	local line, info = build.serialize(proposal, { node_position = function(id) return positions[id] end })
	assert(info.foreign_nodes == 2, info.foreign_nodes)
	assert(line:find(" f1;10,20,1 ", 1, true) and line:find(" f2;30,40,2 ", 1, true), line)
	assert(line:find("s-1;0;-1;f1;", 1, true) and line:find("s-2;0;f1;f2;", 1, true), line)
	assert(not line:find("51498", 1, true), "engine ids must not travel")
	local data = assert(build.deserialize(line))
	assert(data.segments[2].node0 == "f1" and data.foreign.f2.y == 40)
	assert(not pcall(build.serialize, proposal), "without positions an existing node cannot be named")
end)

test("resolve finds existing nodes, removed segments and demolished constructions here", function()
	local proposal = run5_street()
	proposal.addedNodes = { proposal.addedNodes[1], proposal.addedNodes[2] }
	proposal.removedNodes = { { entity = 77, comp = { position = { x = 5, y = 6, z = 0 } } } }
	proposal.removedSegments = { { entity = 78, type = 0, comp = { node0 = 77, node1 = 51458 } } }
	local positions = { [51458] = { x = 30, y = 40, z = 2 } }
	local line, info = build.serialize(proposal, {
		node_position = function(id) return positions[id] end,
		to_remove = { 900 },
		construction = function(id) return id == 900 and { file = "::/depots/road depot.con", position = { x = 1, y = 2, z = 3 } } end,
	})
	assert(info.removed_segments == 1 and info.removed_nodes == 1 and info.demolished == 1, line)
	assert(line:find(" r;5,6,0;30,40,2;0", 1, true) and line:find(" x;5,6,0", 1, true), line)
	assert(line:find(" d;%3A%3A%2Fdepots%2Froad%20depot.con;1,2,3", 1, true), line)
	local data = assert(build.deserialize(line))
	assert(data.demolished[1].file == "::/depots/road depot.con")
	local here = { { id = 501, p = { x = 30.4, y = 40.3, z = 2 } }, { id = 502, p = { x = 5, y = 6.5, z = 0 } } }
	local finder = {
		find_node = function(pos)
			for _, n in ipairs(here) do
				if math.abs(n.p.x - pos.x) <= 1.5 and math.abs(n.p.y - pos.y) <= 1.5 then return n.id end
			end
		end,
		find_edge = function(a, b) if (a == 502 and b == 501) or (a == 501 and b == 502) then return 600 end end,
		find_construction = function(file, pos) if file == "::/depots/road depot.con" and pos.x == 1 then return 700 end end,
	}
	local ok, missing = build.resolve(data, finder)
	assert(ok, missing)
	assert(data.segments[2].node1 == 501 and data.removed_segments[1].entity == 600)
	assert(data.removed_nodes[1].entity == 502 and data.demolished[1].entity == 700)
	assert(data.positions_of[501].x == 30)
	data = assert(build.deserialize(line))
	here[1].p.x = 90
	local ok2, missing2 = build.resolve(data, finder)
	assert(not ok2 and missing2:find("does not exist here", 1, true), missing2)
end)

test("serialize gives each lane layout its own road token and marks missing params", function()
	local proposal = run5_street()
	local seg = proposal.addedSegments[2]
	seg.comp.laneConfigs = { { speed = 33.3, width = 3.5, height = 0, forward = true, transportModes = modes(4), offset = 0 } }
	seg.params = nil
	local line = build.serialize(proposal)
	assert(line:find(" t2;::/infrastructure/street/town/town_old_small.street_template;::/infrastructure/street/town/town_old.street;33.3,3.5,0,1,16,0 ", 1, true), line)
	assert(line:find("s-2;0;-2;-3;69.474,54.226,-0.336;69.474,54.226,-0.47;-1;1;0;2;-;2,2", 1, true), line)
	seg.comp.laneConfigs = {}
	assert(build.serialize(proposal):find("/town_old.street;- ", 1, true), "a segment without lanes says so")
end)

test("deserialize restores positions, tangents and node links", function()
	local line = build.serialize(run5_street())
	local data = assert(build.deserialize(line))
	assert(data.version == build.VERSION)
	assert(#data.nodes == 3 and #data.segments == 2)
	assert(data.nodes[1].id == -1)
	assert(math.abs(data.nodes[1].position.x + 2888.017) < 0.001, data.nodes[1].position.x)
	assert(data.segments[2].node0 == -2 and data.segments[2].node1 == -3)
	assert(data.segments[1].type == 0 and data.segments[1].typeIndex == -1)
	assert(data.segments[1].roadType == 1 and data.segments[1].distance == 0)
	assert(data.segments[2].roadStyle == "::/infrastructure/street/town/town_old.street")
	assert(math.abs(data.segments[1].tangent0.y - 54.226) < 0.001, data.segments[1].tangent0.y)
	local lanes = data.segments[1].lanes
	assert(#lanes == 4 and lanes[1].width == 3 and lanes[1].forward == false and lanes[1].modes == 3)
	assert(lanes[2].modes == 14 and lanes[3].forward == true and lanes[3].offset == 0.5)
	assert(math.abs(lanes[4].offset + 0.15) < 1e-9 and math.abs(lanes[1].speed - 11.11) < 1e-9)
	assert(data.segments[1].params[1] == 2 and data.segments[2].streetEdge[2] == 2)
end)

test("deserialize rejects broken lines", function()
	assert(build.deserialize("n-1;1,2,3") == nil, "a line without a version is rejected")
	assert(build.deserialize("B99 n-1;1,2,3") == nil, "a newer format is rejected")
	assert(build.deserialize("B4 n-1;1,2") == nil, "a short position is rejected")
	assert(build.deserialize("B4 s-1;0;-1") == nil, "a short segment is rejected")
	assert(build.deserialize("B4 s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;7;-;-") == nil, "an undefined road type is rejected")
	assert(build.deserialize("B4 t1;a;b;1,2,3 s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1;-;-") == nil, "a short lane is rejected")
	assert(build.deserialize("B4 t1;a;b s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1;-;-") == nil, "a road token without lanes is rejected")
	assert(build.deserialize("B2 s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1") == nil, "format 2 lacks the lanes")
	local no_lanes = assert(build.deserialize("B4 t1;a;b;- s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1;-;-"))
	assert(no_lanes.segments[1].lanes == nil and no_lanes.segments[1].params == nil)
	assert(build.deserialize("B4 s-1;0;f1;-2;1,0,0;1,0,0;-1;1;0;1;-;-") == nil, "an unknown existing node is rejected")
	assert(build.deserialize("B4 c;a;b;1,2;n1") == nil, "a construction needs 16 transf numbers")
	assert(build.deserialize(42) == nil)
	local data = assert(build.deserialize("B4"), "an empty proposal parses")
	assert(#data.nodes == 0 and #data.segments == 0)
end)

--- Mock of TF3 engine structs with the copy semantics run 9 revealed: reading a nested struct or a
-- list gives a copy, so a change only reaches the owner when it is assigned back. Unknown fields
-- and values of the wrong kind raise, as the C++ binding does.
local STRUCT = {}
--- Marks a known field whose value is nil (run 5: a track segment has params = nil).
local NIL = {}

local function struct_info(v)
	local mt = type(v) == "table" and getmetatable(v)
	return mt and mt[STRUCT]
end

local function vector_items(v)
	local mt = type(v) == "table" and getmetatable(v)
	return mt and mt.vector_items
end

local copy_value

local function new_struct(type_name, store, lists, opts)
	local info = { type_name = type_name, store = store, lists = lists, opts = opts or {} }
	return setmetatable({}, {
		[STRUCT] = info,
		__index = function(_, k)
			local v = store[k]
			if v == nil then error("no field " .. tostring(k) .. " in " .. type_name) end
			if v == NIL then return nil end
			return copy_value(v)
		end,
		__newindex = function(_, k, v)
			local old = store[k]
			if old == nil then error("cannot set unknown field " .. tostring(k) .. " of " .. type_name) end
			if info.opts.ignore_writes and info.opts.ignore_writes[k] then return end
			if lists[k] then
				local items = vector_items(v)
				if not items then
					if type(v) ~= "table" or struct_info(v) then error("Error decoding list " .. k) end
					if info.opts.refuse_tables then error("expected a Vector for " .. k) end
					items = v
				end
				local list = {}
				for i = 1, #items do list[i] = copy_value(items[i]) end
				store[k] = list
				return
			end
			local old_info = struct_info(old)
			if old_info and (struct_info(v) or {}).type_name ~= old_info.type_name then
				error("Error decoding " .. old_info.type_name .. " for " .. k)
			end
			store[k] = v == nil and NIL or copy_value(v)
		end,
	})
end

function copy_value(v)
	local info = struct_info(v)
	if info then
		local store = {}
		for k, x in pairs(info.store) do store[k] = copy_value(x) end
		return new_struct(info.type_name, store, info.lists, info.opts)
	end
	if type(v) == "table" and v ~= NIL and not vector_items(v) then
		local copy = {}
		for k, x in pairs(v) do copy[k] = copy_value(x) end
		return copy
	end
	return v
end

--- A struct with the given fields; the value "list" marks a list field, NIL a field that is nil.
local function struct(type_name, fields, opts)
	local store, lists = {}, {}
	for k, v in pairs(fields) do
		if v == "list" then store[k], lists[k] = {}, true else store[k] = v end
	end
	return new_struct(type_name, store, lists, opts)
end

local function type_name_of(v)
	local info = struct_info(v)
	return info and info.type_name
end

--- TF3's Vector_* types: index assignment raises, push_back works.
local function vector()
	local items = {}
	return setmetatable({}, {
		vector_items = items,
		__len = function() return #items end,
		__index = function(_, k)
			if k == "push_back" then return function(_, v) items[#items + 1] = copy_value(v) end end
			return items[k]
		end,
		__newindex = function() error("cannot assign to a vector") end,
	})
end

test("the struct mock hands out copies, as TF3 did in run 9", function()
	local p = struct("SimpleProposal", { streetProposal = struct("SimpleStreetProposal", { nodesToAdd = "list" }) })
	local list = p.streetProposal.nodesToAdd
	list[#list + 1] = "x"
	assert(#p.streetProposal.nodesToAdd == 0, "appending to the copy changes nothing")
	local sp = p.streetProposal
	sp.nodesToAdd = { "x" }
	assert(#p.streetProposal.nodesToAdd == 0, "the nested struct is a copy too")
	p.streetProposal = sp
	assert(#p.streetProposal.nodesToAdd == 1, "writing it back lands")
	assert(not pcall(function() p.unknown = 1 end), "unknown fields raise")
end)

--- Mock of the TF3 types used when rebuilding.
-- @param opts table { layouts = set of proposal type names that exist (default all),
--   refuse_tables = lists only take Vector_* objects, lose_positions / lose_lanes = node positions
--   or segment lanes are silently not stored, empty_modes = a new LaneConfig hands out an empty
--   transportModes table, builds = set of proposal types the game builds (default all),
--   required_args = number of arguments makeWorldBuildProposalCmd insists on, content_error =
--   makeWorldBuildProposalCmd fails like run 10 }
local function mock_types(opts)
	local function vec3(x, y, z) return struct("Vec3f", { x = x or 0, y = y or 0, z = z or 0 }) end
	local list_opts = { refuse_tables = opts.refuse_tables, ignore_writes = opts.lose_lanes and { laneConfigs = true } or nil }
	local t = {
		Vec3f = { new = vec3 },
		Context = { new = function()
			return struct("Context", { player = -1, cleanupStreetGraph = false, gatherBuildings = false,
				gatherFields = true, checkTerrainAlignment = false })
		end },
		PlayerOwned = { new = function() return struct("PlayerOwned", { player = -1 }) end },
		BaseEdgeStreet = { new = function() return struct("BaseEdgeStreet", { precedenceNode0 = 0, precedenceNode1 = 0 }) end },
		LaneConfig = { new = function()
			return struct("LaneConfig", { speed = 0, width = 0, height = 0, forward = false, offset = 0,
				transportModes = opts.empty_modes and {} or modes() })
		end },
		NodeAndEntity = { new = function()
			return struct("NodeAndEntity", { entity = 0, comp = struct("BaseNode", { position = vec3() },
				{ ignore_writes = opts.lose_positions and { position = true } or nil }) })
		end },
		SegmentAndEntity = { new = function()
			return struct("SegmentAndEntity", {
				entity = 0, type = 0,
				comp = struct("BaseEdge", {
					node0 = 0, node1 = 0, position0 = vec3(), position1 = vec3(), tangent0 = vec3(), tangent1 = vec3(),
					type = 0, typeIndex = 0, roadTemplate = "", roadStyle = "", roadType = 0, distance = 0,
					laneConfigs = "list",
				}, list_opts),
				params = NIL,
				streetEdge = struct("BaseEdgeStreet", { precedenceNode0 = 0, precedenceNode1 = 0 }),
				playerOwned = struct("PlayerOwned", { player = -1 }),
			})
		end },
		Vector_NodeAndEntity = { new = vector },
		Vector_SegmentAndEntity = { new = vector },
		Vector_LaneConfig = { new = vector },
	}
	if opts.layouts == nil or opts.layouts.SimpleProposal then
		t.SimpleProposal = { new = function()
			return struct("SimpleProposal", {
				streetProposal = struct("SimpleStreetProposal", { nodesToAdd = "list", edgesToAdd = "list",
					edgesToRemove = "list", nodesToRemove = "list" }, list_opts),
				constructionsToAdd = "list",
				constructionsToRemove = "list",
			})
		end, ConstructionEntity = { new = function()
			return struct("ConstructionEntity", { fileName = "", name = "", params = {}, playerEntity = -1,
				transf = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } })
		end } }
	end
	return t
end

--- The node and edge lists a sent SimpleProposal carries, read the way the game would.
local function sent_lists(proposal)
	local sp = proposal.streetProposal
	return sp.nodesToAdd, sp.edgesToAdd
end

--- api mock for rebuilding: the game "builds" a sent proposal with segments (one new entity per
-- node and segment, 500 per segment) unless opts.builds leaves its type out.
local function mock_build_api(opts)
	opts = opts or {}
	local sent = {}
	local api = {
		type = mock_types(opts),
		cmd = {
			makeWorldBuildProposalCmd = function(proposal, context, flag)
				if type_name_of(proposal) ~= "SimpleProposal" then
					error("Error decoding argument #2: The lua object can't be cast to desired type")
				end
				if opts.required_args and select("#", proposal, context, flag) ~= opts.required_args then
					error("bad argument #3 to 'makeWorldBuildProposalCmd' (wrong number of arguments)")
				end
				-- Like the game, the error points at the line in build.lua that made the call.
				if opts.content_error then error("Unknown exception", 2) end
				return { proposal = proposal, context = context, flag = flag }
			end,
			sendCommand = function(cmd, callback)
				sent[#sent + 1] = cmd
				cmd.layout = type_name_of(cmd.proposal)
				local nodes, edges = sent_lists(cmd.proposal)
				local work = #edges + #cmd.proposal.constructionsToAdd + #cmd.proposal.streetProposal.edgesToRemove
				local builds = work > 0 and (opts.builds == nil or opts.builds[cmd.layout] == true)
				local entities = {}
				if builds then for i = 1, #nodes + #edges do entities[i] = 1000 + i end end
				if callback then
					callback({
						resultEntities = entities,
						resultProposalData = { costs = builds and 500 * work or 0, errorState = {
							critical = false, messages = {}, warnings = builds and {} or { "nothing to build" } } },
					}, true)
				end
			end,
		},
	}
	return { api = api }, sent
end

local function street_data()
	return assert(build.deserialize(build.serialize(run5_street())))
end

test("replay assigns whole lists to a SimpleProposal whose lists are copies", function()
	local env, sent = mock_build_api()
	local logs, results, inspected = {}, {}, {}
	local ok, message = build.replay(env, street_data(), {
		log = function(line) logs[#logs + 1] = line end,
		on_result = function(_, success, label, outcome) results[#results + 1] = { label, outcome, success } end,
		inspect = function(label, _, edge_list) inspected[#inspected + 1] = label .. " " .. #edge_list end,
		player = 29125,
	})
	assert(ok, message)
	assert(message == "SimpleProposal/table: sent with signature 1", message)
	assert(#sent == 1, "commands sent: " .. #sent)
	local nodes, edges = sent_lists(sent[1].proposal)
	assert(#nodes == 3 and #edges == 2, #nodes .. "/" .. #edges)
	-- Segments keep -1, -2; nodes follow behind them (-3, -4, -5), so no two entities share an id.
	assert(edges[1].entity == -1 and edges[2].entity == -2)
	assert(nodes[1].entity == -3 and nodes[3].entity == -5)
	assert(edges[1].comp.node0 == -3 and edges[1].comp.node1 == -4)
	assert(edges[2].comp.node0 == -4 and edges[2].comp.node1 == -5)
	assert(edges[1].comp.typeIndex == -1 and edges[1].comp.roadType == 1)
	assert(edges[1].comp.roadTemplate == "::/infrastructure/street/town/town_old_small.street_template")
	assert(math.abs(edges[1].comp.tangent0.y - 54.226) < 0.001)
	assert(math.abs(edges[2].comp.position1.x + 2749.069) < 0.001, "position1 is the end node's position")
	assert(edges[1].playerOwned.player == 29125)
	assert(math.abs(nodes[1].comp.position.z - 1.675) < 0.001)
	local lanes = edges[2].comp.laneConfigs
	assert(#lanes == 4, "lanes " .. #lanes)
	assert(lanes[1].width == 3 and lanes[1].forward == false and math.abs(lanes[1].offset - 0.15) < 1e-9)
	assert(lanes[3].forward == true and lanes[3].transportModes[3] == true and lanes[3].transportModes[0] == false)
	assert(build.modes_to_mask(lanes[4].transportModes) == 3)
	assert(edges[1].params.precedenceNode0 == 2 and edges[1].params.precedenceNode1 == 2, "missing params are created")
	assert(edges[2].streetEdge.precedenceNode1 == 2)
	assert(sent[1].context.player == 29125 and sent[1].context.cleanupStreetGraph == true)
	assert(contains(logs, "proposal check SimpleProposal/table: complete, nodes 3/3, edges 2/2, node[1] -3 at -2888.0,-3941.5,1.7, edge[1] -1 type 0 nodes -3->-4 tangent0 69.5,54.2,-0.2 template town_old_small.street_template owner 29125, lanes 4/4 lane[1] width 3 modes 3"),
		table.concat(logs, "\n"))
	assert(not contains(logs, "refused fields"), table.concat(logs, "\n"))
	assert(#inspected == 1 and inspected[1] == "SimpleProposal/table 2", table.concat(inspected, "|"))
	assert(#results == 1 and results[1][1] == "SimpleProposal/table" and results[1][2].built == true)
	assert(results[1][2].costs == 1000 and results[1][2].entities == 5)
end)

test("lists that refuse a Lua table get TF3's vector types, lanes included", function()
	local env, sent = mock_build_api({ refuse_tables = true })
	local logs = {}
	local ok, message = build.replay(env, street_data(), { log = function(line) logs[#logs + 1] = line end })
	assert(ok and message == "SimpleProposal/vector: sent with signature 1", message)
	assert(contains(logs, "SimpleProposal/table refused fields: streetProposal.nodesToAdd: "), table.concat(logs, "\n"))
	assert(contains(logs, "proposal check SimpleProposal/table: INCOMPLETE, nodes 0/3, edges 0/2"))
	assert(contains(logs, "proposal check SimpleProposal/vector: complete, nodes 3/3, edges 2/2"))
	local nodes, edges = sent_lists(sent[1].proposal)
	assert(#nodes == 3 and #edges == 2 and #edges[1].comp.laneConfigs == 4)
end)

test("transport modes are set even when the engine's copy has no keys", function()
	local env, sent = mock_build_api({ empty_modes = true })
	local ok, message = build.replay(env, street_data())
	assert(ok, message)
	local _, edges = sent_lists(sent[1].proposal)
	assert(build.modes_to_mask(edges[1].comp.laneConfigs[2].transportModes) == 14)
end)

test("a proposal that does not read back complete is never sent", function()
	local env, sent = mock_build_api({ lose_positions = true })
	local logs = {}
	local ok, message = build.replay(env, street_data(), { log = function(line) logs[#logs + 1] = line end })
	assert(not ok and message == "no layout could be filled and sent", message)
	assert(#sent == 0, "nothing at the map origin")
	assert(contains(logs, "proposal check SimpleProposal/table: INCOMPLETE, nodes 3/3, edges 2/2, node[1] -3 at 0.0,0.0,0.0, expected at -2888.0,-3941.5,1.7"),
		table.concat(logs, "\n"))
	assert(contains(logs, "proposal check SimpleProposal/vector: INCOMPLETE"))
end)

test("segments whose lanes do not come through are never sent", function()
	local env, sent = mock_build_api({ lose_lanes = true })
	local logs = {}
	local ok, message = build.replay(env, street_data(), { log = function(line) logs[#logs + 1] = line end })
	assert(not ok and #sent == 0, message)
	assert(contains(logs, "lanes 0/4, expected lane[1] width 3 modes 3"), table.concat(logs, "\n"))
end)

test("a replay the game does not build is reported as nothing built", function()
	local env, sent = mock_build_api({ builds = {} })
	local logs, verdicts = {}, {}
	local ok, message = build.replay(env, street_data(), {
		log = function(line) logs[#logs + 1] = line end,
		on_result = function(_, _, label, outcome) verdicts[#verdicts + 1] = label .. "=" .. tostring(outcome.built) end,
	})
	assert(not ok and message == "nothing built with any layout (1 sent)", message)
	assert(#sent == 1 and verdicts[1] == "SimpleProposal/table=false", table.concat(verdicts, " "))
end)

test("a proposal the game cannot compute is not sent again with other signatures", function()
	local env, sent = mock_build_api({ content_error = true })
	local logs = {}
	local ok, message = build.replay(env, street_data(), { log = function(line) logs[#logs + 1] = line end })
	assert(not ok and message:find("^SimpleProposal/table: the game rejected the proposal %(.*Unknown exception%)$"), message)
	assert(#sent == 0)
	assert(contains(logs, "SimpleProposal/table signature 1: "), table.concat(logs, "\n"))
	assert(not contains(logs, "signature 2"), "run 10: the other signatures only repeat the failure")
end)

test("replay logs every failed signature on its own line", function()
	local env, sent = mock_build_api({ required_args = 99 })
	local logs = {}
	local ok, message = build.replay(env, street_data(), { log = function(line) logs[#logs + 1] = line end })
	assert(not ok and message == "SimpleProposal/table: no signature worked", message)
	assert(#sent == 0)
	assert(contains(logs, "SimpleProposal/table signature 5: "), table.concat(logs, "\n"))
end)

test("a missing proposal type is logged", function()
	local env, sent = mock_build_api({ layouts = {} })
	local logs = {}
	local ok, message = build.replay(env, street_data(), { log = function(line) logs[#logs + 1] = line end })
	assert(not ok and message == "no layout could be filled and sent", message)
	assert(contains(logs, "SimpleProposal/table: "), table.concat(logs, "\n"))
	assert(#sent == 0)
end)

test("outcome counts new entities and costs, not the success flag", function()
	local built = build.outcome({ resultEntities = { 4, 5 }, resultProposalData = { costs = 300,
		errorState = { critical = false, messages = { "a" }, warnings = { { text = "b" } } } } })
	assert(built.built == true and built.entities == 2 and built.costs == 300 and built.critical == false)
	assert(built.messages[1] == "message: a" and built.messages[2] == "warning: b", table.concat(built.messages, "|"))
	local empty = build.outcome({ resultEntities = {}, resultProposalData = { costs = 0 } })
	assert(empty.built == false, "run 9: an empty proposal reports success with costs 0")
	assert(build.outcome(nil).built == nil, "no result: unknown")
end)

test("modes_to_mask reads keys 0..15 and lanes survive a round trip", function()
	assert(build.modes_to_mask(modes(0, 1)) == 3)
	assert(build.modes_to_mask(modes(15)) == 32768)
	assert(build.modes_to_mask({}) == 0)
	local text = build.lanes_to_string(town_old_small_lanes())
	assert(text == TOWN_LANES, text)
	local lanes = assert(build.lanes_from_string(text))
	assert(build.lanes_to_string((function()
		local out = {}
		for i, l in ipairs(lanes) do
			local m = {}
			for k = 0, 15 do m[k] = math.floor(l.modes / 2 ^ k) % 2 == 1 end
			out[i] = { speed = l.speed, width = l.width, height = l.height, forward = l.forward, transportModes = m, offset = l.offset }
		end
		return out
	end)()) == text)
	assert(build.lanes_to_string({}) == "-" and build.lanes_from_string("-") == nil)
end)

test("append uses push_back when index assignment fails and reports a nil list", function()
	local v = vector()
	build.append(v, "a")
	build.append(v, "b")
	assert(#v == 2 and v[2] == "b")
	local ok, err = pcall(build.append, nil, "x")
	assert(not ok and tostring(err):find("list is nil", 1, true))
end)

test("side_offset points at a right angle to the first segment", function()
	local data = street_data()
	local dx, dy = build.side_offset(data, 40)
	local t = data.segments[1].tangent0
	assert(math.abs(dx * t.x + dy * t.y) < 1e-6, "perpendicular")
	assert(math.abs(math.sqrt(dx * dx + dy * dy) - 40) < 1e-6, "40 m")
	build.offset(data, dx, dy)
	assert(math.abs(data.nodes[1].position.x - (-2888.017 + dx)) < 0.001)
end)

--- Global engine mock for the main script: game time, player and the build/event commands.
-- @param opts table|nil { bridge_value = TF3MP_IN, no_events = bool, build = mock_build_api opts }
local function with_engine_api(opts, fn)
	opts = opts or {}
	local env, sent = mock_build_api(opts.build)
	local game_time = 1000
	env.api.type.ComponentType = { GAME_TIME = 100 }
	env.api.engine = {
		util = { getWorld = function() return 10 end, getPlayer = function() return 29125 end },
		getComponent = function(_, comp) if comp == 100 then return { gameTime = game_time } end end,
	}
	local events = {}
	env.api.cmd.makeScriptingSendEventCmd = function(a, b, c, d)
		if opts.no_events then error("no script events") end
		return { event = { a, b, c, d } }
	end
	local build_send = env.api.cmd.sendCommand
	env.api.cmd.sendCommand = function(cmd, callback)
		if cmd.event then events[#events + 1] = cmd.event return end
		build_send(cmd, callback)
	end
	local saved_api, saved_os = api, os
	api = env.api
	local ok, err = pcall(fn, {
		env = { api = env.api, os = { getenv = function() return opts.bridge_value end } },
		sent = sent, events = events,
		advance = function(ms) game_time = game_time + ms end,
	})
	api, os = saved_api, saved_os
	if not ok then error(err, 0) end
end

-- TF3 keeps no module variables between calls (runs 7 and 8), so each call below loads a fresh copy
-- of the script, as the game effectively does; only the shared script state carries over.
local function fresh_main() return load_resource("/mp_probe/main.script.lua") end

test("a replay request travels as script event with the line, the event state builds the copy", function()
	with_engine_api({ bridge_value = "replay 7" }, function(t)
		logged = {}
		local state = mock_state()
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param())
		local s = state:get()
		assert(s.last_build, "the capture is kept in the script state")
		fresh_main().bridge_tick(t.env, 1, s)
		fresh_main().bridge_tick(t.env, 2, s)
		assert(#t.events == 1, "the same request is forwarded once: " .. #t.events)
		assert(s.last_replay_request == 7 and s.replays_requested == 1)
		assert(contains(logged, "replay #1 requested as script event (signature 1"), table.concat(logged, "\n"))
		local ev = t.events[1]
		assert(ev[4].line == s.last_build, "the line travels in the event parameter")
		state:set(s)
		fresh_main().handleEvent(nil, state, ev[1], ev[2], ev[3], ev[4])
		assert(contains(logged, "replay event received (src=mp_probe id=mp_probe_replay, line "))
		assert(contains(logged, "replay #1: 3 nodes, 2 segments, 0 existing nodes, 0 removed segments"), table.concat(logged, "\n"))
		assert(contains(logged, "player 29125"))
		assert(contains(logged, "replay proposal check SimpleProposal/table: complete, nodes 3/3, edges 2/2"))
		assert(contains(logged, "---- replay proposal SimpleProposal/table edge[1]"), table.concat(logged, "\n"))
		assert(contains(logged, "edge[1].comp.laneConfigs = table (#4)"))
		assert(contains(logged, "edge[1].comp.laneConfigs[1].width = number 3"))
		assert(contains(logged, "replay: sent, SimpleProposal/table: sent with signature 1"))
		assert(contains(logged, "replay result (SimpleProposal/table): BUILT, success=true, costs 1000, new entities 5"),
			table.concat(logged, "\n"))
		assert(contains(logged, "res.resultProposalData.costs = number 1000"))
		assert(#t.sent == 1)
		local _, edges = sent_lists(t.sent[1].proposal)
		assert(edges[1].comp.roadTemplate == "::/infrastructure/street/town/town_old_small.street_template")
		assert(edges[1].playerOwned.player == 29125)
		-- The copy's own build event comes back within the quiet time and is not captured again.
		t.advance(2000)
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param())
		assert(contains(logged, "build right after a replay (probably the copy, not captured): segments=2 nodes=3 constructions=0 new entities=1 player build=true"),
			table.concat(logged, "\n"))
		-- Run 10: town buildings and other player builds in the quiet time are not taken for the copy.
		logged = {}
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", town_build_param())
		assert(not contains(logged, "build right after a replay"), table.concat(logged, "\n"))
		local other = player_build_param()
		other[1].proposal.addedSegments = { other[1].proposal.addedSegments[1] }
		other[1].proposal.addedNodes = { other[1].proposal.addedNodes[1], other[1].proposal.addedNodes[2] }
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", other)
		assert(contains(logged, "capture player build nodes=2 segments=1"), table.concat(logged, "\n"))
		state:set(s)
		-- Later builds are captured again.
		t.advance(fresh_main().REPLAY_QUIET_MS)
		logged = {}
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param())
		assert(contains(logged, "capture stored for replay"))
	end)
end)

test("a stored capture is logged behind the send marker for the DLL", function()
	with_engine_api({}, function()
		logged = {}
		local main = fresh_main()
		main.handleEvent(nil, mock_state(), "", "apply_command", "onPostBuildProposal", player_build_param())
		local found
		for _, line in ipairs(logged) do
			local at = line:find(main.SEND_MARKER, 1, true)
			if at then found = line:sub(at + #main.SEND_MARKER) end
		end
		assert(found and found:sub(1, 3) == "B4 ", table.concat(logged, "\n"))
		assert(build.deserialize(found), "the sent line parses")
	end)
end)

test("a line from the other PC is built in place, once, and acknowledged on every tick", function()
	local line = build.serialize(run5_street())
	with_engine_api({ bridge_value = "line 4711.1 net " .. line }, function(t)
		logged = {}
		local s = {}
		fresh_main().bridge_tick(t.env, 1, s)
		fresh_main().bridge_tick(t.env, 2, s)
		assert(#t.events == 1, "built once: " .. #t.events)
		local acks = 0
		for _, l in ipairs(logged) do
			if l:find("net received token=4711.1 kind=net (" .. #line .. " characters)", 1, true) then acks = acks + 1 end
		end
		assert(acks == 2, "acknowledged on every tick: " .. acks .. "\n" .. table.concat(logged, "\n"))
		local ev = t.events[1]
		assert(ev[4].line == line and ev[4].offset == 0 and ev[4].source == "net")
		logged = {}
		fresh_main().handleEvent(nil, mock_state(), ev[1], ev[2], ev[3], ev[4])
		assert(contains(logged, "replay #4711.1: 3 nodes, 2 segments, ") and contains(logged, "moved by 0.0,0.0"),
			table.concat(logged, "\n"))
		assert(contains(logged, "replay result (SimpleProposal/table): BUILT"))
		local nodes = sent_lists(t.sent[1].proposal)
		assert(math.abs(nodes[1].comp.position.x - (-2888.017)) < 0.001, "built in place")
	end)
end)

test("a loopback line is built beside the original", function()
	local line = build.serialize(run5_street())
	with_engine_api({ bridge_value = "line 9.2 loop " .. line }, function(t)
		logged = {}
		local s = { last_line_token = "9.1" }
		fresh_main().bridge_tick(t.env, 1, s)
		assert(#t.events == 1 and s.last_line_token == "9.2")
		local ev = t.events[1]
		assert(ev[4].offset == fresh_main().REPLAY_SIDE_OFFSET and ev[4].source == "loop")
		logged = {}
		fresh_main().handleEvent(nil, mock_state(), ev[1], ev[2], ev[3], ev[4])
		assert(not contains(logged, "moved by 0.0,0.0"), table.concat(logged, "\n"))
		assert(contains(logged, "replay result (SimpleProposal/table): BUILT"))
		local nodes = sent_lists(t.sent[1].proposal)
		assert(math.abs(nodes[1].comp.position.y - (-3941.508 + 40)) < 0.01, "moved 40 m north")
	end)
end)

test("without script events a received line is built in the update state", function()
	with_engine_api({ bridge_value = "line 1.1 net " .. build.serialize(run5_street()), no_events = true }, function(t)
		logged = {}
		fresh_main().bridge_tick(t.env, 1, {})
		assert(contains(logged, "line 1.1: no script event possible, building in the update state"), table.concat(logged, "\n"))
		assert(#t.sent == 1)
	end)
end)

test("a replay that builds nothing is reported as such", function()
	with_engine_api({ build = { builds = {} } }, function(t)
		logged = {}
		local state = mock_state()
		fresh_main().handleEvent(nil, state, "mp_probe", "mp_probe_replay", "mp_probe_replay",
			{ line = build.serialize(run5_street()), number = 1 })
		assert(#t.sent == 1, "sent " .. #t.sent)
		assert(contains(logged, "replay result (SimpleProposal/table): NOTHING BUILT, success=true, costs 0, new entities 0"),
			table.concat(logged, "\n"))
		assert(contains(logged, "replay result warning: nothing to build"))
		assert(contains(logged, "replay: failed, nothing built with any layout (1 sent)"))
	end)
end)

test("a proposal the game rejects is logged once", function()
	with_engine_api({ build = { content_error = true } }, function(t)
		logged = {}
		fresh_main().handleEvent(nil, mock_state(), "mp_probe", "mp_probe_replay", "mp_probe_replay",
			{ line = build.serialize(run5_street()), number = 1 })
		assert(#t.sent == 0)
		assert(contains(logged, "replay: failed, SimpleProposal/table: the game rejected the proposal ("), table.concat(logged, "\n"))
		assert(contains(logged, "Unknown exception)"))
	end)
end)

test("a replay event without a parameter falls back to the line in the script state", function()
	with_engine_api({}, function(t)
		logged = {}
		local state = mock_state()
		state:set({ last_build = build.serialize(run5_street()) })
		fresh_main().handleEvent(nil, state, "mp_probe", "mp_probe_replay", "mp_probe_replay", nil)
		assert(contains(logged, "line missing"), table.concat(logged, "\n"))
		assert(contains(logged, "replay: sent, SimpleProposal/table"))
		assert(#t.sent == 1)
	end)
end)

test("without script events the update state replays the line from the script state", function()
	with_engine_api({ bridge_value = "replay 3", no_events = true }, function(t)
		logged = {}
		local s = { last_build = build.serialize(run5_street()) }
		fresh_main().bridge_tick(t.env, 1, s)
		assert(contains(logged, "replay event signature 3: "), table.concat(logged, "\n"))
		assert(contains(logged, "replay: no script event possible, replaying in the update state"))
		assert(contains(logged, "replay: sent, SimpleProposal/table"))
		assert(#t.sent == 1)
	end)
end)

test("replay requests stop after MAX_REPLAYS and need a capture first", function()
	with_engine_api({}, function(t)
		logged = {}
		local s = {}
		fresh_main().request_replay(t.env, s, 1)
		assert(contains(logged, "replay: no captured build in the script state yet"))
		s.last_build = build.serialize(run5_street())
		local main = fresh_main()
		for i = 1, main.MAX_REPLAYS + 1 do fresh_main().request_replay(t.env, s, i) end
		assert(#t.events == main.MAX_REPLAYS, "events " .. #t.events)
		assert(contains(logged, "replay: limit of " .. main.MAX_REPLAYS .. " reached"))
	end)
end)

test("a new probe version gives a savegame its replays back", function()
	local main = fresh_main()
	logged = {}
	local state = mock_state()
	state:set({ probe_version = main.PROBE_VERSION, subscribed = main.PROBE_VERSION, replays_requested = 3,
		replay_version = main.PROBE_VERSION - 1, last_build = "B3" })
	main.update(nil, state, 0)
	assert(state:get().replays_requested == 0)
	assert(state:get().last_build == "B3", "the capture stays")
	state:get().replays_requested = 2
	fresh_main().update(nil, state, 0)
	assert(state:get().replays_requested == 2, "reset once per version")
end)

--- Depot build of run 12 (logs/probe-log-12-mp_probe.txt, "player #3"): one construction, its
-- entrance segment touches the frozen node (0-based index 1) and is left to the construction.
local function depot_param()
	local transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2970.633, -3889.26, 3.18, 1 }
	local seg = run5_street().addedSegments[1]
	seg.comp.node0, seg.comp.node1 = 50605, 45373
	return {
		{
			proposal = {
				addedNodes = {
					{ entity = 50605, comp = { position = { x = -2970.633, y = -3896.631, z = 3.18 } } },
					{ entity = 45373, comp = { position = { x = -2970.633, y = -3881.891, z = 3.18 } } },
				},
				addedSegments = { seg },
				frozenNodes = { 1 },
			},
			toAdd = { { fileName = "::/depots/road/road_depot/road_depot.con", name = "Rehna Strassendepot Süd",
				params = { seed = 12, paramX = 0.5, modules = { [3] = "a b;c" }, flag = true }, transf = transf,
				playerEntity = 29125 } },
			toRemove = {},
		},
		{}, { 51088 }, true,
	}
end

test("a construction travels with file, name, transf and params, without its own segments", function()
	with_engine_api({}, function(t)
		local main = fresh_main()
		logged = {}
		local state = mock_state()
		main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", depot_param())
		assert(contains(logged, "capture player build nodes=0 segments=0 foreign_nodes=0 removed_segments=0 removed_nodes=0 constructions=1"),
			table.concat(logged, "\n"))
		assert(contains(logged, "capture leaves out segment"), "the entrance is the construction's own")
		local line = state:get().last_build
		assert(line and line:find(" c;%3A%3A%2Fdepots%2Froad%2Froad_depot%2Froad_depot.con;Rehna%20Strassendepot%20S%C3%BCd;1,0,0,0,0,1,0,0,0,0,1,0,-2970.633,-3889.26,3.18,1;{", 1, true), line)
		local data = assert(build.deserialize(line))
		local c = data.constructions[1]
		assert(c.name == "Rehna Strassendepot Süd" and c.file == "::/depots/road/road_depot/road_depot.con")
		assert(c.params.seed == 12 and c.params.paramX == 0.5 and c.params.flag == true and c.params.modules[3] == "a b;c")
		logged = {}
		fresh_main().replay_line(t.env, line, "c1", nil, 0)
		assert(contains(logged, "replay proposal check SimpleProposal/table: complete") and contains(logged, "constructionsToAdd 1/1"),
			table.concat(logged, "\n"))
		local sent = t.sent[1].proposal.constructionsToAdd[1]
		assert(sent.fileName == c.file and sent.name == c.name and sent.playerEntity == 29125)
		assert(sent.transf[13] == -2970.633 and sent.params.modules[3] == "a b;c")
	end)
end)

test("world finds nodes, edges and constructions of the running game by position", function()
	local world = require("/mp_probe/world.lua")
	local comps = {
		[1] = { BASE_NODE = { position = { x = 100, y = 200, z = 5 } } },
		[2] = { BASE_NODE = { position = { x = 100.8, y = 200.9, z = 5 } } },
		[3] = { BASE_NODE = { position = { x = 100.5, y = 200.5, z = 15 } } },
		[4] = { BASE_NODE = { position = { x = 300, y = 200, z = 0 } } },
		[10] = { BASE_EDGE = { node0 = 4, node1 = 1 } },
		[20] = { CONSTRUCTION = { fileName = "a.con", transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 50, 60, 0, 1 } },
			PLAYER_OWNED = { player = 7 } },
		[21] = { CONSTRUCTION = { fileName = "town.con", transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } },
			PLAYER_OWNED = { player = -1 } },
	}
	local env = { api = { type = { ComponentType = { BASE_NODE = "BASE_NODE", BASE_EDGE = "BASE_EDGE",
		CONSTRUCTION = "CONSTRUCTION", PLAYER_OWNED = "PLAYER_OWNED" } },
		engine = {
			getComponent = function(id, ct) return comps[id] and comps[id][ct] end,
			forEachEntityWithComponent = function(fn, ct)
				local ids = {}
				for id, c in pairs(comps) do if c[ct] then ids[#ids + 1] = id end end
				table.sort(ids)
				for _, id in ipairs(ids) do fn(id) end
			end,
			system = { streetSystem = {} },
		} } }
	local index = world.node_index(env)
	assert(world.find_node(index, { x = 100.1, y = 200.1, z = 5 }) == 1, "the closest node")
	assert(world.find_node(index, { x = 100.6, y = 200.6, z = 15 }) == 3, "height breaks the tie")
	assert(world.find_node(index, { x = 103, y = 200, z = 5 }) == nil, "nothing within 1.5 m")
	assert(world.find_edge(env, 1, 4) == 10 and world.find_edge(env, 1, 2) == nil)
	assert(world.find_construction(env, "a.con", { x = 51, y = 60, z = 0 }) == 20)
	assert(world.find_construction(env, "a.con", { x = 55, y = 60, z = 0 }) == nil)
	local mine = world.player_constructions(env)
	assert(mine[20] and mine[20].position.y == 60 and mine[21] == nil)
end)

test("world finds nodes and edges when the game refuses to loop over them (run 13)", function()
	local world = require("/mp_probe/world.lua")
	local comps = {
		[1] = { BASE_NODE = { position = { x = 100, y = 200, z = 5 } } },
		[4] = { BASE_NODE = { position = { x = 300, y = 200, z = 0 } } },
		[10] = { BASE_EDGE = { node0 = 4, node1 = 1 } },
	}
	local env = { api = { type = { ComponentType = { BASE_NODE = "BASE_NODE", BASE_EDGE = "BASE_EDGE" } },
		engine = {
			getComponent = function(id, ct) return comps[id] and comps[id][ct] end,
			forEachEntityWithComponent = function() error("Cannot loop over this component type") end,
			getEntitiesWithComponent = function() error("Cannot loop over this component type") end,
			system = { streetSystem = { getNode2SegmentMap = function() return { [1] = { 10 }, [4] = { 10 } } end } },
		} } }
	local index = world.node_index(env)
	assert(world.find_node(index, { x = 100.4, y = 199.8, z = 5 }) == 1)
	assert(world.find_node(index, { x = 300, y = 201, z = 0 }) == 4)
	assert(world.find_edge(env, 1, 4) == 10)
	env.api.engine.system.streetSystem = {}
	local ok, err = pcall(world.node_index, env)
	assert(not ok and tostring(err):find("cannot list BASE_NODE"), tostring(err))
end)

test("params literals survive a round trip and reject broken text", function()
	local value = { 1, 2.5, -3, { x = "y z" }, seed = 42, s = "", b = false, nested = { [10] = { "%;|" } } }
	local text = build.params_to_string(value)
	assert(not text:find("[ ;|]"), text)
	local back = assert(build.params_from_string(text))
	assert(back[2] == 2.5 and back[3] == -3 and back[4].x == "y z" and back.seed == 42 and back.s == "" and back.b == false)
	assert(back.nested[10][1] == "%;|")
	assert(build.params_to_string(back) == text, "deterministic")
	assert(build.params_from_string("{sa=n1") == nil and build.params_from_string("x") == nil)
	assert(build.params_from_string("n1junk") == nil)
	assert(not pcall(build.params_to_string, { f = print }), "functions cannot travel")
end)

test("replay without the engine api says so", function()
	local ok, message = build.replay({}, { nodes = {}, segments = {} })
	assert(not ok and message == "api missing", message)
end)

print(string.format("%d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

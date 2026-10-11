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
	assert(#state.subscribed == #main.SUBSCRIBED_EVENTS and state.subscribed[1] == "onPostBuildProposal", "subscribed once")
	assert(state.subscribed[2] == main.REPLAY_EVENT, "our own replay event is subscribed too")
	assert(state.subscribed[3] == "Obtain" and state.subscribed[4] == "Repay", "original loan operations subscribed")
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

test("a reverse clicked in the GUI is noted for the next action poll (v35)", function()
	local main = load_resource("/mp_probe/main.script.lua")
	logged = {}
	local state = mock_state()
	main.handleEvent(nil, state, "mp_probe", "mp_probe_reverse", "mp_probe_reverse", { vehicle = 117350 })
	assert(state:get().actions.user_reverse["117350"] == true)
	assert(contains(logged, "reverse clicked for vehicle 117350"))
	main.handleEvent(nil, state, "mp_probe", "mp_probe_reverse", "mp_probe_reverse", { vehicle = "x" })
	assert(contains(logged, "invalid vehicle id"))
	local found = false
	for _, e in ipairs(main.SUBSCRIBED_EVENTS) do if e == "mp_probe_reverse" then found = true end end
	assert(found, "not subscribed")
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
	assert(line:sub(1, 2) == "B5", line)
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

test("a removed segment whose end node is gone uses its own end positions (run 14)", function()
	local proposal = run5_street()
	proposal.addedNodes = { proposal.addedNodes[1], proposal.addedNodes[2] }
	proposal.removedSegments = { { entity = -50806, type = 0, comp = { node0 = 48724, node1 = 45373,
		position0 = { x = -2841.78, y = -3959.66, z = 2.45 }, position1 = { x = -2763.81, y = -3964.86, z = 2.26 } } } }
	local positions = { [51458] = { x = 30, y = 40, z = 2 } }
	local line, info = build.serialize(proposal, { node_position = function(id) return positions[id] end })
	assert(info.removed_segments == 1, line)
	assert(line:find(" r;-2841.78,-3959.66,2.45;-2763.81,-3964.86,2.26;0", 1, true), line)
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
	assert(build.deserialize("B5 n-1;1,2") == nil, "a short position is rejected")
	assert(build.deserialize("B5 s-1;0;-1") == nil, "a short segment is rejected")
	assert(build.deserialize("B5 s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;7;-;-") == nil, "an undefined road type is rejected")
	assert(build.deserialize("B5 t1;a;b;1,2,3 s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1;-;-") == nil, "a short lane is rejected")
	assert(build.deserialize("B5 t1;a;b s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1;-;-") == nil, "a road token without lanes is rejected")
	assert(build.deserialize("B2 s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1") == nil, "format 2 lacks the lanes")
	local no_lanes = assert(build.deserialize("B5 t1;a;b;- s-1;0;-1;-2;1,0,0;1,0,0;-1;1;0;1;-;-"))
	assert(no_lanes.segments[1].lanes == nil and no_lanes.segments[1].params == nil)
	assert(build.deserialize("B5 s-1;0;f1;-2;1,0,0;1,0,0;-1;1;0;1;-;-") == nil, "an unknown existing node is rejected")
	assert(build.deserialize("B5 c;a;b;1,2;n1") == nil, "a construction needs 16 transf numbers")
	assert(build.deserialize(42) == nil)
	local data = assert(build.deserialize("B5"), "an empty proposal parses")
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
					laneConfigs = "list", objects = "list",
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
					edgesToRemove = "list", nodesToRemove = "list", edgeObjectsToAdd = "list",
					edgeObjectsToRemove = "list", nodeConfigsToRemove = "list" }, list_opts),
				constructionsToAdd = "list",
				constructionsToRemove = "list",
				old2new = {},
			})
		end, ConstructionEntity = { new = function()
			return struct("ConstructionEntity", { fileName = "", name = "", params = {}, playerEntity = -1,
				transf = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } })
		end } }
	end
	t.SimpleStreetProposal = { EdgeObject = { new = function()
		return struct("EdgeObject", { edgeEntity = 0, param = 0, oneWay = false, left = false, model = "",
			playerEntity = -1, name = "" })
	end } }
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
				-- TF3 indexes edgeObjectsToAdd from -400000000, zero based.
				do
					local edges = proposal.streetProposal.edgesToAdd
					for i = 1, #edges do
						local objects = edges[i].comp.objects
						for j = 1, #objects do
							local id = objects[j][1]
							if id < 0 and not (id <= -400000000 and id > -500000000) then error("Unknown exception", 2) end
							if id < 0 then assert(-400000000 - id < #proposal.streetProposal.edgeObjectsToAdd, "edge object index out of bounds") end
						end
					end
				end
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
	assert(sent[1].context.player == 29125 and sent[1].context.cleanupStreetGraph == false)
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

local function demolition_replay(opts)
	local env, sent = mock_build_api()
	local data = assert(build.deserialize("B5"))
	data.removed_segments = { { entity = 501 } }
	data.demolished = { { entity = 502, file = "::/depots/rail/rail_depot.con" } }
	if opts.station then
		-- run 28: resolve leaves the station's own edges/nodes to the construction removal.
		data.removed_segments = {}
		data.demolished[1].file = "::/stations/rail/modular_station/modular_station.con"
		for i = 1, 24 do data.removed_nodes[i] = { x = i, y = 0, z = 0 } end
	end
	local exists = { [501] = not opts.already_missing, [502] = true }
	local executed, queries = false, 0
	env.api.engine = { entityExists = function(id)
		queries = queries + 1
		if opts.lookup_fails or (opts.lookup_fails_after and executed) then error("world unavailable") end
		return exists[id] == true
	end }
	if opts.callable then
		local lookup = env.api.engine.entityExists
		env.api.engine.entityExists = setmetatable({}, { __call = function(_, id) return lookup(id) end })
		assert(type(env.api.engine.entityExists) == "table", "the real TF3 API is a callable table")
	end
	if opts.no_lookup then env.api.engine.entityExists = nil end
	if opts.addition then data = street_data(); data.removed_segments = { { entity = 501 } } end
	local verdict
	local function execute(callback)
		executed = true
		if not opts.no_effect then exists[501] = nil end
		if not opts.partial and not opts.no_effect then exists[502] = nil end
		return callback({ resultEntities = {}, resultProposalData = { costs = opts.costs or 0,
			errorState = { critical = opts.critical == true } } }, opts.success ~= false)
	end
	local deferred, callback_return
	env.api.cmd.sendCommand = function(cmd, callback)
		sent[#sent + 1] = cmd
		if opts.deferred then deferred = function() callback_return = execute(callback) end
		else callback_return = execute(callback) end
	end
	local rejected
	local ok, message = build.replay(env, data, {
		on_result = function(_, _, _, outcome) verdict = outcome end,
		on_rejected = function(text) rejected = text end,
	})
	if deferred then deferred() end
	return ok, message, verdict, sent, rejected, callback_return, queries
end

test("zero-cost and refunded demolition are confirmed against the world", function()
	for _, costs in ipairs({ 0, -500, 500 }) do
		local ok, message, verdict, sent = demolition_replay({ costs = costs })
		assert(ok and #sent == 1, message)
		assert(verdict.built == true and verdict.removed == 2 and verdict.entities == 0 and verdict.costs == costs)
	end
end)

test("run 28 station demolition accepts TF3 callable-table lookups and ignores its owned nodes", function()
	local ok, message, verdict, sent, _, _, queries = demolition_replay({ station = true, callable = true, costs = 4698 })
	assert(ok and #sent == 1, message)
	assert(verdict.built == true and verdict.removed == 1 and verdict.entities == 0 and not verdict.removal_error)
	assert(queries == 2, "check the one construction before and after execution")
	assert(sent[1].proposal.constructionsToRemove[1] == 502)
	assert(#sent[1].proposal.streetProposal.nodesToRemove == 0, "the game removes the station's own nodes")
end)

test("unconfirmed demolition reports the target and the failed verification stage", function()
	local cases = {
		{ opts = { no_effect = true }, text = "entity still present after removal: 501" },
		{ opts = { partial = true }, text = "entity still present after removal: 502" },
		{ opts = { already_missing = true }, text = "removal target missing before send: entity 501" },
		{ opts = { lookup_fails = true }, text = "removal lookup unreadable before send for entity 501" },
		{ opts = { lookup_fails_after = true }, text = "removal lookup unreadable after execution for entity 501" },
	}
	for _, case in ipairs(cases) do
		local ok, message, verdict = demolition_replay(case.opts)
		assert(not ok and verdict.built == false and verdict.removal_error:find(case.text, 1, true), message)
		assert(message:find(case.text, 1, true), "the failed network action must retain its verification reason")
	end
end)

test("demolition cannot accept a no-op, partial removal or already absent target", function()
	for _, opts in ipairs({ { no_effect = true }, { partial = true }, { already_missing = true },
		{ no_effect = true, costs = 500 }, { already_missing = true, costs = 500 } }) do
		local ok, message, verdict = demolition_replay(opts)
		assert(not ok and verdict.built == false and not verdict.removed, message)
	end
end)

test("demolition without a working world lookup stays unconfirmed", function()
	for _, opts in ipairs({ { no_lookup = true }, { lookup_fails = true }, { no_lookup = true, costs = 500 } }) do
		local ok, message, verdict = demolition_replay(opts)
		assert(not ok and verdict.built == false, message)
	end
end)

test("removing an old entity does not prove that its replacement was built", function()
	local ok, message, verdict = demolition_replay({ addition = true })
	assert(not ok and verdict.built == false and not verdict.removed, message)
end)

test("demolition confirmation also waits for asynchronous execution", function()
	local ok, message, verdict, _, rejected, callback_return = demolition_replay({ deferred = true, costs = -500 })
	assert(ok and verdict.built == true and verdict.removed == 2 and not rejected, message)
	assert(callback_return == true, "the build callback owns the transport verdict")
	ok, message, verdict, _, rejected = demolition_replay({ deferred = true, no_effect = true })
	assert(ok and verdict.built == false and rejected:find("asynchronous build produced nothing", 1, true), message)
end)

test("explicit or critical rejection overrides apparent construction work", function()
	for _, kind in ipairs({ "success", "critical" }) do
		local env = mock_build_api()
		env.api.cmd.sendCommand = function(_, callback)
			assert(callback({ resultEntities = { 1001 }, resultProposalData = { costs = 500,
				errorState = { critical = kind == "critical" } } }, kind ~= "success") == true)
		end
		local ok, message = build.replay(env, street_data())
		assert(not ok and message:find("nothing built", 1, true), message)
	end
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
		if cmd.speed then return end
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
		assert(#t.sent == 1)
		local _, edges = sent_lists(t.sent[1].proposal)
		assert(edges[1].comp.roadTemplate == "::/infrastructure/street/town/town_old_small.street_template")
		assert(edges[1].playerOwned.player == 29125)
		-- The copy's own build event comes back within the quiet time and is not captured again.
		t.advance(2000)
		-- Run 11: the copy's event has isPlayerBuild=false.
		local copy = player_build_param()
		copy[4] = false
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", copy)
		assert(contains(logged, "build right after a replay (probably the copy, not captured): segments=2 nodes=3 constructions=0 new entities=1 player build=false"),
			table.concat(logged, "\n"))
		-- Run 14: a real player build of the same size in the quiet time is captured.
		logged = {}
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param())
		assert(contains(logged, "capture player build nodes=3 segments=2"), table.concat(logged, "\n"))
		state:set(s)
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
		assert(found and found:sub(1, 3) == "B5 ", table.concat(logged, "\n"))
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
		assert(math.abs(nodes[1].comp.position.y - (-3941.508 + 100)) < 0.01, "moved 100 m north")
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

test("a received line is taken between bridge ticks, without the bridge marker (v25)", function()
	local line = build.serialize(run5_street())
	with_engine_api({}, function(t)
		local main = fresh_main()
		local value = "line 77.1 net " .. line
		local saved_os = os
		os = setmetatable({ getenv = function(name) if name == "TF3MP_IN" then return value end end }, { __index = saved_os })
		logged = {}
		local state = mock_state()
		state:set({ probe_version = main.PROBE_VERSION, subscribed = main.PROBE_VERSION,
			replay_version = main.PROBE_VERSION, constructions_scanned = main.PROBE_VERSION,
			actions_version = main.PROBE_VERSION, updates = 0 })
		local ok, err = pcall(function()
			for _ = 1, main.INBOX_EVERY do fresh_main().update(nil, state, 0) end
			assert(#t.events == 1 and t.events[1][4].number == "77.1", "events " .. #t.events)
			assert(contains(logged, "net received token=77.1 kind=net"))
			assert(not contains(logged, "bridge out seq="), "no marker between bridge ticks")
			-- The same line is not taken twice; the regular bridge tick still comes every BRIDGE_EVERY.
			for _ = main.INBOX_EVERY + 1, main.BRIDGE_EVERY do fresh_main().update(nil, state, 0) end
			assert(#t.events == 1 and contains(logged, "bridge out seq=1"))
			value = "ack 1"
			for _ = 1, main.INBOX_EVERY do fresh_main().update(nil, state, 0) end
			assert(#t.events == 1)
		end)
		os = saved_os
		assert(ok, err)
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
-- Run 12: a depot placed away from roads; its entrance street 50605 -> 45373 (gate, frozen) ends in
-- a new node nothing else uses. With `at_road` the entrance meets an existing road end node 50605.
local DEPOT_ROAD_NODE = { x = -2970.633, y = -3896.631, z = 3.18 }
local function depot_param(at_road)
	local transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2970.633, -3889.26, 3.18, 1 }
	local seg = run5_street().addedSegments[1]
	seg.entity = 50524
	seg.comp.node0, seg.comp.node1 = 50605, 45373
	local nodes = {
		{ entity = 50605, comp = { position = DEPOT_ROAD_NODE } },
		{ entity = 45373, comp = { position = { x = -2970.633, y = -3881.891, z = 3.18 } } },
	}
	local frozen = { 1 }
	if at_road then
		table.remove(nodes, 1)
		frozen = { 0 }
	end
	return {
		{
			proposal = {
				addedNodes = nodes,
				addedSegments = { seg },
				frozenNodes = frozen,
			},
			toAdd = { { fileName = "::/depots/road/road_depot/road_depot.con", name = "Rehna Strassendepot Süd",
				params = { seed = 12, paramX = 0.5, modules = { [3] = "a b;c" }, flag = true }, transf = transf,
				playerEntity = 29125 } },
			toRemove = {},
		},
		{}, { 51088 }, true,
	}
end

-- The engine of with_engine_api knows the road end node 50605 the depot's entrance meets.
local function with_depot_road(t, m)
	t.env.api.type.ComponentType.BASE_NODE = "BASE_NODE"
	local get = t.env.api.engine.getComponent
	t.env.api.engine.getComponent = function(id, ct)
		if ct == "BASE_NODE" and id == 50605 then return { position = DEPOT_ROAD_NODE } end
		return get(id, ct)
	end
	m.finder = function()
		return {
			find_node = function(p)
				if math.abs(p.x - DEPOT_ROAD_NODE.x) < 0.01 and math.abs(p.y - DEPOT_ROAD_NODE.y) < 0.01 then return 50605 end
			end,
			find_edge = function() return nil end,
			find_construction = function() return nil end,
			edge_objects_of = function() return {} end,
			edge_construction = function() return nil end,
		}
	end
end

test("a construction travels with file, name, transf, params and its entrance, which the copy leaves out (v21)", function()
	with_engine_api({}, function(t)
		local main = fresh_main()
		with_depot_road(t, main)
		logged = {}
		local state = mock_state()
		main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", depot_param(true))
		-- v20: the entrance street travels along, its gate node (frozen) marked "g".
		assert(contains(logged, "capture player build nodes=1 segments=1 foreign_nodes=1 removed_segments=0 removed_nodes=0 constructions=1"),
			table.concat(logged, "\n"))
		assert(contains(logged, "access_segments=1"), table.concat(logged, "\n"))
		local line = state:get().last_build
		assert(line and line:find(" c;%3A%3A%2Fdepots%2Froad%2Froad_depot%2Froad_depot.con;Rehna%20Strassendepot%20S%C3%BCd;1,0,0,0,0,1,0,0,0,0,1,0,-2970.633,-3889.26,3.18,1;{", 1, true), line)
		assert(line:find(" g;-1 ", 1, true) and line:find(" a;1 ", 1, true), line)
		local data = assert(build.deserialize(line))
		assert(data.gates[-1] and data.access[-1], "gate and entrance parsed")
		local c = data.constructions[1]
		assert(c.name == "Rehna Strassendepot Süd" and c.file == "::/depots/road/road_depot/road_depot.con")
		assert(c.params.seed == 12 and c.params.paramX == 0.5 and c.params.flag == true and c.params.modules[3] == "a b;c")
		logged = {}
		local receiver = fresh_main()
		with_depot_road(t, receiver)
		receiver.replay_line(t.env, line, "c1", nil, 0)
		assert(contains(logged, "replay proposal check SimpleProposal/table: complete") and contains(logged, "constructionsToAdd 1/1"),
			table.concat(logged, "\n"))
		local sent = t.sent[1].proposal.constructionsToAdd[1]
		assert(sent.fileName == c.file and sent.name == c.name and sent.playerEntity == 29125)
		assert(sent.transf[13] == -2970.633 and sent.params.modules[3] == "a b;c")
		-- Run 20b: the copied construction lays its own entrance; a second one would end beside it.
		local _, edges = sent_lists(t.sent[1].proposal)
		assert(#edges == 0, "the entrance street is left out")
		assert(contains(logged, "replay: 1 entrance segment(s) left out, the construction lays its own"),
			table.concat(logged, "\n"))
		-- The command was described before sending, and the weld was checked afterwards.
		assert(contains(logged, "weld command before sending: command fields {"), table.concat(logged, "\n"))
		assert(contains(logged, "weld: the copied road_depot.con near -2970.6,-3889.3 is not here"), table.concat(logged, "\n"))
	end)
end)

test("a build line too long for the network is reported instead of sent (v26)", function()
	with_engine_api({}, function()
		local main = fresh_main()
		main.MAX_LINE = 100
		logged = {}
		local state = mock_state()
		main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param())
		local all = table.concat(logged, "\n")
		assert(state:get().last_build, "kept for the local replay")
		assert(contains(logged, "capture line TOO LONG for the network ("), all)
		assert(contains(logged, "characters, at most 100): the other game does not get this build"), all)
		for _, l in ipairs(logged) do assert(not l:find("net send ", 1, true), l) end
	end)
end)

test("a depot away from roads travels without its entrance stub, the copy gets no weld repair (v26, run 12)", function()
	with_engine_api({}, function(t)
		logged = {}
		local state = mock_state()
		fresh_main().handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", depot_param())
		local all = table.concat(logged, "\n")
		assert(contains(logged, "capture player build nodes=0 segments=0 foreign_nodes=0 removed_segments=0 removed_nodes=0 constructions=1"), all)
		assert(contains(logged, "access_segments=0"), all)
		assert(contains(logged, "capture leaves out segment 50524 (end stub of a construction)"), all)
		local line = state:get().last_build
		assert(line and not line:find(" g;", 1, true) and not line:find(" a;", 1, true), line)
		logged = {}
		fresh_main().replay_line(t.env, line, "c1", nil, 0)
		all = table.concat(logged, "\n")
		assert(contains(logged, "constructionsToAdd 1/1"), all)
		assert(not contains(logged, "entrance segment(s) left out") and not contains(logged, "weld"), all)
	end)
end)

--- Run 5: a modular station on a straight track, 25 nodes along y, all frozen but the free ends of
-- the two stubs at the track ends (indexes 1 and 24).
local function run5_station()
	local function node(id, y) return { entity = id, comp = { position = { x = -2139.415, y = y, z = 1.209 } } } end
	local nodes = { node(50154, -3717.232), node(50460, -3719.232) }
	local y = -3717.232
	for i = 3, 25 do
		y = y + ((i % 2 == 1) and 16 or 2)
		nodes[i] = node(51812 + i, y)
	end
	local frozen = {}
	for i = 0, 24 do if i ~= 1 and i ~= 24 then frozen[#frozen + 1] = i end end
	local track = run5_street().addedSegments[1]
	local function seg(id, a, b)
		local s = { entity = id, type = 1, comp = {} }
		for k, v in pairs(track.comp) do s.comp[k] = v end
		s.comp.node0, s.comp.node1, s.comp.roadType = a, b, 0
		s.comp.roadTemplate = "::/trainstation___/infrastructure/track/simple/simple.street_template"
		s.comp.roadStyle = "::/infrastructure/track/simple/simple.street"
		return s
	end
	local segs = { seg(51838, 50154, 50460), seg(51839, 51815, 50154) }
	for i = 3, 24 do segs[i] = seg(51837 + i, nodes[i + 1].entity, nodes[i].entity) end
	return { addedNodes = nodes, addedSegments = segs, frozenNodes = frozen }
end

test("a modular station travels as its construction alone, without its track end stubs (v26, run 5)", function()
	local line, info = build.serialize(run5_station(), {
		to_add = { { fileName = "::/stations/rail/modular_station/modular_station.con", name = "Allensbach Station",
			params = { length = 3, seed = 0, tracks = 1 }, transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2139.415, -3650, 1.209, 1 } } },
	})
	assert(info.segments == 0 and info.nodes == 0 and info.access == 0 and info.gates == 0 and info.constructions == 1, line)
	local stubs, inner = 0, 0
	for _, what in ipairs(info.dropped) do
		if what:find("(end stub of a construction)", 1, true) then stubs = stubs + 1 end
		if what:find("(part of a construction)", 1, true) then inner = inner + 1 end
	end
	assert(stubs == 2 and inner == 22, stubs .. " stubs, " .. inner .. " inner")
	local data = assert(build.deserialize(line))
	assert(next(data.gates) == nil and next(data.access) == nil and #data.constructions == 1)
end)

test("a depot joined to a road travels as one line with entrance and gate (v20)", function()
	-- Run 18 capture: road split at n1, entrance n1 -> n2 (n2 frozen), removed road segment.
	local road = run5_street().addedSegments[1]
	local function seg(entity, a, b, template)
		local s = { entity = entity, type = 0, comp = {} }
		for k, v in pairs(road.comp) do s.comp[k] = v end
		s.comp.node0, s.comp.node1 = a, b
		if template then s.comp.roadTemplate = template end
		s.params, s.streetEdge = road.params, road.streetEdge
		return s
	end
	local proposal = {
		addedNodes = {
			{ entity = 101, comp = { position = { x = -2861.231, y = -3962.21, z = 2.673 } } },
			{ entity = 102, comp = { position = { x = -2866.509, y = -3979.147, z = 2.673 } } },
		},
		frozenNodes = { 1 },
		addedSegments = {
			seg(201, 101, 102, "::/infrastructure/street/constructions/entrance_new.street_template"),
			seg(202, 11, 101), seg(203, 101, 12),
		},
		removedSegments = { { entity = 300, type = 0, comp = { node0 = 11, node1 = 12,
			position0 = { x = -2903.335, y = -3949.088, z = 2.071 }, position1 = { x = -2821.038, y = -3974.736, z = 2.964 } } } },
	}
	local positions = { [11] = { x = -2903.335, y = -3949.088, z = 2.071 }, [12] = { x = -2821.038, y = -3974.736, z = 2.964 } }
	local opts = {
		node_position = function(id) return positions[id] end,
		to_add = { { fileName = "::/depots/road/road_depot/road_depot.con", name = "Depot", params = { seed = 0 },
			transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2872.5, -3998.5, 2.67, 1 } } },
	}
	local line, info = build.serialize(proposal, opts)
	assert(info.access == 1 and info.gates == 1 and info.segments == 3 and info.constructions == 1, line)
	assert(info.nodes == 2 and info.foreign_nodes == 2 and info.removed_segments == 1, line)
	assert(line:find(" n-2;-2866.509,-3979.147,2.673 g;-2 ", 1, true), line)
	local data = assert(build.deserialize(line))
	assert(data.gates[-2] and data.access[-1] and not data.access[-2], "only the entrance is an access segment")
	-- The fallback without entrance forgets the gate (its node is gone).
	build.drop_access(data)
	assert(next(data.gates) == nil and #data.segments == 2 and #data.nodes == 1)
	assert(not build.deserialize("B5 n-1;0,0,0 g;-3"), "a gate on an unknown node is refused")
end)

test("a depot that splits a road is copied in steps: streets with their node configs, then the depot (v22/v23, runs 21 and 22)", function()
	-- The run 18 capture again, with a node configuration on the split node.
	local road = run5_street().addedSegments[1]
	local function seg(entity, a, b, template)
		local s = { entity = entity, type = 0, comp = {} }
		for k, v in pairs(road.comp) do s.comp[k] = v end
		s.comp.node0, s.comp.node1 = a, b
		if template then s.comp.roadTemplate = template end
		s.params, s.streetEdge = road.params, road.streetEdge
		return s
	end
	local split = { x = -2861.231, y = -3962.21, z = 2.673 }
	local proposal = {
		addedNodes = {
			{ entity = 101, comp = { position = split } },
			{ entity = 102, comp = { position = { x = -2866.509, y = -3979.147, z = 2.673 } } },
		},
		frozenNodes = { 1 },
		addedSegments = {
			seg(201, 101, 102, "::/infrastructure/street/constructions/entrance_new.street_template"),
			seg(202, 11, 101), seg(203, 101, 12),
		},
		removedSegments = { { entity = 300, type = 0, comp = { node0 = 11, node1 = 12,
			position0 = { x = -2903.335, y = -3949.088, z = 2.071 }, position1 = { x = -2821.038, y = -3974.736, z = 2.964 } } } },
	}
	local positions = { [11] = { x = -2903.335, y = -3949.088, z = 2.071 }, [12] = { x = -2821.038, y = -3974.736, z = 2.964 } }
	local line = build.serialize(proposal, {
		node_position = function(id) return positions[id] end,
		to_add = { { fileName = "::/depots/road/road_depot/road_depot.con", name = "Depot", params = { seed = 0 },
			transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2872.5, -3998.5, 2.67, 1 } } },
	})
	line = line .. " k;-2861.231,-3962.21,2.673;-;2;-1;-;-;-"
	with_engine_api({}, function(t)
		local m = fresh_main()
		-- Run 22: both ends of the road have node configurations (set when the road was copied).
		t.env.api.type.ComponentType.BASE_EDGE = "BASE_EDGE"
		t.env.api.type.ComponentType.BASE_NODE_CONFIG = "BASE_NODE_CONFIG"
		local get = t.env.api.engine.getComponent
		t.env.api.engine.getComponent = function(id, ct)
			if ct == "BASE_EDGE" and id == 300 then return { node0 = 11, node1 = 12 } end
			if ct == "BASE_NODE_CONFIG" and (id == 11 or id == 12) then return { laneConnections = {} } end
			return get(id, ct)
		end
		-- The road the depot splits exists here: nodes 11 and 12 joined by segment 300.
		m.finder = function()
			return {
				find_node = function(p)
					for id, q in pairs(positions) do
						if math.abs(p.x - q.x) < 0.01 and math.abs(p.y - q.y) < 0.01 then return id end
					end
				end,
				find_edge = function(a, b) if (a == 11 and b == 12) or (a == 12 and b == 11) then return 300 end end,
				find_construction = function() return nil end,
				edge_objects_of = function() return {} end,
				edge_construction = function() return nil end,
			}
		end
		local nodecfg = require("/mp_probe/nodecfg.lua")
		local saved, applied = nodecfg.apply, {}
		nodecfg.apply = function(_, data) applied[#applied + 1] = { sent = #t.sent, data = data }; return 1, 1 end
		logged = {}
		local ok, err = pcall(m.replay_line, t.env, line, "d1", nil, 0)
		nodecfg.apply = saved
		assert(ok, err)
		local all = table.concat(logged, "\n")
		assert(contains(logged, "replay: 1 entrance segment(s) left out, the construction lays its own"), all)
		assert(contains(logged, "replay in steps: streets first (1 nodes, 2 segments, 1 removed segments, 0 removed nodes), then 1 construction(s)"), all)
		assert(#t.sent == 2, all)
		-- First the split road alone.
		local first = t.sent[1].proposal
		local nodes, edges = sent_lists(first)
		assert(#nodes == 1 and #edges == 2 and first.streetProposal.edgesToRemove[1] == 300, all)
		-- Run 22: the old configurations of the road's ends named segment 300; they go in the same build.
		local cleared = first.streetProposal.nodeConfigsToRemove
		assert(#cleared == 2 and cleared[1] == 11 and cleared[2] == 12, all)
		assert(contains(logged, "replay: 2 old node configuration(s) cleared in the build (nodes 11,12)"), all)
		assert(contains(logged, "nodeConfigsToRemove 2/2"), all)
		assert(#(first.constructionsToAdd or {}) == 0, "no construction with the streets")
		assert(contains(logged, "replay streets: sent, SimpleProposal/table: sent with signature 1"), all)
		-- Then the depot alone.
		local second = t.sent[2].proposal
		local nodes2, edges2 = sent_lists(second)
		assert(#second.constructionsToAdd == 1 and #(nodes2 or {}) == 0 and #(edges2 or {}) == 0, all)
		assert(#(second.streetProposal.edgesToRemove or {}) == 0, "the road is not removed twice")
		assert(contains(logged, "replay construction: sent, SimpleProposal/table: sent with signature 1"), all)
		assert(contains(logged, "weld: the copied road_depot.con near -2872.5,-3998.5 is not here"), all)
		-- Node configurations after the streets only; at the entrance the game sets them (run 22).
		assert(#applied == 1 and applied[1].sent == 1 and #applied[1].data.configs == 1, all)
		assert(#(t.sent[2].proposal.streetProposal.nodeConfigsToRemove or {}) == 0, all)
		assert(contains(logged, "replay: node configurations at the entrance are left to the game"), all)
	end)
end)

--- A small world for weld.lua as run 20b left it: depot 500 with gate node 601 and its own
-- entrance 801 ending in node 604, on the spot of the copied road's node 603 (road 701 to 605) but
-- not joined to it.
local function weld_world()
	local w = { comps = {}, segments = {}, sent = {} }
	local gate = { x = 10, y = 20, z = 2 }
	w.gate = gate
	w.comps[500] = { CONSTRUCTION = { fileName = "::/depots/road/road_depot/road_depot.con",
		transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 0, 2, 1 }, frozenNodes = { 601 }, frozenEdges = { 801 } } }
	w.comps[601] = { BASE_NODE = { position = { x = 10, y = 20, z = 2 } } }
	w.comps[603] = { BASE_NODE = { position = { x = 10, y = 38, z = 2 } } }
	w.comps[604] = { BASE_NODE = { position = { x = 10.0004, y = 38.0003, z = 2 } } }
	w.comps[605] = { BASE_NODE = { position = { x = 40, y = 38, z = 2 } } }
	w.comps[701] = { BASE_EDGE = { node0 = 603, node1 = 605 } }
	w.comps[801] = { BASE_EDGE = { node0 = 604, node1 = 601 } }
	w.segments = { [601] = { 801 }, [604] = { 801 }, [603] = { 701 }, [605] = { 701 } }
	--- What the engine's refresh does when it joins the entrance to the road node on its end.
	function w.join()
		w.comps[801].BASE_EDGE.node0 = 603
		w.segments[603], w.segments[604] = { 701, 801 }, nil
	end
	w.env = { api = {
		type = { ComponentType = { CONSTRUCTION = "CONSTRUCTION", BASE_NODE = "BASE_NODE", BASE_EDGE = "BASE_EDGE" },
			Context = { new = function() return {} end },
			SimpleProposal = { new = function() return {} end, ConstructionEntity = { new = function() return {} end } },
			Vec4f = { new = function(x, y, z, ww) return { x, y, z, ww } end },
			Mat4f = { new = function(a, b, c, d) return { a[1], a[2], a[3], a[4], b[1], b[2], b[3], b[4],
				c[1], c[2], c[3], c[4], d[1], d[2], d[3], d[4] } end } },
		engine = {
			getComponent = function(id, ct) return w.comps[id] and w.comps[id][ct] end,
			forEachEntityWithComponent = function(fn, ct)
				local ids = {}
				for id, c in pairs(w.comps) do if c[ct] then ids[#ids + 1] = id end end
				table.sort(ids)
				for _, id in ipairs(ids) do fn(id) end
			end,
			system = {
				streetSystem = {
					getNodeSegments = function(node) return w.segments[node] or {} end,
					getNode2SegmentMap = function() return w.segments end,
				},
				streetConnectorSystem = { getNode2StreetConnectorMap = function() return { [601] = 500 } end },
			},
			util = { proposal = { refreshConstruction = function(id)
				return { toAdd = { { fileName = "::/depots/road/road_depot/road_depot.con", frozenNodes = { 0 } } },
					toRemove = { id }, proposal = { addedNodes = { { entity = 601, comp = { position = gate } } },
					addedSegments = {}, removedSegments = {}, removedNodes = {}, frozenNodes = { 0 } } }
			end } },
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p, context, ignore) return { proposal = p, context = context } end,
			sendCommand = function(cmd, callback)
				w.sent[#w.sent + 1] = cmd
				if w.on_send then w.on_send(cmd) end
				callback({ resultEntities = { 1 }, resultProposalData = { costs = 10,
					errorState = { critical = false, messages = {}, warnings = {} } } }, true)
			end,
		},
	} }
	w.data = { nodes = { { id = -2, position = gate } }, gates = { [-2] = true },
		constructions = { { file = "::/depots/road/road_depot/road_depot.con", name = "Depot", params = {},
			transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 0, 2, 1 } } } }
	return w
end

test("a copied entrance is checked once more a little later", function()
	with_engine_api({}, function(t)
		local main = fresh_main()
		logged = {}
		local state = mock_state()
		state:set({ probe_version = main.PROBE_VERSION, subscribed = main.PROBE_VERSION,
			replay_version = main.PROBE_VERSION, constructions_scanned = main.PROBE_VERSION,
			weld_checks = { { file = "d.con", position = { x = 1, y = 2, z = 3 }, gates = {}, due = 3000 } } })
		main.update(nil, state, 0)
		assert(#state:get().weld_checks == 1, "not due yet")
		t.advance(5000)
		fresh_main().update(nil, state, 0)
		assert(contains(logged, "weld check later: the copied construction is gone"), table.concat(logged, "\n"))
		assert(#state:get().weld_checks == 0)
	end)
end)

test("weld status follows the construction's own entrance to the road (run 20b)", function()
	local weld = require("/mp_probe/weld.lua")
	local w = weld_world()
	local st = weld.status(w.env, 500, { w.gate })
	assert(st.welded == false and #st.gates == 1 and st.gates[1].outside == 0 and st.gates[1].inner == 1, st.text)
	assert(#st.loose == 1 and st.loose[1].id == 603 and st.loose[1].segments == 1, st.text)
	assert(st.text:find("gate 601 at 10.0,20.0 (0 outside, 1 inner, no road reached, entrance ends at node 604 at 10.0,38.0); " ..
		"other node 603 at 10.0,38.0 (1 segments) -> NOT WELDED", 1, true), st.text)
	-- The player's own depot (run 20b): the entrance is the construction's, its end is on the road.
	w.join()
	st = weld.status(w.env, 500, { w.gate })
	assert(st.welded == true and #st.loose == 0, st.text)
	assert(st.text:find("gate 601 at 10.0,20.0 (0 outside, 1 inner, road at node 603 with 1 segments) -> WELDED", 1, true), st.text)
	-- A construction without gate nodes is not touched.
	w.comps[500].CONSTRUCTION.frozenNodes = {}
	w.env.api.engine.system.streetConnectorSystem.getNode2StreetConnectorMap = function() return {} end
	assert(weld.status(w.env, 500, {}).welded == nil)
end)

test("weld repair stops at the first step that welds the gate", function()
	local weld = require("/mp_probe/weld.lua")
	local w = weld_world()
	local logs = {}
	-- The engine's refresh adopts the waiting entrance end.
	w.on_send = w.join
	local checked = weld.repair(w.env, w.data, { log = function(text) logs[#logs + 1] = text end, player = 29125 })
	local all = table.concat(logs, "\n")
	assert(#w.sent == 1 and w.sent[1].proposal.toRemove[1] == 500, all)
	assert(all:find("weld refresh proposal: toAdd #1 {road_depot.con frozen{0}} | toRemove #1 {500} | old2new none | addedNodes", 1, true), all)
	assert(all:find("addedNodes #1 {601@10.0,20.0} | addedSegments #0 {} | removedSegments #0 {} | removedNodes #0 {} | frozenNodes #1 {0}", 1, true), all)
	assert(all:find("weld result road_depot.con: WELDED (after refresh)", 1, true), all)
	assert(checked[1].verdict == "WELDED")
end)

test("weld repair tries the rebuild with old2new when the refresh does not weld", function()
	local weld = require("/mp_probe/weld.lua")
	local w = weld_world()
	local logs = {}
	weld.repair(w.env, w.data, { log = function(text) logs[#logs + 1] = text end, player = 29125 })
	local all = table.concat(logs, "\n")
	assert(#w.sent == 2, all)
	local p = w.sent[2].proposal
	assert(p.constructionsToRemove[1] == 500 and p.old2new[500] == 0, all)
	assert(p.constructionsToAdd[1].fileName == "::/depots/road/road_depot/road_depot.con" and p.constructionsToAdd[1].playerEntity == 29125)
	assert(all:find("weld check after rebuild: construction 500", 1, true), all)
	assert(all:find("weld result road_depot.con: NOT WELDED (after rebuild)", 1, true), all)
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

local function stop_build(kept, stop_param)
	local proposal = run5_street()
	local seg = proposal.addedSegments[1]
	proposal.addedNodes = {}
	proposal.addedSegments = { seg }
	seg.comp.objects = kept and { { 8001, 1 }, { 9001, 0 } } or { { 9001, 1 } }
	proposal.removedSegments = { { entity = -50, type = 0, comp = { node0 = 51389, node1 = 51498,
		position0 = { x = -2888.017, y = -3941.508, z = 1.675 }, position1 = { x = -2818.543, y = -3887.282, z = 1.473 },
		objects = kept and { { 8001, 1 } } or {} } } }
	proposal.edgeObjectsToAdd = { { resultEntity = 9001, left = true, name = "Amselweg", modelInstance = { modelId = 5 } } }
	local positions = { [51389] = { x = -2888.017, y = -3941.508, z = 1.675 }, [51498] = { x = -2818.543, y = -3887.282, z = 1.473 } }
	local seen = {}
	local line, info = build.serialize(proposal, {
		node_position = function(id) return positions[id] end,
		edge_object = function(id, from_proposal)
			seen[id] = from_proposal or false
			if id == 8001 then return { param = 0.7, position = { x = -2840, y = -3904, z = 1.5 }, model = "::/station/street/stop.mdl", name = "Alt" } end
			return { param = stop_param or 0.25, position = { x = -2870, y = -3928, z = 1.6 }, model = "::/station/street/stop.mdl",
				name = from_proposal and from_proposal.name, left = from_proposal and from_proposal.left }
		end,
	})
	return line, info, seen
end

test("a new stop on a street travels with position, model and side (v15)", function()
	local line, info, seen = stop_build(false)
	assert(info.edge_objects == 1 and info.removed_segments == 1, line)
	assert(seen[9001] and seen[9001].name == "Amselweg", "the proposal entry is matched by result entity")
	assert(line:find(" o;1;1;0.25;-2870,-3928,1.6;%3A%3A%2Fstation%2Fstreet%2Fstop.mdl;Amselweg;nl", 1, true), line)
	local data = assert(build.deserialize(line))
	assert(#data.objects == 1 and data.objects[1].new and data.objects[1].left and data.objects[1].segment == -1)
	build.offset(data, 0, 40)
	assert(data.objects[1].position.y == -3888)
	-- Here the edge carries a stop the other player removed with this build.
	local finder = {
		find_node = function(pos) if pos.x < -2850 then return 11 end return 12 end,
		find_edge = function(a, b) if a == 11 and b == 12 then return 600 end end,
		find_construction = function() end,
		edge_objects_of = function(edge)
			assert(edge == 600)
			return { { id = 7001, side = 0, position = { x = -2830, y = -3860, z = 1 } } }
		end,
	}
	assert(build.resolve(data, finder))
	assert(data.objects[1].entity == nil and data.objects_to_remove[1] == 7001)
	local env, sent = mock_build_api()
	local logs = {}
	local ok, message = build.replay(env, data, { player = 29125, log = function(l) logs[#logs + 1] = l end })
	assert(ok, message .. "\n" .. table.concat(logs, "\n"))
	assert(message:find("numbered range0", 1, true), message)
	local sp = sent[#sent].proposal.streetProposal
	assert(sp.edgesToAdd[1].comp.objects[1][1] == -400000000 and sp.edgesToAdd[1].comp.objects[1][2] == 1)
	assert(sp.edgeObjectsToAdd[1].edgeEntity == -1 and sp.edgeObjectsToAdd[1].param == 0.25)
	assert(sp.edgeObjectsToAdd[1].model == "::/station/street/stop.mdl" and sp.edgeObjectsToAdd[1].left == true)
	assert(sp.edgeObjectsToAdd[1].playerEntity == 29125 and sp.edgeObjectsToAdd[1].name == "Amselweg")
	assert(sp.edgeObjectsToRemove[1] == 7001 and sp.edgesToRemove[1] == 600)
end)

test("an existing stop on a rebuilt edge stays, a new one is added beside it (v15)", function()
	local line, info, seen = stop_build(true)
	assert(info.edge_objects == 2, line)
	assert(seen[8001] == false and seen[9001].name == "Amselweg", "only new objects get the proposal entry")
	local data = assert(build.deserialize(line))
	assert(not data.objects[1].new and data.objects[2].new)
	local finder = {
		find_node = function(pos) if pos.x < -2850 then return 11 end return 12 end,
		find_edge = function() return 600 end,
		find_construction = function() end,
		edge_objects_of = function() return { { id = 7001, side = 1, position = { x = -2840.5, y = -3903, z = 1 } } } end,
	}
	assert(build.resolve(data, finder))
	assert(data.objects[1].entity == 7001 and #data.objects_to_remove == 0)
	local env, sent = mock_build_api()
	assert(build.replay(env, data, { player = 29125 }))
	local sp = sent[1].proposal.streetProposal
	local objects = sp.edgesToAdd[1].comp.objects
	assert(objects[1][1] == 7001 and objects[2][1] == -400000000, tostring(objects[2][1]))
	assert(#sp.edgeObjectsToAdd == 1 and #sp.edgeObjectsToRemove == 0)
	-- Without a readable position nothing is removed by guesswork.
	data = assert(build.deserialize(line))
	finder.edge_objects_of = function() return { { id = 7001, side = 1 } } end
	local ok, missing = build.resolve(data, finder)
	assert(not ok and missing:find("cannot read the position", 1, true))
end)

test("demolishing a depot leaves its own segment to the game (run 15)", function()
	local data = assert(build.deserialize("B5 r;0,0,0;0,18,0;0 r;0,0,0;0,18,0;0 x;0,0,0 x;0,18,0 d;depot.con;5,5,0"))
	local finder = {
		find_node = function(pos) return pos.y == 0 and 11 or 12 end,
		find_edge = function() return 600 end,
		find_construction = function() return 700 end,
		edge_construction = function(edge) return edge == 600 and 700 or nil end,
	}
	local ok, missing, notes = build.resolve(data, finder)
	assert(ok, missing)
	assert(#data.removed_segments == 0 and data.removed_nodes[1].entity == nil, "nothing named twice")
	assert(data.demolished[1].entity == 700 and #notes >= 1)
	-- Run 15: the copy's access segment lies elsewhere; the demolition still goes ahead.
	data = assert(build.deserialize("B5 x;0,0,0 r;0,0,0;0,18,0;0 d;depot.con;5,5,0"))
	finder.find_edge = function() return nil end
	assert(build.resolve(data, finder))
	assert(data.removed_nodes[1].entity == nil, "its end node stays as well (run 16)")
	-- The same segment twice without a demolition is removed once.
	data = assert(build.deserialize("B5 r;0,0,0;0,18,0;0 r;0,18,0;0,0,0;0"))
	finder.find_edge = function() return 601 end
	assert(build.resolve(data, finder))
	assert(#data.removed_segments == 1)
end)

test("an extended station replaces its old construction with old2new, so lines keep their stops (v26)", function()
	local file = "::/stations/rail/modular_station/modular_station.con"
	local line = build.serialize(run5_station(), {
		to_add = { { fileName = "::/depots/rail/rail_depot.con", name = "Depot", params = {},
			transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } },
			{ fileName = file, name = "Allensbach Station", params = { length = 4 },
			transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2139.415, -3650, 1.209, 1 } } },
		to_remove = { 900, 901 },
		construction = function(id)
			if id == 900 then return { file = "::/other.con", position = { x = 0, y = 0, z = 0 } } end
			return { file = file, position = { x = -2139.415, y = -3650, z = 1.209 } }
		end,
	})
	local data = assert(build.deserialize(line))
	assert(#data.demolished == 2 and #data.constructions == 2, line)
	local found = { ["::/other.con"] = 699, [file] = 700 }
	assert(build.resolve(data, {
		find_node = function() end, find_edge = function() end, edge_construction = function() end,
		find_construction = function(f) return found[f] end,
	}))
	local env, sent = mock_build_api()
	local logs = {}
	local ok, message = build.replay(env, data, { player = 29125, log = function(l) logs[#logs + 1] = l end })
	assert(ok, message)
	local p = sent[1].proposal
	assert(p.constructionsToRemove[1] == 699 and p.constructionsToRemove[2] == 700)
	-- The station is the second construction added; the other demolished one has no successor.
	assert(p.old2new[700] == 1 and p.old2new[699] == nil, table.concat(logs, "\n"))
	assert(contains(logs, "old2new 1/1"), table.concat(logs, "\n"))
	-- A game that refuses the field still gets the build.
	data = assert(build.deserialize(line))
	assert(build.resolve(data, {
		find_node = function() end, find_edge = function() end, edge_construction = function() end,
		find_construction = function(f) return found[f] end,
	}))
	local tries = 0
	env, sent = mock_build_api()
	local send = env.api.cmd.sendCommand
	env.api.cmd.sendCommand = function(cmd, callback)
		tries = tries + 1
		if next(cmd.proposal.old2new) ~= nil then callback({}, false) return end
		send(cmd, callback)
	end
	logs = {}
	local transport, state = require("/mp_probe/transport.lua"), mock_state()
	transport.begin(state, "station-retry.1")
	ok, message = build.replay(transport.env(env, state), data, {
		player = 29125, log = function(l) logs[#logs + 1] = l end,
		on_rejected = function(reason) transport.fail(state, reason) end,
	})
	assert(ok and message:find("(without old2new)", 1, true), tostring(message) .. "\n" .. table.concat(logs, "\n"))
	assert(contains(logs, "retrying without old2new"), table.concat(logs, "\n"))
	assert(tries == 2 and state:get().network_work.pending == 0)
	transport.dispatched(state); transport.check(state, function(l) logs[#logs + 1] = l end)
	assert(state:get().network_done.result == "OK", "successful station retry must release following actions")
end)

local function native_station_env(opts)
	opts = opts or {}
	local env, sent = mock_build_api()
	local data = assert(build.deserialize("B5"))
	local frame = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -668.189697, -3369.552246, 1.751801, 1 }
	local file = "::/stations/rail/modular_station/modular_station.con"
	data.constructions = { { file = file, name = "Allensbach Station Umstieg", transf = copy_value(frame),
		params = { length = 3, upgrade = true, modules = { [7400030] = { name = "platform_passenger_era_a.module", variant = 0 } } } } }
	data.demolished = { { entity = 700, file = file, position = { x = frame[13], y = frame[14], z = frame[15] } } }
	for i = 1, 24 do data.removed_nodes[i] = { x = i, y = 0, z = 0 } end
	if opts.fixture then
		local source = assert(io.open("tests/fixtures/run29-station-extension.b5", "r"))
		data = assert(build.deserialize(source:read("*a"))); source:close()
		assert(#data.nodes == 1 and #data.segments == 1 and #data.removed_segments == 24 and #data.configs == 25)
		build.drop_access(data)
		local ids, next_id = {}, 800
		assert(build.resolve(data, {
			find_node = function(p)
				local key = string.format("%.3f,%.3f,%.3f", p.x, p.y, p.z)
				if not ids[key] then next_id = next_id + 1; ids[key] = next_id end
				return ids[key]
			end,
			find_edge = function() return 900 end,
			edge_construction = function() return 700 end,
			find_construction = function(f) assert(f == file); return 700 end,
		}))
		assert(#data.nodes == 0 and #data.segments == 0 and #data.removed_segments == 0)
		assert(#data.removed_nodes == 24 and #data.configs == 25)
		for _, node in ipairs(data.removed_nodes) do assert(node.entity == nil, "construction owns its removed nodes") end
	end
	env.api.type.ComponentType = { CONSTRUCTION = 100 }
	local current = { fileName = file, transf = copy_value(frame) }
	local calls = { helper = 0, simple = 0, native = 0 }
	local helper = function(entity, params)
		calls.helper = calls.helper + 1
		assert(entity == 700 and params.upgrade == true and params.modules[7400030])
		if opts.helper_error then error("native replacement unavailable") end
		if opts.empty_helper then return nil end
		local p = struct("Proposal", {
			toAdd = { { fileName = file, transf = copy_value(frame), params = params } },
			toRemove = { 700 }, old2new = { [700] = 0 },
			proposal = { attachedNode = 47297, nodeConfigsToRemove = { 47297 } },
		})
		if opts.invalid then opts.invalid(p) end
		return p
	end
	env.api.engine = { getComponent = function(id, ct)
		assert(id == 700 and ct == 100); return current
	end, util = { proposal = { createProposalReplaceConstruction =
		setmetatable({}, { __call = function(_, ...) return helper(...) end }) } } }
	if opts.no_helper then env.api.engine.util.proposal.createProposalReplaceConstruction = nil end
	local make, send = env.api.cmd.makeWorldBuildProposalCmd, env.api.cmd.sendCommand
	env.api.cmd.makeWorldBuildProposalCmd = function(...)
		local p, context, ignore, initiated = ...
		if type_name_of(p) ~= "Proposal" then calls.simple = calls.simple + 1; return make(p, context, ignore) end
		assert(select("#", ...) == 4 and context == nil and ignore == false and initiated == false,
			"use the GUI's full-proposal signature with playerInitiated=false")
		calls.native = calls.native + 1
		return { proposal = p, context = context, flag = ignore, playerInitiated = initiated }
	end
	local deferred
	env.api.cmd.sendCommand = function(cmd, callback)
		if type_name_of(cmd.proposal) ~= "Proposal" then return send(cmd, callback) end
		sent[#sent + 1] = cmd
		local function execute()
			local result = { resultEntities = opts.reject and {} or { 700 }, resultProposalData = {
				costs = opts.reject and 0 or 30232, errorState = { critical = opts.reject == true } } }
			assert(callback(result, not opts.reject) == true, "native callback owns the transport verdict")
		end
		if opts.deferred then deferred = execute else execute() end
	end
	return env, data, sent, calls, function() assert(deferred); deferred() end, current
end

test("connected station extensions use the engine's full replacement proposal", function()
	local env, data, sent, calls = native_station_env()
	local ok, message = build.replay(env, data)
	assert(ok and data.native_replacement and calls.helper == 1 and calls.native == 1 and calls.simple == 0, message)
	assert(#sent == 1 and sent[1].proposal.proposal.attachedNode == 47297)
	assert(sent[1].proposal.old2new[700] == 0 and sent[1].proposal.proposal.nodeConfigsToRemove[1] == 47297)
	assert(sent[1].proposal.toAdd[1].params.modules[7400030] and sent[1].playerInitiated == false)
end)

test("the recorded run 29 extension selects native replacement with every module and configuration retained", function()
	local env, data, sent, calls = native_station_env({ fixture = true })
	local encoded_params = build.params_to_string(data.constructions[1].params)
	local ok, message = build.replay(env, data)
	assert(ok and data.native_replacement and calls.helper == 1 and calls.native == 1 and calls.simple == 0, message)
	assert(#sent == 1 and sent[1].playerInitiated == false, "one native command without an echoed player action")
	assert(data.constructions[1].params.upgrade == true and data.constructions[1].params.modules[7400030])
	assert(build.params_to_string(sent[1].proposal.toAdd[1].params) == encoded_params, "all captured modules reach the helper proposal")
	assert(#data.configs == 25 and #data.removed_nodes == 24, "preserve the captured data for read-only verification")
end)

test("native replacement failure never falls back to a new SimpleProposal station", function()
	for _, opts in ipairs({ { helper_error = true }, { empty_helper = true }, { reject = true } }) do
		local env, data, sent, calls = native_station_env(opts)
		local ok, message = build.replay(env, data)
		assert(not ok and calls.helper == 1 and calls.simple == 0 and #sent <= 1, message)
		assert(message:find("native construction replacement", 1, true), message)
	end
end)

test("native replacement validates the target, frame, parameters and old2new mapping", function()
	local invalid = {
		function(p) p.toRemove = { 701 } end,
		function(p) p.toAdd = {} end,
		function(p) p.old2new = { [700] = 1 } end,
		function(p) p.old2new = { [700] = 0, [701] = 0 } end,
		function(p) local a = p.toAdd; a[1].fileName = "::/other.con"; p.toAdd = a end,
		function(p) local a = p.toAdd; a[1].transf[13] = 12; p.toAdd = a end,
		function(p) local a = p.toAdd; a[1].params = {}; p.toAdd = a end,
	}
	for _, change in ipairs(invalid) do
		local env, data, sent, calls = native_station_env({ invalid = change })
		local ok, message = build.replay(env, data)
		assert(not ok and calls.simple == 0 and #sent == 0, message)
		assert(message:find("invalid helper proposal", 1, true), message)
	end
end)

test("native replacement rejects invalid incoming data before invoking the helper", function()
	for _, kind in ipairs({ "parameters", "frame", "file" }) do
		local env, data, sent, calls, _, current = native_station_env()
		if kind == "parameters" then data.constructions[1].params = { bad = function() end }
		elseif kind == "frame" then current.transf = nil
		else current.fileName = "::/other.con" end
		local ok, message = build.replay(env, data)
		assert(not ok and calls.helper == 0 and calls.simple == 0 and #sent == 0, message)
	end
end)

test("asynchronous native replacement rejection is reported without resending the build", function()
	local env, data, sent, calls, finish = native_station_env({ deferred = true, reject = true })
	local rejected
	local ok, message = build.replay(env, data, { on_rejected = function(reason) rejected = reason end })
	assert(ok and data.native_replacement and not rejected and #sent == 1, message)
	finish()
	assert(rejected:find("native construction replacement was rejected", 1, true) and calls.simple == 0 and #sent == 1)
end)

test("missing replacement helper and actual construction moves keep the general build path", function()
	for _, kind in ipairs({ "missing", "move", "other work" }) do
		local env, data, sent, calls = native_station_env({ no_helper = kind == "missing" })
		if kind == "move" then data.constructions[1].transf[13] = data.constructions[1].transf[13] + 10 end
		if kind == "other work" then data.removed_nodes[1].entity = 701 end
		local ok, message = build.replay(env, data)
		assert(ok and not data.native_replacement and calls.helper == 0 and calls.simple > 0 and #sent == 1, message)
	end
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

--- run5_street with the node configurations a TF3 build carries (run 20b): the middle node joins
-- both new segments, the first node joins an existing segment 40000 and has a traffic light, the
-- last names a segment nobody knows.
local function street_with_configs()
	local p = run5_street()
	p.nodeConfigsToAdd = {
		{ entity = 51498, comp = {
			laneConnections = {
				{ segment0 = 51563, lane0 = 1, segment1 = 51564, lane1 = 2, withRoad = true, withTram = false },
				{ segment0 = 51564, lane0 = 1, segment1 = 51563, lane1 = 2, withRoad = true, withTram = false },
			},
			crosswalks = { 51563, 51564 }, trafficLightPreference = 2, doubleSlipSwitch = false,
			trafficLightConfig = { states = {}, trafficLightType = -1 }, userModifiedTrafficLightStates = false } },
		{ entity = 51389, comp = {
			laneConnections = { { segment0 = 40000, lane0 = 1, segment1 = 51563, lane1 = 2, withRoad = true, withTram = true } },
			crosswalks = {}, trafficLightPreference = 0, doubleSlipSwitch = false,
			trafficLightConfig = { trafficLightType = 1,
				states = { { lockedLanes = { 0, 1 }, duration = 30, minDuration = 10.5, canSkip = true } } },
			userModifiedTrafficLightStates = true } },
		{ entity = 51458, comp = {
			laneConnections = { { segment0 = 99999, lane0 = 0, segment1 = 51564, lane1 = 0, withRoad = true, withTram = false } },
			crosswalks = {}, trafficLightPreference = 2, doubleSlipSwitch = false,
			trafficLightConfig = { states = {}, trafficLightType = -1 } } },
	}
	p.nodeConfigsToRemove = { 39000 }
	return p
end

local function config_opts()
	return { segment_ends = function(id)
		if id == 40000 then return { x = -2900, y = -3950, z = 1.5 }, { x = -2888.0170898438, y = -3941.5083007812, z = 1.6745910644531 } end
	end }
end

test("node configurations travel by position with the segments they name (v21, run 20b)", function()
	local line, info = build.serialize(street_with_configs(), config_opts())
	assert(info.node_configs == 2 and info.config_removes == 1, info.node_configs .. "/" .. info.config_removes)
	assert(contains(info.dropped, "node config 51458 (segment 99999 has no end positions)"), table.concat(info.dropped, "\n"))
	assert(line:find(" e1;-2888.017,-3941.508,1.675;-2818.543,-3887.282,1.473 e2;-2818.543,-3887.282,1.473;-2749.069,-3833.056,1.003" ..
		" e3;-2900,-3950,1.5;-2888.017,-3941.508,1.675", 1, true), line)
	assert(line:find(" k;-2818.543,-3887.282,1.473;-;2;-1;1:1:2:2:r,2:1:1:2:r;1,2;-", 1, true), line)
	assert(line:find(" k;-2888.017,-3941.508,1.675;t;0;1;3:1:1:2:rt;-;30:10.5:T:0+1", 1, true), line)
	local data = assert(build.deserialize(line))
	assert(#data.configs == 2 and data.config_segments[3].p0.x == -2900, line)
	local c = data.configs[1]
	assert(c.position.x == -2818.543 and c.pref == 2 and c.tltype == -1 and not c.double and not c.states_modified)
	assert(c.conns[1].a == 1 and c.conns[1].l0 == 1 and c.conns[1].b == 2 and c.conns[1].l1 == 2 and c.conns[1].road and not c.conns[1].tram)
	assert(#c.walks == 2 and c.walks[2] == 2)
	local t = data.configs[2]
	assert(t.states_modified and t.conns[1].tram and t.states[1].duration == 30 and t.states[1].min == 10.5 and t.states[1].skip)
	assert(t.states[1].lanes[1] == 0 and t.states[1].lanes[2] == 1)
	-- The one-PC test moves them along with the rest.
	build.offset(data, 0, 100)
	assert(data.configs[1].position.y == -3787.282 and data.config_segments[3].p1.y == -3841.508)
	-- A configuration naming a segment the line does not describe is refused.
	assert(build.deserialize("B5 k;0,0,0;-;2;-1;1:0:2:1:r;-;-") == nil)
	assert(build.deserialize("B5 e1;0,0,0;1,0,0 k;0,0,0;-;2;-1;1:0:1:x;-;-") == nil, "bad lane connection flags")
	-- Without configurations the line stays as before.
	local plain = build.serialize(run5_street())
	assert(not plain:find(" k;", 1, true) and not plain:find(" e1;", 1, true), plain)
end)

test("oversize builds fail as a whole and never silently lose node configurations", function()
	local saved = build.CONFIG_LINE_LIMIT
	build.CONFIG_LINE_LIMIT = 500
	local ok, err = pcall(build.serialize, street_with_configs(), config_opts())
	build.CONFIG_LINE_LIMIT = saved
	assert(not ok and tostring(err):find("complete build including node configs exceeds", 1, true))
end)

--- A street for nodecfg.lua: nodes 1 - 2 - 3 joined by edges 11 and 12; node 9 lies on node 2's spot
-- without any segment (like the second node of run 20b); node 1 has a configuration already.
local function config_world(opts)
	opts = opts or {}
	local w = { comps = {}, segments = {}, sent = {} }
	local function node(id, x, y) w.comps[id] = { BASE_NODE = { position = { x = x, y = y, z = 0 } } } end
	node(1, 0, 0); node(2, 100.0004, 0); node(3, 200, 0); node(9, 100, 0)
	w.comps[11] = { BASE_EDGE = { node0 = 1, node1 = 2 } }
	w.comps[12] = { BASE_EDGE = { node0 = 2, node1 = 3 } }
	w.comps[1].BASE_NODE_CONFIG = { laneConnections = {} }
	w.segments = { [1] = { 11 }, [2] = { 11, 12 }, [3] = { 12 }, [9] = {} }
	w.env = { api = {
		type = {
			ComponentType = { BASE_NODE = "BASE_NODE", BASE_EDGE = "BASE_EDGE", BASE_NODE_CONFIG = "BASE_NODE_CONFIG" },
			Context = { new = function() return {} end },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			TrafficLightState = { new = function() return {} end },
			BaseNodeLaneConnectionAndEntity = { new = function()
				return { entity = 0, comp = { laneConnections = {}, crosswalks = {}, trafficLightPreference = 2,
					doubleSlipSwitch = false, trafficLightConfig = { states = {}, trafficLightType = -1 } } }
			end },
		},
		engine = {
			getComponent = function(id, ct) return w.comps[id] and w.comps[id][ct] end,
			system = { streetSystem = {
				getNodeSegments = function(n) return w.segments[n] or {} end,
				getNode2SegmentMap = function() return w.segments end,
			} },
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p) return { proposal = p } end,
			sendCommand = function(cmd, callback)
				w.sent[#w.sent + 1] = cmd
				local sp = cmd.proposal.streetProposal
				local refuse = (opts.refuse_several and #sp.nodeConfigsToAdd > 1) == true
				if not refuse then
					for _, id in ipairs(sp.nodeConfigsToRemove or {}) do w.comps[id].BASE_NODE_CONFIG = nil end
					for _, e in ipairs(sp.nodeConfigsToAdd) do w.comps[e.entity].BASE_NODE_CONFIG = e.comp end
				end
				callback({ resultEntities = {}, resultProposalData = { costs = 0,
					errorState = { critical = refuse, messages = refuse and { "Bau nicht möglich" } or {}, warnings = {} } } }, not refuse)
			end,
		},
	} }
	w.data = assert(build.deserialize("B5 e1;0,0,0;100,0,0 e2;100,0,0;200,0,0 " ..
		"k;100,0,0;-;2;-1;1:1:2:2:r,2:1:1:2:r;1,2;- k;0,0,0;-;0;1;1:1:1:2:r;-;30:10:T:0+1 k;500,500,0;-;2;-1;-;-;-"))
	return w
end

test("node configurations are placed on the node all their segments end at, replacing an old one", function()
	local nodecfg = require("/mp_probe/nodecfg.lua")
	local w = config_world()
	local logs = {}
	local placed, total = nodecfg.apply(w.env, w.data, { log = function(text) logs[#logs + 1] = text end, player = 29125 })
	local all = table.concat(logs, "\n")
	assert(placed == 2 and total == 3, all)
	assert(#w.sent == 1, all)
	local sp = w.sent[1].proposal.streetProposal
	assert(#sp.nodeConfigsToAdd == 2 and sp.nodeConfigsToRemove[1] == 1 and #sp.nodeConfigsToRemove == 1, all)
	local mid = w.comps[2].BASE_NODE_CONFIG
	assert(mid and #mid.laneConnections == 2 and mid.laneConnections[1].segment0 == 11 and mid.laneConnections[1].segment1 == 12, all)
	assert(mid.laneConnections[1].lane0 == 1 and mid.laneConnections[1].lane1 == 2 and mid.laneConnections[1].withRoad == true)
	assert(mid.crosswalks[1] == 11 and mid.crosswalks[2] == 12 and w.comps[9].BASE_NODE_CONFIG == nil, "not on the loose node")
	local first = w.comps[1].BASE_NODE_CONFIG
	assert(first.trafficLightPreference == 0 and first.trafficLightConfig.trafficLightType == 1, all)
	local st = first.trafficLightConfig.states[1]
	assert(st.duration == 30 and st.minDuration == 10 and st.canSkip == true and st.lockedLanes[2] == 1, all)
	assert(all:find("node configs: node config near 500.0,500.0 not placed (0 segments named, no node there that they all end at)", 1, true), all)
	assert(all:find("node configs all 2: sent (sent with signature 1), success=true, critical false; 2/2 nodes have one now " ..
		"(1 replaced; connections as table 2)", 1, true), all)
	assert(all:find("node configs result: 2/3 placed, 1 not found here", 1, true), all)
end)

test("a depot's left-out entrance takes its node configurations along (two PCs, 8 Oct: game rejected)", function()
	-- The joining player's road depot: the host built the split road, then failed the whole action
	-- with "node configurations could not all be resolved" because two configurations named the
	-- entrance the construction lays itself (one on its far node, one connection on the split node).
	local road = run5_street().addedSegments[1]
	local function seg(entity, a, b, template)
		local s = { entity = entity, type = 0, comp = {} }
		for k, v in pairs(road.comp) do s.comp[k] = v end
		s.comp.node0, s.comp.node1 = a, b
		if template then s.comp.roadTemplate = template end
		s.params, s.streetEdge = road.params, road.streetEdge
		return s
	end
	local line = build.serialize({
		addedNodes = {
			{ entity = 101, comp = { position = { x = -2861.231, y = -3962.21, z = 2.673 } } },
			{ entity = 102, comp = { position = { x = -2866.509, y = -3979.147, z = 2.673 } } },
		},
		frozenNodes = { 1 },
		addedSegments = {
			seg(201, 101, 102, "::/infrastructure/street/constructions/entrance_new.street_template"),
			seg(202, 11, 101), seg(203, 101, 12),
		},
		removedSegments = { { entity = 300, type = 0, comp = { node0 = 11, node1 = 12,
			position0 = { x = -2903.335, y = -3949.088, z = 2.071 }, position1 = { x = -2821.038, y = -3974.736, z = 2.964 } } } },
	}, {
		node_position = function(id)
			return ({ [11] = { x = -2903.335, y = -3949.088, z = 2.071 }, [12] = { x = -2821.038, y = -3974.736, z = 2.964 } })[id]
		end,
		to_add = { { fileName = "::/depots/road/road_depot/road_depot.con", name = "Depot", params = { seed = 0 },
			transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2872.5, -3998.5, 2.67, 1 } } },
	})
	line = line .. " e1;-2861.231,-3962.21,2.673;-2866.509,-3979.147,2.673" ..
		" e2;-2903.335,-3949.088,2.071;-2861.231,-3962.21,2.673 e3;-2861.231,-3962.21,2.673;-2821.038,-3974.736,2.964" ..
		" k;-2861.231,-3962.21,2.673;-;2;-1;2:1:3:1:r,2:1:1:1:r;1,2,3;- k;-2866.509,-3979.147,2.673;-;2;-1;-;1;-"
	local data = assert(build.deserialize(line))
	build.drop_access(data)
	assert(data.entrance_refs[1] and not data.entrance_refs[2] and not data.entrance_refs[3], "only the entrance is left to the depot")
	assert(#data.entrance_nodes == 1 and math.abs(data.entrance_nodes[1].y - -3979.147) < 0.01, "its far node too")

	-- On a world with the split road: the split node's configuration keeps its road connections and
	-- counts as placed; the entrance node's configuration is left to the depot.
	local nodecfg, world = require("/mp_probe/nodecfg.lua"), require("/mp_probe/world.lua")
	local w = config_world()
	w.data = assert(build.deserialize("B5 e1;0,0,0;100,0,0 e2;100,0,0;200,0,0 e3;100,0,0;100,20,0 " ..
		"k;100,0,0;-;2;-1;1:1:2:2:r,1:1:3:1:r;1,2,3;- k;100,20,0;-;2;-1;-;3;-"))
	w.data.entrance_refs = { [3] = true }
	w.data.entrance_nodes = { { x = 100, y = 20, z = 0 } }
	local resolved, notes, skipped = nodecfg.resolve(w.env, w.data, world.node_index(w.env))
	local all = table.concat(notes, "\n")
	assert(#resolved == 1 and skipped == 1 and resolved[1].partial == nil, all)
	assert(resolved[1].node == 2 and #resolved[1].config.conns == 1 and #resolved[1].config.walks == 2, all)
	assert(all:find("node config near 100.0,20.0 left to the construction's own entrance", 1, true), all)
	local logs = {}
	local placed, total = nodecfg.apply(w.env, w.data, { log = function(text) logs[#logs + 1] = text end })
	all = table.concat(logs, "\n")
	assert(placed == 1 and total == 2, all)
	assert(all:find("node configs result: 1/2 placed, 0 not found here, 1 left to the entrance", 1, true), all)
end)

test("node configurations the game refuses together are sent one node at a time", function()
	local nodecfg = require("/mp_probe/nodecfg.lua")
	local w = config_world({ refuse_several = true })
	local logs = {}
	local placed = nodecfg.apply(w.env, w.data, { log = function(text) logs[#logs + 1] = text end })
	local all = table.concat(logs, "\n")
	-- Node 1 has its old configuration, so only node 2 needs a second try.
	assert(placed == 2 and #w.sent == 2, all)
	assert(all:find("success=false, critical true, message: Bau nicht möglich", 1, true), all)
	assert(all:find("node configs node 1 (2): sent", 1, true), all)
	assert(#w.comps[2].BASE_NODE_CONFIG.laneConnections == 2, all)
end)

test("a node at a construction's entrance keeps the configuration the game gave it (v23, run 22)", function()
	local nodecfg = require("/mp_probe/nodecfg.lua")
	local w = config_world()
	-- Segment 12 is a depot's entrance: node 2 is where it meets the road.
	w.env.api.engine.system.streetConnectorSystem = {
		getConstructionEntityForEdge = function(e) return e == 12 and 77 or -1 end,
		getConstructionEntityForNode = function() return -1 end,
	}
	local logs = {}
	local placed, total = nodecfg.apply(w.env, w.data, { log = function(text) logs[#logs + 1] = text end })
	local all = table.concat(logs, "\n")
	assert(placed == 1 and total == 3 and #w.sent == 1, all)
	assert(#w.sent[1].proposal.streetProposal.nodeConfigsToAdd == 1, all)
	assert(w.comps[2].BASE_NODE_CONFIG == nil, "node 2 is left alone")
	assert(all:find("node configs left to the game at a construction: node 2 (construction 77)", 1, true), all)
	assert(all:find("node configs result: 1/3 placed, 1 left to a construction, 1 not found here", 1, true), all)
end)

test("a segment that cannot be found keeps its node configuration back", function()
	local nodecfg = require("/mp_probe/nodecfg.lua")
	local w = config_world()
	w.segments[3] = {}
	w.segments[2] = { 11 }
	local logs = {}
	local placed = nodecfg.apply(w.env, w.data, { log = function(text) logs[#logs + 1] = text end })
	local all = table.concat(logs, "\n")
	assert(placed == 1 and w.comps[2].BASE_NODE_CONFIG == nil, all)
	assert(all:find("node config near 100.0,0.0 not placed (2 segments named, not found: e2)", 1, true), all)
end)

test("a junction whose entrance ends in a node of its own still gets the connections along the road (run 20b)", function()
	local nodecfg = require("/mp_probe/nodecfg.lua")
	local w = config_world()
	-- The construction's entrance 13 starts at node 9 on the junction's spot, not at node 2.
	w.comps[4] = { BASE_NODE = { position = { x = 100, y = -50, z = 0 } } }
	w.comps[13] = { BASE_EDGE = { node0 = 9, node1 = 4 } }
	w.segments[9], w.segments[4] = { 13 }, { 13 }
	w.data = assert(build.deserialize("B5 e1;0,0,0;100,0,0 e2;100,0,0;200,0,0 e3;100,0,0;100,-50,0 " ..
		"k;100,0,0;-;2;-1;1:1:2:2:r,2:1:1:2:r,1:1:3:0:r;1,2,3;-"))
	local logs = {}
	local placed = nodecfg.apply(w.env, w.data, { log = function(text) logs[#logs + 1] = text end })
	local all = table.concat(logs, "\n")
	assert(placed == 1 and #w.comps[2].BASE_NODE_CONFIG.laneConnections == 2, all)
	assert(#w.comps[2].BASE_NODE_CONFIG.crosswalks == 2 and w.comps[9].BASE_NODE_CONFIG == nil, all)
	assert(all:find("node config near 100.0,0.0 placed in part on node 2 (2 of 3 connections; 2 of 3 segments, " ..
		"no node there that they all end at)", 1, true), all)
end)

test("lane connections the proposal refuses as tables are copied from an existing node", function()
	local nodecfg = require("/mp_probe/nodecfg.lua")
	local w = config_world()
	-- Like an engine list of structs: only LaneConnection objects are kept, and reading hands out copies.
	local LC = {}
	local function lane_connection(v)
		return setmetatable({ segment0 = v.segment0, lane0 = v.lane0, segment1 = v.segment1, lane1 = v.lane1,
			withRoad = v.withRoad, withTram = v.withTram }, LC)
	end
	local function engine_comp()
		local kept = {}
		return setmetatable({ crosswalks = {}, trafficLightPreference = 2, doubleSlipSwitch = false,
			trafficLightConfig = { states = {}, trafficLightType = -1 } }, {
			__index = function(_, k)
				if k == "laneConnections" then
					local out = {}
					for i, lc in ipairs(kept) do out[i] = lane_connection(lc) end
					return out
				end
			end,
			__newindex = function(t, k, v)
				if k ~= "laneConnections" then rawset(t, k, v); return end
				kept = {}
				for _, lc in ipairs(v) do
					if getmetatable(lc) == LC then kept[#kept + 1] = lane_connection(lc) end
				end
			end,
		})
	end
	w.env.api.type.BaseNodeLaneConnectionAndEntity.new = function() return { entity = 0, comp = engine_comp() } end
	local old = engine_comp()
	old.laneConnections = { lane_connection({ segment0 = 11, lane0 = 0, segment1 = 11, lane1 = 1, withRoad = true }) }
	w.comps[1].BASE_NODE_CONFIG = old
	local logs = {}
	local placed = nodecfg.apply(w.env, w.data, { log = function(text) logs[#logs + 1] = text end })
	local all = table.concat(logs, "\n")
	assert(placed == 2, all)
	local mid = w.comps[2].BASE_NODE_CONFIG.laneConnections
	assert(#mid == 2 and mid[1].segment0 == 11 and mid[2].segment0 == 12 and mid[2].lane1 == 2, all)
	assert(all:find("connections as copy 2", 1, true), all)
end)

test("a player build with node configurations captures them and the copy gets them after the build", function()
	with_engine_api({}, function(t)
		local main = fresh_main()
		logged = {}
		local state = mock_state()
		local param = player_build_param()
		param[1].proposal = street_with_configs()
		main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", param)
		assert(contains(logged, "node_configs=1 config_removes=1"), table.concat(logged, "\n"))
		local line = state:get().last_build
		assert(line:find(" k;-2818.543,-3887.282,1.473;", 1, true), line)
		-- The copy: built first, then the configurations go out on their own.
		local applied = nil
		t.env.api.type.BaseNodeLaneConnectionAndEntity = { new = function() return { entity = 0, comp = {} } end }
		logged = {}
		local nodecfg = require("/mp_probe/nodecfg.lua")
		local saved = nodecfg.apply
		nodecfg.apply = function(env, data) applied = data; return 0, #data.configs end
		local ok, err = pcall(function() fresh_main().replay_line(t.env, line, "k1", nil, 0) end)
		nodecfg.apply = saved
		assert(ok, err)
		assert(contains(logged, "1 node configs, moved by 0.0,0.0"), table.concat(logged, "\n"))
		assert(applied and #applied.configs == 1 and #t.sent == 1, table.concat(logged, "\n"))
	end)
end)

test("a build that only changes node configurations travels and is applied without building", function()
	with_engine_api({}, function(t)
		local main = fresh_main()
		logged = {}
		local state = mock_state()
		local param = player_build_param()
		local p = street_with_configs()
		-- Only the middle node's configuration changed (a traffic light set by the player).
		p.addedNodes, p.addedSegments, p.nodeConfigsToRemove = {}, {}, { 51498 }
		p.nodeConfigsToAdd = { p.nodeConfigsToAdd[1] }
		param[1].proposal = p
		local positions = { [51498] = { x = 5, y = 6, z = 0 }, [51389] = { x = 0, y = 0, z = 0 }, [51458] = { x = 10, y = 12, z = 0 } }
		local edges = { [51563] = { 51389, 51498 }, [51564] = { 51498, 51458 } }
		t.env.api.type.ComponentType.BASE_NODE = "BASE_NODE"
		t.env.api.type.ComponentType.BASE_EDGE = "BASE_EDGE"
		local get = t.env.api.engine.getComponent
		t.env.api.engine.getComponent = function(id, ct)
			if ct == "BASE_NODE" and positions[id] then return { position = positions[id] } end
			if ct == "BASE_EDGE" and edges[id] then return { node0 = edges[id][1], node1 = edges[id][2] } end
			return get(id, ct)
		end
		main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", param)
		assert(contains(logged, "nodes=0 segments=0"), table.concat(logged, "\n"))
		assert(contains(logged, "node_configs=1 config_removes=1"), table.concat(logged, "\n"))
		local line = state:get().last_build
		assert(line and line:find("k;5,6,0;-;2;-1;1:1:2:2:r,2:1:1:2:r;1,2;-", 1, true), tostring(line))
		local applied = nil
		local nodecfg = require("/mp_probe/nodecfg.lua")
		local saved = nodecfg.apply
		nodecfg.apply = function(env, data) applied = data; return 1, 1 end
		logged = {}
		local ok, err = pcall(function() fresh_main().replay_line(t.env, line, "k2", nil, 0) end)
		nodecfg.apply = saved
		assert(ok, err)
		assert(contains(logged, "replay #k2: only node configurations (1)"), table.concat(logged, "\n"))
		assert(applied and #t.sent == 0, "nothing is built")
	end)
end)

test("replay without the engine api says so", function()
	local ok, message = build.replay({}, { nodes = {}, segments = {} })
	assert(not ok and message == "api missing", message)
end)

test("network build waits for its callback and verification; duplicate events do not build twice", function()
	with_engine_api({}, function(t)
		local main, state = fresh_main(), mock_state()
		local deferred, original = {}, t.env.api.cmd.sendCommand
		t.env.api.cmd.sendCommand = function(cmd, callback)
			deferred[#deferred + 1] = function() original(cmd, callback) end
		end
		logged = {}
		local param={line=build.serialize(run5_street()),number="test.1",source="net",offset=0}
		main.handleEvent(nil,state,"mp_probe",main.REPLAY_EVENT,main.REPLAY_EVENT,param)
		assert(state:get().network_work.pending == 1 and #deferred == 1)
		assert(not contains(logged,"net result test.1 OK"))
		main.handleEvent(nil,state,"mp_probe",main.REPLAY_EVENT,main.REPLAY_EVENT,param)
		assert(#deferred == 1, "duplicate event must not build twice")
		deferred[1]()
		assert(state:get().network_work.pending == 0)
		for i=1,2 do main.handleEvent(nil,state,"mp_probe",main.REPLAY_EVENT,main.REPLAY_EVENT,{network_continue=true}) end
		assert(state:get().network_done.result == "OK")
		assert(contains(logged,"net result test.1 OK"))
	end)
end)

test("network failure prevents construction follow-ups", function()
	with_engine_api({}, function(t)
		local main, state = fresh_main(), mock_state()
		local callback
		t.env.api.cmd.sendCommand=function(_,cb)callback=cb end
		logged = {}
		main.handleEvent(nil,state,"mp_probe",main.REPLAY_EVENT,main.REPLAY_EVENT,
			{line=build.serialize(run5_street()),number="test.2",source="net",offset=0})
		assert(callback and state:get().network_followup)
		callback({},false)
		main.handleEvent(nil,state,"mp_probe",main.REPLAY_EVENT,main.REPLAY_EVENT,{network_continue=true})
		assert(state:get().network_done.result == "FAIL" and not state:get().network_followup)
		assert(contains(logged,"net result test.2 FAIL"))
	end)
end)

test("asynchronous success=true with nothing built must not acknowledge an applied action", function()
	with_engine_api({build={builds={}}},function(t)
		local main,state=fresh_main(),mock_state()
		local deferred,original=nil,t.env.api.cmd.sendCommand
		t.env.api.cmd.sendCommand=function(cmd,cb)deferred=function()original(cmd,cb)end end
		main.handleEvent(nil,state,"mp_probe",main.REPLAY_EVENT,main.REPLAY_EVENT,
			{line=build.serialize(run5_street()),number="test.3",source="net",offset=0})
		assert(deferred); deferred()
		assert(state:get().network_work.error:find("produced nothing",1,true))
		main.handleEvent(nil,state,"mp_probe",main.REPLAY_EVENT,main.REPLAY_EVENT,{network_continue=true})
		assert(state:get().network_done.result=="FAIL")
	end)
end)

test("successive station upgrades retain a reused construction ID for capture", function()
	local main, id = fresh_main(), 43692
	local station_file = "::/stations/rail/modular_station/modular_station.con"
	local current = { fileName = station_file,
		transf = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 100,200,3,1 } }
	local env = { api = { type = { ComponentType = { CONSTRUCTION = 1, PLAYER_OWNED = 2 } },
		engine = { getComponent = setmetatable({}, { __call = function(_, entity, ct)
			assert(entity == id)
			if ct == 1 then return current end
			if ct == 2 then return { player = 29125 } end
		end }) } } }
	local s = {}
	main.remember_constructions(env, s, { { toRemove = {} }, {}, { id } })
	for upgrade = 1, 3 do
		local line, info = build.serialize({}, { to_remove = { id },
			construction = function(entity) return s.constructions[tostring(entity)] end })
		assert(info.demolished == 1 and #info.dropped == 0, "successive upgrade lost its old construction")
		local parsed = assert(build.deserialize(line))
		assert(parsed.demolished[1].position.x == 99 + upgrade)
		current.transf[13] = 100 + upgrade
		main.remember_constructions(env, s, { { toRemove = { id } }, {}, { id } })
		assert(s.constructions[tostring(id)].position.x == 100 + upgrade)
	end
	main.remember_constructions(env, s, { { toRemove = { id } }, {}, {} })
	assert(s.constructions[tostring(id)] == nil, "a final demolition must clear the cache")
end)

test("native station replacements retain engine configurations and wait for connection verification", function()
	with_engine_api({}, function(t)
		local main, state = fresh_main(), mock_state()
		local transport = require("/mp_probe/transport.lua")
		transport.begin(state, "replacement.1")
		transport.dispatched(state)
		local s = state:get()
		s.network_followup = { phase = "finish", gates = true, data = {
			native_replacement = true, configs = {},
			gate_positions = { { x = 105, y = 200, z = 3 } },
			constructions = { { file = "station.con", transf = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 100,200,3,1 } } },
		} }
		state:set(s)
		main.weld_copy = function() error("native replacement must not run a second build") end
		main.apply_node_configs = function() error("native replacement must keep engine configurations") end
		main.network_continue(t.env, state)
		assert(#t.sent == 0 and state:get().network_followup.phase == "verify")
		local check = state:get().weld_checks[1]
		assert(check.file == "station.con" and check.position.x == 100 and #check.gates == 1)
		assert(check.due == 1000 + main.WELD_RECHECK_MS)
		main.network_continue(t.env, state)
		transport.check(state, function() error("connection check must hold the execution receipt") end)
		assert(state:get().network_work and not state:get().network_done)
	end)
end)

test("a command callback during update() is not overwritten by update's older copy (two PCs, 8 Oct: depot copy stalled)", function()
	with_engine_api({}, function(t)
		local main = fresh_main()
		-- The engine hands each reader its own copy of the script state.
		local value
		local state = { get = function() return value and copy_value(value) end, set = function(_, v) value = copy_value(v) end,
			subscribeToEvent = function() end }
		state:set({ probe_version = main.PROBE_VERSION, subscribed = main.PROBE_VERSION,
			replay_version = main.PROBE_VERSION, constructions_scanned = main.PROBE_VERSION,
			actions_version = main.PROBE_VERSION, actions = {}, updates = 1,
			network_work = { token = "41252-4193703.2", pending = 1, dispatched = true },
			network_followup = { phase = "finish", data = { configs = {} }, player = 83475, gates = true } })
		-- The depot's callback arrives from the event state while update() runs.
		main.sync_tick = function()
			local live = state:get()
			live.network_work.pending = 0
			state:set(live)
		end
		logged = {}
		main.update(nil, state, 0)
		local s = state:get()
		assert(s.network_work.pending == 0, "the callback's countdown must survive update()")
		assert(s.network_followup.requested == true and #t.events == 1, "the next stage is requested once")
		main.update(nil, state, 0)
		assert(#t.events == 1, "and not again while it waits")
		-- The continuation clears the request in the event state; update() must not bring it back.
		main.sync_tick = function()
			local live = state:get()
			live.network_followup = { phase = "verify", data = { configs = {} } }
			state:set(live)
		end
		main.update(nil, state, 0)
		s = state:get()
		assert(s.network_followup.phase == "verify" and s.network_followup.requested == true and #t.events == 2,
			"the next stage is requested after the continuation moved on")
	end)
end)

test("a road depot from the other PC is built, joined and confirmed while paused (two PCs, 8 Oct: stuck after the depot)", function()
	-- Runs 32 and 33: the host built the joining player's road and depot, then never joined the depot's
	-- entrance and never confirmed the action; both PCs' queues stood still ("Weltabweichung").
	local source = assert(io.open("tests/fixtures/run33-road-depot.b5", "r"))
	local line = source:read("*a"); source:close()
	with_engine_api({}, function(t)
		local main = fresh_main()
		local world, weld = require("/mp_probe/world.lua"), require("/mp_probe/weld.lua")
		local value
		local state = { get = function() return value and copy_value(value) end, set = function(_, v) value = copy_value(v) end,
			subscribeToEvent = function() end }
		state:set({ probe_version = main.PROBE_VERSION, subscribed = main.PROBE_VERSION,
			replay_version = main.PROBE_VERSION, constructions_scanned = main.PROBE_VERSION,
			actions_version = main.PROBE_VERSION, actions = {}, updates = 1 })
		-- The road the depot joins exists here (both ends and the node in its middle).
		local ids = {}
		main.finder = function()
			return {
				find_node = function(p)
					local key = string.format("%.0f,%.0f", p.x, p.y)
					ids[key] = ids[key] or (900 + #t.sent * 10 + math.floor(p.x) % 7)
					return ids[key]
				end,
				find_edge = function(a, b) return 5000 + a + b end,
				find_construction = function() return nil end,
				edge_objects_of = function() return {} end,
				edge_construction = function() return nil end,
			}
		end
		local steps, welded = {}, 0
		main.apply_node_configs = function(_, data) steps[#steps + 1] = "configs " .. #data.configs end
		main.verify_node_configs = function() steps[#steps + 1] = "verify" end
		main.weld_copy = function(_, data)
			welded = welded + 1
			assert(#t.sent == 2, "the entrance is joined after the depot is built")
			local live = state:get()
			live.weld_checks = { { file = data.constructions[1].file, position = { x = 7285.8, y = 26.4, z = 8.6 },
				gates = data.gate_positions, due = 1000 + main.WELD_RECHECK_MS } }
			state:set(live)
		end
		local saved_find, saved_status = world.find_construction, weld.status
		world.find_construction = function() return 114736 end
		weld.status = function() return { welded = true, text = "construction 114736: gate -> WELDED" } end
		logged = {}
		local ok, err = pcall(function()
			main.handleEvent(nil, state, "mp_probe", main.REPLAY_EVENT, main.REPLAY_EVENT,
				{ line = line, number = "40780-5464828.1", source = "net", offset = 0 })
			local all = table.concat(logged, "\n")
			assert(#t.sent == 2 and #t.sent[1].proposal.constructionsToAdd == 0 and #t.sent[2].proposal.constructionsToAdd == 1, all)
			assert(welded == 1, "the depot's entrance is joined in the same event: " .. all)
			for _, phase in ipairs({ "street_configs", "street_verify", "construction", "finish", "verify" }) do
				assert(contains(logged, "net step 40780-5464828.1: " .. phase), phase .. " missing: " .. all)
			end
			assert(table.concat(steps, ",") == "configs 5,verify,configs 0,verify", table.concat(steps, ","))
			local s = state:get()
			assert(s.network_work and not s.network_followup and #s.weld_checks == 1 and #t.events == 0, all)
			assert(not contains(logged, "net result"), "the receipt waits for the entrance check")
			-- The game stays paused: game time does not move, update() still runs.
			for _ = 1, main.WELD_RECHECK_UPDATES do main.update(nil, state, 0) end
			all = table.concat(logged, "\n")
			assert(contains(logged, "weld check later: construction 114736: gate -> WELDED"), all)
			assert(contains(logged, "net result 40780-5464828.1 OK"), all)
			assert(#t.events == 0 and #t.sent == 2, "nothing is built twice")
			-- Run 34: the receipt was given in update(), but update() put the open action back, so
			-- it was confirmed on every update and the other PC's next action (a line) waited for good.
			for _ = 1, 5 do main.update(nil, state, 0) end
			local results = 0
			for _, text in ipairs(logged) do if text:find("net result 40780-5464828.1", 1, true) then results = results + 1 end end
			s = state:get()
			assert(results == 1 and not s.network_work and s.network_done.result == "OK", "confirmed " .. results .. " times")
			logged = {}
			main.handleEvent(nil, state, "mp_probe", main.REPLAY_EVENT, main.REPLAY_EVENT,
				{ line = build.serialize(run5_street()), number = "40780-5464828.2", source = "net", offset = 0 })
			assert(contains(logged, "net result 40780-5464828.2 OK"), "the next action is built: " .. table.concat(logged, "\n"))
		end)
		world.find_construction, weld.status = saved_find, saved_status
		assert(ok, err)
	end)
end)

test("a continuation that crosses an outstanding command waits and can be asked for again", function()
	local main, state = fresh_main(), mock_state()
	state:set({ network_work = { token = "c.1", pending = 1, dispatched = true },
		network_followup = { phase = "finish", requested = true, data = { configs = {} }, gates = true } })
	main.weld_copy = function() error("no step while a command is outstanding") end
	logged = {}
	main.network_continue({}, state)
	local s = state:get()
	assert(s.network_followup.phase == "finish" and not s.network_followup.requested and #logged == 0)
end)

test("a confirmed world difference sends this game's records; the other game logs both sides' extra ones", function()
	local main, state = fresh_main(), mock_state()
	local fingerprint = require("/mp_probe/fingerprint.lua")
	local saved = fingerprint.list
	local mine, theirs = {}, {}
	for i = 1, 200 do
		local r = { h = string.format("%016x", i), d = "street " .. i .. " at " .. i .. ".000,0.000,0.000" }
		mine[i], theirs[i] = r, r
	end
	mine[201] = { h = "ffffffffffffff01", d = "entrance_new.street_template/town_new.street 1.000,2.000,3.000 > 4.000,5.000,6.000" }
	theirs[201] = { h = "ffffffffffffff02", d = "entrance_new.street_template/town_new.street 1.000,2.000,3.000 > 4.000,5.000,6.500" }
	local ok, err = pcall(function()
		fingerprint.list = function(_, kind) assert(kind == "edge"); return theirs end
		logged = {}
		local ss = {}
		main.world_send({}, ss, { hedge = "h1_aaaa" }, { "hedge" })
		local lines = {}
		for _, text in ipairs(logged) do
			local line = text:match("net send (W1 .*)$")
			if line then lines[#lines + 1] = line; assert(#line <= 6000, #line) end
		end
		assert(#lines >= 2, "large lists go in parts that each fit one bridge line: " .. #lines)
		assert(contains(logged, "world list hedge: 201 records sent to the other game in " .. #lines .. " part(s)"))
		logged = {}
		main.world_send({}, ss, { hedge = "h1_aaaa" }, { "hedge" })
		assert(#logged == 0, "the same list is not sent twice")
		-- The receiving game (its own records are `mine`).
		fingerprint.list = function() return mine end
		logged = {}
		for i, line in ipairs(lines) do
			local applied = main.replay_line({}, line, "w." .. i, state, 0)
			assert(applied == true)
		end
		assert(contains(logged, "world diff hedge only in the other game: entrance_new.street_template/town_new.street " ..
			"1.000,2.000,3.000 > 4.000,5.000,6.500"), table.concat(logged, "\n"))
		assert(contains(logged, "world diff hedge only in this game: entrance_new.street_template/town_new.street " ..
			"1.000,2.000,3.000 > 4.000,5.000,6.000"), table.concat(logged, "\n"))
		assert(contains(logged, "world diff hedge: 1 only here, 1 only in the other game (there 201 records, here 201)"),
			table.concat(logged, "\n"))
		assert(not (state:get().world_rx or {}).hedge, "nothing is kept once the list is complete")
	end)
	fingerprint.list = saved
	assert(ok, err)
end)

test("the world lists go out when a checkpoint confirms a difference, not before", function()
	local main = fresh_main()
	local sent = {}
	main.world_send = function(_, _, own, fields) sent[#sent + 1] = table.concat(fields, ",") .. "@" .. own.hedge end
	local ss = { own = {}, peer = {} }
	local base = { con = 1, lines = 1, st = 23, veh = 0, money = 100, loan = 0, date = "1900-01-01",
		hcon = "h1_00000000000000c0", hline = "h1_00000000000000d0", hveh = "h1_00000000000000e0" }
	for k = 3, 5 do
		local own, peer = {}, {}
		for f, v in pairs(base) do own[f], peer[f] = v, v end
		own.hedge, peer.hedge, own.ck, peer.ck = string.format("h1_%016x", k), string.format("h1_%016x", 100 + k), k, k
		ss.own[#ss.own + 1] = { k = k, v = own }
		ss.peer[#ss.peer + 1] = { k = k, v = peer }
		logged = {}
		main.sync_compare({}, ss, "host", k * 60000)
		if k == 3 then assert(#sent == 0, "a first difference is only being checked") end
	end
	assert(#sent >= 1 and sent[1] == "hedge@" .. string.format("h1_%016x", 4), table.concat(sent, " "))
end)

test("a received action still waiting says what for, once per bridge tick", function()
	local main = fresh_main()
	logged = {}
	main.log_network_wait({ updates = 49, network_work = { token = "a.1", pending = 0, dispatched = true } })
	assert(#logged == 0)
	main.log_network_wait({ updates = 50, network_work = { token = "a.1", pending = 1, dispatched = true },
		network_followup = { phase = "finish", requested = true }, weld_checks = { {} } })
	assert(#logged == 1 and contains(logged, "net waiting a.1: step finish (requested), 1 command(s) outstanding, " ..
		"1 entrance check(s), 0 action step(s)"), tostring(logged[1]))
end)

test("an unreadable delayed station connection check rejects the execution receipt", function()
	with_engine_api({}, function(t)
		local main, state = fresh_main(), mock_state()
		local transport = require("/mp_probe/transport.lua")
		state:set({ probe_version = main.PROBE_VERSION, subscribed = main.PROBE_VERSION,
			replay_version = main.PROBE_VERSION, constructions_scanned = main.PROBE_VERSION,
			actions_version = main.PROBE_VERSION, actions = {}, updates = 1 })
		transport.begin(state, "replacement-read-failure.1")
		transport.dispatched(state)
		main.check_replacement_later(t.env, { constructions = {
			{ file = "station.con", transf = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 100,200,3,1 } },
		} }, state)
		t.advance(main.WELD_RECHECK_MS)
		main.recheck_welds = function() error("mock engine read failure", 0) end
		logged = {}
		main.update(nil, state, 0)
		assert(state:get().network_done.result == "FAIL", "an unreadable connection must never acknowledge the replacement")
		assert(contains(logged, "net result replacement-read-failure.1 FAIL construction entrance check unreadable: mock engine read failure"))
		assert(not contains(logged, "net result replacement-read-failure.1 OK"))
	end)
end)

test("world comparison publishes matching, persistent mismatch and unknown health for the launcher", function()
	local main = fresh_main()
	local sync = require("/mp_probe/sync.lua")
	local own = { hcon = "h1_0000000000000001", hedge = "h1_0000000000000002",
		hline = "h1_0000000000000003", hveh = "h1_0000000000000004",
		hpos = "h2_0000000000000005", hcargo = "h2_0000000000000006", htown = "h2_0000000000000007", gt = 60000, wgt = 60000 }
	local peer = copy_value(own)
	local mem = { own_k = 1, own = sync.keep(nil, 1, own), peer = sync.keep(nil, 1, peer) }
	logged = {}
	main.sync_compare({}, mem, "host", 60000)
	assert(contains(logged, "net state health ck=1 status=same fields=none"))
	peer.hline = "h1_0000000000000005"
	for k = 2, 3 do
		mem.own_k = k; mem.own = sync.keep(mem.own, k, own); mem.peer = sync.keep(mem.peer, k, peer)
		main.sync_compare({}, mem, "host", k * 60000)
	end
	assert(contains(logged, "net state health ck=2 status=checking fields=hline"))
	assert(contains(logged, "net state health ck=3 status=diff fields=hline"))
	mem.own_k = 4; mem.own = sync.keep(mem.own, 4, {}); mem.peer = sync.keep(mem.peer, 4, peer)
	main.sync_compare({}, mem, "host", 240000)
	assert(contains(logged, "net state health ck=4 status=unknown fields=none"))
end)

test("deferred world hashes publish the original tick and cache its immutable diagnostic records", function()
	local main = fresh_main()
	local sync = require("/mp_probe/sync.lua")
	local saved_values, saved_step, saved_time = sync.values, sync.world_step, main.game_time
	local ok, err = pcall(function()
		local now, steps = 60000, 0
		main.game_time = function() return now end
		sync.values = function(_, gt, deferred)
			assert(deferred and gt == 60000); return { gt = gt }, {}, { immutable = true }
		end
		sync.world_step = function(_, job)
			assert(job.immutable); steps = steps + 1
			if steps == 1 then return nil end
			return { hcon = "h1_0000000000000001", wgt = 60000 }, {}, { records = 1 },
				{ hcon = { { h = "aa", d = "original snapshot" } } }
		end
		local env = { os = { getenv = function(name) if name == "TF3MP_ROLE" then return "host" end end } }
		local s = { journal_test = main.PROBE_VERSION }
		logged = {}; main.sync_tick(env, s)
		assert(s.sync.world_pending and not s.sync.own_k)
		now = 60200; main.sync_tick(env, s)
		assert(not s.sync.world_pending and s.sync.own_k == 1)
		assert(sync.find(s.sync.own, 1).gt == 60000)
		assert(s.sync.world_lists[1].gt == 60000 and s.sync.world_lists[1].lists.hcon[1].d == "original snapshot")
		assert(contains(logged, "gt=60000 hcon=h1_0000000000000001 wgt=60000"))
	end)
	sync.values, sync.world_step, main.game_time = saved_values, saved_step, saved_time
	assert(ok, err)
end)

test("snapshot diagnostics retain multiplicity, ignore repeated parts and never read the live world", function()
	local main = fresh_main()
	local state = mock_state()
	state:set({ sync = { world_lists = { [2] = { gt = 120000, lists = { hcon = {
		{ h = "aa", d = "duplicate building" }, { h = "aa", d = "duplicate building" } } } } } } })
	logged = {}
	local prefix = "W2 hcon 2 120000 "
	local suffix = " 2 h1_0000000000000001 2 0 "
	main.replay_line({}, prefix .. "1" .. suffix .. "aa:duplicate", "diag.1", state, 0)
	main.replay_line({}, prefix .. "1" .. suffix .. "aa:duplicate", "diag.1", state, 0)
	assert(state:get().world_rx.hcon.got == 1)
	main.replay_line({}, prefix .. "2" .. suffix .. "bb:different", "diag.2", state, 0)
	assert(not state:get().world_rx.hcon)
	assert(contains(logged, "1 only here, 1 only there"))
	logged = {}
	main.replay_line({}, "W2 hcon 2 120200 1 1 h1_0000000000000001 1 0 aa:x", "diag.3", state, 0)
	assert(contains(logged, "matching snapshot unavailable, skipped"))
	main.replay_line({}, "W2 hcon 2 120000 0 999 h1_0000000000000001 1 0 aa:x", "diag.4", state, 0)
	assert(contains(logged, "invalid snapshot diagnostic"))
end)

test("large diagnostic lists are bounded and clipped remote records are never called missing", function()
	local main = fresh_main()
	local list = {}; for i = 1, 200 do list[i] = { h = string.format("%016x", i), d = "building " .. i } end
	local own = { ck = 3, gt = 180000, wgt = 180000, hcon = "h1_0000000000000001" }
	logged = {}
	main.world_send({}, { world_lists = { [3] = { gt = own.gt, lists = { hcon = list } } } }, own, { "hcon" })
	assert(contains(logged, "128/200 snapshot records sent (diagnostic limit)"))
	local lines = {}
	for _, text in ipairs(logged) do local line = text:match("net send (W2 .*)$"); if line then lines[#lines + 1] = line; assert(#line <= 6000) end end
	assert(#lines > 0 and #lines <= main.WORLD_MAX_PARTS)
	local state = mock_state(); state:set({ sync = { world_lists = { [3] = { gt = own.gt, lists = { hcon = list } } } } })
	logged = {}
	for i, line in ipairs(lines) do main.replay_line({}, line, "bounded." .. i, state, 0) end
	assert(contains(logged, "0 only here, 0 only there; remote list truncated"))
end)

-- v34: a build held before execution (hold.lua) travels the common timeline; the host builds
-- it at the stamp through its own replay path, and the timeline releases after both results.
test("a held build is planned, built here at its common stamp and released after both results", function()
	local timeline = require("/mp_probe/timeline.lua")
	local line = build.serialize(run5_street())
	with_engine_api({}, function(t)
		logged = {}
		local real_os = os
		local vars = { TF3MP_ROLE = "host", TF3MP_ORDERING = "1", TF3MP_PEER_CLOCK = "gt=1000" }
		os = setmetatable({ getenv = function(k) return vars[k] end }, { __index = real_os })
		local speeds = {}
		t.env.api.cmd.makeGameSetSpeedCmd = function(speed) speeds[#speeds + 1] = speed; return { speed = speed } end
		local ok, err = pcall(function()
			local state = mock_state()
			local client = timeline.new("client")
			local sent_lines, seen = {}, 0
			local function host_out()
				for i = seen + 1, #logged do
					local text = logged[i]:match("net send (S1 .+)$")
					if text then sent_lines[#sent_lines + 1] = text end
				end
				seen = #logged
			end
			local cn = 0
			local function pump(client_now)
				for _ = 1, 20 do
					host_out()
					local moved = false
					while #sent_lines > 0 do
						assert(timeline.receive(client, table.remove(sent_lines, 1), client_now)); moved = true
					end
					local reply = timeline.take(client)
					while reply do
						cn = cn + 1
						fresh_main().handleEvent(nil, state, "mp_probe", "mp_probe_replay", "mp_probe_replay",
							{ line = reply, number = "c1." .. cn, offset = 0, source = "net" })
						reply = timeline.take(client); moved = true
					end
					fresh_main().timeline_tick(_G, state)
					if not moved and #sent_lines == 0 then
						host_out(); if #sent_lines == 0 then return end
					end
				end
			end
			fresh_main().handleEvent(nil, state, "mp_probe", "mp_probe_schedule", "mp_probe_schedule", { line = line, held = true })
			assert(not contains(logged, "timeline intent rejected"), table.concat(logged, "\n"))
			fresh_main().timeline_tick(_G, state); pump(1000)
			local m = state:get().timeline
			assert(m.active and m.active.phase == "committed" and client.active.phase == "committed", table.concat(logged, "\n"))
			local at = m.active.at
			assert(at == 5000 and #t.sent == 0, "nothing built before the stamp")
			-- Both reach the stamp; the client says so, the host gives GO and builds here.
			t.advance(at - 1000)
			assert(not timeline.step(client, at, at)); pump(at)
			fresh_main().timeline_tick(_G, state); pump(at)
			assert(client.active.go, "client received GO")
			local ev
			for _, e in ipairs(t.events) do if type(e[4]) == "table" and e[4].schedule_seq then ev = e end end
			assert(ev and ev[4].line == line and ev[4].source == "scheduled" and ev[4].offset == 0, table.concat(logged, "\n"))
			fresh_main().handleEvent(nil, state, ev[1], ev[2], ev[3], ev[4])
			assert(#t.sent == 1 and contains(logged, "replay result (SimpleProposal/table): BUILT"), table.concat(logged, "\n"))
			assert(contains(logged, "timeline result host.1 OK") and contains(logged, "timeline execute host.1 at gt=5000"), table.concat(logged, "\n"))
			assert(state:get().timeline.active.own_done)
			-- The client builds too; its DONE lets the host release the command and the hold.
			assert(timeline.step(client, at, at)); assert(timeline.complete(client, 1, true)); pump(at)
			fresh_main().timeline_tick(_G, state); pump(at)
			m = state:get().timeline
			assert(not m.active and m.last == 1 and not client.active and client.last == 1, table.concat(logged, "\n"))
			assert(timeline.clock(m).hold == 0 and not m.error)
		end)
		os = real_os
		if not ok then error(err, 0) end
	end)
end)

test("a held build is refused only in a session and handed over after the wait", function()
	local hold = require("/mp_probe/hold.lua")
	local proposal = run5_street()
	local data = { errorState = { critical = false }, costs = 10 }
	local p = { proposal = proposal, toAdd = {}, toRemove = {} }
	local gstate = { value = nil }
	function gstate:get() return self.value end
	function gstate:set(v) self.value = v end
	local vars = { TF3MP_ROLE = "client", TF3MP_ORDERING = "1", TF3MP_OWN_CLOCK = "gt=1000 seq=0 phase=idle", TF3MP_PEER_CLOCK = "gt=1000 seq=0 phase=idle" }
	local now, events = 0, {}
	local env = { os = { getenv = function(k) return vars[k] end, clock = function() return now end },
		api = { cmd = { sendCommand = function(c) events[#events + 1] = c end,
			makeScriptingSendEventCmd = function(a, b, c, d) return { a, b, c, d } end },
			engine = {}, type = {} } }
	logged = {}
	local r = hold.event(env, "", "", "builder.proposalPrepareForApply", { p, data }, gstate)
	assert(r and r.errorMessages[hold.SYNC_TEXT], table.concat(logged, "\n"))
	assert(gstate.value.held and gstate.value.held.line:sub(1, 3) == "B5 ")
	assert(hold.event(env, "", "", "builder.proposalPrepareForApply", { p, data }, gstate) == nil, "one held build at a time")
	hold.step(env, gstate); assert(#events == 0, "waits HELD_WAIT_S")
	now = 1; hold.step(env, gstate)
	assert(#events == 1 and events[1][2] == "mp_probe_schedule" and events[1][4].held == true and events[1][4].line:sub(1, 3) == "B5 ")
	assert(gstate.value.waiting and not gstate.value.held)
	vars.TF3MP_OWN_CLOCK = "gt=1200 seq=1 phase=prepared"
	hold.step(env, gstate); assert(not gstate.value.waiting and not gstate.value.hold_off)
	-- A refusal TF3 ignores switches holding off; the build travels as before.
	local r2 = hold.event(env, "", "", "builder.proposalPrepareForApply", { p, data }, gstate)
	assert(r2)
	hold.event(env, "", "", "builder.proposalApply", { p, data }, gstate)
	assert(gstate.value.hold_off and not gstate.value.held)
	assert(hold.event(env, "", "", "builder.proposalPrepareForApply", { p, data }, gstate) == nil)
	-- Without a partner, or without the ordered DLL, nothing is held.
	local g2 = { value = nil, get = gstate.get, set = gstate.set }
	vars.TF3MP_PEER_CLOCK = ""
	assert(hold.event(env, "", "", "builder.proposalPrepareForApply", { p, data }, g2) == nil)
	vars.TF3MP_PEER_CLOCK = "gt=1000"
	vars.TF3MP_ORDERING = nil
	assert(hold.event(env, "", "", "builder.proposalPrepareForApply", { p, data }, g2) == nil)
end)

test("a handed-over build without a common tick switches holding off", function()
	local hold = require("/mp_probe/hold.lua")
	local gstate = { value = { waiting = { since = 0, seq = 3 } } }
	function gstate:get() return self.value end
	function gstate:set(v) self.value = v end
	local now = 0
	local vars = { TF3MP_ROLE = "host", TF3MP_ORDERING = "1", TF3MP_OWN_CLOCK = "seq=3 phase=idle" }
	local env = { os = { getenv = function(k) return vars[k] end, clock = function() return now end }, api = { cmd = {} } }
	logged = {}
	hold.step(env, gstate); assert(gstate.value.waiting)
	now = hold.GIVE_UP_S + 1; hold.step(env, gstate)
	assert(gstate.value.hold_off == "no common tick" and not gstate.value.waiting)
	gstate.value = { waiting = { since = now, seq = 3 } }
	vars.TF3MP_OWN_CLOCK = "seq=3 phase=failed"
	hold.step(env, gstate); assert(gstate.value.hold_off == "timeline failed")
end)

-- v35: vehicle commands clicked in the GUI are planned like held builds and run at the stamp.
local function vehicle_world(role, vars)
	local entities = {
		[30] = { NAME = { name = "Zug 1" }, PLAYER_OWNED = { player = 7 }, TRANSPORT_VEHICLE = { userStopped = false } },
		[31] = { NAME = { name = "Bus 2" }, PLAYER_OWNED = { player = 7 }, TRANSPORT_VEHICLE = { userStopped = false } },
		[40] = { NAME = { name = "Linie 1" }, PLAYER_OWNED = { player = 7 }, LINE = {} },
	}
	local sent = {}
	local ct = { NAME = "NAME", PLAYER_OWNED = "PLAYER_OWNED", TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE", LINE = "LINE" }
	vars = vars or {}
	vars.TF3MP_ROLE = role
	local env = { os = { getenv = function(k) return vars[k] end },
		api = { type = { ComponentType = ct },
			engine = { getComponent = function(id, c) return entities[id] and entities[id][c] end,
				forEachEntityWithComponent = function(fn, c)
					for id, e in pairs(entities) do if e[c] then fn(id) end end
				end,
				system = { lineSystem = { getLines = function()
					local out = {}
					for id, e in pairs(entities) do if e.LINE then out[#out + 1] = id end end
					return out
				end } },
				util = { getPlayer = function() return 7 end } },
			cmd = {
				makeVehicleReverseCmd = function(id) return { name = "reverse", id = id } end,
				makeVehicleSetStoppedByUserCmd = function(id, v) return { name = "stopped", id = id, value = v } end,
				makeVehicleSendToDepotCmd = function(id, v) return { name = "depot", id = id, value = v } end,
				makeVehicleSetLineCmd = function(id, line, stop) return { name = "line", id = id, line = line, stop = stop } end,
				makeVehicleSellCmd = function(list) return { name = "sell", list = list } end,
				sendCommand = function(c, callback) sent[#sent + 1] = c; if callback then callback(c, true) end end } } }
	return env, sent, entities
end

test("a clicked vehicle command is planned on the timeline in a session, else run at once (v35)", function()
	local main = fresh_main()
	local env, sent = vehicle_world("host", { TF3MP_ORDERING = "1" })
	local state = mock_state()
	logged = {}
	main.vehicle_intent(env, state, { command = "reverse", vehicle = 30 })
	assert(#sent == 0 and contains(logged, "planned for a common tick"), table.concat(logged, "\n"))
	local m = state:get().timeline
	assert(m and #m.queue == 1 and m.queue[1].line:sub(1, 3) == "A1 ", "not queued")
	-- No ordered session: it runs here at once, and a reverse is noted for the action poll.
	local solo, solo_sent = vehicle_world("client")
	local st = mock_state()
	logged = {}
	main.vehicle_intent(solo, st, { command = "reverse", vehicle = 30 })
	assert(#solo_sent == 1 and solo_sent[1].name == "reverse" and solo_sent[1].id == 30)
	assert(st:get().actions.user_reverse["30"] and contains(logged, "running it here now"))
	main.vehicle_intent(solo, st, { command = "stopped", vehicle = 30, value = true })
	assert(solo_sent[2].name == "stopped" and solo_sent[2].value == true)
	assert(not pcall(main.vehicle_intent, solo, st, { command = "sell", vehicle = 30 }))
end)

test("a failed ordered timeline reports a vehicle click without running it only here", function()
	local main = fresh_main()
	local env, sent = vehicle_world("host", { TF3MP_ORDERING = "1" })
	local state = mock_state()
	assert(main.vehicle_intent(env, state, { command = "reverse", vehicle = 30 }))
	local s = state:get(); s.timeline.error = "test failure"; state:set(s)
	logged = {}
	assert(main.vehicle_intent(env, state, { command = "reverse", vehicle = 30 }) == false)
	assert(#sent == 0, "failed shared scheduling executed a local vehicle command")
	assert(contains(logged, "action issue local I1") and contains(logged, "net send I1"), table.concat(logged, "\n"))
	assert(#state:get().timeline.queue == 1, "failed click was queued despite rejection")
end)

test("depot jumps resolve a different local depot before sending the native command", function()
	local main = fresh_main()
	local actions = require("/mp_probe/actions.lua")
	local fixture = assert(loadfile("tests/fixtures/actions_env.lua"))({actions=actions,wire=require("/mp_probe/wire.lua")})
	local source, dest = fixture.mock(), fixture.mock()
	source.construction(10, 12, 25); source.vehicle(30, 10010)
	dest.construction(91, 12, 25); dest.vehicle(90, 10091); dest.entities[90].NAME.name = "Bus 30"
	local entry = main.vehicle_entry(source.env, {command="depot",vehicle=30,value=false,jumpDepot=10010})
	assert(entry.jumpDepot.kind == "depot" and entry.jumpDepot.parent.key == "10")
	dest.env.os = {getenv=function(k) if k == "TF3MP_ROLE" then return "client" end end}
	local sent
	dest.env.api.cmd.makeVehicleSendToDepotCmd = function(id, sell, depot)
		assert(id == 90 and sell == false and depot == 10091)
		return {id=id,depot=depot}
	end
	dest.env.api.cmd.sendCommand = function(command, callback) sent=command; callback({},true) end
	assert(main.run_vehicle_command(dest.env, dest.state, {origin="host",commands={entry}}))
	assert(sent and sent.depot == 10091)
	-- Missing jump target rejects the whole batch before any command can run.
	sent = nil; dest.entities[91] = nil
	assert(not pcall(main.run_vehicle_command,dest.env,dest.state,{origin="host",commands={entry}}) and not sent)
end)

test("at the common tick both games run the vehicle command on their own vehicle (v35)", function()
	local main = fresh_main()
	local actions = require("/mp_probe/actions.lua")
	local line = actions.encode({ op = "vehicle_command", command = "stopped", value = true, origin = "client",
		target = { kind = "vehicle", key = "30", name = "Zug 1" } })
	for _, role in ipairs({ "host", "client" }) do
		local env, sent = vehicle_world(role)
		local state = mock_state()
		state:set({ actions = { snapshots = { vehicle = { ["30"] = { name = "Zug 1", userStopped = false } } } } })
		logged = {}
		assert(main.replay_line(env, line, "scheduled_client.1", state, 0) == true, table.concat(logged, "\n"))
		assert(#sent == 1 and sent[1].name == "stopped" and sent[1].id == 30 and sent[1].value == true)
		assert(state:get().actions.snapshots.vehicle["30"].userStopped == true, "would be sent back")
		assert(contains(logged, "vehicle stopped for Zug 1 at the common tick") and contains(logged, "vehicle stopped for Zug 1 done"))
	end
end)

test("v36: buses sent to a line and sold in one frame are one timed batch", function()
	local main = fresh_main()
	local wire = require("/mp_probe/wire.lua")
	local actions = require("/mp_probe/actions.lua")
	local env, sent = vehicle_world("client", { TF3MP_ORDERING = "1" })
	local state = mock_state()
	logged = {}
	main.vehicle_intent(env, state, { batch = wire.encode({ { command = "line", vehicle = 30, value = 40, stop = 2 },
		{ command = "line", vehicle = 31, value = 40, stop = 0 }, { command = "sell", vehicles = { 31 } } }) })
	assert(#sent == 0 and contains(logged, "vehicle line for Zug 1, line for Bus 2, sell of 1 vehicle(s) planned"), table.concat(logged, "\n"))
	local m = state:get().timeline
	assert(m.pending_requests == 1, "one request for the batch")
	-- Without a session the same batch runs at once, in click order.
	local solo, solo_sent = vehicle_world("host")
	main.vehicle_intent(solo, mock_state(), { batch = wire.encode({ { command = "line", vehicle = 30, value = 40, stop = 2 },
		{ command = "line", vehicle = 31, value = -1 }, { command = "sell", vehicles = { 30, 31 } } }) })
	assert(#solo_sent == 3 and solo_sent[1].name == "line" and solo_sent[1].line == 40 and solo_sent[1].stop == 2)
	assert(solo_sent[2].line == -1 and solo_sent[3].name == "sell" and #solo_sent[3].list == 2)
	assert(not pcall(main.vehicle_intent, solo, mock_state(), { batch = "nonsense" }))
end)

test("native next-reachable-stop choice survives GUI intent and both scheduled replays", function()
	local main = fresh_main()
	local wire = require("/mp_probe/wire.lua")
	local actions = require("/mp_probe/actions.lua")
	local env = vehicle_world("host", { TF3MP_ORDERING = "1" })
	local state = mock_state()
	main.vehicle_intent(env, state, { command = "line", vehicle = 30, value = 40, stop = -1 })
	local line = state:get().timeline.queue[1].line
	local action = assert(actions.decode(line)); assert(action.commands[1].stop == -1)
	for _, role in ipairs({ "host", "client" }) do
		local dest, sent = vehicle_world(role)
		assert(main.replay_line(dest, line, "scheduled_host.1", mock_state(), 0))
		assert(#sent == 1 and sent[1].name == "line" and sent[1].stop == -1)
	end
	local solo, sent = vehicle_world("host")
	main.vehicle_intent(solo, mock_state(), { command = "line", vehicle = 30, value = 40, stop = -1 })
	assert(sent[1].stop == -1, "fallback must preserve the UI choice too")
end)

test("rejected timed line assignment retains the old snapshot and reports TF3's path diagnosis", function()
	local main = fresh_main()
	local actions = require("/mp_probe/actions.lua")
	local transport = require("/mp_probe/transport.lua")
	local env, sent = vehicle_world("host")
	env.api.type.Failure = { Reason = { NoPath = 7 } }
	env.api.engine.util.line = { getFailedPathReason = function(id, line, full)
		assert(id == 30 and line == 40 and full)
		return { reason = 7, pos = { x = 123.5, y = -50 } }
	end }
	env.api.cmd.sendCommand = function(c, callback) sent[#sent + 1] = c; callback({}, false) end
	local state = mock_state()
	state:set({ actions = { snapshots = { vehicle = { ["30"] = { name = "Zug 1", held = true } } } } })
	assert(transport.begin(state, "scheduled_host.1"))
	main.run_vehicle_command(transport.env(env, state), state, { origin = "host", commands = {
		{ command = "line", target = actions.vehicle_ref(env, 30), line = actions.line_ref(env, 40), stop = -1 } } })
	local s = state:get()
	assert(s.actions.snapshots.vehicle["30"].held and not s.actions.snapshots.vehicle["30"].line)
	assert(s.network_work.pending == 0 and s.network_work.error:find("no path at 123.5, -50.0", 1, true))
	env.api.engine.util.line.getFailedPathReason = function() error("not available") end
	assert(main.vehicle_line_failure(env, 30, 40, -1):find("diagnosis unavailable", 1, true))
	env.api.engine.util.line.getDetailedLineProblems = function(line)
		assert(line == 40)
		return { { {noPath=true} }, { {incompatibleStop=true} } }
	end
	local detail = main.vehicle_line_failure(env, 30, 40, -1)
	assert(detail:find("segment 0 point 0: no path",1,true) and detail:find("segment 1 point 0: incompatible stop",1,true), detail)
end)

test("v36: at the common tick the other game finds the bus and the line it bound earlier", function()
	local main = fresh_main()
	local actions = require("/mp_probe/actions.lua")
	-- The host's bus 900 on the host's line 800; here they are 31 and 40 (bound by earlier actions).
	local line = actions.encode({ op = "vehicle_command", origin = "host", commands = {
		{ command = "line", target = { kind = "vehicle", key = "900", name = "Bus 2" },
			line = { kind = "line", key = "800", name = "Linie 1" }, stop = 1 },
		{ command = "sell", targets = { { kind = "vehicle", key = "30", name = "Zug 1" } } } } })
	local env, sent = vehicle_world("client")
	local state = mock_state()
	state:set({ action_entities = { ["13620:vehicle:900"] = 31, ["13620:line:800"] = 40 },
		actions = { snapshots = { vehicle = { ["31"] = { name = "Bus 2", held = true }, ["30"] = { name = "Zug 1" } } } } })
	logged = {}
	assert(main.replay_line(env, line, "scheduled_host.4", state, 0) == true, table.concat(logged, "\n"))
	assert(#sent == 2 and sent[1].name == "line" and sent[1].id == 31 and sent[1].line == 40 and sent[1].stop == 1)
	assert(sent[2].name == "sell" and sent[2].list[1] == 30)
	local snaps = state:get().actions.snapshots.vehicle
	assert(snaps["31"].line.key == "40" and snaps["31"].stopIndex == 1 and snaps["31"].held == nil, "would be sent back")
	assert(snaps["30"] == nil, "a sold vehicle would be reported as removed")
	-- A target that is not there yet stops everything before anything runs.
	local missing = actions.encode({ op = "vehicle_command", origin = "host", commands = {
		{ command = "stopped", target = { kind = "vehicle", key = "30", name = "Zug 1" }, value = true },
		{ command = "reverse", target = { kind = "vehicle", key = "901", name = "Bus 9" } } } })
	local env2, sent2 = vehicle_world("client")
	local ok = pcall(main.replay_line, env2, missing, "scheduled_host.5", mock_state(), 0)
	assert(not ok and #sent2 == 0)
end)

test("v36: a planned vehicle command waits for earlier replays and for its targets", function()
	local main = fresh_main()
	local actions = require("/mp_probe/actions.lua")
	local env = vehicle_world("client")
	local line = actions.encode({ op = "vehicle_command", origin = "host", commands = {
		{ command = "line", target = { kind = "vehicle", key = "900", name = "Bus 9" },
			line = { kind = "line", key = "800", name = "Linie 1" }, stop = 0 } } })
	local intent = { line = line, origin = "host", seq = 3 }
	local ok, why = main.intent_ready(env, { action_inbox = { {} } }, intent, "client")
	assert(not ok and why:find("still being replayed"))
	ok, why = main.intent_ready(env, {}, intent, "client")
	assert(not ok and why:find("not found"), why)
	assert(main.intent_ready(env, { action_entities = { ["13620:vehicle:900"] = 31 } }, intent, "client"))
	assert(main.intent_ready(env, {}, { line = "B5 x", origin = "host", seq = 4 }, "client"), "builds do not wait")
end)

test("vehicle reference waits use elapsed time instead of heartbeat count", function()
	local main = fresh_main()
	local now, wait = 100, {}
	local env = {os={time=function() return now end, clock=function() return 900 end}}
	for _ = 1, 40 do assert(main.intent_wait_pending(env,wait)) end
	now=103; assert(main.intent_wait_pending(env,wait), "fast events consumed the four-second grace period")
	now=104; assert(not main.intent_wait_pending(env,wait))
	wait={}; env={os={}}
	for _=1,main.INTENT_WAIT_STEPS do assert(main.intent_wait_pending(env,wait)) end
	assert(not main.intent_wait_pending(env,wait), "missing timer must remain bounded")
end)

test("v37: a replay that fails in a session is skipped; the common timeline carries on", function()
	local timeline = require("/mp_probe/timeline.lua")
	local wire = require("/mp_probe/wire.lua")
	local real_os = os
	local vars = { TF3MP_ROLE = "client", TF3MP_ORDERING = "1" }
	os = setmetatable({ getenv = function(k) return vars[k] end }, { __index = real_os })
	local ok, err = pcall(function()
		local main = fresh_main()
		assert(main.skip_failures(_G), "a client session skips")
		vars.TF3MP_ORDERING = "0"
		assert(not main.skip_failures(_G), "'Gastgeber simulieren' (client without the host's ordering) keeps FAIL")
		vars.TF3MP_ORDERING = "1"
		-- A common-tick command that this game could not run (its target is missing here).
		local m = timeline.new("client")
		assert(timeline.receive(m, "S1 " .. wire.encode({ op = "plan", seq = 1, at = 200, line = "A1 x", origin = "host" }), 0))
		assert(timeline.receive(m, "S1 " .. wire.encode({ op = "commit", seq = 1, at = 200 }), 0))
		timeline.step(m, 200, 200)
		assert(timeline.receive(m, "S1 " .. wire.encode({ op = "go", seq = 1, at = 200 }), 200))
		assert(timeline.step(m, 200, 200), "executes")
		local state = mock_state()
		state:set({ timeline = m, network_work = { token = "scheduled_host.1", pending = 0, dispatched = true,
			error = "vehicle Bus 9 not found" } })
		logged = {}
		main.check_network(state)
		assert(contains(logged, "net skipped scheduled_host.1 (1 so far), the session carries on: vehicle Bus 9 not found"), table.concat(logged, "\n"))
		assert(contains(logged, "timeline result host.1 OK"))
		local after = state:get().timeline
		assert(not after.error and after.active.own_done, "the timeline did not stop")
		-- A failed message of the timeline itself still stops the session, so the launcher resyncs.
		state:set({ network_work = { token = "999-2.1", pending = 0, dispatched = true, noskip = true,
			error = "partner timeline failure: x" } })
		logged = {}
		main.check_network(state)
		assert(contains(logged, "net result 999-2.1 FAIL partner timeline failure: x"), table.concat(logged, "\n"))
		-- Entrance checks of a skipped replay do not fail the next one.
		state:set({ network_work = { token = "999-3.1", pending = 0, dispatched = true, error = "game command rejected" },
			weld_checks = { { file = "depot.con", position = {}, due = 0 } } })
		main.check_network(state)
		assert(state:get().weld_checks == nil, "weld checks dropped with the failed replay")
		-- Without a partner ('Allein testen') a failure stays a failure.
		vars.TF3MP_ROLE = "loopback"
		assert(not main.skip_failures(_G))
		state:set({ network_work = { token = "loop.1", pending = 0, dispatched = true, error = "nope" } })
		logged = {}
		main.check_network(state)
		assert(contains(logged, "net result loop.1 FAIL nope"), table.concat(logged, "\n"))
	end)
	os = real_os
	assert(ok, err)
end)

test("v37: a failed S1 line is marked so it is never skipped", function()
	local timeline = require("/mp_probe/timeline.lua")
	local wire = require("/mp_probe/wire.lua")
	local real_os = os
	local vars = { TF3MP_ROLE = "client", TF3MP_ORDERING = "1" }
	os = setmetatable({ getenv = function(k) return vars[k] end }, { __index = real_os })
	local saved_api = api
	local ok, err = pcall(function()
		api = { type = { ComponentType = { GAME_TIME = 100 } },
			engine = { util = { getWorld = function() return 10 end }, getComponent = function() return { gameTime = 500 } end } }
		local main = fresh_main()
		local state = mock_state()
		state:set({ network_work = { token = "999-4.1", pending = 0, dispatched = false } })
		local applied = main.replay_line(_G, "S1 " .. wire.encode({ op = "fail", seq = 0, reason = "boom" }), "999-4.1", state)
		assert(not applied, "the partner's failure fails here too")
		assert(state:get().network_work.noskip == true, "marked")
	end)
	api = saved_api
	os = real_os
	assert(ok, err)
end)

test("v37: a common-tick command that meets another replay runs again later instead of hanging", function()
	local timeline = require("/mp_probe/timeline.lua")
	local actions = require("/mp_probe/actions.lua")
	local real_os = os
	local aline = actions.encode({ op = "line_remove", targets = {} })
	local vars = { TF3MP_ROLE = "client", TF3MP_ORDERING = "1", TF3MP_PEER_CLOCK = "gt=4200",
		TF3MP_IN = "part 999-1.5 net 0 1 " .. aline }
	os = setmetatable({ getenv = function(k) return vars[k] end }, { __index = real_os })
	local saved_api = api
	local queue = {}
	local ok, err = pcall(function()
		api = {
			type = { ComponentType = { GAME_TIME = 100 } },
			engine = { util = { getWorld = function() return 10 end, getPlayer = function() return 1 end },
				getComponent = function(_, c) if c == 100 then return { gameTime = 4200 } end end },
			cmd = { makeScriptingSendEventCmd = function(a, b, c, d) return { event = { a, b, c, d } } end,
				makeGameSetSpeedCmd = function(speed) return { speed = speed } end,
				-- TF3 runs the events later, in the order they were sent (run 39).
				sendCommand = function(c) if c.event then queue[#queue + 1] = c.event end end },
		}
		local state = mock_state()
		local m = timeline.new("client")
		m.active = { seq = 1, at = 4000, line = "B5 x", origin = "host", phase = "committed", arrived = true, go = true }
		m.gt = 4000
		state:set({ timeline = m, updates = 7 })
		fresh_main().handleEvent(nil, state, "mp_probe", "mp_probe_replay", "mp_probe_replay", { timeline_tick = true })
		assert(#queue == 2 and tostring(queue[1][4].number) == "999-1.5" and tostring(queue[2][4].number) == "scheduled_host.1",
			"the DLL line and the execution in one tick")
		logged = {}
		for _, ev in ipairs(queue) do fresh_main().handleEvent(nil, state, ev[1], ev[2], ev[3], ev[4]) end
		local s = state:get()
		assert(s.network_work and s.network_work.token == "999-1.5", "the DLL line runs")
		assert(not s.timeline.active.executed and s.timeline.active.phase == "committed", "the held command is open again")
		assert(timeline.step(s.timeline, 4400, 4400) ~= nil, "a later step executes it")
		assert(contains(logged, "timeline execution of scheduled_host.1 waits for replay 999-1.5 before it"), table.concat(logged, "\n"))
	end)
	api = saved_api
	os = real_os
	assert(ok, err)
end)

test("v37: a staged step that throws while paused fails only its replay", function()
	local timeline = require("/mp_probe/timeline.lua")
	local real_os = os
	local vars = { TF3MP_ROLE = "host", TF3MP_ORDERING = "1", TF3MP_PEER_CLOCK = "gt=10000" }
	os = setmetatable({ getenv = function(k) return vars[k] end }, { __index = real_os })
	local saved_api = api
	local ok, err = pcall(function()
		api = {
			type = { ComponentType = { GAME_TIME = 100 } },
			engine = { util = { getWorld = function() return 10 end, getPlayer = function() return 1 end },
				getComponent = function(_, c) if c == 100 then return { gameTime = 10000 } end end },
			cmd = { makeScriptingSendEventCmd = function(...) return { event = { ... } } end,
				makeGameSetSpeedCmd = function(speed) return { speed = speed } end, sendCommand = function() end },
		}
		local main = fresh_main()
		local state = mock_state()
		local m = timeline.new("host")
		m.active = { seq = 1, at = 9800, line = "B5 x", origin = "host", phase = "executing", executed = true,
			arrived = true, peer_arrived = true, go = true }
		m.gt = 9800
		state:set({ timeline = m, network_work = { token = "scheduled_host.1", pending = 0, dispatched = true },
			network_followup = { phase = "construction", data = { constructions = {} }, player = 1, gates = true } })
		main.network_continue = function() error("boom in staged step") end
		logged = {}
		main.handleEvent(nil, state, "mp_probe", "mp_probe_replay", "mp_probe_replay", { timeline_tick = true })
		local s = state:get()
		assert(not s.timeline.error and s.network_work == nil, "the timeline carries on, the replay is closed")
		assert(contains(logged, "net skipped scheduled_host.1") and contains(logged, "timeline result host.1 OK"), table.concat(logged, "\n"))
	end)
	api = saved_api
	os = real_os
	assert(ok, err)
end)

test("track upgrades and node configurations preserve the junction needed by a later depot connection", function()
	local world, nodecfg = require("/mp_probe/world.lua"), require("/mp_probe/nodecfg.lua")
	local w = config_world()
	local env = mock_build_api()
	env.api.engine = w.env.api.engine
	env.api.type.ComponentType = w.env.api.type.ComponentType
	local send = env.api.cmd.sendCommand
	env.api.cmd.sendCommand = function(cmd, callback)
		-- Model the documented cleanup: a degree-two node can disappear when two compatible
		-- tracks are simplified. It is still named by the sender's subsequent depot track.
		if cmd.context.cleanupStreetGraph then
			w.comps[2] = nil; w.segments[2] = nil
			w.comps[11].BASE_EDGE.node1 = 3; w.comps[12] = nil
			w.segments[1], w.segments[3] = { 11 }, { 11 }
		end
		send(cmd, callback)
	end
	local data = street_data()
	data.nodes = {}; data.segments = { data.segments[1] }
	data.segments[1].node0, data.segments[1].node1 = 1, 2
	data.segments[1].roadType = 0
	data.segments[1].roadTemplate = "::/infrastructure/track/simple/simple.street_template"
	data.segments[1].roadStyle = "::/infrastructure/track/simple/simple.street"
	data.removed_segments = { { entity = 11, p0 = { x = 0, y = 0, z = 0 }, p1 = { x = 100, y = 0, z = 0 } } }
	data.positions_of = { [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 100, y = 0, z = 0 } }
	assert(build.replay(env, data, {}))
	assert(w.comps[2], "the track upgrade must preserve the junction")
	-- Apply the later configurations through the same context builder.
	w.data.configs[3] = nil
	w.env.api.cmd.makeWorldBuildProposalCmd = function(p, context) return { proposal = p, context = context } end
	local config_send = w.env.api.cmd.sendCommand
	w.env.api.cmd.sendCommand = function(cmd, cb)
		if cmd.context.cleanupStreetGraph then w.comps[2] = nil; w.segments[2] = nil end
		config_send(cmd, cb)
	end
	assert(nodecfg.apply(w.env, w.data, { log = function() end }) == 2)
	local depot_track = assert(build.deserialize("B5 f1;100,0,0"))
	assert(build.resolve(depot_track, fresh_main().finder(w.env)), "depot connection finds the preserved junction")
end)

test("nested command events cannot execute a construction follow-up twice", function()
	local main = fresh_main()
	local value = { network_work = { token = "nested.1", pending = 0, dispatched = true },
		network_followup = { phase = "finish", data = { configs = {} } } }
	local state = { get = function() return copy_value(value) end, set = function(_, v) value = copy_value(v) end }
	local applied = 0
	main.apply_node_configs = function()
		applied = applied + 1
		if applied == 1 then
			local nested = fresh_main()
			nested.apply_node_configs = main.apply_node_configs
			nested.network_run({}, state)
		end
	end
	main.network_continue({}, state)
	assert(applied == 1, "nested script event applied the same node configurations " .. applied .. " times")
	assert(value.network_followup.phase == "verify" and not value.network_followup.running)
	main.network_continue({}, state)
	assert(not value.network_followup and not value.network_work.error)
end)

test("a failed follow-up clears its reentrancy guard and reports the failure", function()
	local main, state = fresh_main(), mock_state()
	state:set({ network_work = { token = "nested.2", pending = 0, dispatched = true },
		network_followup = { phase = "finish", data = { configs = {} } } })
	main.apply_node_configs = function() error("configuration failed") end
	local ok, err = pcall(main.network_continue, {}, state)
	assert(not ok and tostring(err):find("configuration failed", 1, true))
	assert(not state:get().network_followup.running)
end)

test("rail bridges and tunnels travel with their kind and resolve resource indexes locally", function()
	local world = require("/mp_probe/world.lua")
	for _, kind in ipairs({ "BRIDGE", "TUNNEL" }) do
		local env, sent = mock_build_api()
		env.api.type.BaseEdgeType = { NORMAL = 0, BRIDGE = 1, TUNNEL = 2 }
		local resource = "::/infrastructure/" .. kind:lower() .. "/stone.lua"
		env.api.res = { bridgeTypeRep = {}, tunnelTypeRep = {} }
		local rep = kind == "BRIDGE" and env.api.res.bridgeTypeRep or env.api.res.tunnelTypeRep
		rep.getName = function(index) assert(index == 7); return resource end
		rep.find = function(name) assert(name == resource); return 23 end
		local p = run5_street()
		p.addedSegments[1].type = 1 -- railway, independent of BaseEdgeType
		p.addedSegments[1].comp.type = env.api.type.BaseEdgeType[kind]
		p.addedSegments[1].comp.typeIndex = 7
		local line = build.serialize(p, { edge_structure = function(c) return world.edge_structure(env, c) end })
		local parsed = assert(build.deserialize(line))
		assert(parsed.segments[1].structure.kind == kind and parsed.segments[1].structure.resource == resource)
		assert(build.replay(env, parsed, {}))
		local edge = sent[1].proposal.streetProposal.edgesToAdd[1]
		assert(edge.type == 1 and edge.comp.type == env.api.type.BaseEdgeType[kind])
		assert(edge.comp.typeIndex == 23, "use receiver's repository index instead of sender's index 7")
		local x, y = edge.comp.position0, edge.comp.position1
		assert(math.abs(x.z - parsed.nodes[1].position.z) < 0.001 and y.z ~= x.z, "height and slope retained")
		rep.find = function() return -1 end
		local count = #sent
		local ok = build.replay(env, parsed, {})
		assert(not ok and #sent == count, "missing bridge resource must not become a ground track")
	end
	assert(not build.deserialize("B5 b-9;BRIDGE;stone.lua"))
	assert(not build.deserialize("B5 b-1;BOGUS;stone.lua"))
end)

test("automatic field removals ignore empty construction placeholders", function()
	local frame = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 }
	local line, info = build.serialize({}, { to_add = { { fileName = "", transf = frame, params = {} } },
		to_remove = { 700 }, construction = function() return { file = "::/industries/forest/forest.con",
			position = { x = 1, y = 2, z = 3 } } end })
	assert(info.constructions == 0 and info.demolished == 1)
	assert(#assert(build.deserialize(line)).demolished == 1)
	assert(not line:find("c;;;", 1, true))
end)

test("unowned industries are cached for automatic field replacement captures", function()
	local main, world = fresh_main(), require("/mp_probe/world.lua")
	local frame = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 10,20,0,1 }
	local env = { api = { type = { ComponentType = { CONSTRUCTION = 1, PLAYER_OWNED = 2 } }, engine = {
		getComponent = function(id, ct)
			if ct == 2 then return { player = -1 } end
			return { fileName = id == 700 and "::/industries/farm/farm.con" or "town.con", transf = frame }
		end,
		forEachEntityWithComponent = function(fn) fn(700); fn(701) end,
	} } }
	assert(not next(world.player_constructions(env)))
	assert(world.player_constructions(env, true)[700] and not world.player_constructions(env, true)[701])
	local s = {}; main.remember_constructions(env, s, { { toRemove = {} }, {}, { 700, 701 } })
	assert(s.constructions['700'] and not s.constructions['701'])
	local line, info = build.serialize({}, { to_remove = { 700 }, construction = function(id) return s.constructions[tostring(id)] end })
	assert(info.demolished == 1 and #assert(build.deserialize(line)).demolished == 1)
end)

local function forest_crash_fixture()
	local f = assert(io.open("tests/fixtures/v41-station-over-forest.b5", "r"))
	local line = f:read("*a"); f:close()
	return line, assert(build.deserialize(line))
end

local function forest_crash_finder()
	local coords = {
		[1] = { x = 5248.647, y = -7529.928, z = 54.6 },
		[2] = { x = 5240.815, y = -7522.935, z = 54.6 },
		[3] = { x = 5193.967, y = -7591.17, z = 54.6 },
		[4] = { x = 5280.549, y = -7494.198, z = 54.6 },
	}
	local finder = {
		find_node = function(p) for id, v in pairs(coords) do if build.near(p, v) then return id end end end,
		find_edge = function(a, b) if (a == 1 and b == 2) or (a == 2 and b == 1) then return 115277 end end,
		edge_construction = function(id) if id == 115277 then return 700 end end,
		node_construction = function(id) if id == 1 or id == 2 then return 700 end end,
		find_construction = function(file) if file == "::/industries/forest/forest.con" then return 700 end end,
	}
	return finder
end

test("the recorded field crash never removes the industry's frozen entrance as a loose street", function()
	local _, data = forest_crash_fixture()
	assert(#data.constructions == 2 and #data.demolished == 0 and #data.removed_segments == 1)
	local gates = require("/mp_probe/weld.lua").gate_positions(data)
	build.drop_access(data); data.gate_positions = gates
	local jobs = build.plan_environment(data, forest_crash_finder())
	assert(#jobs == 1 and jobs[1].require_native and jobs[1].demolished[1].entity == 700)
	assert(jobs[1].constructions[1].params.modules[3] and not jobs[1].constructions[1].params.modules[7],
		"retain exactly the captured field modules")
	assert(#data.constructions == 1 and data.constructions[1].file:match("/stations/rail/"))
	assert(#data.nodes == 0 and #data.segments == 0 and #data.removed_segments == 0 and #data.removed_nodes == 0)
	assert(#data.configs == 25 and not next(data.foreign) and not data.replay_has_gates)
	-- Defense in depth for a capture whose construction replacement cannot be resolved.
	local bad = assert(build.deserialize("B5 r;5248.647,-7529.928,54.6;5240.815,-7522.935,54.6;0"))
	local ok, err = build.resolve(bad, forest_crash_finder())
	assert(not ok and err:find("construction-owned", 1, true))
end)

test("the recorded station waits for the native field callback; rejection never starts the station", function()
	for _, reject in ipairs({ false, true }) do
		local line, original_data = forest_crash_fixture()
		local forest = original_data.constructions[2]
		local env, sent = mock_build_api()
		env.api.type.ComponentType = { CONSTRUCTION = 100 }
		env.api.engine = { getComponent = function(id, ct)
			assert(id == 700 and ct == 100); return { fileName = forest.file, transf = forest.transf }
		end, util = { proposal = { createProposalReplaceConstruction = function(id, params)
			assert(id == 700 and build.params_to_string(params) == build.params_to_string(forest.params))
			return { native = true, toAdd = { { fileName = forest.file, transf = forest.transf, params = params } },
				toRemove = { 700 }, old2new = { [700] = 0 } }
		end } } }
		local make, send = env.api.cmd.makeWorldBuildProposalCmd, env.api.cmd.sendCommand
		local main, state, transport = fresh_main(), mock_state(), require("/mp_probe/transport.lua")
		local field_callback, field_done
		env.api.cmd.makeWorldBuildProposalCmd = function(p, context, ignore, player)
			if type_name_of(p) == nil and p.native then return { proposal = p, native = true } end
			assert(field_done, "station must wait for the native field command")
			assert(#p.streetProposal.edgesToRemove == 0 and #p.streetProposal.nodesToRemove == 0)
			assert(#p.constructionsToAdd == 1 and p.constructionsToAdd[1].fileName:match("/stations/rail/"))
			return make(p, context, ignore)
		end
		env.api.cmd.sendCommand = function(cmd, cb)
			if not cmd.native then
				send(cmd, cb)
				transport.check(state, function() error("station was acknowledged before its finish stage") end, true)
				assert(state:get().network_work and not state:get().network_done)
				return
			end
			sent[#sent + 1] = cmd
			field_callback = function()
				field_done = true
				cb({ resultEntities = reject and {} or { 700 }, resultProposalData = {
					costs = 1, errorState = { critical = reject } } }, not reject)
			end
		end
		main.finder = forest_crash_finder
		-- This test models native command order; station geometry verification has separate tests.
		main.apply_node_configs, main.verify_node_configs = function() end, function() end
		assert(transport.begin(state, "field.1"))
		local wrapped = transport.env(env, state)
		assert(main.replay_line(wrapped, line, "field.1", state, 0))
		main.network_run(wrapped, state); transport.dispatched(state)
		assert(#sent == 1 and state:get().network_work.pending == 1 and not state:get().network_done)
		field_callback(); main.network_run(wrapped, state)
		transport.check(state, function() end, true)
		assert(#sent == (reject and 1 or 2), "native field edit once, then station only on success: " .. #sent .. "; " .. table.concat(logged, "\n"))
		assert(state:get().network_done.skipped == (reject or nil))
	end
end)

test("industry field replacements never fall back to an unsafe simple construction command", function()
	local _, data = forest_crash_fixture()
	build.drop_access(data)
	local job = build.plan_environment(data, forest_crash_finder())[1]
	local env, sent = mock_build_api()
	local ok, err = build.replay(env, job, {})
	assert(not ok and #sent == 0 and err:find("native construction helper", 1, true))
end)

test("action diagnostics reach the other PC once without replay or echo", function()
	logged = {}
	local main, state = fresh_main(), mock_state()
	local transport = require("/mp_probe/transport.lua")
	main.skip_failures = function() return true end
	transport.begin(state,"peer.5"); transport.describe(state,"Bahnhof Süd bei 10, 20")
	transport.fail(state,"existing node not found"); transport.dispatched(state); main.check_network(state)
	local packet
	for _, text in ipairs(logged) do packet = packet or text:match("net send (I1 .+)$") end
	assert(packet and state:get().network_done.skipped and not state:get().network_work)
	logged = {}
	local other = mock_state(); transport.begin(other,"diag.1")
	assert(main.replay_line({},packet,"diag.1",other,0))
	transport.dispatched(other); main.check_network(other)
	assert(contains(logged,"action issue peer I1 peer.5 none"))
	assert(not contains(logged,"net send I1"), "a received diagnostic must not echo")
	assert(other:get().network_done.result=="OK" and not other:get().network_done.skipped)
	assert(not main.replay_line({},packet.."\nnet result forged OK","diag.2",other,0))
end)

test("fresh bridge world initializes without legacy and discards saved transient work", function()
	local main=fresh_main()
	local s={ loaded_world="old", network_work={}, network_followup={}, actions={}, action_inbox={}, action_work={}, action_busy=true, sync={}, timeline={} }
	local world, ack = "123-456-1", ""
	local env={os={getenv=function(key) return key=="TF3MP_WORLD" and world or ack end}}
	logged={}; main.initialize_loaded_world(env,s)
	assert(s.loaded_world==world and not s.network_work and not s.actions and not s.action_busy and not s.sync and not s.timeline)
	assert(contains(logged,"net initialized "..world))
	s.actions={kept=true}; ack=world
	for _=1,25 do main.initialize_loaded_world(env,s) end
	assert(s.actions.kept, "repeated checks must keep current-world actions")
	world="123-789-2"; main.initialize_loaded_world(env,s)
	assert(not s.actions and s.loaded_world==world)
end)

test("a stop close to an intersection keeps its exact native edge fraction", function()
	local param = 0.00912345678901234
	local data = assert(build.deserialize(stop_build(false, param)))
	assert(data.objects[1].param == param)
end)

test("a rejected two-stop replay never tries indexes beyond edgeObjectsToAdd", function()
	local f = assert(io.open("tests/fixtures/fliederweg-v54.b5", "r"))
	local data = assert(build.deserialize(f:read("*l"))); f:close()
	assert(build.resolve(data, {
		find_node = function(p) return p.x < 7100 and 11 or 12 end,
		find_edge = function() return 600 end, find_construction = function() end,
		edge_objects_of = function() return {} end,
	}))
	local env, sent = mock_build_api({ builds = {} })
	local ok = build.replay(env, data, { player = 29125 })
	assert(not ok and #sent > 0)
	for _, cmd in ipairs(sent) do
		local sp = cmd.proposal.streetProposal
		assert(#sp.edgeObjectsToAdd == 2)
		assert(sp.edgesToAdd[1].comp.objects[1][1] == -400000000)
		assert(sp.edgesToAdd[1].comp.objects[2][1] == -400000001)
	end
end)

test("station extension distinguishes a retained open track end from a real network entrance", function()
	local p = run5_station()
	local end_node = p.addedNodes[2]
	table.remove(p.addedNodes, 2)
	for i, index in ipairs(p.frozenNodes) do if index >= 2 then p.frozenNodes[i] = index - 1 end end
	for _, degree in ipairs({ 1, 2 }) do
		local _, info = build.serialize(p, {
			node_position = function(id) assert(id == end_node.entity); return end_node.comp.position end,
			node_degree = function(id) assert(id == end_node.entity); return degree end,
		})
		assert(info.gates == (degree == 1 and 0 or 1))
		assert(info.access == info.gates and info.segments == info.gates)
	end
end)

print(string.format("%d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

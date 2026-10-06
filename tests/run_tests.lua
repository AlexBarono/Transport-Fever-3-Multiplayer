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

-- Street build of run 5 (logs/probe-log-5-mp_probe.txt, "player #1"): 3 new nodes, 2 new segments.
local function run5_street()
	local function node(entity, x, y, z)
		return { entity = entity, comp = { position = { x = x, y = y, z = z } } }
	end
	local function segment(entity, node0, node1, t0, t1)
		return { entity = entity, type = 0, comp = {
			type = 0, node0 = node0, node1 = node1, typeIndex = -1,
			tangent0 = { x = t0[1], y = t0[2], z = t0[3] },
			tangent1 = { x = t1[1], y = t1[2], z = t1[3] },
		} }
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
	assert(#state.subscribed == 1 and state.subscribed[1] == "onPostBuildProposal", "subscribed once")
	assert(contains(logged, "subscribe onPostBuildProposal: ok"))
end)

local function player_build_param()
	return { { proposal = run5_street(), toAdd = {} }, {}, { 501 }, false }
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
	assert(line:sub(1, 2) == "B1", line)
	assert(line:find("n-1;-2888.017,-3941.508,1.675", 1, true), line)
	assert(line:find("s-1;0;-1;-2;", 1, true), line)
	assert(line:find("s-2;0;-2;-3;", 1, true), line)
	assert(not line:find("51389", 1, true), "engine ids must not travel")
	assert(#line < 400, "a street build fits in a short line: " .. #line)
end)

test("serialize counts nodes the player connected to", function()
	local proposal = run5_street()
	proposal.addedNodes = { proposal.addedNodes[1] }
	local _, info = build.serialize(proposal)
	assert(info.foreign_nodes == 3, info.foreign_nodes)
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
	assert(math.abs(data.segments[1].tangent0.y - 54.226) < 0.001, data.segments[1].tangent0.y)
end)

test("deserialize rejects broken lines", function()
	assert(build.deserialize("n-1;1,2,3") == nil, "a line without a version is rejected")
	assert(build.deserialize("B99 n-1;1,2,3") == nil, "a newer format is rejected")
	assert(build.deserialize("B1 n-1;1,2") == nil, "a short position is rejected")
	assert(build.deserialize("B1 s-1;0;-1") == nil, "a short segment is rejected")
	assert(build.deserialize(42) == nil)
	local data = assert(build.deserialize("B1"), "an empty proposal parses")
	assert(#data.nodes == 0 and #data.segments == 0)
end)

--- A C++-vector-like list: index assignment raises, push_back works (as a TF3 Vector_* might).
local function vector_list()
	local items = {}
	return setmetatable({}, {
		__len = function() return #items end,
		__index = function(_, k)
			if k == "push_back" then return function(_, v) items[#items + 1] = v end end
			return items[k]
		end,
		__newindex = function() error("cannot assign to a vector") end,
	})
end

--- Mock of the TF3 types used when rebuilding. Only the type named in opts.layout exists.
local function mock_build_api(opts)
	opts = opts or {}
	local sent = {}
	local list = opts.vectors and vector_list or function() return {} end
	local function vec() return { x = 0, y = 0, z = 0 } end
	local types = {
		Context = { new = function() return { context = true } end },
		NodeAndEntity = { new = function() return { comp = { position = vec() } } end },
		SegmentAndEntity = { new = function() return { comp = { tangent0 = vec(), tangent1 = vec() } } end },
	}
	if opts.layout == "SimpleProposal" then
		types.SimpleProposal = { new = function()
			return { streetProposal = { nodesToAdd = list(), edgesToAdd = list() } }
		end }
	elseif opts.layout == "WorldBuildProposal" then
		types.WorldBuildProposal = { new = function()
			return { proposal = { addedNodes = list(), addedSegments = list() }, toAdd = {} }
		end }
	end
	local api = {
		type = types,
		cmd = {
			makeWorldBuildProposalCmd = function(proposal, context, flag)
				if opts.required_args and select("#", proposal, context, flag) ~= opts.required_args then
					error("wrong number of arguments")
				end
				if opts.needs_context and context == nil then error("Error decoding argument #2") end
				return { proposal = proposal, context = context, flag = flag }
			end,
			sendCommand = function(cmd) sent[#sent + 1] = cmd end,
		},
	}
	return { api = api }, sent
end

test("replay fills a SimpleProposal (TF2 layout) and sends one command", function()
	local env, sent = mock_build_api({ layout = "SimpleProposal", needs_context = true })
	local data = assert(build.deserialize(build.serialize(run5_street())))
	local ok, message = build.replay(env, data)
	assert(ok, message)
	assert(message == "SimpleProposal: sent with signature 1", message)
	assert(#sent == 1, "commands sent: " .. #sent)
	local sp = sent[1].proposal.streetProposal
	assert(#sp.nodesToAdd == 3 and #sp.edgesToAdd == 2)
	assert(sp.edgesToAdd[1].entity == -1 and sp.edgesToAdd[2].comp.node0 == -2)
	assert(sp.edgesToAdd[1].comp.typeIndex == -1)
	assert(math.abs(sp.nodesToAdd[1].comp.position.z - 1.675) < 0.001)
	assert(sent[1].context ~= nil, "the command gets a context")
end)

test("replay falls back to WorldBuildProposal and fills C++-style vectors", function()
	local env, sent = mock_build_api({ layout = "WorldBuildProposal", vectors = true })
	local data = assert(build.deserialize(build.serialize(run5_street())))
	local attempts = {}
	local ok, message = build.replay(env, data, function(line) attempts[#attempts + 1] = line end)
	assert(ok, message)
	assert(message:find("WorldBuildProposal", 1, true), message)
	assert(#sent[1].proposal.proposal.addedSegments == 2)
	assert(#sent[1].proposal.proposal.addedNodes == 3)
	assert(contains(attempts, "SimpleProposal: "), "the failed first layout is logged")
end)

test("replay logs every failed signature on its own line", function()
	local env, sent = mock_build_api({ layout = "SimpleProposal", required_args = 99 })
	local data = assert(build.deserialize(build.serialize(run5_street())))
	local attempts = {}
	local ok, message = build.replay(env, data, function(line) attempts[#attempts + 1] = line end)
	assert(not ok and message == "no layout worked", message)
	assert(#sent == 0)
	assert(contains(attempts, "SimpleProposal signature 5: "), table.concat(attempts, "\n"))
	assert(contains(attempts, "WorldBuildProposal: "))
	assert(contains(attempts, "StreetProposal: "))
end)

test("append uses push_back when index assignment fails and reports a nil list", function()
	local v = vector_list()
	build.append(v, "a")
	build.append(v, "b")
	assert(#v == 2 and v[2] == "b")
	local ok, err = pcall(build.append, nil, "x")
	assert(not ok and tostring(err):find("list is nil", 1, true))
end)

test("side_offset points at a right angle to the first segment", function()
	local data = assert(build.deserialize(build.serialize(run5_street())))
	local dx, dy = build.side_offset(data, 40)
	local t = data.segments[1].tangent0
	assert(math.abs(dx * t.x + dy * t.y) < 1e-6, "perpendicular")
	assert(math.abs(math.sqrt(dx * dx + dy * dy) - 40) < 1e-6, "40 m")
	build.offset(data, dx, dy)
	assert(math.abs(data.nodes[1].position.x - (-2888.017 + dx)) < 0.001)
end)

test("replay_last builds at most MAX_REPLAYS copies and ignores the copy's own build event", function()
	local main = load_resource("/mp_probe/main.script.lua")
	main.MAX_REPLAYS = 1
	logged = {}
	local env = mock_build_api({ layout = "SimpleProposal" })
	local state = mock_state()
	main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param())
	main.replay_last(env)
	assert(contains(logged, "replay: ok, SimpleProposal: sent with signature 1"), table.concat(logged, "\n"))
	assert(contains(logged, "replay #1: 3 nodes, 2 segments, moved by"))
	-- The copy arrives as a new player build right after the replay and must not be stored again.
	main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", player_build_param())
	assert(contains(logged, "capture skipped: build arrived right after a replay"))
	main.pending_replay = "B1"
	main.replay_last(env)
	assert(contains(logged, "replay: limit of 1 reached"))
end)

test("replay without the engine api says so", function()
	local ok, message = build.replay({}, { nodes = {}, segments = {} })
	assert(not ok and message == "api missing", message)
end)

print(string.format("%d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

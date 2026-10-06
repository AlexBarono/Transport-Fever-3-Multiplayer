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

local function mock_state()
	local value = nil
	local st = { subscribed = {} }
	st.get = function(_) return value end
	st.set = function(_, v) value = v end
	st.subscribeToEvent = function(self, event) self.subscribed[#self.subscribed + 1] = event end
	return st
end

local probe = require("/mp_probe/probe.lua")

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

test("handleEvent dumps up to BUILD_DUMPS build proposals", function()
	local main = load_resource("/mp_probe/main.script.lua")
	main.BUILD_DUMPS = 2
	logged = {}
	local state = mock_state()
	for _ = 1, 4 do main.handleEvent(nil, state, "", "apply_command", "onPostBuildProposal", { {} }) end
	local dumps = 0
	for _, l in ipairs(logged) do
		if l:find("---- param of onPostBuildProposal", 1, true) then dumps = dumps + 1 end
	end
	assert(dumps == 2, "dumps " .. dumps)
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

print(string.format("%d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

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
	return {
		get = function(_) return value end,
		set = function(_, v) value = v end,
	}
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

test("snapshot collects fields and isolates errors", function()
	local env = { game = { interface = {
		getGameTime = function() return { time = 42 } end,
		getEntities = function() return { 1, 2, 3 } end,
		getPlayer = function() error("no player") end,
		getEntity = function() return {} end,
	} } }
	local snap = probe.snapshot(env)
	assert(snap.fields.game_time == 42)
	assert(snap.fields.vehicle_count == 3)
	assert(snap.errors.money ~= nil)
	assert(probe.format_snapshot(snap) == "game_time=42 vehicle_count=3 money=ERR")
end)

test("snapshot without game.interface reports an error", function()
	local snap = probe.snapshot({})
	assert(snap.errors.game_interface ~= nil)
end)

test("game script registration points at main.script", function()
	local reg = load_resource("/mp_probe/main.gs.lua")
	assert(reg.updateScript.fileName == "main.script@update")
	assert(reg.handleEventScript.fileName == "main.script@handleEvent")
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
	assert(snapshots == 2, "snapshots " .. snapshots)
	assert(state:get().probe_version == main.PROBE_VERSION)
end)

test("handleEvent logs each event type once", function()
	local main = load_resource("/mp_probe/main.script.lua")
	logged = {}
	local state = mock_state()
	main.handleEvent(nil, state, "a.lua", "id1", "onX", {})
	main.handleEvent(nil, state, "a.lua", "id1", "onX", {})
	main.handleEvent(nil, state, "a.lua", "id1", "onY", {})
	assert(#logged == 2, "logged " .. #logged)
end)

print(string.format("%d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

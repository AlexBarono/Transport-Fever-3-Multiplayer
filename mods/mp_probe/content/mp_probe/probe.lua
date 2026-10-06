--- Phase-0 probe: reports what the TF3 Lua sandbox allows and which engine API is visible.
-- Pure module (no engine calls at load time), so it can be tested offline.
-- @module mp_probe.probe
local probe = {}

--- Maximum number of lines a single table listing may produce.
probe.MAX_LINES = 400

local function sorted_keys(t)
	local keys = {}
	local ok = pcall(function()
		for k in pairs(t) do keys[#keys + 1] = k end
	end)
	if not ok then return {} end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local function has(env, path)
	local cur = env
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then return false end
		local ok, v = pcall(function() return cur[part] end)
		if not ok or v == nil then return false end
		cur = v
	end
	return true
end

--- Globals and library functions whose presence decides how the multiplayer bridge can work.
probe.CAPABILITIES = {
	"io", "io.open", "io.popen", "io.lines",
	"os", "os.time", "os.clock", "os.date", "os.getenv", "os.execute", "os.remove", "os.tmpname",
	"package", "package.loadlib", "package.cpath", "package.path", "package.preload",
	"require", "dofile", "loadfile", "load", "loadstring",
	"debug", "debug.getinfo", "debug.sethook",
	"string.dump", "collectgarbage", "setfenv", "getfenv",
	"ffi", "jit", "socket",
	"api", "api.cmd", "api.cmd.sendCommand", "api.engine", "api.res", "api.type", "api.gui",
	"game", "game.interface", "game.config",
}

--- Returns a list of "name: yes/no" lines for probe.CAPABILITIES plus a few active checks.
-- @param env table the global environment (normally _G)
-- @param opts table|nil { try_write = bool, write_path = string }
function probe.capabilities(env, opts)
	opts = opts or {}
	local lines = { "_VERSION: " .. tostring(env._VERSION) }
	for _, name in ipairs(probe.CAPABILITIES) do
		lines[#lines + 1] = name .. ": " .. (has(env, name) and "yes" or "no")
	end

	-- A C module that is not shipped with the game; only proves whether native loading is reachable.
	if has(env, "require") then
		local ok, err = pcall(env.require, "socket")
		lines[#lines + 1] = "require('socket'): " .. (ok and "loaded" or ("failed (" .. tostring(err):sub(1, 120) .. ")"))
	end

	if opts.try_write and has(env, "io.open") then
		local path = opts.write_path or "tf3_mp_probe_write_test.txt"
		local ok, f = pcall(env.io.open, path, "w")
		if ok and f then
			f:write("tf3 mp probe\n")
			f:close()
			lines[#lines + 1] = "file write (" .. path .. "): ok"
			if has(env, "os.remove") then pcall(env.os.remove, path) end
		else
			lines[#lines + 1] = "file write (" .. path .. "): failed (" .. tostring(f) .. ")"
		end
	end
	return lines
end

--- Lists the keys of a table (and of its __index table) recursively.
-- @return table lines like "api.cmd.sendCommand = function"
function probe.list(value, name, max_depth, lines)
	lines = lines or {}
	max_depth = max_depth or 2
	local function walk(v, path, depth, seen)
		if #lines >= probe.MAX_LINES then return end
		local t = type(v)
		lines[#lines + 1] = path .. " = " .. t
		if depth >= max_depth or seen[v] then return end
		local container = nil
		if t == "table" then
			container = v
		elseif t == "userdata" then
			local ok, mt = pcall(getmetatable, v)
			if ok and type(mt) == "table" and type(mt.__index) == "table" then container = mt.__index end
		end
		if not container then return end
		seen[v] = true
		for _, k in ipairs(sorted_keys(container)) do
			local ok, child = pcall(function() return container[k] end)
			if ok then walk(child, path .. "." .. tostring(k), depth + 1, seen) end
			if #lines >= probe.MAX_LINES then
				lines[#lines + 1] = "... (truncated at " .. probe.MAX_LINES .. " lines)"
				return
			end
		end
	end
	walk(value, name, 0, {})
	return lines
end

--- Collects a small, comparable snapshot of the simulation for the determinism test.
-- Every engine call is guarded: TF3 may name things differently than TF2.
-- @return table { fields = {name = value}, errors = {name = message} }
function probe.snapshot(env)
	local result = { fields = {}, errors = {} }
	local gi = has(env, "game.interface") and env.game.interface or nil
	local function try(name, fn)
		local ok, v = pcall(fn)
		if ok then result.fields[name] = v else result.errors[name] = tostring(v) end
	end
	if not gi then
		result.errors.game_interface = "game.interface missing"
		return result
	end
	try("game_time", function() return gi.getGameTime().time end)
	try("vehicle_count", function()
		return #gi.getEntities({ radius = 1e9 }, { type = "VEHICLE" })
	end)
	try("money", function() return gi.getEntity(gi.getPlayer()).balance end)
	return result
end

--- Formats a snapshot as one sorted, diff-friendly log line.
function probe.format_snapshot(snap)
	local parts = {}
	for _, k in ipairs(sorted_keys(snap.fields)) do
		parts[#parts + 1] = k .. "=" .. tostring(snap.fields[k])
	end
	for _, k in ipairs(sorted_keys(snap.errors)) do
		parts[#parts + 1] = k .. "=ERR"
	end
	return table.concat(parts, " ")
end

return probe

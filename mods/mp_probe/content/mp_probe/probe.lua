--- Phase-0 probe: reports what the TF3 Lua sandbox allows and which engine API is visible.
-- Pure module (no engine calls at load time), so it can be tested offline.
-- @module mp_probe.probe
local probe = {}

--- Maximum number of lines a single table listing may produce.
probe.MAX_LINES = 1500

local function sorted_keys(t)
	local keys = {}
	local ok = pcall(function()
		for k in pairs(t) do keys[#keys + 1] = k end
	end)
	if not ok then return {} end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

--- Engine proxy tables expose their metatable fields (__index, ...) and internal userdata keys.
-- They repeat under every entry and say nothing about the API, so listings skip them. Number keys
-- stay: event parameters and proposals are arrays.
local function is_noise_key(k)
	local t = type(k)
	if t == "number" then return false end
	return t ~= "string" or k:sub(1, 2) == "__"
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

--- Lists the keys of a table (and of a userdata's __index table) recursively.
-- @param max_lines number|nil line budget, defaults to probe.MAX_LINES
-- @return table lines like "api.cmd.sendCommand = function"
function probe.list(value, name, max_depth, lines, max_lines)
	lines = lines or {}
	max_depth = max_depth or 2
	max_lines = max_lines or probe.MAX_LINES
	local limit = #lines + max_lines
	local truncated = false
	local function walk(v, path, depth, seen)
		if #lines >= limit then
			truncated = true
			return
		end
		local t = type(v)
		if t == "number" or t == "boolean" or t == "string" then
			lines[#lines + 1] = path .. " = " .. t .. " " .. tostring(v):sub(1, 80)
		else
			lines[#lines + 1] = path .. " = " .. t
		end
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
			if not is_noise_key(k) then
				local ok, child = pcall(function() return container[k] end)
				local child_path = type(k) == "number" and (path .. "[" .. k .. "]") or (path .. "." .. k)
				if ok then walk(child, child_path, depth + 1, seen) end
			end
			if truncated then return end
		end
	end
	walk(value, name, 0, {})
	if truncated then lines[#lines + 1] = "... (" .. name .. " truncated at " .. max_lines .. " lines)" end
	return lines
end

--- Component types whose entity counts go into every snapshot. Run 2 showed that TF3 cannot loop
-- over LINE and BASE_EDGE with forEachEntityWithComponent; lines are counted via lineSystem instead.
probe.COUNTED_COMPONENTS = {
	"TRANSPORT_VEHICLE", "STATION", "CONSTRUCTION", "TOWN", "SIM_PERSON",
}

--- Rounds a coordinate to whole metres so tiny float noise does not hide real divergence.
local function round(x)
	return math.floor(x + 0.5)
end

--- Collects a small, comparable snapshot of the simulation for the determinism test.
-- TF3 has no game.interface, so everything goes through api.engine. Every call is guarded because
-- the TF2 names used here may not exist in TF3; failures land in `errors` with their message.
-- @return table { fields = {name = value}, errors = {name = message} }
function probe.snapshot(env)
	local result = { fields = {}, errors = {} }
	local function try(name, fn)
		local ok, v = pcall(fn)
		if ok and v ~= nil then
			result.fields[name] = v
		else
			result.errors[name] = ok and "nil" or tostring(v)
		end
	end
	if not has(env, "api.engine") then
		result.errors.api_engine = "api.engine missing"
		return result
	end
	local engine = env.api.engine
	local ct = has(env, "api.type.ComponentType") and env.api.type.ComponentType or nil

	try("game_time", function()
		return engine.getComponent(engine.util.getWorld(), ct.GAME_TIME).gameTime
	end)
	try("money", function()
		return engine.getComponent(engine.util.getPlayer(), ct.ACCOUNT).balance
	end)
	try("n_line", function()
		return #engine.system.lineSystem.getLines()
	end)
	-- Sum of all vehicle positions: diverges as soon as any vehicle moves differently.
	try("vehicle_pos_sum", function()
		local vehicles = engine.system.transportVehicleSystem.getVehicles()
		local sum = 0
		for i = 1, #vehicles do
			local p = engine.util.vehicle.getPosition(vehicles[i])
			sum = sum + round(p.x) + round(p.y) + round(p.z)
		end
		return sum
	end)
	for _, comp in ipairs(probe.COUNTED_COMPONENTS) do
		try("n_" .. comp:lower(), function()
			local n = 0
			engine.forEachEntityWithComponent(function() n = n + 1 end, ct[comp])
			return n
		end)
	end
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

--- One line per failed snapshot field with its error message, for diagnosis.
function probe.format_errors(snap)
	local lines = {}
	for _, k in ipairs(sorted_keys(snap.errors)) do
		lines[#lines + 1] = k .. ": " .. tostring(snap.errors[k]):sub(1, 200)
	end
	return lines
end

return probe

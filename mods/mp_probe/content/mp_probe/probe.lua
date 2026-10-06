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
	-- Vehicle checksums diverge as soon as any vehicle moves differently. Run 3 showed that
	-- transportVehicleSystem.getVehicles() wants arguments, so vehicles are collected by component.
	local function vehicles()
		local list = {}
		engine.forEachEntityWithComponent(function(v) list[#list + 1] = v end, ct.TRANSPORT_VEHICLE)
		table.sort(list)
		return list
	end
	try("vehicle_pos_sum", function()
		local sum = 0
		for _, v in ipairs(vehicles()) do
			local p = engine.util.vehicle.getPosition(v)
			sum = sum + round(p.x) + round(p.y) + round(p.z)
		end
		return sum
	end)
	try("vehicle_stop_sum", function()
		local sum = 0
		for _, v in ipairs(vehicles()) do
			sum = sum + engine.getComponent(v, ct.TRANSPORT_VEHICLE).stopIndex
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

--- Field names tried on engine objects that cannot be enumerated with pairs (C++ userdata such as
-- the build proposal). Taken from the TF2 API; whatever exists in TF3 shows up in the log.
probe.KNOWN_FIELDS = {
	"proposal", "context", "streetProposal", "toAdd", "toRemove",
	"constructionsToAdd", "constructionsToRemove", "edgesToAdd", "edgesToRemove",
	"nodesToAdd", "nodesToRemove", "edgeObjectsToAdd", "edgeObjectsToRemove",
	"addedSegments", "removedSegments", "addedNodes", "removedNodes", "new2oldSegments",
	"old2newSegments", "frozenEdges", "frozenNodes", "fileName", "params", "transf", "name",
	"playerEntity", "player", "cleanupStreetGraph", "gatherBuildings", "gatherFields",
	"checkTerrainAlignment", "costs", "errorState", "critical", "messages", "warnings",
	"collisionInfo", "entity", "type", "streetType", "trackType", "comp", "node0", "node1",
	"tangent0", "tangent1", "position", "x", "y", "z",
	-- TF3 guesses (api.type has Edge, EdgeGeometry.Straight/Arc/CubicSpline, Node, NodeAndEntity).
	"comp", "edge", "node", "geometry", "streetEdge", "trackEdge", "typeIndex", "objects",
	"start", "center", "radius", "angle", "length", "p0", "p1", "t0", "t1", "pos", "tangent",
	"nodes", "edges", "segment", "segments", "data", "owner", "ownerEntity", "width", "speed",
	"hasBus", "tramTrackType", "catenary", "edgeType", "edgeTypeName",
}

--- Probes probe.KNOWN_FIELDS on a value (recursing into whatever is found) and on array entries.
-- @return table lines like "param[1].streetProposal = userdata (#3)"
function probe.fields(value, name, max_depth, max_lines)
	local lines = {}
	max_lines = max_lines or 400
	local function describe(v)
		local t = type(v)
		if t == "number" or t == "boolean" or t == "string" then return t .. " " .. tostring(v):sub(1, 80) end
		local ok, n = pcall(function() return #v end)
		if ok and type(n) == "number" then return t .. " (#" .. n .. ")" end
		return t
	end
	local function walk(v, path, depth)
		if #lines >= max_lines or depth > max_depth then return end
		local t = type(v)
		if t ~= "table" and t ~= "userdata" then return end
		local ok_len, n = pcall(function() return #v end)
		if ok_len and type(n) == "number" then
			for i = 1, math.min(n, 3) do
				local ok, child = pcall(function() return v[i] end)
				if ok and child ~= nil then
					lines[#lines + 1] = path .. "[" .. i .. "] = " .. describe(child)
					walk(child, path .. "[" .. i .. "]", depth + 1)
				end
			end
		end
		for _, field in ipairs(probe.KNOWN_FIELDS) do
			local ok, child = pcall(function() return v[field] end)
			if ok and child ~= nil then
				lines[#lines + 1] = path .. "." .. field .. " = " .. describe(child)
				walk(child, path .. "." .. field, depth + 1)
			end
			if #lines >= max_lines then return end
		end
	end
	walk(value, name, 1)
	return lines
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

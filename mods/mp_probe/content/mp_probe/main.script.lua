--- Phase-0 probe game script.
-- Once per savegame (per PROBE_VERSION) it logs the sandbox capabilities and the visible engine API,
-- then logs a simulation snapshot every SNAPSHOT_EVERY updates for the determinism test (the first
-- one with the error message of every field it could not read), and the first occurrence of every
-- event it receives. All output goes to stdout.txt with tag [mp_probe].
-- @module mp_probe.main
local logger = require("/mp_probe/logger.lua")
local probe = require("/mp_probe/probe.lua")

local main = {}

--- Bump to re-run the one-time probe in a savegame that already ran it.
main.PROBE_VERSION = 4
main.SNAPSHOT_EVERY = 300
--- Depth and line budget for the structure dump of the first event of each kind.
main.EVENT_PARAM_DEPTH = 7
main.EVENT_PARAM_LINES = 800
--- Number of build proposals whose structure is dumped (each build looks different).
main.BUILD_DUMPS = 5

--- Events the engine only delivers on subscription. Build proposals are what a multiplayer
-- bridge has to capture and replay, so their parameter structure is dumped once.
main.SUBSCRIBED_EVENTS = { "onPostBuildProposal" }

--- Engine tables listed one by one, each with its own line budget (probe.MAX_LINES).
main.LISTED_ROOTS = {
	"api.engine", "api.type", "api.res", "api.cmd",
	"api.GameScriptStateNotificationHelper", "api.GameScriptTableHelper", "game.config",
}

local function lookup(env, path)
	local cur = env
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then return nil end
		cur = cur[part]
	end
	return cur
end

local function log_lines(header, lines)
	logger.info("---- " .. header .. " (" .. #lines .. " lines) ----")
	for _, line in ipairs(lines) do logger.info(line) end
end

function main.run_probe(env)
	log_lines("capabilities", probe.capabilities(env, { try_write = true }))
	for _, path in ipairs(main.LISTED_ROOTS) do
		local ok, value = pcall(lookup, env, path)
		if ok and value ~= nil then log_lines("listing " .. path, probe.list(value, path, 3)) end
	end
end

function main.update(_user_params, state, _dt)
	local s = state:get() or {}
	if s.probe_version ~= main.PROBE_VERSION then
		local ok, err = pcall(main.run_probe, _G)
		if not ok then logger.info("probe failed: " .. tostring(err)) end
		s.probe_version = main.PROBE_VERSION
	end

	if s.subscribed ~= main.PROBE_VERSION then
		for _, event in ipairs(main.SUBSCRIBED_EVENTS) do
			local ok, err = pcall(function() state:subscribeToEvent(event) end)
			logger.info("subscribe " .. event .. ": " .. (ok and "ok" or ("failed (" .. tostring(err) .. ")")))
		end
		s.subscribed = main.PROBE_VERSION
	end

	s.updates = (s.updates or 0) + 1
	if s.updates % main.SNAPSHOT_EVERY == 0 then
		local snap = probe.snapshot(_G)
		if s.snapshot_errors_logged ~= main.PROBE_VERSION then
			log_lines("snapshot errors", probe.format_errors(snap))
			s.snapshot_errors_logged = main.PROBE_VERSION
		end
		logger.info("snapshot update=" .. s.updates .. " " .. probe.format_snapshot(snap))
	end
	state:set(s)
end

function main.handleEvent(_user_params, state, src, id, name, param)
	local s = state:get() or {}
	s.seen_events = s.seen_events or {}
	local key = tostring(src) .. "|" .. tostring(id) .. "|" .. tostring(name)
	local prev = s.seen_events[key]
	local count = type(prev) == "number" and prev + 1 or 1
	local limit = name == "onPostBuildProposal" and main.BUILD_DUMPS or 1
	if count > limit then return end
	s.seen_events[key] = count
	state:set(s)
	logger.info("event src=" .. tostring(src) .. " id=" .. tostring(id) .. " name=" .. tostring(name) .. " #" .. count)
	local ok, lines = pcall(probe.list, param, "param", main.EVENT_PARAM_DEPTH, nil, main.EVENT_PARAM_LINES)
	if ok then log_lines("param of " .. tostring(name) .. " #" .. count, lines) end
	-- Build proposals arrive as C++ userdata that pairs() cannot enumerate; probe known field names.
	local ok_f, field_lines = pcall(probe.fields, param, "param", 6, main.EVENT_PARAM_LINES)
	if ok_f and #field_lines > 0 then log_lines("fields of " .. tostring(name) .. " #" .. count, field_lines) end
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global data().
function data()
	return main
end

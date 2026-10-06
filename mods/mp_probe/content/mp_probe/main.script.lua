--- Phase-0 probe game script.
-- Once per savegame (per PROBE_VERSION) it logs the sandbox capabilities and the visible engine API,
-- then logs a simulation snapshot every SNAPSHOT_EVERY updates for the determinism test, and the
-- first occurrence of every event it receives. All output goes to stdout.txt with tag [mp_probe].
-- @module mp_probe.main
local logger = require("/mp_probe/logger.lua")
local probe = require("/mp_probe/probe.lua")

local main = {}

--- Bump to re-run the one-time probe in a savegame that already ran it.
main.PROBE_VERSION = 1
main.SNAPSHOT_EVERY = 300

local function log_lines(header, lines)
	logger.info("---- " .. header .. " (" .. #lines .. " lines) ----")
	for _, line in ipairs(lines) do logger.info(line) end
end

function main.run_probe(env)
	log_lines("capabilities", probe.capabilities(env, { try_write = true }))
	for _, name in ipairs({ "api", "game" }) do
		if env[name] ~= nil then log_lines("listing " .. name, probe.list(env[name], name, 3)) end
	end
end

function main.update(_user_params, state, _dt)
	local s = state:get() or {}
	if s.probe_version ~= main.PROBE_VERSION then
		local ok, err = pcall(main.run_probe, _G)
		if not ok then logger.info("probe failed: " .. tostring(err)) end
		s.probe_version = main.PROBE_VERSION
	end

	s.updates = (s.updates or 0) + 1
	if s.updates % main.SNAPSHOT_EVERY == 0 then
		logger.info("snapshot update=" .. s.updates .. " " .. probe.format_snapshot(probe.snapshot(_G)))
	end
	state:set(s)
end

function main.handleEvent(_user_params, state, src, id, name, _param)
	local s = state:get() or {}
	s.seen_events = s.seen_events or {}
	local key = tostring(src) .. "|" .. tostring(id) .. "|" .. tostring(name)
	if s.seen_events[key] then return end
	s.seen_events[key] = true
	state:set(s)
	logger.info("event src=" .. tostring(src) .. " id=" .. tostring(id) .. " name=" .. tostring(name))
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global data().
function data()
	return main
end

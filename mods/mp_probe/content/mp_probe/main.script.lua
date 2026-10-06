--- Phase-0 probe game script.
-- Once per savegame (per PROBE_VERSION) it logs the sandbox capabilities and the visible engine API,
-- then logs a simulation snapshot every SNAPSHOT_EVERY updates for the determinism test (the first
-- one with the error message of every field it could not read), and the first occurrence of every
-- event it receives. All output goes to stdout.txt with tag [mp_probe].
-- @module mp_probe.main
local logger = require("/mp_probe/logger.lua")
local probe = require("/mp_probe/probe.lua")
local build = require("/mp_probe/build.lua")

local main = {}

--- Bump to re-run the one-time probe in a savegame that already ran it.
main.PROBE_VERSION = 7
main.SNAPSHOT_EVERY = 300
--- Depth and line budget for the structure dump of the first event of each kind.
main.EVENT_PARAM_DEPTH = 7
main.EVENT_PARAM_LINES = 800
--- Number of player build proposals whose structure is dumped (each build looks different).
-- Town builds (playerEntity -1, nothing new for the player) are dumped once at most.
main.BUILD_DUMPS = 3

--- Line budget per build dump. Run 5 showed that an unlimited dump of a station proposal writes
-- about 85000 lines and freezes the simulation for a minute, so every dump is capped.
main.BUILD_DUMP_LINES = 400

--- Components read for every entity a player build creates. Built edges and nodes are what a
-- second client has to recreate, so their full data is dumped (TF2 names, guarded).
main.ENTITY_COMPONENTS = {
	"BASE_EDGE", "BASE_EDGE_STREET", "BASE_EDGE_TRACK", "BASE_NODE", "PLAYER_OWNED",
}

--- Events the engine only delivers on subscription. Build proposals are what a multiplayer
-- bridge has to capture and replay, so their parameter structure is dumped once.
main.SUBSCRIBED_EVENTS = { "onPostBuildProposal" }

--- Replay test (phase 1, one PC). The copy is built this many metres beside the original so both
-- are visible; at most MAX_REPLAYS per game session, and builds arriving within REPLAY_QUIET_UPDATES
-- after a replay are not captured, so the copy does not trigger yet another copy.
main.REPLAY_SIDE_OFFSET = 40
main.MAX_REPLAYS = 3
main.REPLAY_QUIET_UPDATES = 50
main.replays_done = 0
main.updates = 0
main.quiet_until = -1

--- Bridge test (phase 1). The sandbox has no io, so the TF2 file exchange is impossible. Candidate
-- channels: Lua -> DLL through tagged lines in stdout.txt (the DLL tails the log), DLL -> Lua through
-- the process environment (the DLL calls _putenv_s on the shared CRT, Lua reads os.getenv).
main.BRIDGE_EVERY = 50
main.BRIDGE_ENV = "TF3MP_IN"

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

-- false so that a first nil (variable not set) is logged too.
local last_bridge_in = false

--- Sends one numbered line towards the DLL and logs whatever the DLL put into the environment.
function main.bridge_tick(env, seq)
	logger.info("bridge out seq=" .. seq)
	local getenv = env.os and env.os.getenv
	if not getenv then return end
	local ok, value = pcall(getenv, main.BRIDGE_ENV)
	if not ok then value = "ERR " .. tostring(value) end
	if value ~= last_bridge_in then
		logger.info("bridge in " .. main.BRIDGE_ENV .. "=" .. tostring(value))
		last_bridge_in = value
		if type(value) == "string" and string.find(value, "replay", 1, true) then
			main.replay_last(env)
		end
	end
end

--- Engine types whose fresh instances are described once before the first replay, so the log
-- shows which fields and list methods they really have (run 6 had to guess).
main.DESCRIBED_TYPES = {
	"SimpleProposal", "WorldBuildProposal", "StreetProposal", "Vector_NodeAndEntity", "Vector_SegmentAndEntity",
}
local types_described = false

function main.describe_types(env)
	if types_described then return end
	types_described = true
	local t = env.api and env.api.type
	if not t then return end
	for _, name in ipairs(main.DESCRIBED_TYPES) do
		local ok, value = pcall(function() return t[name].new() end)
		if ok and value ~= nil then
			local lines = {}
			pcall(probe.list, value, name, 2, lines, 40)
			pcall(function()
				for _, line in ipairs(probe.fields(value, name, 3, 60)) do lines[#lines + 1] = line end
			end)
			log_lines("type " .. name, lines)
		else
			logger.info("type " .. name .. ": new() failed (" .. tostring(value):sub(1, 150) .. ")")
		end
	end
end

--- Rebuilds the last captured build beside the original. The DLL asks for this by setting
-- TF3MP_IN=replay, which is the end-to-end test of phase 1 on a single PC.
function main.replay_last(env)
	local line = main.pending_replay
	if not line then
		logger.info("replay: nothing captured yet")
		return
	end
	if main.replays_done >= main.MAX_REPLAYS then
		logger.info("replay: limit of " .. main.MAX_REPLAYS .. " reached")
		return
	end
	main.pending_replay = nil
	main.replays_done = main.replays_done + 1
	main.quiet_until = main.updates + main.REPLAY_QUIET_UPDATES
	main.describe_types(env)
	local data, err = build.deserialize(line)
	if not data then
		logger.info("replay: bad line (" .. tostring(err) .. ")")
		return
	end
	local dx, dy = build.side_offset(data, main.REPLAY_SIDE_OFFSET)
	build.offset(data, dx, dy)
	logger.info(string.format("replay #%d: %d nodes, %d segments, moved by %.1f,%.1f",
		main.replays_done, #data.nodes, #data.segments, dx, dy))
	local ok, message = build.replay(env, data, function(attempt) logger.info("replay attempt " .. attempt) end)
	logger.info("replay: " .. (ok and "ok, " or "failed, ") .. message)
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

	if main.pending_replay == nil and s.last_build then main.pending_replay = s.last_build end

	s.updates = (s.updates or 0) + 1
	main.updates = s.updates
	if s.updates % main.BRIDGE_EVERY == 0 then
		pcall(main.bridge_tick, _G, s.updates / main.BRIDGE_EVERY)
	end
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

--- True for a build proposal the player made (new road or track segments, or a construction owned
-- by a player). The game itself also builds (towns), with playerEntity -1 and no segments.
function main.is_player_build(param)
	local ok, result = pcall(function()
		local ctx = param[1]
		if #ctx.proposal.addedSegments > 0 then return true end
		for i = 1, #ctx.toAdd do
			if ctx.toAdd[i].playerEntity ~= -1 then return true end
		end
		return false
	end)
	return ok and result
end

--- Dumps the components of the entities a build created. CONSTRUCTION is left out on purpose:
-- in run 5 a single station construction produced about 9000 lines.
function main.dump_new_entities(env, new_ids, label)
	local engine = env.api and env.api.engine
	local ct = env.api and env.api.type and env.api.type.ComponentType
	if not engine or not ct or type(new_ids) ~= "table" then return end
	for i = 1, math.min(#new_ids, 2) do
		local id = new_ids[i]
		for _, comp in ipairs(main.ENTITY_COMPONENTS) do
			local ok, value = pcall(function() return engine.getComponent(id, ct[comp]) end)
			if ok and value ~= nil then
				local ok_f, lines = pcall(probe.fields, value, "e" .. tostring(id) .. "." .. comp, 4, 60)
				if ok_f and #lines > 0 then log_lines("entity " .. tostring(id) .. " " .. comp .. " (" .. label .. ")", lines) end
			end
		end
	end
end

--- Serialises a player build and logs the line. The line is what a second game would receive;
-- it is kept in the savegame state so a replay test can rebuild it later.
function main.capture_build(state, s, param, label)
	local ok, line, info = pcall(build.serialize, param[1].proposal)
	if not ok then
		logger.info("capture failed (" .. label .. "): " .. tostring(line))
		return
	end
	logger.info("capture " .. label .. " nodes=" .. info.nodes .. " segments=" .. info.segments ..
		" foreign_nodes=" .. info.foreign_nodes)
	logger.info("capture line " .. line)
	if info.segments > 0 and info.foreign_nodes == 0 then
		s.last_build = line
		main.pending_replay = line
		state:set(s)
		logger.info("capture stored for replay (" .. #line .. " characters)")
	end
end

function main.handleEvent(_user_params, state, src, id, name, param)
	local s = state:get() or {}
	-- Event counts live in the savegame; start over for each probe version so a new version dumps again.
	if s.seen_events_version ~= main.PROBE_VERSION then
		s.seen_events = {}
		s.seen_events_version = main.PROBE_VERSION
	end
	local key = tostring(src) .. "|" .. tostring(id) .. "|" .. tostring(name)
	local player_build = name == "onPostBuildProposal" and main.is_player_build(param)
	if player_build then key = key .. "|player" end
	if player_build then
		if main.updates < main.quiet_until then
			logger.info("capture skipped: build arrived right after a replay (probably the copy)")
		else
			main.capture_build(state, s, param, "player build")
		end
	end
	local prev = s.seen_events[key]
	local count = type(prev) == "number" and prev + 1 or 1
	local limit = player_build and main.BUILD_DUMPS or 1
	if count > limit then return end
	s.seen_events[key] = count
	state:set(s)
	local label = tostring(name) .. (player_build and " player" or "") .. " #" .. count
	logger.info("event src=" .. tostring(src) .. " id=" .. tostring(id) .. " name=" .. label)
	local budget = player_build and main.BUILD_DUMP_LINES or main.EVENT_PARAM_LINES
	local started = os.clock and os.clock() or 0
	local ok, lines = pcall(probe.list, param, "param", main.EVENT_PARAM_DEPTH, nil, budget)
	if ok then log_lines("param of " .. label, lines) end
	-- Build proposals arrive as C++ userdata that pairs() cannot enumerate; probe known field names.
	local ok_f, field_lines = pcall(probe.fields, param, "param", 7, budget)
	if ok_f and #field_lines > 0 then log_lines("fields of " .. label, field_lines) end
	if player_build then main.dump_new_entities(_G, param[3], label) end
	if os.clock then
		logger.info("dump of " .. label .. " took " .. string.format("%.2f", os.clock() - started) .. " s")
	end
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global data().
function data()
	return main
end

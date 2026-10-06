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
main.PROBE_VERSION = 8
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
main.SUBSCRIBED_EVENTS = { "onPostBuildProposal", "mp_probe_replay" }

--- Replay test (phase 1, one PC). The copy is built this many metres beside the original so both
-- are visible; at most MAX_REPLAYS per game session, and builds arriving within REPLAY_QUIET_MS of
-- game time after a replay are not captured, so the copy does not trigger yet another copy.
main.REPLAY_SIDE_OFFSET = 40
main.MAX_REPLAYS = 3
main.REPLAY_QUIET_MS = 10000
main.replays_done = 0
main.quiet_until = -1

--- Run 7 showed that TF3 runs update() in rotating "Sim Pool" Lua states and handleEvent() in the
-- "Simulation Thread" state; module variables are not shared between them. Captures happen in
-- handleEvent, so the replay runs there too: update() only forwards the DLL's request as a script
-- event with this name.
main.REPLAY_EVENT = "mp_probe_replay"

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
-- A value "replay N" asks for a replay; N is remembered in the savegame state so that the next Sim
-- Pool state, which has its own last_bridge_in, does not act on the same request again.
function main.bridge_tick(env, seq, s)
	logger.info("bridge out seq=" .. seq)
	local getenv = env.os and env.os.getenv
	if not getenv then return end
	local ok, value = pcall(getenv, main.BRIDGE_ENV)
	if not ok then value = "ERR " .. tostring(value) end
	if value ~= last_bridge_in then
		logger.info("bridge in " .. main.BRIDGE_ENV .. "=" .. tostring(value))
		last_bridge_in = value
	end
	local request = type(value) == "string" and tonumber(string.match(value, "^replay (%d+)"))
	if request and s and request > (s.last_replay_request or 0) then
		s.last_replay_request = request
		main.request_replay(env, s)
	end
end

--- Argument lists tried for api.cmd.makeScriptingSendEventCmd; TF2's equivalent took
-- (fileName, id, name, param).
main.EVENT_ARGS = {
	function(name) return { "mp_probe", name, name, {} } end,
	function(name) return { name, name, {} } end,
	function(name) return { name, {} } end,
}

--- Asks the event state to replay. Falls back to replaying right here if no script event can be
-- sent, using the line the event state stored in the savegame state.
function main.request_replay(env, s)
	local api = env.api
	for i, make_args in ipairs(main.EVENT_ARGS) do
		local ok, err = pcall(function()
			local args = make_args(main.REPLAY_EVENT)
			api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd(args[1], args[2], args[3], args[4]))
		end)
		if ok then
			logger.info("replay requested as script event (signature " .. i .. ")")
			return
		end
		logger.info("replay event signature " .. i .. ": " .. tostring(err):sub(1, 200))
	end
	logger.info("replay: no script event possible, replaying in the update state")
	main.pending_replay = s and s.last_build
	main.replay_last(env)
end

function main.is_replay_event(src, id, name)
	return name == main.REPLAY_EVENT or id == main.REPLAY_EVENT or src == main.REPLAY_EVENT
end

--- Game time in milliseconds (200 per update), or nil if the engine is not reachable.
function main.game_time(env)
	local ok, t = pcall(function()
		local engine = env.api.engine
		return engine.getComponent(engine.util.getWorld(), env.api.type.ComponentType.GAME_TIME).gameTime
	end)
	return ok and t or nil
end

local function current_player(env)
	local ok, player = pcall(function() return env.api.engine.util.getPlayer() end)
	return ok and player or nil
end

--- Logs what the game reports after it executed a replayed build.
function main.log_replay_result(result, success, layout)
	logger.info("replay result (" .. tostring(layout) .. "): success=" .. tostring(success) ..
		" result=" .. type(result))
	local ok, lines = pcall(probe.fields, result, "res", 5, 80)
	if ok and #lines > 0 then log_lines("replay result fields", lines) end
end

--- Rebuilds the last captured build beside the original. Runs in the event state, where the
-- capture stored main.pending_replay.
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
	local now = main.game_time(env)
	if now then main.quiet_until = now + main.REPLAY_QUIET_MS end
	local data, err = build.deserialize(line)
	if not data then
		logger.info("replay: bad line (" .. tostring(err) .. ")")
		return
	end
	local dx, dy = build.side_offset(data, main.REPLAY_SIDE_OFFSET)
	build.offset(data, dx, dy)
	local player = current_player(env)
	logger.info(string.format("replay #%d: %d nodes, %d segments, moved by %.1f,%.1f, player %s",
		main.replays_done, #data.nodes, #data.segments, dx, dy, tostring(player)))
	local ok, message = build.replay(env, data, {
		log = function(attempt) logger.info("replay attempt " .. attempt) end,
		on_result = main.log_replay_result,
		player = player,
	})
	logger.info("replay: " .. (ok and "sent, " or "failed, ") .. message)
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
	if s.updates % main.BRIDGE_EVERY == 0 then
		local ok, err = pcall(main.bridge_tick, _G, s.updates / main.BRIDGE_EVERY, s)
		if not ok then logger.info("bridge tick failed: " .. tostring(err):sub(1, 200)) end
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
	if main.is_replay_event(src, id, name) then
		logger.info("replay event received (src=" .. tostring(src) .. " id=" .. tostring(id) .. ")")
		main.replay_last(_G)
		return
	end
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
		local now = main.game_time(_G)
		if now and now < main.quiet_until then
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

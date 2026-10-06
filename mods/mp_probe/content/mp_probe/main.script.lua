--- Phase-0 probe game script.
-- Once per savegame (per PROBE_VERSION) it logs the sandbox capabilities and the visible engine API,
-- then logs a simulation snapshot every SNAPSHOT_EVERY updates for the determinism test (the first
-- one with the error message of every field it could not read), and the first occurrence of every
-- event it receives. All output goes to stdout.txt with tag [mp_probe].
-- @module mp_probe.main
local logger = require("/mp_probe/logger.lua")
local probe = require("/mp_probe/probe.lua")
local build = require("/mp_probe/build.lua")
local world = require("/mp_probe/world.lua")

local main = {}

--- Bump to re-run the one-time probe in a savegame that already ran it.
main.PROBE_VERSION = 13
main.SNAPSHOT_EVERY = 300
--- Depth and line budget for the structure dump of the first event of each kind.
main.EVENT_PARAM_DEPTH = 7
main.EVENT_PARAM_LINES = 800
--- Number of player build proposals whose structure is dumped (each build looks different).
-- Town builds (playerEntity -1, nothing new for the player) are dumped once at most.
main.BUILD_DUMPS = 12

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
-- are visible; at most MAX_REPLAYS per savegame session. A build with as many segments as the copy
-- that arrives within REPLAY_QUIET_MS of game time after a replay is taken for the copy and not
-- captured, so the copy does not trigger yet another copy.
main.REPLAY_SIDE_OFFSET = 40
main.MAX_REPLAYS = 3
main.REPLAY_QUIET_MS = 10000

--- Line budget for the fields of a replay result. A filled proposal comes back in the result, and
-- its entries must not use up the budget before costs and errors are listed.
main.RESULT_DUMP_LINES = 120

--- Runs 7 and 8: module variables survive neither between update() calls (rotating "Sim Pool"
-- Lua states) nor between handleEvent() calls. Only the script state (state:get/set) persists, so
-- every value that one call needs from another lives there. update() sends the DLL's replay
-- request, together with the captured line, as a script event with this name; handleEvent()
-- builds the copy from the line in the event parameter.
main.REPLAY_EVENT = "mp_probe_replay"

--- Bridge test (phase 1). The sandbox has no io, so the TF2 file exchange is impossible. Candidate
-- channels: Lua -> DLL through tagged lines in stdout.txt (the DLL tails the log), DLL -> Lua through
-- the process environment (the DLL calls _putenv_s on the shared CRT, Lua reads os.getenv).
main.BRIDGE_EVERY = 50
main.BRIDGE_ENV = "TF3MP_IN"

--- Network transfer (phase 1, step 4). A build that can be rebuilt elsewhere is logged once more
-- behind SEND_MARKER; the DLL picks the line out of stdout.txt and sends it to the other game (or,
-- with mode=loopback, straight back to this one). A received line arrives in TF3MP_IN as
-- "line <token> <kind> <text>" and stays there until the mod logs RECEIVED_MARKER with the token.
-- kind "net" came from the other PC and is built in place; kind "loop" is the one-PC test and is
-- built REPLAY_SIDE_OFFSET metres beside the original.
main.SEND_MARKER = "net send "
main.RECEIVED_MARKER = "net received token="

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
		-- A received build line is long; its start is enough here.
		local text = tostring(value)
		if #text > 120 then text = text:sub(1, 120) .. "... (" .. #text .. " characters)" end
		logger.info("bridge in " .. main.BRIDGE_ENV .. "=" .. text)
		last_bridge_in = value
	end
	local request = type(value) == "string" and tonumber(string.match(value, "^replay (%d+)"))
	if request and s and request > (s.last_replay_request or 0) then
		s.last_replay_request = request
		main.request_replay(env, s, request)
	end
	if type(value) == "string" and s then main.receive_line(env, s, value) end
end

--- Handles a "line <token> <kind> <text>" value from the DLL. The DLL keeps the value until it sees
-- the acknowledgement in stdout.txt, so the same token can be read again by the next tick; it is
-- built only once (the token is kept in the savegame state) but acknowledged every time.
function main.receive_line(env, s, value)
	local token, kind, line = string.match(value, "^line (%S+) (%a+) (.+)$")
	if not token then return end
	logger.info(main.RECEIVED_MARKER .. token .. " kind=" .. kind .. " (" .. #line .. " characters)")
	if token == s.last_line_token then return end
	s.last_line_token = token
	local offset = kind == "loop" and main.REPLAY_SIDE_OFFSET or 0
	local param = { line = line, number = token, offset = offset, source = kind }
	if main.send_replay_event(env, param) then
		logger.info("line " .. token .. " (" .. kind .. ") handed to the event state")
		return
	end
	logger.info("line " .. token .. ": no script event possible, building in the update state")
	main.replay_line(env, line, token, nil, offset)
end

--- Argument lists tried for api.cmd.makeScriptingSendEventCmd; TF2's equivalent took
-- (fileName, id, name, param). Run 8: signature 1 works.
main.EVENT_ARGS = {
	function(name, param) return { "mp_probe", name, name, param } end,
	function(name, param) return { name, name, param } end,
	function(name, param) return { name, param } end,
}

--- Forwards a replay request with the line captured last (savegame state) to the event state.
-- Falls back to replaying right here if no script event can be sent.
function main.request_replay(env, s, request)
	local line = s.last_build
	if not line then
		logger.info("replay: no captured build in the script state yet")
		return
	end
	if (s.replays_requested or 0) >= main.MAX_REPLAYS then
		logger.info("replay: limit of " .. main.MAX_REPLAYS .. " reached")
		return
	end
	s.replays_requested = (s.replays_requested or 0) + 1
	local param = { line = line, request = request, number = s.replays_requested }
	local signature = main.send_replay_event(env, param)
	if signature then
		logger.info("replay #" .. param.number .. " requested as script event (signature " .. signature .. ", " ..
			#line .. " characters)")
		return
	end
	logger.info("replay: no script event possible, replaying in the update state")
	main.replay_line(env, line, param.number)
end

--- Sends param to handleEvent as a REPLAY_EVENT script event. Returns the signature number that
-- worked, or nil.
function main.send_replay_event(env, param)
	local api = env.api
	for i, make_args in ipairs(main.EVENT_ARGS) do
		local ok, err = pcall(function()
			local args = make_args(main.REPLAY_EVENT, param)
			api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd(args[1], args[2], args[3], args[4]))
		end)
		if ok then return i end
		logger.info("replay event signature " .. i .. ": " .. tostring(err):sub(1, 200))
	end
	return nil
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

--- Logs what the game reports after it executed a replayed build. Run 9: success=true alone means
-- nothing, so the verdict comes from the new entities and the costs (build.outcome).
function main.log_replay_result(result, success, label, outcome)
	outcome = outcome or build.outcome(result)
	local verdict = "UNKNOWN"
	if outcome.built == true then verdict = "BUILT" elseif outcome.built == false then verdict = "NOTHING BUILT" end
	logger.info("replay result (" .. tostring(label) .. "): " .. verdict .. ", success=" .. tostring(success) ..
		", costs " .. tostring(outcome.costs) .. ", new entities " .. tostring(outcome.entities) ..
		", critical " .. tostring(outcome.critical))
	for _, message in ipairs(outcome.messages) do logger.info("replay result " .. message) end
	local ok, lines = pcall(probe.fields, result, "res", 5, main.RESULT_DUMP_LINES)
	if ok and #lines > 0 then log_lines("replay result fields", lines) end
end

function main.count_keys(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

--- Lookups of existing things by position for build.resolve. The node index is built on first use.
function main.finder(env)
	local index = nil
	local function nodes()
		if not index then index = world.node_index(env) end
		return index
	end
	return {
		find_node = function(position) return world.find_node(nodes(), position) end,
		find_edge = function(a, b) return world.find_edge(env, a, b) end,
		find_construction = function(file, position) return world.find_construction(env, file, position) end,
	}
end

--- Rebuilds a captured line, by default REPLAY_SIDE_OFFSET metres beside the original.
-- @param number number|string which replay or received line this is (for the log)
-- @param state table|nil script state; when given, the quiet time for the copy's own build event
--   is stored there
-- @param distance number|nil side offset in metres; 0 builds in place (line from the other PC)
function main.replay_line(env, line, number, state, distance)
	if type(line) ~= "string" then
		logger.info("replay: no line in the request")
		return
	end
	local data, err = build.deserialize(line)
	if not data then
		logger.info("replay: bad line (" .. tostring(err) .. ")")
		return
	end
	local now = main.game_time(env)
	if state and now then
		local s = state:get() or {}
		s.quiet_until = now + main.REPLAY_QUIET_MS
		s.quiet_segments = #data.segments
		state:set(s)
	end
	distance = distance or main.REPLAY_SIDE_OFFSET
	-- The one-PC test always moves by the same vector (north), so a later build that joins or
	-- removes the first copy finds it again.
	local dx, dy = 0, distance
	if distance ~= 0 then build.offset(data, dx, dy) end
	local player = current_player(env)
	logger.info(string.format("replay #%s: %d nodes, %d segments, %d existing nodes, %d removed segments, " ..
		"%d constructions, %d demolished, moved by %.1f,%.1f, player %s", tostring(number), #data.nodes,
		#data.segments, main.count_keys(data.foreign), #data.removed_segments, #data.constructions,
		#data.demolished, dx, dy, tostring(player)))
	local ok_r, found, missing, notes = pcall(build.resolve, data, main.finder(env))
	if not ok_r then
		logger.info("replay: lookup failed (" .. tostring(found):sub(1, 200) .. ")")
		return
	end
	for _, note in ipairs(notes or {}) do logger.info("replay note: " .. note) end
	if not found then
		logger.info("replay SKIPPED: the build " .. tostring(missing))
		return
	end
	local ok, message = build.replay(env, data, {
		log = function(text) logger.info("replay " .. text) end,
		on_result = main.log_replay_result,
		-- What the game holds for the first segment just before sending, lanes included.
		inspect = function(label, _, edge_list)
			local ok_f, lines = pcall(probe.fields, edge_list[1], "edge[1]", 4, main.RESULT_DUMP_LINES)
			if ok_f and #lines > 0 then log_lines("replay proposal " .. label .. " edge[1]", lines) end
		end,
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

	if s.replay_version ~= main.PROBE_VERSION then
		-- A savegame from an older probe may have used up its replays already.
		s.replays_requested = 0
		s.replay_version = main.PROBE_VERSION
	end

	if s.constructions_scanned ~= main.PROBE_VERSION then
		local ok, list = pcall(world.player_constructions, _G)
		if ok then
			s.constructions = {}
			local n = 0
			for id, info in pairs(list) do
				s.constructions[tostring(id)] = info
				n = n + 1
			end
			logger.info("constructions of players found: " .. n)
		else
			logger.info("constructions scan failed: " .. tostring(list):sub(1, 200))
		end
		s.constructions_scanned = main.PROBE_VERSION
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
-- by a player). The game itself also builds (towns), with playerEntity -1. Runs 5-9: param[4] is
-- true for every player build and false for town builds, so it decides whenever it is set.
function main.is_player_build(param)
	local ok, result = pcall(function()
		if type(param[4]) == "boolean" then return param[4] end
		local ctx = param[1]
		if #ctx.proposal.addedSegments > 0 then return true end
		for i = 1, #ctx.toAdd do
			if ctx.toAdd[i].playerEntity ~= -1 then return true end
		end
		return false
	end)
	return ok and result
end

--- Number of road or track segments a build adds.
function main.segment_count(param)
	local ok, n = pcall(function() return #param[1].proposal.addedSegments end)
	return ok and type(n) == "number" and n or 0
end

--- Number of constructions (stations, depots, ...) a build adds. Run 9: a station arrived as 25
-- loose track nodes; such builds are not copied until constructions are transferred as a whole.
function main.construction_count(param)
	local ok, n = pcall(function() return #param[1].toAdd end)
	return ok and type(n) == "number" and n or 0
end

--- Short description of a build event for the log.
function main.describe_build(param)
	local function count(fn)
		local ok, n = pcall(fn)
		return ok and tostring(n) or "?"
	end
	return "segments=" .. count(function() return #param[1].proposal.addedSegments end) ..
		" nodes=" .. count(function() return #param[1].proposal.addedNodes end) ..
		" constructions=" .. count(function() return #param[1].toAdd end) ..
		" new entities=" .. count(function() return #param[3] end) ..
		" player build=" .. tostring(type(param) == "table" and param[4])
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
	local env = _G
	local cons = s.constructions or {}
	local ok, line, info = pcall(build.serialize, param[1].proposal, {
		node_position = function(id) return world.node_position(env, id) end,
		to_add = param[1].toAdd,
		to_remove = param[1].toRemove,
		construction = function(id) return cons[tostring(id)] end,
		read_transf = function(t)
			local m, how = build.read_transf(t)
			if m and s.transf_logged ~= main.PROBE_VERSION then
				logger.info("construction transf read as " .. how)
				s.transf_logged = main.PROBE_VERSION
			end
			return m, how
		end,
	})
	if not ok then
		logger.info("capture failed (" .. label .. "): " .. tostring(line))
		return
	end
	logger.info("capture " .. label .. " nodes=" .. info.nodes .. " segments=" .. info.segments ..
		" foreign_nodes=" .. info.foreign_nodes .. " removed_segments=" .. info.removed_segments ..
		" removed_nodes=" .. info.removed_nodes .. " constructions=" .. info.constructions ..
		" demolished=" .. info.demolished .. " edge_objects=" .. info.edge_objects)
	for _, what in ipairs(info.dropped) do logger.info("capture leaves out " .. what) end
	logger.info("capture line " .. line)
	if info.segments + info.removed_segments + info.constructions + info.demolished > 0 then
		s.last_build = line
		state:set(s)
		logger.info("capture stored for replay (" .. #line .. " characters)")
		logger.info(main.SEND_MARKER .. line)
	end
end

--- Keeps file and position of every construction in the script state, because a demolish event
-- only names the construction's id and arrives after it is gone. Fed from the ids each build
-- creates (also copies built for the other player) and once per savegame from a full scan.
function main.remember_constructions(env, s, param)
	s.constructions = s.constructions or {}
	pcall(function()
		local ids = param[3]
		for i = 1, #ids do
			-- Town buildings come through here too; only player constructions are kept.
			if world.is_player_owned(env, ids[i]) then
				local info = world.construction_info(env, ids[i])
				if info then s.constructions[tostring(ids[i])] = info end
			end
		end
	end)
	pcall(function()
		local removed = param[1].toRemove
		for i = 1, #removed do s.constructions[tostring(removed[i])] = nil end
	end)
end

function main.handleEvent(_user_params, state, src, id, name, param)
	if main.is_replay_event(src, id, name) then
		local line = type(param) == "table" and param.line or nil
		local number = type(param) == "table" and param.number or nil
		local distance = type(param) == "table" and tonumber(param.offset) or nil
		logger.info("replay event received (src=" .. tostring(src) .. " id=" .. tostring(id) .. ", line " ..
			(line and (#line .. " characters") or "missing") .. ")")
		if not line then
			-- The parameter did not come through; fall back to the script state.
			local s = state:get() or {}
			line = s.last_build
		end
		main.replay_line(_G, line, number, state, distance)
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
	if name == "onPostBuildProposal" then
		local now = main.game_time(_G)
		if now and now < (s.quiet_until or -1) and main.segment_count(param) == s.quiet_segments
			and main.construction_count(param) == 0 then
			-- Most likely the copy itself: it confirms the build independently of the result callback.
			-- Run 10: town buildings arrive in the quiet time too; they have constructions and no
			-- segments, so they no longer count.
			logger.info("build right after a replay (probably the copy, not captured): " .. main.describe_build(param))
		elseif player_build then
			main.capture_build(state, s, param, "player build")
		end
		-- After the capture, which still needs the demolished constructions.
		main.remember_constructions(_G, s, param)
		state:set(s)
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

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
local actions = require("/mp_probe/actions.lua")
local weld = require("/mp_probe/weld.lua")
local nodecfg = require("/mp_probe/nodecfg.lua")
local sync = require("/mp_probe/sync.lua")
local gui = require("/mp_probe/gui.lua")
local transport = require("/mp_probe/transport.lua")
local fingerprint = require("/mp_probe/fingerprint.lua")

local main = {}

--- Bump to re-run the one-time probe in a savegame that already ran it.
main.PROBE_VERSION = 32
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
main.REPLAY_SIDE_OFFSET = 100
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
--- v25: between bridge ticks, a received line waiting in TF3MP_IN or an action line waiting to go
-- out is handled every INBOX_EVERY updates (2 s of game time at 1x instead of 10 s), without the
-- "bridge out" marker in the log. DLL v9 offers a line as soon as it arrives; DLL v8 only on the
-- marker or after the previous line was acknowledged.
main.INBOX_EVERY = 1
main.BRIDGE_ENV = "TF3MP_IN"
--- Poll purchases/line edits more frequently than the full street graph.
main.ACTION_EVERY = 10
--- Dump every replay result (slow for stations, run 14).
main.DUMP_REPLAY_RESULTS = false
--- Action kinds polled by actions.lua (the rest comes from build events, format B5). v32: the
-- account, so a loan taken in either game reaches the other.
main.ACTION_KINDS = { "line", "vehicle", "account" }
--- v20: a copied construction's entrance is checked again this much game time after the copy,
-- in case the world was not up to date right after the command.
main.WELD_RECHECK_MS = 4000
--- Two PCs, 8 Oct: the host played paused, so game time stood still and a check due by game time
-- never came; update() still runs then (5 per second), so the check is also due after this many.
main.WELD_RECHECK_UPDATES = 20
--- How many staged steps (main.network_continue) one event runs at most while every command so far
-- has come back; the depot copy has five.
main.NETWORK_STEPS = 8
--- Line budget for the dump of a refresh proposal (weld.lua).
main.WELD_DUMP_LINES = 150
--- Depot builds of the player whose refresh proposal is dumped (the engine's own picture of a
-- welded entrance).
main.WELD_ORIGINAL_DUMPS = 2

--- Network transfer (phase 1, step 4). A build that can be rebuilt elsewhere is logged once more
-- behind SEND_MARKER; the DLL picks the line out of stdout.txt and sends it to the other game (or,
-- with mode=loopback, straight back to this one). A received line arrives in TF3MP_IN as
-- "line <token> <kind> <text>" and stays there until the mod logs RECEIVED_MARKER with the token.
-- kind "net" came from the other PC and is built in place; kind "loop" is the one-PC test and is
-- built REPLAY_SIDE_OFFSET metres beside the original.
main.SEND_MARKER = "net send "
--- Complete message limit. transport.lua chunks stdout and environment values to 6000 bytes;
-- the DLL uses 768-byte UDP fragments, independently of those bridge chunks.
main.MAX_LINE = transport.MAX_BYTES
main.RECEIVED_MARKER = "net received token="

--- v24: keeping the two games in step (sync.lua). The simulation records a checkpoint every
-- sync.CHECK_MS of game time and reads the other game's every SYNC_READ_EVERY updates. Without a
-- GUI script (no TF3MP_OWN_GUI from it after SYNC_FALLBACK_AFTER updates) the simulation keeps the
-- shared speed itself, which cannot lift a pause.
main.STATE_MARKER = "net state "
main.SYNC_READ_EVERY = 5
main.SYNC_FALLBACK_AFTER = 100
--- Updates after loading before the one-time description of the game's journal entries.
main.JOURNAL_TEST_AFTER = 25

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

--- True if a line from the other game waits in TF3MP_IN or an action line waits to go out.
function main.bridge_has_work(env, s)
	if actions.next_line_waiting(s) then return true end
	local getenv = env.os and env.os.getenv
	if not getenv then return false end
	local ok, value = pcall(getenv, main.BRIDGE_ENV)
	local token = ok and type(value) == "string" and value:match("^line (%S+) ")
	if ok and type(value) == "string" and value:match("^part ") then return true end
	return token ~= nil and token ~= s.last_line_token
end

--- Sends one numbered line towards the DLL and logs whatever the DLL put into the environment.
-- A value "replay N" asks for a replay; N is remembered in the savegame state so that the next Sim
-- Pool state, which has its own last_bridge_in, does not act on the same request again.
-- @param quiet boolean v25: a tick between bridge ticks, without the "bridge out" marker
function main.bridge_tick(env, seq, s, state, quiet)
	if not quiet then logger.info("bridge out seq=" .. seq) end
	local outgoing = s and actions.next_line(s)
	if outgoing then transport.send(outgoing, s, logger.info) end
	if state then main.store(state, s) end
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
	if type(value) == "string" and s then main.receive_line(env, s, value, state) end
end

--- Handles a "line <token> <kind> <text>" value from the DLL. The DLL keeps the value until it sees
-- the acknowledgement in stdout.txt, so the same token can be read again by the next tick; it is
-- built only once (the token is kept in the savegame state) but acknowledged every time.
function main.receive_line(env, s, value, state)
	value = transport.receive(s, value, logger.info)
	if state then main.store(state, s) end
	if not value then return end
	local token, kind, line = string.match(value, "^line (%S+) (%a+) (.+)$")
	if not token then return end
	logger.info(main.RECEIVED_MARKER .. token .. " kind=" .. kind .. " (" .. #line .. " characters)")
	if token == s.last_line_token then
		if s.network_done and s.network_done.token == token then
			logger.info("net result " .. token .. " " .. s.network_done.result)
		end
		return
	end
	s.last_line_token = token
	if state then main.store(state, s) end
	local offset = kind == "loop" and main.REPLAY_SIDE_OFFSET or 0
	local param = { line = line, number = token, offset = offset, source = kind }
	if main.send_replay_event(env, param) then
		logger.info("line " .. token .. " (" .. kind .. ") handed to the event state")
		return
	end
	logger.info("line " .. token .. ": no script event possible, building in the update state")
	if state then
		transport.begin(state, token)
		transport.fail(state, "simulation event unavailable; no build executed")
		transport.dispatched(state); transport.check(state, logger.info)
		return
	end
	main.replay_line(env, line, token, state, offset)
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
		", critical " .. tostring(outcome.critical) ..
		(outcome.removed and (", confirmed removals " .. tostring(outcome.removed)) or ""))
	if outcome.removal_error then logger.info("replay removal check: " .. outcome.removal_error) end
	for _, message in ipairs(outcome.messages) do logger.info("replay result " .. message) end
	-- Run 14: walking the result of a station copy stalled the game for 23 s, so it is off.
	if main.DUMP_REPLAY_RESULTS then
		local ok, lines = pcall(probe.fields, result, "res", 5, main.RESULT_DUMP_LINES)
		if ok and #lines > 0 then log_lines("replay result fields", lines) end
	end
end

--- Readable text of an error value. Run 17: a failed vehicle purchase raised a table.
function main.error_text(err)
	if type(err) ~= "table" then return tostring(err) end
	local parts = {}
	for k, v in pairs(err) do
		local text = type(v) == "table" and main.error_text(v) or tostring(v)
		parts[#parts + 1] = tostring(k) .. "=" .. text
		if #parts >= 12 then break end
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
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
		edge_objects_of = function(edge) return world.edge_objects_of(env, edge) end,
		edge_construction = function(edge) return world.edge_construction(env, edge) end,
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
		return false, "missing replay line"
	end
	if line:sub(1, 3) == "W1 " then return main.world_receive(env, line, state) end
	if line:sub(1, 1) == "A" then
		local action, err = actions.decode(line)
		if not action then logger.info("action replay: bad line (" .. tostring(err) .. ")"); return false, err end
		local peer = tostring(number):match("^([^.]+)")
		local ok, result = pcall(actions.receive, state, action, peer, distance or main.REPLAY_SIDE_OFFSET)
		if not ok then logger.info("action replay failed: " .. tostring(result):sub(1, 240)) end
		return ok, result
	end
	local data, err = build.deserialize(line)
	if not data then
		logger.info("replay: bad line (" .. tostring(err) .. ")")
		return false, err
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
		"%d constructions, %d demolished, %d node configs, moved by %.1f,%.1f, player %s", tostring(number),
		#data.nodes, #data.segments, main.count_keys(data.foreign), #data.removed_segments, #data.constructions,
		#data.demolished, #data.configs, dx, dy, tostring(player)))
	local has_gates = next(data.gates or {}) ~= nil and #data.constructions > 0
	if has_gates then
		-- Run 20b: the copied construction lays its own entrance, and the copied entrance street
		-- came on top of it as a second one ending in a second node on the gate. v21 leaves the
		-- street out; weld.lua checks that the construction's own entrance meets the road.
		data.gate_positions = weld.gate_positions(data)
		local before = #data.segments
		build.drop_access(data)
		logger.info(string.format("replay: %d entrance segment(s) left out, the construction lays its own",
			before - #data.segments))
	end
	local configs_only = #data.nodes == 0 and #data.segments == 0 and #data.removed_segments == 0 and
		#data.removed_nodes == 0 and #data.constructions == 0 and #data.demolished == 0 and #data.configs > 0
	if configs_only then
		logger.info("replay #" .. tostring(number) .. ": only node configurations (" .. #data.configs .. ")")
		main.apply_node_configs(env, data, player)
		if state and (state:get() or {}).network_work then
			local live = state:get() or {}; live.network_followup = { phase = "verify", data = data }
			state:set(live)
		end
		return true
	end
	local ok_r, found, missing, notes = pcall(build.resolve, data, main.finder(env))
	if not ok_r then
		logger.info("replay: lookup failed (" .. tostring(found):sub(1, 200) .. ")")
		return false, found
	end
	for _, note in ipairs(notes or {}) do logger.info("replay note: " .. note) end
	if #(data.objects or {}) > 0 or #(data.objects_to_remove or {}) > 0 then
		local kept = 0
		for _, o in ipairs(data.objects) do if o.entity then kept = kept + 1 end end
		logger.info(string.format("replay stops/signals: %d sent, %d already here, %d to add, %d to remove",
			#data.objects, kept, #data.objects - kept, #(data.objects_to_remove or {})))
	end
	if not found then
		logger.info("replay SKIPPED: the build " .. tostring(missing))
		return false, missing
	end
	local ok_k, cleared = pcall(main.configs_to_clear, env, data)
	data.configs_to_remove = ok_k and cleared or {}
	if not ok_k then logger.info("replay: node configurations to clear unreadable (" .. tostring(cleared):sub(1, 120) .. ")") end
	if #data.configs_to_remove > 0 then
		local ids = {}
		for i, id in ipairs(data.configs_to_remove) do ids[i] = tostring(id) end
		logger.info(string.format("replay: %d old node configuration(s) cleared in the build (nodes %s)",
			#data.configs_to_remove, table.concat(ids, ",")))
	end
	local street_work = #data.segments + #data.removed_segments + #data.removed_nodes
	if has_gates and street_work > 0 and #data.demolished == 0 then
		return main.replay_in_steps(env, data, state, player)
	end
	local ok, message = build.replay(env, data, main.replay_options(player, has_gates, state))
	logger.info("replay: " .. (ok and "sent, " or "failed, ") .. message)
	if ok and state and (state:get() or {}).network_work then
		local live = state:get() or {}
		live.network_followup = { phase = "finish", data = data, gates = has_gates, player = player }
		state:set(live)
		return ok, message
	end
	if ok and data.native_replacement then
		if has_gates and state then main.check_replacement_later(env, data, state) end
		return ok, message
	end
	if ok and has_gates then main.weld_copy(env, data, state, player) end
	if ok then main.apply_node_configs(env, data, player) end
	return ok, message
end

--- Options for build.replay of a received line.
-- @param describe boolean v20: log what the game made of a copy with an entrance before it is sent
function main.replay_options(player, describe, state)
	local described = false
	return {
		log = function(text) logger.info("replay " .. text) end,
		on_result = main.log_replay_result,
		on_rejected = function(message) transport.fail(state, message) end,
		-- What the game holds for the first segment just before sending, lanes included.
		inspect = function(label, _, edge_list)
			local ok_f, lines = pcall(probe.fields, edge_list[1], "edge[1]", 4, main.RESULT_DUMP_LINES)
			if ok_f and #lines > 0 then log_lines("replay proposal " .. label .. " edge[1]", lines) end
		end,
		prepare = describe and function(cmd)
			if described then return end
			described = true
			logger.info("weld command before sending: " .. weld.describe_command(cmd))
		end or nil,
		player = player,
	}
end

--- v22: a construction whose entrance joins a street the same build split or changed. Run 21: with
-- the copied entrance left out, the street split and the construction in one SimpleProposal made
-- the game assert (map_util Get, then StreetShapeFactory PrepareTransitions '!cc.empty()') and
-- nothing was built. The build tool hands the entrance to the construction in ways a SimpleProposal
-- cannot, so the copy goes in steps: the streets and their node configurations, the construction
-- alone, the entrance check with the engine's refresh (run 20b: it lays the entrance from the gate
-- to the road node; that time our copied entrance was in its way), then all node configurations
-- again, now that the entrance they name exists.
function main.replay_in_steps(env, data, state, player)
	local streets, constructions = build.split_constructions(data)
	logger.info(string.format("replay in steps: streets first (%d nodes, %d segments, %d removed segments, " ..
		"%d removed nodes), then %d construction(s)", #streets.nodes, #streets.segments,
		#streets.removed_segments, #streets.removed_nodes, #constructions.constructions))
	local ok_s, message_s = build.replay(env, streets, main.replay_options(player, false, state))
	logger.info("replay streets: " .. (ok_s and "sent, " or "failed, ") .. message_s)
	if not ok_s then return false, message_s end
	if state and (state:get() or {}).network_work then
		local live = state:get() or {}
		live.network_followup = { phase = "street_configs", data = constructions, streets = streets, player = player, gates = true }
		state:set(live)
		return true, message_s
	end
	if ok_s then main.apply_node_configs(env, streets, player) end
	local ok_c, message_c = build.replay(env, constructions, main.replay_options(player, true, state))
	logger.info("replay construction: " .. (ok_c and "sent, " or "failed, ") .. message_c)
	if ok_c then main.weld_copy(env, constructions, state, player) end
	-- Run 22: setting the configurations once more after the refresh made the game assert
	-- (TransportNetworkSystem EntityToBeRemoved) and left a street without its transport network,
	-- which crashed the game a few seconds later. The refresh sets the junction's and the gate's
	-- configurations itself, the others were set after the streets.
	if ok_c then logger.info("replay: node configurations at the entrance are left to the game") end
	return ok_c, message_c
end

-- Continue staged builds only after all callbacks of the earlier stage have returned.
function main.network_continue(env, state)
	local live = state:get() or {}; local follow = live.network_followup
	if live.network_work and live.network_work.error then return end
	if not follow then return end
	follow.requested = nil
	if live.network_work and (live.network_work.pending or 0) > 0 then
		-- A request that crossed a command still outstanding; update() asks again once it is back.
		state:set(live)
		return
	end
	logger.info("net step " .. tostring(live.network_work and live.network_work.token) .. ": " .. tostring(follow.phase))
	if follow.phase == "street_configs" then
		main.apply_node_configs(env, follow.streets, follow.player)
		follow.phase = "street_verify"
	elseif follow.phase == "street_verify" then
		main.verify_node_configs(env, follow.streets, state)
		follow.phase = "construction"; follow.streets = nil
	elseif follow.phase == "construction" then
		local ok, err = build.replay(env, follow.data, main.replay_options(follow.player, true, state))
		if not ok then transport.fail(state, err) end
		follow.phase = "finish"
	elseif follow.phase == "finish" then
		if follow.data.native_replacement then
			-- The engine's replacement proposal owns the complete station graph, including
			-- snapping and node configurations. Do not rebuild or overwrite it afterwards.
			logger.info("replay replacement: connections and node configurations supplied by the engine")
			if follow.gates then main.check_replacement_later(env, follow.data, state) end
		else
			if follow.gates then main.weld_copy(env, follow.data, state, follow.player) end
			main.apply_node_configs(env, follow.data, follow.player)
		end
		follow.phase = "verify"
	else
		main.verify_node_configs(env, follow.data, state)
		follow = nil
	end
	live = state:get() or {}; live.network_followup = follow; state:set(live)
end

--- Two PCs, 8 Oct (runs 32 and 33): the copy of a depot stopped for good after the depot itself was
-- built; the next step, which joins its entrance to the road, never ran, so neither PC confirmed the
-- other's action. Each step waited for update() to see the step before it finished and to send the
-- next event, and that hand-over between the Lua states got lost. TF3 calls the build callbacks
-- before sendCommand returns (runs 9, 23, 30), so the steps now run right here, one after another,
-- as v22 to v26 did in one event (runs 23 and 24); only a callback still outstanding leaves the
-- rest to update() and the next event.
function main.network_run(env, state)
	for _ = 1, main.NETWORK_STEPS do
		local live = state:get() or {}
		local work = live.network_work
		if not live.network_followup or not work or work.error or (work.pending or 0) > 0 then return end
		main.network_continue(env, state)
	end
end

-- Verify native replacements with the existing delayed, read-only connection check.
function main.check_replacement_later(env, data, state)
	local now = main.game_time(env)
	if not now then transport.fail(state, "replacement connection check has no game time"); return end
	local live = state:get() or {}
	live.weld_checks = live.weld_checks or {}
	for _, c in ipairs(data.constructions or {}) do
		live.weld_checks[#live.weld_checks + 1] = {
			file = c.file, position = { x = c.transf[13], y = c.transf[14], z = c.transf[15] },
			gates = data.gate_positions or {}, due = now + main.WELD_RECHECK_MS,
		}
	end
	state:set(live)
end

function main.verify_node_configs(env, data, state)
	local total = #(data.configs or {})
	if total == 0 then return end
	local resolved, _, skipped = nodecfg.resolve(env, data, world.node_index(env))
	if #resolved + (skipped or 0) < total then transport.fail(state, "node configurations could not all be resolved"); return end
	for _, entry in ipairs(resolved) do
		if not world.node_construction(env, entry.node) and not world.has_node_config(env, entry.node) then
			transport.fail(state, "node configuration missing after execution: " .. tostring(entry.node))
			return
		end
	end
end

--- v23 (run 22): existing nodes whose configuration the build makes wrong: ends of removed
-- segments and existing ends of new segments (not at a construction's entrance) that have a
-- configuration, unless the build removes the node. Run 22: removing a segment that the configuration of its end node still named made the
-- game assert (map_util Get); the player's own build clears such configurations in the same proposal.
function main.configs_to_clear(env, data)
	local candidates, order = {}, {}
	local function add(node, dangling)
		if type(node) == "number" and node >= 0 and not candidates[node] then
			-- A node at a construction's entrance keeps its configuration unless it would name a
			-- removed segment (run 22: the game manages those itself).
			if not dangling and world.node_construction(env, node) then return end
			candidates[node] = true
			order[#order + 1] = node
		end
	end
	for _, r in ipairs(data.removed_segments or {}) do
		if r.entity then
			local a, b = world.edge_nodes(env, r.entity)
			add(a, true)
			add(b, true)
		end
	end
	for _, seg in ipairs(data.segments or {}) do
		add(seg.node0, false)
		add(seg.node1, false)
	end
	local removed = {}
	for _, n in ipairs(data.removed_nodes or {}) do
		if n.entity then removed[n.entity] = true end
	end
	local out = {}
	for _, node in ipairs(order) do
		if not removed[node] and world.has_node_config(env, node) then out[#out + 1] = node end
	end
	return out
end

--- v21: gives the copy's nodes the lane connections the original got (nodecfg.lua).
function main.apply_node_configs(env, data, player)
	if #(data.configs or {}) == 0 then return end
	local ok, err = pcall(nodecfg.apply, env, data, {
		log = function(text) logger.info(text) end,
		player = player,
	})
	if not ok then logger.info("node configs failed: " .. tostring(err):sub(1, 200)) end
end

--- v20: checks the entrance of a copied construction and tries to weld it (weld.lua); remembers
-- it for one more check a little later.
function main.weld_copy(env, data, state, player)
	local ok, checked = pcall(weld.repair, env, data, {
		log = function(text) logger.info(text) end,
		player = player,
		on_result = main.log_replay_result,
		dump = main.dump_value,
	})
	if not ok then
		transport.fail(state, "weld failed: " .. tostring(checked))
		logger.info("weld failed: " .. tostring(checked):sub(1, 200))
		return
	end
	local now = main.game_time(env)
	if state and now and #checked > 0 then
		local s = state:get() or {}
		s.weld_checks = s.weld_checks or {}
		for _, c in ipairs(checked) do
			c.due = now + main.WELD_RECHECK_MS
			s.weld_checks[#s.weld_checks + 1] = c
		end
		state:set(s)
	end
end

--- The later check of main.weld_copy, from update().
-- @param fail function|nil receives the reason when an entrance is not confirmed (transport.fail
--   on the live state; update()'s own copy of the receipt is never written back)
function main.recheck_welds(env, s, fail)
	fail = fail or function() end
	local now = main.game_time(env)
	if not now or not s.weld_checks or #s.weld_checks == 0 then return end
	local waiting = {}
	for _, c in ipairs(s.weld_checks) do
		c.updates = (c.updates or 0) + 1
		if now >= (c.due or 0) or c.updates >= main.WELD_RECHECK_UPDATES then
			local id = world.find_construction(env, c.file, c.position)
			if id then
				local status = weld.status(env, id, c.gates or {})
				logger.info("weld check later: " .. status.text)
				if status.welded ~= true then fail("construction entrance not confirmed: " .. status.text) end
			else
				logger.info("weld check later: the copied construction is gone")
				fail("copied construction missing after build")
			end
		else
			waiting[#waiting + 1] = c
		end
	end
	s.weld_checks = waiting
end

--- Writes update()'s copy of the script state, keeping the execution receipt as it is now. Only
-- the event state, the command callbacks and the transport functions (each reads, changes and
-- writes the live state at once) change the receipt; update()'s copy is older (two PCs, 8 Oct).
-- bdc8cd3 instead put back the live receipt on every write through update()'s state, also on
-- transport.check's own write from update(), so a confirmed action stayed open for good and every
-- later action from the other PC waited behind it (run 34: "1 Vorgang wartet").
function main.store(state, s)
	local live = state:get() or {}
	s.network_work, s.network_done, s.network_followup = live.network_work, live.network_done, live.network_followup
	state:set(s)
end

--- Once per bridge tick while a received action is not confirmed yet: what it still waits for, so a
-- stuck one can be told apart in the log (runs 32 and 33 showed nothing at all).
function main.log_network_wait(s)
	local w = s.network_work
	if not w or (s.updates or 0) % main.BRIDGE_EVERY ~= 0 then return end
	local f = s.network_followup
	logger.info(string.format("net waiting %s: step %s%s, %d command(s) outstanding, %d entrance check(s), " ..
		"%d action step(s)%s%s", tostring(w.token), f and tostring(f.phase) or "-", f and f.requested and " (requested)" or "",
		w.pending or 0, #(s.weld_checks or {}), #(s.action_work or {}), w.dispatched and "" or ", not dispatched",
		w.error and (", error " .. tostring(w.error):sub(1, 120)) or ""))
end

function main.update(_user_params, state, _dt)
	local s = state:get() or {}
	-- Reset observation baseline on upgrade; never send an existing save as new actions.
	if s.actions_version ~= main.PROBE_VERSION then
		s.actions = nil
		s.actions_version = main.PROBE_VERSION
	end
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
	if s.weld_checks and #s.weld_checks > 0 then
		local ok, err = pcall(main.recheck_welds, _G, s, function(text) transport.fail(state, text) end)
		if not ok then
			s.weld_checks = nil
			transport.fail(state, "construction entrance check unreadable: " .. tostring(err):sub(1, 180))
			logger.info("weld check later failed: " .. tostring(err):sub(1, 200))
		end
	end
	if (not s.actions or s.updates % main.ACTION_EVERY == 0) and not s.action_busy
		and not (s.action_work and #s.action_work > 0) then
		-- Roads, buildings and demolition travel as B5 lines from the build events; the polled
		-- actions only add lines and vehicles, so nothing is copied twice.
		local kinds = main.ACTION_KINDS
		local ok, err = pcall(actions.poll, _G, s, function(text) logger.info(text) end, kinds)
		if not ok then logger.info("action poll failed: " .. tostring(err):sub(1, 220)) end
	end
	local bridge_now = s.updates % main.BRIDGE_EVERY == 0
	if bridge_now or (s.updates % main.INBOX_EVERY == 0 and main.bridge_has_work(_G, s)) then
		-- Store the baseline before dispatching an event that can update replay mappings.
		main.store(state, s)
		local ok, err = pcall(main.bridge_tick, _G, s.updates / main.BRIDGE_EVERY, s, state, not bridge_now)
		if not ok then logger.info("bridge tick failed: " .. tostring(err):sub(1, 200)) end
		-- An immediate event/callback may already have refreshed parts of the baseline.
		local live = state:get() or s
		s.actions, s.action_entities = live.actions, live.action_entities
		s.action_inbox, s.action_work, s.action_busy = live.action_inbox, live.action_work, live.action_busy
		s.action_work_requested = live.action_work_requested
		s.network_work, s.network_done = live.network_work, live.network_done
		s.network_followup = live.network_followup
		-- A replay handled right away also leaves its quiet time and weld checks there (v20).
		s.quiet_until, s.quiet_segments, s.weld_checks = live.quiet_until, live.quiet_segments, live.weld_checks
	end
	local ok_sync, err_sync = pcall(main.sync_tick, _G, s)
	if not ok_sync then logger.info("sync failed: " .. main.error_text(err_sync):sub(1, 240)) end
	local ok_fix, err_fix = pcall(main.sync_send_fix, _G, state, s)
	if not ok_fix then logger.info("sync correction failed: " .. main.error_text(err_fix):sub(1, 240)) end
	if s.updates % main.SNAPSHOT_EVERY == 0 then
		local snap = probe.snapshot(_G)
		if s.snapshot_errors_logged ~= main.PROBE_VERSION then
			log_lines("snapshot errors", probe.format_errors(snap))
			s.snapshot_errors_logged = main.PROBE_VERSION
		end
		logger.info("snapshot update=" .. s.updates .. " " .. probe.format_snapshot(snap))
	end
	main.store(state, s)
	local live = state:get() or {}
	local follow, work = live.network_followup, live.network_work
	if follow and work and not work.error and (work.pending or 0) == 0 and not follow.requested then
		follow.requested = true; state:set(live)
		if not main.send_replay_event(_G, { network_continue = true }) then
			transport.fail(state, "build continuation event unavailable")
		end
	end
	transport.check(state, logger.info)
	s = state:get() or s
	main.log_network_wait(s)
	if actions.has_work(s) and not s.action_work_requested then
		s.action_work_requested = true
		state:set(s)
		if not main.send_replay_event(_G, { action_work = true }) then
			local live = state:get() or s
			live.action_work_requested = false
			state:set(live)
			logger.info("action continuation: simulation event unavailable; work remains queued")
		end
	end
end

--- The simulation side of keeping the games in step (sync.lua), once per update.
function main.sync_tick(env, s)
	local getenv = env.os and env.os.getenv
	if not getenv then return end
	local role = sync.role(getenv)
	if not role then return end
	local gt = main.game_time(env)
	if not gt then return end
	local ss = s.sync
	-- A savegame loaded again in the same game goes back in time; its checkpoints start over.
	if type(ss) ~= "table" or ss.version ~= main.PROBE_VERSION or (ss.gt and gt < ss.gt) then
		ss = { version = main.PROBE_VERSION, ticks = 0 }
		s.sync = ss
		logger.info("sync: this game is the " .. role .. (role == "host" and ", its money and date count" or ""))
	end
	ss.gt, ss.ticks = gt, ss.ticks + 1
	if s.journal_test ~= main.PROBE_VERSION and ss.ticks >= main.JOURNAL_TEST_AFTER then
		s.journal_test = main.PROBE_VERSION
		main.journal_test(env)
	end
	if role ~= "host" and role ~= "client" then return end
	if sync.at_checkpoint(gt) then
		local k = sync.checkpoint_of(gt)
		if k ~= ss.own_k then
			local values, failed = sync.values(env, gt)
			values.ck = k
			-- Money this game booked to follow the host (the simulated host in tools\fake-partner.ps1
			-- needs it to keep its own difference).
			if role == "client" then values.adj = ss.adj or 0 end
			ss.own, ss.own_k = sync.keep(ss.own, k, values), k
			if #failed > 0 and ss.failed_logged ~= table.concat(failed, ",") then
				ss.failed_logged = table.concat(failed, ",")
				logger.info("sync: checkpoint values unreadable: " .. ss.failed_logged)
			end
			logger.info(main.STATE_MARKER .. "sim " .. sync.encode(values))
		end
	end
	if ss.ticks % main.SYNC_READ_EVERY == 0 then
		local raw = getenv("TF3MP_PEER_SIM") or ""
		if raw ~= ss.peer_raw then
			ss.peer_raw = raw
			local v = sync.decode(raw)
			if v and tonumber(v.ck) then ss.peer = sync.keep(ss.peer, tonumber(v.ck), v) end
		end
		main.sync_compare(env, ss, role, gt)
	end
	main.sync_speed_fallback(env, ss, role, gt, getenv)
end

--- Compares every checkpoint both games have and that was not compared yet.
function main.sync_compare(env, ss, role, gt)
	for _, p in ipairs(ss.peer or {}) do
		if p.k > (ss.compared_k or -1) then
			local own = sync.find(ss.own, p.k)
			if own then
				ss.compared_k = p.k
				local out = sync.compare(ss, p.k, own, p.v, role, ss.own_k)
				local fields = {}
				for field in pairs(out.diffs) do fields[#fields + 1] = field end
				table.sort(fields)
				logger.info(string.format("sync check %d (%s): %s", p.k, tostring(own.date),
					#fields == 0 and "same" or ("differs in " .. table.concat(fields, ", "))))
				for _, note in ipairs(out.notes) do logger.info("sync: " .. note) end
				for _, warning in ipairs(out.warnings) do logger.info("sync WARNING: the games differ: " .. warning) end
				local world_status = out.world_mismatch and "diff" or (out.world_different or 0) > 0 and "checking"
					or (out.world_fields or 0) == #(sync.HASH_FIELDS or {}) and (out.world_fields or 0) > 0 and "same" or "unknown"
				local world_fields = {}
				for _, field in ipairs(sync.HASH_FIELDS or {}) do
					if out.diffs[field] then world_fields[#world_fields + 1] = field end
				end
				logger.info(main.STATE_MARKER .. "health ck=" .. p.k .. " status=" .. world_status ..
					" fields=" .. (#world_fields > 0 and table.concat(world_fields, ",") or "none"))
				if world_status == "diff" then
					local ok_w, err_w = pcall(main.world_send, env, ss, own, world_fields)
					if not ok_w then logger.info("world list failed: " .. tostring(err_w):sub(1, 200)) end
				end
				main.sync_correct(ss, out.fix, gt)
			elseif ss.own_k and ss.own_k > p.k then
				-- This game has no checkpoint with that number (loaded later); it is skipped.
				ss.compared_k = p.k
			end
		end
	end
end

--- Run 34 (two PCs): both launchers said "Weltabweichung (hcon,hedge)", but the log only had the
-- two digests, not which buildings or roads differ. Once a difference is confirmed, each game sends
-- the other its records of that category (W1 lines: hash and a readable description each); the
-- receiver logs which records only it has and which only the other game has (main.world_receive),
-- so one log names both sides. Sent once per category and own digest.
main.WORLD_PART_BYTES = 5800

function main.world_send(env, ss, own, fields)
	ss.world_sent = ss.world_sent or {}
	for _, field in ipairs(fields) do
		local digest = own[field]
		local kind
		for k, f in pairs(fingerprint.FIELDS) do if f == field then kind = k end end
		if kind and digest and ss.world_sent[field] ~= digest then
			ss.world_sent[field] = digest
			local list = fingerprint.list(env, kind)
			local parts, current = {}, {}
			local size = 0
			for _, r in ipairs(list) do
				local item = r.h .. ":" .. build.escape(r.d)
				if size + #item + 1 > main.WORLD_PART_BYTES and #current > 0 then
					parts[#parts + 1] = current; current, size = {}, 0
				end
				current[#current + 1] = item; size = size + #item + 1
			end
			parts[#parts + 1] = current
			for i, items in ipairs(parts) do
				transport.send(string.format("W1 %s %d %d %s %d %s", field, i, #parts, tostring(digest), #list,
					#items > 0 and table.concat(items, " ") or "-"), {}, logger.info)
			end
			logger.info(string.format("world list %s: %d records sent to the other game in %d part(s)", field, #list, #parts))
		end
	end
end

--- Handles a W1 line from the other game (main.world_send): logs the records that differ.
function main.world_receive(env, line, state)
	local field, index, count, digest, total, rest = line:match("^W1 (%a+) (%d+) (%d+) (%S+) (%d+) (.*)$")
	if not field then logger.info("world list: bad line"); return true end
	index, count = tonumber(index), tonumber(count)
	local kind
	for k, f in pairs(fingerprint.FIELDS) do if f == field then kind = k end end
	if not kind then logger.info("world list: unknown category " .. field); return true end
	local own = fingerprint.list(env, kind)
	local here = {}
	for _, r in ipairs(own) do here[r.h] = r.d end
	local s = state and (state:get() or {}) or {}
	s.world_rx = s.world_rx or {}
	local rx = s.world_rx[field]
	if not rx or rx.digest ~= digest or rx.count ~= count then
		rx = { digest = digest, count = count, got = 0, there = 0, hashes = {} }
		s.world_rx[field] = rx
	end
	rx.got = rx.got + 1
	for item in rest:gmatch("%S+") do
		local h, d = item:match("^([^:]+):(.*)$")
		if h then
			rx.hashes[h] = true
			if not here[h] then
				rx.there = rx.there + 1
				logger.info("world diff " .. field .. " only in the other game: " .. build.unescape(d))
			end
		end
	end
	if rx.got >= count then
		local only_here = 0
		for _, r in ipairs(own) do
			if not rx.hashes[r.h] then
				only_here = only_here + 1
				logger.info("world diff " .. field .. " only in this game: " .. r.d)
			end
		end
		logger.info(string.format("world diff %s: %d only here, %d only in the other game (there %s records, here %d)",
			field, only_here, rx.there, total, #own))
		s.world_rx[field] = nil
	end
	if state then state:set(s) end
	return true
end

--- Client: takes over the host's loan, money and date. Run 25: in update() the game refuses commands
-- with a result callback ("Callbacks are currently disallowed"), so the corrections wait in
-- ss.pending_fix; main.sync_send_fix sends them as a script event and handleEvent books them
-- (main.sync_apply), like a replayed build.
function main.sync_correct(ss, fix, gt)
	if not (fix.loan or fix.money or fix.date) then return end
	if fix.loan then logger.info("sync: loan differs by " .. fix.loan .. " from the host's, booking it") end
	if fix.money then logger.info("sync: money differs by " .. fix.money .. " from the host's, booking it") end
	if fix.date then logger.info("sync: date differs by " .. fix.date .. " day(s) from the host's, moving it") end
	ss.pending_fix = { loan = fix.loan, money = fix.money, date = fix.date, gt = gt }
end

--- Stops correcting a field after a correction that could not be made.
function main.sync_give_up(ss, field)
	ss.off = ss.off or {}
	ss.off[field] = true
	if ss.fixes then ss.fixes[field] = nil end
end

--- update(): sends the waiting corrections to handleEvent.
function main.sync_send_fix(env, state, s)
	local ss = s.sync
	local fix = type(ss) == "table" and ss.pending_fix
	if not fix then return end
	ss.pending_fix = nil
	-- Stored before dispatching: the game can handle the event right away and note the result.
	main.store(state, s)
	-- Flat, only numbers and a flag, like the other event parameters that are known to arrive.
	local sent = main.send_replay_event(env, { sync_fix = true, fix_loan = fix.loan, fix_money = fix.money,
		fix_date = fix.date, fix_gt = fix.gt })
	local live = state:get() or s
	if type(live.sync) == "table" then
		s.sync = live.sync
		ss = live.sync
	end
	if not sent then
		for _, field in ipairs({ "loan", "money", "date" }) do
			if fix[field] then
				main.sync_give_up(ss, field)
				logger.info("sync: the " .. field .. " correction could not be sent; " .. field .. " is no longer corrected")
			end
		end
	end
end

--- handleEvent: makes the corrections. Commands may report their result here.
-- @param fix table the event parameter: fix_loan, fix_money, fix_date (days), fix_gt
function main.sync_apply(env, state, fix)
	local function settle(field, amount, success)
		local live = state:get() or {}
		local ss = live.sync
		if type(ss) ~= "table" then return end
		if success == false then
			main.sync_give_up(ss, field)
		elseif field == "money" then
			ss.adj = (ss.adj or 0) + amount
		end
		state:set(live)
	end
	local function correct(field, label, send)
		local amount = tonumber(fix["fix_" .. field])
		if not amount then return end
		local ok, sent, notes = pcall(send, amount, function(_, success)
			logger.info("sync: " .. label .. " " .. amount .. ", success=" .. tostring(success) ..
				(success == false and ("; " .. field .. " is no longer corrected") or ""))
			local ok_s, err_s = pcall(settle, field, amount, success)
			if not ok_s then logger.info("sync: noting the " .. field .. " correction failed: " .. main.error_text(err_s):sub(1, 200)) end
		end)
		if ok and sent then
			logger.info("sync: " .. field .. " correction sent (" .. tostring(notes) .. ")")
		else
			logger.info("sync: " .. field .. " NOT corrected (" .. (ok and tostring(notes) or main.error_text(sent)):sub(1, 200) ..
				"); " .. field .. " is no longer corrected")
			pcall(settle, field, amount, false)
		end
	end
	correct("loan", "loan corrected by", function(amount, cb) return sync.book(env, amount, "LOAN", cb) end)
	correct("money", "money corrected by", function(amount, cb) return sync.book(env, amount, "OTHER", cb) end)
	correct("date", "date moved by", function(days, cb)
		return true, sync.shift_date(env, main.game_time(env) or tonumber(fix.fix_gt) or 0, days, cb)
	end)
end

--- Without a GUI script the simulation keeps the shared speed (it stops while paused).
function main.sync_speed_fallback(env, ss, role, gt, getenv)
	local own_gui = sync.decode(getenv("TF3MP_OWN_GUI"))
	if own_gui and own_gui.src == "gui" then ss.gui_seen = true end
	if ss.gui_seen or ss.ticks < main.SYNC_FALLBACK_AFTER then return end
	local clock = env.os and env.os.clock
	if not clock then return end
	if not ss.fallback_logged then
		ss.fallback_logged = true
		logger.info("sync: the GUI script does not run here; the simulation keeps the speed " ..
			"(a pause of the other game cannot be lifted from here)")
	end
	ss.speed_mem = ss.speed_mem or {}
	local out = sync.speed_step(ss.speed_mem, {
		own = sync.read_speed(env), own_t = gt, role = role, peer = sync.decode(getenv("TF3MP_PEER_GUI")),
		now = clock(), hold = false, src = "sim",
	})
	for _, line in ipairs(out.logs) do logger.info("sync " .. line) end
	if out.command then
		local target = out.command
		-- No result callback: update() may not have one (run 25).
		sync.set_speed(env, target)
	end
	if out.publish then logger.info(main.STATE_MARKER .. "gui " .. out.publish) end
end

--- Once per savegame and version: how the game's journal entries look (read only). Nothing is
-- booked here: a booking the engine rejects with an assertion could end the game, and this test
-- would then run again on every load, because the savegame never got to keep the mark.
function main.journal_test(env)
	local ok, text = pcall(sync.describe_journal, env)
	logger.info("journal: " .. (ok and text or ("unreadable " .. main.error_text(text))))
end

--- GUI script (main.gs.lua): runs on every frame, also while the game is paused.
function main.guiUpdate()
	gui.update(_G)
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
	local opts = {
		node_position = function(id) return world.node_position(env, id) end,
		segment_ends = function(id) return world.edge_ends(env, id) end,
		to_add = param[1].toAdd,
		to_remove = param[1].toRemove,
		construction = function(id) return cons[tostring(id)] end,
		edge_object = function(id, from_proposal)
			local o = world.edge_object_info(env, id, from_proposal)
			if s.edge_object_logged ~= main.PROBE_VERSION then
				-- First stop/signal of this version: everything that was read, for the docs.
				logger.info("stop/signal " .. tostring(id) .. " read: " .. world.describe_edge_object(o))
				s.edge_object_logged = main.PROBE_VERSION
			end
			return o
		end,
		read_transf = function(t)
			local m, how = build.read_transf(t)
			if m and s.transf_logged ~= main.PROBE_VERSION then
				logger.info("construction transf read as " .. how)
				s.transf_logged = main.PROBE_VERSION
			end
			return m, how
		end,
	}
	local ok, line, info = pcall(build.serialize, param[1].proposal, opts)
	if not ok then
		logger.info("capture failed (" .. label .. "): " .. tostring(line))
		return
	end
	logger.info("capture " .. label .. " nodes=" .. info.nodes .. " segments=" .. info.segments ..
		" foreign_nodes=" .. info.foreign_nodes .. " removed_segments=" .. info.removed_segments ..
		" removed_nodes=" .. info.removed_nodes .. " constructions=" .. info.constructions ..
		" demolished=" .. info.demolished .. " edge_objects=" .. info.edge_objects ..
		" access_segments=" .. tostring(info.access) .. " node_configs=" .. tostring(info.node_configs) ..
		" config_removes=" .. tostring(info.config_removes))
	for _, what in ipairs(info.dropped) do logger.info("capture leaves out " .. what) end
	logger.info("capture line " .. line)
	-- v21: a build that only changes node configurations (lane connections, traffic lights) travels too.
	if info.segments + info.removed_segments + info.constructions + info.demolished + (info.node_configs or 0) > 0 then
		s.last_build = line
		state:set(s)
		logger.info("capture stored for replay (" .. #line .. " characters)")
		if #line > main.MAX_LINE then
			-- v26: the DLL drops such a line with a note in its own log only.
			logger.info(string.format("capture line TOO LONG for the network (%d characters, at most %d): " ..
				"the other game does not get this build", #line, main.MAX_LINE))
		else
			transport.send(line, s, logger.info)
			state:set(s)
		end
	end
	if info.access > 0 and info.constructions > 0 then
		local ok_w, err = pcall(main.describe_original_entrance, env, s, param)
		if not ok_w then logger.info("weld check of the original failed: " .. tostring(err):sub(1, 200)) end
	end
end

--- v20 diagnosis on the building side: is the player's own construction welded (it should be,
-- which tests weld.status), and how does the engine's refresh proposal describe its gate.
function main.describe_original_entrance(env, s, param)
	local id = weld.construction_in(env, param[3])
	if not id then
		logger.info("weld check (original): construction not among the new entities")
		return
	end
	logger.info("weld check (original): " .. weld.status(env, id, {}).text)
	s.weld_original_dumps = s.weld_original_dumps or 0
	if s.weld_original_dumps >= main.WELD_ORIGINAL_DUMPS then return end
	s.weld_original_dumps = s.weld_original_dumps + 1
	local ok, p = pcall(function() return env.api.engine.util.proposal.refreshConstruction(id) end)
	if not ok or p == nil then
		logger.info("weld refresh proposal (original): none (" .. tostring(p):sub(1, 160) .. ")")
		return
	end
	logger.info("weld refresh proposal (original, not sent): " .. weld.describe_proposal(p))
	main.dump_value("weld refresh proposal (original)", p)
end

--- Field dump of an engine value with the weld line budget.
function main.dump_value(label, value)
	local ok, lines = pcall(probe.fields, value, "p", 6, main.WELD_DUMP_LINES)
	if ok and #lines > 0 then log_lines(label, lines) end
end

--- Keeps file and position of every construction in the script state, because a demolish event
-- only names the construction's id and arrives after it is gone. Fed from the ids each build
-- creates (also copies built for the other player) and once per savegame from a full scan.
function main.remember_constructions(env, s, param)
	s.constructions = s.constructions or {}
	-- Upgrades may reuse the removed construction's ID (run28). Clear the old snapshot
	-- first, then remember the current construction, so the next upgrade can replace it.
	pcall(function()
		local removed = param[1].toRemove
		for i = 1, #removed do s.constructions[tostring(removed[i])] = nil end
	end)
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
end

function main.handleEvent(_user_params, state, src, id, name, param)
	if main.is_replay_event(src, id, name) then
		if type(param) == "table" and param.network_continue then
			local env = transport.env(_G, state)
			local ok, err = pcall(main.network_continue, env, state)
			if ok then ok, err = pcall(main.network_run, env, state) end
			if not ok then transport.fail(state, err) end
			transport.check(state, logger.info)
			return
		end
		if type(param) == "table" and param.sync_fix then
			local ok, err = pcall(main.sync_apply, _G, state, param)
			if not ok then logger.info("sync correction failed: " .. main.error_text(err):sub(1, 240)) end
			return
		end
		if type(param) == "table" and param.action_work then
			local s = state:get() or {}
			s.action_work_requested = false
			state:set(s)
			local ok, err = pcall(actions.tick, transport.env(_G, state), state, transport.action_log(state, logger.info))
			if not ok then
				transport.fail(state, main.error_text(err))
				logger.info("action continuation failed: " .. main.error_text(err):sub(1, 400))
			end
			transport.check(state, logger.info)
			return
		end
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
		local network = type(param) == "table" and param.source ~= nil
		if network then
			local live = state:get() or {}
			if live.network_done and live.network_done.token == tostring(number) then
				logger.info("net result " .. tostring(number) .. " " .. live.network_done.result)
				return
			end
			if live.network_work and live.network_work.dispatched then return end
			if not transport.begin(state, tostring(number)) then return end
		end
		local env = transport.env(_G, state)
		local ok, applied, err = pcall(main.replay_line, env, line, number, state, distance)
		if network then
			if not ok or not applied then transport.fail(state, ok and (err or "replay failed") or applied)
			else
				local ok_run, err_run = pcall(main.network_run, env, state)
				if not ok_run then transport.fail(state, err_run) end
			end
			transport.dispatched(state); transport.check(state, logger.info)
		elseif not ok then logger.info("replay failed: " .. main.error_text(applied)) end
		return
	end
	local s = state:get() or {}
	if name == "handleLegacy" then
		logger.info("net reload")
		s.network_work = nil
		-- A native callback or an event in flight cannot survive a game reload.
		-- Observe the loaded save anew; don't execute persisted, stale UI operations.
		s.actions, s.action_inbox, s.action_work = nil, nil, nil
		s.action_busy, s.action_work_requested = false, false
		s.network_followup = nil
		-- The other game's checkpoints and corrections belong to the session before.
		s.sync = nil
	end
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
		-- The copy arrives with isPlayerBuild=false (run 11); run 14 swallowed a real player build here.
		if not player_build and now and now < (s.quiet_until or -1) and main.segment_count(param) == s.quiet_segments
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

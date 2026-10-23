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
local timeline = require("/mp_probe/timeline.lua")
local hold = require("/mp_probe/hold.lua")
local wire = require("/mp_probe/wire.lua")
local economy = require("/mp_probe/economy.lua")

local main = {}

--- Bump to re-run the one-time probe in a savegame that already ran it.
main.PROBE_VERSION = 68
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
-- v34: the builder events reach guiHandleEvent only when subscribed (company.script.tl does the same).
main.SUBSCRIBED_EVENTS = { "onPostBuildProposal", "mp_probe_replay", "Obtain", "Repay", "mp_probe_schedule",
	"builder.proposalCreate", "builder.proposalPrepareForApply", "builder.proposalApply", "mp_probe_reverse", "mp_probe_vehicle", "mp_probe_economy" }

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
main.ACTION_KINDS = { "line", "vehicle", "account", "company" }
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
main.HANDOVER_RETRY_SECONDS = 2
main.HANDOVER_RETRY_POLLS = 50

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
	if s.network_handover and s.network_handover.phase == "queued" then return true end
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
	if not getenv then
		if state then main.handover_tick(env, state) end
		return
	end
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
	if state then main.handover_tick(env, state) end
end

--- Handles a "line <token> <kind> <text>" value from the DLL. The DLL keeps the value until it sees
-- the acknowledgement in stdout.txt, so the same token can be read again by the next tick; it is
-- built only once (the token is kept in the savegame state) but acknowledged every time.
function main.receive_line(env, s, value, state)
	value = transport.receive(s, value, logger.info, state ~= nil)
	if state then main.store(state, s) end
	if not value then return end
	local token, kind, line = string.match(value, "^line (%S+) (%a+) (.+)$")
	if not token or #line > main.MAX_LINE then return end
	if state then
		local live = state:get() or {}
		-- Never release the DLL inbox while another receipt owns the event state.
		-- In particular a scheduled action has no separate native inbox permit.
		if live.network_work and live.network_work.token ~= token then return end
		local h, reason = transport.accept_handover(state, token, kind, line,
			kind == "loop" and main.REPLAY_SIDE_OFFSET or 0)
		if not h and reason ~= "owned" then return end
		live = state:get() or {}
		transport.ack_complete(live, token, logger.info)
		logger.info(main.RECEIVED_MARKER .. token .. " kind=" .. kind .. " (" .. #line .. " characters)")
		if live.network_done and live.network_done.token == token then
			logger.info("net result " .. token .. " " .. live.network_done.result)
		end
		main.handover_tick(env, state)
		return
	end
	-- Legacy one-PC callers without a game-script state cannot retain a handover.
	logger.info(main.RECEIVED_MARKER .. token .. " kind=" .. kind .. " (" .. #line .. " characters)")
	if token == s.last_line_token then
		if s.network_done and s.network_done.token == token then
			logger.info("net result " .. token .. " " .. s.network_done.result)
		end
		return
	end
	-- A logical scheduled action has no native permit of its own. Controls may arrive
	-- during its callbacks; leave their inbox token untouched until that receipt clears.
	if s.network_work and s.network_work.token ~= token then return end
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
		transport.dispatched(state); transport.check(state, logger.info, main.skip_failures(env))
		return
	end
	main.replay_line(env, line, token, state, offset)
end

local function handover_time(env)
	for _, key in ipairs({ "time", "clock" }) do
		local ok, now = pcall(function() return env.os[key]() end)
		if ok and type(now) == "number" and now == now and math.abs(now) < math.huge then return now, key end
	end
end

-- Sending a scripting command is not evidence that its event was delivered.
-- Retry only the durable, not-yet-started handover; the handler atomically claims
-- its identity before executing anything. Once started, only diagnostics remain.
function main.handover_tick(env, state)
	local s = state:get() or {}; local h = s.network_handover
	if not h or h.phase ~= "queued" or s.network_work then return end
	main.publish_network_work(state, false)
	s = state:get() or s; h = s.network_handover
	h.polls = (h.polls or 0) + 1
	local now, timer = handover_time(env)
	local due = (h.attempts or 0) == 0
	if not due then
		if now and h.timer == timer and h.last_attempt and now >= h.last_attempt then
			due = now - h.last_attempt >= main.HANDOVER_RETRY_SECONDS or h.polls >= 2000
		else due = h.polls >= main.HANDOVER_RETRY_POLLS end
	end
	if not due then state:set(s); return end
	h.attempts, h.polls = (h.attempts or 0) + 1, 0
	h.last_attempt, h.timer = now, timer
	state:set(s)
	local sent = main.send_replay_event(env, { number = h.token, source = h.kind,
		handover_id = h.id, handover_world = h.world })
	-- No state write after dispatch: the event may have run synchronously.
	if h.attempts == 1 or h.attempts % 5 == 0 then
		logger.info("net handover " .. h.token .. ": event attempt " .. h.attempts ..
			(sent and " submitted; waiting for execution to start" or " unavailable; retained for safe delivery"))
	end
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
		find_edge_at = function(a, b, kind) return world.find_edge_at(env, nodes(), a, b, kind) end,
		node_construction = function(node) return world.node_construction(env, node) end,
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
	if line:sub(1, 3) == "S1 " then
		local s = state:get() or {}
		local role = sync.role(env.os and env.os.getenv)
		if role ~= "host" and role ~= "client" then return false, "common timing needs a prepared peer" end
		local now = main.game_time(env)
		if not now then return false, "game time unreadable" end
		local ok, err = timeline.receive(main.timeline_of(s, role), line, now)
		-- v37: a failed timeline message is never skipped (transport.check).
		if s.network_work and s.network_work.token == tostring(number) then s.network_work.noskip = true end
		state:set(s)
		return ok, err
	end
	if line:sub(1, 3) == "W1 " or line:sub(1, 3) == "W2 " then return main.world_receive(env, line, state) end
	if line:sub(1, 3) == "I1 " then
		local token, partial, description, reason = line:match("^I1 ([%w_.%-]+) (%a+) (%x+) (%x+)$")
		if not token or #token > 64 or (partial ~= "partial" and partial ~= "none") or
			#description > 640 or #reason > 480 or #description % 2 ~= 0 or #reason % 2 ~= 0 then
			return false, "invalid action diagnostic"
		end
		logger.info("action issue peer " .. line)
		return true
	end
	if line:sub(1, 1) == "A" then
		local action, err = actions.decode(line)
		if not action then logger.info("action replay: bad line (" .. tostring(err) .. ")"); return false, err end
		local descriptions = { construction_create = "Gebäude bauen", construction_update = "Gebäude ändern",
			construction_remove = "Gebäude abreißen", edge_remove = "Straße/Gleis abreißen",
			line_create = "Linie erstellen", line_update = "Linie ändern", line_remove = "Linie löschen",
			vehicle_create = "Fahrzeug kaufen", vehicle_update = "Fahrzeug ändern", vehicle_remove = "Fahrzeug verkaufen",
			loan_event = "Kredit ändern", account_update = "Konto ändern" }
		local label = descriptions[action.op] or tostring(action.op or "Aktion")
		local record = action.value or action.record or action.data or action.target or action.ref or {}
		if type(record) ~= "table" then record = {} end
		local ref = type(record.ref) == "table" and record.ref or {}
		label = label .. ": " .. tostring(record.name or ref.name or "")
		label = economy.description(action) or label
		if action.op == "loan_event" then
			label = (record.name == "Obtain" and "Kredit aufnehmen" or "Kredit zurückzahlen") ..
				": " .. tostring(record.obtained and record.obtained.amount or "?")
		end
		if action.op == "vehicle_command" then
			label = main.vehicle_label(action)
		end
		transport.describe(state, label)
		if action.op == "vehicle_command" then return main.run_vehicle_command(env, state, action) end
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
	local labels = {}
	for _, c in ipairs(data.constructions) do
		local kind = c.file:find("/stations/", 1, true) and "Bahnhof/Haltestelle" or
			(c.file:find("/depots/", 1, true) and "Depot" or "Gebäude")
		labels[#labels + 1] = kind .. " " .. (c.name ~= "" and c.name or (c.file:match("([^/]+)$") or c.file)) ..
			string.format(" bei %.1f, %.1f", c.transf[13], c.transf[14])
	end
	local label = #labels > 0 and table.concat(labels, "; ") or "Straßen/Gleise oder Abriss"
	local point = data.nodes[1] and data.nodes[1].position or
		(data.removed_segments[1] and data.removed_segments[1].p0) or data.removed_nodes[1] or
		(data.configs[1] and data.configs[1].position)
	if not point then local _, p = next(data.foreign); point = p end
	if #labels == 0 and data.demolished[1] then
		label = "Gebäude abreißen: " .. (data.demolished[1].file:match("([^/]+)$") or data.demolished[1].file)
		point = data.demolished[1].position
	end
	if #labels == 0 and point then label = label .. string.format(" bei %.1f, %.1f", point.x, point.y) end
	transport.describe(state, label)
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
	return main.replay_data(env, data, state, player, number)
end

--- Continue a build after native field replacements have finished. Resolve graph IDs only then,
-- because refreshing an industry's entrance can change its entities.
function main.replay_data(env, data, state, player, number)
	local has_gates = data.replay_has_gates
	if has_gates == nil then has_gates = next(data.gates or {}) ~= nil and #data.constructions > 0 end
	if has_gates and data.replay_has_gates == nil then
		-- Run 20b: the copied construction lays its own entrance, and the copied entrance street
		-- came on top of it as a second one ending in a second node on the gate. v21 leaves the
		-- street out; weld.lua checks that the construction's own entrance meets the road.
		data.gate_positions = weld.gate_positions(data)
		local before = #data.segments
		build.drop_access(data)
		logger.info(string.format("replay: %d entrance segment(s) left out, the construction lays its own",
			before - #data.segments))
	end
	data.replay_has_gates = has_gates
	if not data.environment_planned then
		local jobs = build.plan_environment(data, main.finder(env))
		data.environment_planned = true
		has_gates = data.replay_has_gates
		if #jobs > 0 then
			logger.info("replay: " .. #jobs .. " industry field replacement(s) through the native helper before building")
			if state and (state:get() or {}).network_work then
				local live = state:get() or {}
				live.network_followup = { phase = "environment", jobs = jobs, index = 1,
					data = data, player = player, number = number }
				state:set(live)
				return true, "industry field replacements queued"
			end
			for _, job in ipairs(jobs) do
				local opts, completed = main.replay_options(player, false, state), false
				opts.on_result = function(...)
					completed = true; main.log_replay_result(...)
				end
				local ok, err = build.replay(env, job, opts)
				if not ok then return false, err end
				if not completed then return false, "asynchronous field replacement needs a network execution receipt" end
			end
		end
	end
	-- A field-only event needs no empty player proposal after its native replacements.
	if #data.constructions + #data.demolished + #data.nodes + #data.segments + #data.removed_segments +
		#data.removed_nodes + #data.configs == 0 then return true end
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
	-- sendCommand can deliver nested script events before its callback returns. Persist the
	-- guard before sending: otherwise the nested event sees the same phase and repeats it.
	if follow.running then return end
	follow.requested = nil
	if live.network_work and (live.network_work.pending or 0) > 0 then
		-- A request that crossed a command still outstanding; update() asks again once it is back.
		state:set(live)
		return
	end
	local token = live.network_work and live.network_work.token
	follow.running = true
	state:set(live)
	logger.info("net step " .. tostring(live.network_work and live.network_work.token) .. ": " .. tostring(follow.phase))
	local ok, err = pcall(function()
		if follow.phase == "environment" then
			local ok, err = build.replay(env, follow.jobs[follow.index], main.replay_options(follow.player, false, state))
			if not ok then transport.fail(state, err) end
			follow.index = follow.index + 1
			if follow.index > #follow.jobs then follow.phase = "environment_build"; follow.jobs = nil end
		elseif follow.phase == "environment_build" then
			-- replay_data installs its own finish/verification stages. Do not overwrite them
			-- with this completed environment stage when returning from the command callback.
			-- Keep the running guard visible until it returns, including while a synchronous
			-- callback has reached pending=0 but the new finish stage is not installed yet.
			local ok, err = main.replay_data(env, follow.data, state, follow.player, follow.number)
			if not ok then transport.fail(state, err) end
			follow = (state:get() or {}).network_followup
			if follow and follow.phase == "environment_build" then follow = nil end
		elseif follow.phase == "street_configs" then
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
	end)
	live = state:get() or {}
	if (live.network_work and live.network_work.token) == token then
		if follow then follow.running = nil end
		live.network_followup = follow
		state:set(live)
	end
	if not ok then error(err, 0) end
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
		if not live.network_followup or live.network_followup.running or not work or work.error or (work.pending or 0) > 0 then return end
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
			gates = data.gate_positions or {}, require_connection = weld.connection_required(data),
			due = now + main.WELD_RECHECK_MS,
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
				local status = weld.status(env, id, c.gates or {}, c.require_connection)
				logger.info("weld check later: " .. status.text)
				local confirmed = status.confirmed
				if confirmed == nil then confirmed = status.welded == true end
				if not confirmed then fail("construction entrance not confirmed: " .. status.text) end
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
	s.network_handover, s.network_handover_seq = live.network_handover, live.network_handover_seq
	s.network_handover_epoch, s.network_receipt_seq = live.network_handover_epoch, live.network_receipt_seq
	s.network_work_published = live.network_work_published
	s.last_line_token, s.loaded_world = live.last_line_token, live.loaded_world
	s.timeline = live.timeline
	state:set(s)
end

-- A compact native/launcher heartbeat. A handoff is still unstarted and may be
-- safely redelivered; callbacks/followup/weld always retain their engine receipt.
function main.publish_network_work(state, heartbeat)
	local s = state:get() or {}; local w, h = s.network_work, s.network_handover
	local token, phase, pending = "-", "idle", 0
	if w then
		token, pending = w.token, math.max(0, math.min(100000, tonumber(w.pending) or 0))
		if pending > 0 then phase = "callbacks"
		elseif s.network_followup then phase = "followup"
		elseif s.weld_checks and #s.weld_checks > 0 then phase = "weld"
		else phase = "waiting" end
	elseif h and h.phase == "queued" then token, phase = h.token, "handoff" end
	local raw = "token=" .. tostring(token):gsub("[^%w_.%-]", "_"):sub(1, 120) ..
		" phase=" .. phase .. " pending=" .. string.format("%d", pending)
	if heartbeat or raw ~= s.network_work_published then
		s.network_work_published = raw; state:set(s)
		logger.info(main.STATE_MARKER .. "work " .. raw)
	end
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

function main.reset_loaded_runtime(s)
	s.network_work, s.network_followup, s.network_done = nil, nil, nil
	s.network_handover = nil
	s.network_handover_epoch = (s.network_handover_epoch or 0) + 1
	s.network_work_published = nil
	s.actions, s.action_inbox, s.action_work = nil, nil, nil
	s.action_busy, s.action_work_requested = false, false
	s.sync, s.timeline = nil, nil
	-- The shared save now contains the host's actual entity ids. Mappings, chunks
	-- and entrance checks from either previous world must never survive its load.
	s.action_entities, s.weld_checks, s.bridge_parts = nil, nil, nil
	s.last_line_token, s.quiet_until, s.quiet_segments = nil, nil, nil
	s.paused_polls = nil
end

-- WORLD changes on every original engine load, including saves without handleLegacy.
-- The token is per process/load, rather than a persisted savegame counter.
function main.initialize_loaded_world(env, s)
	local getenv = env.os and env.os.getenv
	if not getenv then return end
	local ok, world_id = pcall(getenv, "TF3MP_WORLD")
	if not ok or type(world_id) ~= "string" or not world_id:match("^%d+%-%d+%-%d+$") then return end
	local changed = s.loaded_world ~= world_id
	if changed then
		main.reset_loaded_runtime(s)
		s.loaded_world, s.world_ready_retry = world_id, 0
		logger.info("net runtime reset for world " .. world_id)
	end
	local ack_ok, ack = pcall(getenv, "TF3MP_WORLD_ACK")
	if not ack_ok or ack ~= world_id then
		s.world_ready_retry = (s.world_ready_retry or 0) + 1
		if s.world_ready_retry % 10 == 1 then logger.info("net initialized " .. world_id) end
	end
	return changed
end

-- Commit the reset before store() merges the live execution receipt. A normal
-- update and the first GUI heartbeat while paused must use this same path.
function main.loaded_state(env, state)
	local s = state:get() or {}
	if main.initialize_loaded_world(env, s) then
		state:set(s)
		main.publish_network_work(state, true)
		s = state:get() or s
	end
	return s
end

function main.update(_user_params, state, _dt)
	local s = main.loaded_state(_G, state)
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
		local ok, list = pcall(world.player_constructions, _G, true)
		if ok then
			s.constructions = {}
			local n = 0
			for id, info in pairs(list) do
				s.constructions[tostring(id)] = info
				n = n + 1
			end
			logger.info("player and industry constructions found: " .. n)
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
	if follow and not follow.running and work and not work.error and (work.pending or 0) == 0 and not follow.requested then
		follow.requested = true; state:set(live)
		if not main.send_replay_event(_G, { network_continue = true }) then
			transport.fail(state, "build continuation event unavailable")
		end
	end
	main.check_network(state)
	s = state:get() or s
	main.log_network_wait(s)
	main.publish_network_work(state, bridge_now)
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
	main.timeline_tick(_G, state)
	local ok_money, err_money = pcall(main.economy_tick, _G, state)
	if not ok_money then logger.info("subvention money sync failed: " .. main.error_text(err_money):sub(1, 220)) end
end

-- After both native subsidy decisions, the host's actual balance wins. This is
-- independent of the slow world comparison and of differences in loan offers.
local function economy_busy(env, s)
	if s.action_busy or s.network_work or (s.action_work and #s.action_work > 0) then return true end
	local getenv = env.os and env.os.getenv; if not getenv then return false end
	for _, key in ipairs({ "TF3MP_OWN_CLOCK", "TF3MP_PEER_CLOCK" }) do
		local clock = sync.decode(getenv(key) or "")
		if clock and (clock.hold == 1 or (clock.phase and clock.phase ~= "idle")) then return true end
	end
	return false
end

function main.economy_tick(env, state)
	local s = state:get() or {}; local request = s.actions and s.actions.subvention_money
	if not request then return end
	local getenv = env.os and env.os.getenv; if not getenv then return end
	local role = sync.role(getenv); if role ~= "host" and role ~= "client" then return end
	if economy_busy(env, s) then return end
	if (request.settle or 0) > 0 then request.settle = request.settle - 1; state:set(s); return end
	if role == "host" then
		if (s.updates or 0) % main.SYNC_READ_EVERY ~= 0 then return end
		local account = env.api.engine.getComponent(env.api.engine.util.getPlayer(), env.api.type.ComponentType.ACCOUNT)
		local raw = sync.encode({ key = request.key, money = account.balance })
		if raw ~= request.published then request.published = raw; state:set(s); logger.info(main.STATE_MARKER .. "economy " .. raw) end
	elseif not request.requested and not request.applied then
		local peer = sync.decode(getenv("TF3MP_PEER_ECONOMY") or "")
		if not peer or peer.key ~= request.key or type(peer.money) ~= "number" then return end
		request.requested = true; state:set(s)
		if not main.send_replay_event(env, { economy_money = true, money = peer.money, key = request.key }) then
			main.economy_issue(env, state, "Subvention: Geld an Gastgeber angleichen", "subvention money sync event unavailable")
		end
	end
end

function main.economy_apply(env, state, param)
	if sync.role(env.os and env.os.getenv) ~= "client" then return end
	local s = state:get() or {}; local request = s.actions and s.actions.subvention_money
	if not request or request.key ~= param.key or request.applied then return end
	if economy_busy(env, s) then request.requested = nil; state:set(s); return end
	local target = param.money
	assert(type(target) == "number" and target == math.floor(target) and math.abs(target) <= 9007199254740991, "invalid host subsidy balance")
	local account = env.api.engine.getComponent(env.api.engine.util.getPlayer(), env.api.type.ComponentType.ACCOUNT)
	local amount = target - account.balance
	-- Reserve before sending: a synchronous callback or duplicate event cannot pay twice.
	request.applied = true
	if s.sync then
		-- A checkpoint from before the subsidy must not apply an older delta later.
		if s.sync.pending_fix then s.sync.pending_fix.money = nil end
		if s.sync.fixes then s.sync.fixes.money = nil end
		s.sync.compared_k = math.max(s.sync.compared_k or -1, s.sync.own_k or -1)
		s.sync.money_rebased_gt = main.game_time(env)
	end
	state:set(s)
	if amount == 0 then logger.info("subvention money: already matches host " .. target); return end
	local sent, why = sync.book(env, amount, "OTHER", function(_, success)
		if success == false then main.economy_issue(env, state, "Subvention: Geld an Gastgeber angleichen", "subvention money correction rejected"); return end
		local live = state:get() or {}; if live.sync then live.sync.adj = (live.sync.adj or 0) + amount end; state:set(live)
		logger.info("subvention money: corrected by " .. amount .. "; host balance " .. target)
	end)
	if not sent then main.economy_issue(env, state, "Subvention: Geld an Gastgeber angleichen", "subvention money correction unavailable: " .. tostring(why)) end
end

--- The common-tick timeline of this game. A save made by the other game (Neuabgleich) carries its
-- timeline with the other role; that one is never continued here.
function main.timeline_of(s, role)
	if not s.timeline or s.timeline.role ~= role then s.timeline = timeline.new(role) end
	return s.timeline
end

-- This entry accepts only intents whose caller has prevented their original execution.
-- Ordinary TF3 UI capture remains post-execution and must not use this path.
function main.submit_intent(env, state, param)
	if type(param) ~= "table" then return false, "held command data missing" end
	local role = sync.role(env.os and env.os.getenv)
	if (role ~= "host" and role ~= "client") or env.os.getenv("TF3MP_ORDERING") ~= "1" then
		return false, "common timing requires the native ordered session"
	end
	local s = main.loaded_state(env, state)
	local action = type(param.line) == "string" and param.line:sub(1, 3) == "A1 " and actions.decode(param.line)
	local ok, err = timeline.submit(main.timeline_of(s, role), param.line, param.held,
		{ barrier = action and action.op == "vehicle_command" or false })
	state:set(s)
	return ok, err
end

--- A handover failure must also reach the launcher's normal, paired error report.
-- This isolated receipt cannot overwrite another replay currently in flight.
function main.economy_issue(env, state, label, reason)
	local s = state:get() or {}; s.economy_issue_seq = (s.economy_issue_seq or 0) + 1
	local token = "economy_" .. tostring(sync.role(env.os and env.os.getenv)) .. "." .. s.economy_issue_seq
	state:set(s)
	local temporary = {}; local receipt = { get = function() return temporary end, set = function(_, v) temporary = v end }
	transport.begin(receipt, token); transport.describe(receipt, label); transport.fail(receipt, reason); transport.dispatched(receipt)
	transport.check(receipt, function(text)
		local issue = text:match("^action issue local (I1 .+)$")
		if issue then
			logger.info(text)
			if main.skip_failures(env) then
				local live = state:get() or {}; transport.send(issue, live, logger.info); state:set(live)
			end
		end
	end, true)
end

function main.economy_intent(env, state, param)
	local label = type(param) == "table" and param.kind == "company" and
		("Unternehmen umbenennen: " .. tostring(param.name or "")) or
		("Subvention " .. (type(param) == "table" and param.name == "onDecline" and "ablehnen" or "annehmen"))
	local prepared, action = pcall(economy.prepare, env, param)
	if not prepared then action = { op = "economy_error", value = { label = label, reason = main.error_text(action):sub(1, 240) } } end
	local line = actions.encode(action)
	local planned, why = main.submit_intent(env, state, { line = line, held = true })
	if planned then logger.info("economy command scheduled: " .. (economy.description(action) or label)); return true end
	-- Never execute an intercepted financial decision locally after a failed plan:
	-- that could pay one account while the partner never sees the request.
	main.economy_issue(env, state, economy.description(action) or label, "economy scheduling failed: " .. tostring(why))
	return false
end

--- v35: a vehicle command clicked in this game's GUI (hold.lua: reverse, start/stop, to the
-- depot; v36 also to a line and selling, several at once as param.batch). It is planned on the
-- common timeline and runs in both games at the same tick. Without a timeline it runs here at
-- once and travels as before (actions.poll).
function main.vehicle_entry(env, p)
	assert(type(p) == "table" and actions.VEHICLE_COMMANDS[p.command], "unknown vehicle command")
	local function id(v) assert(type(v) == "number" and v >= 0 and v % 1 == 0, "invalid vehicle id"); return v end
	if p.command == "sell" then
		assert(type(p.vehicles) == "table" and #p.vehicles > 0, "nothing to sell")
		local targets = {}
		for i, v in ipairs(p.vehicles) do targets[i] = actions.vehicle_ref(env, id(v)) end
		return { command = "sell", targets = targets }
	end
	local e = { command = p.command, target = actions.vehicle_ref(env, id(p.vehicle)) }
	if p.command == "line" then
		assert(type(p.value) == "number" and p.value % 1 == 0, "invalid line id")
		if p.value >= 0 then e.line = actions.line_ref(env, p.value) end
		e.stop = type(p.stop) == "number" and p.stop >= -1 and p.stop % 1 == 0 and p.stop or 0
	else
		e.value = p.value == true
		if p.command == "depot" and p.jumpDepot ~= nil then
			e.jumpDepot = actions.depot_ref(env, id(p.jumpDepot))
		end
	end
	return e
end

--- The local ids of one entry: vehicle(s) and, for "line", the line (-1: none).
function main.vehicle_ids(env, s, e, own)
	if e.command == "sell" then
		local list = {}
		for i, ref in ipairs(e.targets) do list[i] = actions.timed_target(env, s, ref, own) end
		return list
	end
	local vehicle = actions.timed_target(env, s, e.target, own)
	local line = e.line and actions.timed_target(env, s, e.line, own) or -1
	local jump_depot = e.jumpDepot and actions.resolve(env, e.jumpDepot, s, "timed", 0) or nil
	return { vehicle }, line, jump_depot
end

function main.entry_name(e)
	if e.command == "sell" then return "sell of " .. #e.targets .. " vehicle(s)" end
	return e.command .. " for " .. tostring(e.target.name)
end

function main.vehicle_label(action)
	local labels = {}
	local commands = { reverse = "umkehren", stopped = "Start/Stopp", depot = "ins Depot",
		line = "Linie zuweisen", sell = "verkaufen" }
	for _, e in ipairs(main.vehicle_entries(action)) do
		labels[#labels + 1] = (commands[e.command] or tostring(e.command)) .. " " ..
			tostring(e.target and e.target.name or (#(e.targets or {}) .. " Fahrzeug(e)"))
	end
	return "Fahrzeug: " .. table.concat(labels, ", ")
end

function main.vehicle_intent(env, state, param)
	assert(type(param) == "table", "vehicle command data missing")
	local list = { param }
	if param.batch ~= nil then
		local decoded, err = wire.decode(param.batch)
		assert(type(decoded) == "table" and #decoded > 0, "invalid vehicle batch: " .. tostring(err))
		list = decoded
	end
	local entries, poll = {}, false
	for i, p in ipairs(list) do
		entries[i] = main.vehicle_entry(env, p)
		poll = poll or p.command == "line" or p.command == "sell"
	end
	local role = sync.role(env.os and env.os.getenv)
	local s = state:get() or {}
	if poll and not s.action_busy and not (s.action_work and #s.action_work > 0) then
		-- A bus bought a moment ago must reach the other game before it is sent onto its line there.
		local ok, err = pcall(actions.poll, env, s, function(text) logger.info(text) end, { "line", "vehicle" })
		if not ok then logger.info("action poll failed: " .. tostring(err):sub(1, 220)) end
		state:set(s)
	end
	local action = { op = "vehicle_command", origin = role, commands = entries }
	local ok, err = main.submit_intent(env, state, { line = actions.encode(action), held = true })
	local names = {}
	for i, e in ipairs(entries) do names[i] = main.entry_name(e) end
	if ok then
		logger.info("vehicle " .. table.concat(names, ", ") .. " planned for a common tick")
		return true
	end
	if (role == "host" or role == "client") and env.os.getenv("TF3MP_ORDERING") == "1" then
		-- The original UI command was held. Executing only here would send a bus
		-- out before its peer knows about it, or lose a second reverse entirely.
		main.economy_issue(env, state, main.vehicle_label(action), "vehicle scheduling failed: " .. tostring(err))
		return false
	end
	logger.info("vehicle " .. table.concat(names, ", ") .. " not timed (" .. tostring(err) .. "); running it here now")
	s = state:get() or {}
	for _, e in ipairs(entries) do
		local ids, line, jump_depot = main.vehicle_ids(env, s, e, true)
		if e.command == "reverse" then actions.note_reverse(s, ids[1]); state:set(s) end
		main.send_vehicle_command(env, e, ids, line, nil, nil, jump_depot)
	end
	return true
end

function main.vehicle_line_failure(env, id, line, stop)
	local detail = "line assignment rejected (vehicle " .. id .. ", line " .. line .. ", stop " .. tostring(stop) .. ")"
	-- Same native diagnosis used by TF3's vehicle manager. It can be unavailable
	-- in a simulation context; diagnostic failure must preserve the rejection.
	local ok, reason = pcall(function()
		local failure = env.api.engine.util.line.getFailedPathReason(id, line, true)
		local descriptions = { Unkown = "no specific path diagnosis from TF3", Unknown = "no specific path diagnosis from TF3",
			NoPath = "no path", NoElectric = "missing electrification", NoRail = "missing rail",
			NoRoad = "missing road", NoTram = "missing tram", NoTramButTramTrack = "incompatible tram track",
			NoTramTrackButRail = "incompatible rail", NoSmallAircraft = "aircraft incompatible with airport",
			NoSmallShip = "ship incompatible with port" }
		local text = "path reason " .. tostring(failure.reason):sub(1, 70)
		local types = env.api.type.Failure.Reason
		for name, description in pairs(descriptions) do
			if types[name] ~= nil and types[name] == failure.reason then text = description; break end
		end
		if failure.pos then text = text .. string.format(" at %.1f, %.1f", failure.pos.x, failure.pos.y) end
		return text
	end)
	detail = detail .. (ok and (": " .. reason) or ": path diagnosis unavailable")
	-- TF3's generic reason 0 does not explain whether a copied line has lost a
	-- stop or path. Read native stop problems only after a rejection, bounded in
	-- Lua and independently protected so diagnosis cannot replace the failure.
	pcall(function()
		local groups = env.api.engine.util.line.getDetailedLineProblems(line)
		local notes = {}
		for i = 1, math.min(#groups, 64) do
			for j = 1, math.min(#groups[i], 64) do
				local problem, why = groups[i][j], nil
				if problem.noPath then why = "no path"
				elseif problem.noPathFromAlternative and #problem.noPathFromAlternative > 0 then why = "no path from alternative"
				elseif problem.noPathToAlternative and #problem.noPathToAlternative > 0 then why = "no path to alternative"
				elseif problem.incompatibleStop then why = "incompatible stop"
				elseif problem.duplicateStop then why = "duplicate stop"
				elseif problem.empty then why = "less than two stops and no vehicles" end
				-- Native GUI calls this segment -> waypoint -> problem, not a flat
				-- list of station stops. Waypoints must not acquire wrong stop labels.
				if why then notes[#notes + 1] = "segment " .. (i - 1) .. " point " .. (j - 1) .. ": " .. why end
				if #notes == 2 then break end
			end
			if #notes == 2 then break end
		end
		if #notes > 0 then detail = detail .. "; line problems: " .. table.concat(notes, ", ") end
	end)
	return detail
end

function main.send_vehicle_command(env, e, ids, line, state, confirmed, jump_depot)
	local cmd = env.api.cmd
	local c, id = nil, ids[1]
	if e.command == "reverse" then c = cmd.makeVehicleReverseCmd(id)
	elseif e.command == "stopped" then c = cmd.makeVehicleSetStoppedByUserCmd(id, e.value == true)
	elseif e.command == "depot" then
		if jump_depot ~= nil then c = cmd.makeVehicleSendToDepotCmd(id, e.value == true, jump_depot)
		else c = cmd.makeVehicleSendToDepotCmd(id, e.value == true) end
	elseif e.command == "line" then c = cmd.makeVehicleSetLineCmd(id, line, e.stop or 0)
	elseif e.command == "sell" then c = cmd.makeVehicleSellCmd(ids)
	else error("unknown vehicle command " .. tostring(e.command)) end
	local name = main.entry_name(e)
	cmd.sendCommand(c, function(_, success)
		logger.info("vehicle " .. name .. (success == false and " REJECTED by the game" or " done"))
		if success == false and e.command == "line" then
			local reason = main.vehicle_line_failure(env, id, line, e.stop or 0)
			logger.info("vehicle " .. name .. ": " .. reason)
			if state then transport.fail(state, reason); return true end
		elseif success == true and confirmed then confirmed() end
	end)
end

--- The entries of a vehicle_command line (v35 lines carry one command at the top level).
function main.vehicle_entries(action)
	if type(action.commands) == "table" then return action.commands end
	return { { command = action.command, target = action.target, value = action.value } }
end

--- At the common tick (scheduled replay of the planned line), in both games. All targets are
-- found before anything runs.
function main.run_vehicle_command(env, state, action)
	local role = sync.role(env.os and env.os.getenv)
	local own = action.origin == role
	local s = state:get() or {}
	local entries, found = main.vehicle_entries(action), {}
	for i, e in ipairs(entries) do
		assert(actions.VEHICLE_COMMANDS[e.command], "unknown vehicle command")
		local ids, line, jump_depot = main.vehicle_ids(env, s, e, own)
		found[i] = { ids = ids, line = line, jump_depot = jump_depot }
	end
	for i, e in ipairs(entries) do
		local f = found[i]
		local line_ref = f.line and f.line >= 0 and actions.line_ref(env, f.line) or nil
		logger.info("vehicle " .. main.entry_name(e) .. " at the common tick")
		main.send_vehicle_command(env, e, f.ids, f.line, state, function()
			-- A rejected assignment must not be recorded as applied: the next poll
			-- would otherwise send a spurious opposite action from the old state.
			local live = state:get() or {}
			for _, id in ipairs(f.ids) do actions.vehicle_command_done(live, id, e.command, e.value, line_ref, e.stop) end
			state:set(live)
		end, f.jump_depot)
	end
	return true
end

--- Wait for earlier replay targets by elapsed time, independent of GUI heartbeat
-- frequency or overlapping simulation updates. Without a readable timer retain
-- the old bounded step fallback. A known-missing target still ends in a report.
main.INTENT_WAIT_STEPS = 16
main.INTENT_WAIT_SECONDS = 4
function main.intent_wait_pending(env, wait)
	wait.n = (wait.n or 0) + 1
	local now, source
	for _, key in ipairs({ "time", "clock" }) do
		local ok, value = pcall(function() return env.os[key]() end)
		if ok and type(value) == "number" and value == value and math.abs(value) < math.huge then
			now, source = value, key; break
		end
	end
	if now and wait.since == nil then wait.since, wait.timer = now, source end
	if now and source == wait.timer and now >= wait.since then
		-- Even a broken/stationary clock cannot leave this hold without a bound.
		return now - wait.since < main.INTENT_WAIT_SECONDS and wait.n <= 400
	end
	return wait.n <= main.INTENT_WAIT_STEPS
end

function main.intent_ready(env, s, intent, role)
	if type(intent.line) ~= "string" or intent.line:sub(1, 3) ~= "A1 " then return true end
	local action = actions.decode(intent.line)
	if not action or action.op ~= "vehicle_command" then return true end
	if s.action_busy or (s.action_work and #s.action_work > 0) or (s.action_inbox and #s.action_inbox > 0) then
		return false, "earlier actions are still being replayed"
	end
	for _, e in ipairs(main.vehicle_entries(action)) do
		local ok, err = pcall(main.vehicle_ids, env, s, e, intent.origin == role)
		if not ok then return false, main.error_text(err) end
	end
	return true
end

--- v37: in a session with a partner (host or client with the host's ordering, which the DLL turns
-- on only between two PCs) a replay that fails here is skipped and the session carries on
-- (transport.check); 'Allein testen' and the local tests ('Gastgeber simulieren', same spot) keep FAIL.
function main.skip_failures(env)
	local ok, skip = pcall(function()
		local role = sync.role(env.os.getenv)
		return (role == "host" or role == "client") and env.os.getenv("TF3MP_ORDERING") == "1"
	end)
	return ok and skip == true
end

function main.check_network(state)
	transport.check(state, function(text)
		local issue = text:match("^action issue local (I1 .+)$")
		if issue then
			logger.info(text)
			if main.skip_failures(_G) then
				local live = state:get() or {}
				transport.send(issue, live, logger.info); state:set(live)
			end
			return
		end
		local origin, seq, result = text:match("^net result scheduled_(%a+)%.(%d+) (%a+)")
		if seq then
			local s = state:get() or {}
			if s.timeline then timeline.complete(s.timeline, tonumber(seq), result == "OK"); state:set(s) end
			logger.info("timeline result " .. origin .. "." .. seq .. " " .. result)
		else logger.info(text) end
	end, main.skip_failures(_G))
	main.publish_network_work(state, false)
end

function main.timeline_tick(env, state)
	local getenv = env.os and env.os.getenv
	local role = sync.role(getenv)
	if (role ~= "host" and role ~= "client") or getenv("TF3MP_ORDERING") ~= "1" then return end
	local now = main.game_time(env)
	-- An unreadable clock is skipped, never taken as a timeline failure (that would hold both games).
	if not now then return end
	local s = main.loaded_state(env, state)
	local m = main.timeline_of(s, role)
	local peer = sync.decode(getenv("TF3MP_PEER_CLOCK"))
	-- Purchases/line edits must enter the reliable FIFO before a command that
	-- references them. Drain a bounded batch, also while the game is paused.
	for _ = 1, 8 do
		local outgoing = actions.next_line(s)
		if not outgoing then break end
		transport.send(outgoing, s, logger.info)
	end
	local own_gui, peer_gui = sync.decode(getenv("TF3MP_OWN_GUI")), sync.decode(getenv("TF3MP_PEER_GUI"))
	local speed_ok, speed_now = pcall(sync.read_speed, env)
	local intent = timeline.step(m, now, peer and tonumber(peer.gt), {
		paused = (own_gui and own_gui.speed == 0) or (peer_gui and peer_gui.speed == 0),
		dependencies = actions.next_line_waiting(s),
		stopped = not own_gui or (speed_ok and speed_now == 0),
	})
	local clock = timeline.clock(m)
	local raw = sync.encode(clock)
	if (not m.published or m.published_phase ~= clock.phase or m.active or m.error or (s.updates or 0) % 5 == 0)
		and m.published ~= raw then
		-- RELEASE must clear the GUI hold immediately, even if update() is stopped
		-- and its persisted counter will never reach the next multiple of five.
		m.published, m.published_phase = raw, clock.phase
		logger.info(main.STATE_MARKER .. "clock " .. raw)
	end
	if m.error and not m.error_logged then
		m.error_logged = true; logger.info("timeline stopped: " .. m.error)
		logger.info(main.STATE_MARKER .. "health ck=" .. (s.sync and s.sync.own_k or 0) .. " status=diff fields=clock")
	end
	local line = not actions.next_line_waiting(s) and timeline.take_batch(m)
	-- Save before any engine command: its callback can replace the live receipt/timeline.
	state:set(s)
	if line then
		transport.send(line, s, logger.info)
		local live = state:get() or {}
		live.transport_seq = math.max(live.transport_seq or 0, s.transport_seq or 0)
		state:set(live)
	end
	-- Let the GUI mark its automatic hold before sending PAUSE. Pausing here
	-- first could make the GUI publish that transient 0 as a new user choice
	-- during the DLL's stdout/clock-echo delay. Keep the old fallback without GUI.
	if clock.hold == 1 and not own_gui then sync.set_speed(env, 0) end
	if intent then
		local live = state:get() or {}
		-- Another replay is still running: stay held at the barrier and execute on a later step.
		if live.network_work then timeline.retry(live.timeline); state:set(live); return end
		local ready, why = main.intent_ready(env, live, intent, role)
		local wait = live.timeline.wait
		if not ready then
			if not wait or wait.seq ~= intent.seq then
				wait = { seq = intent.seq, n = 0 }; live.timeline.wait = wait
				logger.info("timeline " .. intent.origin .. "." .. intent.seq .. " waits: " .. tostring(why):sub(1, 160))
			end
			if main.intent_wait_pending(env, wait) then timeline.retry(live.timeline); state:set(live); return end
			logger.info("timeline " .. intent.origin .. "." .. intent.seq .. " waited too long, running it anyway")
		end
		live.timeline.wait = nil
		logger.info("timeline execute " .. intent.origin .. "." .. intent.seq .. " at gt=" .. tostring(intent.gt) ..
			" (stamp " .. intent.at .. (intent.barrier and ", ready barrier" or "") .. ")")
		local token = "scheduled_" .. intent.origin .. "." .. intent.seq
		if not main.send_replay_event(env, { line = intent.line, number = token, offset = 0, source = "scheduled",
			schedule_seq = intent.seq, schedule_at = intent.barrier and intent.gt or intent.at }) then
			live = state:get() or live
			timeline.reject(live.timeline, "common execution event unavailable"); state:set(live)
		end
	end
end

-- GUI sends this event while paused, when simulation update() no longer runs.
-- Also observe purchases/line edits while idle, so they can precede a paused assignment.
function main.paused_network_tick(env, state)
	local getenv = env.os and env.os.getenv
	local role = sync.role(getenv)
	if (role ~= "host" and role ~= "client") or getenv("TF3MP_ORDERING") ~= "1" then return end
	main.loaded_state(env, state)
	local wrapped = transport.env(env, state)
	-- v37: a failing step fails only this replay, as in handleEvent's network_continue.
	local ok_run, err_run = pcall(main.network_run, wrapped, state)
	if not ok_run then transport.fail(state, main.error_text(err_run)) end
	local s = state:get() or {}
	if actions.has_work(s) then
		local ok, err = pcall(actions.tick, wrapped, state, transport.action_log(state, logger.info))
		if not ok then transport.fail(state, main.error_text(err)) end
	end
	s = state:get() or {}
	if s.weld_checks and #s.weld_checks > 0 then
		local ok, err = pcall(main.recheck_welds, env, s, function(text) transport.fail(state, text) end)
		if not ok then s.weld_checks = nil; transport.fail(state, main.error_text(err)) end
		main.store(state, s)
	end
	main.check_network(state)
	s = state:get() or {}
	s.paused_polls = (s.paused_polls or 0) + 1
	if (not s.actions or s.paused_polls % 4 == 0) and not s.action_busy and not s.network_work
		and not (s.action_work and #s.action_work > 0) then
		local ok, err = pcall(actions.poll, env, s, logger.info, main.ACTION_KINDS)
		if not ok then logger.info("paused action poll failed: " .. main.error_text(err):sub(1, 220)) end
	end
	main.store(state, s)
	if main.bridge_has_work(env, s) then main.bridge_tick(env, 0, s, state, true) end
	main.timeline_tick(env, state)
	main.publish_network_work(state, s.paused_polls % main.BRIDGE_EVERY == 0)
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
		if k ~= (ss.capture_k or ss.own_k) and not ss.world_pending then
			local values, failed, job = sync.values(env, gt, true)
			values.ck = k
			if getenv("TF3MP_ORDERING") == "1" then
				values.econseq = s.timeline and s.timeline.last or 0
				values.econbusy = main.money_busy(s) and 1 or 0
			end
			-- Money this game booked to follow the host (the simulated host in tools\fake-partner.ps1
			-- needs it to keep its own difference).
			if role == "client" then values.adj = ss.adj or 0 end
			ss.capture_k = k
			if job then ss.world_pending = { values = values, failed = failed, job = job }
			else main.sync_publish(ss, values, failed) end
		end
	end
	-- Engine records are captured at one game tick. Only pure-data hashing continues later;
	-- moving positions/cargo must never be re-read across several simulation ticks.
	if ss.world_pending then
		local pending = ss.world_pending
		local hashes, failed, stats, lists = sync.world_step(env, pending.job)
		if hashes then
			for field, value in pairs(hashes) do pending.values[field] = value end
			for _, field in ipairs(failed or {}) do pending.failed[#pending.failed + 1] = field end
			ss.world_lists = ss.world_lists or {}
			ss.world_lists[pending.values.ck] = { gt = pending.values.gt, lists = lists or {} }
			for key in pairs(ss.world_lists) do
				if key <= pending.values.ck - sync.KEEP then ss.world_lists[key] = nil end
			end
			if stats then
				logger.info("world scan ck=" .. pending.values.ck .. " " .. sync.encode(stats))
			end
			main.sync_publish(ss, pending.values, pending.failed)
			ss.world_pending = nil
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

function main.sync_publish(ss, values, failed)
	ss.own, ss.own_k = sync.keep(ss.own, values.ck, values), values.ck
	if #failed > 0 and ss.failed_logged ~= table.concat(failed, ",") then
		ss.failed_logged = table.concat(failed, ",")
		logger.info("sync: checkpoint values unreadable: " .. ss.failed_logged)
	end
	logger.info(main.STATE_MARKER .. "sim " .. sync.encode(values))
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
				local world_status = (out.world_mismatch or out.needs_resync) and "diff" or (out.world_different or 0) > 0 and "checking"
					or (out.world_fields or 0) == #(sync.HASH_FIELDS or {}) and (out.world_fields or 0) > 0 and "same" or "unknown"
				local world_fields = {}
				for _, field in ipairs(sync.HASH_FIELDS or {}) do
					if out.diffs[field] then world_fields[#world_fields + 1] = field end
				end
				if out.needs_resync and out.diffs.loan then world_fields[#world_fields + 1] = "loan" end
				logger.info(main.STATE_MARKER .. "health ck=" .. p.k .. " status=" .. world_status ..
					" fields=" .. (#world_fields > 0 and table.concat(world_fields, ",") or "none"))
				if world_status == "diff" then
					local ok_w, err_w = pcall(main.world_send, env, ss, own, world_fields)
					if not ok_w then logger.info("world list failed: " .. tostring(err_w):sub(1, 200)) end
				end
				main.sync_correct(ss, out.fix, gt, own)
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
main.WORLD_MAX_RECORDS = 128
main.WORLD_MAX_PARTS = 8

-- Diagnostics use the immutable records that produced the compared digest. Never walk the
-- live world again several seconds later, especially for moving vehicles and cargo.
function main.world_send_snapshot(ss, own, field, list)
	local parts, current, size, sent = {}, {}, 0, 0
	local total = list.total or #list
	for i = 1, math.min(#list, main.WORLD_MAX_RECORDS) do
		local r = list[i]
		local description = tostring(r.d or ""):sub(1, 320)
		local item = r.h .. ":" .. build.escape(description)
		if size + #item + 1 > main.WORLD_PART_BYTES and #current > 0 then
			parts[#parts + 1] = current; current, size = {}, 0
			if #parts >= main.WORLD_MAX_PARTS then break end
		end
		current[#current + 1] = item; size = size + #item + 1; sent = sent + 1
	end
	if #current > 0 or #parts == 0 then parts[#parts + 1] = current end
	for i, items in ipairs(parts) do
		transport.send(string.format("W2 %s %d %.0f %d %d %s %d %d %s", field, own.ck, own.gt,
			i, #parts, own[field], total, (list.truncated or sent < total) and 1 or 0, #items > 0 and table.concat(items, " ") or "-"), {}, logger.info)
	end
	logger.info(string.format("world list %s ck=%d: %d/%d snapshot records sent%s", field, own.ck,
		sent, total, (list.truncated or sent < total) and " (diagnostic limit)" or ""))
end

function main.world_send(env, ss, own, fields)
	ss.world_sent = ss.world_sent or {}
	for _, field in ipairs(fields) do
		local digest = own[field]
		local kind
		for k, f in pairs(fingerprint.FIELDS) do if f == field then kind = k end end
		if kind and digest and ss.world_sent[field] ~= digest then
			ss.world_sent[field] = digest
			local cached = ss.world_lists and ss.world_lists[own.ck]
			local snapshot = cached and cached.gt == own.gt and (cached.lists[field] or cached.lists[kind])
			if snapshot then main.world_send_snapshot(ss, own, field, snapshot)
			elseif own.wgt then
				logger.info("world list " .. field .. ": original checkpoint snapshot unavailable; no fresh live comparison")
			else
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
end

function main.world_receive_snapshot(line, state)
	local field, ck, gt, index, count, digest, total, clipped, rest = line:match(
		"^W2 (%a+) (%d+) (%d+) (%d+) (%d+) (h%d+_%x+) (%d+) ([01]) (.*)$")
	ck, gt, index, count, total = tonumber(ck), tonumber(gt), tonumber(index), tonumber(count), tonumber(total)
	local kind
	for k, f in pairs(fingerprint.FIELDS) do if f == field then kind = k end end
	if not kind or not count or count < 1 or count > main.WORLD_MAX_PARTS or index < 1 or index > count
		or #rest > main.WORLD_PART_BYTES or total > 100000 then
		logger.info("world list: invalid snapshot diagnostic"); return true
	end
	local s = state and (state:get() or {}) or {}
	local cache = s.sync and s.sync.world_lists and s.sync.world_lists[ck]
	local own = cache and cache.gt == gt and (cache.lists[field] or cache.lists[kind])
	if not own then logger.info("world list " .. field .. ": matching snapshot unavailable, skipped"); return true end
	s.world_rx = s.world_rx or {}
	local key = field .. ":" .. ck .. ":" .. gt .. ":" .. digest
	local rx = s.world_rx[field]
	if not rx or rx.key ~= key then rx = { key = key, count = count, total = total, clipped = clipped, parts = {}, got = 0 }; s.world_rx[field] = rx end
	if rx.count ~= count or rx.total ~= total or rx.clipped ~= clipped then return true end
	if rx.parts[index] then return true end
	rx.parts[index] = rest; rx.got = rx.got + 1
	if rx.got == count then
		local here, there, descriptions = {}, {}, {}
		for _, r in ipairs(own) do here[r.h] = (here[r.h] or 0) + 1 end
		local received = 0
		for i = 1, count do
			for item in rx.parts[i]:gmatch("%S+") do
				local h, d = item:match("^(%x+):(.*)$")
				if h then
					received = received + 1
					if received > main.WORLD_MAX_RECORDS then s.world_rx[field] = nil; if state then state:set(s) end; return true end
					there[h] = (there[h] or 0) + 1; descriptions[h] = build.unescape(d)
				end
			end
		end
		if received > total or (clipped == "0" and received ~= total) then
			s.world_rx[field] = nil
			if state then state:set(s) end
			logger.info("world list: invalid snapshot record count"); return true
		end
		local only_here, only_there, shown = 0, 0, 0
		for h, n in pairs(there) do
			if not own.truncated and n > (here[h] or 0) then
				only_there = only_there + n - (here[h] or 0)
				if shown < 16 then logger.info("world diff " .. field .. " only in the other snapshot: " .. descriptions[h]); shown = shown + 1 end
			end
		end
		if clipped == "0" then
			for _, r in ipairs(own) do
				if (here[r.h] or 0) > (there[r.h] or 0) then
					only_here = only_here + 1; here[r.h] = here[r.h] - 1
					if shown < 16 then logger.info("world diff " .. field .. " only in this snapshot: " .. r.d); shown = shown + 1 end
				end
			end
		end
		logger.info(string.format("world diff %s ck=%d gt=%.0f: %d only here, %d only there%s", field, ck, gt,
			only_here, only_there, (clipped == "1" and "; remote list truncated, missing remote records are not differences" or "") ..
			(own.truncated and "; local list truncated, missing local records are not differences" or "")))
		s.world_rx[field] = nil
	end
	if state then state:set(s) end
	return true
end

--- Handles a W1 line from the other game (main.world_send): logs the records that differ.
function main.world_receive(env, line, state)
	if line:sub(1, 3) == "W2 " then return main.world_receive_snapshot(line, state) end
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
function main.money_busy(s)
	local t, a = s.timeline, s.actions
	return s.action_busy or s.network_work ~= nil or (s.network_handover and s.network_handover.phase ~= "done")
		or (s.action_work and #s.action_work > 0)
		or (s.action_inbox and #s.action_inbox > 0)
		or (a and a.queue and #a.queue > 0)
		or (t and (t.active or (t.queue and #t.queue > 0) or (t.pending_requests or 0) > 0)) or false
end

function main.sync_correct(ss, fix, gt, own)
	if not (fix.loan or fix.money or fix.date) then return end
	if fix.loan then logger.info("sync: loan differs by " .. fix.loan .. " from the host's, booking it") end
	if fix.money then logger.info("sync: money differs by " .. fix.money .. " from the host's, booking it") end
	if fix.date then logger.info("sync: date differs by " .. fix.date .. " day(s) from the host's, moving it") end
	ss.pending_fix = { loan = fix.loan, money = fix.money, date = fix.date, gt = gt,
		seq = own and own.econseq, adj = own and own.adj }
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
		fix_date = fix.date, fix_gt = fix.gt, fix_seq = fix.seq, fix_adj = fix.adj })
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
	local function settle(field, amount, success, evidence)
		local live = state:get() or {}
		local ss = live.sync
		if type(ss) ~= "table" then return end
		local outcome = sync.settle_fix(ss, field, amount, success, evidence)
		if outcome == "no_effect_stopped" then
			logger.info("sync: three consecutive money bookings left the observed account unchanged; money is no longer corrected")
		elseif outcome == "no_effect" then
			logger.info("sync: money booking callback left the observed account unchanged; awaiting a fresh checkpoint")
		end
		state:set(live)
	end
	local function correct(field, label, send)
		local amount = tonumber(fix["fix_" .. field])
		if not amount then return end
		local live = state:get() or {}; local rebased = live.sync and live.sync.money_rebased_gt
		if field == "money" and live.sync and
			((fix.fix_seq ~= nil and (main.money_busy(live) or (live.timeline and live.timeline.last or 0) ~= fix.fix_seq))
			or (fix.fix_adj ~= nil and (live.sync.adj or 0) ~= fix.fix_adj)) then
			-- Leave correction enabled, but require fresh matching checkpoints.
			if live.sync.fixes then live.sync.fixes.money = nil end
			if live.sync.last then live.sync.last.money_compatible = false end
			state:set(live)
			logger.info("sync: skipped stale money correction after player action or balance alignment"); return
		end
		if field == "money" and rebased and tonumber(fix.fix_gt) and fix.fix_gt <= rebased then
			logger.info("sync: skipped money correction captured before subsidy balance alignment"); return
		end
		local ok, sent, notes = pcall(send, amount, function(_, success, evidence)
			logger.info("sync: " .. label .. " " .. amount .. ", success=" .. tostring(success) ..
				(success == false and ("; " .. field .. " is no longer corrected") or ""))
			local ok_s, err_s = pcall(settle, field, amount, success, evidence)
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
	local common = sync.decode(getenv("TF3MP_OWN_CLOCK"))
	local own_menu = sync.decode(getenv("TF3MP_OWN_MENU"))
	local peer_menu = sync.decode(getenv("TF3MP_PEER_MENU"))
	if getenv("TF3MP_ORDERING") == "1" and ((own_menu and own_menu.open == 1) or (peer_menu and peer_menu.open == 1)) then
		sync.set_speed(env, 0)
		return
	end
	if common and (common.hold == 1 or (common.phase == "failed" and tonumber(common.at) and common.at > 0) or
		(tonumber(common.at) and common.at > 0 and gt >= common.at and common.phase ~= "idle")) then
		-- The shared speed register describes the user's speed, not this temporary barrier.
		sync.set_speed(env, 0)
		return
	end
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
	local speed, calendar = sync.read_speed(env)
	local out = sync.speed_step(ss.speed_mem, {
		own = speed, calendar = calendar, own_t = gt, role = role, peer = sync.decode(getenv("TF3MP_PEER_GUI")),
		max_speed = sync.maximum_speed(env), ordered = getenv("TF3MP_ORDERING") == "1",
		now = clock(), hold = false, src = "sim", restore = own_gui,
	})
	for _, line in ipairs(out.logs) do logger.info("sync " .. line) end
	if out.command then
		local target = out.command
		-- No result callback: update() may not have one (run 25).
		sync.set_speed(env, target)
	end
	if out.publish then logger.info(main.STATE_MARKER .. "gui " .. out.publish) end
	if out.calendar_command ~= nil then sync.set_calendar(env, out.calendar_command) end
end

--- Once per savegame and version: how the game's journal entries look (read only). Nothing is
-- booked here: a booking the engine rejects with an assertion could end the game, and this test
-- would then run again on every load, because the savegame never got to keep the mark.
function main.journal_test(env)
	local ok, text = pcall(sync.describe_journal, env)
	logger.info("journal: " .. (ok and text or ("unreadable " .. main.error_text(text))))
end

--- GUI script (main.gs.lua): runs on every frame, also while the game is paused.
function main.guiUpdate(_user_params, _state, gui_state)
	gui.update(_G, gui_state)
end

--- GUI events (main.gs.lua, probe v33): what TF3's tools announce before they execute
-- (hold.lua). Never lets an error reach the game's UI; nil means no objection.
function main.guiHandleEvent(_user_params, _state, _gui_state, src, id, name, param)
	local ok, result = pcall(hold.event, _G, src, id, name, param, _gui_state)
	if ok then return result end
	logger.info("gui event failed: " .. main.error_text(result):sub(1, 200))
	return nil
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

--- A successful native build can still fail capture before it ever reaches the partner.
-- Report that separately from live execution receipts: no fake ACK may advance their queue.
-- Use the caller's state copy so the post-build bookkeeping cannot overwrite this diagnostic.
function main.capture_issue(env, s, param, reason)
	s.capture_issue_seq = (s.capture_issue_seq or 0) + 1
	local token = "capture_" .. tostring(sync.role(env.os and env.os.getenv)) .. "." .. s.capture_issue_seq
	local label = "Bau nicht übertragen"
	pcall(function()
		local con = (param[1].toAdd or {})[1]
		if con and type(con.name) == "string" and con.name ~= "" then label = label .. ": " .. con.name end
		local node = (param[1].proposal.addedNodes or {})[1]
		local p = node and node.comp.position
		if p then label = label .. string.format(" bei %.1f, %.1f", p.x, p.y) end
	end)
	local temporary = {}; local receipt = { get = function() return temporary end, set = function(_, v) temporary = v end }
	transport.begin(receipt, token); transport.describe(receipt, label); transport.fail(receipt, reason)
	-- The original build already happened on the sending PC, so this is a partial result.
	temporary.network_work.sent = 1
	transport.dispatched(receipt)
	transport.check(receipt, function(text)
		local issue = text:match("^action issue local (I1 .+)$")
		if issue then
			logger.info(text)
			if main.skip_failures(env) then transport.send(issue, s, logger.info) end
		end
	end, true)
end

--- Serialises a player build and logs the line. The line is what a second game would receive;
-- it is kept in the savegame state so a replay test can rebuild it later.
function main.capture_build(state, s, param, label)
	local env = _G
	local cons = s.constructions or {}
	local opts = {
		node_position = function(id) return world.node_position(env, id) end,
		node_degree = function(id)
			if not world.node_position(env, id) then return nil end
			local list = env.api.engine.system.streetSystem.getNodeSegments(id)
			return list and #list or nil
		end,
		segment_ends = function(id) return world.edge_ends(env, id) end,
		to_add = param[1].toAdd,
		to_remove = param[1].toRemove,
		construction = function(id) return cons[tostring(id)] end,
		edge_structure = function(comp) return world.edge_structure(env, comp) end,
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
		main.capture_issue(env, s, param, "build capture failed: " .. main.error_text(line))
		state:set(s)
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
			main.capture_issue(env, s, param, string.format("build capture too long: %d characters, limit %d", #line, main.MAX_LINE))
			state:set(s)
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
			-- Fields are industry modules. Their automatic replacement must retain the old
			-- construction too, otherwise a station over a field duplicates its industry.
			local info = world.construction_info(env, ids[i])
			if info and (world.is_player_owned(env, ids[i]) or info.file:match("^::/industries/")) then
				s.constructions[tostring(ids[i])] = info
			end
		end
	end)
end

function main.handleEvent(_user_params, state, src, id, name, param)
	main.loaded_state(_G, state)
	if name == "mp_probe_economy" and id == "mp_probe_economy" then
		local ok, err = pcall(main.economy_intent, _G, state, param)
		if not ok then main.economy_issue(_G, state, "Unternehmen/Subvention", main.error_text(err)) end
		return
	end
	if name == "mp_probe_vehicle" then
		local ok, err = pcall(main.vehicle_intent, _G, state, param)
		if not ok then
			main.economy_issue(_G, state, "Fahrzeugbefehl vorbereiten", main.error_text(err):sub(1, 240))
		end
		return
	end
	if name == "mp_probe_reverse" then
		-- v35: the player clicked "Reverse" (hold.lua); the next action poll sends it.
		local ok, err = pcall(function()
			local s = state:get() or {}
			actions.note_reverse(s, type(param) == "table" and param.vehicle or nil)
			state:set(s)
		end)
		logger.info("reverse clicked for vehicle " .. tostring(type(param) == "table" and param.vehicle) ..
			(ok and "" or (": " .. main.error_text(err):sub(1, 160))))
		return
	end
	if name == "mp_probe_schedule" or id == "mp_probe_schedule" then
		local ok, err = main.submit_intent(_G, state, param)
		if not ok then logger.info("timeline intent rejected: " .. tostring(err)) end
		return
	end
	if main.is_replay_event(src, id, name) then
		if type(param) == "table" and param.timeline_tick then
			local ok, err = pcall(main.paused_network_tick, _G, state)
			if not ok then
				local live = state:get() or {}
				if live.timeline then timeline.reject(live.timeline, main.error_text(err)); state:set(live) end
				logger.info("paused network tick failed: " .. main.error_text(err):sub(1, 240))
			end
			return
		end
		if type(param) == "table" and param.network_continue then
			local env = transport.env(_G, state)
			local ok, err = pcall(main.network_continue, env, state)
			if ok then ok, err = pcall(main.network_run, env, state) end
			if not ok then transport.fail(state, err) end
			main.check_network(state)
			return
		end
		if type(param) == "table" and param.sync_fix then
			local ok, err = pcall(main.sync_apply, _G, state, param)
			if not ok then logger.info("sync correction failed: " .. main.error_text(err):sub(1, 240)) end
			return
		end
		if type(param) == "table" and param.economy_money then
			local ok, err = pcall(main.economy_apply, _G, state, param)
			if not ok then main.economy_issue(_G, state, "Subvention: Geld an Gastgeber angleichen", main.error_text(err)) end
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
			main.check_network(state)
			return
		end
		local line = type(param) == "table" and param.line or nil
		local number = type(param) == "table" and param.number or nil
		local distance = type(param) == "table" and tonumber(param.offset) or nil
		local durable = type(param) == "table" and param.handover_id ~= nil
		if durable then
			local reason
			line, reason = transport.start_handover(state, param)
			if not line then
				logger.info("net handover " .. tostring(number):sub(1, 120) .. ": ignored " .. tostring(reason) .. " event")
				return
			end
			distance = reason -- start_handover returns the persisted replay offset on success.
		end
		logger.info("replay event received (src=" .. tostring(src) .. " id=" .. tostring(id) .. ", line " ..
			(line and (#line .. " characters") or "missing") .. ")")
		if not line then
			-- The parameter did not come through; fall back to the script state.
			local s = state:get() or {}
			line = s.last_build
		end
		local network = type(param) == "table" and param.source ~= nil
		if type(param) == "table" and param.schedule_seq and (main.game_time(_G) or -1) < param.schedule_at then
			local live = state:get() or {}
			if live.timeline then timeline.reject(live.timeline, "engine event missed the common tick"); state:set(live) end
			logger.info("timeline execution rejected after its tick"); return
		end
		if network and not durable then
			local live = state:get() or {}
			if live.network_done and live.network_done.token == tostring(number) then
				logger.info("net result " .. tostring(number) .. " " .. live.network_done.result)
				return
			end
			-- v37: a common-tick command that meets another replay still running is executed again
			-- on a later step (both games stay held); returning without that left it hanging for good.
			local busy = live.network_work and live.network_work.dispatched
			if busy or not transport.begin(state, tostring(number)) then
				live = state:get() or {}
				local other = live.network_work and live.network_work.token ~= tostring(number)
				local a = live.timeline and live.timeline.active
				if other and type(param) == "table" and param.schedule_seq and a and a.seq == param.schedule_seq then
					timeline.retry(live.timeline); state:set(live)
					logger.info("timeline execution of " .. tostring(number) .. " waits for replay " ..
						tostring(live.network_work.token) .. " before it")
				end
				return
			end
		end
		if network then transport.describe(state, "Aktion " .. tostring(line and line:sub(1, 2) or "unbekannt")) end
		local env = transport.env(_G, state)
		-- Keep the exact incoming build once, so a missing rail connection can be reproduced
		-- offline. The bridge preview truncates it; duplicate deliveries return above.
		if network and type(line) == "string" and line:match("^B%d+ ") then
			logger.info("replay input " .. tostring(number) .. " " .. line)
		end
		local ok, applied, err = pcall(main.replay_line, env, line, number, state, distance)
		if network then
			if not ok or not applied then transport.fail(state, ok and (err or "replay failed") or applied)
			else
				local ok_run, err_run = pcall(main.network_run, env, state)
				if not ok_run then transport.fail(state, err_run) end
			end
			transport.dispatched(state); main.check_network(state)
		elseif not ok then logger.info("replay failed: " .. main.error_text(applied)) end
		return
	end
	-- The base game's Loan script owns repayment schedules. Capture its player events,
	-- never infer another loan request from its automatic monthly account movements.
	local role = sync.role(_G.os and _G.os.getenv)
	if (role == "host" or role == "client") and actions.capture_loan then
		local ok, captured = pcall(actions.capture_loan, _G, state, src, id, name, param, logger.info)
		if not ok then logger.info("loan capture failed: " .. main.error_text(captured):sub(1, 200))
		elseif captured then return end
	end
	local s = state:get() or {}
	if name == "handleLegacy" then
		logger.info("net reload")
		-- A native callback or an event in flight cannot survive a game reload.
		-- Observe the loaded save anew; don't execute persisted, stale UI operations.
		main.reset_loaded_runtime(s)
		logger.info(main.STATE_MARKER .. "work token=- phase=idle pending=0")
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

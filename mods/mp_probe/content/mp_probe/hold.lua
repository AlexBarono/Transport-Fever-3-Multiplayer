--- Holding a player's build BEFORE TF3 executes it, so that both games build it at a common tick
-- (timeline.lua). Capturing after the fact can only replay an action late.
--
-- TF3's own game scripts show the hook (base/content/game_mechanics.zip, company.script.tl): the
-- native build tools fire guiHandleEvent "builder.proposalCreate", "builder.proposalPrepareForApply"
-- and "builder.proposalApply" with param {proposal, data} to every game script that subscribed to
-- them (main.SUBSCRIBED_EVENTS), and a script refuses a build by returning { errorMessages = {...} }.
-- v33 did not subscribe, so its probe saw no events (run 36).
--
-- v34, in a session (host or client, DLL v12 ordering):
--   proposalPrepareForApply: serialize the proposal like the capture does (build.lua), refuse it
--   and keep the line in the GUI script state. If TF3 applies it anyway (proposalApply of the same
--   proposal), holding is switched off and the build travels as before.
--   guiUpdate, HELD_WAIT_S later: hand the line to the simulation as "mp_probe_schedule" with
--   held=true. The timeline gives it a common stamp; both games pause there and build it.
--   If the timeline fails or does not plan it within GIVE_UP_S, holding is switched off.
-- 'Allein testen' (loopback): the first build is refused once and re-sent by the mod REISSUE_S
-- later, to show in one minute whether refusing holds a build.
-- @module mp_probe.hold
local logger = require("/mp_probe/logger.lua")
-- Load dependencies while TF3 still resolves paths inside this mod. A require during a GUI
-- callback can resolve against ::/ instead (v40 VPN run: build.lua not found on every build).
local build = require("/mp_probe/build.lua")
local world = require("/mp_probe/world.lua")
local sync = require("/mp_probe/sync.lua")
local wire = require("/mp_probe/wire.lua")

local hold = {}

--- Distinct GUI events logged per Lua state.
hold.MAX_EVENTS = 40
--- Builder events logged in full (with counts) per Lua state.
hold.MAX_BUILDS = 12
--- Real seconds between the refused build and the mod's own copy of it ('Allein testen').
hold.REISSUE_S = 2
--- Real seconds a held build waits for a proposalApply that would show the refusal did not hold.
hold.HELD_WAIT_S = 0.3
--- Real seconds a handed-over build may wait for its common stamp before holding is switched off.
hold.GIVE_UP_S = 30
--- Largest line the timeline carries (timeline.MAX_PAYLOAD).
hold.MAX_LINE = 120000
--- Shown in TF3 as the reason the build was refused.
hold.TEST_TEXT = "TF3MP-Test: Bau einmal zurückgehalten, er erscheint gleich von selbst"
hold.SYNC_TEXT = "TF3MP: wird gleich auf beiden PCs gleichzeitig gebaut"

local memories = setmetatable({}, { __mode = "k" })
local function memory(env)
	local m = memories[env]
	if not m then
		m = { events = {}, event_count = 0, builds = 0 }
		-- Without TF3's GUI script state (older callers), keep the shared data in this Lua state.
		local value = {}
		m.fallback = { get = function() return value end, set = function(_, v) value = v end }
		memories[env] = m
	end
	return m
end

local function count(fn)
	local ok, n = pcall(fn)
	return ok and tostring(n) or "?"
end

--- Short description of a builder event's proposal; also identifies it between two events.
function hold.describe_proposal(param)
	local p = type(param) == "table" and param[1] or nil
	local d = type(param) == "table" and param[2] or nil
	return "segments=" .. count(function() return #p.proposal.addedSegments end) ..
		" removed=" .. count(function() return #p.proposal.removedSegments end) ..
		" constructions=" .. count(function() return #p.toAdd end) ..
		" demolished=" .. count(function() return #p.toRemove end) ..
		" critical=" .. count(function() return d.errorState.critical end) ..
		" cost=" .. count(function() return d.costs end)
end

local function getenv(env, key)
	local ok, value = pcall(function() return env.os.getenv(key) end)
	return ok and value or nil
end

--- The GUI script state TF3 hands to guiUpdate and guiHandleEvent (plain data only). It is the
-- one place both are sure to share, even if they run in different Lua states.
local function shared(gui_state)
	if not gui_state then return {} end
	local ok, value = pcall(function() return gui_state:get() end)
	return ok and type(value) == "table" and value or {}
end
local function store(gui_state, value)
	if gui_state then pcall(function() gui_state:set(value) end) end
end

--- Real time in seconds (os.clock), or a frame count.
function hold.clock(env, m)
	local ok, t = pcall(function() return env.os.clock() end)
	if ok and type(t) == "number" then return t end
	m.frames = (m.frames or 0) + 1
	return m.frames / 60
end

--- The proposal as a B5 line, read like main.capture_build does, but before TF3 executes it:
-- demolished constructions still exist, so they are read from the engine directly.
-- @return line or nil, error text
function hold.serialize(env, p)
	local opts = {
		node_position = function(id) return world.node_position(env, id) end,
		segment_ends = function(id) return world.edge_ends(env, id) end,
		to_add = p.toAdd,
		to_remove = p.toRemove,
		construction = function(id) return world.construction_info(env, id) end,
		edge_object = function(id, from_proposal) return world.edge_object_info(env, id, from_proposal) end,
		read_transf = function(t) return build.read_transf(t) end,
	}
	local ok, line, info = pcall(build.serialize, p.proposal, opts)
	if not ok then return nil, tostring(line):sub(1, 200) end
	if #info.dropped > 0 then return nil, "the line would leave out " .. table.concat(info.dropped, ", ") end
	if info.segments + info.removed_segments + info.constructions + info.demolished + (info.node_configs or 0) == 0 then
		return nil, "nothing to build"
	end
	if #line > hold.MAX_LINE then return nil, "line too long (" .. #line .. " characters)" end
	return line
end

--- A session whose partner is there: the DLL empties TF3MP_PEER_CLOCK once the partner falls silent,
-- and without a partner nobody could plan the common stamp, so nothing is held then.
local function session(env)
	local role = getenv(env, "TF3MP_ROLE")
	local peer = getenv(env, "TF3MP_PEER_CLOCK")
	return (role == "host" or role == "client") and getenv(env, "TF3MP_ORDERING") == "1"
		and type(peer) == "string" and peer:find("gt=", 1, true) ~= nil
end

--- guiHandleEvent (main.gs.lua). nil means no objection.
function hold.event(env, src, id, name, param, gui_state)
	local m = memory(env)
	local key = tostring(id) .. "/" .. tostring(name)
	if not m.events[key] and m.event_count < hold.MAX_EVENTS then
		m.events[key] = true
		m.event_count = m.event_count + 1
		logger.info("gui event " .. key .. " (src=" .. tostring(src) .. ", param " .. type(param) .. ")")
	end
	if type(name) ~= "string" or name:sub(1, 16) ~= "builder.proposal" then return nil end
	local described = hold.describe_proposal(param)
	if m.builds < hold.MAX_BUILDS then
		m.builds = m.builds + 1
		logger.info("gui " .. name .. ": " .. described)
	end
	local critical = false
	pcall(function() critical = param[2].errorState.critical == true end)
	local usable = not critical and type(param) == "table" and param[1] ~= nil
	gui_state = gui_state or m.fallback
	local g = shared(gui_state)

	if name == "builder.proposalApply" then
		local h = g.held
		if h and not h.sent and h.key == described then
			-- TF3 built it although it was refused: refusing does not hold builds here.
			g.held, g.hold_off = nil, "TF3 applied a refused build"
			store(gui_state, g)
			logger.info("hold: TF3 applied the held build anyway; holding is off, builds travel as before")
		end
		local test = m.test
		if test and not test.done then
			test.applied = true
			logger.info("hold test: TF3 applied the refused build anyway (proposalApply arrived); nothing is sent again")
		end
		return nil
	end
	if name ~= "builder.proposalPrepareForApply" or not usable then return nil end

	if session(env) then
		if g.hold_off or g.held then return nil end
		local line, err = hold.serialize(env, param[1])
		if not line then
			logger.info("hold: build not held (" .. tostring(err) .. "); it travels as before")
			return nil
		end
		g.held = { line = line, key = described, at = hold.clock(env, m) + hold.HELD_WAIT_S }
		store(gui_state, g)
		logger.info("hold: build held for a common tick (" .. described .. ", " .. #line .. " characters)")
		return { errorMessages = { [hold.SYNC_TEXT] = true } }
	end

	if getenv(env, "TF3MP_ROLE") == "loopback" and not g.tested then
		-- The engine may reuse its proposal after the event; keep a copy (Proposal.clone).
		local ok_c, copy = pcall(function() return env.api.type.Proposal.clone(param[1]) end)
		if not ok_c or copy == nil then
			logger.info("hold test: Proposal.clone unavailable (" .. tostring(copy):sub(1, 100) .. "), keeping the original")
			copy = param[1]
		end
		m.test = { proposal = copy, at = hold.clock(env, m) + hold.REISSUE_S, applied = false }
		g.tested, g.test_pending = true, true
		store(gui_state, g)
		logger.info("hold test: refusing this build once at proposalPrepareForApply (" .. described .. ")")
		return { errorMessages = { [hold.TEST_TEXT] = true } }
	end
	return nil
end

--- Hands a held build to the simulation (main.submit_intent) as a script event.
function hold.submit(env, line)
	local cmd = env.api.cmd
	cmd.sendCommand(cmd.makeScriptingSendEventCmd("mp_probe", "mp_probe_schedule", "mp_probe_schedule",
		{ line = line, held = true }))
end

local function own_clock(env)
	return sync.decode(getenv(env, "TF3MP_OWN_CLOCK")) or {}
end

--- Every GUI step: the vehicle hooks, held builds and the 'Allein testen' check.
function hold.step(env, gui_state)
	local m = memory(env)
	m.gui_state = gui_state
	hold.watch_vehicles(env, m)
	hold.flush_vehicles(env, m)
	local now = hold.clock(env, m)
	gui_state = gui_state or m.fallback
	local g = shared(gui_state)
	local changed = false
	local h = g.held
	if h and not h.sent and now >= h.at then
		local ok, err = pcall(hold.submit, env, h.line)
		if ok then
			g.waiting = { since = now, seq = tonumber(own_clock(env).seq) or 0 }
			logger.info("hold: held build handed over for its common tick")
		else
			g.hold_off = "handing over failed"
			logger.info("hold: handing over the held build failed (" .. tostring(err):sub(1, 160) .. "); it is lost, please build it again")
		end
		g.held = nil
		changed = true
	end
	local w = g.waiting
	if w then
		local clock = own_clock(env)
		if clock.phase == "failed" then
			g.waiting, g.hold_off = nil, "timeline failed"
			logger.info("hold: the common timeline failed; holding is off, builds travel as before")
		elseif (tonumber(clock.seq) or 0) > w.seq then
			g.waiting = nil
		elseif now - w.since > hold.GIVE_UP_S or now < w.since then
			g.waiting, g.hold_off = nil, "no common tick"
			logger.info("hold: no common tick for the held build within " .. hold.GIVE_UP_S .. " s; holding is off")
		end
		changed = changed or g.waiting == nil
	end
	if changed then store(gui_state, g) end

	local test = m.test
	if g.test_pending and not test then
		g.test_pending = nil; store(gui_state, g)
		logger.info("hold test: the refused proposal is not in this Lua state (guiUpdate and guiHandleEvent differ); not sent again")
		return
	end
	if not test or test.done or now < test.at then return end
	test.done = true
	g.test_pending = nil; store(gui_state, g)
	if test.applied then return end
	logger.info("hold test: TF3 did not build the refused proposal; sending it again now")
	local ok, err = pcall(function()
		local cmd = env.api.cmd
		cmd.sendCommand(cmd.makeWorldBuildProposalCmd(test.proposal, nil, false, true), function(_, success)
			logger.info("hold test: the held build was " .. (success and "built" or "REJECTED") .. " when sent again")
		end)
	end)
	if not ok then logger.info("hold test: sending the held build failed: " .. tostring(err):sub(1, 200)) end
	test.proposal = nil
end

--- v35 (run 37): a train turned with "Reverse" did not travel, and a command that runs in one
-- game a moment before the other leaves the vehicles in different places for good. TF3's vehicle
-- windows build these commands with api.cmd.make...Cmd at the moment of the click
-- (gui/entity_window/vehicle/vehicle.tl, gui/line_vehicle_mgmt/manager_window.tl).
-- v36 (run 38): five buses sent onto their line left the depot one replay after the other in the
-- other game. Sending to a line and selling are timed too, and the hooks no longer hand the GUI a
-- different command: each maker returns TF3's own command and marks it; api.cmd.sendCommand (also
-- wrapped) holds a marked command in a session, tells the GUI it succeeded (TF3's own callbacks,
-- e.g. engine_react_util's command counter, must run) and collects it. Commands of one frame (all
-- buses sent to a line at once) go to the simulation as one batch, one common tick for all
-- (main.handleEvent "mp_probe_vehicle"). Outside a session everything passes through.
-- TF3's bindings are callable tables whose metatable cannot be read (run 36/37), so the originals
-- are called as they are.
hold.VEHICLE_COMMANDS = { makeVehicleReverseCmd = "reverse", makeVehicleSetStoppedByUserCmd = "stopped",
	makeVehicleSendToDepotCmd = "depot", makeVehicleSetLineCmd = "line", makeVehicleSellCmd = "sell" }
hold.VEHICLE_HOOKS = 6
--- Most commands in one batch.
hold.MAX_BATCH = 40

--- Whether a vehicle command can go through the simulation now.
function hold.timed(env, m)
	if not session(env) then return false end
	if shared(m.gui_state or m.fallback).hold_off then return false end
	return own_clock(env).phase ~= "failed"
end

--- What a maker's arguments mean for the simulation (plain data), or nil when they cannot travel.
function hold.vehicle_args(command, a, b, c)
	local function id(v) return type(v) == "number" and v >= 0 and v % 1 == 0 end
	if command == "sell" then
		local list = {}
		local ok = pcall(function()
			for i = 1, #a do
				local v = a[i]
				assert(id(v)); list[i] = v
			end
		end)
		if not ok or #list == 0 then return nil end
		return { command = command, vehicles = list }
	end
	if not id(a) then return nil end
	if command == "line" then
		if type(b) ~= "number" or b % 1 ~= 0 then return nil end
		return { command = command, vehicle = a, value = b, stop = id(c) and c or 0 }
	end
	return { command = command, vehicle = a, value = b == true }
end

local function describe(t)
	if t.command == "sell" then return "sell of " .. #t.vehicles .. " vehicle(s)" end
	return t.command .. " for " .. tostring(t.vehicle)
end

function hold.watch_vehicles(env, m)
	if m.vehicle_hooks ~= nil then return end
	m.vehicle_hooks = 0
	m.marked = setmetatable({}, { __mode = "k" })
	m.batch = {}
	local cmd = env.api and env.api.cmd
	local missing = {}
	for maker, command in pairs(hold.VEHICLE_COMMANDS) do
		local ok, err = pcall(function()
			local original = cmd[maker]
			assert(original ~= nil, maker .. " missing")
			local hook = function(a, b, c, ...)
				local made = original(a, b, c, ...)
				local args = hold.vehicle_args(command, a, b, c)
				if args and made ~= nil then pcall(function() m.marked[made] = args end) end
				return made
			end
			cmd[maker] = hook
			assert(cmd[maker] == hook, "api.cmd did not keep the hook")
		end)
		if ok then m.vehicle_hooks = m.vehicle_hooks + 1 else missing[#missing + 1] = tostring(err):sub(1, 100) end
	end
	local ok, err = pcall(function()
		local send = cmd and cmd.sendCommand
		assert(send ~= nil, "sendCommand missing")
		m.send = send
		local hook = function(c, callback, ...)
			local args = c ~= nil and m.marked[c] or nil
			if args then m.marked[c] = nil end
			if args and #m.batch < hold.MAX_BATCH and hold.timed(env, m) then
				m.batch[#m.batch + 1] = { args = args, command = c, callback = callback, at = hold.clock(env, m) }
				logger.info("vehicle " .. describe(args) .. " clicked; both games run it at a common tick")
				if callback then
					-- As if it had run: TF3's windows count their open commands down in the callback.
					local ok_cb, why = pcall(callback, c, true, {})
					if not ok_cb then logger.info("vehicle " .. args.command .. ": the window's callback failed (" .. tostring(why):sub(1, 120) .. ")") end
				end
				return
			end
			local result = send(c, callback, ...)
			if args and args.command == "reverse" then
				local sent, why = pcall(hold.reverse_clicked, env, args.vehicle)
				if not sent then logger.info("reverse: could not tell the simulation (" .. tostring(why):sub(1, 160) .. ")") end
			end
			return result
		end
		cmd.sendCommand = hook
		assert(cmd.sendCommand == hook, "api.cmd did not keep the sendCommand hook")
	end)
	if ok then m.vehicle_hooks = m.vehicle_hooks + 1 else missing[#missing + 1] = tostring(err):sub(1, 100) end
	logger.info("vehicle hooks: " .. m.vehicle_hooks .. " of " .. hold.VEHICLE_HOOKS .. " installed" ..
		(#missing > 0 and (" (" .. table.concat(missing, "; ") .. ")") or ""))
end

--- Every GUI step: hands the collected vehicle commands to the simulation as one script event.
-- If that is impossible, TF3's own commands run here at once and travel as before.
function hold.flush_vehicles(env, m)
	local batch = m.batch
	if not batch or #batch == 0 then return end
	m.batch = {}
	local list = {}
	for i, entry in ipairs(batch) do list[i] = entry.args end
	local ok, err = pcall(function()
		local cmd = env.api.cmd
		local event = cmd.makeScriptingSendEventCmd("mp_probe", "mp_probe_vehicle", "mp_probe_vehicle",
			{ batch = wire.encode(list) })
		assert(event ~= nil, "no script event")
		;(m.send or cmd.sendCommand)(event)
	end)
	if ok then
		logger.info("vehicle commands handed over: " .. #list)
		return
	end
	logger.info("vehicle commands: no script event (" .. tostring(err):sub(1, 120) .. "); running them here now")
	for _, entry in ipairs(batch) do
		local sent, why = pcall(m.send or env.api.cmd.sendCommand, entry.command)
		if not sent then logger.info("vehicle " .. entry.args.command .. " failed: " .. tostring(why):sub(1, 120)) end
		if sent and entry.args.command == "reverse" then pcall(hold.reverse_clicked, env, entry.args.vehicle) end
	end
end

--- The player clicked "Reverse" and it ran here at once (no timeline): the simulation sends it
-- with its next action poll, also for a train standing at a station.
function hold.reverse_clicked(env, vehicle)
	local role = getenv(env, "TF3MP_ROLE")
	if role ~= "host" and role ~= "client" then return end
	assert(type(vehicle) == "number", "vehicle id is a " .. type(vehicle))
	local cmd = env.api.cmd
	local m = memory(env)
	;(m.send or cmd.sendCommand)(cmd.makeScriptingSendEventCmd("mp_probe", "mp_probe_reverse", "mp_probe_reverse", { vehicle = vehicle }))
	logger.info("reverse clicked for vehicle " .. vehicle .. "; the other game turns it too")
end

return hold

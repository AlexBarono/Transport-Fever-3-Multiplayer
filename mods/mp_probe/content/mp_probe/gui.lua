--- The GUI side of the game script (probe v24, resync save v32). TF3 calls main.guiUpdate in the GUI's Lua state on
-- every frame, also while the game is paused, so the shared game speed lives here (sync.speed_step):
-- pause, speed changes and common capacity. The simulation scripts stop while the game is paused and
-- could neither notice a pause of this game nor lift one of the other game.
-- @module mp_probe.gui
local logger = require("/mp_probe/logger.lua")
local sync = require("/mp_probe/sync.lua")
local hold = require("/mp_probe/hold.lua")

local gui = {}

--- Real seconds between two steps.
gui.INTERVAL = 0.25
--- Failures logged per Lua state.
gui.MAX_FAILURES = 5

--- Memory belongs to this module, never the sandbox's forbidden global namespace.
-- If the whole Lua state is new each time, speed_step restores the
-- register from TF3MP_OWN_GUI (what this game said last, kept by the DLL).
local memories = setmetatable({}, { __mode = "k" })
local function memory(env)
	local g = memories[env]
	if not g then
		g = { speed = {}, calls = 0, failures = 0, next_at = -1 }
		memories[env] = g
	end
	return g
end

--- v40: only an explicit launcher request saves a world for a manual resync.
gui.RESYNC_SAVE = "TF3MP-Neuabgleich"

--- v37: seconds before the same reload request is tried again (gui.resync_load).
gui.RELOAD_RETRY_S = 60

--- Real time in seconds.
function gui.now(env, g)
	local clock = env.os and env.os.clock
	if clock then
		local ok, t = pcall(clock)
		if ok and type(t) == "number" then return t end
	end
	-- About 60 frames per second.
	return g.calls / 60
end

--- What the GUI state offers, for the log.
function gui.describe(env)
	local api = env.api or {}
	local function has(fn) local ok, v = pcall(fn); return ok and v ~= nil end
	local parts = {
		"api.engine " .. tostring(has(function() return api.engine.getComponent end)),
		"sendCommand " .. tostring(has(function() return api.cmd.sendCommand end)),
		"makeGameSetSpeedCmd " .. tostring(has(function() return api.cmd.makeGameSetSpeedCmd end)),
		"os.getenv " .. tostring(has(function() return env.os.getenv end)),
		"os.clock " .. tostring(has(function() return env.os.clock end)),
	}
	local ok, max = pcall(function() return api.gui.game.getEstimatedMaximumGameSpeed() end)
	parts[#parts + 1] = "estimated max speed " .. (ok and tostring(max) or "?")
	return table.concat(parts, ", ")
end

--- Keep the automatic pause out of the shared speed register until TF3 has
-- actually resumed. sendCommand returning does not mean the GUI sees its result.
-- The DLL echo also protects a GUI Lua state that loses its memory between calls.
function gui.release_hold(env, g, clock_ui, speed, now, getenv)
	local limit = sync.effective_speed_limit(sync.maximum_speed(env),
		sync.decode(getenv("TF3MP_PEER_GUI")), getenv("TF3MP_ORDERING") == "1")
	local run = math.min(tonumber(clock_ui.run) or 0, limit)
	local releasing = tonumber(clock_ui.release) == 1
	-- Seeing the old positive speed is not proof of a resume: a quick menu
	-- close may leave its earlier pause command queued. Wait for our resume
	-- acknowledgement before removing the guard, including when speed==run.
	if releasing and ((clock_ui.ack == 1 and speed == run) or
		(speed > 0 and (clock_ui.ack == 1 or clock_ui.stopped == 1))) then
		logger.info("net state clockui hold=0 run=" .. speed)
		-- A different positive speed after the command's acknowledgement is the
		-- player's choice; the ordinary speed register detects it on the next step.
		g.speed.target, g.speed.pending = run, nil
		return
	end
	local sent, tries = tonumber(clock_ui.sent), tonumber(clock_ui.tries) or 0
	if releasing and sent and now >= sent and now - sent < sync.APPLY_WAIT_S then return end
	if tries >= sync.APPLY_TRIES then
		if clock_ui.stopped ~= 1 then
			logger.info("sync automatic pause release not confirmed; waiting for the game's speed or a manual resume")
			logger.info("net state clockui " .. sync.encode({ hold = 1, release = 1, run = run, stopped = 1, tries = tries, sent = now }))
		end
		return
	end
	tries = tries + 1
	local pending = { hold = 1, release = 1, run = run, sent = now, tries = tries }
	logger.info("net state clockui " .. sync.encode(pending))
	sync.set_speed(env, run, function(_, success)
		if success == false then logger.info("sync automatic pause release rejected by the game"); return end
		local live = sync.decode(getenv("TF3MP_OWN_CLOCKUI"))
		if live and live.release == 1 and live.tries == tries and live.run == run then
			live.ack = 1; logger.info("net state clockui " .. sync.encode(live))
		end
	end)
end

function gui.update(env, gui_state)
	env = env or _G
	local g = memory(env)
	g.calls = g.calls + 1
	local now = gui.now(env, g)
	-- A clock that jumped back does not stop the steps.
	if now < g.next_at and g.next_at - now <= gui.INTERVAL then return end
	local getenv = env.os and env.os.getenv
	local clock = getenv and sync.decode(getenv("TF3MP_OWN_CLOCK"))
	-- During a live action only: faster confirmations shorten the common pause.
	-- Idle games retain the normal polling interval and snapshot frequency.
	local active = clock and clock.phase and clock.phase ~= "idle" and clock.phase ~= "failed"
	g.next_at = now + (active and 0.1 or gui.INTERVAL)
	-- hold.lua: vehicle hooks (v35), held builds (v34) and the 'Allein testen' hold test.
	local ok_h, err_h = pcall(hold.step, env, gui_state)
	if not ok_h and g.failures < gui.MAX_FAILURES then
		g.failures = g.failures + 1
		logger.info("hold probe failed: " .. tostring(err_h):sub(1, 240))
	end
	local ok, err = pcall(gui.step, env, g, now)
	if not ok then
		g.failures = g.failures + 1
		if g.failures <= gui.MAX_FAILURES then logger.info("gui sync failed: " .. tostring(err):sub(1, 240)) end
	end
end

function gui.step(env, g, now)
	local getenv = env.os and env.os.getenv
	local restore = getenv and sync.decode(getenv("TF3MP_OWN_GUI"))
	if not g.described then
		g.described = true
		-- Once per game, not again when the Lua state lost its memory.
		if not restore then logger.info("gui script running: " .. gui.describe(env)) end
	end
	if not getenv then return end
	local role = sync.role(getenv)
	if not role then return end
	local ordered = getenv("TF3MP_ORDERING") == "1"
	local speed, calendar = sync.read_speed(env)
	local gt = sync.read_time(env)
	if not g.tested and not restore then
		g.tested = true
		-- One harmless command at the start: the speed it already has. Shows whether the GUI may
		-- send commands at all.
		sync.set_speed(env, speed, function(_, success)
			logger.info("gui speed command test: " .. sync.speed_name(speed) .. ", success=" .. tostring(success))
		end)
	end
	if role ~= "host" and role ~= "client" then
		if not g.idle and not restore then
			g.idle = true
			-- Marks for a Lua state without memory that this game's GUI script already started.
			logger.info("net state gui src=gui role=" .. role)
		end
		return
	end
	-- v35: in-game resync. The launcher asks through the DLL; nobody has to leave the game.
	gui.resync_load(env, g, getenv)
	-- v40: world differences are diagnostic only; save_request handles explicit clicks.
	gui.save_request(env, g, getenv, role)
	-- A common-tick intent freezes simulation time at its barrier until both results exist.
	-- Do not feed this automatic pause into the user's shared speed register.
	local clock = sync.decode(getenv("TF3MP_OWN_CLOCK"))
	local clock_ui = sync.decode(getenv("TF3MP_OWN_CLOCKUI"))
	local own_menu = sync.decode(getenv("TF3MP_OWN_MENU"))
	local peer_menu = sync.decode(getenv("TF3MP_PEER_MENU"))
	local menu_hold = ordered and
		((own_menu and own_menu.open == 1) or (peer_menu and peer_menu.open == 1))
	local at = clock and tonumber(clock.at)
	local holding = clock and ((clock.phase == "failed" and at and at > 0) or tonumber(clock.hold) == 1 or
		(at and at > 0 and gt >= at and clock.phase ~= "idle"))
	holding = holding or menu_hold
	if ordered and (speed == 0 or holding) then
		-- Simulation update() stops at a barrier; script events still run while paused.
		-- gui.update already throttles this heartbeat to four events per second.
		local ok, err = pcall(function()
			env.api.cmd.sendCommand(env.api.cmd.makeScriptingSendEventCmd(
				"mp_probe", "mp_probe_replay", "mp_probe_replay", { timeline_tick = true }))
		end)
		if not ok and not g.heartbeat_failed then
			g.heartbeat_failed = true
			logger.info("paused network heartbeat unavailable: " .. tostring(err):sub(1, 200))
		end
	end
	if holding then
		if not clock_ui or tonumber(clock_ui.hold) ~= 1 or clock_ui.release == 1 then
			-- Overlapping menu/action holds keep the original speed, even if a
			-- delayed resume command from the previous hold is still in flight.
			local run = clock_ui and clock_ui.hold == 1 and tonumber(clock_ui.run) or
				(restore and tonumber(restore.tg or restore.run) or speed)
			if ordered and not (clock_ui and clock_ui.hold == 1) then
				-- Preserve the user's shared request, not an old local catch-up
				-- target or temporary capacity limit. Release applies the common cap.
				local requested = tonumber(g.speed.speed) or (restore and tonumber(restore.speed))
				if requested and requested >= 0 and requested <= sync.MAX_SPEED and requested == math.floor(requested) then
					run = requested
				end
			end
			logger.info("sync automatic pause: " .. (menu_hold and "a player is in the game menu" or "common action"))
			logger.info("net state clockui hold=1 run=" .. tostring(run))
		end
		if speed ~= 0 then sync.set_speed(env, 0) end
		return
	elseif clock_ui and tonumber(clock_ui.hold) == 1 then
		gui.release_hold(env, g, clock_ui, speed, now, getenv)
		return
	end
	local out = sync.speed_step(g.speed, {
		own = speed, calendar = calendar, own_t = gt, role = role, peer = sync.decode(getenv("TF3MP_PEER_GUI")), now = now,
		max_speed = sync.maximum_speed(env), ordered = ordered,
		-- Ordered sessions share the requested speed and both capacity limits.
		-- Time differences remain diagnostic; action/menu holds still pause both.
		hold = not ordered, src = "gui", restore = restore,
	})
	for _, line in ipairs(out.logs) do logger.info("sync " .. line) end
	if out.command then
		local target = out.command
		sync.set_speed(env, target, function(_, success)
			if success == false then logger.info("sync speed " .. sync.speed_name(target) .. " rejected by the game") end
		end)
	end
	if out.publish then logger.info("net state gui " .. out.publish) end
	if out.calendar_command ~= nil then
		local target = out.calendar_command
		sync.set_calendar(env, target, function(_, success)
			if success == false then logger.info("sync calendar " .. target .. " ms/day rejected by the game") end
		end)
	end
end

--- v35: the launcher asks for a resync (TF3MP_SAVE=<n>, through the DLL), e.g. when the session
-- stopped on a rejected action. "net state resync ... req=n" tells the partner's launcher (DLL status
-- resync_peer=n); the host's game also saves the resync save it then sends.
function gui.save_request(env, g, getenv, role)
	local n = getenv("TF3MP_SAVE")
	if type(n) ~= "string" or not n:match("^%d+$") then return end
	local done = sync.decode(getenv("TF3MP_OWN_RESYNC"))
	if g.save_req == n or (done and tostring(done.req) == n) then return end
	g.save_req = n
	logger.info("net state resync ck=" .. tostring(done and done.ck or g.resync_ck or 0) .. " req=" .. n)
	if role == "host" then
		gui.save_now(env, "for the launcher (request " .. n .. ")", "the launcher asks for the resync save")
	end
end

function gui.save_now(env, label, reason)
	local found, save = pcall(function() return env.app.saveGame end)
	-- Run 35: TF3's bindings hand out app.saveGame as a table, which is called like a function.
	local kind = type(save)
	if not found or (kind ~= "function" and kind ~= "table" and kind ~= "userdata") then
		logger.info("resync: this game cannot save from the mod (" .. tostring(save):sub(1, 120) ..
			"); for 'Neu abgleichen' save by hand")
		return
	end
	local name = gui.RESYNC_SAVE
	-- Not the map editor; skipSetName keeps the player's own name for the next save.
	local ok, err = pcall(save, name, function() logger.info("resync: saved '" .. name .. "' " .. label) end, false, true)
	if ok then
		logger.info("resync: " .. reason .. ", saving '" .. name .. "' for 'Neu abgleichen'")
	else
		logger.info("resync: saving '" .. name .. "' did not work: " .. tostring(err):sub(1, 200))
	end
end

--- v35: the launcher got (client) or sent (host) the resync save and asks this game to load it
-- while it runs: TF3MP_RELOAD="<epoch> <save name>" (DLL v13, cleared once the load began). The
-- DLL then drops all earlier actions and both games continue from the same save. Loading works
-- like TF3's own load page in the pause menu (gui/menu/savegame_react_util.tl).
function gui.resync_load(env, g, getenv)
	local value = getenv("TF3MP_RELOAD")
	if type(value) ~= "string" then return end
	local epoch, name = value:match("^(%d+) (.+)$")
	if not epoch then return end
	-- v37: a launcher that asks again after a load that never started gets the same epoch (it rises
	-- only with a load), maybe with another save: a new request loads at once, the same one again
	-- after RELOAD_RETRY_S (the DLL clears the request as soon as a load begins).
	local now = gui.now(env, g)
	if g.reload_value == value and now - (g.reload_at or now) < gui.RELOAD_RETRY_S then return end
	g.reload_value, g.reload_at = value, now
	logger.info("resync: loading '" .. name .. "' in the running game (resync " .. epoch .. ")")
	local ok, err = pcall(gui.load_save, env, name)
	if not ok then
		logger.info("resync: loading '" .. name .. "' did not work: " .. tostring(err):sub(1, 200) ..
			"; please use 'Neu abgleichen' in the launcher")
	end
end

function gui.load_save(env, name)
	local app, api = env.app, env.api
	local namespace = app.SaveGameNamespace.getSavegame()
	local id = api.type.SavegameId.new()
	id.saveGameNamespace, id.saveGameName, id.path = namespace, name, ""
	-- The entry of TF3's own save list, as the load page uses it.
	local ok, list = pcall(function() return app.findAllSavegames(namespace) end)
	local found = false
	if ok and type(list) == "table" then
		for _, info in pairs(list) do
			local ok_i, save_name, path = pcall(function() return info.saveName, info.path end)
			if ok_i and save_name == name then
				id.saveGameName, id.path, found = save_name, path or "", true
				break
			end
		end
	end
	logger.info("resync: '" .. name .. "' " .. (found and "found in the save list" or
		("not in the save list (" .. (ok and type(list) or tostring(list):sub(1, 80)) .. "), loading by name")))
	pcall(function() app.setWaitForStartReadyGame() end)
	app.loadGame(id, false, nil)
end

return gui

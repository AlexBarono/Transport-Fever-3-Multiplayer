--- The GUI side of the game script (probe v24, resync save v32). TF3 calls main.guiUpdate in the GUI's Lua state on
-- every frame, also while the game is paused, so the shared game speed lives here (sync.speed_step):
-- pause, speed changes and catching up. The simulation scripts stop while the game is paused and
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

--- Neuabgleich (probe v32): when the world check finds a difference, the host's GUI script saves the
-- host's game under this name. The launcher's 'Neu abgleichen' then sends the newest save written
-- since the game started, so nobody has to save by hand.
gui.RESYNC_SAVE = "TF3MP-Neuabgleich"
--- At most one save per this many checkpoints while the difference lasts (saving makes the game stutter).
-- v37 (run 39): was 3. Every third check TF3 saved this name again, also while the launcher was
-- sending it or TF3's own save menu had it open; TF3 then could not rename its .tmp file over the
-- save ("Save game rename failed") and stopped the game. The live resync asks for its own save
-- (alut_proxy.save); this one is only kept for 'Neu abgleichen' after TF3 was closed.
gui.RESYNC_EVERY = 40
--- v37: differences that only come from things drifting apart (vehicle positions, cargo, towns) do
-- not need a resync; the launcher leaves them alone, so this game does not save for them either.
gui.DRIFT_FIELDS = { hpos = true, hcargo = true, htown = true }

--- Whether the comma list of differing fields names one that is more than drift.
function gui.structural(fields)
	for field in tostring(fields or ""):gmatch("[^,%s]+") do
		if not gui.DRIFT_FIELDS[field] and field ~= "none" then return true end
	end
	return false
end

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

function gui.update(env, gui_state)
	env = env or _G
	local g = memory(env)
	g.calls = g.calls + 1
	local now = gui.now(env, g)
	-- A clock that jumped back does not stop the steps.
	if now < g.next_at and g.next_at - now <= gui.INTERVAL then return end
	g.next_at = now + gui.INTERVAL
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
	local speed = sync.read_speed(env)
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
	if role == "host" then gui.resync_save(env, g, getenv) end
	gui.save_request(env, g, getenv, role)
	-- A common-tick intent freezes simulation time at its barrier until both results exist.
	-- Do not feed this automatic pause into the user's shared speed register.
	local clock = sync.decode(getenv("TF3MP_OWN_CLOCK"))
	local clock_ui = sync.decode(getenv("TF3MP_OWN_CLOCKUI"))
	local at = clock and tonumber(clock.at)
	local holding = clock and ((clock.phase == "failed" and at and at > 0) or tonumber(clock.hold) == 1 or
		(at and at > 0 and gt >= at and clock.phase ~= "idle"))
	if getenv("TF3MP_ORDERING") == "1" and (speed == 0 or holding) then
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
		if not clock_ui or tonumber(clock_ui.hold) ~= 1 then
			local run = restore and tonumber(restore.tg or restore.run) or speed
			logger.info("net state clockui hold=1 run=" .. tostring(run))
		end
		if speed ~= 0 then sync.set_speed(env, 0) end
		return
	elseif clock_ui and tonumber(clock_ui.hold) == 1 then
		local run = tonumber(clock_ui.run) or 0
		logger.info("net state clockui hold=0 run=" .. run)
		if speed ~= run then sync.set_speed(env, run) end
		return
	end
	local out = sync.speed_step(g.speed, {
		own = speed, own_t = gt, role = role, peer = sync.decode(getenv("TF3MP_PEER_GUI")), now = now,
		hold = true, src = "gui", restore = restore,
	})
	for _, line in ipairs(out.logs) do logger.info("sync " .. line) end
	if out.command then
		local target = out.command
		sync.set_speed(env, target, function(_, success)
			if success == false then logger.info("sync speed " .. sync.speed_name(target) .. " rejected by the game") end
		end)
	end
	if out.publish then logger.info("net state gui " .. out.publish) end
end

--- Host: saves this game once the world check reports a difference (TF3MP_OWN_HEALTH status=diff),
-- again only RESYNC_EVERY checkpoints later. "net state resync ck=N" marks the checkpoint, so a
-- GUI Lua state without memory does not save twice (the DLL keeps it as TF3MP_OWN_RESYNC).
function gui.resync_save(env, g, getenv)
	local health = sync.decode(getenv("TF3MP_OWN_HEALTH"))
	if not health or health.status ~= "diff" or not gui.structural(health.fields) then return end
	local ck = tonumber(health.ck)
	if not ck then return end
	local done = sync.decode(getenv("TF3MP_OWN_RESYNC"))
	local last = g.resync_ck or (done and tonumber(done.ck))
	if last and ck >= last and ck < last + gui.RESYNC_EVERY then return end
	g.resync_ck = ck
	logger.info("net state resync ck=" .. ck .. (done and done.req and (" req=" .. done.req) or ""))
	gui.save_now(env, "at check " .. ck, "the world differs at check " .. ck)
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

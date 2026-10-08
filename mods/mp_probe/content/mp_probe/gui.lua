--- The GUI side of the game script (probe v24, resync save v32). TF3 calls main.guiUpdate in the GUI's Lua state on
-- every frame, also while the game is paused, so the shared game speed lives here (sync.speed_step):
-- pause, speed changes and catching up. The simulation scripts stop while the game is paused and
-- could neither notice a pause of this game nor lift one of the other game.
-- @module mp_probe.gui
local logger = require("/mp_probe/logger.lua")
local sync = require("/mp_probe/sync.lua")

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
gui.RESYNC_EVERY = 3

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

function gui.update(env)
	env = env or _G
	local g = memory(env)
	g.calls = g.calls + 1
	local now = gui.now(env, g)
	-- A clock that jumped back does not stop the steps.
	if now < g.next_at and g.next_at - now <= gui.INTERVAL then return end
	g.next_at = now + gui.INTERVAL
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
	if role == "host" then gui.resync_save(env, g, getenv) end
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
	if not health or health.status ~= "diff" then return end
	local ck = tonumber(health.ck)
	if not ck then return end
	local done = sync.decode(getenv("TF3MP_OWN_RESYNC"))
	local last = g.resync_ck or (done and tonumber(done.ck))
	if last and ck >= last and ck < last + gui.RESYNC_EVERY then return end
	g.resync_ck = ck
	logger.info("net state resync ck=" .. ck)
	local found, save = pcall(function() return env.app.saveGame end)
	if not found or type(save) ~= "function" then
		logger.info("resync: this game cannot save from the mod (" .. tostring(save):sub(1, 120) ..
			"); for 'Neu abgleichen' save by hand")
		return
	end
	local name = gui.RESYNC_SAVE
	-- Not the map editor; skipSetName keeps the player's own name for the next save.
	local ok, err = pcall(save, name, function() logger.info("resync: saved '" .. name .. "' at check " .. ck) end, false, true)
	if ok then
		logger.info("resync: the world differs at check " .. ck .. ", saving '" .. name .. "' for 'Neu abgleichen'")
	else
		logger.info("resync: saving '" .. name .. "' did not work: " .. tostring(err):sub(1, 200))
	end
end

return gui

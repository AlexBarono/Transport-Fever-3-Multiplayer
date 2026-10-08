--- The GUI side of the game script (probe v24). TF3 calls main.guiUpdate in the GUI's Lua state on
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

return gui

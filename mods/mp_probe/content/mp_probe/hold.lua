--- Probe v33: can a player's action be held BEFORE TF3 executes it? Common-tick execution
-- (timeline.lua) needs that; capturing after the fact can only replay an action late.
--
-- TF3's own game scripts show two hooks in the GUI Lua state (base/content/game_mechanics.zip):
--   * The native build tools fire guiHandleEvent "builder.proposalCreate", then
--     "builder.proposalPrepareForApply" and "builder.proposalApply" with param {proposal, data}.
--     company.script returns { errorMessages = {...} } from proposalCreate to refuse a build.
--   * The line and vehicle windows are Lua (gui/line_vehicle_mgmt) and send their commands
--     through api.cmd.sendCommand.
-- This module only observes, except for one self-test in 'Allein testen' (role loopback): the
-- first build is refused at proposalPrepareForApply and, if TF3 really did not build it, sent
-- again by the mod REISSUE_S seconds later. The log then says whether holding works.
-- @module mp_probe.hold
local logger = require("/mp_probe/logger.lua")

local hold = {}

--- Distinct GUI events and commands logged per Lua state.
hold.MAX_EVENTS = 40
hold.MAX_COMMANDS = 30
--- Builder events logged in full (with counts) per Lua state.
hold.MAX_BUILDS = 12
--- Real seconds between the refused build and the mod's own copy of it.
hold.REISSUE_S = 2
--- Shown in TF3 as the reason the build was refused.
hold.TEST_TEXT = "TF3MP-Test: Bau einmal zurückgehalten, er erscheint gleich von selbst"

local memories = setmetatable({}, { __mode = "k" })
local function memory(env)
	local m = memories[env]
	if not m then
		m = { events = {}, event_count = 0, commands = {}, command_count = 0, builds = 0 }
		memories[env] = m
	end
	return m
end

local function count(fn)
	local ok, n = pcall(fn)
	return ok and tostring(n) or "?"
end

--- Short description of a builder event's proposal.
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

local function role_of(env)
	local ok, role = pcall(function() return env.os.getenv("TF3MP_ROLE") end)
	return ok and role or nil
end

--- guiHandleEvent (main.gs.lua). Returns nil (no opinion) except in the loopback self-test.
function hold.event(env, src, id, name, param)
	local m = memory(env)
	local key = tostring(id) .. "/" .. tostring(name)
	if not m.events[key] and m.event_count < hold.MAX_EVENTS then
		m.events[key] = true
		m.event_count = m.event_count + 1
		logger.info("gui event " .. key .. " (src=" .. tostring(src) .. ", param " .. type(param) .. ")")
	end
	if type(name) ~= "string" or name:sub(1, 16) ~= "builder.proposal" then
		return nil
	end
	if m.builds < hold.MAX_BUILDS then
		m.builds = m.builds + 1
		logger.info("gui " .. name .. ": " .. hold.describe_proposal(param))
	end
	local test = m.test
	if name == "builder.proposalPrepareForApply" and not m.tested and role_of(env) == "loopback" then
		local critical = false
		pcall(function() critical = param[2].errorState.critical == true end)
		if critical or type(param) ~= "table" or param[1] == nil then return nil end
		m.tested = true
		-- The engine may reuse its proposal after the event; keep a copy (Proposal.clone).
		local ok_c, copy = pcall(function() return env.api.type.Proposal.clone(param[1]) end)
		if not ok_c or copy == nil then
			logger.info("hold test: Proposal.clone unavailable (" .. tostring(copy):sub(1, 100) .. "), keeping the original")
			copy = param[1]
		end
		m.test = { proposal = copy, at = hold.clock(env, m) + hold.REISSUE_S, applied = false }
		logger.info("hold test: refusing this build once at proposalPrepareForApply (" .. hold.describe_proposal(param) .. ")")
		return { errorMessages = { [hold.TEST_TEXT] = true } }
	end
	if name == "builder.proposalApply" and test and not test.done then
		-- TF3 applied the build although it was refused: refusing does not hold it.
		test.applied = true
		logger.info("hold test: TF3 applied the refused build anyway (proposalApply arrived); nothing is sent again")
	end
	return nil
end

--- Real time in seconds (os.clock), or a frame count.
function hold.clock(env, m)
	local ok, t = pcall(function() return env.os.clock() end)
	if ok and type(t) == "number" then return t end
	m.frames = (m.frames or 0) + 1
	return m.frames / 60
end

--- Every GUI step: finishes the self-test and installs the command logger once.
function hold.step(env)
	local m = memory(env)
	hold.wrap(env, m)
	local test = m.test
	if not test or test.done or hold.clock(env, m) < test.at then return end
	test.done = true
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

--- Logs which commands go through api.cmd.sendCommand in this Lua state, by the name of the
-- make...Cmd that built them. Everything is passed through unchanged.
function hold.wrap(env, m)
	if m.wrapped then return end
	m.wrapped = true
	local cmd = env.api and env.api.cmd
	if not cmd then return end
	local names = setmetatable({}, { __mode = "k" })
	local made = 0
	local ok_pairs, err_pairs = pcall(function()
		local makers = {}
		for k, v in pairs(cmd) do
			if type(k) == "string" and k:match("^make.+Cmd$") and type(v) == "function" then makers[k] = v end
		end
		for k, f in pairs(makers) do
			cmd[k] = function(...)
				local c = f(...)
				if c ~= nil and (type(c) == "table" or type(c) == "userdata") then pcall(function() names[c] = k end) end
				return c
			end
			made = made + 1
		end
	end)
	local send = cmd.sendCommand
	local ok_send, err_send = pcall(function()
		assert(type(send) == "function", "sendCommand is a " .. type(send))
		cmd.sendCommand = function(c, ...)
			pcall(function()
				local name = names[c] or tostring(c):gsub("0x%x+", ""):gsub("%x%x%x%x%x%x%x%x+", "")
				m.commands[name] = (m.commands[name] or 0) + 1
				if m.commands[name] == 1 and m.command_count < hold.MAX_COMMANDS then
					m.command_count = m.command_count + 1
					logger.info("gui command " .. name)
				end
			end)
			return send(c, ...)
		end
	end)
	logger.info("hold probe: " .. made .. " command makers wrapped" ..
		(ok_pairs and "" or (" (makers: " .. tostring(err_pairs):sub(1, 100) .. ")")) ..
		", sendCommand " .. (ok_send and "wrapped" or ("not wrapped: " .. tostring(err_send):sub(1, 100))))
end

return hold

-- hold.lua: GUI events of TF3's build tools, the 'Allein testen' hold test and the vehicle hooks
-- (v35); no running game required.
local base_require = require
function require(name)
	if name:sub(1, 1) == "/" then return assert(loadfile("mods/mp_probe/content" .. name))() end
	return base_require(name)
end
local logs = {}
function debugPrint(...) logs[#logs + 1] = table.concat({ ... }, " ") end
local hold = require("/mp_probe/hold.lua")
local passed, failed = 0, 0
local function test(name, fn)
	logs = {}
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function has(text)
	for _, l in ipairs(logs) do if l:find(text, 1, true) then return true end end
	return false
end

--- A GUI Lua state with a clock, a role and a command API that records what it sends.
local function env(role)
	local e = { now = 0, sent = {}, made = {} }
	local cmd = {}
	function cmd.makeWorldBuildProposalCmd(proposal, context, ignore, player)
		return { kind = "build", proposal = proposal, ignore = ignore, player = player }
	end
	function cmd.makeGameSetSpeedCmd(speed) return { kind = "speed", speed = speed } end
	function cmd.sendCommand(c, callback, extra)
		e.sent[#e.sent + 1] = { c = c, extra = extra }
		if callback then callback(c, true) end
		return "sent"
	end
	e.api = { cmd = cmd, type = { Proposal = { clone = function(p) return { copy_of = p } end } } }
	e.os = { clock = function() return e.now end, getenv = function(k) if k == "TF3MP_ROLE" then return role end end }
	return e
end
local function proposal(critical)
	return { { proposal = { addedSegments = { 1, 2 }, removedSegments = {} }, toAdd = {}, toRemove = {} },
		{ errorState = { critical = critical or false }, costs = 1200 } }
end

test("'Allein testen': the first build is refused once and the mod sends a copy later", function()
	local e = env("loopback")
	local p = proposal()
	assert(hold.event(e, "", "", "builder.proposalCreate", p) == nil, "the preview is never refused")
	local r = hold.event(e, "", "", "builder.proposalPrepareForApply", p)
	assert(type(r) == "table" and r.errorMessages[hold.TEST_TEXT], "refused once")
	hold.step(e)
	assert(#e.sent == 0, "not before REISSUE_S")
	e.now = hold.REISSUE_S + 0.1
	hold.step(e)
	assert(#e.sent == 1 and e.sent[1].c.kind == "build" and e.sent[1].c.proposal.copy_of == p[1], "the cloned proposal is sent")
	assert(e.sent[1].c.ignore == false and e.sent[1].c.player == true)
	assert(has("hold test: the held build was built when sent again"))
	assert(hold.event(e, "", "", "builder.proposalPrepareForApply", proposal()) == nil, "only the first build is refused")
	e.now = 10; hold.step(e)
	assert(#e.sent == 1)
end)

test("a refusal TF3 ignores is reported and never sent a second time", function()
	local e = env("loopback")
	local p = proposal()
	assert(hold.event(e, "", "", "builder.proposalPrepareForApply", p))
	hold.event(e, "", "", "builder.proposalApply", p)
	e.now = 5; hold.step(e)
	assert(#e.sent == 0 and has("TF3 applied the refused build anyway"))
end)

test("in a session (host or client) nothing is refused, builds are only logged", function()
	for _, role in ipairs({ "host", "client", "off" }) do
		local e = env(role)
		assert(hold.event(e, "", "", "builder.proposalPrepareForApply", proposal()) == nil)
		assert(hold.event(e, "", "", "builder.proposalApply", proposal()) == nil)
		e.now = 5; hold.step(e)
		assert(#e.sent == 0)
	end
	assert(has("gui builder.proposalApply: segments=2 removed=0 constructions=0 demolished=0 critical=false cost=1200"))
end)

test("a proposal with a critical error is left alone", function()
	local e = env("loopback")
	assert(hold.event(e, "", "", "builder.proposalPrepareForApply", proposal(true)) == nil)
	e.now = 5; hold.step(e)
	assert(#e.sent == 0)
end)

test("without Proposal.clone the original proposal is kept", function()
	local e = env("loopback")
	e.api.type.Proposal = nil
	local p = proposal()
	assert(hold.event(e, "", "", "builder.proposalPrepareForApply", p))
	e.now = 5; hold.step(e)
	assert(e.sent[1].c.proposal == p[1] and has("Proposal.clone unavailable"))
end)

test("other GUI events are logged once each and never answered", function()
	local e = env("host")
	for _ = 1, 3 do assert(hold.event(e, "", "vehicleStore", "mission.buyVehicle", {}) == nil) end
	local n = 0
	for _, l in ipairs(logs) do if l:find("gui event vehicleStore/mission.buyVehicle", 1, true) then n = n + 1 end end
	assert(n == 1)
end)

--- A GUI state with TF3's vehicle commands; vars make it a session with a partner (v35).
local function vehicle_env(role, vars)
	local e = env(role)
	local getenv = e.os.getenv
	e.os.getenv = function(k) if vars and vars[k] then return vars[k] end return getenv(k) end
	function e.api.cmd.makeVehicleReverseCmd(id) return { kind = "reverse", id = id } end
	function e.api.cmd.makeVehicleSetStoppedByUserCmd(id, v) return { kind = "stopped", id = id, value = v } end
	function e.api.cmd.makeVehicleSendToDepotCmd(id, v) return { kind = "depot", id = id, value = v } end
	function e.api.cmd.makeScriptingSendEventCmd(src, id, name, param) return { kind = "event", id = id, name = name, param = param } end
	return e
end
local SESSION = { TF3MP_ORDERING = "1", TF3MP_PEER_CLOCK = "at=0 gt=1000 hold=0 phase=idle seq=0" }

test("in a session vehicle clicks become script events for a common tick (v35)", function()
	local e = vehicle_env("host", SESSION)
	hold.step(e)
	assert(has("vehicle hooks: 3 of 3 installed"))
	local c = e.api.cmd.makeVehicleReverseCmd(117350)
	assert(c.kind == "event" and c.name == "mp_probe_vehicle" and c.param.command == "reverse" and c.param.vehicle == 117350)
	c = e.api.cmd.makeVehicleSetStoppedByUserCmd(7, true)
	assert(c.param.command == "stopped" and c.param.value == true)
	c = e.api.cmd.makeVehicleSendToDepotCmd(7, false)
	assert(c.param.command == "depot" and c.param.value == false)
	assert(#e.sent == 0, "the GUI sends the event itself")
	hold.step(e)
	assert(e.api.cmd.makeVehicleReverseCmd(5).param.vehicle == 5, "hooked twice")
	-- A failed timeline or switched-off holding: commands run as usual.
	e.os.getenv = (function(get) return function(k)
		if k == "TF3MP_OWN_CLOCK" then return "at=0 gt=1 hold=0 phase=failed seq=0" end
		return get(k) end end)(e.os.getenv)
	assert(e.api.cmd.makeVehicleSetStoppedByUserCmd(7, true).kind == "stopped")
end)

test("without a partner a reverse runs at once and is told to the simulation; alone nothing travels (v35)", function()
	local e = vehicle_env("client")
	hold.step(e)
	local c = e.api.cmd.makeVehicleReverseCmd(117350)
	assert(c.kind == "reverse" and c.id == 117350, "command not passed through")
	assert(#e.sent == 1 and e.sent[1].c.name == "mp_probe_reverse" and e.sent[1].c.param.vehicle == 117350)
	assert(e.api.cmd.makeVehicleSetStoppedByUserCmd(3, true).kind == "stopped" and #e.sent == 1)
	local solo = vehicle_env("loopback", SESSION)
	hold.step(solo)
	assert(solo.api.cmd.makeVehicleReverseCmd(3).id == 3 and #solo.sent == 0)
end)

test("a read-only command table or missing commands are reported, not fatal", function()
	local e = vehicle_env("host", SESSION)
	local real = e.api.cmd
	e.api.cmd = setmetatable({}, { __index = real, __newindex = function() error("read only") end })
	hold.step(e)
	assert(has("vehicle hooks: 0 of 3 installed"))
	assert(e.api.cmd.makeVehicleReverseCmd(4).id == 4)
	local f = env("host"); logs = {}
	hold.step(f)
	assert(has("vehicle hooks: 0 of 3 installed") and has("makeVehicleReverseCmd missing"))
end)

test("a failing script event still gives the GUI the real command", function()
	local e = vehicle_env("client", SESSION)
	function e.api.cmd.makeScriptingSendEventCmd() error("no events here") end
	hold.step(e)
	assert(e.api.cmd.makeVehicleReverseCmd(8).id == 8 and has("vehicle reverse: no script event"))
	assert(has("reverse: could not tell the simulation"))
end)

print(string.format("%d hold tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

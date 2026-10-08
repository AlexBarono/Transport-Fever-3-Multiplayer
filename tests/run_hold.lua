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
-- v36: the makers return TF3's own commands; the wrapped sendCommand collects marked ones.
local function vehicle_env(role, vars)
	local e = env(role)
	local getenv = e.os.getenv
	e.os.getenv = function(k) if vars and vars[k] then return vars[k] end return getenv(k) end
	function e.api.cmd.makeVehicleReverseCmd(id) return { kind = "reverse", id = id } end
	function e.api.cmd.makeVehicleSetStoppedByUserCmd(id, v) return { kind = "stopped", id = id, value = v } end
	function e.api.cmd.makeVehicleSendToDepotCmd(id, v) return { kind = "depot", id = id, value = v } end
	function e.api.cmd.makeVehicleSetLineCmd(id, line, stop) return { kind = "line", id = id, line = line, stop = stop } end
	function e.api.cmd.makeVehicleSellCmd(list) return { kind = "sell", list = list } end
	function e.api.cmd.makeScriptingSendEventCmd(src, id, name, param) return { kind = "event", id = id, name = name, param = param } end
	return e
end
local SESSION = { TF3MP_ORDERING = "1", TF3MP_PEER_CLOCK = "at=0 gt=1000 hold=0 phase=idle seq=0" }
local wire = require("/mp_probe/wire.lua")

test("in a session vehicle commands of one frame travel as one script event (v36)", function()
	local e = vehicle_env("host", SESSION)
	hold.step(e)
	assert(has("vehicle hooks: 6 of 6 installed"))
	local cmd = e.api.cmd
	local c = cmd.makeVehicleReverseCmd(117350)
	assert(c.kind == "reverse" and c.id == 117350, "the maker returns TF3's own command")
	local answers = {}
	local function cb(r, ok) answers[#answers + 1] = { r = r, ok = ok } end
	cmd.sendCommand(c, cb)
	cmd.sendCommand(cmd.makeVehicleSetLineCmd(5, 40, 2), cb)
	cmd.sendCommand(cmd.makeVehicleSetLineCmd(6, -1), cb)
	cmd.sendCommand(cmd.makeVehicleSellCmd({ 7, 8 }), cb)
	cmd.sendCommand(cmd.makeVehicleSetStoppedByUserCmd(9, true))
	assert(#e.sent == 0, "nothing runs before the common tick")
	assert(#answers == 4 and answers[1].ok == true and answers[1].r == c, "the window's callbacks run as if done")
	assert(has("vehicle line for 5 clicked; both games run it at a common tick"))
	hold.step(e)
	assert(#e.sent == 1 and e.sent[1].c.kind == "event" and e.sent[1].c.name == "mp_probe_vehicle")
	local list = assert(wire.decode(e.sent[1].c.param.batch))
	assert(#list == 5 and list[1].command == "reverse" and list[1].vehicle == 117350)
	assert(list[2].command == "line" and list[2].vehicle == 5 and list[2].value == 40 and list[2].stop == 2)
	assert(list[3].value == -1 and list[3].stop == 0)
	assert(list[4].command == "sell" and list[4].vehicles[2] == 8)
	assert(list[5].command == "stopped" and list[5].value == true)
	assert(has("vehicle commands handed over: 5"))
	hold.step(e)
	assert(#e.sent == 1, "a batch is sent once; hooked once")
	-- Other commands pass through untouched.
	cmd.sendCommand({ kind = "build" })
	assert(#e.sent == 2 and e.sent[2].c.kind == "build")
	-- A failed timeline: commands run as usual.
	e.os.getenv = (function(get) return function(k)
		if k == "TF3MP_OWN_CLOCK" then return "at=0 gt=1 hold=0 phase=failed seq=0" end
		return get(k) end end)(e.os.getenv)
	cmd.sendCommand(cmd.makeVehicleSetStoppedByUserCmd(7, true))
	assert(#e.sent == 3 and e.sent[3].c.kind == "stopped")
end)

test("without a partner a reverse runs at once and is told to the simulation; alone nothing travels (v35)", function()
	local e = vehicle_env("client")
	hold.step(e)
	local cmd = e.api.cmd
	cmd.sendCommand(cmd.makeVehicleReverseCmd(117350))
	assert(#e.sent == 2 and e.sent[1].c.kind == "reverse" and e.sent[1].c.id == 117350, "command not passed through")
	assert(e.sent[2].c.name == "mp_probe_reverse" and e.sent[2].c.param.vehicle == 117350)
	cmd.sendCommand(cmd.makeVehicleSetLineCmd(3, 40, 0))
	assert(#e.sent == 3 and e.sent[3].c.kind == "line")
	local solo = vehicle_env("loopback", SESSION)
	hold.step(solo)
	solo.api.cmd.sendCommand(solo.api.cmd.makeVehicleReverseCmd(3))
	assert(#solo.sent == 1 and solo.sent[1].c.id == 3)
end)

test("a read-only command table or missing commands are reported, not fatal", function()
	local e = vehicle_env("host", SESSION)
	local real = e.api.cmd
	e.api.cmd = setmetatable({}, { __index = real, __newindex = function() error("read only") end })
	hold.step(e)
	assert(has("vehicle hooks: 0 of 6 installed"))
	assert(e.api.cmd.makeVehicleReverseCmd(4).id == 4)
	local f = env("host"); logs = {}
	hold.step(f)
	assert(has("vehicle hooks: 1 of 6 installed") and has("makeVehicleReverseCmd missing"))
end)

test("a failing script event runs TF3's own commands here at once", function()
	local e = vehicle_env("client", SESSION)
	function e.api.cmd.makeScriptingSendEventCmd() error("no events here") end
	hold.step(e)
	local cmd = e.api.cmd
	cmd.sendCommand(cmd.makeVehicleReverseCmd(8))
	cmd.sendCommand(cmd.makeVehicleSetLineCmd(9, 40, 1))
	assert(#e.sent == 0)
	hold.step(e)
	assert(has("vehicle commands: no script event"))
	assert(#e.sent == 2 and e.sent[1].c.kind == "reverse" and e.sent[2].c.kind == "line")
end)

print(string.format("%d hold tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

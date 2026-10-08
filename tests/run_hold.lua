-- Probe v33 (hold.lua): GUI events of TF3's build tools, the 'Allein testen' hold test and the
-- command logger; no running game required.
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

test("the command logger names commands by their maker and passes everything through", function()
	local e = env("host")
	hold.step(e)
	assert(has("hold probe: 2 command makers wrapped, sendCommand wrapped"))
	local c = e.api.cmd.makeGameSetSpeedCmd(2)
	assert(c.kind == "speed" and c.speed == 2)
	local called
	assert(e.api.cmd.sendCommand(c, function() called = true end, "x") == "sent")
	assert(called and e.sent[1].c == c and e.sent[1].extra == "x")
	e.api.cmd.sendCommand(e.api.cmd.makeGameSetSpeedCmd(1))
	local n = 0
	for _, l in ipairs(logs) do if l == "gui command makeGameSetSpeedCmd" or l:find("gui command makeGameSetSpeedCmd", 1, true) then n = n + 1 end end
	assert(n == 1, "logged once")
	hold.step(e)
	assert(e.api.cmd.sendCommand(c) == "sent" and #e.sent == 3, "wrapped only once")
end)

test("a read-only command table is reported, not fatal", function()
	local e = env("host")
	local real = e.api.cmd
	e.api.cmd = setmetatable({}, { __index = real, __newindex = function() error("read only") end })
	hold.step(e)
	assert(has("sendCommand not wrapped"))
	assert(e.api.cmd.sendCommand({ kind = "x" }) == "sent")
end)

print(string.format("%d hold tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

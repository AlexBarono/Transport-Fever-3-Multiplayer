local root = "mods/mp_probe/content"
local original = require
local modules = {}
function require(name)
	if name:sub(1, 1) ~= "/" then return original(name) end
	if not modules[name] then modules[name] = assert(loadfile(root .. name))() end
	return modules[name]
end
function debugPrint() end
local t = require("/mp_probe/transport.lua")
local wire = require("/mp_probe/wire.lua")
local gui = require("/mp_probe/gui.lua")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function copy(v)
	if type(v) ~= "table" then return v end
	local r = {}; for k, x in pairs(v) do r[k] = copy(x) end; return r
end
local function state()
	local s = {}
	return { get = function() return copy(s) end, set = function(_, v) s = copy(v) end }
end
local function setup()
	local s, callbacks, logs = state(), {}, {}
	t.begin(s, "peer.1")
	local env = t.env({ api = { cmd = { sendCommand = function(_, cb) callbacks[#callbacks + 1] = cb end } } }, s)
	return s, env, callbacks, logs, function(text) logs[#logs + 1] = text end
end

test("large payload round trip through bounded stdout and environment chunks", function()
	local line = "B5 " .. string.rep("x", t.MAX_BYTES - 3)
	local logs, s, ack = {}, {}, {}
	t.send(line, s, function(text) logs[#logs + 1] = text end)
	assert(#logs == math.ceil(#line / t.CHUNK))
	local received
	for i, log in ipairs(logs) do
		assert(#log < 6100 and not log:find("\n", 1, true))
		local _, index, count, text = log:match("^net upload (%S+) (%d+) (%d+) (.+)$")
		local part = "part peer.1 net " .. index .. " " .. count .. " " .. text
		received = t.receive(s, part, function(a) ack[#ack + 1] = a end)
		if i < #logs then assert(received == nil) end
		assert(t.receive(s, part, function() end) == received, "duplicate chunks must be idempotent")
	end
	assert(received == "line peer.1 net " .. line and #ack == #logs)
end)
test("short payloads preserve the existing recording marker", function()
	local log; t.send("B5 abc", {}, function(x) log = x end); assert(log == "net send B5 abc")
end)
test("oversized and out-of-order chunks are refused", function()
	assert(not pcall(t.send, string.rep("x", t.MAX_BYTES + 1), {}, function() end))
	local ack = 0; local log = function() ack = ack + 1 end
	assert(not t.receive({}, "part p.1 net 1 2 x", log))
	assert(not t.receive({}, "part p.1 net 0 999 x", log))
	assert(not t.receive({}, "part p.1 net 0 2 x", log))
	assert(ack == 0)
end)
test("large data codec supports complete train and station records", function()
	local record = { params = {}, name = string.rep("station", 5000) }
	for i = 1, 3000 do record.params[i] = { model = "train", index = i } end
	local text = wire.encode(record); assert(#text > 16384)
	assert(wire.encode(assert(wire.decode(text))) == text)
end)
test("receipt waits for asynchronous execution and follow-up work", function()
	local s, env, cb, logs, log = setup()
	env.api.cmd.sendCommand({}, function() local live=s:get(); live.action_work={1}; s:set(live) end)
	t.dispatched(s); t.check(s, log); assert(#logs == 0)
	cb[1]({}, true); t.check(s, log); assert(#logs == 0)
	local live=s:get(); live.action_work=nil; s:set(live)
	t.check(s, log); assert(logs[1] == "net result peer.1 OK")
end)
test("staged builds and weld checks prevent premature success", function()
	local s, _, _, logs, log = setup(); t.dispatched(s)
	local live=s:get(); live.network_followup={phase="construction"}; s:set(live)
	t.check(s,log); assert(#logs==0)
	live=s:get(); live.network_followup=nil; live.weld_checks={1}; s:set(live)
	t.check(s,log); assert(#logs==0)
	live=s:get(); live.weld_checks=nil; s:set(live); t.check(s,log)
	assert(logs[1] == "net result peer.1 OK")
end)
test("game rejection yields FAIL and discards dependent work", function()
	local s, env, cb, logs, log = setup()
	env.api.cmd.sendCommand({}); t.dispatched(s)
	local live=s:get(); live.action_work={1}; live.network_followup={}; s:set(live)
	cb[1]({}, false); t.check(s,log)
	assert(logs[1]:find("net result peer.1 FAIL",1,true))
	assert(not s:get().action_work and not s:get().network_followup)
end)
test("v37: in a session a rejected replay is skipped and reported as done, the session carries on", function()
	local s, env, cb, logs, log = setup()
	env.api.cmd.sendCommand({}); t.dispatched(s)
	local live=s:get(); live.action_work={1}; live.network_followup={}; s:set(live)
	cb[1]({}, false); t.check(s, log, true)
	assert(logs[1]:find("net skipped peer.1 (1 so far), the session carries on: game command rejected", 1, true), logs[1])
	assert(logs[2] == "net result peer.1 OK", tostring(logs[2]))
	local after = s:get()
	assert(after.network_done.result == "OK" and after.network_done.skipped == true)
	assert(after.skipped == 1 and after.last_skipped.token == "peer.1")
	assert(not after.action_work and not after.network_followup, "the rest of the skipped action is dropped")
	-- A success is not counted as skipped.
	t.begin(s, "peer.2"); local env2 = t.env({ api = { cmd = { sendCommand = function(_, c) cb[#cb + 1] = c end } } }, s)
	env2.api.cmd.sendCommand({}); t.dispatched(s); cb[#cb]({}, true); t.check(s, log, true)
	assert(logs[3] == "net result peer.2 OK" and s:get().skipped == 1 and not s:get().network_done.skipped)
end)
test("critical game result and callback exceptions fail the transaction", function()
	for _, mode in ipairs({"critical", "callback"}) do
		local s, env, cb, logs, log = setup()
		env.api.cmd.sendCommand({}, function() if mode=="callback" then error("mapping missing") end end)
		t.dispatched(s); cb[1]({resultProposalData={errorState={critical=mode=="critical"}}},true); t.check(s,log)
		assert(logs[1]:find(" FAIL",1,true))
	end
end)
test("duplicate callbacks cannot consume another pending command", function()
	local s, env, cb, logs, log = setup()
	env.api.cmd.sendCommand({}); env.api.cmd.sendCommand({}); t.dispatched(s)
	cb[1]({},true); cb[1]({},true); t.check(s,log)
	assert(#logs==0 and s:get().network_work.pending==1)
	cb[2]({},true); t.check(s,log); assert(logs[1]=="net result peer.1 OK")
end)

test("a build callback can retry a rejected attempt without poisoning the transaction", function()
	local s, env, cb, logs, log = setup()
	local accepted = false
	local function build_result(_, success) accepted = success == true; return true end
	env.api.cmd.sendCommand({}, build_result)
	cb[1]({resultProposalData={errorState={critical=true}}}, false)
	assert(not s:get().network_work.error and not accepted)
	env.api.cmd.sendCommand({}, build_result)
	cb[2]({}, true); t.dispatched(s); t.check(s, log)
	assert(accepted and logs[1] == "net result peer.1 OK")
end)

test("exhausted and asynchronous build failures still stop the transaction", function()
	for _, mode in ipairs({"exhausted", "asynchronous"}) do
		local s, env, cb, logs, log = setup()
		env.api.cmd.sendCommand({}, function(_, success)
			if mode == "asynchronous" and not success then t.fail(s, "build rejected after dispatch") end
			return true
		end)
		if mode == "asynchronous" then t.dispatched(s) end
		cb[1]({}, false)
		if mode == "exhausted" then t.fail(s, "no build attempt succeeded"); t.dispatched(s) end
		t.check(s, log); assert(logs[1]:find(" FAIL", 1, true))
	end
end)

test("an exception in a managed build callback cannot be acknowledged", function()
	local s, env, cb, logs, log = setup()
	env.api.cmd.sendCommand({}, function() error("build verification failed"); return true end)
	cb[1]({}, true); t.dispatched(s); t.check(s, log)
	assert(logs[1]:find(" FAIL", 1, true))
end)
test("thrown sendCommand is a failed transaction", function()
	local s=state(); t.begin(s,"p.1")
	local env=t.env({api={cmd={sendCommand=function() error("not allowed") end}}},s)
	assert(not pcall(env.api.cmd.sendCommand,{})); t.dispatched(s)
	local result; t.check(s,function(x)result=x end); assert(result:find(" FAIL",1,true))
end)
test("GUI never writes forbidden globals, including after module reload", function()
	local writes=0
	local env=setmetatable({os={clock=function()return 1 end,getenv=function()return nil end}},
		{__newindex=function()writes=writes+1; error("Global variable in mod") end})
	gui.update(env); gui.update(env)
	local fresh=assert(loadfile(root.."/mp_probe/gui.lua"))(); fresh.update(env)
	assert(writes==0)
end)
print(string.format("%d transport tests passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end

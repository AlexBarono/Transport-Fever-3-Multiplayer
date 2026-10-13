-- The Lua/DLL boundary and event delivery, using copy-on-read/write engine state.
local root, real_require, modules = "mods/mp_probe/content", require, {}
function require(name)
	if name:sub(1, 1) ~= "/" then return real_require(name) end
	if not modules[name] then modules[name] = assert(loadfile(root .. name))() end
	return modules[name]
end
local logs = {}
function debugPrint(...) logs[#logs + 1] = table.concat({...}, " ") end
local transport = require("/mp_probe/transport.lua")
local passed, failed = 0, 0
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function state()
	local value = {}
	return { get = function() return copy(value) end, set = function(_, v) value = copy(v) end }
end
local function count(needle)
	local n = 0; for _, text in ipairs(logs) do if text:find(needle, 1, true) then n = n + 1 end end; return n
end
local function test(name, fn)
	local saved_api, saved_os = api, os
	logs = {}
	local ok, err = pcall(fn)
	api, os = saved_api, saved_os
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function setup(opts)
	opts = opts or {}
	assert(loadfile(root .. "/mp_probe/main.script.lua"))()
	local main, st = data(), state()
	local vars, now = { TF3MP_WORLD = "1-2-3" }, 100
	local events, callbacks, builds, handled = {}, {}, {}, 0
	local env = { os = { getenv = function(k) return vars[k] end, time = function() return now end } }
	env.api = { cmd = {
		makeScriptingSendEventCmd = function(a, b, c, d) return { event = {a, b, c, copy(d)} } end,
		sendCommand = function(cmd, cb)
			if cmd.event then
				events[#events + 1] = copy(cmd.event)
				if opts.synchronous then main.handleEvent(nil, st, cmd.event[1], cmd.event[2], cmd.event[3], cmd.event[4]) end
				return
			end
			builds[#builds + 1] = cmd
			callbacks[#callbacks + 1] = cb
			if opts.reentrant then
				local ev = events[#events]
				main.handleEvent(nil, st, ev[1], ev[2], ev[3], ev[4])
			end
			if opts.synchronous then cb({}, true) end
		end,
	} }
	api, os = env.api, env.os
	if not opts.real_replay then
		main.replay_line = function(wrapped, line, token, _, offset)
			wrapped.api.cmd.sendCommand({ line = line, token = token, offset = offset }, function() handled = handled + 1 end)
			return true
		end
	end
	main.network_run = function() end
	main.loaded_state(env, st)
	logs = {}
	return { main = main, state = st, env = env, vars = vars, events = events, callbacks = callbacks, builds = builds,
		now = function(value) now = value end, handled = function() return handled end,
		receive = function(value) main.receive_line(env, st:get(), value, st) end,
		deliver = function(index)
			local ev = events[index]; assert(ev, "event missing")
			main.handleEvent(nil, st, ev[1], ev[2], ev[3], copy(ev[4]))
		end }
end
local function finish_other(t)
	local s = t.state:get(); s.network_work.pending = 0; t.state:set(s)
	t.main.check_network(t.state)
end

test("busy scheduled receipt does not acknowledge or lose a short incoming line", function()
	local t = setup()
	transport.begin(t.state, "scheduled_client.7"); transport.dispatched(t.state)
	local s = t.state:get(); s.network_work.pending = 1; t.state:set(s)
	t.receive("line peer.1 net X1 test")
	assert(count("net received token=peer.1") == 0 and #t.events == 0)
	assert(not t.state:get().last_line_token and not t.state:get().network_handover)
	finish_other(t)
	t.receive("line peer.1 net X1 test")
	assert(count("net received token=peer.1") == 1 and #t.events == 1)
	assert(t.state:get().network_handover.line == "X1 test")
	t.receive("line peer.1 net X1 test")
	assert(count("net received token=peer.1") == 2 and #t.events == 1)
end)

test("256 KiB payload keeps its final fragment unacknowledged until durable acceptance", function()
	local t = setup()
	transport.begin(t.state, "scheduled_host.8"); transport.dispatched(t.state)
	local s = t.state:get(); s.network_work.pending = 1; t.state:set(s)
	local line = "X1 " .. string.rep("x", transport.MAX_BYTES - 3)
	local n, final = math.ceil(#line / transport.CHUNK)
	for i = 0, n - 1 do
		local part = "part peer.large net " .. i .. " " .. n .. " " .. line:sub(i * transport.CHUNK + 1, (i + 1) * transport.CHUNK)
		t.receive(part); final = part
	end
	assert(count("net partreceived peer.large ") == n - 1)
	assert(count("net received token=peer.large") == 0 and #t.events == 0)
	t.receive(final); assert(count("net partreceived peer.large ") == n - 1)
	assert(#table.concat(t.state:get().bridge_parts.parts) == transport.MAX_BYTES)
	finish_other(t); t.receive(final)
	assert(count("net partreceived peer.large " .. (n - 1)) == 1 and #t.events == 1)
	assert(t.state:get().network_handover.line == line and t.events[1][4].line == nil)
	t.deliver(1); assert(#t.builds == 1 and t.builds[1].line == line)
	t.deliver(1); assert(#t.builds == 1)
end)

test("accepted but lost event is safely redelivered and late duplicates cannot execute", function()
	local t = setup()
	t.receive("line peer.2 net X1 test")
	assert(#t.events == 1 and t.state:get().network_handover.phase == "queued")
	t.vars.TF3MP_IN = nil -- The DLL has already consumed the receipt.
	assert(t.main.bridge_has_work(t.env, t.state:get()))
	t.now(101); t.main.handover_tick(t.env, t.state); assert(#t.events == 1)
	t.now(102); t.main.handover_tick(t.env, t.state); assert(#t.events == 2)
	assert(t.events[1][4].handover_id == t.events[2][4].handover_id)
	t.deliver(2); t.deliver(1)
	assert(#t.builds == 1 and t.state:get().network_work.pending == 1)
	t.now(999); for _ = 1, 100 do t.main.handover_tick(t.env, t.state) end
	assert(#t.events == 2 and #t.builds == 1, "a started engine command must never be redelivered")
	t.main.check_network(t.state)
	assert(not t.state:get().network_done and count("net result peer.2") == 0,
		"a missing native callback cannot be guessed successful or skipped")
	t.callbacks[1]({}, true); t.main.check_network(t.state)
	t.deliver(1); assert(#t.builds == 1 and t.state:get().network_handover.phase == "done")
end)

test("failed durable storage cannot release the final fragment or execute the action", function()
	local t = setup()
	local set = t.state.set
	t.state.set = function(self, value)
		if value.network_handover then error("state write unavailable") end
		return set(self, value)
	end
	local part = "part peer.storage net 0 1 X1 test"
	assert(not pcall(t.receive, part))
	assert(count("net partreceived peer.storage") == 0 and count("net received token=peer.storage") == 0)
	assert(#t.events == 0 and not t.state:get().network_handover)
	t.state.set = set
	t.receive(part)
	assert(count("net partreceived peer.storage 0") == 1 and #t.events == 1)
	assert(t.state:get().network_handover.line == "X1 test")
end)

test("synchronous dispatch survives stale copy writes after the event completes", function()
	local t = setup({ synchronous = true })
	local old = t.state:get()
	t.receive("line peer.sync net X1 test")
	assert(#t.builds == 1 and t.state:get().network_done.token == "peer.sync")
	t.main.store(t.state, old)
	local live = t.state:get()
	assert(live.network_handover.phase == "done" and not live.network_work)
	assert(live.last_line_token == "peer.sync" and live.network_receipt_seq == 1)
	assert(live.network_handover_seq == 1 and live.network_handover_epoch == 1)
	t.receive("line peer.sync net X1 test"); t.deliver(1)
	assert(#t.builds == 1 and #t.events == 1)
end)

test("real W2 and I1 diagnostics complete without native callbacks, including synchronous delivery", function()
	for _, synchronous in ipairs({ false, true }) do
		local t = setup({ real_replay = true, synchronous = synchronous })
		local s = t.state:get()
		s.sync = { world_lists = { [1] = { gt = 200, lists = { hpos = {} } } } }
		t.state:set(s)
		local before = t.state:get()
		t.receive("part peer.world net 0 1 W2 hpos 1 200 1 1 h2_00 0 0 ")
		if not synchronous then t.deliver(1) end
		assert(#t.builds == 0 and not t.state:get().network_work)
		assert(t.state:get().network_handover.phase == "done" and t.state:get().network_done.token == "peer.world")
		assert(count("world diff hpos ck=1 gt=200: 0 only here, 0 only there") == 1)
		t.main.store(t.state, before)
		assert(t.state:get().network_handover.phase == "done" and not t.state:get().network_work)
		t.receive("part peer.issue net 0 1 I1 peer.action none 426175 4772756e64")
		if not synchronous then t.deliver(2) end
		assert(#t.builds == 0 and not t.state:get().network_work)
		assert(t.state:get().network_handover.phase == "done" and t.state:get().network_done.token == "peer.issue")
		assert(count("action issue peer I1 peer.action none 426175 4772756e64") == 1)
		t.deliver(1); t.deliver(2)
		assert(count("action issue peer I1 peer.action none 426175 4772756e64") == 1)
		assert(#t.builds == 0 and not t.state:get().network_work)
	end
end)

test("a reentrant duplicate before dispatched is true still cannot submit a second command", function()
	local t = setup({ reentrant = true })
	t.receive("line peer.reentrant net X1 test"); t.deliver(1)
	assert(#t.builds == 1 and t.state:get().network_work.pending == 1)
end)

test("a delayed prior token is rejected after a newer handover replaces its record", function()
	local t = setup({ synchronous = true })
	t.receive("line peer.old net X1 old"); t.receive("line peer.new net X1 new")
	assert(#t.builds == 2)
	t.deliver(1); t.deliver(2)
	assert(#t.builds == 2 and t.state:get().network_done.token == "peer.new")
end)

test("a pending delivery waits for a scheduled receipt acquired before event arrival", function()
	local t = setup()
	t.receive("line peer.wait net X1 test")
	transport.begin(t.state, "scheduled_client.9"); transport.dispatched(t.state)
	local s = t.state:get(); s.network_work.pending = 1; t.state:set(s)
	t.deliver(1); assert(#t.builds == 0 and t.state:get().network_handover.phase == "queued")
	t.now(103); t.main.handover_tick(t.env, t.state); assert(#t.events == 1)
	finish_other(t); t.main.handover_tick(t.env, t.state); t.deliver(2)
	assert(#t.builds == 1 and t.state:get().network_work.token == "peer.wait")
end)

test("world reload invalidates an accepted but still undelivered event", function()
	local t = setup()
	t.receive("line peer.reload net X1 old")
	t.vars.TF3MP_WORLD = "1-2-4"; t.main.loaded_state(t.env, t.state)
	t.deliver(1)
	assert(#t.builds == 0 and not t.state:get().network_handover and not t.state:get().network_work)
	assert(count("net state work token=- phase=idle pending=0") > 0)
end)

test("the event handler detects a world change before claiming a delayed event", function()
	local t = setup()
	t.receive("line peer.changed net X1 old")
	t.vars.TF3MP_WORLD = "1-2-4"
	t.deliver(1) -- No simulation update or explicit loaded_state call happened first.
	assert(#t.builds == 0 and not t.state:get().network_handover)
	assert(t.state:get().loaded_world == "1-2-4")
end)

test("late old-world callback cannot mutate a reused token or its follow-up mappings", function()
	local t = setup()
	t.receive("line peer.same net X1 old"); t.deliver(1)
	local old_identity = t.state:get().network_work.identity
	t.vars.TF3MP_WORLD = "1-2-4"; t.main.loaded_state(t.env, t.state)
	t.receive("line peer.same net X1 new"); t.deliver(2)
	assert(t.state:get().network_work.identity ~= old_identity)
	t.callbacks[1]({}, true)
	assert(t.handled() == 0 and t.state:get().network_work.pending == 1)
	t.callbacks[2]({}, true); t.main.check_network(t.state)
	assert(t.handled() == 1 and t.state:get().network_done.result == "OK")
end)

test("legacy reload generation also invalidates late events without a changed WORLD value", function()
	local t = setup()
	t.receive("line peer.legacy net X1 old")
	local s = t.state:get(); t.main.reset_loaded_runtime(s); t.state:set(s)
	t.deliver(1); assert(#t.builds == 0)
	t.receive("line peer.legacy net X1 new"); t.deliver(2)
	assert(#t.builds == 1 and t.builds[1].line == "X1 new")
end)

test("unavailable scripting API retains the line without failing or skipping a build", function()
	local t = setup()
	local make = t.env.api.cmd.makeScriptingSendEventCmd
	t.env.api.cmd.makeScriptingSendEventCmd = function() error("event unavailable") end
	t.receive("line peer.unavailable net X1 test")
	assert(t.state:get().network_handover.line == "X1 test" and not t.state:get().network_done)
	assert(#t.builds == 0 and count("net result peer.unavailable") == 0)
	t.env.api.cmd.makeScriptingSendEventCmd = make
	t.now(102); t.main.handover_tick(t.env, t.state); t.deliver(1)
	assert(#t.builds == 1)
end)

test("missing timers still allow bounded event redelivery", function()
	local t = setup(); t.env.os.time = nil
	t.receive("line peer.timer net X1 test")
	for _ = 1, t.main.HANDOVER_RETRY_POLLS - 1 do t.main.handover_tick(t.env, t.state) end
	assert(#t.events == 1)
	t.main.handover_tick(t.env, t.state); assert(#t.events == 2)
end)

test("a GUI heartbeat redelivers an unstarted handover while simulation updates are paused", function()
	local t = setup()
	t.vars.TF3MP_ROLE, t.vars.TF3MP_ORDERING = "client", "1"
	t.main.ACTION_KINDS = {} -- No world polling is needed to exercise the bridge.
	t.receive("line peer.paused net X1 test")
	t.vars.TF3MP_IN = nil -- The native inbox consumed our durable acceptance.
	t.now(102)
	t.main.handleEvent(nil, t.state, "mp_probe", t.main.REPLAY_EVENT, t.main.REPLAY_EVENT,
		{ timeline_tick = true })
	assert(t.state:get().paused_polls == 1 and #t.events == 2 and #t.builds == 0)
	t.deliver(2); assert(#t.builds == 1 and t.state:get().network_work.pending == 1)
	t.now(104)
	t.main.handleEvent(nil, t.state, "mp_probe", t.main.REPLAY_EVENT, t.main.REPLAY_EVENT,
		{ timeline_tick = true })
	assert(#t.events == 2 and #t.builds == 1 and not t.state:get().network_done)
	t.callbacks[1]({}, true)
	t.main.handleEvent(nil, t.state, "mp_probe", t.main.REPLAY_EVENT, t.main.REPLAY_EVENT,
		{ timeline_tick = true })
	assert(t.state:get().network_done.result == "OK")
	assert(count("net state work token=- phase=idle pending=0") == 1)
end)

test("work status publishes bounded phases on change and explicit heartbeat", function()
	local t = setup()
	t.receive("line peer.status net X1 test")
	assert(count("net state work token=peer.status phase=handoff pending=0") == 1)
	t.main.publish_network_work(t.state, false)
	assert(count("net state work token=peer.status phase=handoff pending=0") == 1)
	t.main.publish_network_work(t.state, true)
	assert(count("net state work token=peer.status phase=handoff pending=0") == 2)
	t.deliver(1)
	assert(count("net state work token=peer.status phase=callbacks pending=1") == 1)
	t.callbacks[1]({}, true)
	local s = t.state:get(); s.network_followup = {}; t.state:set(s)
	t.main.publish_network_work(t.state, false)
	assert(count("phase=followup pending=0") == 1)
	s = t.state:get(); s.network_followup = nil; s.weld_checks = {{} }; t.state:set(s)
	t.main.publish_network_work(t.state, false)
	assert(count("phase=weld pending=0") == 1)
	s = t.state:get(); s.weld_checks = nil; t.state:set(s)
	t.main.check_network(t.state)
	assert(count("net state work token=- phase=idle pending=0") == 1)
end)

test("same token with changed payload is not accepted as the queued handover", function()
	local t = setup()
	t.receive("line peer.identity net X1 original")
	logs = {}; t.receive("line peer.identity net X1 changed")
	assert(count("net received token=peer.identity") == 0 and #t.events == 1)
	assert(t.state:get().network_handover.line == "X1 original")
end)

print(string.format("%d handover tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

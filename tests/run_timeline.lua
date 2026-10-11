-- Common simulation stamps under different packet timing; no running game required.
local base_require = require
function require(name)
	if name:sub(1, 1) == "/" then return assert(loadfile("mods/mp_probe/content" .. name))() end
	return base_require(name)
end
local timeline, wire = require("/mp_probe/timeline.lua"), require("/mp_probe/wire.lua")
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function pair() return { h = timeline.new("host"), c = timeline.new("client"), ht = 0, ct = 0 } end
local function packet(v) return "S1 " .. wire.encode(v) end
local function pump(p)
	for _ = 1, 100 do
		local changed = false
		local h = timeline.take(p.h)
		if h then assert(timeline.receive(p.c, h, p.ct)); changed = true end
		local c = timeline.take(p.c)
		if c then assert(timeline.receive(p.h, c, p.ht)); changed = true end
		if not changed then return end
	end
	error("message loop")
end
local function prepare(p, line)
	assert(timeline.submit(p.h, line or "A1 command", true))
	assert(not timeline.step(p.h, p.ht, p.ct)); pump(p)
	assert(p.h.active.phase == "committed" and p.c.active.phase == "committed")
	return p.h.active.at
end
local function execute(p, at)
	p.ht, p.ct = at, at
	assert(not timeline.step(p.h, at, at)); assert(not timeline.step(p.c, at, at)); pump(p)
	local h = assert(timeline.step(p.h, at, at)); pump(p)
	local c = assert(timeline.step(p.c, at, at)); pump(p)
	return h, c
end
local function complete(p)
	assert(timeline.complete(p.h, p.h.active.seq, true)); assert(timeline.complete(p.c, p.c.active.seq, true)); pump(p)
	timeline.step(p.h, p.ht, p.ct); pump(p)
end

test("already executed observations never enter the common time path", function()
	local m = timeline.new("host")
	local ok, err = timeline.submit(m, "B5 already built", false)
	assert(not ok and err:find("pre%-execution") and #m.queue == 0 and not m.error)
end)
test("both engines execute once at the same simulation tick after both reach its barrier", function()
	local p = pair(); local at = prepare(p)
	for gt = 0, at - timeline.STEP, timeline.STEP do
		p.ht, p.ct = gt, gt; assert(not timeline.step(p.h, gt, gt)); assert(not timeline.step(p.c, gt, gt)); pump(p)
	end
	local h, c = execute(p, at)
	assert(h.at == c.at and h.line == c.line and h.seq == c.seq and h.origin == "host")
	assert(not timeline.step(p.h, at, at) and not timeline.step(p.c, at, at))
	assert(timeline.clock(p.h).hold == 1 and timeline.clock(p.c).hold == 1)
	complete(p)
	assert(not p.h.active and not p.c.active and p.h.last == 1 and p.c.last == 1)
	assert(timeline.clock(p.h).hold == 0)
end)
test("a slow peer reaches the same stamp before either engine starts", function()
	local p = pair(); local at = prepare(p)
	p.ht = at; assert(not timeline.step(p.h, at, 0)); pump(p)
	assert(timeline.clock(p.h).hold == 1 and not p.h.active.executed)
	for gt = 0, at - timeline.STEP, timeline.STEP do p.ct = gt; assert(not timeline.step(p.c, gt, at)); pump(p) end
	p.ct = at; assert(not timeline.step(p.c, at, at)); pump(p)
	local h = assert(timeline.step(p.h, at, at)); pump(p)
	local c = assert(timeline.step(p.c, at, at)); assert(h.at == c.at)
end)
test("client and host requests receive one common sequence and callbacks gate the next command", function()
	local p = pair()
	assert(timeline.submit(p.h, "A1 host", true)); assert(timeline.submit(p.c, "B5 client", true)); pump(p)
	timeline.step(p.h, 0, 0); pump(p)
	local at = p.h.active.at; local h, c = execute(p, at)
	assert(h.seq == 1 and c.seq == 1 and h.line == "A1 host")
	assert(timeline.complete(p.h, 1, true)); pump(p); timeline.step(p.h, at, at)
	assert(p.h.active.seq == 1, "one result cannot release the next command")
	assert(timeline.complete(p.c, 1, true)); pump(p); timeline.step(p.h, at, at); pump(p)
	timeline.step(p.h, at, at); pump(p)
	assert(p.h.active.seq == 2 and p.c.active.line == "B5 client" and p.c.active.origin == "client")
end)
test("a pause that lands a tick late still meets at the barrier (v34)", function()
	local p = pair(); local at = prepare(p)
	local late = at + timeline.STEP
	assert(not timeline.step(p.h, late, 0) and not p.h.error)
	assert(timeline.clock(p.h).hold == 1 and not p.h.active.executed)
	p.ct = at; assert(not timeline.step(p.c, at, late)); pump(p)
	local h = assert(timeline.step(p.h, late, at)); pump(p)
	local c = assert(timeline.step(p.c, at, late))
	assert(h.gt == late and c.gt == at and h.seq == c.seq and not p.h.error and not p.c.error)
end)
test("a late plan or commit no longer stops the session (v34)", function()
	local p = pair(); assert(timeline.submit(p.h, "A1 command", true)); timeline.step(p.h, 0, 0)
	local plan = timeline.take(p.h); local at = p.h.active.at
	assert(timeline.receive(p.c, plan, at + 5 * timeline.STEP) and not p.c.error)
	pump(p); assert(p.h.active.phase == "committed" and p.c.active.phase == "committed")
end)
test("an engine busy at the barrier retries the same command once it is free", function()
	local p = pair(); local at = prepare(p)
	local h = select(1, execute(p, at))
	timeline.retry(p.h)
	assert(not p.h.active.executed and timeline.clock(p.h).hold == 1)
	local again = assert(timeline.step(p.h, at, at))
	assert(again.seq == h.seq and again.line == h.line)
end)
test("lost commit delivery holds both clocks at the stamp and can recover there", function()
	local p = pair(); assert(timeline.submit(p.h, "A1 command", true)); timeline.step(p.h, 0, 0)
	assert(timeline.receive(p.c, timeline.take(p.h), 0))
	assert(timeline.receive(p.h, timeline.take(p.c), 0))
	local delayed = timeline.take(p.h); local at = p.h.active.at
	p.ht, p.ct = at, at
	assert(not timeline.step(p.h, at, at)); assert(not timeline.step(p.c, at, at)); pump(p)
	-- Host may issue GO only after client has accepted COMMIT and acknowledged that fact.
	assert(not timeline.step(p.h, at, at) and not p.c.active.executed and not p.h.active.executed)
	assert(timeline.receive(p.c, delayed, at)); pump(p)
	assert(not timeline.step(p.c, at, at)); pump(p)
	assert(timeline.step(p.h, at, at)); pump(p)
	assert(timeline.step(p.c, at, at))
end)
test("errors remain held and propagate to the partner", function()
	local p = pair(); local at = prepare(p); execute(p, at)
	local ok = timeline.complete(p.h, 1, false); assert(not ok)
	local fail = timeline.take(p.h); assert(fail)
	assert(not timeline.receive(p.c, fail, at))
	assert(timeline.clock(p.h).phase == "failed" and timeline.clock(p.c).hold == 1)
end)
test("missing partner clock never releases a held request", function()
	local p = pair(); assert(timeline.submit(p.h, "A1 command", true))
	assert(not timeline.step(p.h, 0, nil)); assert(not p.h.active and #p.h.queue == 1)
end)
test("conflicting plans and sequence gaps are rejected", function()
	local c = timeline.new("client")
	assert(not timeline.receive(c, packet({ op = "plan", seq = 2, at = 4000, line = "A1 x", origin = "host" }), 0))
	c = timeline.new("client")
	assert(timeline.receive(c, packet({ op = "plan", seq = 1, at = 4000, line = "A1 x", origin = "host" }), 0))
	assert(not timeline.receive(c, packet({ op = "plan", seq = 1, at = 4000, line = "A1 y", origin = "host" }), 0))
end)
test("invalid timestamps, malformed inputs, queue overflow and wrong result ids are bounded", function()
	assert(not timeline.receive(timeline.new("host"), nil, 0))
	assert(not timeline.receive(timeline.new("host"), packet({ op = "request", origin = "client" }), 0))
	assert(not timeline.step(timeline.new("host"), 201, 0))
	local m = timeline.new("host")
	for _ = 1, timeline.MAX_QUEUE do assert(timeline.submit(m, "A1 x", true)) end
	assert(not timeline.submit(m, "A1 x", true) and #m.queue == timeline.MAX_QUEUE)
	m = timeline.new("client")
	for _ = 1, timeline.MAX_QUEUE do assert(timeline.submit(m, "A1 x", true)); assert(timeline.take(m)) end
	assert(not timeline.submit(m, "A1 x", true) and m.pending_requests == timeline.MAX_QUEUE and #m.out == 0)
	assert(not timeline.complete(timeline.new("host"), 1, true))
end)
test("completed requests cannot be executed again through duplicate request messages", function()
	local p = pair(); assert(timeline.submit(p.c, "A1 from client", true))
	local request = timeline.take(p.c); assert(timeline.receive(p.h, request, 0))
	timeline.step(p.h, 0, 0); pump(p); local at = p.h.active.at
	execute(p, at); complete(p)
	assert(p.c.pending_requests == 0)
	assert(timeline.receive(p.h, request, at) and #p.h.queue == 0)
end)
test("vehicle barriers finish without advancing paused or widely separated clocks", function()
	for _, times in ipairs({ { 0, 0 }, { 1402000, 0 }, { 0, 1402000 } }) do
		for _, origin in ipairs({ "host", "client" }) do
			local p = pair(); p.ht, p.ct = times[1], times[2]
			assert(timeline.submit(origin == "host" and p.h or p.c, "A1 vehicle", true, { barrier = true })); pump(p)
			local count_h, count_c = 0, 0
			for _ = 1, 20 do
				local h = timeline.step(p.h, p.ht, p.ct); pump(p)
				local c = timeline.step(p.c, p.ct, p.ht); pump(p)
				if h then assert(h.barrier); count_h = count_h + 1; assert(timeline.complete(p.h, h.seq, true)) end
				if c then assert(c.barrier); count_c = count_c + 1; assert(timeline.complete(p.c, c.seq, true)) end
				pump(p)
			end
			assert(count_h == 1 and count_c == 1 and not p.h.active and not p.c.active)
			assert(timeline.clock(p.h).hold == 0 and timeline.clock(p.c).hold == 0)
			assert(not p.h.error and not p.c.error)
		end
	end
end)
test("paused builds and large time skew use a ready barrier instead of a future clock", function()
	for _, options in ipairs({ { now = 0, peer = 0, paused = true }, { now = 0, peer = 1402000 } }) do
		local p = pair(); p.ht, p.ct = options.now, options.peer
		assert(timeline.submit(p.h, "B5 build", true))
		timeline.step(p.h, p.ht, p.ct, options); pump(p)
		assert(p.h.active.barrier and p.c.active.barrier)
		assert(timeline.clock(p.h).hold == 1 and timeline.clock(p.c).hold == 1)
		for _ = 1, 10 do
			local h = timeline.step(p.h, p.ht, p.ct); pump(p)
			local c = timeline.step(p.c, p.ct, p.ht); pump(p)
			if h then timeline.complete(p.h, h.seq, true) end
			if c then timeline.complete(p.c, c.seq, true) end
			pump(p)
		end
		assert(p.h.last == 1 and p.c.last == 1 and not p.h.active and not p.c.active)
	end
end)
test("a plan waits for previously captured purchase and line dependencies", function()
	local p = pair(); assert(timeline.submit(p.h, "A1 vehicle", true, { barrier = true }))
	timeline.step(p.h, 0, 0, { dependencies = true }); assert(not p.h.active and not timeline.take(p.h))
	timeline.step(p.h, 0, 0); pump(p)
	assert(p.h.active and p.c.active and p.h.active.barrier)
end)
test("an unconfirmed engine pause cannot acknowledge arrival at a ready barrier", function()
	local p = pair(); assert(timeline.submit(p.h,"A1 vehicle",true,{barrier=true}))
	timeline.step(p.h,0,0,{stopped=false}); pump(p)
	timeline.step(p.h,0,0,{stopped=false}); timeline.step(p.c,0,0,{stopped=true}); pump(p)
	assert(not p.h.active.arrived and p.c.active.arrived)
	assert(not p.h.active.go and not p.c.active.go)
	timeline.step(p.h,0,0,{stopped=true}); pump(p)
	assert(p.h.active.arrived and p.c.active.go)
end)
test("duplicate plans cannot change an already accepted barrier mode", function()
	local c = timeline.new("client")
	local v = { op = "plan", seq = 1, at = 4000, line = "A1 x", origin = "host", barrier = true }
	assert(timeline.receive(c, packet(v), 0)); assert(timeline.receive(c, packet(v), 0))
	v.barrier = false; assert(not timeline.receive(c, packet(v), 0))
end)
test("adjacent commit and arrival share one order but cannot execute before both arrive", function()
	local p = pair()
	assert(timeline.submit(p.h, "A1 held", true, {barrier=true}))
	timeline.step(p.h, 0, 0)
	assert(timeline.receive(p.c, timeline.take_batch(p.h), 0))
	assert(timeline.receive(p.h, timeline.take_batch(p.c), 0))
	timeline.step(p.h, 0, 0, {stopped=true})
	local batch = assert(timeline.take_batch(p.h))
	assert(wire.decode(batch:sub(4)).op == "batch" and #p.h.out == 0)
	assert(timeline.receive(p.c, batch, 0))
	assert(p.c.active.phase == "committed" and p.c.active.peer_arrived and not p.c.active.go)
	timeline.step(p.c, 0, 0, {stopped=true})
	assert(timeline.receive(p.h, timeline.take_batch(p.c), 0))
	assert(timeline.step(p.h, 0, 0, {stopped=true}))
	assert(timeline.receive(p.c, timeline.take_batch(p.h), 0))
	assert(timeline.step(p.c, 0, 0, {stopped=true}))
	complete(p)
	assert(p.h.last == 1 and p.c.last == 1 and not p.c.active)
end)

test("malformed, nested and executable timeline batch members cannot bypass the barrier", function()
	for _, bad in ipairs({ packet(7), packet({op="batch",lines={}}),
		packet({op="plan",seq=1,at=0,line="A1 x",origin="host"}), packet({op="request",line="A1 x"}), packet({op="unknown"}) }) do
		local c = timeline.new("client")
		local ok, err = timeline.receive(c, packet({op="batch",lines={packet({op="arrived",seq=1,at=0}),bad}}), 0)
		assert(not ok and err and not c.active)
	end
	for _,lines in ipairs({{[1]=packet({op="ready"}),[3]=packet({op="go"})},
		{packet({op="ready"}),packet({op="go"}),extra=packet({op="done"})}}) do
		local c=timeline.new("client")
		assert(not timeline.receive(c,packet({op="batch",lines=lines}),0) and not c.active)
	end
end)

print(string.format("%d timeline tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

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
test("late or skipped simulation ticks fail instead of executing the command late", function()
	local p = pair(); local at = prepare(p)
	local action, err = timeline.step(p.h, at + timeline.STEP, 0)
	assert(not action and err:find("no late replay", 1, true))
	assert(timeline.clock(p.h).hold == 1 and not p.h.active.executed)
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
print(string.format("%d timeline tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

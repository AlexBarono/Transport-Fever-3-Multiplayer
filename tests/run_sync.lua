-- Offline tests for keeping two games in step (sync.lua, gui.lua, main.sync_tick), probes v24 and v25.
-- Two mock games are linked by a fake DLL: a "net state <key> <text>" line one game logs lands in
-- its own TF3MP_OWN_<KEY> and in the other game's TF3MP_PEER_<KEY> at once.
-- As in TF3 (run 25), a command with a result callback fails in the simulation's update(); script
-- events reach handleEvent after the update (or right away, with events_now), where callbacks work.
-- Run from the repository root: python3 tools/run_lua.py tests/run_sync.lua
local MOD_ROOT = "mods/mp_probe/content"
local real_require = require
local loaded = {}
function require(name)
	if type(name) == "string" and name:sub(1, 1) == "/" then
		if loaded[name] == nil then loaded[name] = assert(loadfile(MOD_ROOT .. name))() end
		return loaded[name]
	end
	return real_require(name)
end

local current -- the game whose globals are active
function debugPrint(...)
	local line = table.concat({ ... }, " ")
	if current then current.print(line) end
end

local sync = require("/mp_probe/sync.lua")
local gui = require("/mp_probe/gui.lua")
data = nil
assert(loadfile(MOD_ROOT .. "/mp_probe/main.script.lua"))()
local main = data()

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

local function has(lines, needle)
	for _, l in ipairs(lines) do if l:find(needle, 1, true) then return l end end
	return nil
end

local function count(lines, needle)
	local n = 0
	for _, l in ipairs(lines) do if l:find(needle, 1, true) then n = n + 1 end end
	return n
end

--- Days to a date table and back (for the mock calendar).
local function date_of(days)
	-- Inverse of sync.days (civil_from_days).
	local z = days + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then y = y + 1 end
	return { year = y, month = m, day = d }
end

local function copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = copy(x) end
	return t
end

local function game(role)
	-- The one-time journal test has its own test below.
	local g = { role = role, logs = {}, sent = {}, vars = { TF3MP_ROLE = role }, s = { journal_test = main.PROBE_VERSION },
		speed = 1, gt = 0, clock = 0, balance = 1000000, loan = 0, lines = 3, veh = 5, st = 4, con = 2,
		date_base = sync.days(2026, 1, 1), ms_per_day = 600000, date_shift = 0, book_works = true,
		events = {}, events_sent = 0 }
	-- The script state hands out copies, like the game's state:get().
	g.state = { get = function() return copy(g.s) end, set = function(_, v) g.s = copy(v) end }
	local ct = {}
	for _, k in ipairs({ "GAME_SPEED", "GAME_TIME", "ACCOUNT", "TRANSPORT_VEHICLE", "STATION", "CONSTRUCTION",
		"PLAYER_OWNED" }) do ct[k] = k end
	local function today(gt) return g.date_base + math.floor(gt / g.ms_per_day) + g.date_shift end
	local engine = { util = {}, system = { lineSystem = {} } }
	function engine.util.getWorld() return 1 end
	function engine.util.getPlayer() return 7 end
	function engine.util.getCalendarDate(gt) return date_of(today(gt)) end
	function engine.system.lineSystem.getLines()
		local out = {}; for i = 1, g.lines do out[i] = 500 + i end; return out
	end
	function engine.getComponent(id, c)
		if c == "GAME_SPEED" then return { speedup = g.speed, millisPerDay = g.speed > 0 and g.ms_per_day or 0 } end
		if c == "GAME_TIME" then return { gameTime = g.gt } end
		if c == "ACCOUNT" then assert(id == 7); return { balance = g.balance, loan = g.loan } end
		if c == "PLAYER_OWNED" then return id < 3000 + g.con and { player = 7 } or { player = 9 } end
		return nil
	end
	function engine.forEachEntityWithComponent(fn, c)
		local n = ({ TRANSPORT_VEHICLE = g.veh, STATION = g.st, CONSTRUCTION = g.con + 4 })[c]
		local base = ({ TRANSPORT_VEHICLE = 1000, STATION = 2000, CONSTRUCTION = 3000 })[c]
		for i = 0, n - 1 do fn(base + i) end
	end
	local JE = { Type = { LOAN = 0, CONSTRUCTION = 2, OTHER = 6 }, Other = { CHEAT = 3 } }
	function JE.new() return { amount = 0, time = 0, category = { type = 0, other = 0 } } end
	local cmd = {}
	function cmd.makeJournalBookAssetCmd(player, entry) return { name = "book", player = player, entry = entry } end
	function cmd.makeGameSetDateCmd(date) return { name = "date", date = date } end
	function cmd.makeGameSetSpeedCmd(speed) return { name = "speed", speed = speed } end
	function cmd.makeScriptingSendEventCmd(a, b, c, d) return { name = "event", args = { a, b, c, d } } end
	function cmd.sendCommand(c, callback)
		if callback and g.context == "update" then error("Callbacks are currently disallowed") end
		if c.name == "event" then
			g.events_sent = g.events_sent + 1
			if g.events_now then g.handle(c.args) else g.events[#g.events + 1] = c.args end
			return
		end
		g.sent[#g.sent + 1] = c
		if c.name == "book" and g.book_works then
			local kind = c.entry.category.type
			if kind == JE.Type.LOAN then g.loan, g.balance = g.loan + c.entry.amount, g.balance + c.entry.amount
			elseif kind == JE.Type.OTHER then g.balance = g.balance + c.entry.amount end
		elseif c.name == "date" then
			g.date_shift = g.date_shift + sync.days(c.date.year, c.date.month, c.date.day) - today(g.gt)
		elseif c.name == "speed" and not g.speed_broken then
			g.speed = c.speed
		end
		if callback then callback({}, not (c.name == "book" and g.book_rejects)) end
	end
	g.api = { engine = engine, cmd = cmd,
		type = { ComponentType = ct, JournalEntry = JE,
			Date = { addOffsetDays = function(d, n) return date_of(sync.days(d.year, d.month, d.day) + n) end } } }
	g.os = { getenv = function(name) return g.vars[name] end, clock = function() return g.clock end }
	g.env = { api = g.api, os = g.os }
	function g.print(line)
		g.logs[#g.logs + 1] = line
		local key, text = line:match("net state (%a+) (.*)$")
		if key then
			g.vars["TF3MP_OWN_" .. key:upper()] = text
			if g.peer then g.peer.vars["TF3MP_PEER_" .. key:upper()] = text end
		end
	end
	--- Runs fn with this game's globals (main.script reads _G).
	function g.run(fn)
		local old_api, old_os, old_current = api, os, current
		api, current = g.api, g
		os = setmetatable({ getenv = g.os.getenv, clock = g.os.clock }, { __index = old_os })
		local ok, err = pcall(fn)
		api, os, current = old_api, old_os, old_current
		assert(ok, err)
	end
	--- One script event in handleEvent.
	function g.handle(args)
		local before = g.context
		g.context = "event"
		main.handleEvent(nil, g.state, args[1], args[2], args[3], args[4])
		g.context = before
	end
	--- One simulation update (the sync part of main.update), then the events it sent.
	function g.tick()
		g.gt = g.gt + 200
		g.run(function()
			g.context = "update"
			local s = g.state:get()
			main.sync_tick(_G, s)
			main.sync_send_fix(_G, g.state, s)
			g.state:set(s)
			g.context = nil
			while #g.events > 0 do g.handle(table.remove(g.events, 1)) end
		end)
	end
	--- One GUI step (gui.update keeps its memory in g.env).
	function g.gui(dt)
		g.clock = g.clock + (dt or 0.3)
		g.run(function() gui.update(g.env) end)
	end
	return g
end

local function pair()
	local host, client = game("host"), game("client")
	host.peer, client.peer = client, host
	return host, client
end

--- Both games run n updates side by side.
local function run(host, client, n)
	for _ = 1, n do host.tick(); client.tick() end
end

-- ---------------------------------------------------------------------------------------------
-- State texts, dates, checkpoints

test("state texts keep numbers, words and negative values", function()
	local t = sync.decode(sync.encode({ speed = 0, ver = 12, by = "host", money = -2500, date = "2026-10-07", x = 1.5 }))
	assert(t.speed == 0 and t.ver == 12 and t.by == "host" and t.money == -2500 and t.date == "2026-10-07" and t.x == 1.5)
	assert(sync.decode("") == nil and sync.decode(nil) == nil and sync.decode("garbage") == nil)
	assert(sync.encode({ name = "a b=c" }) == "name=a_b_c")
end)

test("day counting matches the calendar, leap years included", function()
	assert(sync.days(1970, 1, 1) == 0 and sync.days(2000, 3, 1) == 11017 and sync.days(1850, 1, 1) == -43829)
	assert(sync.day_diff("2026-12-31", "2027-01-01") == 1 and sync.day_diff("2024-02-28", "2024-03-01") == 2)
	assert(sync.day_diff("2023-02-28", "2023-03-01") == 1 and sync.day_diff("2026-05-10", "2026-05-07") == -3)
	assert(sync.day_diff("x", "2026-01-01") == nil)
	for _, d in ipairs({ -100000, -1, 0, 59, 11017, 20000 }) do
		local t = date_of(d); assert(sync.days(t.year, t.month, t.day) == d, d)
	end
end)

test("a checkpoint falls on the first update of each minute of game time", function()
	assert(sync.at_checkpoint(0) and sync.at_checkpoint(60000) and sync.at_checkpoint(3120000))
	assert(not sync.at_checkpoint(60200) and not sync.at_checkpoint(59800))
	assert(sync.at_checkpoint(60100) and sync.checkpoint_of(60100) == 1)
	local list = nil
	for k = 1, 12 do list = sync.keep(list, k, { k = k }) end
	assert(#list == sync.KEEP and list[1].k == 5 and sync.find(list, 12).k == 12 and sync.find(list, 4) == nil)
	list = sync.keep(list, 10, { again = true })
	assert(list[#list].k == 10 and list[#list].v.again and sync.find(list, 11) == nil)
end)

-- ---------------------------------------------------------------------------------------------
-- Game speed (sync.speed_step)

--- Two speed registers talking through their published texts.
local function speed_pair()
	local p = { host = { mem = {}, speed = 1, gt = 0, role = "host" }, client = { mem = {}, speed = 1, gt = 0, role = "client" } }
	p.now = 0
	function p.step(side, hold)
		local me, other = p[side], p[side == "host" and "client" or "host"]
		local out = sync.speed_step(me.mem, { own = me.speed, own_t = me.gt, role = me.role, peer = other.state,
			now = p.now, hold = hold ~= false, src = "gui" })
		if out.publish then me.state = sync.decode(out.publish) end
		if out.command and not me.broken then me.speed = out.command end
		me.out = out
		return out
	end
	--- Both change at the same moment: neither has seen the other's change yet.
	function p.concurrent()
		p.now = p.now + 0.3
		local hs, cs = p.host.state, p.client.state
		p.client.state = cs; p.step("host")
		local new_host = p.host.state
		p.host.state = hs; p.step("client")
		p.host.state = new_host
	end
	function p.both(n, dt)
		for _ = 1, n or 1 do
			p.now = p.now + (dt or 0.3)
			p.step("host"); p.step("client")
		end
	end
	return p
end

test("at the start the client takes the host's speed", function()
	local p = speed_pair(); p.host.speed, p.client.speed = 2, 1
	p.both(2)
	assert(p.client.speed == 2 and p.host.speed == 2, p.client.speed)
end)

test("a pause in one game pauses the other, and starting again starts both", function()
	local p = speed_pair(); p.both(2)
	p.host.speed = 0; p.both(2)
	assert(p.client.speed == 0 and p.client.mem.ver == 1)
	p.client.speed = 4; p.both(2)
	assert(p.host.speed == 4 and p.client.speed == 4 and p.host.mem.ver == 2 and p.host.mem.by == "client")
end)

test("changes at the same moment end with the host's speed in both games", function()
	local p = speed_pair(); p.both(2)
	p.host.speed, p.client.speed = 2, 4
	p.concurrent()
	assert(p.host.mem.ver == 1 and p.client.mem.ver == 1)
	p.both(3)
	assert(p.host.speed == 2 and p.client.speed == 2, p.host.speed .. "/" .. p.client.speed)
end)

test("a speed command on its way is not taken for the player's change, and is sent again", function()
	local mem = {}
	local function step(own, now, peer)
		return sync.speed_step(mem, { own = own, own_t = 0, role = "client", peer = peer, now = now, src = "gui" })
	end
	step(1, 0)
	local peer = { speed = 0, ver = 3, by = "host", hb = 1, gt = 0, run = 0 }
	local out = step(1, 1, peer); assert(out.command == 0)
	out = step(1, 2, peer); assert(out.command == nil and mem.ver == 3, "counted as own change")
	out = step(1, 4.5, peer); assert(out.command == 0 and mem.tries == 1)
	step(1, 8, peer); step(1, 11.5, peer); out = step(1, 15, peer)
	assert(mem.broken and has(out.logs, "could not be set"))
	-- Without working commands the player's changes still go out, once each.
	out = step(2, 16, peer); assert(mem.ver == 4 and mem.speed == 2)
	out = step(2, 17, peer); assert(mem.ver == 4 and #out.logs == 0)
end)

test("the game behind runs at twice the speed until it caught up", function()
	local p = speed_pair(); p.both(2)
	-- Game time goes out with the heartbeat.
	p.host.gt = 60000; p.both(1, 2.1)
	assert(p.client.speed == 2 and p.host.speed == 1 and has(p.client.out.logs, "behind"))
	-- The shared speed stays 1; the faster run is not a change by the player.
	assert(p.client.mem.speed == 1 and p.client.mem.ver == 0)
	p.both(3)
	assert(p.client.speed == 2 and p.host.mem.ver == 0, "the faster run went back to the host as a change")
	p.client.gt = 58000; p.both(1, 2.1)
	assert(p.client.speed == 1 and has(p.client.out.logs, "caught up"))
end)

test("at the highest speed the game ahead slows down instead", function()
	local p = speed_pair(); p.host.speed = 4; p.both(2)
	p.host.gt = 60000; p.both(1, 2.1)
	assert(p.client.speed == 4 and p.host.speed == 2 and has(p.host.out.logs, "slowing down"))
end)

test("far ahead the GUI waits at speed 0, the simulation does not", function()
	local p = speed_pair(); p.both(2)
	p.client.gt = 200000; p.both(2, 2.1)
	assert(p.client.speed == 0 and p.host.speed == 2 and p.client.mem.catchup == "hold")
	assert(p.client.mem.speed == 1, "waiting changed the shared speed")
	local q = speed_pair(); q.both(2)
	q.client.gt = 200000
	for _ = 1, 2 do q.now = q.now + 2.1; q.step("host", false); q.step("client", false) end
	assert(q.client.speed == 1 and q.host.speed == 2)
end)

test("no catching up without news from the other game, while paused, or when the games are far apart", function()
	local p = speed_pair(); p.both(2)
	p.host.gt = 60000; p.now = p.now + 2.1; p.step("host"); p.step("client")
	assert(p.client.speed == 2)
	-- The host says nothing more (its game hangs); after PEER_STALE_S the client stops catching up.
	local logs = {}
	for _ = 1, 30 do
		p.now = p.now + 0.3; p.step("client")
		for _, l in ipairs(p.client.out.logs) do logs[#logs + 1] = l end
	end
	assert(p.client.speed == 1 and has(logs, "no news from the other game"), "stale news")
	local q = speed_pair(); q.host.speed = 0; q.both(2)
	q.host.gt = 600000; q.both(2, 2.1); assert(q.client.speed == 0)
	local r = speed_pair(); r.both(2)
	r.host.gt = sync.FAR_MS + 600000; r.both(2, 2.1)
	assert(r.client.speed == 1 and r.host.speed == 1 and r.client.mem.far)
end)

test("the state goes out on every change and as a heartbeat, with the game time", function()
	local mem = {}
	local out = sync.speed_step(mem, { own = 1, own_t = 400, role = "host", now = 0, src = "gui" })
	assert(out.publish and sync.decode(out.publish).gt == 400 and sync.decode(out.publish).hb == 1)
	out = sync.speed_step(mem, { own = 1, own_t = 600, role = "host", now = 0.3, src = "gui" })
	assert(out.publish == nil)
	out = sync.speed_step(mem, { own = 1, own_t = 600, role = "host", now = 2.4, src = "gui" })
	assert(out.publish and sync.decode(out.publish).hb == 2)
	out = sync.speed_step(mem, { own = 0, own_t = 600, role = "host", now = 2.5, src = "gui" })
	assert(out.publish and sync.decode(out.publish).speed == 0)
end)

test("a GUI state that lost its memory takes the register back from what it said last", function()
	local mem = {}
	sync.speed_step(mem, { own = 1, own_t = 0, role = "client", now = 0, src = "gui" })
	local out = sync.speed_step(mem, { own = 2, own_t = 0, role = "client", now = 1, src = "gui" })
	local said = sync.decode(out.publish)
	local fresh = {}
	out = sync.speed_step(fresh, { own = 2, own_t = 0, role = "client", now = 1.2, src = "gui", restore = said })
	assert(fresh.ver == said.ver and fresh.speed == 2 and fresh.restores == 1 and #out.logs == 0)
	-- A text written by the simulation's stand-in is not taken by the GUI.
	local other = {}
	sync.speed_step(other, { own = 1, own_t = 0, role = "client", now = 1.2, src = "gui",
		restore = { src = "sim", ver = 9, speed = 4 } })
	assert(other.ver == 0)
end)

-- ---------------------------------------------------------------------------------------------
-- The GUI script through the fake DLL

test("the GUI scripts of both games pass a pause on, through the DLL", function()
	local host, client = pair()
	host.gt, client.gt = 60000, 60000
	for _ = 1, 3 do host.gui(); client.gui() end
	assert(has(host.logs, "gui script running") and has(host.logs, "gui speed command test: 1x, success=true"))
	assert(host.vars.TF3MP_OWN_GUI and client.vars.TF3MP_PEER_GUI)
	host.speed = 0
	for _ = 1, 3 do host.gui(); client.gui() end
	assert(client.speed == 0 and has(client.logs, "sync speed from the other game: paused"))
	client.speed = 2
	for _ = 1, 3 do host.gui(); client.gui() end
	assert(host.speed == 2, host.speed)
	-- Steps come at most every gui.INTERVAL seconds.
	local n = #client.logs
	for _ = 1, 5 do client.gui(0.01) end
	assert(#client.logs == n)
end)

test("the GUI script does nothing without DLL v8 and only marks itself in a loopback test", function()
	local g = game("loopback"); g.vars.TF3MP_ROLE = nil
	g.gui(); assert(#g.sent == 0 and has(g.logs, "gui script running"))
	local l = game("loopback")
	l.gui(); l.gui(); l.gui()
	assert(count(l.logs, "net state gui") == 1 and #l.sent == 1 and l.sent[1].name == "speed")
end)

-- ---------------------------------------------------------------------------------------------
-- Checkpoints in the simulation (main.sync_tick)

test("both games record a checkpoint each minute and find each other the same", function()
	local host, client = pair()
	-- The host reads every SYNC_READ_EVERY updates; the client's checkpoint comes after its own.
	run(host, client, 305)
	assert(has(host.logs, "net state sim ") and has(client.logs, "sync: this game is the client"))
	local check = has(client.logs, "sync check 1 (2026-01-01): same")
	assert(has(client.logs, "net state sim adj=0 ck=1 con=2 date=2026-01-01 gt=60000 lines=3 loan=0 money=1000000 st=4 veh=5"))
	assert(has(host.logs, "net state sim ck=1 con=2 date=2026-01-01 gt=60000 lines=3 loan=0 money=1000000 st=4 veh=5"))
	assert(check, "no comparison")
	assert(has(host.logs, "sync check 1 (2026-01-01): same"))
	assert(not has(client.logs, "WARNING"))
end)

test("lasting money difference: the client books it once, the host never", function()
	local host, client = pair()
	run(host, client, 299)
	client.balance = host.balance - 50000
	run(host, client, 300)
	assert(has(client.logs, "sync check 1"), "check 1")
	local books = {}
	for _, c in ipairs(client.sent) do if c.name == "book" then books[#books + 1] = c end end
	assert(#books == 0, "booked after one difference")
	run(host, client, 300)
	books = {}
	for _, c in ipairs(client.sent) do if c.name == "book" then books[#books + 1] = c end end
	assert(#books == 1 and books[1].entry.amount == 50000 and books[1].entry.category.type == 6, #books)
	assert(books[1].entry.category.other == 3 and books[1].player == 7)
	assert(client.balance == host.balance)
	for _, c in ipairs(host.sent) do assert(c.name ~= "book", "host booked") end
	assert(has(client.logs, "sync WARNING: the games differ: money here"))
	run(host, client, 600)
	assert(has(client.logs, "the money correction by 50000 worked"))
	assert(#client.sent == 1)
end)

test("the booking goes to handleEvent as a script event and is counted in the next checkpoint", function()
	for _, now in ipairs({ false, true }) do
		local host, client = pair()
		client.events_now = now
		run(host, client, 299)
		client.balance = host.balance - 50000
		run(host, client, 600)
		assert(client.events_sent == 1 and client.balance == host.balance, tostring(now))
		assert(has(client.logs, "sync: money differs by 50000 from the host's, booking it"))
		assert(has(client.logs, "sync: money correction sent (amount 50000, other CHEAT, type OTHER)"))
		assert(has(client.logs, "sync: money corrected by 50000, success=true"))
		-- What handleEvent noted survives the update that sent the event.
		assert(client.s.sync.adj == 50000 and client.s.sync.fixes.money, tostring(now))
		run(host, client, 300)
		assert(has(client.logs, "net state sim adj=50000 ck=3 "), tostring(now))
		assert(has(client.logs, "the money correction by 50000 worked") and client.s.sync.fixes.money == nil)
	end
end)

test("a booking the game rejects turns the money correction off at once", function()
	local host, client = pair()
	client.book_rejects = true
	run(host, client, 299)
	client.balance = host.balance - 50000
	run(host, client, 1500)
	local books = 0
	for _, c in ipairs(client.sent) do if c.name == "book" then books = books + 1 end end
	assert(books == 1, books)
	assert(has(client.logs, "money corrected by 50000, success=false; money is no longer corrected"))
	assert(client.s.sync.off.money and not client.s.sync.adj and not has(client.logs, "correction by 50000 worked"))
end)

test("a correction that cannot be sent is given up, and nothing is booked in update()", function()
	local host, client = pair()
	client.api.cmd.makeScriptingSendEventCmd = function() error("no events here") end
	run(host, client, 299)
	client.balance = host.balance - 50000
	run(host, client, 1500)
	assert(#client.sent == 0 and has(client.logs, "the money correction could not be sent; money is no longer corrected"))
	assert(count(client.logs, "booking it") == 1)
end)

test("a money difference that is gone at the next checkpoint is not booked", function()
	local host, client = pair()
	run(host, client, 299)
	client.balance = host.balance - 50000
	run(host, client, 300)
	client.balance = host.balance
	run(host, client, 600)
	for _, c in ipairs(client.sent) do assert(c.name ~= "book") end
end)

test("a booking without effect turns the money correction off", function()
	local host, client = pair()
	client.book_works = false
	run(host, client, 299)
	client.balance = host.balance - 50000
	run(host, client, 1500)
	local books = 0
	for _, c in ipairs(client.sent) do if c.name == "book" then books = books + 1 end end
	assert(books == 1, books)
	assert(has(client.logs, "had no effect"))
end)

test("a loan difference is booked as a loan, and money waits for it", function()
	local host, client = pair()
	run(host, client, 299)
	host.loan, host.balance = 500000, host.balance + 500000
	run(host, client, 600)
	local books = {}
	for _, c in ipairs(client.sent) do if c.name == "book" then books[#books + 1] = c end end
	assert(#books == 1 and books[1].entry.category.type == 0 and books[1].entry.amount == 500000)
	assert(client.loan == 500000 and client.balance == host.balance)
	run(host, client, 600)
	assert(#client.sent == 1)
end)

test("a lasting date difference moves the client's calendar", function()
	local host, client = pair()
	run(host, client, 299)
	host.date_shift = 3
	run(host, client, 600)
	local dates = {}
	for _, c in ipairs(client.sent) do if c.name == "date" then dates[#dates + 1] = c end end
	assert(#dates == 1, #dates)
	local today = function(g) return g.date_base + math.floor(g.gt / g.ms_per_day) + g.date_shift end
	assert(today(client) == today(host))
	run(host, client, 600)
	assert(has(client.logs, "the date correction by 3 worked"))
end)

test("lasting count differences are reported in both games, not again every minute", function()
	local host, client = pair()
	run(host, client, 299)
	client.veh = 4
	run(host, client, 600)
	assert(count(client.logs, "sync WARNING: the games differ: veh here 4, in the other game 5") == 1)
	assert(count(host.logs, "sync WARNING: the games differ: veh here 5, in the other game 4") == 1)
	run(host, client, 900)
	assert(count(client.logs, "sync WARNING: the games differ: veh") == 1)
	for _, c in ipairs(client.sent) do assert(c.name ~= "book") end
end)

test("checkpoints are compared in either order, with the client behind or ahead", function()
	local host, client = pair()
	for _ = 1, 400 do host.tick() end
	assert(not has(host.logs, "sync check"))
	for _ = 1, 400 do client.tick() end
	assert(has(client.logs, "sync check 1 (2026-01-01): same"))
	for _ = 1, 10 do host.tick() end
	assert(has(host.logs, "sync check 1 (2026-01-01): same"))
end)

test("a savegame loaded again starts the checkpoints over", function()
	local host, client = pair()
	run(host, client, 700)
	host.gt, client.gt = 0, 0
	run(host, client, 300)
	assert(count(client.logs, "sync: this game is the client") == 2)
	assert(count(client.logs, "sync check 1 ") == 2)
end)

test("the journal is described once per savegame, and nothing is booked for it", function()
	local g = game("host"); g.s.journal_test = nil
	for _ = 1, 60 do g.tick() end
	assert(has(g.logs, "journal: Type: CONSTRUCTION,LOAN,OTHER; Other: CHEAT; amount=0"))
	assert(#g.sent == 0 and g.balance == 1000000)
	g.gt = 0; for _ = 1, 60 do g.tick() end
	assert(count(g.logs, "journal: Type") == 1)
end)

test("an entry whose type cannot be set is not booked", function()
	local g = game("client")
	g.api.type.JournalEntry.Type = {}
	local ok, sent, notes = pcall(sync.book, g.env, 100, "OTHER")
	assert(ok and sent == false and notes:find("type FAILED", 1, true) and #g.sent == 0)
end)

test("nothing happens without DLL v8, and checkpoints wait for a host or client role", function()
	local g = game("host"); g.vars.TF3MP_ROLE = nil
	for _ = 1, 400 do g.tick() end
	assert(#g.logs == 0 and #g.sent == 0)
	local l = game("loopback")
	for _ = 1, 400 do l.tick() end
	assert(not has(l.logs, "net state sim") and has(l.logs, "this game is the loopback"))
end)

test("without a GUI script the simulation keeps the speed and says so once", function()
	local host, client = pair()
	host.speed = 2
	run(host, client, 120)
	assert(count(client.logs, "the GUI script does not run here") == 1)
	assert(has(client.logs, "net state gui ") and client.vars.TF3MP_OWN_GUI:find("src=sim", 1, true))
	assert(client.speed == 2, client.speed)
	-- With the GUI script running the simulation stays out of it.
	local h2, c2 = pair()
	h2.gui(); c2.gui()
	run(h2, c2, 120)
	assert(not has(c2.logs, "the GUI script does not run"))
end)

test("the installed mod manifest lists sync.lua and gui.lua, and the GUI script is registered", function()
	local f = assert(io.open("mods/mp_probe/_content.json", "r")); local manifest = f:read("*a"); f:close()
	assert(manifest:find('"mp_probe/sync.lua"', 1, true) and manifest:find('"mp_probe/gui.lua"', 1, true))
	data = nil
	assert(loadfile(MOD_ROOT .. "/mp_probe/main.gs.lua"))()
	local desc = data()
	assert(desc.guiUpdateScript.fileName == "main.script@guiUpdate" and type(main.guiUpdate) == "function")
end)

print(string.format("%d sync tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

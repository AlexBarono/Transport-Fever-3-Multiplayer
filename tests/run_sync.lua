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
		if c == "GAME_SPEED" then return { speedup = g.speed, millisPerDay = g.ms_per_day } end
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
	function engine.getEntitiesWithComponent(c, filters)
		local out = {}
		engine.forEachEntityWithComponent(function(id)
			if not filters or engine.getComponent(id, "PLAYER_OWNED").player == filters.requireOwnedByPlayer then out[#out + 1] = id end
		end, c)
		return out
	end
	local JE = { Type = { LOAN = 0, CONSTRUCTION = 2, OTHER = 6 }, Other = { CHEAT = 3 } }
	function JE.new() return { amount = 0, time = 0, category = { type = 0, other = 0 } } end
	local cmd = {}
	function cmd.makeJournalBookAssetCmd(player, entry, position)
		-- The position is optional (api/cmd.d.tl); runs 24-30 booked without one.
		assert(position == nil or (position.x and position.y and position.z), "journal position must be a Vec3f")
		return { name = "book", player = player, entry = entry }
	end
	function cmd.makeGameSetDateCmd(date) return { name = "date", date = date } end
	function cmd.makeGameSetSpeedCmd(speed) return { name = "speed", speed = speed } end
	function cmd.makeGameSetCalendarSpeedCmd(value) return { name = "calendar", value = value } end
	function cmd.makeScriptingSendEventCmd(a, b, c, d) return { name = "event", args = { a, b, c, d } } end
	function cmd.sendCommand(c, callback)
		if callback and g.context == "update" then error("Callbacks are currently disallowed") end
		if c.name == "book" then assert(c.entry.time == -1, "cmd.journalEntry.time == -1") end
		if c.name == "event" then
			g.events_sent = g.events_sent + 1
			if g.events_now then g.handle(c.args) else g.events[#g.events + 1] = c.args end
			return
		end
		g.sent[#g.sent + 1] = c
		if c.name == "speed" and g.delay_speed then
			g.speed_commands = g.speed_commands or {}
			g.speed_commands[#g.speed_commands + 1] = { command = c, callback = callback }
			return
		end
		if c.name == "book" and g.book_works then
			local kind = c.entry.category.type
			if kind == JE.Type.LOAN then g.loan, g.balance = g.loan + c.entry.amount, g.balance + c.entry.amount
			elseif kind == JE.Type.OTHER then g.balance = g.balance + c.entry.amount end
		elseif c.name == "date" then
			g.date_shift = g.date_shift + sync.days(c.date.year, c.date.month, c.date.day) - today(g.gt)
		elseif c.name == "speed" and not g.speed_broken then
			g.speed = c.speed
		elseif c.name == "calendar" and not g.calendar_broken then
			g.ms_per_day = c.value
		end
		if callback then callback({}, not (c.name == "book" and g.book_rejects)) end
	end
	g.api = { engine = engine, cmd = cmd,
		type = { ComponentType = ct, JournalEntry = JE,
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			Date = { addOffsetDays = function(d, n) return date_of(sync.days(d.year, d.month, d.day) + n) end } } }
	g.api.gui = { game = { getEstimatedMaximumGameSpeed = function() return g.max_speed or 0 end } }
	g.os = { getenv = function(name) return g.vars[name] end, clock = function() return g.clock end }
	g.env = { api = g.api, os = g.os }
	function g.apply_speed_commands()
		g.run(function()
			for _, item in ipairs(g.speed_commands or {}) do
				g.speed = item.command.speed
				if item.callback then item.callback({}, true) end
			end
		end)
		g.speed_commands = {}
	end
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
			now = p.now, hold = hold ~= false, src = "gui", ordered = p.ordered, max_speed = me.max_speed })
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

test("native capacity clamps catchup without disabling shared speed or creating a user edit", function()
	local mem, peer = {}, {speed=3,ver=0,by="client",hb=1,gt=60000,run=3}
	local function step(own, now, limit)
		peer.hb = peer.hb + 1
		return sync.speed_step(mem, {own=own,own_t=0,role="client",peer=peer,now=now,src="gui",max_speed=limit})
	end
	local out=step(3,0,3)
	assert(out.command==nil and mem.target==3 and mem.speed==3)
	assert(has(out.logs,"current capacity: 3x"))
	for now=1,20 do
		out=step(3,now,3)
		assert(out.command==nil and not mem.broken and mem.ver==0 and mem.speed==3)
	end
	out=step(3,21,4); assert(out.command==4 and mem.ver==0)
	out=step(4,22,4); assert(not mem.pending and mem.speed==3 and mem.ver==0)
	out=step(3,23,3); assert(out.command==nil and not mem.broken and mem.ver==0)
end)

test("a lower native capacity settles an already pending 4x request", function()
	local mem, peer={}, {speed=4,ver=1,by="host",hb=1,gt=0,run=4}
	local out=sync.speed_step(mem,{own=3,own_t=0,role="client",peer=peer,now=0,src="gui"})
	assert(out.command==4 and mem.pending==4)
	out=sync.speed_step(mem,{own=3,own_t=0,role="client",peer=peer,now=20,src="gui",max_speed=3})
	assert(out.command==nil and not mem.pending and not mem.broken and mem.speed==4 and mem.ver==1)
end)

test("ordered sessions keep the same speed even when their simulation times differ", function()
	local p = speed_pair(); p.ordered = true; p.both(2)
	p.host.speed = 2; p.both(2)
	-- The real v61 run had shared speed2, host run2 and client run4 once
	-- the client fell 30 seconds behind. Building is allowed despite drift.
	p.host.gt, p.client.gt = 120000, 0
	p.both(10, 2.1)
	assert(p.host.speed == 2 and p.client.speed == 2)
	assert(not p.host.mem.catchup and not p.client.mem.catchup)
	assert(p.host.mem.speed == 2 and p.client.mem.speed == 2 and p.host.mem.ver == 1 and p.client.mem.ver == 1)
	p.client.gt = 240000; p.both(10, 2.1)
	assert(p.host.speed == 2 and p.client.speed == 2, "time drift must not override the common speed")
end)

test("ordered sessions use the slower PC's capacity without changing the requested register", function()
	for _, slower in ipairs({ "host", "client" }) do
		local p = speed_pair(); p.ordered = true; p.both(2)
		p.host.speed = 4; p.both(3)
		local version = p.host.mem.ver
		p[slower].max_speed = 3; p.both(4)
		assert(p.host.speed == 3 and p.client.speed == 3, slower)
		assert(p.host.mem.speed == 4 and p.client.mem.speed == 4 and p.host.mem.ver == version and p.client.mem.ver == version)
		assert(p[slower].state.max == 3)
		p[slower].max_speed = 4; p.both(4)
		assert(p.host.speed == 4 and p.client.speed == 4, "capacity recovery " .. slower)
		assert(p.host.mem.ver == version and p.client.mem.ver == version, "capacity is not a local click")
	end
end)

test("an expired peer capacity cannot leave the connected PC permanently throttled", function()
	local mem, peer = {}, { speed = 4, ver = 1, by = "host", hb = 1, gt = 0, run = 3, max = 3 }
	local function step(own, now)
		return sync.speed_step(mem, { own = own, role = "client", peer = peer, now = now, src = "gui", ordered = true, max_speed = 4 })
	end
	local out = step(1, 0); assert(out.command == 3)
	step(3, 1)
	out = step(3, sync.PEER_STALE_S + 1); assert(out.command == 4 and mem.ver == 1 and mem.speed == 4)
	step(4, sync.PEER_STALE_S + 1.3)
	peer.hb = 2; out = step(4, sync.PEER_STALE_S + 2)
	assert(out.command == 3 and mem.ver == 1 and mem.speed == 4, "fresh lower capacity must apply again")
end)

test("late speed readbacks after a capacity change do not become new player versions", function()
	for _, role in ipairs({ "host", "client" }) do
		local mem, peer = {}, { speed = 4, ver = 1, by = "host", hb = 1, gt = 0, run = 4, max = 4 }
		local function step(own, now, limit)
			peer.hb = peer.hb + 1
			return sync.speed_step(mem, { own = own, own_t = 0, role = role, peer = peer, now = now,
				src = "gui", ordered = true, max_speed = limit })
		end
		assert(step(1, 0, 4).command == 4)
		assert(step(1, 0.3, 3).command == 3)
		step(3, 0.6, 3)
		local out = step(4, 0.9, 3) -- Earlier 4x native command arrives late.
		assert(out.command == 3 and mem.ver == 1 and mem.speed == 4 and not has(out.logs, "changed here"), role)
		step(3, 1.2, 3)
		assert(mem.ver == 1 and not mem.broken and not mem.pending)
	end
end)

test("capacity readbacks during automatic catchup cannot promote the shared speed", function()
	local mem, peer = {}, { speed = 2, ver = 1, by = "host", hb = 1, gt = 120000, run = 2 }
	local function step(own, now, limit)
		peer.hb = peer.hb + 1
		return sync.speed_step(mem, { own = own, own_t = 0, role = "client", peer = peer, now = now, src = "gui", max_speed = limit })
	end
	assert(step(1, 0, 4).command == 4)
	assert(step(1, 0.3, 3).command == 3)
	step(3, 0.6, 3)
	local out = step(4, 0.9, 3)
	assert(out.command == 3 and mem.ver == 1 and mem.speed == 2, "old v61 code promoted the automatic4x to shared4x")
	step(3, 1.2, 3); assert(mem.ver == 1 and mem.speed == 2)
end)

test("a distinct local click wins immediately while a native speed command is pending", function()
	for _, role in ipairs({ "host", "client" }) do
		local mem, peer = {}, { speed = 4, ver = 1, by = "host", hb = 1, gt = 0, run = 4 }
		local function step(own, now)
			peer.hb = peer.hb + 1
			return sync.speed_step(mem, { own = own, role = role, peer = peer, now = now, src = "gui", ordered = true })
		end
		assert(step(1, 0).command == 4)
		local out = step(0, 0.3)
		assert(mem.speed == 0 and mem.ver == 2 and not mem.pending and out.command == nil, role)
		out = step(4, 0.6) -- Old4x command must not undo the pause.
		assert(out.command == 0 and mem.ver == 2 and mem.speed == 0 and not has(out.logs, "changed here"))
		step(0, 0.9); assert(not mem.pending)
	end
end)

test("a confirmed command cannot hide a later real click back to that speed", function()
	for _, role in ipairs({ "host", "client" }) do
		local mem, peer = {}, { speed = 2, ver = 1, by = "host", hb = 1, gt = 0, run = 2 }
		local function step(own, now)
			peer.hb = peer.hb + 1
			return sync.speed_step(mem, { own = own, role = role, peer = peer, now = now, src = "gui", ordered = true })
		end
		assert(step(1, 0).command == 2)
		step(2, 0.3); assert(not mem.command_echoes[2], "confirmed command is no longer in flight")
		peer.speed, peer.ver = 4, 2
		assert(step(2, 0.6).command == 4)
		step(4, 0.9)
		local out = step(2, 1.2)
		assert(mem.speed == 2 and mem.ver == 3 and out.command == nil and has(out.logs, "changed here"), role)
	end
end)

test("an observed obsolete command cannot hide a subsequent deliberate click", function()
	local mem, peer = {}, { speed = 4, ver = 1, by = "host", hb = 1, gt = 0, run = 4 }
	local function step(own, now)
		return sync.speed_step(mem, { own = own, role = "client", peer = peer, now = now, src = "gui", ordered = true })
	end
	step(1, 0); step(0, 0.3)
	assert(step(4, 0.6).command == 0 and mem.ver == 2)
	step(0, 0.9)
	local out = step(4, 1.2)
	assert(mem.speed == 4 and mem.ver == 3 and out.command == nil and has(out.logs, "changed here"))
end)

test("a late obsolete readback stays guarded until the replacement is applied or retried", function()
	for _, role in ipairs({ "host", "client" }) do
		for _, lose_memory in ipairs({ false, true }) do
			local mem, restore, peer = {}, nil, { speed = 4, ver = 1, by = "host", hb = 1, gt = 0, run = 4 }
			local function step(own, now)
				peer.hb = peer.hb + 1
				if lose_memory then mem = {} end
				local out = sync.speed_step(mem, { own = own, role = role, peer = peer, now = now, src = "gui",
					ordered = true, restore = restore })
				if out.publish then restore = sync.decode(out.publish) end
				return out
			end
			assert(step(1, 0).command == 4)
			peer.speed, peer.ver = 0, 2
			assert(step(1, 0.3).command == 0)
			local out = step(4, 0.6) -- Superseded4x arrives before the new pause.
			assert(out.command == nil and mem.speed == 0 and mem.ver == 2 and mem.pending_from == 4)
			out = step(4, 0.9)
			assert(out.command == nil and mem.speed == 0 and mem.ver == 2)
			for _, now in ipairs({ 3.6, 6.9 }) do
				out = step(4, now)
				assert(out.command == 0 and mem.speed == 0 and mem.ver == 2 and mem.pending == 0,
					role .. " memory=" .. tostring(lose_memory) .. " at " .. now)
				assert(not has(out.logs, "changed here"))
			end
			step(0, 7.2)
			assert(mem.pending == nil and mem.speed == 0 and mem.ver == 2 and not mem.broken)
		end
	end
end)

test("a new peer speed recovers from a previous command timeout", function()
	local mem, peer = {}, { speed = 0, ver = 1, by = "host", hb = 1, gt = 0, run = 0 }
	local function step(own, now)
		peer.hb = peer.hb + 1
		return sync.speed_step(mem, { own = own, role = "client", peer = peer, now = now, src = "gui", ordered = true })
	end
	step(1, 0); step(1, 4); step(1, 8); step(1, 12); step(1, 16)
	assert(mem.broken)
	peer.speed, peer.ver = 2, 2
	local out = step(1, 17)
	assert(not mem.broken and out.command == 2 and mem.ver == 2)
	step(2, 17.3); assert(not mem.pending and mem.speed == 2)
end)

test("a reconnect can retry the same previously failed speed request", function()
	local mem, peer = {}, { speed = 0, ver = 1, by = "host", hb = 1, gt = 0, run = 0 }
	local function step(own, now, live)
		if live then peer.hb = peer.hb + 1 end
		return sync.speed_step(mem, { own = own, role = "client", peer = live and peer or nil, now = now, src = "gui", ordered = true })
	end
	for _, now in ipairs({ 0, 4, 8, 12, 16 }) do step(1, now, true) end
	assert(mem.broken)
	step(1, 17, false)
	local out = step(1, 18, true)
	assert(not mem.broken and out.command == 0 and mem.ver == 1 and mem.speed == 0)
end)

test("lost GUI memory retains the pending command and cannot publish its old readback as a click", function()
	local mem, peer = {}, { speed = 4, ver = 1, by = "host", hb = 1, gt = 0, run = 4, max = 3 }
	local function step(own, now, restore)
		peer.hb = peer.hb + 1
		return sync.speed_step(mem, { own = own, role = "client", peer = peer, now = now, src = "gui",
			ordered = true, max_speed = 4, restore = restore })
	end
	local out = step(1, 0); assert(out.command == 3)
	local restore = sync.decode(out.publish); mem = {}
	out = step(1, 1, restore)
	assert(mem.speed == 4 and mem.ver == 1 and mem.pending == 3 and not has(out.logs, "changed here"))
	assert(out.command == nil, "lost memory must not flood the native command queue")
	restore = sync.decode(out.publish); mem = {}
	out = step(3, 1.3, restore)
	assert(mem.speed == 4 and mem.ver == 1 and mem.pending == nil)
end)

test("lost GUI memory retains the late command guard across a newer local pause", function()
	local mem, peer = {}, { speed = 4, ver = 1, by = "host", hb = 1, gt = 0, run = 4 }
	local function step(own, now, restore)
		return sync.speed_step(mem, { own = own, role = "client", peer = peer, now = now, src = "gui", ordered = true, restore = restore })
	end
	assert(step(1, 0).command == 4)
	local out = step(0, 0.3)
	assert(mem.ver == 2 and mem.speed == 0)
	local restore = sync.decode(out.publish); mem = {}
	out = step(4, 0.6, restore)
	assert(mem.ver == 2 and mem.speed == 0 and out.command == 0 and not has(out.logs, "changed here"))
end)

test("native speed capacity also bounds direct commands and menu release", function()
	local g=game("client"); g.max_speed=3; g.speed=3; g.vars.TF3MP_ORDERING="1"; g.gui()
	g.run(function() sync.set_speed(g.env,4) end); assert(g.speed==3)
	g.vars.TF3MP_OWN_GUI="speed=4 ver=8 by=host run=3 tg=3 src=gui hb=9"
	g.vars.TF3MP_OWN_CLOCKUI="hold=1 run=4"
	g.speed=0; g.gui(); g.gui(); g.gui()
	assert(g.speed==3 and sync.decode(g.vars.TF3MP_OWN_CLOCKUI).hold==0)
	assert(not has(g.logs,"could not be set"))
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
		assert(has(client.logs, "sync: money correction sent (amount 50000, time -1, other CHEAT, type OTHER)"))
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

test("three directly observed ineffective bookings turn the money correction off", function()
	local host, client = pair()
	client.book_works = false
	run(host, client, 299)
	client.balance = host.balance - 50000
	run(host, client, 1500)
	local books = 0
	for _, c in ipairs(client.sent) do if c.name == "book" then books = books + 1 end end
	assert(books == 3, books)
	assert(client.s.sync.off.money and client.s.sync.money_no_effect == 3)
end)

test("new economic drift after a successful booking cannot permanently disable money alignment", function()
	for _, sign in ipairs({-1,1}) do
		local host,client=pair()
		run(host,client,299); client.balance=host.balance-sign*16502
		run(host,client,600); assert(client.balance==host.balance)
		client.balance=host.balance-sign*41174 -- income/costs after the first booking
		run(host,client,300)
		assert(not client.s.sync.off.money and client.balance==host.balance)
		assert(has(client.logs,"continuing comparison") and not has(client.logs,"had no effect"))
		run(host,client,300); assert(not client.s.sync.off.money)
	end
end)

test("journal callback evidence distinguishes applied, unchanged, mixed and unreadable balances", function()
	local g=game("client")
	local evidence
	local function booked(amount)
		assert(sync.book(g.env,amount,"OTHER",function(_,success,observed) assert(success); evidence=observed end))
		return evidence
	end
	assert(booked(5000).applied==true and evidence.delta==5000)
	g.book_works=false
	assert(booked(5000).applied==false and evidence.delta==0)
	local native=g.api.cmd.sendCommand
	g.api.cmd.sendCommand=function(command,cb) g.balance=g.balance+command.entry.amount+7; cb({},true) end
	assert(booked(5000).applied==nil and evidence.delta==5007)
	g.api.cmd.sendCommand=native
	local getComponent=g.api.engine.getComponent
	g.api.engine.getComponent=function(id,ct) if ct=="ACCOUNT" then error("not readable") end; return getComponent(id,ct) end
	assert(booked(5000).applied==nil and evidence.before==nil and evidence.after==nil)
end)

test("a repeated native booking callback settles the financial observation only once", function()
	local g = game("client")
	local callback, answers = nil, 0
	g.api.cmd.sendCommand = function(_, done) callback = done end
	assert(sync.book(g.env, 5000, "OTHER", function() answers = answers + 1 end))
	assert(callback and answers == 0)
	callback({}, true); callback({}, true); callback({}, false)
	assert(answers == 1)
end)

test("only consecutive directly unchanged booking callbacks reach the financial safeguard", function()
	local mem={fixes={money={amount=5000,after=1}}}
	assert(sync.settle_fix(mem,"money",5000,true,{applied=false})=="no_effect")
	assert(sync.settle_fix(mem,"money",5000,true,{applied=false})=="no_effect")
	sync.settle_fix(mem,"money",5000,true,{delta=5007})
	assert(not mem.money_no_effect and not mem.off.money)
	sync.settle_fix(mem,"money",5000,true,{applied=false})
	sync.settle_fix(mem,"money",5000,true,{applied=true})
	assert(not mem.money_no_effect and mem.fixes.money.observed==true)
	for _=1,2 do assert(sync.settle_fix(mem,"money",5000,true,{applied=false})=="no_effect") end
	assert(sync.settle_fix(mem,"money",5000,true,{applied=false})=="no_effect_stopped")
	assert(mem.off.money and not mem.fixes.money)
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

test("journal corrections request the game's current time with the required sentinel", function()
	local g = game("client")
	-- JE.new() starts at time=0; the real game's command rejects that default (run 27).
	local entry = g.api.type.JournalEntry.new()
	assert(not pcall(g.api.cmd.sendCommand, g.api.cmd.makeJournalBookAssetCmd(7, entry, g.api.type.Vec3f.new(0, 0, 0))))
	for _, amount in ipairs({ 5000, -5000 }) do
		local ok = sync.book(g.env, amount, "OTHER")
		assert(ok and g.sent[#g.sent].entry.time == -1 and g.sent[#g.sent].entry.amount == amount)
	end
	assert(#g.sent == 2 and g.balance == 1000000)
end)

test("an entry whose required time cannot be set is not booked", function()
	local g = game("client")
	function g.api.type.JournalEntry.new()
		return setmetatable({ amount = 0, category = { type = 0, other = 0 } }, {
			__newindex = function(t, key, value)
				if key == "time" then error("time unavailable") end
				rawset(t, key, value)
			end,
		})
	end
	local ok, sent, notes = pcall(sync.book, g.env, 100, "OTHER")
	assert(ok and sent == false and notes:find("time FAILED", 1, true) and #g.sent == 0)
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
	-- v33: the GUI event hook (hold.lua) is registered and listed.
	assert(desc.guiHandleEventScript.fileName == "main.script@guiHandleEvent" and type(main.guiHandleEvent) == "function")
	assert(manifest:find('"mp_probe/hold.lua"', 1, true) and manifest:find('"mp_probe/timeline.lua"', 1, true))
	assert(main.guiHandleEvent({}, nil, nil, "", "x", "y", nil) == nil)
end)

test("world content differences require two consecutive checkpoints and never modify the world", function()
	local m = {}
	local own = { hcon = "h1_0000000000000001", hedge = "h1_0000000000000002",
		hline = "h1_0000000000000003", hveh = "h1_0000000000000004" }
	local peer = copy(own); peer.hline = "h1_0000000000000005"
	local out = sync.compare(m, 1, own, peer, "client", 1)
	assert(out.world_fields == 4 and out.world_different == 1 and not out.world_mismatch)
	assert(#out.warnings == 0 and next(out.fix) == nil)
	out = sync.compare(m, 2, own, peer, "client", 2)
	assert(out.world_mismatch and #out.warnings == 1 and out.world_diffs[1] == "hline")
	assert(next(out.fix) == nil, "world contents must only be reported")
	out = sync.compare(m, 3, own, own, "client", 3)
	assert(out.world_fields == 4 and out.world_different == 0 and not out.world_mismatch)
end)

test("missing and invalid world hashes break consecutive evidence instead of proving equality", function()
	local m, own, peer = {}, { hcon = "h1_0000000000000001" }, { hcon = "h1_0000000000000002" }
	sync.compare(m, 1, own, peer, "host", 1)
	local out = sync.compare(m, 2, {}, peer, "host", 2)
	assert(out.world_fields == 0 and out.world_different == 0 and not out.world_mismatch)
	out = sync.compare(m, 3, own, peer, "host", 3)
	assert(out.world_fields == 1 and not out.world_mismatch)
	out = sync.compare(m, 4, own, peer, "host", 4)
	assert(out.world_mismatch)
	out = sync.compare(m, 5, { hcon = "garbage" }, peer, "host", 5)
	assert(out.world_fields == 0 and not out.world_mismatch)
end)

test("nonadjacent mismatches do not trigger a world warning", function()
	local m, own, peer = {}, { hveh = "h1_0000000000000001" }, { hveh = "h1_0000000000000002" }
	sync.compare(m, 1, own, peer, "host", 1)
	local out = sync.compare(m, 3, own, peer, "host", 3)
	assert(not out.world_mismatch and #out.warnings == 0)
end)

-- ---------------------------------------------------------------------------------------------
-- Neuabgleich: the host saves its game when the world check finds a difference (probe v32)

--- A save function like app.saveGame; it calls back at once.
local function saver(g)
	g.saves = {}
	g.env.app = { saveGame = function(name, cb, editor, skip)
		g.saves[#g.saves + 1] = { name = name, editor = editor, skip = skip }
		cb()
	end }
end

test("v40: persistent world differences never save or pause either game", function()
	local host, client = pair(); saver(host); saver(client)
	for ck = 1, 120 do
		for _, field in ipairs({ "hcon", "hedge", "hline", "hveh", "hpos", "hcargo", "htown", "loan", "clock" }) do
			host.vars.TF3MP_OWN_HEALTH = "ck=" .. ck .. " fields=" .. field .. " status=diff"
			client.vars.TF3MP_OWN_HEALTH = host.vars.TF3MP_OWN_HEALTH
			host.gui(); client.gui()
		end
	end
	assert(#host.saves == 0 and #client.saves == 0)
	assert(host.speed == 1 and client.speed == 1)
	assert(not has(host.logs, "resync: saving") and not host.vars.TF3MP_OWN_RESYNC)
end)

test("v40: losing GUI memory does not turn differences into an automatic save", function()
	local host = game("host"); saver(host)
	host.vars.TF3MP_OWN_HEALTH = "ck=9 fields=hveh,hcon status=diff"
	host.gui()
	host.env = { api = host.api, os = host.os, app = host.env.app }
	host.gui()
	assert(#host.saves == 0)
end)
test("app.saveGame as a callable table (run 35) is called like a function", function()
	local host = game("host")
	host.saves = {}
	host.env.app = { saveGame = setmetatable({}, { __call = function(_, name, cb, editor, skip)
		host.saves[#host.saves + 1] = { name = name, editor = editor, skip = skip }
		cb()
	end }) }
	host.vars.TF3MP_SAVE = "1"
	host.gui()
	assert(#host.saves == 1 and host.saves[1].name == gui.RESYNC_SAVE and host.saves[1].skip == true)
	assert(has(host.logs, "resync: saved 'TF3MP-Neuabgleich' for the launcher (request 1)") and not has(host.logs, "save by hand"))
end)

--- app as TF3's load page uses it (gui/menu/savegame_react_util.tl).
local function loader(g, saves)
	g.loads, g.waits = {}, 0
	g.env.app = { saveGame = g.env.app and g.env.app.saveGame,
		SaveGameNamespace = { getSavegame = function() return "ns" end },
		findAllSavegames = function(ns) assert(ns == "ns"); return saves or {} end,
		setWaitForStartReadyGame = function() g.waits = g.waits + 1 end,
		loadGame = function(id, editor, extra) g.loads[#g.loads + 1] = { id = id, editor = editor, extra = extra } end }
	g.api.type.SavegameId = { new = function() return {} end }
end

test("v35: the launcher's reload request loads the save in the running game, once per resync", function()
	local client = game("client")
	loader(client, { { saveName = "Andere", path = "x" }, { saveName = "TF3MP-Neuabgleich", path = "C:/saves/TF3MP-Neuabgleich.sav" } })
	client.gui()
	assert(#client.loads == 0, "nothing without a request")
	client.vars.TF3MP_RELOAD = "1 TF3MP-Neuabgleich"
	client.gui(); client.gui()
	assert(#client.loads == 1 and client.waits == 1, "one load")
	local id = client.loads[1].id
	assert(id.saveGameNamespace == "ns" and id.saveGameName == "TF3MP-Neuabgleich" and id.path == "C:/saves/TF3MP-Neuabgleich.sav")
	assert(client.loads[1].editor == false)
	assert(has(client.logs, "found in the save list"))
	-- The next resync has a new epoch.
	client.vars.TF3MP_RELOAD = "2 TF3MP-Neuabgleich"
	client.gui()
	assert(#client.loads == 2)
	-- Not in the save list yet: loads by name.
	local host = game("host")
	loader(host)
	host.vars.TF3MP_RELOAD = "1 TF3MP-Neuabgleich"
	host.gui()
	assert(#host.loads == 1 and host.loads[1].id.saveGameName == "TF3MP-Neuabgleich" and host.loads[1].id.path == "")
	assert(has(host.logs, "loading by name"))
end)

test("v35: a failed in-game load points to 'Neu abgleichen' and the GUI keeps running", function()
	local client = game("client")
	loader(client)
	client.env.app.loadGame = function() error("not now") end
	client.vars.TF3MP_RELOAD = "1 TF3MP-Neuabgleich"
	client.gui(); client.gui()
	assert(count(client.logs, "did not work: ") == 1 and has(client.logs, "'Neu abgleichen'"))
	assert(not has(client.logs, "gui sync failed"))
	-- Reload requests are ignored outside a session.
	local solo = game("loopback")
	loader(solo)
	solo.vars.TF3MP_RELOAD = "1 TF3MP-Neuabgleich"
	solo.gui()
	assert(#solo.loads == 0)
end)

test("v37: a reload request asked again (new save or after a load that never started) loads again", function()
	local client = game("client")
	loader(client)
	client.vars.TF3MP_RELOAD = "1 TF3MP-Sync-1"
	client.gui(); client.gui()
	assert(#client.loads == 1, "one load")
	-- The load did not start; the launcher asks again with a new copy, the DLL keeps the epoch.
	client.vars.TF3MP_RELOAD = "1 TF3MP-Sync-2"
	client.gui(); client.gui()
	assert(#client.loads == 2 and client.loads[2].id.saveGameName == "TF3MP-Sync-2", "a new save at once")
	-- The same request stays: tried again only after a while.
	for _ = 1, 20 do client.gui() end
	assert(#client.loads == 2, "not every frame")
	client.clock = client.clock + gui.RELOAD_RETRY_S
	client.gui(); client.gui()
	assert(#client.loads == 3, "again after RELOAD_RETRY_S")
end)

test("v35: a launcher save request saves on the host and tells the partner on both", function()
	local host, client = pair()
	saver(host); saver(client)
	host.vars.TF3MP_SAVE = "1"
	host.gui(); host.gui()
	assert(#host.saves == 1 and host.saves[1].name == gui.RESYNC_SAVE, "the host saves once")
	assert(client.vars.TF3MP_PEER_RESYNC == "ck=0 req=1", tostring(client.vars.TF3MP_PEER_RESYNC))
	-- A Lua state without memory does not save the same request again.
	host.env = { api = host.api, os = host.os, app = host.env.app }
	host.gui()
	assert(#host.saves == 1)
	client.vars.TF3MP_SAVE = "1"
	client.gui(); client.gui()
	assert(#client.saves == 0, "the client never saves")
	assert(host.vars.TF3MP_PEER_RESYNC == "ck=0 req=1", "but tells the host")
	host.vars.TF3MP_SAVE = "2"
	host.gui()
	assert(#host.saves == 2 and client.vars.TF3MP_PEER_RESYNC == "ck=0 req=2")
end)

test("moving-world hashes are comparable only at identical actual simulation ticks", function()
	local own = { gt = 60000, wgt = 60000, hpos = "h2_0000000000000001", hcargo = "h2_0000000000000003", htown = "h2_0000000000000005" }
	local peer = copy(own); peer.hpos = "h2_0000000000000002"
	local m, out = {}, nil
	out = sync.compare(m, 1, own, peer, "host", 1)
	assert(out.world_fields == 3 and out.world_different == 1 and not out.world_mismatch)
	out = sync.compare(m, 2, own, peer, "host", 2)
	assert(out.world_mismatch)
	peer.gt, peer.wgt = 60200, 60200
	out = sync.compare(m, 3, own, peer, "host", 3)
	assert(out.world_fields == 0 and not out.world_mismatch and #out.world_unreadable == 7)
	peer.gt, peer.wgt = 60000, nil
	out = sync.compare(m, 4, own, peer, "host", 4)
	assert(out.world_fields == 0 and not out.world_mismatch)
end)

test("managed loan differences retain the real schedule but do not block host money alignment", function()
	local own = { money = 1000000, loan = 2750001, loanmanaged = 1 }
	local peer = { money = 1083333, loan = 2833334, loanmanaged = 1 }
	local m, out = {}, nil
	for k = 1, 3 do
		out = sync.compare(m, k, own, peer, "client", k)
		assert(out.fix.loan == nil, "native loan schedules must never be replicated by journal deltas")
		if k == 2 then assert(out.fix.money == 83333); own.money = peer.money end
	end
	assert(out.loan_mismatch and out.needs_resync)
	out = sync.compare(m, 4, own, own, "client", 4)
	assert(not out.loan_mismatch and not out.needs_resync)
end)

test("the official game-script system marks its account loan as managed", function()
	local g = game("client")
	g.api.engine.system.gameScriptSystem = {}
	local values = sync.values(g.env, g.gt)
	assert(values.loanmanaged == 1 and values.loan == 0)
end)

test("real money bookings still execute with different managed loan balances", function()
	local host, client = pair()
	host.api.engine.system.gameScriptSystem={}; client.api.engine.system.gameScriptSystem={}
	run(host,client,299)
	host.loan,client.loan = 2750001,2833334
	client.balance = host.balance - 83333
	run(host,client,600)
	local books={}
	for _,c in ipairs(client.sent) do if c.name=="book" then books[#books+1]=c end end
	assert(#books==1 and books[1].entry.amount==83333 and books[1].entry.category.type~=0)
	assert(client.balance==host.balance and client.loan==2833334 and host.loan==2750001)
end)

test("a committed common-tick hold pauses without changing the shared speed version", function()
	local g = game("host"); g.speed, g.gt = 3, 1200
	g.gui()
	local before = sync.decode(g.vars.TF3MP_OWN_GUI)
	g.vars.TF3MP_OWN_CLOCK = "at=1200 phase=committed hold=1"
	for _ = 1, 3 do g.gui() end
	assert(g.speed == 0)
	local after = sync.decode(g.vars.TF3MP_OWN_GUI)
	assert(after.ver == before.ver and after.speed == 3 and after.run == 3)
	local held = sync.decode(g.vars.TF3MP_OWN_CLOCKUI)
	assert(held.hold == 1 and held.run == 3)
	assert(not has(g.logs, "speed changed here: paused") and not has(g.logs, "gui sync failed"))
end)

test("a remembered common-tick hold restores its speed after the clock becomes idle", function()
	local g = game("client"); g.speed, g.gt = 0, 1200
	g.vars.TF3MP_OWN_GUI = "speed=3 ver=8 by=client run=3 tg=3 src=gui hb=9"
	g.vars.TF3MP_OWN_CLOCKUI = "hold=1 run=3"
	g.vars.TF3MP_OWN_CLOCK = "at=1200 phase=idle hold=0"
	g.gui()
	assert(g.speed == 3 and sync.decode(g.vars.TF3MP_OWN_CLOCKUI).release == 1)
	g.gui(); g.gui()
	assert(sync.decode(g.vars.TF3MP_OWN_CLOCKUI).hold == 0)
	local restored = sync.decode(g.vars.TF3MP_OWN_GUI)
	assert(restored.ver == 8 and restored.speed == 3 and restored.run == 3)
	assert(not has(g.logs, "speed changed here: paused") and not has(g.logs, "gui sync failed"))
end)

test("delayed barrier release never publishes the automatic pause as a user speed change", function()
	for _, role in ipairs({ "host", "client" }) do
		local g = game(role); g.speed, g.gt, g.delay_speed = 0, 1200, true
		g.max_speed = 3
		g.vars.TF3MP_ORDERING = "1"
		g.vars.TF3MP_OWN_HEALTH = "ck=258 fields=hcon,hedge status=diff"
		g.vars.TF3MP_OWN_GUI = "speed=3 ver=8 by=host run=3 tg=3 src=gui hb=9"
		g.vars.TF3MP_OWN_CLOCKUI = "hold=1 run=3"
		g.vars.TF3MP_OWN_CLOCK = "at=0 phase=idle hold=0"
		for _ = 1, 5 do g.gui() end
		local before = sync.decode(g.vars.TF3MP_OWN_GUI)
		assert(before.speed == 3 and before.ver == 8, table.concat(g.logs, "\n"))
		assert(not has(g.logs, "speed changed here: paused"))
		g.apply_speed_commands(); g.gui(); g.gui()
		local after = sync.decode(g.vars.TF3MP_OWN_GUI)
		assert(g.speed == 3 and after.speed == 4 and after.ver == 8)
	end
end)

test("an ordered session with world and time differences never pauses just to catch up", function()
	local host, client = pair(); host.gt = 200000
	for _, g in ipairs({ host, client }) do
		g.vars.TF3MP_ORDERING = "1"
		g.vars.TF3MP_OWN_HEALTH = "ck=258 fields=hcon,hedge status=diff"
		g.vars.TF3MP_OWN_CLOCK = "at=0 phase=idle hold=0"
	end
	for _ = 1, 20 do host.gui(); client.gui() end
	assert(host.speed == 1 and client.speed == 1, table.concat(host.logs, "\n"))
	host.speed = 4
	for _ = 1, 20 do host.gui(); client.gui() end
	assert(host.speed == 4 and client.speed == 4 and sync.decode(host.vars.TF3MP_OWN_GUI).speed == 4)
end)

test("both ordered GUI scripts share every speed despite a large simulation gap", function()
	for _, setter in ipairs({ "host", "client" }) do
		local h, c = pair(); h.gt, c.gt = 120000, 0
		h.vars.TF3MP_ORDERING, c.vars.TF3MP_ORDERING = "1", "1"
		for _ = 1, 4 do h.gui(); c.gui() end
		for _, speed in ipairs({ 2, 4, 1, 0, 4 }) do
			(setter == "host" and h or c).speed = speed
			for _ = 1, 8 do h.gui(); c.gui() end
			assert(h.speed == speed and c.speed == speed, setter .. " requested " .. speed)
			assert(sync.decode(h.vars.TF3MP_OWN_GUI).speed == speed and sync.decode(c.vars.TF3MP_OWN_GUI).speed == speed)
		end
	end
end)

test("ordered menu and action holds preserve a common capacity limit and the requested version", function()
	for _, opener in ipairs({ "host", "client" }) do
		local h, c = pair(); h.gt, c.gt, c.max_speed = 120000, 0, 3
		h.vars.TF3MP_ORDERING, c.vars.TF3MP_ORDERING = "1", "1"
		for _ = 1, 4 do h.gui(); c.gui() end
		h.speed = 4
		for _ = 1, 8 do h.gui(); c.gui() end
		local version = sync.decode(h.vars.TF3MP_OWN_GUI).ver
		assert(h.speed == 3 and c.speed == 3)
		local first = opener == "host" and h or c
		first.run(function() first.print("net state menu open=1") end)
		for _ = 1, 3 do h.gui(); c.gui() end
		assert(h.speed == 0 and c.speed == 0)
		assert(sync.decode(h.vars.TF3MP_OWN_CLOCKUI).run == 4 and sync.decode(c.vars.TF3MP_OWN_CLOCKUI).run == 4,
			"holds remember the shared request, then apply the common effective capacity")
		-- A scheduled vehicle/subvention action overlaps the open menu.
		for _, g in ipairs({ h, c }) do g.vars.TF3MP_OWN_CLOCK = "at=1 phase=committed hold=1" end
		first.run(function() first.print("net state menu open=0") end)
		for _ = 1, 3 do h.gui(); c.gui() end
		assert(h.speed == 0 and c.speed == 0)
		for _, g in ipairs({ h, c }) do g.vars.TF3MP_OWN_CLOCK = "at=0 phase=idle hold=0"; g.delay_speed = true end
		for _ = 1, 3 do h.gui(); c.gui() end
		h.apply_speed_commands(); c.apply_speed_commands(); h.delay_speed, c.delay_speed = false, false
		for _ = 1, 8 do h.gui(); c.gui() end
		assert(h.speed == 3 and c.speed == 3)
		for _, g in ipairs({ h, c }) do
			local state = sync.decode(g.vars.TF3MP_OWN_GUI)
			assert(state.speed == 4 and state.ver == version and not has(g.logs, "speed changed here: paused"))
		end
	end
end)

test("a new ordered hold remembers the shared choice instead of an older catchup target", function()
	for _, role in ipairs({ "host", "client" }) do
		local g = game(role); g.speed = 4; g.vars.TF3MP_ORDERING = "1"
		g.max_speed = 3
		g.vars.TF3MP_OWN_GUI = "speed=3 ver=8 by=host run=4 tg=4 src=gui hb=9"
		g.vars.TF3MP_OWN_CLOCK = "at=1 phase=committed hold=1"
		g.gt = 1; g.gui()
		assert(g.speed == 0 and sync.decode(g.vars.TF3MP_OWN_CLOCKUI).run == 4)
		g.vars.TF3MP_OWN_CLOCK = "at=0 phase=idle hold=0"
		for _ = 1, 5 do g.gui() end
		local state = sync.decode(g.vars.TF3MP_OWN_GUI)
		assert(g.speed == 3 and state.speed == 4 and state.ver == 8, "the hold must not invent a user edit")
	end
end)

test("the simulation fallback also preserves a common ordered speed despite time drift", function()
	local g = game("client"); g.speed = 2; g.vars.TF3MP_ORDERING = "1"
	g.vars.TF3MP_PEER_GUI = "speed=2 ver=1 by=host run=2 max=3 gt=120000 hb=1 src=sim"
	local ss = { ticks = 100 }
	g.run(function() main.sync_speed_fallback(g.env, ss, "client", 0, g.os.getenv) end)
	assert(g.speed == 2 and ss.speed_mem.speed == 2 and not ss.speed_mem.catchup)
	g.vars.TF3MP_PEER_GUI = "speed=4 ver=2 by=host run=3 max=3 gt=120000 hb=2 src=sim"
	g.clock = 1
	g.run(function() main.sync_speed_fallback(g.env, ss, "client", 0, g.os.getenv) end)
	assert(g.speed == 3 and ss.speed_mem.speed == 4 and ss.speed_mem.ver == 2)
end)

test("automatic pause release survives lost GUI memory and preserves a later real pause", function()
	local g = game("client"); g.speed, g.gt, g.delay_speed = 0, 1200, true
	g.vars.TF3MP_ORDERING = "1"
	g.vars.TF3MP_OWN_GUI = "speed=4 ver=8 by=host run=4 tg=4 src=gui hb=9"
	g.vars.TF3MP_OWN_CLOCKUI = "hold=1 run=4"
	g.vars.TF3MP_OWN_CLOCK = "at=0 phase=idle hold=0"
	for _ = 1, 5 do
		g.env = { api = g.api, os = g.os }; g.gui()
		assert(sync.decode(g.vars.TF3MP_OWN_GUI).ver == 8)
	end
	assert(#g.speed_commands == 1, "do not flood TF3 while the speed command is queued")
	g.apply_speed_commands(); g.delay_speed = false
	for _ = 1, 3 do g.env = { api = g.api, os = g.os }; g.gui() end
	assert(g.speed == 4 and sync.decode(g.vars.TF3MP_OWN_GUI).ver == 8)
	g.speed = 0; g.gui()
	local paused = sync.decode(g.vars.TF3MP_OWN_GUI)
	assert(paused.speed == 0 and paused.ver == 9, "a real player pause still travels")
	g.speed = 2; g.gui()
	assert(sync.decode(g.vars.TF3MP_OWN_GUI).speed == 2 and g.speed == 2)
end)

test("a positive speed chosen after automatic resume acknowledgement is preserved", function()
	local g = game("host"); g.speed, g.gt, g.delay_speed = 0, 1200, true
	g.vars.TF3MP_OWN_GUI = "speed=3 ver=8 by=host run=3 tg=3 src=gui hb=9"
	g.vars.TF3MP_OWN_CLOCKUI = "hold=1 run=3"
	g.vars.TF3MP_OWN_CLOCK = "at=0 phase=idle hold=0"
	g.gui(); g.apply_speed_commands(); g.delay_speed = false
	g.speed = 4; g.gui(); g.gui()
	assert(g.speed == 4 and sync.decode(g.vars.TF3MP_OWN_GUI).speed == 4)
	assert(sync.decode(g.vars.TF3MP_OWN_GUI).ver == 9)
end)

test("a clock warning with no planned action cannot pause the simulation fallback", function()
	local g = game("host"); g.speed = 3
	g.vars.TF3MP_OWN_CLOCK = "at=0 phase=failed hold=0"
	g.run(function() main.sync_speed_fallback(g.env, { ticks = 100, gui_seen = true }, "host", g.gt, g.os.getenv) end)
	assert(g.speed == 3 and #g.sent == 0)
end)

test("either player's menu holds both engines and restores every previous speed", function()
	for _, opener in ipairs({ "host", "client" }) do
		for _, speed in ipairs({ 0, 1, 2, 4 }) do
			local h,c=pair(); h.speed,c.speed=speed,speed
			h.vars.TF3MP_ORDERING,c.vars.TF3MP_ORDERING="1","1"
			for _=1,3 do h.gui();c.gui() end
			local first,other=opener=="host" and h or c,opener=="host" and c or h
			first.run(function() first.print("net state menu open=1") end)
			for _=1,3 do h.gui();c.gui() end
			assert(h.speed==0 and c.speed==0)
			other.speed=4 -- A speed click cannot unpause while the menu is open.
			other.gui(); assert(other.speed==0)
			other.run(function() other.print("net state menu open=1") end)
			first.run(function() first.print("net state menu open=0") end)
			for _=1,3 do h.gui();c.gui() end
			assert(h.speed==0 and c.speed==0, "the second menu still holds both games")
			other.run(function() other.print("net state menu open=0") end)
			for _=1,5 do h.gui();c.gui() end
			assert(h.speed==speed and c.speed==speed, "restore "..speed)
			assert(not has(h.logs,"speed changed here: paused") and not has(c.logs,"speed changed here: paused"))
		end
	end
end)

test("vehicle action pause and overlapping menus resume after both holds finish, with delayed commands", function()
	for _, role in ipairs({ "host", "client" }) do
		for _, speed in ipairs({ 0,1,2,4 }) do
			local g=game(role); g.speed,g.gt=speed,1200; g.vars.TF3MP_ORDERING="1"
			g.gui()
			g.vars.TF3MP_OWN_CLOCK="at=1200 phase=committed hold=1 seq=1"
			g.gui(); assert(g.speed==0)
			g.vars.TF3MP_PEER_MENU="open=1"
			g.vars.TF3MP_OWN_CLOCK="at=0 phase=idle hold=0"
			g.gui(); assert(g.speed==0, "menu outlasts reverse action")
			g.vars.TF3MP_PEER_MENU="open=0"; g.delay_speed=true
			g.env={api=g.api,os=g.os}; g.gui();g.gui()
			g.apply_speed_commands(); g.delay_speed=false
			for _=1,4 do g.gui() end
			assert(g.speed==speed and sync.decode(g.vars.TF3MP_OWN_GUI).speed==speed)
			assert(sync.decode(g.vars.TF3MP_OWN_GUI).ver==0)
		end
	end
end)

test("closing a menu before its pause command arrives cannot publish a false permanent pause", function()
	for _, role in ipairs({"host","client"}) do
		local g=game(role); g.speed=4; g.vars.TF3MP_ORDERING="1"; g.gui(); g.delay_speed=true
		g.vars.TF3MP_PEER_MENU="open=1"; g.gui()
		assert(#g.speed_commands==1 and g.speed_commands[1].command.speed==0)
		g.vars.TF3MP_PEER_MENU="open=0"; g.gui(); g.gui()
		assert(sync.decode(g.vars.TF3MP_OWN_CLOCKUI).hold==1, "the old 4x is not a confirmed resume")
		local pause=table.remove(g.speed_commands,1); g.speed=pause.command.speed
		g.gui(); assert(sync.decode(g.vars.TF3MP_OWN_GUI).speed==4)
		g.apply_speed_commands(); g.delay_speed=false; g.gui();g.gui()
		assert(g.speed==4 and sync.decode(g.vars.TF3MP_OWN_GUI).ver==0)
	end
end)

test("invalid, fractional, non-finite and unsafe journal amounts are rejected before sending", function()
	local g = game("client")
	for _, amount in ipairs({ 0 / 0, math.huge, -math.huge, 0.5, 9007199254740992, -9007199254740992, "5000" }) do
		local ok, notes = sync.book(g.env, amount, "LOAN")
		assert(ok == false and notes:find("invalid journal amount", 1, true))
	end
	local ok, notes = sync.book(g.env, 5000, "MADE_UP")
	assert(ok == false and notes:find("unsupported journal category", 1, true) and #g.sent == 0)
end)

local function gui_pair_steps(host, client, n)
	for _ = 1, n or 4 do host.gui(); client.gui() end
end

test("calendar initially follows host and changes propagate in both directions", function()
	local h, c = pair(); h.ms_per_day, c.ms_per_day = 2000, 600000
	gui_pair_steps(h, c)
	assert(c.ms_per_day == 2000)
	h.ms_per_day = 4000; gui_pair_steps(h, c)
	assert(c.ms_per_day == 4000)
	c.ms_per_day = 8000; gui_pair_steps(h, c)
	assert(h.ms_per_day == 8000)
	assert(h.speed == 1 and c.speed == 1)
	assert(not has(h.logs, "gui sync failed") and not has(c.logs, "gui sync failed"))
end)

test("calendar stopped and resumed while simulation remains paused", function()
	local h, c = pair(); h.speed, c.speed = 0, 0
	gui_pair_steps(h, c)
	h.ms_per_day = 0; gui_pair_steps(h, c)
	assert(c.ms_per_day == 0 and h.speed == 0 and c.speed == 0)
	c.ms_per_day = 12000; gui_pair_steps(h, c)
	assert(h.ms_per_day == 12000 and h.speed == 0 and c.speed == 0)
end)

test("simultaneous calendar changes converge to host", function()
	local h, c = pair(); gui_pair_steps(h, c)
	local previous_host = c.vars.TF3MP_PEER_GUI
	h.ms_per_day, c.ms_per_day = 4000, 8000
	h.gui(); local new_host = c.vars.TF3MP_PEER_GUI
	c.vars.TF3MP_PEER_GUI = previous_host; c.gui(); c.vars.TF3MP_PEER_GUI = new_host
	gui_pair_steps(h, c)
	assert(h.ms_per_day == 4000 and c.ms_per_day == 4000)
end)

test("calendar and simulation changes do not overwrite each other", function()
	local h, c = pair(); gui_pair_steps(h, c)
	h.speed, c.ms_per_day = 2, 3000
	gui_pair_steps(h, c)
	assert(h.speed == 2 and c.speed == 2 and h.ms_per_day == 3000 and c.ms_per_day == 3000)
end)

test("calendar survives GUI memory loss without rebroadcasting an applied command", function()
	local h, c = pair(); gui_pair_steps(h, c)
	h.ms_per_day = 4000; gui_pair_steps(h, c)
	local before = sync.decode(c.vars.TF3MP_OWN_GUI)
	c.env = { api = c.api, os = c.os }; c.gui()
	local after = sync.decode(c.vars.TF3MP_OWN_GUI)
	assert(after.cal == before.cal and after.cv == before.cv and after.cb == before.cb)
	assert(h.ms_per_day == 4000 and c.ms_per_day == 4000)
end)

test("invalid and stale calendar packets never reach command API", function()
	for _, value in ipairs({ -1, 0.5, math.huge, 2147483648, "1000" }) do
		local out = sync.calendar_step({}, { calendar = 1000, role = "client", now = 0, src = "gui",
			peer = { cal = value, cv = 1, hb = 1, cb = "host" } })
		assert(out.command == nil)
	end
	local mem, peer = {}, { cal = 1000, cv = 0, hb = 1, cb = "host" }
	sync.calendar_step(mem, { calendar = 1000, role = "client", now = 0, peer = peer })
	peer.cal, peer.cv = 2000, 1
	local out = sync.calendar_step(mem, { calendar = 1000, role = "client", now = 20, peer = peer })
	assert(out.command == nil and mem.value == 1000)
end)

test("calendar commands retry without producing new user versions", function()
	local mem, peer = {}, { cal = 2000, cv = 3, hb = 1, cb = "host" }
	local function step(now)
		return sync.calendar_step(mem, { calendar = 1000, role = "client", now = now, peer = peer })
	end
	assert(step(0).command == 2000)
	assert(step(1).command == nil and mem.ver == 3)
	assert(step(3.5).command == 2000 and mem.ver == 3)
	step(7); step(10.5); local out = step(14)
	assert(mem.broken and out.command == nil and has(out.logs, "could not be applied"))
end)

test("catchup changes only simulation speed, never calendar day length", function()
	local h, c = pair(); gui_pair_steps(h, c)
	h.gt = 60000
	for _ = 1, 5 do h.gui(2.1); c.gui(2.1) end
	assert(c.speed == 2 and h.ms_per_day == 600000 and c.ms_per_day == 600000)
end)

test("calendar commands also work through the simulation fallback without callbacks", function()
	local h, c = pair(); h.ms_per_day = 4000
	for _ = 1, main.SYNC_FALLBACK_AFTER + 10 do
		h.clock, c.clock = h.clock + 0.3, c.clock + 0.3
		h.tick(); c.tick()
	end
	assert(c.ms_per_day == 4000 and not has(c.logs, "Callbacks are currently disallowed"))
end)

test("loading a shared save clears both copied timelines before the first paused heartbeat", function()
	local timeline = require("/mp_probe/timeline.lua")
	for _, first in ipairs({ "update", "heartbeat" }) do
		local h, c = pair()
		for i, g in ipairs({h, c}) do
			g.vars.TF3MP_ORDERING = "1"
			g.vars.TF3MP_WORLD = tostring(i) .. "-123-4"
			g.vars.TF3MP_WORLD_ACK = g.vars.TF3MP_WORLD
			g.gt, g.speed = 8200600, 0
			-- Both load the host's saved, still PREPARED command (the reported run).
			g.s.loaded_world = "1-122-3"
			g.s.timeline = timeline.new("host")
			g.s.timeline.last = 2
			g.s.timeline.active = { seq=3, at=8194400, line="A1 stale", origin="host", phase="prepared" }
			g.s.network_work = { token="old.8", pending=1 }
			g.s.network_done = { token="old.7", result="OK" }
			g.s.action_entities = { ["old:line:1"]=999 }
			g.s.weld_checks = {{due=1}}
			g.s.bridge_parts = { token="old.8" }
			g.run(function()
				if first == "update" then main.update(nil,g.state,0)
				else main.handleEvent(nil,g.state,"mp_probe","mp_probe_replay","mp_probe_replay",{timeline_tick=true}) end
			end)
			assert(g.s.timeline.role == g.role and g.s.timeline.last == 0 and not g.s.timeline.active)
			assert(not g.s.network_work and not g.s.network_done and not g.s.action_entities and not g.s.weld_checks and not g.s.bridge_parts)
			assert(sync.decode(g.vars.TF3MP_OWN_CLOCK).hold == 0, "fresh idle clock must be published without an update counter")
		end
		for _=1,3 do h.gui(); c.gui() end
		h.speed=1
		for _=1,6 do h.gui(); c.gui() end
		assert(h.speed==1 and c.speed==1, "either copied timeline must allow the shared resume after loading")
	end
end)

test("a completed paused action publishes its release without another simulation update", function()
	local timeline = require("/mp_probe/timeline.lua")
	local g = game("host"); g.vars.TF3MP_ORDERING="1"; g.vars.TF3MP_PEER_CLOCK="gt=1200"
	g.gt, g.speed = 1200, 0
	local m = timeline.new("host"); m.gt=1200
	m.active={seq=1,at=1200,line="A1 completed",origin="host",phase="executing",executed=true,own_done=true,peer_done=true}
	m.published=sync.encode(timeline.clock(m)); m.published_phase="executing"
	g.s.timeline, g.s.updates = m, 7 -- No later multiple of five while paused.
	g.vars.TF3MP_OWN_CLOCK=m.published
	g.vars.TF3MP_OWN_CLOCKUI="hold=1 run=1"
	g.vars.TF3MP_OWN_GUI="speed=1 ver=2 by=host run=1 tg=1 src=gui hb=8"
	g.run(function() main.timeline_tick(g.env,g.state) end)
	assert(sync.decode(g.vars.TF3MP_OWN_CLOCK).hold==0 and g.s.updates==7)
	for _=1,5 do g.gui() end
	assert(g.speed==1 and sync.decode(g.vars.TF3MP_OWN_CLOCKUI).hold==0)
end)

test("simulation cannot pause ahead of the GUI hold marker and overwrite the user's speed", function()
	local timeline = require("/mp_probe/timeline.lua")
	local g=game("host"); g.gt,g.speed,g.max_speed=1200,3,3; g.vars.TF3MP_ORDERING="1"; g.gui()
	local m=timeline.new("host")
	m.active={seq=1,at=1200,line="A1 vehicle",origin="host",phase="committed",barrier=true}
	g.s.timeline=m; g.vars.TF3MP_PEER_CLOCK="gt=1200"
	g.run(function()main.timeline_tick(g.env,g.state)end)
	assert(g.speed==3 and not g.s.timeline.active.arrived, "GUI must record the hold before changing the engine speed")
	g.gui(); assert(g.speed==0 and sync.decode(g.vars.TF3MP_OWN_CLOCKUI).run==4)
	g.run(function()main.timeline_tick(g.env,g.state)end)
	assert(g.s.timeline.active.arrived)
	assert(not has(g.logs,"speed changed here: paused"))
end)

test("different action generations or asset counts never refund a historical purchase delta", function()
	for _, mismatch in ipairs({"econseq", "econbusy", "veh", "st", "con", "lines", "hveh"}) do
		local own = {money=10587941, econseq=5, econbusy=0, veh=222, st=295, con=80, lines=50, hveh="h1_1111111111111111"}
		local peer = copy(own); peer.money=4404624
		peer[mismatch] = mismatch == "hveh" and "h1_2222222222222222" or own[mismatch]+1
		local mem = {}
		for k=1,3 do
			local out=sync.compare(mem,k,own,peer,"client",k)
			assert(out.fix.money==nil and has(out.notes,"money comparison deferred"), mismatch)
		end
		peer[mismatch]=own[mismatch]
		assert(not sync.compare(mem,4,own,peer,"client",4).fix.money)
		assert(sync.compare(mem,5,own,peer,"client",5).fix.money == -6183317)
	end
end)

test("ordered checkpoints publish completed sequence and pending action state", function()
	local g=game("client"); g.vars.TF3MP_ORDERING="1"
	g.s.timeline={last=8,queue={},active={seq=9}}
	g.gt=59800; g.tick()
	local v=sync.decode(g.vars.TF3MP_OWN_SIM)
	assert(v.econseq==8 and v.econbusy==1)
end)

test("completed handover does not block subsequent money alignment", function()
	assert(not main.money_busy({network_handover={phase="done"},timeline={last=4,queue={}}}))
	assert(main.money_busy({network_handover={phase="queued"}}))
	assert(main.money_busy({actions={queue={"A1 pending purchase"}}}))
end)

test("money correction events recheck actions and already applied balance adjustments", function()
	for _, scenario in ipairs({"sequence", "pending", "adjustment"}) do
		local g=game("client")
		g.s.sync={adj=900,fixes={money={amount=-6183317}},last={money_compatible=true}}
		g.s.timeline={last=5,queue={}}
		if scenario=="sequence" then g.s.timeline.last=6
		elseif scenario=="pending" then g.s.actions={queue={"A1 buy"}}
		else g.s.sync.adj=1000 end
		g.run(function() main.sync_apply(g.env,g.state,{fix_money=-6183317,fix_seq=5,fix_adj=900,fix_gt=1000}) end)
		assert(g.balance==1000000 and #g.sent==0,scenario)
		assert(not g.s.sync.fixes.money and not g.s.sync.last.money_compatible and not g.s.sync.off)
		assert(has(g.logs,"skipped stale money correction"))
	end
end)

test("fresh money correction after matching action generation still books exactly once", function()
	local g=game("client"); g.s.timeline={last=5,queue={}}
	g.s.sync={adj=900,fixes={money={amount=1234}},last={money_compatible=true}}
	g.run(function() main.sync_apply(g.env,g.state,{fix_money=1234,fix_seq=5,fix_adj=900,fix_gt=1000}) end)
	assert(g.balance==1001234 and #g.sent==1 and g.s.sync.adj==2134)
end)

test("simulation progress measures time rather than trusting the speed display", function()
	local m={}
	assert(not sync.progress_step(m,0,0,3,false))
	for t=1,9 do assert(not sync.progress_step(m,t,t*1500,3,false)) end
	local rate,elapsed=sync.progress_step(m,10,15000,3,false)
	assert(rate==1.5 and elapsed==10)
	assert(not sync.progress_step(m,11,15000,0,false))
	assert(not sync.progress_step(m,30,15000,3,true))
	assert(not sync.progress_step(m,31,15000,3,false))
	assert(not sync.progress_step(m,32,16000,1,false))
	assert(not sync.progress_step(m,50,30000,1,false),"long frame gaps restart measurement")
	assert(not sync.progress_step(m,51,0,1,false),"reloaded game time restarts measurement")
end)

test("explicit selection survives unchanged throttled readback, delayed commands and GUI restoration", function()
	for _, role in ipairs({"host","client"}) do
		local mem, now, own, seq = {}, 0, 2, 10
		local function step(intent)
			now=now+0.3
			local out=sync.speed_step(mem,{own=own,role=role,now=now,src="gui",ordered=true,max_speed=2,intent=intent})
			return out
		end
		step();mem.speed=4;mem.target=2
		local out=step({seq=seq,speed=2})
		assert(mem.speed==2 and mem.ver==1 and out.command==nil,"a 2x click must not require a changed engine component")
		out=step({seq=seq,speed=2});assert(mem.ver==1,"same intent replayed")
		seq=seq+1;out=step({seq=seq,speed=0});assert(out.command==0 and mem.speed==0 and mem.ver==2)
		own=0;out=step({seq=seq,speed=0})
		local restore=sync.decode(out.publish or sync.encode({src="gui",speed=mem.speed,ver=mem.ver,by=role,tg=mem.target,run=0,ui=seq}))
		mem={};now=now+0.3
		sync.speed_step(mem,{own=0,role=role,now=now,src="gui",ordered=true,max_speed=3,restore=restore,intent={seq=seq,speed=0}})
		assert(mem.speed==0 and mem.ver==2,"restored GUI replays its last click")
		own=3;out=step({seq=seq+1,speed=4})
		assert(mem.speed==4 and mem.ver==3,"resume from internal 3x must retain valid requested 4x")
	end
end)
test("ordered 3x native resume and legacy peer state normalize to the 4x button", function()
	for _, role in ipairs({"host","client"}) do
		local mem={};sync.speed_step(mem,{own=0,role=role,now=0,src="gui",ordered=true,max_speed=3})
		local out=sync.speed_step(mem,{own=3,role=role,now=1,src="gui",ordered=true,max_speed=3})
		assert(mem.speed==4 and mem.target==3 and sync.decode(out.publish).speed==4)
		local peer={speed=3,ver=5,by="host",hb=1,max=3}
		out=sync.speed_step(mem,{own=3,role=role,now=2,src="gui",ordered=true,max_speed=3,peer=peer})
		assert(mem.speed==4 and mem.ver==5 and peer.speed==3,"peer input must remain untouched")
	end
end)
test("late native callbacks cannot replace a newer explicit user choice", function()
	local mem={};local function step(own,now,intent)
		return sync.speed_step(mem,{own=own,now=now,role="client",src="gui",ordered=true,max_speed=4,intent=intent})
	end
	step(2,0);step(2,1,{seq=1,speed=1})
	local version=mem.ver
	local out=step(4,2,{seq=1,speed=1})
	assert(mem.speed==1 and mem.ver==version and mem.target==1,"old native 4x callback became a fresh user request")
	out=step(1,3,{seq=1,speed=1});assert(mem.speed==1 and mem.ver==version and not mem.pending)
	out=step(1,4,{seq=2,speed=2});assert(mem.speed==2 and mem.ver==version+1,"new real click must still win")
end)
test("two ordered GUIs survive 16000 frames of capacity changes, explicit selections and pauses", function()
	local h,c=pair();h.vars.TF3MP_ORDERING,c.vars.TF3MP_ORDERING="1","1"
	for _=1,4 do h.gui();c.gui() end
	local seq={host=0,client=0}
	for cycle=1,1000 do
		local setter=cycle%2==0 and h or c
		h.max_speed,c.max_speed=1+(cycle%4),1+((cycle+2)%4)
		local speed=({0,1,2,4})[1+(cycle%4)]
		seq[setter.role]=seq[setter.role]+1
		setter.vars.TF3MP_OWN_SPEEDUI="seq="..seq[setter.role].." speed="..speed
		for _=1,8 do h.gui();c.gui() end
		for _,g in ipairs({h,c}) do
			local shared=sync.decode(g.vars.TF3MP_OWN_GUI)
			assert(shared.speed==speed and g.speed==math.min(speed,h.max_speed,c.max_speed),"cycle "..cycle.." "..g.role)
			assert(not has(g.logs,"could not be set"),"capacity changes exhausted speed commands")
		end
	end
end)
print(string.format("%d sync tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

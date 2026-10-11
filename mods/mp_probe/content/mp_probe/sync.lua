--- Keeping the two games in step (probe v24): game speed and pause, game time, date, money, and a
-- check that both games still hold the same things.
--
-- Channel (DLL v8): the mod logs "net state <key> <text>"; the DLL sends the latest text per key
-- to the other game every second (nothing queued, the latest text wins), where it lands in the
-- environment variable TF3MP_PEER_<KEY> (empty once the other game went silent). This game's own
-- latest text is echoed in TF3MP_OWN_<KEY>, and TF3MP_ROLE holds host, client, loopback or off.
--   gui  the shared game speed. Written by the GUI script, which also runs while the game is
--        paused; the simulation scripts stop with the game (GameTime.updateCount stands still).
--   sim  a checkpoint of the simulation every CHECK_MS of game time: money, loan, counts, date.
-- Both games compare the checkpoints with the same number; the host's values count, so only the
-- client corrects money, loan and date.
-- @module mp_probe.sync
local fingerprint = require("/mp_probe/fingerprint.lua")
local sync = {}

--- Game speed. The speed is a register both games can change; the change with the higher version
-- wins, and on a tie the host's value.
sync.MAX_SPEED = 4
--- TF3 may throttle a requested 4x to 3x on a busy world. Its own GUI clamps
-- requests to this estimate; that is capacity feedback, not a failed command.
function sync.maximum_speed(env)
	local ok, value = pcall(function() return env.api.gui.game.getEstimatedMaximumGameSpeed() end)
	if ok and type(value) == "number" and value == value and value > 0 and value < math.huge then
		return math.min(sync.MAX_SPEED, math.max(1, math.floor(value)))
	end
	return sync.MAX_SPEED
end
--- Catching up: the game that is behind by more than CATCHUP_START_MS of game time runs at twice
-- the shared speed (or, at MAX_SPEED, the game ahead runs at half) until the gap is below
-- CATCHUP_STOP_MS. The GUI script lets the game ahead wait at speed 0 beyond HOLD_MS. Beyond
-- FAR_MS the games are taken to run different savegames and nothing is done.
sync.CATCHUP_START_MS = 30000
sync.CATCHUP_STOP_MS = 5000
sync.HOLD_MS = 120000
sync.FAR_MS = 2 * 3600 * 1000
--- Real seconds: own state sent again at least this often, the other game's state counted as
-- current for this long after its heartbeat last changed, and a speed command given this long to
-- arrive before it is sent again (APPLY_TRIES times).
sync.HEARTBEAT_S = 2
sync.PEER_STALE_S = 8
sync.APPLY_WAIT_S = 3
sync.APPLY_TRIES = 3

--- Checkpoints: game time between two, and the length of one update (run 24: 200 ms each).
sync.CHECK_MS = 60000
sync.UPDATE_MS = 200
--- Checkpoints kept of each game.
sync.KEEP = 8
--- Money differences up to this much are left alone.
sync.MONEY_TOLERANCE = 1000
--- Counts that must match in both games.
sync.COUNT_FIELDS = { "lines", "veh", "st", "con" }
--- Persistent world contents, compared independently of local entity ids and moving vehicles.
sync.HASH_FIELDS = { "hcon", "hedge", "hline", "hveh", "hpos", "hcargo", "htown" }
local HASH_FIELD = { hcon = true, hedge = true, hline = true, hveh = true, hpos = true, hcargo = true, htown = true }
local DYNAMIC_HASH = { hpos = true, hcargo = true, htown = true }
--- A difference that stays is reported again after this many checkpoints.
sync.REPEAT_WARNING = 10

-- ---------------------------------------------------------------------------------------------
-- State texts

--- "key=value" pairs sorted by key; values are numbers or words without spaces.
function sync.encode(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = t[k]
		if type(v) == "number" then
			if v == math.floor(v) and math.abs(v) < 2 ^ 53 then v = string.format("%.0f", v)
			else v = string.format("%.3f", v) end
		elseif type(v) == "boolean" then
			v = v and "1" or "0"
		else
			v = tostring(v):gsub("[%s=]", "_")
		end
		parts[#parts + 1] = k .. "=" .. v
	end
	return table.concat(parts, " ")
end

--- The table of a state text; numbers come back as numbers. nil for an empty or unreadable text.
function sync.decode(text)
	if type(text) ~= "string" then return nil end
	local out, any = {}, false
	for k, v in text:gmatch("(%w+)=(%S+)") do
		out[k] = tonumber(v) or v
		any = true
	end
	return any and out or nil
end

--- host, client, loopback or off from the DLL; nil without DLL v8.
function sync.role(getenv)
	local ok, value = pcall(getenv, "TF3MP_ROLE")
	if ok and type(value) == "string" and value ~= "" then return value end
	return nil
end

function sync.speed_name(speed)
	if speed == 0 then return "paused" end
	return tostring(speed) .. "x"
end

-- ---------------------------------------------------------------------------------------------
-- Game speed

local function newer(peer, mem, role)
	local ver, speed = tonumber(peer.ver), tonumber(peer.speed)
	if not ver or not speed then return false end
	if ver > mem.ver then return true end
	return ver == mem.ver and speed ~= mem.speed and role == "client"
end

--- Where this game's speed should be, given the shared speed and the gap to the other game.
function sync.catchup(mem, input, fresh, log)
	local base = mem.speed
	local mode
	if base > 0 and fresh and mem.peer_t and input.own_t then
		local peer_now = mem.peer_t + (input.now - mem.peer_seen) * 1000 * (mem.peer_run or 0)
		-- Positive: this game is behind.
		local gap = peer_now - input.own_t
		if math.abs(gap) > sync.FAR_MS then
			if not mem.far then
				log(string.format("the games are %.0f minutes of game time apart; not catching up " ..
					"(load the same savegame in both games)", math.abs(gap) / 60000))
				mem.far = true
			end
		else
			mem.far = nil
			mode = mem.catchup
			if mode == "fast" and gap < sync.CATCHUP_STOP_MS then mode = nil end
			if (mode == "slow" or mode == "hold") and gap > -sync.CATCHUP_STOP_MS then mode = nil end
			if mode == "hold" and not input.hold then mode = nil end
			if mode == nil and mem.catchup == nil then
				if gap > sync.CATCHUP_START_MS and base < sync.MAX_SPEED then
					mode = "fast"
				elseif gap < -sync.CATCHUP_START_MS then
					if input.hold and -gap > sync.HOLD_MS then mode = "hold"
					elseif base >= sync.MAX_SPEED then mode = "slow" end
				end
			end
			if mode ~= mem.catchup then
				local seconds = math.abs(gap) / 1000
				if mode == "fast" then log(string.format("this game is %.0f s of game time behind, catching up", seconds))
				elseif mode == "slow" then log(string.format("this game is %.0f s of game time ahead, slowing down", seconds))
				elseif mode == "hold" then log(string.format("this game is %.0f s of game time ahead, waiting", seconds))
				else log(string.format("caught up (gap %.0f s of game time)", seconds)) end
			end
		end
	end
	if mode ~= mem.catchup and mode == nil and mem.catchup ~= nil and not (base > 0 and fresh) then
		log("catching up stopped (" .. (base == 0 and "paused" or "no news from the other game") .. ")")
	end
	mem.catchup = mode
	if mode == "fast" then return math.min(sync.MAX_SPEED, base * 2) end
	if mode == "slow" then return math.max(1, math.floor(base / 2)) end
	if mode == "hold" then return 0 end
	return base
end

--- One step of the shared game speed, from the GUI script or (without it) from the simulation.
-- @param mem table kept between calls
-- @param input table own (speedup now), calendar (calendar editor milliseconds per day),
--   own_t (game time in ms), role ("host" or "client"),
--   peer (decoded gui state of the other game or nil), now (real seconds), hold (the game ahead
--   may wait at speed 0), src ("gui" or "sim"), restore (decoded TF3MP_OWN_GUI, used when mem is
--   empty: the DLL keeps what this game said last, in case the Lua state lost its memory)
-- @return table command (speed to set or nil), logs (list of texts), publish (state text or nil)
local function calendar_value(value)
	return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value == math.floor(value)
end

--- Independent calendar register: milliseconds per day, including 0 (calendar stopped).
-- Both players may change it; higher version wins, host wins simultaneous changes.
function sync.calendar_step(mem, input)
	local out = { logs = {} }
	local own, peer, now, role = input.calendar, input.peer, input.now, input.role
	if not calendar_value(own) then return out end
	if mem.value == nil then
		local r = input.restore
		if r and r.src == input.src and calendar_value(r.cal) and calendar_value(r.cv) then
			mem.value, mem.ver, mem.by = r.cal, r.cv, r.cb
			mem.target = calendar_value(r.ct) and r.ct or own
		else mem.value, mem.ver, mem.by, mem.target = own, 0, role, own end
	end
	if peer and peer.hb ~= nil and peer.hb ~= mem.peer_hb then
		mem.peer_hb, mem.peer_seen = peer.hb, now
	end
	local fresh = peer and mem.peer_seen and now - mem.peer_seen <= sync.PEER_STALE_S
	local valid_peer = fresh and calendar_value(peer.cal) and calendar_value(peer.cv)
	if mem.pending ~= nil then
		if own == mem.pending then mem.pending = nil
		elseif own ~= mem.pending_from then mem.pending = nil -- a new local user change
		elseif now - mem.pending_at > sync.APPLY_WAIT_S then
			if mem.tries < sync.APPLY_TRIES then
				mem.tries, mem.pending_at = mem.tries + 1, now
				out.command = mem.pending
				out.logs[#out.logs + 1] = "calendar command not applied yet, retrying"
			else
				mem.broken, mem.pending, mem.target = true, nil, own
				out.logs[#out.logs + 1] = "calendar command could not be applied; this game no longer follows"
			end
		end
	end
	if mem.pending == nil and own ~= mem.target then
		mem.ver = math.max(mem.ver, valid_peer and peer.cv or 0) + 1
		mem.value, mem.by = own, role
		out.logs[#out.logs + 1] = "calendar changed here: " .. own .. " ms/day (version " .. mem.ver .. ")"
	end
	if valid_peer and (peer.cv > mem.ver or (peer.cv == mem.ver and peer.cal ~= mem.value and role == "client")) then
		mem.value, mem.ver, mem.by = peer.cal, peer.cv, peer.cb
		out.logs[#out.logs + 1] = "calendar from the other game: " .. mem.value .. " ms/day (version " .. mem.ver .. ")"
	end
	mem.target = mem.broken and own or mem.value
	if own == mem.target then mem.pending = nil
	elseif mem.pending ~= mem.target then
		out.command = mem.target
		mem.pending, mem.pending_from, mem.pending_at, mem.tries = mem.target, own, now, 0
	end
	out.state = { cal = mem.value, cv = mem.ver, cb = mem.by, ct = mem.target, cr = own }
	return out
end

function sync.speed_step(mem, input)
	local out = { logs = {} }
	local function log(text) out.logs[#out.logs + 1] = text end
	local own, role, peer, now = input.own, input.role, input.peer, input.now
	local limit = tonumber(input.max_speed)
	if not limit or limit ~= limit or limit < 1 or limit > sync.MAX_SPEED or limit ~= math.floor(limit) then limit = sync.MAX_SPEED end
	if mem.speed == nil then
		local o = input.restore
		if o and o.src == input.src and tonumber(o.ver) and tonumber(o.speed) then
			mem.speed, mem.ver, mem.by = tonumber(o.speed), tonumber(o.ver), tostring(o.by)
			mem.target, mem.hb, mem.restores = tonumber(o.tg) or own, tonumber(o.hb) or 0, (tonumber(o.rs) or 0) + 1
		else
			mem.speed, mem.ver, mem.by, mem.target, mem.hb = own, 0, role, own, 0
		end
	end
	-- A lower engine capacity must not turn an otherwise applied speed request
	-- into a player edit or exhaust the retry budget. Preserve the shared request
	-- so a later capacity increase can resume it without creating a new version.
	local capacity_pending = mem.target and mem.target > limit and own == mem.target
	if mem.target then mem.target = math.min(mem.target, limit) end
	if mem.pending then mem.pending = math.min(mem.pending, limit) end
	if peer and peer.hb ~= nil and peer.hb ~= mem.peer_hb then
		mem.peer_hb, mem.peer_seen = peer.hb, now
		mem.peer_t, mem.peer_run = tonumber(peer.gt), tonumber(peer.run) or 0
	end
	local fresh = peer ~= nil and mem.peer_seen ~= nil and now - mem.peer_seen <= sync.PEER_STALE_S
	-- A speed command of ours that has not arrived yet.
	if mem.pending ~= nil then
		if own == mem.pending then
			mem.pending = nil
		elseif now - mem.pending_at > sync.APPLY_WAIT_S then
			if own == mem.pending_from and (mem.tries or 0) < sync.APPLY_TRIES then
				mem.tries = (mem.tries or 0) + 1
				mem.pending_at = now
				out.command = mem.pending
				log("speed " .. sync.speed_name(mem.pending) .. " not set yet, sending again")
			elseif own == mem.pending_from then
				log("speed " .. sync.speed_name(mem.pending) .. " could not be set; this game no longer follows")
				mem.broken, mem.pending, mem.target = true, nil, own
			else
				-- The player changed the speed in the meantime.
				mem.pending = nil
			end
		end
	end
	-- The player changed the speed in this game.
	if mem.pending == nil and own ~= mem.target and not capacity_pending then
		mem.ver = math.max(mem.ver, peer and tonumber(peer.ver) or 0) + 1
		mem.speed, mem.by, mem.catchup = own, role, nil
		log(string.format("speed changed here: %s (version %d)", sync.speed_name(own), mem.ver))
	end
	if peer and newer(peer, mem, role) then
		mem.speed, mem.ver, mem.by, mem.catchup = tonumber(peer.speed), tonumber(peer.ver), tostring(peer.by), nil
		log(string.format("speed from the other game: %s (version %d, set by the %s)", sync.speed_name(mem.speed),
			mem.ver, mem.by))
	end
	local requested = sync.catchup(mem, input, fresh, log)
	local target = math.min(requested, limit)
	if target ~= requested then
		if mem.limited ~= limit then log("speed limited by the game's current capacity: " .. sync.speed_name(limit)) end
		mem.limited = limit
	else mem.limited = nil end
	mem.target = target
	if mem.broken then
		-- Commands do not work here: follow nothing, but still pass the player's changes on.
		mem.target = own
	elseif own == target then
		mem.pending = nil
	elseif mem.pending ~= target then
		out.command = target
		mem.pending, mem.pending_from, mem.pending_at, mem.tries = target, own, now, 0
	end
	local state = { speed = mem.speed, ver = mem.ver, by = mem.by, run = own, tg = mem.target, src = input.src }
	mem.calendar = mem.calendar or {}
	local calendar = sync.calendar_step(mem.calendar, input)
	out.calendar_command = calendar.command
	for _, line in ipairs(calendar.logs) do log(line) end
	for k, v in pairs(calendar.state or {}) do state[k] = v end
	if mem.restores then state.rs = mem.restores end
	local key = sync.encode(state)
	if key ~= mem.published or now - (mem.published_at or -1e9) >= sync.HEARTBEAT_S then
		mem.hb = (mem.hb or 0) + 1
		state.hb, state.gt = mem.hb, input.own_t
		out.publish = sync.encode(state)
		mem.published, mem.published_at = key, now
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Dates

--- Days since 1970-01-01 (proleptic Gregorian calendar).
function sync.days(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

function sync.date_text(date)
	return string.format("%d-%02d-%02d", date.year, date.month, date.day)
end

--- Days from date a to date b ("y-m-d" texts); nil if one is unreadable.
function sync.day_diff(a, b)
	local function parse(text)
		if type(text) ~= "string" then return nil end
		local y, m, d = text:match("^(%-?%d+)%-(%d+)%-(%d+)$")
		if not y then return nil end
		return sync.days(tonumber(y), tonumber(m), tonumber(d))
	end
	local da, db = parse(a), parse(b)
	if not da or not db then return nil end
	return db - da
end

-- ---------------------------------------------------------------------------------------------
-- Checkpoints

function sync.checkpoint_of(gt)
	return math.floor(gt / sync.CHECK_MS)
end

--- True in the first update of a checkpoint period. Both games load the same savegame, so they
-- step through the same game times and record the same checkpoint at the same game time.
function sync.at_checkpoint(gt)
	return gt - sync.checkpoint_of(gt) * sync.CHECK_MS < sync.UPDATE_MS
end

--- Adds values as checkpoint k to a list of { k = , v = } (ascending, at most KEEP).
function sync.keep(list, k, values)
	list = list or {}
	for i = #list, 1, -1 do
		if list[i].k >= k then table.remove(list, i) end
	end
	list[#list + 1] = { k = k, v = values }
	while #list > sync.KEEP do table.remove(list, 1) end
	return list
end

function sync.find(list, k)
	for _, entry in ipairs(list or {}) do
		if entry.k == k then return entry.v end
	end
	return nil
end

local CORRECTED = { "loan", "money", "date" }

--- Compares checkpoint k of both games.
-- @param mem table kept in the script state (last comparison, corrections waiting to show, ...)
-- @param own table this game's values (money, loan, lines, veh, st, con, date)
-- @param peer table the other game's values
-- @param role string "host" or "client"; only the client corrects
-- @param latest number this game's newest checkpoint; a correction made now shows from the next one
-- @return table diffs (field -> {own, peer, d}), warnings, notes (texts), fix (field -> amount)
function sync.compare(mem, k, own, peer, role, latest)
	local out = { warnings = {}, notes = {}, fix = {}, diffs = {},
		world_fields = 0, world_different = 0, world_mismatch = false, world_diffs = {}, world_unreadable = {},
		loan_mismatch = false, needs_resync = false }
	local diffs = out.diffs
	for _, f in ipairs(sync.COUNT_FIELDS) do
		local a, b = tonumber(own[f]), tonumber(peer[f])
		if a and b and a ~= b then diffs[f] = { own = a, peer = b, d = b - a } end
	end
	for _, f in ipairs(sync.HASH_FIELDS) do
		local a, b = own[f], peer[f]
		local time_match = not DYNAMIC_HASH[f] or (type(own.wgt) == "number" and own.wgt == peer.wgt
			and own.wgt >= 0 and own.wgt < math.huge and own.wgt == own.gt and peer.wgt == peer.gt)
		if time_match and type(a) == "string" and type(b) == "string"
			and a:match("^h[12]_%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")
			and b:match("^h[12]_%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")
			and a:sub(1, 3) == b:sub(1, 3) and (not DYNAMIC_HASH[f] or a:sub(1, 3) == "h2_") then
			out.world_fields = out.world_fields + 1
			if a ~= b then
				diffs[f] = { own = a, peer = b }
				out.world_different = out.world_different + 1
				out.world_diffs[#out.world_diffs + 1] = f
			end
		else out.world_unreadable[#out.world_unreadable + 1] = f
		end
	end
	local m_own, m_peer = tonumber(own.money), tonumber(peer.money)
	if m_own and m_peer and math.abs(m_peer - m_own) > sync.MONEY_TOLERANCE then
		diffs.money = { own = m_own, peer = m_peer, d = m_peer - m_own }
	end
	local l_own, l_peer = tonumber(own.loan), tonumber(peer.loan)
	if l_own and l_peer and l_own ~= l_peer then diffs.loan = { own = l_own, peer = l_peer, d = l_peer - l_own } end
	local days = sync.day_diff(own.date, peer.date)
	if days and days ~= 0 then diffs.date = { own = own.date, peer = peer.date, d = days } end

	-- Corrections made earlier show from this game's next checkpoint on.
	mem.fixes, mem.off, mem.warned = mem.fixes or {}, mem.off or {}, mem.warned or {}
	for _, field in ipairs(CORRECTED) do
		local fix = mem.fixes[field]
		if fix and k > fix.after then
			local d = diffs[field] and diffs[field].d or 0
			if field == "money" and d ~= 0 then
				-- Purchases, maintenance and income continue between checkpoints.
				-- A new difference of the same sign cannot prove a booking failed.
				-- Direct callback/account observations are handled by settle_fix.
				out.notes[#out.notes + 1] = string.format("the money correction by %s %s; current difference %s, continuing comparison",
					tostring(fix.amount), fix.observed == true and "was observed in the account" or
					(fix.confirmed and "was accepted by the game" or "has no direct confirmation"), tostring(d))
			elseif d ~= 0 and (d > 0) == (fix.amount > 0) and math.abs(d) * 2 >= math.abs(fix.amount) then
				mem.off[field] = true
				out.notes[#out.notes + 1] = string.format("the %s correction by %s had no effect (still %s); " ..
					"%s is no longer corrected", field, tostring(fix.amount), tostring(d), field)
			else
				out.notes[#out.notes + 1] = string.format("the %s correction by %s worked", field, tostring(fix.amount))
			end
			mem.fixes[field] = nil
		end
	end

	local prev = mem.last
	local managed_loan = own.loanmanaged == 1 or peer.loanmanaged == 1
	local function lasting(field)
		local p = prev and prev.k == k - 1 and prev.diffs[field]
		local d = diffs[field]
		if not d or not p then return false end
		if field == "money" or field == "loan" or field == "date" then return (p.d > 0) == (d.d > 0) end
		return true
	end
	local fields = {}
	for field in pairs(diffs) do fields[#fields + 1] = field end
	table.sort(fields)
	for _, field in ipairs(fields) do
		local d = diffs[field]
		local w = mem.warned[field]
		local repeated = w and w.own == d.own and w.peer == d.peer and k - w.k < sync.REPEAT_WARNING
		if lasting(field) and HASH_FIELD[field] then out.world_mismatch = true end
		if lasting(field) and not repeated then
			mem.warned[field] = { k = k, own = d.own, peer = d.peer }
			out.warnings[#out.warnings + 1] = string.format("%s here %s, in the other game %s",
				field, tostring(d.own), tostring(d.peer))
		end
	end
	out.loan_mismatch = managed_loan and lasting("loan") or false
	out.needs_resync = out.loan_mismatch
	if role == "client" then
		for _, field in ipairs(CORRECTED) do
			-- A loan booking moves the balance too, so money waits for the next comparison.
			local blocked = (field == "money" and out.fix.loan ~= nil)
				-- Native loan schedules can differ with the calendar. Keep those
				-- diagnostic, but still align spendable money to the host; blocking
				-- both let the real v54 accounts drift by over twenty million.
				or (managed_loan and field == "loan")
			if lasting(field) and not mem.off[field] and not mem.fixes[field] and not blocked then
				out.fix[field] = diffs[field].d
				mem.fixes[field] = { amount = diffs[field].d, after = latest or k, k = k }
			end
		end
	end
	mem.last = { k = k, diffs = diffs }
	return out
end

--- Record direct command evidence separately from a later world's balance.
-- Only an explicit rejection stops a field immediately. Three consecutive
-- successful nonzero money callbacks with an unchanged observed account stop
-- that correction too, rather than issuing ineffective bookings forever.
-- Mixed economic changes or unreadable accounts provide no such proof.
function sync.settle_fix(mem, field, amount, success, evidence)
	mem.fixes, mem.off = mem.fixes or {}, mem.off or {}
	if success == false then
		mem.off[field], mem.fixes[field] = true, nil
		return "rejected"
	end
	local fix = mem.fixes[field]
	if fix and fix.amount == amount then
		fix.confirmed = success == true or nil
		fix.observed = evidence and evidence.applied
	end
	if field == "money" then
		if not evidence or evidence.applied ~= false then mem.adj = (mem.adj or 0) + amount end
		if success == true and amount ~= 0 and evidence and evidence.applied == false then
			mem.money_no_effect = (mem.money_no_effect or 0) + 1
			if mem.money_no_effect >= 3 then
				mem.off.money, mem.fixes.money = true, nil
				return "no_effect_stopped"
			end
			return "no_effect"
		end
		mem.money_no_effect = nil
	end
	return evidence and evidence.applied == true and "observed" or "accepted"
end

-- ---------------------------------------------------------------------------------------------
-- Reading and changing the game (engine calls, guarded by the callers)

local function world_component(env, name)
	local e = env.api.engine
	return assert(e.getComponent(e.util.getWorld(), env.api.type.ComponentType[name]), name .. " missing")
end

--- Speed (0 = paused) and calendar day length.
function sync.read_speed(env)
	local c = world_component(env, "GAME_SPEED")
	return c.speedup, c.millisPerDay
end

function sync.read_time(env)
	return world_component(env, "GAME_TIME").gameTime
end

--- The values of a checkpoint. Fields that cannot be read are left out and named in the second
-- return value.
function sync.values(env, gt, deferred_world)
	local e, ct = env.api.engine, env.api.type.ComponentType
	local out, failed = { gt = gt }, {}
	local function try(name, fn)
		local ok, v = pcall(fn)
		if ok and v ~= nil then out[name] = v else failed[#failed + 1] = name end
	end
	local account
	try("money", function()
		account = e.getComponent(e.util.getPlayer(), ct.ACCOUNT)
		return account.balance
	end)
	try("loan", function() return account and account.loan end)
	if e.system and e.system.gameScriptSystem ~= nil then out.loanmanaged = 1 end
	try("lines", function() return #e.system.lineSystem.getLines() end)
	local function count(name, filter)
		if deferred_world then
			local config = name == "CONSTRUCTION" and { requireOwnedByPlayer = e.util.getPlayer() } or nil
			return #e.getEntitiesWithComponent(assert(ct[name]), config)
		end
		local ids = {}
		e.forEachEntityWithComponent(function(id) ids[#ids + 1] = id end, assert(ct[name]))
		if not filter then return #ids end
		local n = 0
		for _, id in ipairs(ids) do if filter(id) then n = n + 1 end end
		return n
	end
	try("veh", function() return count("TRANSPORT_VEHICLE") end)
	try("st", function() return count("STATION") end)
	try("con", function()
		local player, owned = e.util.getPlayer(), assert(ct.PLAYER_OWNED)
		return count("CONSTRUCTION", function(id)
			local o = e.getComponent(id, owned)
			return o ~= nil and o.player == player
		end)
	end)
	try("date", function() return sync.date_text(e.util.getCalendarDate(gt)) end)
	if deferred_world then return out, failed, fingerprint.begin(env, gt) end
	local contents, unreadable = fingerprint.values(env)
	for name, value in pairs(contents) do out[name] = value end
	for _, name in ipairs(unreadable) do failed[#failed + 1] = name end
	return out, failed
end

--- Processes only the immutable checkpoint data; no live world reads on later updates.
function sync.world_step(env, job)
	return fingerprint.step(env, job)
end

--- Names of an engine enum table, sorted.
function sync.names(t)
	local out = {}
	pcall(function()
		for k in pairs(t) do if type(k) == "string" then out[#out + 1] = k end end
	end)
	table.sort(out)
	return out
end

--- Values tried in order for JournalEntry.Other of a money correction.
sync.OTHER_NAMES = { "CHEAT", "OTHER", "MISC" }

--- A journal entry of kind (a JournalEntry.Type name, e.g. OTHER or LOAN) over amount.
-- @return entry or nil, text of what was set
function sync.journal_entry(env, amount, kind)
	if type(amount) ~= "number" or amount ~= amount or math.abs(amount) > 9007199254740991
		or amount ~= math.floor(amount) then return nil, "invalid journal amount (finite safe integer required)" end
	if kind ~= "OTHER" and kind ~= "LOAN" then return nil, "unsupported journal category" end
	local JE = env.api.type.JournalEntry
	local made, entry = pcall(function() return JE.new() end)
	if not made or not entry then return nil, "journal entry constructor unavailable" end
	local notes = {}
	local ok_a, err_a = pcall(function() entry.amount = amount end)
	notes[#notes + 1] = ok_a and ("amount " .. tostring(amount)) or ("amount FAILED " .. tostring(err_a):sub(1, 80))
	-- JournalBookAsset requires -1 so the game assigns the booking's current time (run 27).
	local ok_t, err_t = pcall(function() entry.time = -1 end)
	notes[#notes + 1] = ok_t and "time -1" or ("time FAILED " .. tostring(err_t):sub(1, 80))
	local ok_c, err_c = pcall(function()
		local category = entry.category
		category.type = assert(JE.Type[kind], "JournalEntry.Type." .. kind .. " missing")
		if kind == "OTHER" and JE.Other then
			for _, name in ipairs(sync.OTHER_NAMES) do
				local ok_o, value = pcall(function() return JE.Other[name] end)
				if ok_o and value ~= nil then
					category.other = value
					notes[#notes + 1] = "other " .. name
					break
				end
			end
		end
		-- Reassigned as before v33: money corrections booked this way in game (runs 24-30). If the
		-- engine hands out a copy, only the reassignment carries the type; on a reference it is a no-op.
		entry.category = category
	end)
	notes[#notes + 1] = ok_c and ("type " .. kind) or ("type FAILED " .. tostring(err_c):sub(1, 80))
	-- Without its type the entry could land as anything (a loan, a construction), so it is not booked.
	if not ok_a or not ok_t or not ok_c then return nil, table.concat(notes, ", ") end
	return entry, table.concat(notes, ", ")
end

--- What the game's JournalEntry looks like, for the log.
function sync.describe_journal(env)
	local JE = env.api.type.JournalEntry
	local parts = {}
	parts[#parts + 1] = "Type: " .. table.concat(sync.names(JE.Type), ",")
	parts[#parts + 1] = "Other: " .. table.concat(sync.names(JE.Other), ",")
	local ok, entry = pcall(JE.new)
	if ok then
		for _, f in ipairs({ "amount", "time" }) do
			local ok_f, v = pcall(function() return entry[f] end)
			parts[#parts + 1] = f .. "=" .. (ok_f and tostring(v) or "?")
		end
		local ok_c, category = pcall(function() return entry.category end)
		for _, f in ipairs({ "type", "carrier", "construction", "maintenance", "other" }) do
			local ok_f, v = pcall(function() return category[f] end)
			parts[#parts + 1] = "category." .. f .. "=" .. ((ok_c and ok_f) and tostring(v) or "?")
		end
	end
	return table.concat(parts, "; ")
end

--- Books amount for this game's player. callback(result, success) as for api.cmd.sendCommand.
function sync.book(env, amount, kind, callback)
	local entry, notes = sync.journal_entry(env, amount, kind)
	if not entry then return false, notes end
	local cmd = env.api.cmd
	local function balance()
		local ok, value = pcall(function()
			return env.api.engine.getComponent(env.api.engine.util.getPlayer(), env.api.type.ComponentType.ACCOUNT).balance
		end)
		if ok and type(value) == "number" and value == value and math.abs(value) < 2^53 then return value end
	end
	local before = callback and balance()
	local done
	if callback then
		local settled = false
		done = function(result, success)
			if settled then return end
			settled = true
			local after = balance()
			local evidence = { before = before, after = after, expected = amount }
			if before ~= nil and after ~= nil then
				evidence.delta = after - before
				if evidence.delta == amount then evidence.applied = true
				elseif amount ~= 0 and evidence.delta == 0 then evidence.applied = false end
			end
			callback(result, success, evidence)
		end
	end
	-- Without a position, as in runs 24-30 (the position is optional and only places the money popup).
	cmd.sendCommand(cmd.makeJournalBookAssetCmd(env.api.engine.util.getPlayer(), entry), done)
	return true, notes
end

--- Moves the calendar by days (from the date of game time gt).
function sync.shift_date(env, gt, days, callback)
	local now = env.api.engine.util.getCalendarDate(gt)
	local target = env.api.type.Date.addOffsetDays(now, days)
	local cmd = env.api.cmd
	cmd.sendCommand(cmd.makeGameSetDateCmd(target), callback)
	return sync.date_text(now) .. " -> " .. sync.date_text(target)
end

--- Without callback the command goes out alone: the simulation's update() may not pass one (run 25).
function sync.set_speed(env, speed, callback)
	local cmd = env.api.cmd
	speed = math.min(speed, sync.maximum_speed(env))
	if callback then
		cmd.sendCommand(cmd.makeGameSetSpeedCmd(speed), callback)
	else
		cmd.sendCommand(cmd.makeGameSetSpeedCmd(speed))
	end
end

function sync.set_calendar(env, millis_per_day, callback)
	assert(calendar_value(millis_per_day), "invalid calendar day length")
	local cmd = env.api.cmd
	local command = cmd.makeGameSetCalendarSpeedCmd(millis_per_day)
	if callback then cmd.sendCommand(command, callback) else cmd.sendCommand(command) end
end

return sync

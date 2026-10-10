-- Common simulation stamps for commands HELD BEFORE their original execution.
-- Post-build observations are expressly rejected: delaying a copy is not lockstep.
-- v34: the stamp is a barrier. Each game holds (speed 0) once its clock reaches the stamp and
-- executes when both have arrived; a game whose pause landed a tick late still executes, so a
-- late packet or a coarse pause never stops the session (a pause through the speed command
-- cannot be placed on an exact tick). The executing tick is logged on both games.
-- Plain persisted data only; the caller supplies reliable messages and the actual game clock.
-- v54: vehicle commands, paused games and widely separated clocks use a readiness barrier.
-- Both stop at their current tick; no original command runs before both have acknowledged it.
local wire = require("/mp_probe/wire.lua")
local timeline = { STEP = 200, LEAD = 4000, MAX_SKEW = 4000, MAX_QUEUE = 64, MAX_PAYLOAD = 120000 }

local function integer(n) return type(n) == "number" and n == n and n >= 0 and n < 2^53 and n == math.floor(n) end
local function payload(line)
	return type(line) == "string" and #line <= timeline.MAX_PAYLOAD and
		(line:sub(1, 3) == "A1 " or line:sub(1, 3) == "B5 ")
end
local function emit(m, v) m.out[#m.out + 1] = "S1 " .. wire.encode(v) end
local function fail(m, reason)
	if not m.error then
		m.error = tostring(reason):sub(1, 180)
		emit(m, { op = "fail", seq = m.active and m.active.seq or 0, reason = m.error })
	end
	return nil, m.error
end
function timeline.new(role)
	assert(role == "host" or role == "client", "timeline role missing")
	return { role = role, next_request = 0, last = 0, queue = {}, out = {}, seen = {}, requests = { host = 0, client = 0 } }
end
local function request(m, v)
	if not payload(v.line) or (v.origin ~= "host" and v.origin ~= "client")
		or type(v.id) ~= "string" or not v.id:match("^[hc]%d+$")
		or (v.barrier ~= nil and type(v.barrier) ~= "boolean") then return fail(m, "invalid held command") end
	if m.seen[v.id] then
		local seen = m.seen[v.id]
		if seen.line ~= v.line or seen.barrier ~= v.barrier then return fail(m, "request identity reused with different command") end
		return true
	end
	local prefix, n = v.id:match("^([hc])(%d+)$"); n = tonumber(n)
	if prefix ~= (v.origin == "host" and "h" or "c") or not integer(n) then return fail(m, "invalid request identity") end
	if n <= m.requests[v.origin] then return true end
	if n ~= m.requests[v.origin] + 1 then return fail(m, "held request sequence gap") end
	if #m.queue >= timeline.MAX_QUEUE then return fail(m, "held command queue full") end
	m.requests[v.origin] = n
	m.seen[v.id] = { line = v.line, barrier = v.barrier }; m.queue[#m.queue + 1] = v
	return true
end
function timeline.submit(m, line, held, options)
	if held ~= true then return nil, "pre-execution capture required; original command already applied" end
	if m.error then return nil, m.error end
	if not payload(line) then return nil, "unsupported or oversized held command" end
	if m.role == "client" and (m.pending_requests or 0) >= timeline.MAX_QUEUE then
		return nil, "held command queue full"
	end
	m.next_request = m.next_request + 1
	local v = { op = "request", origin = m.role, id = (m.role == "host" and "h" or "c") .. m.next_request, line = line }
	if options and options.barrier then v.barrier = true end
	if m.role == "host" then return request(m, v) end
	m.pending_requests = (m.pending_requests or 0) + 1
	emit(m, v); return true
end
local function matches(a, v) return a and a.seq == v.seq and a.at == v.at end
function timeline.receive(m, line, now)
	if m.error then return nil, m.error end
	if type(line) ~= "string" or line:sub(1, 3) ~= "S1 " then return fail(m, "invalid timeline message") end
	local v, err = wire.decode(line:sub(4))
	if type(v) ~= "table" or not integer(now) then return fail(m, err or "invalid timeline message") end
	if v.op == "fail" then return fail(m, "partner timeline failure: " .. tostring(v.reason):sub(1, 120)) end
	if v.op == "request" then
		if m.role ~= "host" or v.origin ~= "client" or type(v.id) ~= "string" or not v.id:match("^c%d+$") then return fail(m, "request direction invalid") end
		return request(m, v)
	end
	if not integer(v.seq) or v.seq < 1 then return fail(m, "invalid common sequence") end
	if v.seq <= m.last then return true end
	local a = m.active
	if v.op == "plan" then
		if m.role ~= "client" or v.seq ~= m.last + 1 or not integer(v.at) or v.at % timeline.STEP ~= 0
			or not payload(v.line) or (v.origin ~= "host" and v.origin ~= "client")
			or (v.barrier ~= nil and type(v.barrier) ~= "boolean") then
			return fail(m, "invalid common plan (sequence " .. tostring(v.seq) .. ", expected " .. tostring(m.last + 1) .. ")")
		end
		if a then
			if not matches(a, v) or a.line ~= v.line or a.origin ~= v.origin or a.barrier ~= v.barrier then return fail(m, "conflicting common plan") end
		else
			a = { seq = v.seq, at = v.at, line = v.line, origin = v.origin, barrier = v.barrier, phase = "prepared" }; m.active = a
		end
		emit(m, { op = "ready", seq = a.seq, at = a.at }); return true
	end
	if not matches(a, v) then return fail(m, "unexpected common sequence or stamp") end
	if v.op == "ready" and m.role == "host" then
		if a.phase == "prepared" then a.phase = "committed"; emit(m, { op = "commit", seq = a.seq, at = a.at }) end
		return true
	elseif v.op == "commit" and m.role == "client" then
		if a.phase == "prepared" then a.phase = "committed" end
		return true
	elseif v.op == "arrived" then
		a.peer_arrived = true; return true
	elseif v.op == "go" and m.role == "client" then
		if a.go then return true end
		if not a.arrived or a.phase ~= "committed" then return fail(m, "execution before common clock barrier") end
		a.go = true; return true
	elseif v.op == "done" then
		if v.ok ~= true then return fail(m, "partner rejected common command") end
		a.peer_done = true; return true
	elseif v.op == "release" and m.role == "client" then
		if not a.own_done or not a.peer_done then return fail(m, "common command released before both results") end
		if a.origin == "client" then m.pending_requests = math.max(0, (m.pending_requests or 0) - 1) end
		m.last, m.active = a.seq, nil; return true
	end
	return fail(m, "timeline message direction invalid")
end
function timeline.step(m, now, peer_now, options)
	options = options or {}
	if not integer(now) or now % timeline.STEP ~= 0 then return fail(m, "simulation clock is not on the 200 ms grid") end
	if m.gt and now < m.gt then return fail(m, "simulation clock moved backwards") end
	m.gt = now
	if m.error then return nil, m.error end
	if not m.active and m.role == "host" and #m.queue > 0 and integer(peer_now) and not options.dependencies then
		local v = table.remove(m.queue, 1)
		-- Vehicle commands need no four-second simulation lead. Paused games
		-- cannot advance to a future stamp; a large skew must not freeze building
		-- until the slower world catches up. In those cases both stop at their
		-- current tick and still require READY/COMMIT/ARRIVED/GO and both results.
		local barrier = v.barrier or options.paused or math.abs(now - peer_now) > timeline.MAX_SKEW
		barrier = barrier and true or nil
		local at = math.ceil((math.max(now, peer_now) + (barrier and 0 or timeline.LEAD)) / timeline.STEP) * timeline.STEP
		m.active = { seq = m.last + 1, at = at, line = v.line, origin = v.origin, id = v.id, barrier = barrier, phase = "prepared" }
		emit(m, { op = "plan", seq = m.active.seq, at = at, line = v.line, origin = v.origin, barrier = barrier })
	end
	local a = m.active
	if not a then return end
	if not a.executed and (a.barrier or now >= a.at) then
		if not a.arrived and a.phase == "committed" and options.stopped ~= false then
			a.arrived = true; emit(m, { op = "arrived", seq = a.seq, at = a.at })
		end
		if m.role == "host" and a.arrived and a.peer_arrived and a.phase == "committed" and not a.go then
			a.go = true; emit(m, { op = "go", seq = a.seq, at = a.at })
		end
		if a.go then
			a.executed, a.phase = true, "executing"
			return { seq = a.seq, at = a.at, line = a.line, origin = a.origin, gt = now, barrier = a.barrier }
		end
	end
	if m.role == "host" and a.own_done and a.peer_done then
		emit(m, { op = "release", seq = a.seq, at = a.at })
		m.last, m.active = a.seq, nil
		-- Reliable transport retains the release before the next plan. Retain only bounded history.
		if a.id then m.seen[a.id] = nil end
	end
end
function timeline.complete(m, seq, success)
	local a = m.active
	if not a or a.seq ~= seq or not a.executed then return fail(m, "result without common execution") end
	if success ~= true then return fail(m, "common command rejected locally") end
	if not a.own_done then
		a.own_done = true; emit(m, { op = "done", seq = a.seq, at = a.at, ok = true })
	end
	return true
end
function timeline.take(m) return table.remove(m.out, 1) end
function timeline.clock(m)
	local a = m.active
	return { gt = m.gt or 0, seq = a and a.seq or m.last, at = a and a.at or 0,
		-- A failure holds only a planned command; with nothing planned there is nothing to protect
		-- and a permanent pause would only stop both games (the failure is reported as health diff).
		hold = (a and (a.barrier or m.error or (m.gt and m.gt >= a.at))) and 1 or 0,
		barrier = a and a.barrier and 1 or 0,
		phase = m.error and "failed" or a and a.phase or "idle" }
end
function timeline.reject(m, reason) return fail(m, reason) end
--- The engine could not take the command yet (another replay still running): execute it again
-- on a later step; both games stay held at the barrier meanwhile.
function timeline.retry(m)
	local a = m.active
	if a and a.executed and not a.own_done then a.executed, a.phase = nil, "committed" end
end
return timeline

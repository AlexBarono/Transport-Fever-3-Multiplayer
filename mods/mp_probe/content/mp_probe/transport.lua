-- Bounded Lua/DLL chunks and persisted execution receipts. No globals or executable payloads.
local transport = { MAX_BYTES = 262144, CHUNK = 6000 }

function transport.send(line, s, log)
	assert(type(line) == "string" and #line <= transport.MAX_BYTES, "message exceeds 256 KiB")
	if #line <= transport.CHUNK then log("net send " .. line); return end
	s.transport_seq = (s.transport_seq or 0) + 1
	local count = math.ceil(#line / transport.CHUNK)
	for i = 0, count - 1 do
		log(string.format("net upload %d %d %d %s", s.transport_seq, i, count,
			line:sub(i * transport.CHUNK + 1, (i + 1) * transport.CHUNK)))
	end
end

function transport.receive(s, value, log)
	local token, kind, index, count, text = value:match("^part (%S+) (%a+) (%d+) (%d+) (.+)$")
	if not token then return value end
	index, count = tonumber(index), tonumber(count)
	if count < 1 or count > math.ceil(transport.MAX_BYTES / transport.CHUNK) or index >= count or
		#text > transport.CHUNK or (index < count - 1 and #text ~= transport.CHUNK) then return nil end
	local b = s.bridge_parts
	if not b or b.token ~= token then
		if index ~= 0 then return nil end
		b = { token = token, kind = kind, count = count, next = 0, parts = {} }; s.bridge_parts = b
	end
	if b.count ~= count or b.kind ~= kind or index > b.next then return nil end
	if index == b.next then b.parts[#b.parts + 1] = text; b.next = b.next + 1 end
	log("net partreceived " .. token .. " " .. index)
	if b.next ~= count then return nil end
	local line = table.concat(b.parts)
	if #line > transport.MAX_BYTES then return nil end
	-- Keep the assembly until a different token arrives: a lost stdout ACK must not rebuild it.
	return "line " .. token .. " " .. kind .. " " .. line
end

function transport.begin(state, token)
	local s = state:get() or {}
	if s.network_work then return s.network_work.token == token end
	s.network_work = { token = token, pending = 0, dispatched = false }
	state:set(s); return true
end

function transport.fail(state, message)
	if not state then return end
	local s = state:get() or {}
	if s.network_work then s.network_work.error = tostring(message):sub(1, 240); state:set(s) end
end

-- Wrap commands only in handleEvent, where TF3 permits callbacks. Counts asynchronous commands
-- and all follow-up settings; enqueueing or sending a command alone never means applied.
-- A callback may return true when it owns result validation and retry handling (build.replay).
-- Callback exceptions still fail the transaction, including for those managed results.
function transport.env(env, state)
	if not state or not (state:get() or {}).network_work then return env end
	local command_api = setmetatable({}, { __index = env.api.cmd })
	command_api.sendCommand = function(command, callback)
		local s = state:get() or {}; local work = s.network_work
		if not work then return env.api.cmd.sendCommand(command, callback) end
		local token = work.token
		local called = false
		work.pending = work.pending + 1; state:set(s)
		local function done(result, success)
			if called then return end
			called = true
			local ok, handled = pcall(function() if callback then return callback(result, success) end end)
			local critical = false
			pcall(function() critical = result.resultProposalData.errorState.critical == true end)
			local live = state:get() or {}; local active = live.network_work
			if active and active.token == token then
				active.pending = math.max(0, active.pending - 1)
				if not ok then active.error = tostring(handled)
				elseif handled ~= true and (success == false or critical) then active.error = "game command rejected" end
				state:set(live)
			end
		end
		local ok, err = pcall(env.api.cmd.sendCommand, command, done)
		if not ok then done(nil, false); error(err, 0) end
	end
	local api = setmetatable({ cmd = command_api }, { __index = env.api })
	return setmetatable({ api = api }, { __index = env })
end

function transport.dispatched(state)
	local s = state:get() or {}
	if s.network_work then s.network_work.dispatched = true; state:set(s) end
end

--- v37 (run 39): skip true (a session with a partner) reports a failed replay as done and logs it
-- as skipped. DLL v13 stops both games' queues for good on FAIL ("game rejected"), and the only way
-- out was reloading a 90 MB save; one line the host could not build stopped the whole session.
-- Now the session carries on; the world check shows whether the games really differ.
-- A failed S1 line (the common timeline itself, w.noskip) still reports FAIL: a stopped timeline
-- holds both games, and only the resync that the DLL's stop starts gets them going again.
function transport.check(state, log, skip)
	local s = state:get() or {}; local w = s.network_work
	if not w or not w.dispatched or w.pending > 0 or s.action_busy then return end
	if not w.error and (s.network_followup or (s.action_work and #s.action_work > 0) or (s.action_inbox and #s.action_inbox > 0) or
		(s.weld_checks and #s.weld_checks > 0)) then return end
	local skipped = w.error ~= nil and skip == true and not w.noskip
	local result = (w.error and not skipped) and "FAIL" or "OK"
	s.network_done = { token = w.token, result = result, skipped = skipped or nil }
	s.network_work = nil
	-- The later entrance checks belong to this replay; left over, they would fail the next one.
	if w.error then s.action_work, s.action_inbox, s.network_followup, s.weld_checks = nil, nil, nil, nil end
	if skipped then
		s.skipped = (s.skipped or 0) + 1
		s.last_skipped = { token = w.token, error = w.error:sub(1, 160) }
	end
	state:set(s)
	local reason = w.error and (" " .. w.error:gsub("[\r\n]", " ")) or ""
	if skipped then
		log("net skipped " .. w.token .. " (" .. s.skipped .. " so far), the session carries on:" .. reason)
		log("net result " .. w.token .. " OK")
	else
		log("net result " .. w.token .. " " .. result .. reason)
	end
end

function transport.action_log(state, log)
	return function(text)
		if text:find("failed", 1, true) or text:find("rejected", 1, true) or text:find("not copied yet", 1, true) then
			transport.fail(state, text)
		end
		log(text)
	end
end

return transport

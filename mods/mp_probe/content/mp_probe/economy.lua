--- Shared company names and subsidy decisions. The original TF3 script owns rewards.
local wire = require("/mp_probe/wire.lua")
local economy = { SCRIPT = "::/game_mechanics/subventions/subventions.gs", SOURCE = "mp_probe_economy" }

local function integer(v)
	return type(v) == "number" and v == v and math.abs(v) <= 9007199254740991 and v % 1 == 0
end

function economy.company_name(name)
	assert(type(name) == "string" and #name > 0 and #name <= 1024 and not name:find("[%z\1-\31\127]"), "invalid company name")
	return name
end

function economy.read(env)
	local engine, ct = env.api.engine, env.api.type.ComponentType
	local id = engine.system.gameScriptSystem.getEntityForGameScript(economy.SCRIPT)
	assert(integer(id) and id >= 0, "subvention script missing")
	local script = assert(engine.getComponent(id, assert(ct.GAME_SCRIPT)), "subvention script missing")
	local state = assert(script.state, "subvention state missing")
	assert(type(state.proposedSubventions) == "table", "subvention offers unreadable")
	return state
end

-- All offer terms and rewards travel; running counters do not identify the offer.
-- EntityAndRevision is a Lua struct containing an engine Revision userdata.
local function plain(v, depth)
	depth = (depth or 0) + 1; assert(depth <= 16, "subvention data nested too deep")
	if type(v) == "userdata" then
		local ok, t = pcall(function() return v:asTable() end)
		if ok and type(t) == "table" then return plain(t, depth) end
		local out = {}
		for _, key in ipairs({ "entity", "revision", "num" }) do
			local found, value = pcall(function() return v[key] end)
			if found and value ~= nil then out[key] = plain(value, depth) end
		end
		if next(out) then return out end
		local ok_n, n = pcall(function() return #v end)
		if ok_n and type(n) == "number" then
			for i = 1, n do out[i] = plain(v[i], depth) end; return out
		end
		error("subvention engine value unreadable", 0)
	end
	if type(v) ~= "table" then return v end
	local out = {}; for k, x in pairs(v) do out[k] = plain(x, depth) end; return out
end

function economy.offer(v)
	assert(type(v.id) == "string" and #v.id > 0 and integer(v.uid), "invalid subvention identity")
	assert(v.data, "subvention terms missing")
	local data = plain(v.data)
	data.delivered, data.affectedLines, data.lineEntity = nil, nil, nil
	return { id = v.id, uid = v.uid, spawnTime = v.spawnTime, data = wire.copy(data) }
end

local function terms(v)
	return wire.encode({ id = v.id, data = v.data })
end

local function instance(v)
	return wire.encode({ id = v.id, uid = v.uid, spawnTime = v.spawnTime, data = v.data })
end

local function matches(list, offer)
	local candidates, exact = {}, {}
	for _, v in ipairs(list or {}) do
		local local_offer = economy.offer(v)
		if terms(local_offer) == terms(offer) then
			candidates[#candidates + 1] = v
			if v.uid == offer.uid and v.spawnTime == offer.spawnTime then exact[#exact + 1] = v end
		end
	end
	if #exact == 1 then return exact[1] end
	assert(#exact < 2 and #candidates <= 1, "subvention offer ambiguous")
	return candidates[1]
end

function economy.prepare(env, param)
	assert(type(param) == "table", "economy command missing")
	if param.kind == "company" then
		return { op = "company_update", value = { name = economy.company_name(param.name), ref = { kind = "company", key = "player" } } }
	end
	assert(param.kind == "subvention" and (param.name == "onAccept" or param.name == "onDecline") and integer(param.uid), "invalid subvention decision")
	for _, v in ipairs(economy.read(env).proposedSubventions) do
		-- TF3 also uses the first matching uid, rather than the resource id.
		if v.uid == param.uid then return { op = "subvention_event", value = { name = param.name, offer = economy.offer(v) } } end
	end
	error("subvention offer not found or already decided", 0)
end

function economy.payout(offer)
	local total = 0
	for _, reward in ipairs(offer.data.upfront or {}) do
		if reward.type == "Money" then
			local amount = reward.params and reward.params.amount
			assert(integer(amount), "invalid subvention payout"); total = total + amount
		end
	end
	assert(integer(total), "invalid subvention payout"); return total
end

function economy.description(action)
	local v = action.value or {}
	if action.op == "company_update" then return "Unternehmen umbenennen: " .. tostring(v.name or "") end
	if action.op == "economy_error" then return tostring(v.label or "Unternehmen/Subvention") end
	if action.op == "subvention_event" then
		local offer = v.offer or {}; local data = offer.data or {}
		local label = "Subvention " .. (v.name == "onAccept" and "annehmen" or "ablehnen") .. ": " .. tostring(data.name or offer.id or "")
		if v.name == "onAccept" then label = label .. " (Auszahlung " .. tostring(economy.payout(offer)) .. ")" end
		return label
	end
end

local function receipt(state, offer, decision)
	local s = state:get() or {}; s.actions = s.actions or { snapshots = {}, queue = {}, errors = {} }
	local list = s.actions.subventions or {}; s.actions.subventions = list
	list[#list + 1] = { key = instance(offer), decision = decision }
	while #list > 128 do table.remove(list, 1) end
	state:set(s)
end

--- Returns a native command and a verification task, or nil for an idempotent repeat.
function economy.command(env, state, value)
	assert(value.name == "onAccept" or value.name == "onDecline", "invalid subvention decision")
	local offer = economy.offer(assert(value.offer, "subvention offer missing"))
	economy.payout(offer)
	local key = instance(offer)
	for _, r in ipairs(((state:get() or {}).actions or {}).subventions or {}) do
		if r.key == key then
			assert(r.decision == value.name, "subvention already decided differently")
			return nil
		end
	end
	local current = economy.read(env)
	-- Check the exact decided occurrence before any matching new proposal. An
	-- older repeated request must never accept a later offer with identical terms.
	for _, list in ipairs({ current.activeSubventions or {}, current.completedSubventions or {}, current.failedSubventions or {} }) do
		for _, v in ipairs(list) do
			if instance(economy.offer(v)) == key then
				assert(value.name == "onAccept", "subvention already accepted; cannot decline")
				receipt(state, offer, value.name); return nil
			end
		end
	end
	local proposed = matches(current.proposedSubventions, offer)
	if not proposed then
		error("subvention offer not found or terms/rewards differ; no payout booked", 0)
	end
	for _, v in ipairs(current.proposedSubventions) do
		if v.uid == proposed.uid then
			assert(instance(economy.offer(v)) == instance(economy.offer(proposed)), "subvention uid collision; no payout booked")
			break
		end
	end
	return env.api.cmd.makeScriptingSendEventCmd(economy.SOURCE, "Subvention", value.name, { uid = proposed.uid }),
		{ command = "verify_subvention", name = value.name, offer = offer, local_offer = economy.offer(proposed) }
end

function economy.verify(env, state, task)
	local current, key = economy.read(env), instance(task.local_offer)
	local present, accepted = false, false
	for _, v in ipairs(current.proposedSubventions) do if instance(economy.offer(v)) == key then present = true end end
	for _, list in ipairs({ current.activeSubventions or {}, current.completedSubventions or {}, current.failedSubventions or {} }) do
		for _, v in ipairs(list) do if instance(economy.offer(v)) == key then accepted = true end end
	end
	if present or (task.name == "onAccept" and not accepted) then return false end
	assert(task.name ~= "onDecline" or not accepted, "subvention was accepted instead of declined")
	receipt(state, task.offer, task.name); return true
end

return economy

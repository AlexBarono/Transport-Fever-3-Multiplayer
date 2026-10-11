--- Shared company names and subsidy decisions. The original TF3 script owns rewards.
local wire = require("/mp_probe/wire.lua")
local build = require("/mp_probe/build.lua")
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

-- Vanilla subsidy rewards, deadlines and spawn times are randomized separately.
-- Locate the actual target by component and position instead of comparing rewards.
local function component(env, id, kind)
	local ok, value = pcall(function() return env.api.engine.getComponent(id, env.api.type.ComponentType[kind]) end)
	return ok and value or nil
end

local function target_ref(env, id, kind)
	assert(component(env, id, kind), "subvention target missing: " .. kind)
	local bb = assert(component(env, id, "BOUNDING_VOLUME"), "subvention target position missing").bbox
	local p = {}; for _, axis in ipairs({ "x", "y", "z" }) do
		p[axis] = (bb.min[axis] + bb.max[axis]) / 2
		assert(type(p[axis]) == "number" and p[axis] == p[axis] and math.abs(p[axis]) < 1e8, "invalid subvention position")
	end
	local out = { kind = kind, position = p }
	-- Industry bounds change with fields and upgrades; their centre is not an
	-- identity. Keep the construction's fixed anchor and resource as well.
	if kind == "INDUSTRY" then
		local industry = component(env, id, kind)
		local c = component(env, industry.construction or id, "CONSTRUCTION")
		if c then
			local m = build.read_transf(c.transf)
			if m and type(c.fileName) == "string" then
				out.anchor = { x = m[13], y = m[14], z = m[15] }; out.fileName = c.fileName
			end
		end
	end
	return out
end

function economy.specific(env, offer)
	local d, kind = offer.data, offer.id:match("/subventions/(deliver_[^/]+)/")
	if kind == "deliver_workers" then return { target = target_ref(env, d.to.entity, "INDUSTRY") } end
	if kind == "deliver_passengers" then
		return { source = target_ref(env, d.from.entity, "TOWN"), target = target_ref(env, d.to.entity, "TOWN") }
	end
	if kind == "deliver_cargo_town" then
		assert(type(d.cargoType) == "string", "subvention cargo type missing")
		return { target = target_ref(env, d.townEntity.entity, "TOWN"), cargo = d.cargoType }
	end
	if kind == "deliver_cargo" then
		local industry
		env.api.engine.forEachEntityWithComponent(function(id)
			local v = component(env, id, "INDUSTRY")
			if v and v.stockList == d.stockListEntity.entity then assert(not industry, "ambiguous subsidy industry"); industry = id end
		end, env.api.type.ComponentType.INDUSTRY)
		return { target = target_ref(env, assert(industry, "subvention industry missing"), "INDUSTRY") }
	end
	error("unsupported subvention target", 0)
end

local function same_target(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or a.cargo ~= b.cargo then return false end
	for _, key in ipairs({ "target", "source" }) do
		local x, y = a[key], b[key]
		if (x == nil) ~= (y == nil) then return false end
		if x then
			if x.kind ~= y.kind then return false end
			local xp, yp = x.position, y.position
			if x.anchor and y.anchor then
				if x.fileName ~= y.fileName then return false end
				xp, yp = x.anchor, y.anchor
			end
			for _, axis in ipairs({ "x", "y", "z" }) do
				local p, q = xp[axis], yp[axis]
				assert(type(p) == "number" and p == p and math.abs(p) < 1e8 and type(q) == "number" and q == q and math.abs(q) < 1e8, "invalid subvention position")
				if math.abs(p - q) > 1 then return false end
			end
		end
	end
	return true
end

local function target_match(env, list, value)
	local found
	for _, v in ipairs(list or {}) do
		if v.id == value.offer.id then
			local ok, ref = pcall(economy.specific, env, v)
			if ok and same_target(ref, value.specific) then assert(not found, "subvention target ambiguous"); found = v end
		end
	end
	return found
end

local function resolve_target(env, ref)
	assert(ref and (ref.kind == "INDUSTRY" or ref.kind == "TOWN"), "invalid subvention target kind")
	local found
	env.api.engine.forEachEntityWithComponent(function(id)
		local ok, local_ref = pcall(target_ref, env, id, ref.kind)
		if ok and same_target({target=local_ref}, {target=ref}) then assert(not found, "subvention target ambiguous"); found = id end
	end, env.api.type.ComponentType[ref.kind])
	return assert(found, "subvention target missing on this PC; no payout booked")
end

function economy.prepare(env, param)
	assert(type(param) == "table", "economy command missing")
	if param.kind == "company" then
		return { op = "company_update", value = { name = economy.company_name(param.name), ref = { kind = "company", key = "player" } } }
	end
	assert(param.kind == "subvention" and (param.name == "onAccept" or param.name == "onDecline") and integer(param.uid), "invalid subvention decision")
	for _, v in ipairs(economy.read(env).proposedSubventions) do
		-- TF3 also uses the first matching uid, rather than the resource id.
		if v.uid == param.uid then
			local value = { name = param.name, offer = economy.offer(v) }
			local ok, ref = pcall(economy.specific, env, value.offer)
			if ok then value.specific = ref end
			return { op = "subvention_event", value = value }
		end
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

local function balance_key(offer)
	return (offer.id:match("/subventions/(deliver_[^/]+)/") or "subvention") .. "_" .. tostring(offer.uid) .. "_" .. tostring(offer.spawnTime or 0)
end

local function receipt(state, offer, decision)
	local s = state:get() or {}; s.actions = s.actions or { snapshots = {}, queue = {}, errors = {} }
	local list = s.actions.subventions or {}; s.actions.subventions = list
	list[#list + 1] = { key = instance(offer), decision = decision }
	while #list > 128 do table.remove(list, 1) end
	if decision == "onAccept" then s.actions.subvention_money = { key = balance_key(offer), settle = 3 } end
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
	local proposed = value.specific and target_match(env, current.proposedSubventions, value) or matches(current.proposedSubventions, offer)
	if not proposed then
		if value.specific then
			local active = target_match(env, current.activeSubventions, value)
			if active then
				assert(value.name == "onAccept", "subvention already accepted; cannot decline")
				receipt(state, offer, value.name); return nil
			end
			if value.name == "onDecline" then receipt(state, offer, value.name); return nil end
			local params = { target = resolve_target(env, value.specific.target), expireDurationProposed = -1 }
			if value.specific.source then params.source = resolve_target(env, value.specific.source) end
			if value.specific.cargo then
				params.cargoTypeId = env.api.res.cargoTypeRep.find(value.specific.cargo)
				assert(integer(params.cargoTypeId) and params.cargoTypeId >= 0, "subvention cargo unavailable")
			end
			-- Native onAccept looks up uid across all types. Pick a free uid, and
			-- respect the original script's history so a used uid cannot block spawn.
			local uid = offer.uid
			local used = {}; for _, list in ipairs({ current.proposedSubventions, current.activeSubventions or {}, current.completedSubventions or {}, current.failedSubventions or {} }) do
				for _, v in ipairs(list) do used[v.uid] = true end
			end
			for _, history in pairs(current.usedUids or {}) do for k in pairs(history) do if tonumber(k) then used[tonumber(k)] = true end end end
			while used[uid] do uid = uid + 1; assert(integer(uid), "subvention uid exhausted") end
			params.uid = uid
			return env.api.cmd.makeScriptingSendEventCmd(economy.SOURCE, "Subvention", "subventionSpawn", { name = offer.id, specific = params }),
				{ command = "accept_spawned_subvention", value = value, uid = uid }
		end
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
	receipt(state, task.offer, task.name)
	return true
end

function economy.spawn_ready(env, task)
	for _, v in ipairs(economy.read(env).proposedSubventions) do
		if v.uid == task.uid and v.id == task.value.offer.id then return true end
	end
	return false
end

return economy

-- Reproducible Lua-side cost probe; this does not estimate native engine enumeration latency.
-- python tools/run_lua.py tests/bench_world.lua
local original_require, loaded = require, {}
function require(path)
	if path:sub(1, 1) ~= "/" then return original_require(path) end
	if not loaded[path] then loaded[path] = assert(loadfile("mods/mp_probe/content" .. path))() end
	return loaded[path]
end
local fingerprint = require("/mp_probe/fingerprint.lua")
local function xyz(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
local function fixture(vehicles, cargos, towns)
	local ct, ids, entities = {}, {}, {}
	for _, k in ipairs({ "NAME", "COLOR", "PLAYER_OWNED", "CONSTRUCTION", "LINE", "TRANSPORT_VEHICLE",
		"BASE_EDGE", "GAME_TIME", "TOWN", "BOUNDING_VOLUME", "SIM_CARGO", "SIM_ENTITY_AT_VEHICLE" }) do ct[k], ids[k] = k, {} end
	local config = { vehicles = { { part = { modelId = 1, reversed = false, color = xyz(1, 0, 0),
		compartment2loadConfig = {} }, autoLoadConfig = {} } }, vehicleGroups = { 1 }, muFileNames = { "" } }
	for i = 1, vehicles do
		local id = 1000000 + i
		ids.TRANSPORT_VEHICLE[i] = id
		entities[id] = { NAME = { name = "Vehicle " .. i }, PLAYER_OWNED = { player = 7 },
			TRANSPORT_VEHICLE = { carrier = 2, line = -1, depot = -1, stopIndex = 0,
				transportVehicleConfig = config, userStopped = false, autoDeparture = true } }
	end
	for i = 1, towns do
		ids.TOWN[i] = i
		entities[i] = { NAME = { name = "Town " .. i },
			BOUNDING_VOLUME = { bbox = { min = xyz(i * 100, 0, 0), max = xyz(i * 100 + 10, 10, 2) } },
			TOWN = { initialLandUseCapacities = { 100, 50, 25 }, sizeFactors = { 1, 1, 1 },
				capacityScalingFactor = 1, developmentActive = true, cargoNeeds = { {}, {}, {} } } }
	end
	for i = 1, cargos do
		local id = 2000000 + i
		ids.SIM_CARGO[i] = id
		entities[id] = { SIM_CARGO = { cargoType = 1, sourceEntity = 1, targetOrPickupEntity = 1, startTime = 1000, pickupTime = 2000 } }
	end
	entities[9999999] = { GAME_TIME = { gameTime = 60000 } }
	local engine = { getComponent = function(id, c) return assert(entities[id], "missing entity")[c] end,
		getEntitiesWithComponent = function(c) return assert(ids[c]) end,
		util = { getPlayer = function() return 7 end, getWorld = function() return 9999999 end,
			vehicle = { getPosition = function(id) return xyz(id - 1000000, 20, 1) end, getSpeed = function() return 10 end },
			cargo = { getNumCargoPerTypeInVehicle = function() return { 0, 10 } end },
			town = { getTownCapacityUsage = function() return { { used = 42, capacity = 100 }, { used = 20, capacity = 50 }, { used = 10, capacity = 25 } } end,
				getTownStockCargo = function() return {} end } }, system = {} }
	return { api = { engine = engine, type = { ComponentType = ct }, res = {
		modelRep = { getName = function() return "::/train.mdl" end },
		cargoTypeRep = { getName = function() return "::/coal.cargo" end } } }, os = { clock = os.clock } }
end
for _, case in ipairs({ { "small", 20, 100, 10 }, { "medium", 200, 2000, 100 }, { "large", 10000, 100000, 1000 } }) do
	local env = fixture(case[2], case[3], case[4])
	local job = fingerprint.begin(env, 60000)
	local values, failed, stats
	repeat
		values, failed, stats = fingerprint.step(env, job)
		assert((job.stats.last_step_bytes or 0) <= fingerprint.HASH_BYTES_PER_STEP)
		assert((job.stats.last_step_records or 0) <= fingerprint.HASH_RECORDS_PER_STEP)
	until values
	print(string.format("%s vehicles=%d cargo=%d towns=%d capture=%.3fms max_hash_step=%.3fms calls=%d steps=%d unknown=%s detail=%s",
		case[1], case[2], case[3], case[4], stats.capture_ms, stats.max_step_ms or 0, stats.calls, stats.steps,
		#failed > 0 and table.concat(failed, ",") or "none",
		(function() local t = {} for _, f in ipairs(failed) do t[#t + 1] = f .. ":" .. tostring(stats[f]) end return table.concat(t, "; ") end)()))
end
print("Lua-side microbenchmark only; native batch enumeration is measured in-game and cannot be preempted by Lua.")

--- Additional actions, built against TF3's bundled api/tealdef declarations.
-- Effect snapshots capture UI operations without replacing any engine functions.
-- All persistent values live in script state (TF3 reloads modules between calls).
local wire = require("/mp_probe/wire.lua")
local build = require("/mp_probe/build.lua")
local actions = { VERSION = 1, KINDS = { "construction", "line", "vehicle", "edge" } }

local function field(obj, key)
	local ok, value = pcall(function() return obj[key] end)
	if ok then return value end
end

local function component(env, id, name)
	local ct = assert(env.api.type.ComponentType[name], "component type missing: " .. name)
	return assert(env.api.engine.getComponent(id, ct), name .. " missing for " .. tostring(id))
end

local function name_of(env, id)
	local ok, name = pcall(function() return component(env, id, "NAME").name end)
	return ok and name or ""
end

local function vec(v)
	return { x = assert(v.x), y = assert(v.y), z = assert(v.z) }
end

--- Turns engine values into plain Lua data. Run 14: not every TF3 userdata has asTable
-- ("unsupported wire value: userdata" for vehicles), so lists and vector structs are read by hand.
actions.STRUCT_FIELDS = { "x", "y", "z", "w", "loadConfigIndex", "cargoTypeId", "cargoEntry", "toHide",
	"cargoType", "amount", "loadConfigs", "loadConfig" }

local function to_plain(value, depth)
	depth = depth or 0
	if depth > 12 then error("value nested too deep", 0) end
	local t = type(value)
	if t ~= "userdata" and t ~= "table" then return value end
	if t == "userdata" then
		local ok, as = pcall(function() return value:asTable() end)
		if ok and type(as) == "table" then return to_plain(as, depth + 1) end
		local ok_n, n = pcall(function() return #value end)
		if ok_n and type(n) == "number" then
			local out = {}
			for i = 1, n do out[i] = to_plain(value[i], depth + 1) end
			return out
		end
		local out, any = {}, false
		-- Vectors and the structs vehicles carry (run 15: LoadConfig).
		for _, key in ipairs(actions.STRUCT_FIELDS) do
			local ok_k, v = pcall(function() return value[key] end)
			if ok_k and v ~= nil and type(v) ~= "function" then out[key], any = to_plain(v, depth + 1), true end
		end
		if any then return out end
		error("unreadable engine value " .. tostring(value):gsub("0x%x+", ""), 0)
	end
	local out = {}
	for k, v in pairs(value) do out[k] = to_plain(v, depth + 1) end
	return out
end

local function plain(value)
	return wire.copy(to_plain(value))
end

local function take(obj, keys)
	local out = {}
	for _, key in ipairs(keys) do
		local v = field(obj, key)
		if v ~= nil then out[key] = plain(v) end
	end
	return out
end

local function matrix(env, value)
	local out = {}
	-- Run 14: api.type.Mat4f.cols does not exist in TF3; build.read_transf knows what works.
	local m = build.read_transf(value)
	if m then
		for i = 1, 4 do
			local b = (i - 1) * 4
			out[i] = { x = m[b + 1], y = m[b + 2], z = m[b + 3], w = m[b + 4] }
		end
		return out
	end
	for i = 1, 4 do
		local c = env.api.type.Mat4f.cols(value, i)
		out[i] = { x = c.x, y = c.y, z = c.z, w = c.w }
	end
	return out
end

local function make_matrix(env, value, offset)
	local cols = {}
	for i = 1, 4 do
		local c = value[i]
		cols[i] = env.api.type.Vec4f.new(c.x, c.y + (i == 4 and offset or 0), c.z, c.w)
	end
	return env.api.type.Mat4f.new(cols[1], cols[2], cols[3], cols[4])
end

local function ids(env, kind)
	local e, ct = env.api.engine, env.api.type.ComponentType
	local out = {}
	if kind == "line" then
		out = e.system.lineSystem.getLines()
	elseif kind == "edge" then
		local seen = {}
		-- BASE_EDGE cannot be enumerated with forEachEntityWithComponent in TF3.
		for _, edges in pairs(e.system.streetSystem.getNode2SegmentMap()) do
			for _, id in ipairs(edges) do
				if not seen[id] then out[#out + 1], seen[id] = id, true end
			end
		end
	else
		local key = kind == "vehicle" and "TRANSPORT_VEHICLE" or "CONSTRUCTION"
		e.forEachEntityWithComponent(function(id) out[#out + 1] = id end, assert(ct[key]))
	end
	table.sort(out)
	return out
end

local function owned(env, id)
	local ct = assert(env.api.type.ComponentType.PLAYER_OWNED, "PLAYER_OWNED type missing")
	local owner = env.api.engine.getComponent(id, ct)
	return owner ~= nil and owner.player == env.api.engine.util.getPlayer()
end

local function construction_ref(env, id)
	local c = component(env, id, "CONSTRUCTION")
	return { kind = "construction", key = tostring(id), fileName = c.fileName,
		transf = matrix(env, c.transf) }
end

local function child_ref(env, id, kind)
	local connector = env.api.engine.system.streetConnectorSystem
	local parent = kind == "depot" and connector.getConstructionEntityForDepot(id)
		or connector.getConstructionEntityForStation(id)
	local c = component(env, parent, "CONSTRUCTION")
	local list = kind == "depot" and c.depots or c.stations
	for i = 1, #list do
		if list[i] == id then
			return { kind = kind, parent = construction_ref(env, parent), index = i }
		end
	end
	error("no " .. kind .. " index in construction")
end

local function edge_ref(env, id)
	local c = component(env, id, "BASE_EDGE")
	return { kind = "edge", key = tostring(id), position0 = vec(c.position0), position1 = vec(c.position1),
		tangent0 = vec(c.tangent0), tangent1 = vec(c.tangent1), roadTemplate = c.roadTemplate,
		roadStyle = c.roadStyle }
end

local function named_ref(env, id, kind)
	return { kind = kind, key = tostring(id), name = name_of(env, id) }
end

local function stop_ref(env, stop)
	local group = component(env, stop.stationGroup, "STATION_GROUP")
	local group_stations = {}
	for i = 1, #group.stations do group_stations[i] = child_ref(env, group.stations[i], "station") end
	return { stations = group_stations, station = stop.station }
end

local STOP_FIELDS = { "terminal", "loadMode", "minWaitingTime", "maxWaitingTime", "maxAdditionalWaitingTime" }
local CONFIG_FIELDS = { "load", "maxLoad", "forceUnload", "destroyForConfigChange", "destroyForRefresh" }

local function line_data(env, id)
	local l = component(env, id, "LINE")
	local out = take(l, { "customFilters", "reservationPriority" })
	out.stops = {}
	for i = 1, #l.stops do
		local s = l.stops[i]
		local entry = take(s, STOP_FIELDS)
		entry.target = stop_ref(env, s)
		entry.stopConfig = take(s.stopConfig, CONFIG_FIELDS)
		entry.alternativeTerminals = {}
		for j = 1, #s.alternativeTerminals do
			local t = s.alternativeTerminals[j]
			entry.alternativeTerminals[j] = { station = t.station, terminal = t.terminal }
		end
		-- Preserve geographic waypoints. Edge waypoints need the local base-edge id.
		entry.waypoints = {}
		for j = 1, #s.waypoints do
			local w = s.waypoints[j]
			local eid = field(field(w, "edgePos"), "edgeId")
			if eid and eid.entity >= 0 then
				entry.waypoints[j] = { edge = edge_ref(env, eid.entity), index = eid.index,
					param = w.edgePos.param, tag = w.tag }
			else entry.waypoints[j] = { pos = vec(w.pos), tag = w.tag } end
		end
		out.stops[i] = entry
	end
	out.vehicleInfo = { transportModes = plain(l.vehicleInfo.transportModes) }
	return out
end

local function vehicle_config(env, config)
	local out = { vehicles = {}, vehicleGroups = plain(config.vehicleGroups), muFileNames = plain(config.muFileNames) }
	for i = 1, #config.vehicles do
		local v, part = config.vehicles[i], config.vehicles[i].part
		local model = env.api.res.modelRep.getName(part.modelId)
		assert(type(model) == "string" and #model > 0, "vehicle model name missing")
		out.vehicles[i] = { model = model, reversed = part.reversed,
			compartment2loadConfig = plain(part.compartment2loadConfig), color = vec(part.color),
			autoLoadConfig = plain(v.autoLoadConfig) }
	end
	return out
end

local function record(env, id, kind)
	if not owned(env, id) then return nil end
	if kind == "construction" then
		local c = component(env, id, "CONSTRUCTION")
		local params = field(c, "params_native")
		params = params and to_plain(params) or c.params
		-- Include ALL parameters, including modular stations' modules/seed/year.
		return { ref = construction_ref(env, id), data = { fileName = c.fileName,
			params = plain(params), transf = matrix(env, c.transf), name = name_of(env, id) } }
	elseif kind == "line" then
		return { ref = named_ref(env, id, kind), data = line_data(env, id), name = name_of(env, id),
			color = vec(component(env, id, "COLOR").color) }
	elseif kind == "vehicle" then
		local v = component(env, id, "TRANSPORT_VEHICLE")
		local out = { ref = named_ref(env, id, kind), config = vehicle_config(env, v.transportVehicleConfig),
			name = name_of(env, id), userStopped = v.userStopped, autoDeparture = v.autoDeparture }
		if v.depot and v.depot >= 0 then out.depot = child_ref(env, v.depot, "depot") end
		if v.line and v.line >= 0 then out.line = named_ref(env, v.line, "line") end
		return out
	elseif kind == "edge" then
		local parent = env.api.engine.system.streetConnectorSystem.getConstructionEntityForEdge(id)
		if parent and parent >= 0 then return nil end -- Construction internals are removed as a whole.
		return { ref = edge_ref(env, id) }
	end
end

function actions.snapshot(env, kind)
	local out = {}
	for _, id in ipairs(ids(env, kind)) do
		local r = record(env, id, kind)
		if r then out[tostring(id)] = r end
	end
	return out
end

function actions.encode(action)
	assert(type(action) == "table" and type(action.op) == "string", "invalid action")
	return "A1 " .. wire.encode(action)
end

function actions.decode(line)
	if type(line) ~= "string" or line:sub(1, 3) ~= "A1 " then return nil, "unsupported action version" end
	local a, err = wire.decode(line:sub(4))
	if type(a) ~= "table" or type(a.op) ~= "string" then return nil, err or "invalid action" end
	return a
end

local function same(a, b) return wire.encode(a) == wire.encode(b) end

local function changed(kind, r, old)
	if kind == "vehicle" then
		-- Depot presence and stopIndex change during ordinary travel, not just UI actions.
		return r.name ~= old.name or r.userStopped ~= old.userStopped or r.autoDeparture ~= old.autoDeparture
			or not same(r.config, old.config) or not same(r.line or {}, old.line or {})
	end
	return not same(r, old)
end

--- Diffs each category independently. A failed read never masquerades as demolition/sale.
-- First successful snapshot is only a baseline; loading a save sends nothing.
function actions.poll(env, s, log, kinds)
	s.actions = s.actions or { snapshots = {}, queue = {}, errors = {} }
	local a = s.actions
	local pending = {}
	for _, kind in ipairs(kinds or actions.KINDS) do
		local ok, current = pcall(actions.snapshot, env, kind)
		if ok then
			local previous = a.snapshots[kind]
			if previous then
				local staged = {}
				local success, err = pcall(function()
					local replaced = {}
					local edge_additions = false
					if kind == "edge" then
						for key in pairs(current) do if not previous[key] then edge_additions = true end end
					end
					for _, key in ipairs((function()
						local keys = {}; for k in pairs(current) do keys[#keys + 1] = k end
						table.sort(keys); return keys
					end)()) do
						local r, old = current[key], previous[key]
						-- Modular upgrades can replace the construction with a new entity id.
						if kind == "construction" and not old then
							local matches = {}
							for old_key, candidate in pairs(previous) do
								if not current[old_key] and not replaced[old_key] and same(candidate.ref.transf, r.ref.transf) then
									matches[#matches + 1] = old_key
								end
							end
							if #matches == 1 then old = previous[matches[1]]; replaced[matches[1]] = true end
						end
						if kind ~= "edge" and (not old or changed(kind, r, old)) then
							local op = kind .. (old and "_update" or "_create")
							if kind == "vehicle" and not old then
								assert(r.depot, "new vehicle left depot before capture; buy cannot be reconstructed")
							end
							staged[#staged + 1] = actions.encode({ op = op, target = old and old.ref or r.ref, value = r,
								previous = kind == "vehicle" and old or nil })
						end
					end
					local removed = {}
					for key, old in pairs(previous) do
						if not current[key] and not replaced[key] then removed[#removed + 1] = old.ref end
					end
					if kind == "edge" and edge_additions and #removed > 0 then
						-- Splitting/upgrading a road also removes old edges. Sending only that
						-- half would destroy the other world's road; mixed edits need B3 support.
						if log then log("action edge removal skipped: street graph also added edges (mixed edit)") end
						removed = {}
					end
					if #removed > 0 then
						table.sort(removed, function(x, y) return x.key < y.key end)
						staged[#staged + 1] = actions.encode({ op = kind .. "_remove", targets = removed })
					end
				end)
				if success then
					for _, line in ipairs(staged) do pending[#pending + 1] = line end
				else
					ok, current = false, err
				end
			end
			if ok then a.snapshots[kind], a.errors[kind] = current, nil end
		end
		if not ok and a.errors[kind] ~= tostring(current) then
			a.errors[kind] = tostring(current)
			if log then log("action capture " .. kind .. " failed: " .. tostring(current):sub(1, 220)) end
		end
	end
	local priority = { construction_create = 1, construction_update = 1,
		line_create = 2, line_update = 2, vehicle_create = 3, vehicle_update = 3,
		vehicle_remove = 4, line_remove = 5, edge_remove = 6, construction_remove = 7 }
	-- Create dependencies first, remove dependents first; retain prior polls' FIFO order.
	local ordered = {}
	for i, line in ipairs(pending) do ordered[i] = { line = line, index = i, rank = priority[actions.decode(line).op] } end
	table.sort(ordered, function(x, y) return x.rank == y.rank and x.index < y.index or x.rank < y.rank end)
	for _, entry in ipairs(ordered) do a.queue[#a.queue + 1] = entry.line end
end

--- Throttle new action lines so the DLL's eight-entry outbox is not flooded by a snapshot.
function actions.next_line(s)
	if s.actions and #s.actions.queue > 0 then return table.remove(s.actions.queue, 1) end
end

local function near(a, b, offset)
	return math.abs(a.x - b.x) < 0.05 and math.abs(a.y - b.y - offset) < 0.05
		and math.abs(a.z - b.z) < 0.05
end

local function map_key(peer, ref) return peer .. ":" .. ref.kind .. ":" .. ref.key end

local function unique(list, label)
	assert(#list == 1, label .. (#list == 0 and " not found" or " is ambiguous"))
	return list[1]
end

local function resolve(env, ref, s, peer, offset)
	assert(type(ref) == "table", "missing entity reference")
	local maps = s.action_entities or {}
	if ref.key then
		local mapped = maps[map_key(peer, ref)]
		if mapped then
			local key = ({ construction = "CONSTRUCTION", line = "LINE", vehicle = "TRANSPORT_VEHICLE", edge = "BASE_EDGE" })[ref.kind]
			component(env, mapped, assert(key, "unknown reference kind"))
			assert(owned(env, mapped), "mapped target no longer owned by local player")
			return mapped
		end
	end
	if ref.kind == "depot" or ref.kind == "station" then
		local parent = resolve(env, ref.parent, s, peer, offset)
		local c = component(env, parent, "CONSTRUCTION")
		local list = ref.kind == "depot" and c.depots or c.stations
		return assert(list[ref.index], "construction child index missing")
	end
	local matches = {}
	for _, id in ipairs(ids(env, ref.kind)) do
		if owned(env, id) then
			local found = false
			if ref.kind == "construction" then
				local c = component(env, id, "CONSTRUCTION")
				local tr = matrix(env, c.transf)
				found = c.fileName == ref.fileName and near(tr[4], ref.transf[4], offset)
				for i = 1, 3 do
					found = found and near(tr[i], ref.transf[i], 0) and math.abs(tr[i].w - ref.transf[i].w) < 0.05
				end
			elseif ref.kind == "edge" then
				local e = component(env, id, "BASE_EDGE")
				local shift = offset ~= 0 and s.edge_loop_offsets and s.edge_loop_offsets[ref.key]
				local dx, dy = shift and shift.x or 0, shift and shift.y or offset
				local p0, p1 = vec(e.position0), vec(e.position1)
				p0.x, p1.x = p0.x - dx, p1.x - dx
				found = e.roadTemplate == ref.roadTemplate and e.roadStyle == ref.roadStyle
					and near(p0, ref.position0, dy) and near(p1, ref.position1, dy)
					and near(vec(e.tangent0), ref.tangent0, 0) and near(vec(e.tangent1), ref.tangent1, 0)
			else found = name_of(env, id) == ref.name end
			if found then matches[#matches + 1] = id end
		end
	end
	return unique(matches, ref.kind .. " reference")
end

actions.resolve = resolve

local function put_fields(obj, values)
	for k, v in pairs(values) do obj[k] = v end
	return obj
end

local function line_type(env, name)
	return assert(env.api.type.Line[name], "Line." .. name .. " type missing")
end

local function make_line(env, value, s, peer, offset)
	local line = env.api.type.Line.new()
	put_fields(line, take(value, { "customFilters", "reservationPriority" }))
	local stops = {}
	for i, entry in ipairs(value.stops) do
		local station_ids = {}
		for j, ref in ipairs(entry.target.stations) do station_ids[j] = resolve(env, ref, s, peer, offset) end
		local group_id = env.api.engine.system.stationGroupSystem.getStationGroup(station_ids[1])
		local group = component(env, group_id, "STATION_GROUP")
		assert(#group.stations == #station_ids, "station grouping differs")
		local indexes = {}
		for j, id in ipairs(station_ids) do
			for k = 1, #group.stations do if group.stations[k] == id then indexes[j - 1] = k - 1 end end
			assert(indexes[j - 1], "station missing from destination group")
		end
		local stop = line_type(env, "Stop").new()
		put_fields(stop, take(entry, STOP_FIELDS))
		stop.stationGroup, stop.station = group_id, assert(indexes[entry.target.station], "invalid station index")
		stop.stopConfig = put_fields(line_type(env, "StopConfig").new(), entry.stopConfig)
		local alternatives = {}
		for j, alt in ipairs(entry.alternativeTerminals) do
			alternatives[j] = env.api.type.StationTerminal.new(assert(indexes[alt.station]), alt.terminal)
		end
		stop.alternativeTerminals = alternatives
		local waypoints = {}
		for j, w in ipairs(entry.waypoints) do
			local waypoint = env.api.type.Waypoint.new()
			waypoint.tag = w.tag
			if w.edge then
				local ep, ei = env.api.type.EdgePos.new(), env.api.type.EdgeId.new()
				ei.entity, ei.index = resolve(env, w.edge, s, peer, offset), w.index
				ep.edgeId, ep.param = ei, w.param
				waypoint.edgePos = ep
			else waypoint.pos = env.api.type.Vec3f.new(w.pos.x, w.pos.y + offset, w.pos.z) end
			waypoints[j] = waypoint
		end
		stop.waypoints = waypoints
		stops[i] = stop
	end
	line.stops = stops
	local info = env.api.type.LineVehicleInfo.new()
	info.transportModes = value.vehicleInfo.transportModes
	line.vehicleInfo = info
	return line
end

local function make_vehicle(env, value)
	local config = env.api.type.TransportVehicleConfig.new()
	local vehicles = {}
	for i, v in ipairs(value.vehicles) do
		local model_id = env.api.res.modelRep.find(v.model)
		assert(model_id and model_id >= 0, "vehicle model missing: " .. v.model)
		local part = env.api.type.VehiclePart.new()
		part.modelId, part.reversed = model_id, v.reversed
		part.compartment2loadConfig = v.compartment2loadConfig
		part.color = env.api.type.Vec3f.new(v.color.x, v.color.y, v.color.z)
		local tv = env.api.type.TransportVehiclePart.new()
		tv.part, tv.autoLoadConfig = part, v.autoLoadConfig
		vehicles[i] = tv
	end
	config.vehicles, config.vehicleGroups, config.muFileNames = vehicles, value.vehicleGroups, value.muFileNames
	return config
end

local function result_id(result, key)
	local id = field(result, key)
	if type(id) == "number" and id >= 0 then return id end
	local entities = field(result, "resultEntities")
	if entities and #entities == 1 then
		id = entities[1]
		id = type(id) == "number" and id or field(id, 1)
		if type(id) == "number" and id >= 0 then return id end
	end
	return nil
end

local function enqueue(state, work)
	local s = state:get() or {}
	s.action_work = s.action_work or {}
	for _, entry in ipairs(work) do s.action_work[#s.action_work + 1] = entry end
	state:set(s)
end

local function refresh(env, state, peer, kind, id, ref, remove)
	local live = state:get() or {}
	live.action_entities = live.action_entities or {}
	if ref and not remove then live.action_entities[map_key(peer, ref)] = id end
	if remove then
		for key, local_id in pairs(live.action_entities) do
			if local_id == id then live.action_entities[key] = nil end
		end
	end
	local snapshots = live.actions and live.actions.snapshots
	if snapshots and snapshots[kind] then
		if remove then snapshots[kind][tostring(id)] = nil
		else snapshots[kind][tostring(id)] = record(env, id, kind) end
	end
	state:set(live)
end

local function busy(state, value)
	local s = state:get() or {}; s.action_busy = value; state:set(s)
end

--- Incoming actions wait behind settings of an earlier action, even with async callbacks.
function actions.receive(state, action, peer, offset)
	local s = state:get() or {}
	s.action_inbox = s.action_inbox or {}
	s.action_inbox[#s.action_inbox + 1] = { action = action, peer = peer, offset = offset }
	state:set(s)
end

function actions.has_work(s)
	return not s.action_busy and ((s.action_work and #s.action_work > 0) or (s.action_inbox and #s.action_inbox > 0))
end

function actions.tick(env, state, log)
	local s = state:get() or {}
	if s.action_busy then return end
	if s.action_work and #s.action_work > 0 then return actions.continue(env, state, log) end
	local task = s.action_inbox and table.remove(s.action_inbox, 1)
	state:set(s)
	if task then return actions.replay(env, task.action, state, task.peer, task.offset, log) end
end

--- Runs exactly one persisted follow-up command in a new simulation event.
-- In TF3 sendCommand can call back synchronously. Never send a command from that callback.
function actions.continue(env, state, log)
	log = log or function() end
	local s = state:get() or {}
	local task = s.action_work and table.remove(s.action_work, 1)
	state:set(s)
	if not task then return end
	local cmd, id, value = env.api.cmd, task.id, task.value
	component(env, id, task.kind == "line" and "LINE" or "TRANSPORT_VEHICLE")
	assert(owned(env, id), "follow-up target no longer owned by local player")
	local command
	if task.command == "name" then command = cmd.makeEntitySetNameCmd(id, value)
	elseif task.command == "color" then command = cmd.makeEntitySetColorCmd(id, env.api.type.Vec3f.new(value.x, value.y, value.z))
	elseif task.command == "line" then command = cmd.makeVehicleSetLineCmd(id, value, 0)
	elseif task.command == "stopped" then command = cmd.makeVehicleSetStoppedByUserCmd(id, value)
	elseif task.command == "manual" then command = cmd.makeVehicleSetManualDepartureCmd(id, value)
	elseif task.command == "remove_line" then command = cmd.makeLineDestroyCmd(id)
	else error("unknown local continuation") end
	busy(state, true)
	local sent, send_error = pcall(cmd.sendCommand, command, function(_, success)
		busy(state, false)
		if success == false then
			-- Discard this entity's remaining settings rather than pretending the chain succeeded.
			local live = state:get() or {}
			local remaining = {}
			for _, entry in ipairs(live.action_work or {}) do
				if entry.id ~= id or entry.kind ~= task.kind then remaining[#remaining + 1] = entry end
			end
			live.action_work = remaining; state:set(live)
			log("action continuation " .. task.command .. " rejected by game")
			return
		end
		local ok, err = pcall(refresh, env, state, task.peer, task.kind, id, task.ref, task.command == "remove_line")
		log(ok and ("action continuation " .. task.command .. " applied") or ("action continuation result failed: " .. tostring(err)))
	end)
	if not sent then busy(state, false); error(send_error) end
end

--- Execute in handleEvent's simulation state. Never pass a source game's id to api.cmd.
function actions.replay(env, action, state, peer, offset, log)
	assert(state and peer, "action replay needs script state and peer")
	offset = offset or 0
	log = log or function() end
	local s = state:get() or {}
	local cmd, value, op = env.api.cmd, action.value, action.op
	local function updated(kind, id, ref, remove) refresh(env, state, peer, kind, id, ref, remove) end
	local function send(command, done)
		busy(state, true)
		local sent, send_error = pcall(cmd.sendCommand, command, function(result, success)
			busy(state, false)
			local errors = field(field(result, "resultProposalData"), "errorState")
			if success == false or (errors and field(errors, "critical") == true) then
				log("action " .. op .. " rejected by game")
				return
			end
			local ok, err = pcall(function() if done then done(result) end end)
			if not ok then log("action " .. op .. " result failed: " .. tostring(err):sub(1, 220))
			else log("action " .. op .. " applied") end
		end)
		if not sent then busy(state, false); error(send_error) end
	end
	local function world(proposal, done)
		local context = build.make_context(env, env.api.engine.util.getPlayer())
		-- playerInitiated=false prevents onPostBuildProposal from sending the copy back.
		send(cmd.makeWorldBuildProposalCmd(proposal, context, false, false), done)
	end
	local function vehicle_settings(id, r, old)
		local work = {}
		local function add(command, value)
			work[#work + 1] = { command = command, value = value, id = id, kind = "vehicle", peer = peer, ref = r.ref }
		end
		if not old or r.name ~= old.name then add("name", r.name) end
		if not old or not same(r.line or {}, old.line or {}) then
			local line = r.line and resolve(env, r.line, state:get() or {}, peer, offset) or -1
			add("line", line)
		end
		if not old or r.userStopped ~= old.userStopped then
			add("stopped", r.userStopped)
		end
		if not old or r.autoDeparture ~= old.autoDeparture then
			add("manual", not r.autoDeparture)
		end
		enqueue(state, work)
	end
	if op == "construction_create" or op == "construction_update" then
		local p = env.api.type.SimpleProposal.new()
		local c = env.api.type.SimpleProposal.ConstructionEntity.new()
		c.fileName, c.params = value.data.fileName, value.data.params
		c.transf, c.name = make_matrix(env, value.data.transf, offset), value.data.name
		c.playerEntity, c.autoFillSlots = env.api.engine.util.getPlayer(), false
		p.constructionsToAdd = { c }
		local old
		if op == "construction_update" then
			old = resolve(env, action.target, s, peer, offset)
			p.constructionsToRemove, p.old2new = { old }, { [old] = 0 }
		end
		world(p, function(result)
			local id = assert(result_id(result), "construction result id missing")
			if old then updated("construction", old, nil, true) end
			updated("construction", id, value.ref)
		end)
	elseif op == "line_create" or op == "line_update" then
		local l = make_line(env, value.data, s, peer, offset)
		if op == "line_create" then
			local color = env.api.type.Vec3f.new(value.color.x, value.color.y, value.color.z)
			send(cmd.makeLineCreateCmd(value.name, color, env.api.engine.util.getPlayer(), l), function(result)
				updated("line", assert(result_id(result, "resultEntity"), "line result id missing"), value.ref)
			end)
		else
			local id = resolve(env, action.target, s, peer, offset)
			send(cmd.makeLineUpdateCmd(id, l), function()
				updated("line", id, value.ref)
				enqueue(state, {
					{ command = "name", value = value.name, id = id, kind = "line", peer = peer, ref = value.ref },
					{ command = "color", value = value.color, id = id, kind = "line", peer = peer, ref = value.ref },
				})
			end)
		end
	elseif op == "vehicle_create" then
		local depot = resolve(env, assert(value.depot, "buy needs depot"), s, peer, offset)
		-- Validate line dependencies before purchasing, avoiding a half-applied action.
		if value.line then resolve(env, value.line, s, peer, offset) end
		send(cmd.makeVehicleBuyCmd(env.api.engine.util.getPlayer(), depot, make_vehicle(env, value.config)), function(result)
			local id = assert(result_id(result, "resultVehicleEntity"), "vehicle result id missing")
			updated("vehicle", id, value.ref)
			vehicle_settings(id, value)
		end)
	elseif op == "vehicle_update" then
		local id = resolve(env, action.target, s, peer, offset)
		if value.line then resolve(env, value.line, s, peer, offset) end
		if not same(value.config, action.previous.config) then
			send(cmd.makeVehicleReplaceCmd(id, make_vehicle(env, value.config)), function()
				updated("vehicle", id, value.ref)
				vehicle_settings(id, value, action.previous)
			end)
		else vehicle_settings(id, value, action.previous) end
	elseif op == "construction_remove" or op == "edge_remove" or op == "line_remove" or op == "vehicle_remove" then
		local kind = op:match("^(%a+)_")
		local targets = {}
		-- Resolve ALL targets before issuing a destructive command.
		for i, ref in ipairs(action.targets) do targets[i] = resolve(env, ref, s, peer, offset) end
		assert(#targets > 0, "empty removal")
		local function removed()
			for i, id in ipairs(targets) do updated(kind, id, action.targets[i], true) end
		end
		if kind == "construction" or kind == "edge" then
			local p = env.api.type.SimpleProposal.new()
			if kind == "construction" then p.constructionsToRemove = targets
			else local sp = p.streetProposal; sp.edgesToRemove = targets; p.streetProposal = sp end
			world(p, removed)
		elseif kind == "vehicle" then send(cmd.makeVehicleSellCmd(targets), removed)
		else
			local work = {}
			for i, id in ipairs(targets) do
				work[i] = { command = "remove_line", id = id, kind = "line", peer = peer, ref = action.targets[i] }
			end
			enqueue(state, work)
		end
	else error("unsupported action: " .. tostring(op)) end
	return true
end

return actions

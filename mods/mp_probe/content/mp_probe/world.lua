--- Lookups in the running game: existing nodes, edges and constructions by position.
-- Entity ids differ between two games, so a line names existing things by where they are; these
-- functions turn such a position back into this game's entity. Every engine call is guarded,
-- because the TF3 API is only partly known (see docs/tf2mp-reference.md and docs/phase1-bridge.md).
-- @module mp_probe.world
local build = require("/mp_probe/build.lua")

local world = {}

--- Horizontal search radius for an existing node (TF2 multiplayer mod: 1.5 m).
world.NODE_RADIUS = 1.5
--- Search radius for a construction of the same file (TF2 multiplayer mod: 2 m).
world.CONSTRUCTION_RADIUS = 2

local function component(env, id, name)
	local ok, value = pcall(function()
		return env.api.engine.getComponent(id, env.api.type.ComponentType[name])
	end)
	if ok then return value end
	return nil
end

--- Calls fn(id) for every entity with the component `name`. TF3 refuses some component types in
-- forEachEntityWithComponent ("Cannot loop over this component type", run 13: BASE_NODE), so the
-- list function is tried next.
local function each_with(env, name, fn)
	local engine = env.api.engine
	local ct = env.api.type.ComponentType[name]
	local errors = {}
	if engine.forEachEntityWithComponent then
		local list = {}
		local ok, err = pcall(engine.forEachEntityWithComponent, function(id) list[#list + 1] = id end, ct)
		if ok then
			for i = 1, #list do fn(list[i]) end
			return
		end
		errors[#errors + 1] = tostring(err)
	end
	local ok, ids = pcall(engine.getEntitiesWithComponent, ct)
	if ok and type(ids) == "table" then
		for i = 1, #ids do fn(ids[i]) end
		return
	end
	errors[#errors + 1] = tostring(ids)
	error("cannot list " .. name .. ": " .. table.concat(errors, " / "), 0)
end

--- Node ids from the street system's node-to-segment map (BASE_NODE cannot be looped over).
local function each_node(env, fn)
	local ok, map = pcall(function() return env.api.engine.system.streetSystem.getNode2SegmentMap() end)
	if ok and map ~= nil then
		local found = 0
		local ok_pairs = pcall(function()
			for id in pairs(map) do
				found = found + 1
				fn(id)
			end
		end)
		if ok_pairs and found > 0 then return end
	end
	each_with(env, "BASE_NODE", fn)
end

--- Edge ids from the street system's node-to-segment map (BASE_EDGE cannot be looped over).
local function each_edge(env, fn)
	local seen = {}
	local ok, map = pcall(function() return env.api.engine.system.streetSystem.getNode2SegmentMap() end)
	if ok and map ~= nil then
		local ok_pairs = pcall(function()
			for _, edges in pairs(map) do
				for i = 1, #edges do
					local id = edges[i]
					if not seen[id] then
						seen[id] = true
						fn(id)
					end
				end
			end
		end)
		if ok_pairs and next(seen) then return end
	end
	each_with(env, "BASE_EDGE", function(id)
		if not seen[id] then fn(id) end
	end)
end

world.each_with = each_with
world.each_node = each_node
world.each_edge = each_edge

--- Position of a node entity as a plain table, or nil.
function world.node_position(env, id)
	local node = component(env, id, "BASE_NODE")
	if not node then return nil end
	local ok, p = pcall(function()
		local v = node.position
		return { x = v.x, y = v.y, z = v.z }
	end)
	return ok and p or nil
end

--- See build.read_transf.
world.read_transf = build.read_transf

--- Index of all nodes for repeated searches within one replay. Built on first use.
function world.node_index(env)
	local index = { cells = {}, size = 16 }
	each_node(env, function(id)
		local p = world.node_position(env, id)
		if p then
			local key = math.floor(p.x / index.size) .. ":" .. math.floor(p.y / index.size)
			local cell = index.cells[key]
			if not cell then
				cell = {}
				index.cells[key] = cell
			end
			cell[#cell + 1] = { id = id, p = p }
		end
	end)
	return index
end

--- The node closest to `pos` within `radius` metres (horizontally), or nil. With several close
-- candidates the one nearest in height wins as tie breaker (bridges over roads).
function world.find_node(index, pos, radius)
	radius = radius or world.NODE_RADIUS
	local best, best_d = nil, nil
	local cx, cy = math.floor(pos.x / index.size), math.floor(pos.y / index.size)
	for x = cx - 1, cx + 1 do
		for y = cy - 1, cy + 1 do
			for _, n in ipairs(index.cells[x .. ":" .. y] or {}) do
				local dx, dy = n.p.x - pos.x, n.p.y - pos.y
				local d2 = dx * dx + dy * dy
				if d2 <= radius * radius then
					local d = d2 + (n.p.z - pos.z) * (n.p.z - pos.z) * 0.01
					if not best_d or d < best_d then best, best_d = n.id, d end
				end
			end
		end
	end
	return best
end

--- Edge entity joining nodes a and b (either direction), or nil.
function world.find_edge(env, a, b)
	local found = nil
	local ok_sys, list = pcall(function() return env.api.engine.system.streetSystem.getNodeSegments(a) end)
	if ok_sys and list ~= nil then
		local ok_n, n = pcall(function() return #list end)
		for i = 1, (ok_n and n or 0) do
			local edge = component(env, list[i], "BASE_EDGE")
			if edge and ((edge.node0 == a and edge.node1 == b) or (edge.node0 == b and edge.node1 == a)) then
				return list[i]
			end
		end
	end
	-- Fallback: look at every edge once.
	pcall(each_edge, env, function(id)
		if found then return end
		local edge = component(env, id, "BASE_EDGE")
		if edge and ((edge.node0 == a and edge.node1 == b) or (edge.node0 == b and edge.node1 == a)) then
			found = id
		end
	end)
	return found
end

--- File name and position of a construction entity, or nil.
function world.construction_info(env, id)
	local con = component(env, id, "CONSTRUCTION")
	if not con then return nil end
	local ok, file = pcall(function() return con.fileName end)
	local m = nil
	pcall(function() m = world.read_transf(con.transf) end)
	if not ok or type(file) ~= "string" or not m then return nil end
	return { file = file, position = { x = m[13], y = m[14], z = m[15] } }
end

--- True if a player (not the game, -1) owns the entity.
function world.is_player_owned(env, id)
	local owner = component(env, id, "PLAYER_OWNED")
	local player = nil
	pcall(function() player = owner.player end)
	return type(player) == "number" and player >= 0
end

--- Constructions owned by a player, as { [id] = { file, position } }. Used once per savegame;
-- afterwards the list is kept up to date from build events.
function world.player_constructions(env)
	local list = {}
	each_with(env, "CONSTRUCTION", function(id)
		if world.is_player_owned(env, id) then
			local info = world.construction_info(env, id)
			if info then list[id] = info end
		end
	end)
	return list
end

--- The construction of `file` closest to `pos` within `radius` metres, or nil.
function world.find_construction(env, file, pos, radius)
	radius = radius or world.CONSTRUCTION_RADIUS
	local best, best_d = nil, nil
	pcall(each_with, env, "CONSTRUCTION", function(id)
		local info = world.construction_info(env, id)
		if info and info.file == file then
			local dx, dy = info.position.x - pos.x, info.position.y - pos.y
			local d = dx * dx + dy * dy
			if d <= radius * radius and (not best_d or d < best_d) then best, best_d = id, d end
		end
	end)
	return best
end

--- What a stop/signal on an edge needs to travel: param along the edge, position, model
-- resource and name. The model is taken from the EDGE_OBJECT component (edgeObjectConstruction,
-- tealdef) or from the proposal's model instance via modelRep.
-- @param from_proposal table|nil { left, name, category, modelId } from edgeObjectsToAdd
-- @return table { param, position, model, name, left, oneWay, side_left, sources } or { problem }
function world.edge_object_info(env, id, from_proposal)
	local out = { sources = {} }
	local eo = component(env, id, "EDGE_OBJECT")
	if not eo then return { problem = "no EDGE_OBJECT component" } end
	pcall(function() out.param = eo.param end)
	local m = nil
	pcall(function() m = build.read_transf(eo.transf) end)
	if m then out.position = { x = m[13], y = m[14], z = m[15] } end
	pcall(function()
		local res = eo.edgeObjectConstruction
		if type(res) == "string" and res ~= "" then
			out.model = res
			out.sources[#out.sources + 1] = "edgeObjectConstruction"
		end
	end)
	from_proposal = from_proposal or {}
	if not out.model and from_proposal.modelId then
		pcall(function()
			local name = env.api.res.modelRep.getName(from_proposal.modelId)
			if type(name) == "string" and name ~= "" then
				out.model = name
				out.sources[#out.sources + 1] = "modelRep"
			end
		end)
	end
	if from_proposal.left ~= nil then out.left = from_proposal.left and true or false end
	out.name = from_proposal.name
	if not out.name then
		pcall(function() out.name = component(env, id, "NAME").name end)
	end
	if type(out.model) == "string" and out.model:find("one_way", 1, true) then out.oneWay = true end
	if not out.position then out.problem = "no position" elseif not out.model then out.problem = "no model" end
	return out
end

function world.describe_edge_object(o)
	o = o or {}
	local p = o.position
	return string.format("param=%s position=%s model=%s (%s) name=%s left=%s oneWay=%s problem=%s",
		tostring(o.param), p and string.format("%.1f,%.1f,%.1f", p.x, p.y, p.z) or "nil", tostring(o.model),
		table.concat(o.sources or {}, ","), tostring(o.name), tostring(o.left), tostring(o.oneWay), tostring(o.problem))
end

--- Stops/signals on an edge of this game: {{id, side, position}}.
function world.edge_objects_of(env, edge)
	local out = {}
	local comp = component(env, edge, "BASE_EDGE")
	if not comp then return out end
	for _, entry in ipairs(build.edge_objects_of(comp)) do
		local o = world.edge_object_info(env, entry[1])
		out[#out + 1] = { id = entry[1], side = entry[2], position = o.position }
	end
	return out
end

return world

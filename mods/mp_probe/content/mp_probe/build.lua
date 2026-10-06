--- Serialises a road/track build proposal to a text line and rebuilds it from that line.
-- This is the core of phase 1: what the player builds has to travel to the other game as data
-- (never as entity ids, which differ per game) and be rebuilt there with api.cmd.
-- Everything except replay() is pure, so the format can be tested offline.
-- @module mp_probe.build
local build = {}

--- Wire format version, part of every line so an old client can reject a new line.
build.VERSION = 3

local function round(x)
	return math.floor(x * 1000 + 0.5) / 1000
end

--- A rounded number without a trailing ".0", so Lua 5.2 (the game) and 5.3+ write the same text.
local function num(x)
	local r = round(x)
	if r == math.floor(r) then return string.format("%d", r) end
	return tostring(r)
end

--- 2^k as an exact integer.
local function bit(k)
	local v = 1
	for _ = 1, k do v = v * 2 end
	return v
end

local function has_bit(mask, k)
	return math.floor(mask / bit(k)) % 2 == 1
end

--- Highest transport mode index probed; run 5 showed 16 modes (keys 0..15) per lane.
local MAX_MODE = 31

--- Packs a lane's transportModes (a table the engine fills with keys 0..15) into one number,
-- bit k = mode k.
function build.modes_to_mask(modes)
	local mask = 0
	for k = 0, MAX_MODE do
		local ok, v = pcall(function() return modes[k] end)
		if ok and v == true then mask = mask + bit(k) end
	end
	return mask
end

--- Lane configurations of a segment as text: lanes separated by "|", each
-- "speed,width,height,forward,modes,offset" (forward 1/0, modes as build.modes_to_mask).
-- Run 10: without them the game's street geometry fails ("Assertion '!laneConfigs.empty()'").
function build.lanes_to_string(lanes)
	local n = 0
	pcall(function() n = #lanes end)
	if n == 0 then return "-" end
	local parts = {}
	for i = 1, n do
		local lane = lanes[i]
		parts[i] = table.concat({ num(lane.speed), num(lane.width), num(lane.height), lane.forward and 1 or 0,
			build.modes_to_mask(lane.transportModes), num(lane.offset) }, ",")
	end
	return table.concat(parts, "|")
end

--- Parses build.lanes_to_string. Returns nil for "-" and nil plus an error for broken text.
function build.lanes_from_string(text)
	if text == "-" then return nil end
	local lanes = {}
	for part in string.gmatch(text, "[^|]+") do
		local speed, width, height, forward, modes, offset =
			string.match(part, "^([^,]+),([^,]+),([^,]+),([01]),(%d+),([^,]+)$")
		if not speed then return nil, "bad lane " .. part end
		lanes[#lanes + 1] = {
			speed = tonumber(speed), width = tonumber(width), height = tonumber(height),
			forward = forward == "1", modes = tonumber(modes), offset = tonumber(offset),
		}
	end
	return lanes
end

--- precedenceNode0/1 of an entry's params or streetEdge as "p0,p1", or "-" when it has none
-- (run 5: tracks have no params).
local function precedence_to_string(entry, key)
	local ok, text = pcall(function()
		local p = entry[key]
		if p == nil then return "-" end
		return p.precedenceNode0 .. "," .. p.precedenceNode1
	end)
	return ok and text or "-"
end

local function precedence_from_string(text)
	if text == "-" then return nil end
	local p0, p1 = string.match(text, "^(%-?%d+),(%-?%d+)$")
	if not p0 then return nil end
	return { tonumber(p0), tonumber(p1) }
end

local function vec_to_string(v)
	return round(v.x) .. "," .. round(v.y) .. "," .. round(v.z)
end

local function vec_from_string(s)
	local x, y, z = string.match(s, "([^,]+),([^,]+),([^,]+)")
	if not x then return nil end
	return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

--- Turns a captured proposal into one line.
-- New nodes and segments keep only their position and shape; their engine ids become placeholders
-- -1, -2, ... because the other game will create different ones. A node the player connected to
-- (not part of addedNodes) keeps its real id, which only works inside the same game, so the count
-- of those is reported in `info.foreign_nodes` and the caller can skip such a line.
-- @param proposal userdata param[1].proposal of onPostBuildProposal
-- @return string line, table info { nodes, segments, foreign_nodes }
function build.serialize(proposal)
	local parts = { "B" .. build.VERSION }
	local placeholder = {}
	local road_ids, road_count = {}, 0
	local info = { nodes = 0, segments = 0, foreign_nodes = 0 }
	local nodes = proposal.addedNodes
	for i = 1, #nodes do
		local node = nodes[i]
		placeholder[node.entity] = -i
		info.nodes = i
		parts[#parts + 1] = "n" .. (-i) .. ";" .. vec_to_string(node.comp.position)
	end
	local segments = proposal.addedSegments
	for i = 1, #segments do
		local seg = segments[i]
		local comp = seg.comp
		local n0, n1 = placeholder[comp.node0], placeholder[comp.node1]
		if not n0 then
			n0 = comp.node0
			info.foreign_nodes = info.foreign_nodes + 1
		end
		if not n1 then
			n1 = comp.node1
			info.foreign_nodes = info.foreign_nodes + 1
		end
		if comp.roadTemplate == nil or comp.roadStyle == nil then
			error("segment " .. tostring(seg.entity) .. " has no roadTemplate/roadStyle", 0)
		end
		info.segments = i
		-- TF3 keeps the street or track type in the segment itself (run 5 raw dump):
		-- comp.roadTemplate/roadStyle are resource paths, roadType is 1 for streets and 0 for tracks,
		-- and comp.laneConfigs holds the lanes the game derived from them. Each template/style/lanes
		-- combination is written once as a "t" token and referenced by number.
		local road_key = comp.roadTemplate .. ";" .. comp.roadStyle .. ";" .. build.lanes_to_string(comp.laneConfigs)
		local road = road_ids[road_key]
		if not road then
			road_count = road_count + 1
			road = road_count
			road_ids[road_key] = road
			parts[#parts + 1] = "t" .. road .. ";" .. road_key
		end
		parts[#parts + 1] = table.concat({
			"s" .. (-i), seg.type, n0, n1,
			vec_to_string(comp.tangent0), vec_to_string(comp.tangent1), comp.typeIndex,
			comp.roadType or -1, comp.distance or 0, road,
			precedence_to_string(seg, "params"), precedence_to_string(seg, "streetEdge"),
		}, ";")
	end
	return table.concat(parts, " "), info
end

--- Parses a line produced by build.serialize.
-- @return table|nil data { version, nodes = {{id, position}}, segments = {{id, type, node0, node1,
--   tangent0, tangent1, typeIndex, roadType, distance, roadTemplate, roadStyle, lanes, params,
--   streetEdge}} }, or nil plus an error message
function build.deserialize(line)
	if type(line) ~= "string" then return nil, "not a string" end
	local data = { nodes = {}, segments = {} }
	local roads = {}
	for token in string.gmatch(line, "%S+") do
		local kind = token:sub(1, 1)
		if kind == "B" then
			data.version = tonumber(token:sub(2))
			if data.version ~= build.VERSION then
				return nil, "unsupported version " .. tostring(token:sub(2))
			end
		elseif kind == "t" then
			local id, template, style, lanes_text = string.match(token, "^t(%d+);([^;]+);([^;]+);([^;]+)$")
			if not id then return nil, "bad road token " .. token end
			local lanes, err = build.lanes_from_string(lanes_text)
			if err then return nil, err end
			roads[tonumber(id)] = { template = template, style = style, lanes = lanes }
		elseif kind == "n" then
			local id, pos = string.match(token, "^n(%-?%d+);(.+)$")
			local position = id and vec_from_string(pos)
			if not position then return nil, "bad node token " .. token end
			data.nodes[#data.nodes + 1] = { id = tonumber(id), position = position }
		elseif kind == "s" then
			local fields = {}
			for field in string.gmatch(token:sub(2), "[^;]+") do fields[#fields + 1] = field end
			if #fields ~= 12 then return nil, "bad segment token " .. token end
			local road = roads[tonumber(fields[10])]
			if not road then return nil, "unknown road type in " .. token end
			local t0, t1 = vec_from_string(fields[5]), vec_from_string(fields[6])
			if not t0 or not t1 then return nil, "bad tangent in " .. token end
			data.segments[#data.segments + 1] = {
				id = tonumber(fields[1]),
				type = tonumber(fields[2]),
				node0 = tonumber(fields[3]),
				node1 = tonumber(fields[4]),
				tangent0 = t0,
				tangent1 = t1,
				typeIndex = tonumber(fields[7]),
				roadType = tonumber(fields[8]),
				distance = tonumber(fields[9]),
				roadTemplate = road.template,
				roadStyle = road.style,
				lanes = road.lanes,
				params = precedence_from_string(fields[11]),
				streetEdge = precedence_from_string(fields[12]),
			}
		end
	end
	if not data.version then return nil, "no version token" end
	return data
end

--- Writes obj[key] = value. A failure goes into `errors` as "label: message" instead of raising,
-- so one field the engine refuses does not hide what happened to the others.
local function try_set(obj, key, value, errors, label)
	local ok, err = pcall(function() obj[key] = value end)
	if not ok and errors then errors[#errors + 1] = label .. ": " .. tostring(err):sub(1, 80) end
	return ok
end

--- Changes the nested value obj[key] with `change` and writes it back. Run 9 showed that TF3 hands
-- out copies: a list read from a proposal is a new Lua table, and what was appended to it never
-- reached the proposal. Nested structs may be copies as well, so every level is written back.
local function update(obj, key, change, errors, label)
	local ok, nested = pcall(function() return obj[key] end)
	if not ok or nested == nil then
		if errors then errors[#errors + 1] = label .. ": cannot read" end
		return false
	end
	local ok_change, err = pcall(change, nested)
	if not ok_change and errors then errors[#errors + 1] = label .. ": " .. tostring(err):sub(1, 80) end
	-- Written back even after a failed change, so whatever did change is kept.
	return try_set(obj, key, nested, errors, label) and ok_change
end

--- Sets a Vec3f field to a new api.type.Vec3f. If that does not work, the copy of the current
-- vector is changed and written back instead; only when both fail is an error recorded.
local function set_vec(api, obj, key, v, errors, label)
	local first = {}
	local ok, vec = pcall(function() return api.type.Vec3f.new(v.x, v.y, v.z) end)
	if ok and vec ~= nil then
		if try_set(obj, key, vec, first, label) then return true end
	else
		first[1] = label .. ": Vec3f.new failed (" .. tostring(vec):sub(1, 60) .. ")"
	end
	if update(obj, key, function(cur) cur.x, cur.y, cur.z = v.x, v.y, v.z end, first, label) then return true end
	for _, e in ipairs(first) do errors[#errors + 1] = e end
	return false
end

--- Sets a lane's transportModes to `mask`. First the engine's own copy is changed and written back,
-- which keeps whatever keys the engine uses (run 5: 0..15); then fresh tables numbered from 0 and
-- from 1 are tried. Each attempt is read back.
local function set_modes(lane, mask, errors, label)
	local function read_mask()
		local ok, m = pcall(function() return build.modes_to_mask(lane.transportModes) end)
		return ok and m or nil
	end
	update(lane, "transportModes", function(modes)
		for k = 0, MAX_MODE do
			local ok, v = pcall(function() return modes[k] end)
			if ok and v ~= nil then modes[k] = has_bit(mask, k) end
		end
	end, nil, label)
	if read_mask() == mask then return true end
	for _, base in ipairs({ 0, 1 }) do
		local modes = {}
		for k = 0, 15 do modes[k + base] = has_bit(mask, k) end
		try_set(lane, "transportModes", modes, nil, label)
		if read_mask() == mask then return true end
	end
	errors[#errors + 1] = label .. ": reads back as " .. tostring(read_mask()) .. " instead of " .. mask
	return false
end

--- Creates one api.type.LaneConfig from a parsed lane.
function build.make_lane(api, lane, errors, label)
	local entry = api.type.LaneConfig.new()
	for _, key in ipairs({ "speed", "width", "height", "forward", "offset" }) do
		try_set(entry, key, lane[key], errors, label .. "." .. key)
	end
	set_modes(entry, lane.modes, errors, label .. ".transportModes")
	return entry
end

--- Sets precedenceNode0/1 on entry[key] (params or streetEdge, both api.type.BaseEdgeStreet in
-- TF3). If the entry has none yet, a new one is created.
local function set_precedence(api, entry, key, precedence, errors, label)
	local ok, current = pcall(function() return entry[key] end)
	if not ok or current == nil then
		local ok_new, created = pcall(function() return api.type.BaseEdgeStreet.new() end)
		if not ok_new or created == nil then
			errors[#errors + 1] = label .. ": missing and BaseEdgeStreet.new failed"
			return
		end
		try_set(created, "precedenceNode0", precedence[1], errors, label .. ".precedenceNode0")
		try_set(created, "precedenceNode1", precedence[2], errors, label .. ".precedenceNode1")
		try_set(entry, key, created, errors, label)
		return
	end
	update(entry, key, function(p)
		p.precedenceNode0 = precedence[1]
		p.precedenceNode1 = precedence[2]
	end, errors, label)
end

--- Appends to one of TF3's Vector_* objects (see build.to_vector). Plain index assignment is tried
-- first, then the usual vector methods.
function build.append(list, item)
	if list == nil then error("list is nil", 0) end
	local errors = {}
	local attempts = {
		function() list[#list + 1] = item end,
		function() list:push_back(item) end,
		function() list:add(item) end,
		function() list:append(item) end,
	}
	for _, attempt in ipairs(attempts) do
		local ok, err = pcall(attempt)
		if ok then return end
		errors[#errors + 1] = tostring(err):sub(1, 60)
	end
	error("cannot append (" .. table.concat(errors, " / ") .. ")", 0)
end

--- Proposal layouts tried when rebuilding, in order; each entry returns a new proposal (`new`),
-- assigns the two finished lists as a whole and writes every level back (`fill`), and returns the
-- lists as the proposal holds them now (`read`). Run 10: makeWorldBuildProposalCmd decodes only an
-- api.type.SimpleProposal as its proposal ("Error decoding argument" for WorldBuildProposal and
-- StreetProposal), so that is the only layout left.
build.LAYOUTS = {
	{
		name = "SimpleProposal",
		new = function(t) return t.SimpleProposal.new() end,
		fill = function(p, nodes, edges, errors)
			update(p, "streetProposal", function(sp)
				try_set(sp, "nodesToAdd", nodes, errors, "streetProposal.nodesToAdd")
				try_set(sp, "edgesToAdd", edges, errors, "streetProposal.edgesToAdd")
			end, errors, "streetProposal")
		end,
		read = function(p)
			local sp = p.streetProposal
			return sp.nodesToAdd, sp.edgesToAdd
		end,
	},
}

--- How the entry lists are handed to a proposal: as a plain Lua table (what TF3 returns when a
-- list is read) or, if the proposal refuses that, as TF3's own vector types
-- (api.type.Vector_NodeAndEntity and Vector_SegmentAndEntity).
build.LIST_KINDS = { "table", "vector" }

--- Placeholder entity id of a node inside a proposal. Nodes and segments are both entities, and
-- TF2 scripts number all new entities of a proposal with one shared counter (-1, -2, ...), so a node
-- must not reuse a segment's placeholder. The line numbers both from -1; here the nodes move behind
-- the segments (-1 becomes -(segments + 1)). Real (positive) ids of existing nodes stay as they are.
function build.node_entity(data, id)
	if id < 0 then return id - #data.segments end
	return id
end

--- Creates the NodeAndEntity for one node of parsed data.
function build.make_node(api, data, node, errors)
	local entry = api.type.NodeAndEntity.new()
	try_set(entry, "entity", build.node_entity(data, node.id), errors, "node.entity")
	update(entry, "comp", function(comp)
		set_vec(api, comp, "position", node.position, errors, "node.comp.position")
	end, errors, "node.comp")
	return entry
end

--- Creates the SegmentAndEntity for one segment of parsed data.
-- @param positions table node positions by line id, for comp.position0/position1
-- @param player number|nil player entity that will own the segment
function build.make_segment(api, data, seg, positions, player, errors)
	local entry = api.type.SegmentAndEntity.new()
	try_set(entry, "entity", seg.id, errors, "edge.entity")
	try_set(entry, "type", seg.type, errors, "edge.type")
	update(entry, "comp", function(comp)
		try_set(comp, "node0", build.node_entity(data, seg.node0), errors, "edge.comp.node0")
		try_set(comp, "node1", build.node_entity(data, seg.node1), errors, "edge.comp.node1")
		set_vec(api, comp, "tangent0", seg.tangent0, errors, "edge.comp.tangent0")
		set_vec(api, comp, "tangent1", seg.tangent1, errors, "edge.comp.tangent1")
		if positions[seg.node0] then set_vec(api, comp, "position0", positions[seg.node0], errors, "edge.comp.position0") end
		if positions[seg.node1] then set_vec(api, comp, "position1", positions[seg.node1], errors, "edge.comp.position1") end
		if seg.typeIndex then try_set(comp, "typeIndex", seg.typeIndex, errors, "edge.comp.typeIndex") end
		-- Without its template the segment has no street or track type.
		try_set(comp, "roadTemplate", seg.roadTemplate, errors, "edge.comp.roadTemplate")
		try_set(comp, "roadStyle", seg.roadStyle, errors, "edge.comp.roadStyle")
		if seg.roadType then try_set(comp, "roadType", seg.roadType, errors, "edge.comp.roadType") end
		if seg.distance then try_set(comp, "distance", seg.distance, errors, "edge.comp.distance") end
		if seg.lanes then
			-- Run 10: the game does not derive the lanes from the template, so they travel in the line.
			local lanes = {}
			for i, lane in ipairs(seg.lanes) do
				lanes[i] = build.make_lane(api, lane, errors, "edge.comp.laneConfigs[" .. i .. "]")
			end
			if not try_set(comp, "laneConfigs", lanes, nil, "edge.comp.laneConfigs") then
				local ok, vector = pcall(build.to_vector, api, "Vector_LaneConfig", lanes)
				if ok then
					try_set(comp, "laneConfigs", vector, errors, "edge.comp.laneConfigs")
				else
					errors[#errors + 1] = "edge.comp.laneConfigs: " .. tostring(vector):sub(1, 80)
				end
			end
		end
	end, errors, "edge.comp")
	if seg.params then set_precedence(api, entry, "params", seg.params, errors, "edge.params") end
	if seg.streetEdge then set_precedence(api, entry, "streetEdge", seg.streetEdge, errors, "edge.streetEdge") end
	if player then
		local ok, owned = pcall(function() return api.type.PlayerOwned.new() end)
		if ok and owned ~= nil then
			try_set(owned, "player", player, errors, "edge.playerOwned.player")
			try_set(entry, "playerOwned", owned, errors, "edge.playerOwned")
		else
			errors[#errors + 1] = "edge.playerOwned: PlayerOwned.new failed"
		end
	end
	return entry
end

--- Copies entries into a new api.type.<type_name>, for proposals that refuse a plain Lua table.
function build.to_vector(api, type_name, items)
	local vector = api.type[type_name].new()
	for _, item in ipairs(items) do build.append(vector, item) end
	return vector
end

local function count(list)
	local ok, n = pcall(function() return #list end)
	return ok and type(n) == "number" and n or 0
end

local function format_vec(v)
	local ok, text = pcall(string.format, "%.1f,%.1f,%.1f", v.x, v.y, v.z)
	return ok and text or "?"
end

local function near(a, b)
	return type(a) == "number" and math.abs(a - b) <= 0.5
end

--- Reads a filled proposal back. Only a proposal whose lists and first entries came through is
-- worth sending: run 9 sent an empty one, which the game accepted without building anything.
-- @return table { complete = bool, text = string with what was read back }
function build.check(layout, proposal, data)
	local want_nodes, want_edges = #data.nodes, #data.segments
	local ok, node_list, edge_list = pcall(layout.read, proposal)
	if not ok then return { complete = false, text = "read back failed: " .. tostring(node_list):sub(1, 100) } end
	local n, e = count(node_list), count(edge_list)
	local complete = n == want_nodes and e == want_edges
	local parts = { "nodes " .. n .. "/" .. want_nodes, "edges " .. e .. "/" .. want_edges }
	if n > 0 and want_nodes > 0 then
		local ok_n, entity, pos = pcall(function()
			local node = node_list[1]
			local p = node.comp.position
			return node.entity, { x = p.x, y = p.y, z = p.z }
		end)
		if ok_n then
			local want = data.nodes[1].position
			parts[#parts + 1] = "node[1] " .. tostring(entity) .. " at " .. format_vec(pos)
			if not (near(pos.x, want.x) and near(pos.y, want.y) and near(pos.z, want.z)) then
				complete = false
				parts[#parts + 1] = "expected at " .. format_vec(want)
			end
		else
			complete = false
			parts[#parts + 1] = "node[1] unreadable (" .. tostring(entity):sub(1, 60) .. ")"
		end
	end
	if e > 0 and want_edges > 0 then
		local ok_e, edge = pcall(function()
			local x = edge_list[1]
			local c = x.comp
			local t = c.tangent0
			local owner = nil
			pcall(function() owner = x.playerOwned.player end)
			local lanes, lane1 = 0, nil
			pcall(function()
				local list = c.laneConfigs
				lanes = count(list)
				if lanes > 0 then lane1 = { width = list[1].width, modes = build.modes_to_mask(list[1].transportModes) } end
			end)
			return {
				entity = x.entity, type = x.type, node0 = c.node0, node1 = c.node1,
				tangent0 = { x = t.x, y = t.y, z = t.z }, template = c.roadTemplate, owner = owner,
				lanes = lanes, lane1 = lane1,
			}
		end)
		if ok_e then
			local want = data.segments[1]
			parts[#parts + 1] = string.format("edge[1] %s type %s nodes %s->%s tangent0 %s template %s owner %s",
				tostring(edge.entity), tostring(edge.type), tostring(edge.node0), tostring(edge.node1),
				format_vec(edge.tangent0), tostring(edge.template):match("[^/]*$"), tostring(edge.owner))
			if edge.node0 ~= build.node_entity(data, want.node0) or edge.node1 ~= build.node_entity(data, want.node1) then
				complete = false
				parts[#parts + 1] = "expected nodes " .. build.node_entity(data, want.node0) .. "->" ..
					build.node_entity(data, want.node1)
			end
			-- Run 10: segments without their lanes make the game's street geometry fail.
			local want_lanes = want.lanes and #want.lanes or 0
			local lane_text = "lanes " .. edge.lanes .. "/" .. want_lanes
			if edge.lane1 then
				lane_text = lane_text .. " lane[1] width " .. tostring(edge.lane1.width) .. " modes " .. tostring(edge.lane1.modes)
			end
			parts[#parts + 1] = lane_text
			if edge.lanes ~= want_lanes or (want_lanes > 0 and not (edge.lane1 and near(edge.lane1.width, want.lanes[1].width)
				and edge.lane1.modes == want.lanes[1].modes)) then
				complete = false
				if want_lanes > 0 then
					parts[#parts + 1] = "expected lane[1] width " .. want.lanes[1].width .. " modes " .. want.lanes[1].modes
				end
			end
		else
			complete = false
			parts[#parts + 1] = "edge[1] unreadable (" .. tostring(edge):sub(1, 60) .. ")"
		end
	end
	return { complete = complete, text = table.concat(parts, ", ") }
end

--- Builds a proposal from parsed data with one entry of build.LAYOUTS and reads it back.
-- @param list_kind string|nil one of build.LIST_KINDS, default "table"
-- @return userdata proposal, table check (see build.check), table errors (fields the engine
--   refused); raises when a type is missing, callers use pcall
function build.make_proposal(env, data, layout, player, list_kind)
	local api = env.api
	local errors = {}
	local positions = {}
	for _, node in ipairs(data.nodes) do positions[node.id] = node.position end
	local nodes, edges = {}, {}
	for _, node in ipairs(data.nodes) do nodes[#nodes + 1] = build.make_node(api, data, node, errors) end
	for _, seg in ipairs(data.segments) do
		edges[#edges + 1] = build.make_segment(api, data, seg, positions, player, errors)
	end
	if list_kind == "vector" then
		nodes = build.to_vector(api, "Vector_NodeAndEntity", nodes)
		edges = build.to_vector(api, "Vector_SegmentAndEntity", edges)
	end
	local proposal = layout.new(api.type)
	layout.fill(proposal, nodes, edges, errors, build.make_context(env, player))
	-- The same field fails for every segment and lane; report each message once with a count.
	local unique, seen = {}, {}
	for _, e in ipairs(errors) do
		if seen[e] then
			seen[e].n = seen[e].n + 1
		else
			seen[e] = { n = 1 }
			unique[#unique + 1] = e
		end
	end
	for i, e in ipairs(unique) do
		if seen[e].n > 1 then unique[i] = e .. " (" .. seen[e].n .. "x)" end
	end
	return proposal, build.check(layout, proposal, data), unique
end

--- Argument lists tried for api.cmd.makeWorldBuildProposalCmd (TF2 passed proposal, context and an
-- "ignore errors" flag). Run 9: signature 1 is accepted with a SimpleProposal.
build.CMD_ARGS = {
	function(proposal, context) return { proposal, context, true } end,
	function(proposal, context) return { proposal, context, false } end,
	function(proposal, context) return { proposal, context } end,
	function(proposal) return { proposal, true } end,
	function(proposal) return { proposal } end,
}

--- Builds the command context like a player build: owned by `player`, with street graph
-- cleanup and terrain alignment, as TF2 scripts did.
function build.make_context(env, player)
	local context = env.api.type.Context.new()
	pcall(function()
		if player then context.player = player end
		context.cleanupStreetGraph = true
		context.gatherBuildings = true
		context.gatherFields = true
		context.checkTerrainAlignment = true
	end)
	return context
end

--- Sends a proposal, trying every signature in build.CMD_ARGS.
-- @param log function|nil receives one line per failed attempt
-- @param on_result function|nil callback(result, success) the game calls once it has executed the
--   command; this is the only place that says whether the build really happened
-- @return boolean ok, string message
function build.send(env, proposal, log, on_result, player)
	local api = env.api
	local context = nil
	pcall(function() context = build.make_context(env, player) end)
	for i, make_args in ipairs(build.CMD_ARGS) do
		local ok, err = pcall(function()
			local args = make_args(proposal, context)
			local cmd = api.cmd.makeWorldBuildProposalCmd(args[1], args[2], args[3])
			if on_result then
				api.cmd.sendCommand(cmd, on_result)
			else
				api.cmd.sendCommand(cmd)
			end
		end)
		if ok then return true, "sent with signature " .. i end
		if log then log("signature " .. i .. ": " .. tostring(err):sub(1, 200)) end
		-- Run 10: with a decodable proposal the game computes it right away and raises "Unknown
		-- exception" when the content is wrong; other signatures only repeat that.
		local text = tostring(err)
		if not (text:find("Error decoding argument", 1, true) or text:find("bad argument", 1, true)) then
			return false, "the game rejected the proposal (" .. text:sub(1, 120) .. ")"
		end
	end
	return false, "no signature worked"
end

--- Text of an error or warning in a command result; it may be a string or a struct.
local function message_text(m)
	if type(m) == "string" then return m end
	for _, key in ipairs({ "text", "message", "description" }) do
		local ok, v = pcall(function() return m[key] end)
		if ok and type(v) == "string" then return v end
	end
	return tostring(m)
end

--- Reads what the game did with a sent proposal. Run 9: `success` was true and the costs 0 for an
-- empty proposal, so only new entities or positive costs count as built.
-- @return table { built = true, false or nil (unknown), costs, entities, critical,
--   messages = list of "message: ..." and "warning: ..." }
function build.outcome(result)
	local o = { messages = {} }
	pcall(function() o.costs = result.resultProposalData.costs end)
	pcall(function() o.entities = #result.resultEntities end)
	pcall(function() o.critical = result.resultProposalData.errorState.critical end)
	pcall(function()
		local state = result.resultProposalData.errorState
		for _, key in ipairs({ "messages", "warnings" }) do
			local list = state[key]
			for i = 1, #list do o.messages[#o.messages + 1] = key:sub(1, -2) .. ": " .. message_text(list[i]) end
		end
	end)
	if o.entities ~= nil or o.costs ~= nil then
		o.built = (o.entities or 0) > 0 or (type(o.costs) == "number" and o.costs > 0)
	end
	return o
end

--- Moves every node of parsed data by (dx, dy). Only for the single-PC test, where the copy has
-- to appear next to the original instead of on top of it.
function build.offset(data, dx, dy)
	for _, node in ipairs(data.nodes) do
		node.position.x = node.position.x + dx
		node.position.y = node.position.y + dy
	end
	return data
end

--- Offset of `distance` metres at a right angle to the first segment, so a straight road gets a
-- parallel copy.
function build.side_offset(data, distance)
	local seg = data.segments[1]
	if not seg then return 0, distance end
	local tx, ty = seg.tangent0.x, seg.tangent0.y
	local len = math.sqrt(tx * tx + ty * ty)
	if len < 1e-6 then return 0, distance end
	return -ty / len * distance, tx / len * distance
end

--- Rebuilds parsed data in the running game. For each layout the list kinds are tried until the
-- proposal reads back complete; an incomplete proposal is never sent. Run 9 showed that the game
-- calls the result callback before sendCommand returns, so when it reports that nothing was built,
-- the next layout is tried right here, without a command inside the callback.
-- @param opts table|nil { log = function(line), on_result = function(result, success, label,
--   outcome), inspect = function(label, node_list, edge_list) called with a complete proposal
--   before it is sent, player = entity }
-- @return boolean ok, string message
function build.replay(env, data, opts)
	opts = opts or {}
	local log = opts.log or function() end
	if not (env.api and env.api.type and env.api.cmd) then return false, "api missing" end
	local nothing_built, failure = 0, nil
	for index, layout in ipairs(build.LAYOUTS) do
		local proposal, label = nil, nil
		for _, kind in ipairs(build.LIST_KINDS) do
			local attempt = layout.name .. "/" .. kind
			local ok, p, check, errors = pcall(build.make_proposal, env, data, layout, opts.player, kind)
			if not ok then
				log(attempt .. ": " .. tostring(p):sub(1, 200))
			else
				if #errors > 0 then log(attempt .. " refused fields: " .. table.concat(errors, "; "):sub(1, 600)) end
				log("proposal check " .. attempt .. ": " .. (check.complete and "complete" or "INCOMPLETE") ..
					", " .. check.text)
				if check.complete then
					proposal, label = p, attempt
					if opts.inspect then
						pcall(function()
							local node_list, edge_list = layout.read(p)
							opts.inspect(attempt, node_list, edge_list)
						end)
					end
					break
				end
			end
		end
		if proposal then
			local nothing = false
			local function on_result(result, success)
				local outcome = build.outcome(result)
				if opts.on_result then opts.on_result(result, success, label, outcome) end
				nothing = outcome.built == false or (outcome.built == nil and success == false)
			end
			local sent, message = build.send(env, proposal, function(line) log(label .. " " .. line) end,
				on_result, opts.player)
			if sent and not nothing then return true, label .. ": " .. message end
			if sent then
				nothing_built = nothing_built + 1
				if index < #build.LAYOUTS then
					log(label .. ": " .. message .. ", but nothing was built; trying the next layout")
				end
			else
				failure = label .. ": " .. message
			end
		end
	end
	if nothing_built > 0 then return false, "nothing built with any layout (" .. nothing_built .. " sent)" end
	return false, failure or "no layout could be filled and sent"
end

return build

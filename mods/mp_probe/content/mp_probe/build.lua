--- Serialises a road/track build proposal to a text line and rebuilds it from that line.
-- This is the core of phase 1: what the player builds has to travel to the other game as data
-- (never as entity ids, which differ per game) and be rebuilt there with api.cmd.
-- Everything except replay() is pure, so the format can be tested offline.
-- @module mp_probe.build
local build = {}

--- Wire format version, part of every line so an old client can reject a new line.
build.VERSION = 2

local function round(x)
	return math.floor(x * 1000 + 0.5) / 1000
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
		-- comp.roadTemplate/roadStyle are resource paths, roadType is 1 for streets and 0 for tracks.
		-- Each template/style pair is written once as a "t" token and referenced by number.
		local road_key = comp.roadTemplate .. ";" .. comp.roadStyle
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
		}, ";")
	end
	return table.concat(parts, " "), info
end

--- Parses a line produced by build.serialize.
-- @return table|nil data { version, nodes = {{id, position}}, segments = {{id, type, node0, node1,
--   tangent0, tangent1, typeIndex, roadType, distance, roadTemplate, roadStyle}} }, or nil plus an
--   error message
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
			local id, template, style = string.match(token, "^t(%d+);([^;]+);([^;]+)$")
			if not id then return nil, "bad road token " .. token end
			roads[tonumber(id)] = { template = template, style = style }
		elseif kind == "n" then
			local id, pos = string.match(token, "^n(%-?%d+);(.+)$")
			local position = id and vec_from_string(pos)
			if not position then return nil, "bad node token " .. token end
			data.nodes[#data.nodes + 1] = { id = tonumber(id), position = position }
		elseif kind == "s" then
			local fields = {}
			for field in string.gmatch(token:sub(2), "[^;]+") do fields[#fields + 1] = field end
			if #fields ~= 10 then return nil, "bad segment token " .. token end
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

--- Proposal layouts tried when rebuilding, in order. Run 6 showed that api.type.Proposal has
-- neither streetProposal nor addedSegments. TF3 also offers SimpleProposal (TF2's input type,
-- with streetProposal.nodesToAdd/edgesToAdd), WorldBuildProposal (proposal.proposal.addedNodes/
-- addedSegments plus its own context, like the param[1] the build event reports) and
-- StreetProposal. `fill` assigns the two finished lists as a whole and writes every level back;
-- `read` returns the lists as the proposal holds them now.
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
	{
		name = "WorldBuildProposal",
		new = function(t) return t.WorldBuildProposal.new() end,
		fill = function(p, nodes, edges, errors, context)
			update(p, "proposal", function(outer)
				update(outer, "proposal", function(inner)
					try_set(inner, "addedNodes", nodes, errors, "proposal.proposal.addedNodes")
					try_set(inner, "addedSegments", edges, errors, "proposal.proposal.addedSegments")
				end, errors, "proposal.proposal")
			end, errors, "proposal")
			if context then try_set(p, "context", context, errors, "context") end
		end,
		read = function(p)
			local inner = p.proposal.proposal
			return inner.addedNodes, inner.addedSegments
		end,
	},
	{
		name = "StreetProposal",
		new = function(t) return t.StreetProposal.new() end,
		fill = function(p, nodes, edges, errors)
			try_set(p, "addedNodes", nodes, errors, "addedNodes")
			try_set(p, "addedSegments", edges, errors, "addedSegments")
		end,
		read = function(p) return p.addedNodes, p.addedSegments end,
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
	end, errors, "edge.comp")
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
			return {
				entity = x.entity, type = x.type, node0 = c.node0, node1 = c.node1,
				tangent0 = { x = t.x, y = t.y, z = t.z }, template = c.roadTemplate, owner = owner,
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
	return proposal, build.check(layout, proposal, data), errors
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
--   outcome), player = entity }
-- @return boolean ok, string message
function build.replay(env, data, opts)
	opts = opts or {}
	local log = opts.log or function() end
	if not (env.api and env.api.type and env.api.cmd) then return false, "api missing" end
	local nothing_built = 0
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
			end
		end
	end
	if nothing_built > 0 then return false, "nothing built with any layout (" .. nothing_built .. " sent)" end
	return false, "no layout could be filled and sent"
end

return build

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

local function set_vec(target, v)
	target.x = v.x
	target.y = v.y
	target.z = v.z
end

--- Appends to an engine list. Lists inside TF3 proposals may be C++ vectors rather than Lua
-- tables, so after plain index assignment the usual vector methods are tried.
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
-- with streetProposal.nodesToAdd/edgesToAdd), WorldBuildProposal (matches makeWorldBuildProposalCmd
-- and the param[1] the build event reports: proposal.addedNodes/addedSegments) and StreetProposal.
-- Each entry returns the object to send plus the two lists to fill.
build.LAYOUTS = {
	{ name = "SimpleProposal", make = function(t)
		local p = t.SimpleProposal.new()
		return p, p.streetProposal.nodesToAdd, p.streetProposal.edgesToAdd
	end },
	{ name = "WorldBuildProposal", make = function(t)
		local p = t.WorldBuildProposal.new()
		return p, p.proposal.addedNodes, p.proposal.addedSegments
	end },
	{ name = "StreetProposal", make = function(t)
		local p = t.StreetProposal.new()
		return p, p.addedNodes, p.addedSegments
	end },
}

--- Builds a proposal from parsed data with one entry of build.LAYOUTS.
-- @param player number|nil player entity that will own the new segments
-- @return userdata proposal (raises on failure, callers use pcall)
function build.make_proposal(env, data, layout, player)
	local api = env.api
	local proposal, node_list, edge_list = layout.make(api.type)
	local positions = {}
	for _, node in ipairs(data.nodes) do positions[node.id] = node.position end
	for _, node in ipairs(data.nodes) do
		local entry = api.type.NodeAndEntity.new()
		entry.entity = node.id
		set_vec(entry.comp.position, node.position)
		build.append(node_list, entry)
	end
	for _, seg in ipairs(data.segments) do
		local entry = api.type.SegmentAndEntity.new()
		entry.entity = seg.id
		entry.type = seg.type
		entry.comp.node0 = seg.node0
		entry.comp.node1 = seg.node1
		set_vec(entry.comp.tangent0, seg.tangent0)
		set_vec(entry.comp.tangent1, seg.tangent1)
		if seg.typeIndex then pcall(function() entry.comp.typeIndex = seg.typeIndex end) end
		-- Without its template the segment has no street or track type; run 7 showed the game then
		-- accepts the command and silently builds nothing.
		entry.comp.roadTemplate = seg.roadTemplate
		entry.comp.roadStyle = seg.roadStyle
		if seg.roadType then entry.comp.roadType = seg.roadType end
		if seg.distance then pcall(function() entry.comp.distance = seg.distance end) end
		pcall(function()
			if positions[seg.node0] then set_vec(entry.comp.position0, positions[seg.node0]) end
			if positions[seg.node1] then set_vec(entry.comp.position1, positions[seg.node1]) end
		end)
		if player then
			pcall(function()
				local owned = api.type.PlayerOwned.new()
				owned.player = player
				entry.playerOwned = owned
			end)
		end
		build.append(edge_list, entry)
	end
	return proposal
end

--- Argument lists tried for api.cmd.makeWorldBuildProposalCmd (TF2 passed proposal, context and an
-- "ignore errors" flag). The real signature is unknown, so the first call that does not raise wins.
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

--- Rebuilds a serialized line in the running game, trying every layout.
-- @param opts table|nil { log = function(line), on_result = function(result, success, layout),
--   player = entity }
-- @return boolean ok, string message
function build.replay(env, data, opts)
	opts = opts or {}
	local log = opts.log
	if not (env.api and env.api.type and env.api.cmd) then return false, "api missing" end
	for _, layout in ipairs(build.LAYOUTS) do
		local ok, proposal = pcall(build.make_proposal, env, data, layout, opts.player)
		if ok then
			local on_result = opts.on_result and function(result, success)
				opts.on_result(result, success, layout.name)
			end
			local sent, message = build.send(env, proposal, function(line)
				if log then log(layout.name .. " " .. line) end
			end, on_result, opts.player)
			if sent then return true, layout.name .. ": " .. message end
		elseif log then
			log(layout.name .. ": " .. tostring(proposal):sub(1, 200))
		end
	end
	return false, "no layout worked"
end

return build

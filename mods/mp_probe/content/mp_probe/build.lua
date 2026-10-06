--- Serialises a road/track build proposal to a text line and rebuilds it from that line.
-- This is the core of phase 1: what the player builds has to travel to the other game as data
-- (never as entity ids, which differ per game) and be rebuilt there with api.cmd.
-- Everything except replay() is pure, so the format can be tested offline.
-- @module mp_probe.build
local build = {}

--- Wire format version, part of every line so an old client can reject a new line.
build.VERSION = 1

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
		info.segments = i
		parts[#parts + 1] = table.concat({
			"s" .. (-i), seg.type, n0, n1,
			vec_to_string(comp.tangent0), vec_to_string(comp.tangent1), comp.typeIndex,
		}, ";")
	end
	return table.concat(parts, " "), info
end

--- Parses a line produced by build.serialize.
-- @return table|nil data { version, nodes = {{id, position}}, segments = {{id, type, node0, node1,
--   tangent0, tangent1, typeIndex}} }, or nil plus an error message
function build.deserialize(line)
	if type(line) ~= "string" then return nil, "not a string" end
	local data = { nodes = {}, segments = {} }
	for token in string.gmatch(line, "%S+") do
		local kind = token:sub(1, 1)
		if kind == "B" then
			data.version = tonumber(token:sub(2))
			if data.version ~= build.VERSION then
				return nil, "unsupported version " .. tostring(token:sub(2))
			end
		elseif kind == "n" then
			local id, pos = string.match(token, "^n(%-?%d+);(.+)$")
			local position = id and vec_from_string(pos)
			if not position then return nil, "bad node token " .. token end
			data.nodes[#data.nodes + 1] = { id = tonumber(id), position = position }
		elseif kind == "s" then
			local fields = {}
			for field in string.gmatch(token:sub(2), "[^;]+") do fields[#fields + 1] = field end
			if #fields ~= 7 then return nil, "bad segment token " .. token end
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

--- Proposal layouts tried when rebuilding. TF2 fills proposal.streetProposal.edgesToAdd; the
-- proposal TF3 reports after a build uses addedSegments instead, and which one the build command
-- expects is unknown, so both are tried and the log says which worked.
build.LAYOUTS = { "streetProposal", "added" }

--- Builds an api.type.Proposal from parsed data in one of build.LAYOUTS.
-- @return userdata proposal (raises on failure, callers use pcall)
function build.make_proposal(env, data, layout)
	local api = env.api
	local proposal = api.type.Proposal.new()
	local node_list, edge_list
	if layout == "streetProposal" then
		if proposal.streetProposal == nil then error("no streetProposal field") end
		node_list, edge_list = proposal.streetProposal.nodesToAdd, proposal.streetProposal.edgesToAdd
	else
		node_list, edge_list = proposal.addedNodes, proposal.addedSegments
	end
	for _, node in ipairs(data.nodes) do
		local entry = api.type.NodeAndEntity.new()
		entry.entity = node.id
		set_vec(entry.comp.position, node.position)
		node_list[#node_list + 1] = entry
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
		edge_list[#edge_list + 1] = entry
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

--- Sends a proposal, trying every signature in build.CMD_ARGS.
-- @return boolean ok, string message
function build.send(env, proposal)
	local api = env.api
	local context = nil
	pcall(function() context = api.type.Context.new() end)
	local errors = {}
	for i, make_args in ipairs(build.CMD_ARGS) do
		local ok, err = pcall(function()
			local args = make_args(proposal, context)
			api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(args[1], args[2], args[3]))
		end)
		if ok then return true, "sent with signature " .. i end
		errors[#errors + 1] = i .. ": " .. tostring(err):sub(1, 100)
	end
	return false, "no signature worked (" .. table.concat(errors, " | ") .. ")"
end

--- Rebuilds a serialized line in the running game.
-- @return boolean ok, string message
function build.replay(env, data)
	if not (env.api and env.api.type and env.api.cmd) then return false, "api missing" end
	local messages = {}
	for _, layout in ipairs(build.LAYOUTS) do
		local ok, proposal = pcall(build.make_proposal, env, data, layout)
		if ok then
			local sent, message = build.send(env, proposal)
			if sent then return true, layout .. ": " .. message end
			messages[#messages + 1] = layout .. ": " .. message
		else
			messages[#messages + 1] = layout .. ": " .. tostring(proposal):sub(1, 100)
		end
	end
	return false, table.concat(messages, " || ")
end

return build

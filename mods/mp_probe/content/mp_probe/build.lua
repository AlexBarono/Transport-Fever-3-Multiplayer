--- Serialises a road/track build proposal to a text line and rebuilds it from that line.
-- This is the core of phase 1: what the player builds has to travel to the other game as data
-- (never as entity ids, which differ per game) and be rebuilt there with api.cmd.
-- Everything except replay() is pure, so the format can be tested offline.
-- @module mp_probe.build
local build = {}

--- Wire format version, part of every line so an old client can reject a new line.
build.VERSION = 5

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
	return num(v.x) .. "," .. num(v.y) .. "," .. num(v.z)
end

local function vec_from_string(s)
	local x, y, z = string.match(s, "([^,]+),([^,]+),([^,]+)")
	if not x then return nil end
	return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

--- Reads a transformation matrix (api Mat4f or a plain table) as 16 numbers, column by column,
-- so numbers 13..15 are the position. Several access styles are tried because the TF3 type is
-- not documented; the one that worked is returned as the second value.
function build.read_transf(t)
	if t == nil then return nil, "no transf" end
	local attempts = {
		{ "index1", function()
			local m = {}
			for i = 1, 16 do m[i] = t[i] end
			return m
		end },
		{ "cols0", function()
			local m = {}
			for c = 0, 3 do
				local col = t:cols(c)
				m[#m + 1], m[#m + 2], m[#m + 3], m[#m + 4] = col.x, col.y, col.z, col.w
			end
			return m
		end },
		{ "index0", function()
			local m = {}
			for i = 0, 15 do m[i + 1] = t[i] end
			return m
		end },
	}
	local errors = {}
	for _, attempt in ipairs(attempts) do
		local ok, m = pcall(attempt[2])
		if ok and type(m) == "table" then
			local complete = true
			for i = 1, 16 do
				if type(m[i]) ~= "number" then complete = false end
			end
			if complete then return m, attempt[1] end
			errors[#errors + 1] = attempt[1] .. ": not 16 numbers"
		else
			errors[#errors + 1] = attempt[1] .. ": " .. tostring(m):sub(1, 60)
		end
	end
	return nil, table.concat(errors, "; ")
end

--- Percent-encodes every character that is not a letter, digit, "_", "." or "-", so a text field
-- never contains the separators of the line (space, ";", "|", ",") or of a params literal.
function build.escape(text)
	return (string.gsub(tostring(text), "[^%w_%.%-]", function(c) return string.format("%%%02X", c:byte()) end))
end

function build.unescape(text)
	return (string.gsub(text, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

--- A number with up to 6 decimals and no trailing zeros (rotation parts of a transformation need
-- more than the 3 decimals of positions).
local function fine(x)
	local s = string.format("%.6f", x)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then s = "0" end
	return s
end

--- Writes a construction's params table as a literal: {key=value,...} with keys sorted, strings
-- as 's<escaped>', numbers as 'n<number>', booleans as 'T'/'F'. Functions and userdata cannot
-- travel and raise an error.
function build.params_to_string(value)
	local t = type(value)
	if t == "number" then
		if value == math.floor(value) and math.abs(value) < 1e15 then return "n" .. string.format("%d", value) end
		return "n" .. string.format("%.10g", value)
	elseif t == "string" then
		return "s" .. build.escape(value)
	elseif t == "boolean" then
		return value and "T" or "F"
	elseif t == "table" then
		local keys = {}
		for k in pairs(value) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		local parts = {}
		for _, k in ipairs(keys) do
			parts[#parts + 1] = build.params_to_string(k) .. "=" .. build.params_to_string(value[k])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("params value of type " .. t .. " cannot be sent", 0)
end

--- Parses build.params_to_string. Returns the value, or nil plus an error. A small parser of its
-- own, so a line from the network is never run as Lua code.
function build.params_from_string(text)
	local pos = 1
	local parse
	local function fail(msg) error("params: " .. msg .. " at " .. pos, 0) end
	function parse()
		local c = text:sub(pos, pos)
		if c == "n" then
			local s, e = text:find("^[-%d%.eE+]+", pos + 1)
			if not s then fail("bad number") end
			pos = e + 1
			return tonumber(text:sub(s, e)) or fail("bad number")
		elseif c == "s" then
			local s, e = text:find("^[%w_%.%-%%]*", pos + 1)
			pos = e + 1
			return build.unescape(text:sub(s, e))
		elseif c == "T" or c == "F" then
			pos = pos + 1
			return c == "T"
		elseif c == "{" then
			pos = pos + 1
			local t = {}
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				return t
			end
			while true do
				local k = parse()
				if text:sub(pos, pos) ~= "=" then fail("missing =") end
				pos = pos + 1
				t[k] = parse()
				local sep = text:sub(pos, pos)
				pos = pos + 1
				if sep == "}" then return t end
				if sep ~= "," then fail("missing , or }") end
			end
		end
		fail("unexpected '" .. c .. "'")
	end
	local ok, value = pcall(parse)
	if not ok then return nil, value end
	if pos ~= #text + 1 then return nil, "params: trailing text at " .. pos end
	return value
end

local function list_items(list)
	local items = {}
	local ok, n = pcall(function() return #list end)
	for i = 1, (ok and n or 0) do items[i] = list[i] end
	return items
end
build.list_items = list_items

--- The {entity, side} entries of comp.objects of a segment (empty if unreadable).
local function edge_objects_of(comp)
	local out = {}
	pcall(function()
		local list = comp.objects
		for i = 1, #list do
			local entry = list[i]
			local id, side = entry[1], entry[2]
			if type(id) == "number" then out[#out + 1] = { id, side } end
		end
	end)
	return out
end
build.edge_objects_of = edge_objects_of

--- Turns a captured build into one line (format B4, see docs/phase1-bridge.md).
-- New nodes and segments keep only their position and shape; their engine ids become placeholders
-- -1, -2, ... because the other game creates different ones. Existing things the build touches
-- (nodes it connects to, segments and nodes it removes, constructions it demolishes) are named by
-- their position, which the receiver turns back into its own entities (world.lua).
-- @param proposal userdata param[1].proposal of onPostBuildProposal
-- @param opts table|nil {
--   node_position = function(id) -> {x,y,z} of an existing node,
--   to_add = param[1].toAdd (constructions), to_remove = param[1].toRemove (construction ids),
--   construction = function(id) -> { file, position } of a demolished construction,
--   read_transf = function(transf) -> 16 numbers, or nil and a message,
--   edge_object = function(id, proposal_entry) -> { param, position, model, name, left, oneWay }
--     of a stop/signal on an added segment, or { problem = text },
--   }
-- @return string line, table info { nodes, segments, foreign_nodes, removed_segments,
--   removed_nodes, constructions, demolished, edge_objects, access (entrance segments), gates
--   (their gate nodes), dropped = list of what was left out }
function build.serialize(proposal, opts)
	opts = opts or {}
	local parts = { "B" .. build.VERSION }
	local placeholder = {}
	local road_ids, road_count = {}, 0
	local info = { nodes = 0, segments = 0, foreign_nodes = 0, removed_segments = 0, removed_nodes = 0,
		constructions = 0, demolished = 0, edge_objects = 0, dropped = {} }

	-- Nodes a construction owns (0-based indexes into addedNodes, run 5); the construction
	-- creates them and the segments touching them itself.
	local frozen = {}
	for _, index in ipairs(list_items(proposal.frozenNodes)) do frozen[index + 1] = true end
	local frozen_ids = {}
	local nodes = list_items(proposal.addedNodes)
	for i, node in ipairs(nodes) do
		if frozen[i] then frozen_ids[node.entity] = true end
	end

	-- A segment with both ends frozen belongs to the construction. One with a single frozen end is
	-- the entrance street the build tool laid from the road to the construction's gate (run 19:
	-- template entrance_new.street_template, the gate node frozen in toAdd[i].frozenNodes). Run 17
	-- and 19: built after the construction the game refuses it or finds no node to weld to, so it
	-- travels in the same line, marked "a", with its gate node marked "g". The receiver builds it
	-- together with the construction and then checks and repairs the weld (weld.lua).
	--
	-- v26: a segment from a frozen node to a new node that no other segment of the build touches
	-- leads nowhere. A modular station has one at each track end (run 5: 50154 frozen -> 50460 new),
	-- a depot placed away from roads one at its gate (run 12); the construction lays them itself.
	-- Sent as an entrance they made the copy look unwelded and the receiver refresh or rebuild it.
	local added_ids, touches = {}, {}
	for _, node in ipairs(nodes) do added_ids[node.entity] = true end
	local added_segments = list_items(proposal.addedSegments)
	for _, seg in ipairs(added_segments) do
		local comp = seg.comp
		touches[comp.node0] = (touches[comp.node0] or 0) + 1
		touches[comp.node1] = (touches[comp.node1] or 0) + 1
	end
	local segments, used, access, gates = {}, {}, {}, {}
	for _, seg in ipairs(added_segments) do
		local comp = seg.comp
		local f0, f1 = frozen_ids[comp.node0] == true, frozen_ids[comp.node1] == true
		local free = (f0 and not f1 and comp.node1) or (f1 and not f0 and comp.node0) or nil
		if f0 and f1 then
			info.dropped[#info.dropped + 1] = "segment " .. tostring(seg.entity) .. " (part of a construction)"
		elseif free and added_ids[free] and touches[free] == 1 then
			info.dropped[#info.dropped + 1] = "segment " .. tostring(seg.entity) .. " (end stub of a construction)"
		else
			segments[#segments + 1] = seg
			used[comp.node0], used[comp.node1] = true, true
			if f0 or f1 then
				access[#segments] = true
				gates[f0 and comp.node0 or comp.node1] = true
			end
		end
	end
	info.access = 0
	for _ in pairs(access) do info.access = info.access + 1 end
	local added_position = {}
	for _, node in ipairs(nodes) do
		pcall(function()
			local v = node.comp.position
			added_position[node.entity] = { x = v.x, y = v.y, z = v.z }
		end)
	end

	local count = 0
	for _, node in ipairs(nodes) do
		if used[node.entity] then
			count = count + 1
			placeholder[node.entity] = -count
			parts[#parts + 1] = "n" .. (-count) .. ";" .. vec_to_string(node.comp.position)
		end
	end
	info.nodes = count
	info.gates = 0
	for _, node in ipairs(nodes) do
		if gates[node.entity] and placeholder[node.entity] then
			info.gates = info.gates + 1
			parts[#parts + 1] = "g;" .. placeholder[node.entity]
		end
	end

	local foreign, foreign_count = {}, 0
	local function node_ref(id)
		if placeholder[id] then return placeholder[id] end
		if not foreign[id] then
			local p = (opts.node_position and opts.node_position(id)) or added_position[id]
			if not p then error("existing node " .. tostring(id) .. " has no position", 0) end
			foreign_count = foreign_count + 1
			foreign[id] = foreign_count
			parts[#parts + 1] = "f" .. foreign_count .. ";" .. vec_to_string(p)
		end
		return "f" .. foreign[id]
	end

	-- Objects that were on a removed segment already existed; all others are new in this build.
	local kept_objects = {}
	for _, seg in ipairs(list_items(proposal.removedSegments)) do
		for _, entry in ipairs(edge_objects_of(seg.comp)) do kept_objects[entry[1]] = true end
	end
	-- What the proposal says about its new objects (left side, name, model), by result entity and
	-- in order, because it is not known whether resultEntity holds the final id.
	local new_objects = { by_order = {} }
	for _, eo in ipairs(list_items(proposal.edgeObjectsToAdd)) do
		local entry = {}
		pcall(function() entry.left = eo.left end)
		pcall(function() entry.name = eo.name end)
		pcall(function() entry.category = eo.category end)
		pcall(function() entry.modelId = eo.modelInstance.modelId end)
		local ok, result = pcall(function() return eo.resultEntity end)
		if ok and result ~= nil then new_objects[result] = entry end
		new_objects.by_order[#new_objects.by_order + 1] = entry
	end
	local placed_new = {}
	for i, seg in ipairs(segments) do
		local comp = seg.comp
		local n0, n1 = node_ref(comp.node0), node_ref(comp.node1)
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
		-- Stops, waypoints and signals on the segment (v15). TF3 places one by removing the edge and
		-- adding it again with the object in comp.objects (run 14). Each object travels with its
		-- position, so the receiver can tell its own existing objects from new ones.
		for _, entry in ipairs(edge_objects_of(comp)) do
			local id, side = entry[1], entry[2]
			local is_new = not kept_objects[id]
			local from_proposal = nil
			if is_new then
				from_proposal = new_objects[id] or new_objects.by_order[#placed_new + 1]
				placed_new[#placed_new + 1] = id
			end
			local o = opts.edge_object and opts.edge_object(id, from_proposal)
			if not o or not o.position or type(o.model) ~= "string" or o.model == "" then
				info.dropped[#info.dropped + 1] = "stop/signal " .. tostring(id) .. " on segment " ..
					tostring(seg.entity) .. " (" .. tostring(o and o.problem or "no data") .. ")"
			else
				local flags = (is_new and "n" or "") .. (o.left and "l" or "") .. (o.oneWay and "w" or "")
				info.edge_objects = info.edge_objects + 1
				parts[#parts + 1] = table.concat({ "o", i, tostring(side), num(o.param or 0.5),
					vec_to_string(o.position), build.escape(o.model), build.escape(o.name or ""),
					flags == "" and "-" or flags }, ";")
			end
		end
	end
	info.foreign_nodes = foreign_count
	local access_list = {}
	for i in pairs(access) do access_list[#access_list + 1] = i end
	table.sort(access_list)
	for _, i in ipairs(access_list) do parts[#parts + 1] = "a;" .. i end

	-- Removed nodes: their positions are only in the proposal, the entities are gone.
	local removed_position = {}
	for _, node in ipairs(list_items(proposal.removedNodes)) do
		local ok, p = pcall(function()
			local v = node.comp.position
			return { x = v.x, y = v.y, z = v.z }
		end)
		if ok then
			removed_position[node.entity] = p
			info.removed_nodes = info.removed_nodes + 1
			parts[#parts + 1] = "x;" .. vec_to_string(p)
		end
	end
	local function position_of(id)
		return removed_position[id] or (opts.node_position and opts.node_position(id))
	end
	local function end_position(comp, key)
		local ok, p = pcall(function()
			local v = comp[key]
			return { x = v.x, y = v.y, z = v.z }
		end)
		if ok and type(p.x) == "number" then return p end
		return nil
	end
	for _, seg in ipairs(list_items(proposal.removedSegments)) do
		local comp = seg.comp
		-- Run 14: an end node can be gone already, but the removed segment keeps position0/1.
		local p0 = end_position(comp, "position0") or position_of(comp.node0)
		local p1 = end_position(comp, "position1") or position_of(comp.node1)
		if not p0 or not p1 then error("removed segment " .. tostring(seg.entity) .. " has no node positions", 0) end
		info.removed_segments = info.removed_segments + 1
		parts[#parts + 1] = "r;" .. vec_to_string(p0) .. ";" .. vec_to_string(p1) .. ";" .. tostring(seg.type)
	end

	for _, con in ipairs(list_items(opts.to_add)) do
		local m, how = (opts.read_transf or build.read_transf)(con.transf)
		if not m then error("construction " .. tostring(con.fileName) .. ": transf unreadable (" .. tostring(how) .. ")", 0) end
		local numbers = {}
		for i = 1, 16 do numbers[i] = fine(m[i]) end
		local params = build.params_to_string(con.params)
		info.constructions = info.constructions + 1
		parts[#parts + 1] = table.concat({ "c", build.escape(con.fileName), build.escape(con.name or ""),
			table.concat(numbers, ","), params }, ";")
	end
	for _, id in ipairs(list_items(opts.to_remove)) do
		local con = opts.construction and opts.construction(id)
		-- Run 16: a town building the player tears down is not in the cache of player buildings.
		if not con then
			info.dropped[#info.dropped + 1] = "demolished construction " .. tostring(id) .. " (not a known player building)"
			goto continue
		end
		info.demolished = info.demolished + 1
		parts[#parts + 1] = "d;" .. build.escape(con.file) .. ";" .. vec_to_string(con.position)
		::continue::
	end

	local line = table.concat(parts, " ")
	-- The build itself must travel even if its node configurations cannot be read.
	local ok_c, config_tokens = pcall(build.serialize_configs, proposal, opts, info, list_items(proposal.addedSegments),
		added_position)
	if not ok_c then
		info.dropped[#info.dropped + 1] = "node configs (" .. tostring(config_tokens):sub(1, 120) .. ")"
		info.node_configs, config_tokens = 0, {}
	end
	if #config_tokens > 0 then
		local text = table.concat(config_tokens, " ")
		if #line + 1 + #text > build.CONFIG_LINE_LIMIT then
			info.dropped[#info.dropped + 1] = info.node_configs .. " node configs (line would be " ..
				(#line + 1 + #text) .. " characters)"
			info.node_configs = 0
		else
			line = line .. " " .. text
		end
	end
	return line, info
end

--- Node configurations (v21). TF3 keeps the lane connections, crosswalks and traffic light setup of
-- a street node in a BaseNodeConfig, and a player's build hands one per node it touches to the game
-- in proposal.nodeConfigsToAdd (run 20b: six for a road of six nodes). A copy without them has
-- nodes nothing can drive through, and clicking such a junction breaks the game's window
-- ("attempt to index local 'baseNodeConfig' (a nil value)", double_slip_switch.tl).
-- They travel by position, like everything else: the node, and each segment a connection or
-- crosswalk names, by the positions of its two end nodes ("e" tokens). The receiver applies them
-- after the build (nodecfg.lua), when every segment has its id in that game, including the ones a
-- construction lays itself.
build.CONFIG_LINE_LIMIT = 14000

--- Reads a number field that may come as a number, boolean or enum value.
local function int_of(v)
	if type(v) == "number" then return v end
	if type(v) == "boolean" then return v and 1 or 0 end
	local n = tonumber(tostring(v))
	if n then return n end
	error("not a number: " .. tostring(v), 0)
end

--- One entry of nodeConfigsToAdd as a plain table: { node, conns = {{s0, l0, s1, l1, road, tram}},
-- walks = {segment ids}, pref, double, lanes_modified, states_modified, tltype, states = {{duration,
-- min, skip, lanes}} }. Raises when a required field cannot be read.
function build.read_node_config(entry)
	local comp = entry.comp
	local c = { node = entry.entity, conns = {}, walks = {}, states = {} }
	for _, lc in ipairs(list_items(comp.laneConnections)) do
		c.conns[#c.conns + 1] = { s0 = lc.segment0, l0 = int_of(lc.lane0), s1 = lc.segment1, l1 = int_of(lc.lane1),
			road = lc.withRoad == true, tram = lc.withTram == true }
	end
	for _, w in ipairs(list_items(comp.crosswalks)) do c.walks[#c.walks + 1] = w end
	c.pref = 2
	pcall(function() c.pref = int_of(comp.trafficLightPreference) end)
	pcall(function() c.double = comp.doubleSlipSwitch == true end)
	pcall(function() c.lanes_modified = comp.userModifiedLaneConnections == true end)
	pcall(function() c.states_modified = comp.userModifiedTrafficLightStates == true end)
	c.tltype = -1
	pcall(function()
		local tlc = comp.trafficLightConfig
		c.tltype = int_of(tlc.trafficLightType)
		for _, st in ipairs(list_items(tlc.states)) do
			local lanes = {}
			pcall(function()
				for _, l in ipairs(list_items(st.lockedLanes)) do lanes[#lanes + 1] = int_of(l) end
			end)
			c.states[#c.states + 1] = { duration = st.duration or 0, min = st.minDuration or 0,
				skip = st.canSkip == true, lanes = lanes }
		end
	end)
	return c
end

--- The "e" and "k" tokens of a build's node configurations (see above).
-- @param segments list of the proposal's addedSegments
-- @param added_position table node id -> position of the added nodes
function build.serialize_configs(proposal, opts, info, segments, added_position)
	info.node_configs, info.config_removes = 0, 0
	pcall(function() info.config_removes = #list_items(proposal.nodeConfigsToRemove) end)
	local entries = {}
	pcall(function() entries = list_items(proposal.nodeConfigsToAdd) end)
	if #entries == 0 then return {} end
	local seg_nodes = {}
	for _, seg in ipairs(segments) do
		pcall(function() seg_nodes[seg.entity] = { seg.comp.node0, seg.comp.node1 } end)
	end
	local function node_pos(id)
		return added_position[id] or (opts.node_position and opts.node_position(id))
	end
	local function ends_of(id)
		local pair = seg_nodes[id]
		if pair then
			local p0, p1 = node_pos(pair[1]), node_pos(pair[2])
			if p0 and p1 then return p0, p1 end
		end
		if opts.segment_ends then return opts.segment_ends(id) end
		return nil
	end
	local tokens, seg_index, seg_tokens = {}, {}, {}
	local function seg_ref(id)
		if seg_index[id] then return seg_index[id] end
		local p0, p1 = ends_of(id)
		if not p0 or not p1 then error("segment " .. tostring(id) .. " has no end positions", 0) end
		local k = #seg_tokens + 1
		seg_index[id] = k
		seg_tokens[k] = "e" .. k .. ";" .. vec_to_string(p0) .. ";" .. vec_to_string(p1)
		return k
	end
	local config_tokens = {}
	for _, entry in ipairs(entries) do
		local ok, token = pcall(function()
			local c = build.read_node_config(entry)
			local pos = node_pos(c.node)
			if not pos then error("node " .. tostring(c.node) .. " has no position", 0) end
			local conns = {}
			for _, lc in ipairs(c.conns) do
				local flags = (lc.road and "r" or "") .. (lc.tram and "t" or "")
				conns[#conns + 1] = table.concat({ seg_ref(lc.s0), num(lc.l0), seg_ref(lc.s1), num(lc.l1),
					flags == "" and "-" or flags }, ":")
			end
			local walks = {}
			for _, w in ipairs(c.walks) do walks[#walks + 1] = seg_ref(w) end
			local states = {}
			for _, st in ipairs(c.states) do
				local lanes = {}
				for _, l in ipairs(st.lanes) do lanes[#lanes + 1] = num(l) end
				states[#states + 1] = table.concat({ num(st.duration), num(st.min), st.skip and "T" or "F",
					#lanes > 0 and table.concat(lanes, "+") or "-" }, ":")
			end
			local flags = (c.double and "d" or "") .. (c.lanes_modified and "l" or "") .. (c.states_modified and "t" or "")
			return table.concat({ "k", vec_to_string(pos), flags == "" and "-" or flags, num(c.pref), num(c.tltype),
				#conns > 0 and table.concat(conns, ",") or "-", #walks > 0 and table.concat(walks, ",") or "-",
				#states > 0 and table.concat(states, ",") or "-" }, ";")
		end)
		if ok then
			config_tokens[#config_tokens + 1] = token
			info.node_configs = info.node_configs + 1
		else
			info.dropped[#info.dropped + 1] = "node config " .. tostring(entry.entity) .. " (" .. tostring(token) .. ")"
		end
	end
	for _, t in ipairs(seg_tokens) do tokens[#tokens + 1] = t end
	for _, t in ipairs(config_tokens) do tokens[#tokens + 1] = t end
	return tokens
end

local function node_ref_from_string(text)
	local f = string.match(text, "^f(%d+)$")
	if f then return "f" .. f end
	return tonumber(text)
end

--- Parses a line produced by build.serialize.
-- @return table|nil data { version, nodes = {{id, position}}, foreign = {[k] = position},
--   segments = {{id, type, node0, node1 (number or "f<k>"), tangent0, tangent1, typeIndex, roadType,
--   distance, roadTemplate, roadStyle, lanes, params, streetEdge}}, removed_segments = {{p0, p1,
--   type}}, removed_nodes = {position}, constructions = {{file, name, transf, params}},
--   demolished = {{file, position}} }, or nil plus an error message
function build.deserialize(line)
	if type(line) ~= "string" then return nil, "not a string" end
	local data = { nodes = {}, foreign = {}, segments = {}, removed_segments = {}, removed_nodes = {},
		constructions = {}, demolished = {}, objects = {}, access = {}, gates = {}, configs = {},
		config_segments = {} }
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
		elseif kind == "f" then
			local id, pos = string.match(token, "^f(%d+);(.+)$")
			local position = id and vec_from_string(pos)
			if not position then return nil, "bad existing node token " .. token end
			data.foreign["f" .. id] = position
		elseif kind == "x" then
			local position = vec_from_string(token:sub(3))
			if not position then return nil, "bad removed node token " .. token end
			data.removed_nodes[#data.removed_nodes + 1] = position
		elseif kind == "r" then
			local a, b, t = string.match(token, "^r;([^;]+);([^;]+);(%d+)$")
			local p0, p1 = a and vec_from_string(a), b and vec_from_string(b)
			if not p0 or not p1 then return nil, "bad removed segment token " .. token end
			data.removed_segments[#data.removed_segments + 1] = { p0 = p0, p1 = p1, type = tonumber(t) }
		elseif kind == "c" then
			local file, name, numbers, params_text = string.match(token, "^c;([^;]+);([^;]*);([^;]+);([^;]+)$")
			if not file then return nil, "bad construction token " .. token:sub(1, 80) end
			local transf = {}
			for n in string.gmatch(numbers, "[^,]+") do transf[#transf + 1] = tonumber(n) end
			if #transf ~= 16 then return nil, "bad construction transf " .. numbers end
			local params, err = build.params_from_string(params_text)
			if err then return nil, err end
			data.constructions[#data.constructions + 1] = {
				file = build.unescape(file), name = build.unescape(name), transf = transf, params = params,
			}
		elseif kind == "d" then
			local file, pos = string.match(token, "^d;([^;]+);([^;]+)$")
			local position = pos and vec_from_string(pos)
			if not position then return nil, "bad demolish token " .. token end
			data.demolished[#data.demolished + 1] = { file = build.unescape(file), position = position }
		elseif kind == "a" then
			local i = string.match(token, "^a;(%d+)$")
			if not i then return nil, "bad access token " .. token end
			data.access[-tonumber(i)] = true
		elseif kind == "g" then
			local id = string.match(token, "^g;(%-%d+)$")
			if not id then return nil, "bad gate token " .. token end
			data.gates[tonumber(id)] = true
		elseif kind == "e" then
			local k, a, b = string.match(token, "^e(%d+);([^;]+);([^;]+)$")
			local p0, p1 = a and vec_from_string(a), b and vec_from_string(b)
			if not p0 or not p1 then return nil, "bad config segment token " .. token end
			data.config_segments[tonumber(k)] = { p0 = p0, p1 = p1 }
		elseif kind == "k" then
			local c, err = build.parse_config(token)
			if not c then return nil, err end
			data.configs[#data.configs + 1] = c
		elseif kind == "o" then
			local seg, side, param, pos, model, name, flags =
				string.match(token, "^o;(%d+);(%-?%d+);([^;]+);([^;]+);([^;]+);([^;]*);([^;]+)$")
			local position = pos and vec_from_string(pos)
			if not position or not tonumber(param) then return nil, "bad stop/signal token " .. token:sub(1, 80) end
			data.objects[#data.objects + 1] = {
				segment = -tonumber(seg), side = tonumber(side), param = tonumber(param), position = position,
				model = build.unescape(model), name = build.unescape(name), new = flags:find("n", 1, true) ~= nil,
				left = flags:find("l", 1, true) ~= nil, oneWay = flags:find("w", 1, true) ~= nil,
			}
		elseif kind == "s" then
			local fields = {}
			for field in string.gmatch(token:sub(2), "[^;]+") do fields[#fields + 1] = field end
			if #fields ~= 12 then return nil, "bad segment token " .. token end
			local road = roads[tonumber(fields[10])]
			if not road then return nil, "unknown road type in " .. token end
			local t0, t1 = vec_from_string(fields[5]), vec_from_string(fields[6])
			if not t0 or not t1 then return nil, "bad tangent in " .. token end
			local n0, n1 = node_ref_from_string(fields[3]), node_ref_from_string(fields[4])
			if not n0 or not n1 then return nil, "bad node in " .. token end
			data.segments[#data.segments + 1] = {
				id = tonumber(fields[1]),
				type = tonumber(fields[2]),
				node0 = n0,
				node1 = n1,
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
	for id in pairs(data.gates) do
		local found = false
		for _, node in ipairs(data.nodes) do
			if node.id == id then found = true end
		end
		if not found then return nil, "gate on unknown node " .. id end
	end
	for _, o in ipairs(data.objects) do
		local found = false
		for _, seg in ipairs(data.segments) do
			if seg.id == o.segment then found = true end
		end
		if not found then return nil, "stop/signal on unknown segment " .. o.segment end
	end
	for _, seg in ipairs(data.segments) do
		for _, ref in ipairs({ seg.node0, seg.node1 }) do
			if type(ref) == "string" and not data.foreign[ref] then return nil, "unknown existing node " .. ref end
		end
	end
	for _, c in ipairs(data.configs) do
		for k in pairs(build.config_refs(c)) do
			if not data.config_segments[k] then return nil, "node config names unknown segment e" .. k end
		end
	end
	return data
end

--- Parses one "k" token (see build.serialize_configs).
-- @return table { position, double, lanes_modified, states_modified, pref, tltype, conns = {{a, l0,
--   b, l1, road, tram}} (a, b = "e" token numbers), walks = {numbers}, states = {{duration, min, skip,
--   lanes}} }, or nil and an error message
function build.parse_config(token)
	local fields = {}
	for field in string.gmatch(token, "[^;]+") do fields[#fields + 1] = field end
	if #fields ~= 8 or fields[1] ~= "k" then return nil, "bad node config token " .. token:sub(1, 80) end
	local position = vec_from_string(fields[2])
	local pref, tltype = tonumber(fields[4]), tonumber(fields[5])
	if not position or not pref or not tltype then return nil, "bad node config token " .. token:sub(1, 80) end
	local flags = fields[3]
	local c = { position = position, pref = pref, tltype = tltype, conns = {}, walks = {}, states = {},
		double = flags:find("d", 1, true) ~= nil, lanes_modified = flags:find("l", 1, true) ~= nil,
		states_modified = flags:find("t", 1, true) ~= nil }
	if fields[6] ~= "-" then
		for item in string.gmatch(fields[6], "[^,]+") do
			local a, l0, b, l1, f = string.match(item, "^(%d+):(%-?%d+):(%d+):(%-?%d+):([%-rt]+)$")
			if not a then return nil, "bad lane connection " .. item end
			c.conns[#c.conns + 1] = { a = tonumber(a), l0 = tonumber(l0), b = tonumber(b), l1 = tonumber(l1),
				road = f:find("r", 1, true) ~= nil, tram = f:find("t", 1, true) ~= nil }
		end
	end
	if fields[7] ~= "-" then
		for item in string.gmatch(fields[7], "[^,]+") do
			local k = tonumber(item)
			if not k then return nil, "bad crosswalk " .. item end
			c.walks[#c.walks + 1] = k
		end
	end
	if fields[8] ~= "-" then
		for item in string.gmatch(fields[8], "[^,]+") do
			local d, m, skip, lanes_text = string.match(item, "^([^:]+):([^:]+):([TF]):([^:]+)$")
			if not d or not tonumber(d) or not tonumber(m) then return nil, "bad traffic light state " .. item end
			local lanes = {}
			if lanes_text ~= "-" then
				for l in string.gmatch(lanes_text, "[^+]+") do lanes[#lanes + 1] = tonumber(l) end
			end
			c.states[#c.states + 1] = { duration = tonumber(d), min = tonumber(m), skip = skip == "T", lanes = lanes }
		end
	end
	return c
end

--- The "e" token numbers a parsed node config names, as a set.
function build.config_refs(c)
	local refs = {}
	for _, lc in ipairs(c.conns) do refs[lc.a], refs[lc.b] = true, true end
	for _, w in ipairs(c.walks) do refs[w] = true end
	return refs
end

--- Turns the existing things a parsed line names by position into this game's entities.
-- Segment node references "f<k>" become entity ids; removed segments, removed nodes and
-- demolished constructions get `entity`. A removed segment or demolished construction that is not
-- found makes the whole build fail (TF2 multiplayer mod: building without removing would double
-- the road); a removed node that is not found is left out (the street graph cleanup removes it).
-- @param finder table { find_node = function(position) -> id, find_edge = function(a, b) -> id,
--   find_construction = function(file, position) -> id, edge_objects_of = function(edge) ->
--   {{id, side, position}} (optional) }
-- @return boolean ok, string|nil what could not be found, table notes
build.OBJECT_RADIUS = 3

function build.resolve(data, finder)
	local notes = {}
	local ids = {}
	for ref, position in pairs(data.foreign) do
		local id = finder.find_node(position)
		if not id then
			return false, string.format("joins a road or track that does not exist here (node near %.1f,%.1f)",
				position.x, position.y), notes
		end
		ids[ref] = id
	end
	data.positions_of = {}
	for ref, id in pairs(ids) do data.positions_of[id] = data.foreign[ref] end
	for _, seg in ipairs(data.segments) do
		if type(seg.node0) == "string" then seg.node0 = ids[seg.node0] end
		if type(seg.node1) == "string" then seg.node1 = ids[seg.node1] end
	end
	-- Demolished constructions first: the game removes their own connecting segments itself, and
	-- naming such a segment again makes it assert (run 15, StreetProposal::RemoveSegment).
	for _, d in ipairs(data.demolished) do
		d.entity = finder.find_construction(d.file, d.position)
		if not d.entity then
			return false, "demolishes " .. d.file .. " which does not exist here", notes
		end
	end
	local demolished = {}
	for _, d in ipairs(data.demolished) do demolished[d.entity] = true end
	local kept_removed, dropped_nodes, missing_ends = {}, {}, {}
	for _, r in ipairs(data.removed_segments) do
		local a, b = finder.find_node(r.p0), finder.find_node(r.p1)
		r.entity = a and b and a ~= b and finder.find_edge(a, b) or nil
		local owner = r.entity and finder.edge_construction and finder.edge_construction(r.entity)
		if r.entity and owner and demolished[owner] then
			notes[#notes + 1] = "removed segment belongs to a demolished construction, the game removes it"
			dropped_nodes[a], dropped_nodes[b] = true, true
		elseif not r.entity and #data.demolished > 0 then
			-- Run 15: a depot's own access segment lies a little differently in the copy. Its end
			-- nodes stay too (run 16: removing one that is still used asserts).
			missing_ends[#missing_ends + 1] = r.p0
			missing_ends[#missing_ends + 1] = r.p1
			notes[#notes + 1] = string.format("removed segment %.1f,%.1f to %.1f,%.1f not found; left to the demolished construction",
				r.p0.x, r.p0.y, r.p1.x, r.p1.y)
		elseif not r.entity then
			return false, string.format("removes a road or track that does not exist here (%.1f,%.1f to %.1f,%.1f)",
				r.p0.x, r.p0.y, r.p1.x, r.p1.y), notes
		else
			local twice = false
			for _, k in ipairs(kept_removed) do if k.entity == r.entity then twice = true end end
			if twice then
				notes[#notes + 1] = "segment named twice for removal, kept once"
			else
				kept_removed[#kept_removed + 1] = r
			end
		end
	end
	data.removed_segments = kept_removed
	-- Stops and signals: objects on the edges removed here either come back (same position) or
	-- were removed by the other player. A sent object that is not here yet is added.
	data.objects_to_remove = {}
	if finder.edge_objects_of then
		local here = {}
		for _, r in ipairs(data.removed_segments) do
			for _, o in ipairs(finder.edge_objects_of(r.entity) or {}) do
				-- Without its position an object could only be dropped by mistake.
				if not o.position then return false, "cannot read the position of stop/signal " .. tostring(o.id), notes end
				here[#here + 1] = o
			end
		end
		local taken = {}
		for _, o in ipairs(data.objects or {}) do
			local best, best_d = nil, nil
			for k, h in ipairs(here) do
				if not taken[k] and h.position then
					local dx, dy = h.position.x - o.position.x, h.position.y - o.position.y
					local d = dx * dx + dy * dy
					if d <= build.OBJECT_RADIUS * build.OBJECT_RADIUS and (not best_d or d < best_d) then
						best, best_d = k, d
					end
				end
			end
			if best then
				taken[best] = true
				o.entity = here[best].id
			end
		end
		for k, h in ipairs(here) do
			if not taken[k] then data.objects_to_remove[#data.objects_to_remove + 1] = h.id end
		end
	end
	local removed_node_ids = {}
	for _, n in ipairs(data.removed_nodes) do
		n.entity = finder.find_node(n)
		if not n.entity then
			notes[#notes + 1] = string.format("removed node near %.1f,%.1f not found", n.x, n.y)
		elseif dropped_nodes[n.entity] or removed_node_ids[n.entity] then
			n.entity = nil
		elseif (function()
			for _, p in ipairs(missing_ends) do
				if math.abs(p.x - n.x) <= 1.5 and math.abs(p.y - n.y) <= 1.5 then return true end
			end
			return false
		end)() then
			n.entity = nil
		else
			removed_node_ids[n.entity] = true
		end
	end
	return true, nil, notes
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
build.try_set, build.update = try_set, update

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
		fill = function(p, nodes, edges, errors, extra)
			extra = extra or {}
			update(p, "streetProposal", function(sp)
				try_set(sp, "nodesToAdd", nodes, errors, "streetProposal.nodesToAdd")
				try_set(sp, "edgesToAdd", edges, errors, "streetProposal.edgesToAdd")
				-- Removals are entity ids of this game (TF2 multiplayer mod: edgesToRemove/nodesToRemove).
				if extra.edges_to_remove and #extra.edges_to_remove > 0 then
					try_set(sp, "edgesToRemove", extra.edges_to_remove, errors, "streetProposal.edgesToRemove")
				end
				if extra.nodes_to_remove and #extra.nodes_to_remove > 0 then
					try_set(sp, "nodesToRemove", extra.nodes_to_remove, errors, "streetProposal.nodesToRemove")
				end
				if extra.objects_to_add and #extra.objects_to_add > 0 then
					try_set(sp, "edgeObjectsToAdd", extra.objects_to_add, errors, "streetProposal.edgeObjectsToAdd")
				end
				if extra.objects_to_remove and #extra.objects_to_remove > 0 then
					try_set(sp, "edgeObjectsToRemove", extra.objects_to_remove, errors, "streetProposal.edgeObjectsToRemove")
				end
				if extra.configs_to_remove and #extra.configs_to_remove > 0 then
					try_set(sp, "nodeConfigsToRemove", extra.configs_to_remove, errors, "streetProposal.nodeConfigsToRemove")
				end
			end, errors, "streetProposal")
			if extra.constructions and #extra.constructions > 0 then
				try_set(p, "constructionsToAdd", extra.constructions, errors, "constructionsToAdd")
			end
			if extra.constructions_to_remove and #extra.constructions_to_remove > 0 then
				try_set(p, "constructionsToRemove", extra.constructions_to_remove, errors, "constructionsToRemove")
			end
			if extra.old2new and next(extra.old2new) ~= nil then
				try_set(p, "old2new", extra.old2new, errors, "old2new")
			end
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

--- How new stops/signals are numbered in a proposal; not documented for TF3, so build.replay
-- tries each.
-- Run 15: TF3 asserts "EdgeObjectEntityToIndex: entity.GetId() <= -400000000 && > -500000000", so
-- new edge objects live in their own id range; whether the first is -400000000 or -400000001 is
-- tried.
build.OBJECT_NUMBERINGS = { "range0", "range1" }
build.OBJECT_ID_BASE = -400000000

--- Gives every sent stop/signal its id in this proposal: the local entity when it already exists
-- here (build.resolve), otherwise a placeholder by data.object_numbering. Returns the new ones.
function build.number_objects(data)
	local added = {}
	for _, o in ipairs(data.objects or {}) do
		if o.entity then
			o.proposal_id = o.entity
		else
			added[#added + 1] = o
			if data.object_numbering == "range1" then
				o.proposal_id = build.OBJECT_ID_BASE - #added
			else
				o.proposal_id = build.OBJECT_ID_BASE - (#added - 1)
			end
		end
	end
	return added
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
		local objects = {}
		for _, o in ipairs(data.objects or {}) do
			if o.segment == seg.id and o.proposal_id then objects[#objects + 1] = { o.proposal_id, o.side } end
		end
		if #objects > 0 then try_set(comp, "objects", objects, errors, "edge.comp.objects") end
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
	for id, p in pairs(data.positions_of or {}) do positions[id] = p end
	local added_objects = build.number_objects(data)
	local nodes, edges = {}, {}
	for _, node in ipairs(data.nodes) do nodes[#nodes + 1] = build.make_node(api, data, node, errors) end
	for _, seg in ipairs(data.segments) do
		edges[#edges + 1] = build.make_segment(api, data, seg, positions, player, errors)
	end
	if list_kind == "vector" then
		nodes = build.to_vector(api, "Vector_NodeAndEntity", nodes)
		edges = build.to_vector(api, "Vector_SegmentAndEntity", edges)
	end
	-- v23 (run 22): existing nodes whose configuration names a segment this build removes or that get
	-- a new segment lose it in the same proposal; nodecfg.lua sets the sent one after the build.
	local extra = { edges_to_remove = {}, nodes_to_remove = {}, constructions = {}, constructions_to_remove = {},
		objects_to_add = {}, objects_to_remove = data.objects_to_remove or {},
		configs_to_remove = data.configs_to_remove or {} }
	for i, o in ipairs(added_objects) do
		extra.objects_to_add[i] = build.make_edge_object(api, o, player, errors, "edgeObject[" .. i .. "]")
	end
	for _, r in ipairs(data.removed_segments or {}) do extra.edges_to_remove[#extra.edges_to_remove + 1] = r.entity end
	for _, n in ipairs(data.removed_nodes or {}) do
		if n.entity then extra.nodes_to_remove[#extra.nodes_to_remove + 1] = n.entity end
	end
	for i, c in ipairs(data.constructions or {}) do
		extra.constructions[i] = build.make_construction(api, c, player, errors, "construction[" .. i .. "]")
	end
	for _, d in ipairs(data.demolished or {}) do
		extra.constructions_to_remove[#extra.constructions_to_remove + 1] = d.entity
	end
	extra.old2new = build.old2new(data)
	local proposal = layout.new(api.type)
	layout.fill(proposal, nodes, edges, errors, extra)
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
	local check = build.check(layout, proposal, data)
	-- Removals and constructions read back as well; a list the proposal dropped must not be sent.
	local readback = {
		{ "edgesToRemove", #extra.edges_to_remove, function() return proposal.streetProposal.edgesToRemove end },
		{ "nodesToRemove", #extra.nodes_to_remove, function() return proposal.streetProposal.nodesToRemove end },
		{ "constructionsToAdd", #extra.constructions, function() return proposal.constructionsToAdd end },
		{ "constructionsToRemove", #extra.constructions_to_remove, function() return proposal.constructionsToRemove end },
		{ "edgeObjectsToAdd", #extra.objects_to_add, function() return proposal.streetProposal.edgeObjectsToAdd end },
		{ "edgeObjectsToRemove", #extra.objects_to_remove, function() return proposal.streetProposal.edgeObjectsToRemove end },
		{ "nodeConfigsToRemove", #extra.configs_to_remove, function() return proposal.streetProposal.nodeConfigsToRemove end },
	}
	local want_objects = 0
	for _, o in ipairs(data.objects or {}) do if o.proposal_id then want_objects = want_objects + 1 end end
	if want_objects > 0 then
		local ok, n = pcall(function()
			local list, total = proposal.streetProposal.edgesToAdd, 0
			for i = 1, #list do total = total + count(list[i].comp.objects) end
			return total
		end)
		n = ok and n or 0
		check.text = check.text .. ", objects on edges " .. n .. "/" .. want_objects
		if n ~= want_objects then check.complete = false end
	end
	for _, r in ipairs(readback) do
		if r[2] > 0 then
			local ok, list = pcall(r[3])
			local n = ok and count(list) or 0
			check.text = check.text .. ", " .. r[1] .. " " .. n .. "/" .. r[2]
			if n ~= r[2] then check.complete = false end
		end
	end
	-- Only reported: a proposal without old2new still builds (the station then counts as new).
	local want_pairs = 0
	for _ in pairs(extra.old2new) do want_pairs = want_pairs + 1 end
	if want_pairs > 0 then
		local ok, n = pcall(function()
			local total = 0
			for _ in pairs(proposal.old2new) do total = total + 1 end
			return total
		end)
		check.text = check.text .. ", old2new " .. (ok and tostring(n) or "?") .. "/" .. want_pairs
	end
	return proposal, check, unique
end

--- Creates the api.type.SimpleStreetProposal.EdgeObject for a new stop/signal (tealdef: edgeEntity
-- is the new segment's placeholder, param 0..1 along it, model a resource name).
function build.make_edge_object(api, o, player, errors, label)
	local eo = api.type.SimpleStreetProposal.EdgeObject.new()
	try_set(eo, "edgeEntity", o.segment, errors, label .. ".edgeEntity")
	try_set(eo, "param", o.param, errors, label .. ".param")
	try_set(eo, "oneWay", o.oneWay and true or false, errors, label .. ".oneWay")
	try_set(eo, "left", o.left and true or false, errors, label .. ".left")
	try_set(eo, "model", o.model, errors, label .. ".model")
	if player then try_set(eo, "playerEntity", player, errors, label .. ".playerEntity") end
	try_set(eo, "name", o.name or "", errors, label .. ".name")
	return eo
end

--- Creates the api.type.SimpleProposal.ConstructionEntity for one parsed construction. The
-- transformation is tried as api.type.Mat4f of four Vec4f columns (TF2), as a plain list of 16
-- numbers, and by changing the entity's own matrix; each attempt is read back.
function build.make_construction(api, c, player, errors, label)
	local entry = api.type.SimpleProposal.ConstructionEntity.new()
	try_set(entry, "fileName", c.file, errors, label .. ".fileName")
	-- TF2 multiplayer mod: without a name the construction's children crash the GUI on click.
	try_set(entry, "name", c.name or "", errors, label .. ".name")
	try_set(entry, "params", c.params, errors, label .. ".params")
	if player then try_set(entry, "playerEntity", player, errors, label .. ".playerEntity") end
	local t = c.transf
	local function matches()
		local ok, m = pcall(function() return build.read_transf(entry.transf) end)
		if not ok or not m then return false end
		for i = 1, 16 do
			if math.abs(m[i] - t[i]) > 0.01 then return false end
		end
		return true
	end
	local attempts = {
		function()
			local v = api.type.Vec4f
			entry.transf = api.type.Mat4f.new(v.new(t[1], t[2], t[3], t[4]), v.new(t[5], t[6], t[7], t[8]),
				v.new(t[9], t[10], t[11], t[12]), v.new(t[13], t[14], t[15], t[16]))
		end,
		function() entry.transf = { t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12],
			t[13], t[14], t[15], t[16] } end,
		function()
			local m = entry.transf
			for i = 1, 16 do m[i] = t[i] end
			entry.transf = m
		end,
	}
	local failed = {}
	for i, attempt in ipairs(attempts) do
		local ok, err = pcall(attempt)
		if ok and matches() then return entry end
		failed[#failed + 1] = "way " .. i .. ": " .. (ok and "reads back different" or tostring(err):sub(1, 60))
	end
	errors[#errors + 1] = label .. ".transf: " .. table.concat(failed, "; ")
	return entry
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
-- @param prepare function|nil called with the command before it is sent (v20: to read the full
--   Proposal the game made of a SimpleProposal); its errors are logged, never raised
-- @return boolean ok, string message
function build.send(env, proposal, log, on_result, player, prepare)
	local api = env.api
	local context = nil
	pcall(function() context = build.make_context(env, player) end)
	for i, make_args in ipairs(build.CMD_ARGS) do
		local ok, err = pcall(function()
			local args = make_args(proposal, context)
			local cmd = api.cmd.makeWorldBuildProposalCmd(args[1], args[2], args[3])
			if prepare then
				local ok_p, err_p = pcall(prepare, cmd)
				if not ok_p and log then log("prepare: " .. tostring(err_p):sub(1, 200)) end
			end
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

--- Moves everything in parsed data by (dx, dy): new and existing nodes, removals and
-- constructions. Only for the single-PC test, where the copy has to appear next to the original.
function build.offset(data, dx, dy)
	local function move(p)
		p.x = p.x + dx
		p.y = p.y + dy
	end
	for _, node in ipairs(data.nodes) do move(node.position) end
	for _, p in pairs(data.foreign or {}) do move(p) end
	for _, r in ipairs(data.removed_segments or {}) do
		move(r.p0)
		move(r.p1)
	end
	for _, p in ipairs(data.removed_nodes or {}) do move(p) end
	for _, c in ipairs(data.constructions or {}) do
		c.transf[13] = c.transf[13] + dx
		c.transf[14] = c.transf[14] + dy
	end
	for _, d in ipairs(data.demolished or {}) do move(d.position) end
	for _, o in ipairs(data.objects or {}) do move(o.position) end
	for _, c in ipairs(data.configs or {}) do move(c.position) end
	for _, e in pairs(data.config_segments or {}) do
		move(e.p0)
		move(e.p1)
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
--   before it is sent, prepare = function(cmd) (see build.send), player = entity }
-- @return boolean ok, string message
local function replay_once(env, data, opts)
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
				on_result, opts.player, opts.prepare)
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

--- v26: which demolished construction a new one replaces, as SimpleProposal.old2new wants it
-- ({[old entity] = 0-based index into constructionsToAdd}, like the engine's own refresh proposal,
-- runs 20-22). Extending or changing a station demolishes it and adds one of the same file; without
-- old2new the copy was a new station and the lines lost their stops there. Pairs by file, in order.
function build.old2new(data)
	local map, taken = {}, {}
	if data.no_old2new then return map end
	for _, d in ipairs(data.demolished or {}) do
		if d.entity then
			for i, c in ipairs(data.constructions or {}) do
				if not taken[i] and c.file == d.file then
					taken[i] = true
					map[d.entity] = i - 1
					break
				end
			end
		end
	end
	return map
end

--- Removes the segments that join a construction to the network, and nodes only they used.
function build.drop_access(data)
	local segments, used = {}, {}
	for _, seg in ipairs(data.segments) do
		if not data.access[seg.id] then
			segments[#segments + 1] = seg
			used[seg.node0], used[seg.node1] = true, true
		end
	end
	local nodes = {}
	for _, node in ipairs(data.nodes) do
		if used[node.id] then nodes[#nodes + 1] = node end
	end
	data.segments, data.nodes, data.access, data.gates = segments, nodes, {}, {}
	-- Placeholders stay dense: -1, -2, ... for segments and for nodes (node_entity moves the nodes
	-- behind the segments).
	local renumber, node_ids = {}, {}
	for i, seg in ipairs(data.segments) do renumber[seg.id] = -i; seg.id = -i end
	for _, o in ipairs(data.objects or {}) do o.segment = renumber[o.segment] or o.segment end
	for i, node in ipairs(data.nodes) do node_ids[node.id] = -i; node.id = -i end
	for _, seg in ipairs(data.segments) do
		if type(seg.node0) == "number" and seg.node0 < 0 then seg.node0 = node_ids[seg.node0] end
		if type(seg.node1) == "number" and seg.node1 < 0 then seg.node1 = node_ids[seg.node1] end
	end
end

--- Splits parsed and resolved data into its streets and its constructions, for a copy built in two
-- proposals (v22). Both share the lists they keep; the construction part carries the gate positions.
-- @return table streets, table constructions
function build.split_constructions(data)
	local streets = {}
	for k, v in pairs(data) do streets[k] = v end
	streets.constructions, streets.demolished = {}, {}
	local constructions = {
		version = data.version, nodes = {}, foreign = {}, segments = {}, removed_segments = {}, configs_to_remove = {},
		removed_nodes = {}, objects = {}, objects_to_remove = {}, access = {}, gates = {}, configs = {},
		config_segments = {}, positions_of = {}, constructions = data.constructions, demolished = data.demolished,
		gate_positions = data.gate_positions,
	}
	return streets, constructions
end

function build.replay(env, data, opts)
	opts = opts or {}
	local log = opts.log or function() end
	local needs_numbering = false
	for _, o in ipairs(data.objects or {}) do
		if not o.entity then needs_numbering = true end
	end
	if not needs_numbering then
		local ok, message = replay_once(env, data, opts)
		if not ok and next(data.access or {}) then
			log("retrying without the access segments: " .. tostring(message))
			build.drop_access(data)
			ok, message = replay_once(env, data, opts)
			if ok then message = message .. " (without access segments)" end
		end
		-- v26: old2new is new in copied builds; a game that refuses it still gets the build.
		if not ok and next(build.old2new(data)) ~= nil then
			log("retrying without old2new: " .. tostring(message))
			data.no_old2new = true
			ok, message = replay_once(env, data, opts)
			if ok then message = message .. " (without old2new)" end
		end
		-- Run 16: a removal was rejected once ("map_util Get"); the street graph cleanup removes
		-- loose nodes by itself, so it is tried again without naming them.
		local named = 0
		for _, n in ipairs(data.removed_nodes or {}) do if n.entity then named = named + 1 end end
		if not ok and named > 0 and #(data.removed_segments or {}) > 0 then
			log("retrying without the " .. named .. " removed node(s): " .. tostring(message))
			for _, n in ipairs(data.removed_nodes) do n.entity = nil end
			ok, message = replay_once(env, data, opts)
			if ok then message = message .. " (without removed nodes)" end
		end
		return ok, message
	end
	local last_ok, last_message = false, nil
	for _, numbering in ipairs(build.OBJECT_NUMBERINGS) do
		data.object_numbering = numbering
		last_ok, last_message = replay_once(env, data, opts)
		if last_ok then return true, last_message .. " (stops/signals numbered " .. numbering .. ")" end
		log("stops/signals numbered " .. numbering .. ": " .. tostring(last_message))
	end
	return last_ok, last_message
end

return build

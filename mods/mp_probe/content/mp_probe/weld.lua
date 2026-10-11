--- Construction entrances (v20, v21).
-- The build tool lays a depot's entrance street from the road to the depot's gate and hands the
-- gate node to the construction: in its proposal the gate is a new node that both
-- proposal.frozenNodes and toAdd[i].frozenNodes name (run 19), and afterwards the entrance is one
-- of the construction's own frozen edges (run 20b). A SimpleProposal has no field for that. A
-- copied construction lays its own entrance; the copied entrance street came on top of it as a
-- second one ending in a second node on the gate (run 20b), so v21 leaves that street out and the
-- construction's own entrance has to meet the road. This module tells whether a copy's entrance
-- reaches the road and tries the engine's own ways to join it. Every engine call is guarded.
-- @module mp_probe.weld
local build = require("/mp_probe/build.lua")
local world = require("/mp_probe/world.lua")

local weld = {}

--- Horizontal distance within which a node counts as lying on a gate.
weld.GATE_RADIUS = 1.0
--- Entries listed per proposal list in weld.describe_proposal.
weld.LIST_LIMIT = 8

local list_items = build.list_items

local function component(env, id, name)
	local ok, value = pcall(function()
		return env.api.engine.getComponent(id, env.api.type.ComponentType[name])
	end)
	if ok then return value end
	return nil
end

local function fmt(p)
	if not p then return "?" end
	return string.format("%.1f,%.1f", p.x, p.y)
end

local function short(file)
	return tostring(file):match("([^/]+)$") or tostring(file)
end

--- Frozen nodes (gates) and frozen edges (inner streets) of a construction.
-- @return table node ids, table set of edge ids
function weld.frozen_of(env, construction)
	local nodes, edges = {}, {}
	local con = component(env, construction, "CONSTRUCTION")
	if con then
		pcall(function() nodes = list_items(con.frozenNodes) end)
		pcall(function()
			for _, e in ipairs(list_items(con.frozenEdges)) do edges[e] = true end
		end)
	end
	if #nodes == 0 then
		pcall(function()
			local map = env.api.engine.system.streetConnectorSystem.getNode2StreetConnectorMap()
			for node, owner in pairs(map) do
				if owner == construction then nodes[#nodes + 1] = node end
			end
		end)
		table.sort(nodes)
	end
	return nodes, edges
end

weld.segments_at = world.node_segments
weld.nodes_near = world.nodes_near

--- How many nodes weld.status walks along a construction's own edges from one gate.
weld.WALK_LIMIT = 64

--- Follows the construction's own (frozen) edges from a gate and returns the first node that
-- also has a segment of someone else (the road its entrance joins) and how many such segments it
-- has, or nil.
local function road_from(env, gate, frozen_edges)
	local seen, queue, head = { [gate] = true }, { gate }, 1
	local examined = 0
	while head <= #queue and examined < weld.WALK_LIMIT do
		local n = queue[head]
		head = head + 1
		examined = examined + 1
		local road = 0
		for _, e in ipairs(weld.segments_at(env, n)) do
			if frozen_edges[e] then
				local a, b = world.edge_nodes(env, e)
				local other = (a == n) and b or a
				if other ~= nil and not seen[other] then
					seen[other] = true
					queue[#queue + 1] = other
				end
			else
				road = road + 1
			end
		end
		if road > 0 then return n, road, queue, false end
	end
	-- A bounded search that stopped early did not prove a disconnected entrance. In particular,
	-- a long modular station may have more frozen track nodes than this diagnostic walks.
	return nil, nil, queue, head <= #queue
end

--- Whether the captured proposal actually requires an entrance to meet the outside network.
-- Frozen nodes alone are not evidence: modular stations also freeze ordinary track midpoints
-- and open track ends. B5 explicitly marks access segments/gates when the player's proposal
-- makes an outside connection. A native replacement with only c/k records may legitimately
-- have none; the native command result and node-configuration checks still verify that build.
function weld.connection_required(data)
	return #(data.gate_positions or {}) > 0 or next(data.gates or {}) ~= nil or next(data.access or {}) ~= nil
end

--- Whether the construction's gates reach the street network. Run 20b: TF3 hands the entrance
-- street to the construction, so even the player's own depot has only its entrance at the gate,
-- among the construction's frozen edges ("0 outside, 1 inner"). The check therefore follows the
-- construction's own edges from each gate; it is welded when a node on that way also has a segment
-- that is not the construction's (the road the entrance joins).
-- @param gate_positions list of {x, y, z} where the line puts the gates (may be empty)
-- @param require_connection boolean|nil false if the captured proposal names no external access;
--   nil keeps the legacy strict entrance check for saved checks and older callers.
-- @return table { welded = true, false or nil (no gate found / bounded search), confirmed,
--   connection_required, gates = {{id, position, outside,
--   inner, road, road_segments}}, loose = {{id, position, segments}} (other nodes on a gate spot),
--   text }
function weld.status(env, construction, gate_positions, require_connection)
	local nodes, frozen_edges = weld.frozen_of(env, construction)
	local st = { welded = nil, gates = {}, loose = {} }
	st.exists = component(env, construction, "CONSTRUCTION") ~= nil
	local incomplete = false
	local is_gate = {}
	for _, id in ipairs(nodes) do
		is_gate[id] = true
		local outside, inner = 0, 0
		for _, e in ipairs(weld.segments_at(env, id)) do
			if frozen_edges[e] then inner = inner + 1 else outside = outside + 1 end
		end
		local road, road_segments, walked, limited = road_from(env, id, frozen_edges)
		incomplete = incomplete or limited
		if road then st.welded = true elseif st.welded == nil then st.welded = false end
		-- Where the construction's own entrance ends when it reaches no road (a dead end).
		local tip = nil
		if not road then
			for _, n in ipairs(walked) do
				if n ~= id and #weld.segments_at(env, n) == 1 then tip = n end
			end
		end
		st.gates[#st.gates + 1] = { id = id, position = world.node_position(env, id), outside = outside, inner = inner,
			road = road, road_segments = road_segments, tip = tip, tip_position = tip and world.node_position(env, tip),
			limited = limited }
	end
	if incomplete and st.welded ~= true then st.welded = nil end
	st.connection_required = require_connection ~= false
	st.confirmed = st.exists and (not st.connection_required or st.welded == true)
	st.limited = incomplete
	-- Other nodes on the spot where an entrance ends: a road node there that the entrance did not
	-- join is the copy's own street.
	local spots = {}
	for _, pos in ipairs(gate_positions or {}) do spots[#spots + 1] = pos end
	gate_positions = spots
	for _, g in ipairs(st.gates) do
		if g.tip_position then gate_positions[#gate_positions + 1] = g.tip_position end
	end
	if #(gate_positions or {}) > 0 then
		local ok, index = pcall(world.node_index, env)
		if ok then
			local seen = {}
			for _, pos in ipairs(gate_positions) do
				for _, n in ipairs(weld.nodes_near(index, pos, weld.GATE_RADIUS)) do
					local own = false
					for _, g in ipairs(st.gates) do if g.tip == n.id then own = true end end
					if not is_gate[n.id] and not own and not seen[n.id] then
						seen[n.id] = true
						st.loose[#st.loose + 1] = { id = n.id, position = n.p, segments = #weld.segments_at(env, n.id) }
					end
				end
			end
		end
	end
	local parts = {}
	for i, g in ipairs(st.gates) do
		if i > weld.LIST_LIMIT then
			parts[#parts + 1] = tostring(#st.gates - weld.LIST_LIMIT) .. " further frozen nodes"
			break
		end
		local reach = g.road and string.format("road at node %s with %d segments", tostring(g.road), g.road_segments)
			or g.limited and "outside connection unknown (frozen-node search limit)"
			or g.tip and string.format("no road reached, entrance ends at node %s at %s", tostring(g.tip), fmt(g.tip_position))
			or "no road reached"
		parts[#parts + 1] = string.format("gate %s at %s (%d outside, %d inner, %s)", tostring(g.id), fmt(g.position),
			g.outside, g.inner, reach)
	end
	if #parts == 0 then parts[1] = "no gate node found" end
	for i, n in ipairs(st.loose) do
		if i > weld.LIST_LIMIT then
			parts[#parts + 1] = tostring(#st.loose - weld.LIST_LIMIT) .. " further coincident nodes"
			break
		end
		parts[#parts + 1] = string.format("other node %s at %s (%d segments)", tostring(n.id), fmt(n.position), n.segments)
	end
	local verdict = st.welded == true and "WELDED" or st.welded == false and "NOT WELDED" or "UNKNOWN"
	st.text = "construction " .. tostring(construction) .. ": " .. table.concat(parts, "; ") .. " -> " .. verdict
	if not st.connection_required then
		st.text = st.text .. "; external network connection not required by captured proposal"
	end
	return st
end

--- One line about a full Proposal (what refreshConstruction returns, or a command's proposal):
-- constructions with their frozen node indexes, removals, and the street part.
function weld.describe_proposal(p)
	local out = {}
	local limit = weld.LIST_LIMIT
	local function try(label, fn)
		local ok, text = pcall(fn)
		out[#out + 1] = label .. " " .. (ok and tostring(text) or ("? (" .. tostring(text):sub(1, 60) .. ")"))
	end
	local function ids(list)
		local items = {}
		for i, v in ipairs(list_items(list)) do
			if i > limit then items[#items + 1] = "..."; break end
			items[#items + 1] = tostring(v)
		end
		return "#" .. #list_items(list) .. " {" .. table.concat(items, ",") .. "}"
	end
	local function segments(list)
		local items = {}
		for i, seg in ipairs(list_items(list)) do
			if i > limit then items[#items + 1] = "..."; break end
			local text = tostring(seg.entity)
			pcall(function()
				text = text .. ":" .. tostring(seg.comp.node0) .. ">" .. tostring(seg.comp.node1) .. " " ..
					short(seg.comp.roadTemplate)
			end)
			items[#items + 1] = text
		end
		return "#" .. #list_items(list) .. " {" .. table.concat(items, "; ") .. "}"
	end
	try("toAdd", function()
		local items = {}
		for _, ce in ipairs(list_items(p.toAdd)) do
			local text = "?"
			pcall(function() text = short(ce.fileName) end)
			pcall(function()
				local frozen = {}
				for _, k in ipairs(list_items(ce.frozenNodes)) do frozen[#frozen + 1] = tostring(k) end
				text = text .. " frozen{" .. table.concat(frozen, ",") .. "}"
			end)
			pcall(function()
				if ce.playerEntity ~= nil then text = text .. " player " .. tostring(ce.playerEntity) end
			end)
			items[#items + 1] = text
		end
		return "#" .. #items .. " {" .. table.concat(items, "; ") .. "}"
	end)
	try("toRemove", function() return ids(p.toRemove) end)
	try("old2new", function()
		local map = p.old2new
		if map == nil then return "none" end
		local items = {}
		for k, v in pairs(map) do items[#items + 1] = tostring(k) .. "=" .. tostring(v) end
		table.sort(items)
		return "{" .. table.concat(items, ",") .. "}"
	end)
	local ok, sp = pcall(function() return p.proposal end)
	if ok and sp ~= nil then
		try("addedNodes", function()
			local items = {}
			for i, n in ipairs(list_items(sp.addedNodes)) do
				if i > limit then items[#items + 1] = "..."; break end
				local text = tostring(n.entity)
				pcall(function() text = text .. "@" .. fmt(n.comp.position) end)
				items[#items + 1] = text
			end
			return "#" .. #list_items(sp.addedNodes) .. " {" .. table.concat(items, "; ") .. "}"
		end)
		try("addedSegments", function() return segments(sp.addedSegments) end)
		try("removedSegments", function() return segments(sp.removedSegments) end)
		try("removedNodes", function()
			local items = {}
			for i, n in ipairs(list_items(sp.removedNodes)) do
				if i > limit then items[#items + 1] = "..."; break end
				items[#items + 1] = tostring(n.entity)
			end
			return "#" .. #list_items(sp.removedNodes) .. " {" .. table.concat(items, ",") .. "}"
		end)
		try("frozenNodes", function() return ids(sp.frozenNodes) end)
		try("nodeConfigsToAdd", function()
			local items = {}
			for i, c in ipairs(list_items(sp.nodeConfigsToAdd)) do
				if i > limit then items[#items + 1] = "..."; break end
				local text = tostring(c.entity)
				pcall(function() text = text .. ":" .. #list_items(c.comp.laneConnections) .. " lanes" end)
				items[#items + 1] = text
			end
			return "#" .. #list_items(sp.nodeConfigsToAdd) .. " {" .. table.concat(items, ",") .. "}"
		end)
		try("nodeConfigsToRemove", function() return ids(sp.nodeConfigsToRemove) end)
	else
		out[#out + 1] = "no street part (" .. tostring(sp):sub(1, 60) .. ")"
	end
	return table.concat(out, " | ")
end

--- What a WorldBuildProposal command holds before it is sent: for a SimpleProposal the game may
-- already have computed the full Proposal (run 10: errors come from makeWorldBuildProposalCmd).
function weld.describe_command(cmd)
	local present = {}
	for _, key in ipairs({ "proposal", "context", "resultProposalData", "ignoreErrors", "resultEntities" }) do
		local ok, v = pcall(function() return cmd[key] end)
		if ok and v ~= nil then present[#present + 1] = key end
	end
	local text = "command fields {" .. table.concat(present, ",") .. "}"
	local ok, p = pcall(function() return cmd.proposal end)
	if ok and p ~= nil then text = text .. "; proposal " .. weld.describe_proposal(p) end
	return text
end

--- The construction among a build's new entities (param[3] of onPostBuildProposal), or nil.
function weld.construction_in(env, ids)
	for _, id in ipairs(list_items(ids)) do
		if type(id) == "number" and component(env, id, "CONSTRUCTION") then return id end
	end
	return nil
end

--- Sends a proposal through build.send and reports whether something was built.
local function send(env, proposal, label, opts)
	local built = nil
	local sent, message = build.send(env, proposal, function(line) opts.log("weld " .. label .. " " .. line) end,
		function(result, success)
			local outcome = build.outcome(result)
			built = outcome.built
			if opts.on_result then opts.on_result(result, success, "weld " .. label, outcome) end
		end, opts.player)
	return sent and built ~= false, message
end

--- Rebuilds the construction with the engine's own refresh proposal. If the engine places a
-- construction's gate the way its tools do, it may weld the waiting entrance end.
function weld.refresh(env, construction, _, opts)
	local ok, p = pcall(function() return env.api.engine.util.proposal.refreshConstruction(construction) end)
	if not ok or p == nil then return false, "refreshConstruction gave nothing (" .. tostring(p):sub(1, 160) .. ")" end
	opts.log("weld refresh proposal: " .. weld.describe_proposal(p))
	if opts.dump then opts.dump("weld refresh proposal", p) end
	return send(env, p, "refresh", opts)
end

--- Replaces the construction by itself through a SimpleProposal with old2new, the way a station
-- upgrade does.
function weld.rebuild(env, construction, c, opts)
	local api = env.api
	local errors = {}
	local p = api.type.SimpleProposal.new()
	local entry = build.make_construction(api, c, opts.player, errors, "rebuild")
	local function set(key, value)
		local ok, err = pcall(function() p[key] = value end)
		if not ok then errors[#errors + 1] = key .. ": " .. tostring(err):sub(1, 80) end
	end
	set("constructionsToAdd", { entry })
	set("constructionsToRemove", { construction })
	set("old2new", { [construction] = 0 })
	if #errors > 0 then opts.log("weld rebuild refused fields: " .. table.concat(errors, "; ")) end
	local n = 0
	pcall(function() n = #p.constructionsToAdd end)
	if n ~= 1 then return false, "constructionsToAdd not taken" end
	return send(env, p, "rebuild", opts)
end

weld.STEPS = { { "refresh", weld.refresh }, { "rebuild", weld.rebuild } }

--- Gate positions a parsed line names (nodes marked "g").
function weld.gate_positions(data)
	local out = {}
	for _, node in ipairs(data.nodes or {}) do
		if data.gates and data.gates[node.id] then out[#out + 1] = node.position end
	end
	return out
end

--- After a copy with an entrance was built: checks each copied construction and, while it is
-- not welded, tries weld.STEPS in turn.
-- @param opts table { log = function(text), player, on_result, dump = function(label, value) }
-- @return table list of { file, position, verdict } for a later check
function weld.repair(env, data, opts)
	local gates = data.gate_positions or weld.gate_positions(data)
	local checked = {}
	for _, c in ipairs(data.constructions or {}) do
		local pos = { x = c.transf[13], y = c.transf[14], z = c.transf[15] }
		local id = world.find_construction(env, c.file, pos)
		if not id then
			opts.log("weld: the copied " .. short(c.file) .. " near " .. fmt(pos) .. " is not here")
		else
			local st = weld.status(env, id, gates)
			opts.log("weld check after build: " .. st.text)
			local last = "build"
			for _, step in ipairs(weld.STEPS) do
				if st.welded ~= false then break end
				local ok, sent, message = pcall(step[2], env, id, c, opts)
				if not ok then sent, message = false, tostring(sent):sub(1, 200) end
				opts.log("weld " .. step[1] .. ": " .. (sent and "sent, " or "failed, ") .. tostring(message))
				id = world.find_construction(env, c.file, pos) or id
				st = weld.status(env, id, gates)
				last = step[1]
				opts.log("weld check after " .. step[1] .. ": " .. st.text)
			end
			local verdict = st.welded == true and "WELDED" or st.welded == false and "NOT WELDED" or "UNKNOWN"
			opts.log("weld result " .. short(c.file) .. ": " .. verdict .. " (after " .. last .. ")")
			checked[#checked + 1] = { file = c.file, position = pos, gates = gates, verdict = verdict,
				require_connection = true }
		end
	end
	return checked
end

return weld

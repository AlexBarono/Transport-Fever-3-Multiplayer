--- Node configurations of a copy (v21).
-- A player's build gives every street node it touches a BaseNodeConfig (lane connections,
-- crosswalks, traffic lights) through proposal.nodeConfigsToAdd; the line carries them by position
-- (build.serialize_configs). Run 20b: a copy without them had a junction nothing could drive
-- through, and clicking it broke the game's window ("baseNodeConfig (a nil value)").
-- They are applied after the build and after weld.lua joined a construction's entrance, because
-- only then does every segment they name exist here, also the entrance a construction lays itself.
-- A segment is found by the positions of its two end nodes; the node of a configuration is the
-- one near its position that all its segments end at. Every engine call is guarded.
-- @module mp_probe.nodecfg
local build = require("/mp_probe/build.lua")
local world = require("/mp_probe/world.lua")

local nodecfg = {}

--- Horizontal distance within which a node counts as the one a position names.
nodecfg.RADIUS = 1.0

local try_set, update = build.try_set, build.update

local function fmt(p)
	return string.format("%.1f,%.1f", p.x, p.y)
end

local function count_keys(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

--- Edges joining a node near p0 with a node near p1: list of { id, a, b } (a near p0, b near p1).
local function edges_between(env, index, p0, p1)
	local far = {}
	for _, n in ipairs(world.nodes_near(index, p1, nodecfg.RADIUS)) do far[n.id] = true end
	local out = {}
	for _, n in ipairs(world.nodes_near(index, p0, nodecfg.RADIUS)) do
		for _, e in ipairs(world.node_segments(env, n.id)) do
			local a, b = world.edge_nodes(env, e)
			local other = (a == n.id) and b or (b == n.id) and a or nil
			if other ~= nil and far[other] then out[#out + 1] = { id = e, a = n.id, b = other } end
		end
	end
	return out
end

--- Keeps only the connections and crosswalks of a configuration whose segments were found.
local function reduce(c, found)
	local out = { position = c.position, pref = c.pref, tltype = c.tltype, double = c.double,
		lanes_modified = c.lanes_modified, states_modified = c.states_modified, states = c.states, conns = {}, walks = {} }
	for _, lc in ipairs(c.conns) do
		if found[lc.a] and found[lc.b] then out.conns[#out.conns + 1] = lc end
	end
	for _, w in ipairs(c.walks) do
		if found[w] then out.walks[#out.walks + 1] = w end
	end
	return out
end

--- Turns the configurations of a parsed line into this game's ids. The node is the one near the
-- configuration's position that all its segments end at. When there is none (run 20b: a copied
-- entrance ending in its own node beside the road), the node with the most of them gets the
-- connections among those, so traffic along the road still passes and the junction window works.
-- @param index table world.node_index made after the build
-- @return list of { node, config, segments = {[e number] = edge id}, partial = nil or
--   "k of n connections" }, list of notes, number of configurations left to a construction's entrance
function nodecfg.resolve(env, data, index)
	local candidates = {}
	for k, s in pairs(data.config_segments or {}) do candidates[k] = edges_between(env, index, s.p0, s.p1) end
	local resolved, notes, skipped = {}, {}, 0
	local entrance = data.entrance_refs or {}
	for _, original in ipairs(data.configs or {}) do
		local c = original
		local refs = build.config_refs(c)
		-- A construction's entrance was left out of the build (build.drop_access): the construction
		-- lays it with its configurations. Its far-end node is the construction's own, and the
		-- connections to it come with it; only the rest of a configuration is ours to place.
		local at_entrance = false
		for _, p in ipairs(data.entrance_nodes or {}) do
			if build.near(p, c.position) then at_entrance = true end
		end
		local named = 0
		for k in pairs(refs) do
			if entrance[k] then refs[k] = nil; named = named + 1 end
		end
		if named > 0 and not at_entrance then
			local keep = {}
			for k in pairs(refs) do keep[k] = true end
			c = reduce(c, keep)
		end
		if at_entrance or (named > 0 and next(refs) == nil) then
			skipped = skipped + 1
			notes[#notes + 1] = string.format("node config near %s left to the construction's own entrance", fmt(c.position))
			goto continue
		end
		local wanted = count_keys(refs)
		local best, best_count = nil, -1
		for _, n in ipairs(world.nodes_near(index, c.position, nodecfg.RADIUS)) do
			local map, found = {}, 0
			for k in pairs(refs) do
				for _, e in ipairs(candidates[k] or {}) do
					if e.a == n.id or e.b == n.id then
						map[k] = e.id
						found = found + 1
						break
					end
				end
			end
			if found > best_count then best, best_count = { node = n.id, config = c, segments = map }, found end
			if found == wanted then break end
		end
		local missing = {}
		for k in pairs(refs) do
			if #(candidates[k] or {}) == 0 then missing[#missing + 1] = "e" .. k end
		end
		table.sort(missing)
		local why = #missing > 0 and ", not found: " .. table.concat(missing, ",") or ", no node there that they all end at"
		if best and best_count == wanted then
			resolved[#resolved + 1] = best
		elseif best and best_count > 0 then
			best.config = reduce(c, best.segments)
			if #best.config.conns > 0 then
				best.partial = #best.config.conns .. " of " .. #c.conns .. " connections"
				resolved[#resolved + 1] = best
				notes[#notes + 1] = string.format("node config near %s placed in part on node %s (%s; %d of %d segments%s)",
					fmt(c.position), tostring(best.node), best.partial, best_count, wanted, why)
			else
				best = nil
			end
		else
			best = nil
		end
		if not best then
			notes[#notes + 1] = string.format("node config near %s not placed (%d segments named%s)", fmt(c.position),
				wanted, why)
		end
		::continue::
	end
	return resolved, notes, skipped
end

--- Whether the lane connections comp holds now are the wanted ones.
local function connections_match(comp, wanted)
	local ok, same = pcall(function()
		local list = build.list_items(comp.laneConnections)
		if #list ~= #wanted then return false end
		for i, v in ipairs(wanted) do
			local lc = list[i]
			if lc.segment0 ~= v.segment0 or lc.segment1 ~= v.segment1 or lc.lane0 ~= v.lane0 or lc.lane1 ~= v.lane1 then
				return false
			end
		end
		return true
	end)
	return ok and same
end

--- Sets comp.laneConnections. TF3's type list has no constructor for LaneConnection, so after
-- api.type.LaneConnection.new (should it exist) a plain table per connection is tried, then
-- copies of a connection read from an existing node (getComponent hands out copies). Each attempt
-- is read back.
-- @param template function|nil returns a fresh LaneConnection copy
-- @return string|nil the way that worked
local function set_connections(api, comp, wanted, template, errors, label)
	local function filled(make)
		return function(v)
			local lc = make()
			for k, x in pairs(v) do lc[k] = x end
			return lc
		end
	end
	local attempts = {
		{ "LaneConnection.new", filled(function() return api.type.LaneConnection.new() end) },
		{ "table", function(v) return v end },
	}
	if template then attempts[#attempts + 1] = { "copy", filled(template) } end
	local tried = {}
	for _, a in ipairs(attempts) do
		local ok, list = pcall(function()
			local out = {}
			for i, v in ipairs(wanted) do out[i] = a[2](v) end
			return out
		end)
		local why = ok and "reads back different" or tostring(list):sub(1, 60)
		if ok then
			local set, err = pcall(function() comp.laneConnections = list end)
			if set and connections_match(comp, wanted) then return a[1] end
			if not set then why = tostring(err):sub(1, 60) end
		end
		tried[#tried + 1] = a[1] .. ": " .. why
	end
	errors[#errors + 1] = label .. ".laneConnections: " .. table.concat(tried, "; ")
	return nil
end

--- Creates the api.type.BaseNodeLaneConnectionAndEntity for one resolved configuration.
-- @param template function|nil see set_connections
function nodecfg.make_entry(api, r, errors, label, template)
	local c = r.config
	local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
	try_set(entry, "entity", r.node, errors, label .. ".entity")
	update(entry, "comp", function(comp)
		local wanted = {}
		for i, lc in ipairs(c.conns) do
			wanted[i] = { segment0 = r.segments[lc.a], lane0 = lc.l0, segment1 = r.segments[lc.b], lane1 = lc.l1,
				withRoad = lc.road, withTram = lc.tram }
		end
		r.connections_by = set_connections(api, comp, wanted, template, errors, label)
		local walks = {}
		for i, w in ipairs(c.walks) do walks[i] = r.segments[w] end
		try_set(comp, "crosswalks", walks, errors, label .. ".crosswalks")
		try_set(comp, "trafficLightPreference", c.pref, errors, label .. ".trafficLightPreference")
		try_set(comp, "doubleSlipSwitch", c.double, errors, label .. ".doubleSlipSwitch")
		try_set(comp, "userModifiedLaneConnections", c.lanes_modified, nil, label .. ".userModifiedLaneConnections")
		try_set(comp, "userModifiedTrafficLightStates", c.states_modified, nil, label .. ".userModifiedTrafficLightStates")
		update(comp, "trafficLightConfig", function(tlc)
			tlc.trafficLightType = c.tltype
			local states = {}
			for i, st in ipairs(c.states) do
				local s = api.type.TrafficLightState.new()
				s.duration, s.minDuration, s.canSkip, s.lockedLanes = st.duration, st.min, st.skip, st.lanes
				states[i] = s
			end
			tlc.states = states
		end, errors, label .. ".trafficLightConfig")
	end, errors, label .. ".comp")
	return entry
end

--- A function that returns a fresh copy of a lane connection of some existing node near the
-- configurations, or nil when none is found.
function nodecfg.template(env, index, data)
	local function first_connection(id)
		local ok, lc = pcall(function()
			local cfg = env.api.engine.getComponent(id, env.api.type.ComponentType.BASE_NODE_CONFIG)
			return cfg and cfg.laneConnections[1]
		end)
		return ok and lc or nil
	end
	for _, c in ipairs(data.configs or {}) do
		for _, n in ipairs(world.nodes_near(index, c.position, nodecfg.TEMPLATE_RADIUS)) do
			if first_connection(n.id) ~= nil then
				local id = n.id
				return function()
					local lc = first_connection(id)
					if lc == nil then error("no lane connection to copy", 0) end
					return lc
				end
			end
		end
	end
	return nil
end

--- How far from the configurations nodecfg.template looks for a node to copy from.
nodecfg.TEMPLATE_RADIUS = 60

--- Reads back how many lane connections an entry holds (nil if unreadable).
local function lane_count(entry)
	local ok, n = pcall(function() return #build.list_items(entry.comp.laneConnections) end)
	return ok and n or nil
end

--- A SimpleProposal that sets the given resolved configurations; a node that has one already gets
-- it removed in the same proposal.
local function make_proposal(env, list, errors, template)
	local api = env.api
	local entries, removes, lanes_ok = {}, {}, true
	for i, r in ipairs(list) do
		entries[i] = nodecfg.make_entry(api, r, errors, "nodeConfig[" .. i .. "]", template)
		local want = #r.config.conns
		local got = lane_count(entries[i])
		if got ~= want then
			-- A node without its connections would block the junction just the same.
			lanes_ok = false
			errors[#errors + 1] = "nodeConfig[" .. i .. "]: " .. tostring(got) .. "/" .. want .. " lane connections read back"
		end
		if world.has_node_config(env, r.node) then removes[#removes + 1] = r.node end
	end
	local p = api.type.SimpleProposal.new()
	update(p, "streetProposal", function(sp)
		try_set(sp, "nodeConfigsToAdd", entries, errors, "streetProposal.nodeConfigsToAdd")
		if #removes > 0 then try_set(sp, "nodeConfigsToRemove", removes, errors, "streetProposal.nodeConfigsToRemove") end
	end, errors, "streetProposal")
	local n = 0
	pcall(function() n = #build.list_items(p.streetProposal.nodeConfigsToAdd) end)
	return p, n == #entries and lanes_ok, #removes
end

--- Sends one proposal for `list` and returns how many of its nodes have a configuration afterwards.
local function send_list(env, list, opts, label)
	local errors = {}
	local ok_make, p, complete, removes = pcall(make_proposal, env, list, errors, opts.template)
	if not ok_make then
		opts.log("node configs " .. label .. ": proposal failed (" .. tostring(p):sub(1, 200) .. ")")
		return 0
	end
	if #errors > 0 then opts.log("node configs " .. label .. " refused fields: " .. table.concat(errors, "; "):sub(1, 600)) end
	if not complete then
		opts.log("node configs " .. label .. ": the proposal did not take the list or its lane connections, not sent")
		return 0
	end
	local result_text = "no result"
	local sent, message = build.send(env, p, function(line) opts.log("node configs " .. label .. " " .. line) end,
		function(result, success)
			local outcome = build.outcome(result)
			result_text = "success=" .. tostring(success) .. ", critical " .. tostring(outcome.critical)
			if #outcome.messages > 0 then result_text = result_text .. ", " .. table.concat(outcome.messages, "; ") end
		end, opts.player)
	local have = 0
	for _, r in ipairs(list) do
		if world.has_node_config(env, r.node) then have = have + 1 end
	end
	local ways = {}
	for _, r in ipairs(list) do
		if r.connections_by then ways[r.connections_by] = (ways[r.connections_by] or 0) + 1 end
	end
	local way_text = {}
	for way, n in pairs(ways) do way_text[#way_text + 1] = way .. " " .. n end
	table.sort(way_text)
	opts.log(string.format("node configs %s: %s (%s), %s; %d/%d nodes have one now (%d replaced; connections as %s)",
		label, sent and "sent" or "not sent", tostring(message), result_text, have, #list, removes,
		#way_text > 0 and table.concat(way_text, ", ") or "-"))
	return have
end

--- Applies the configurations of a built copy.
-- @param opts table { log = function(text), player }
-- @return number placed, number total
function nodecfg.apply(env, data, opts)
	local total = #(data.configs or {})
	if total == 0 then return 0, 0 end
	local index = world.node_index(env)
	local found, notes, skipped = nodecfg.resolve(env, data, index)
	for _, note in ipairs(notes) do opts.log("node configs: " .. note) end
	-- v23 (run 22): a configuration set again on the node a depot's entrance meets made the game
	-- assert (TransportNetworkSystem EntityToBeRemoved) and left a street without its transport
	-- network, which crashed the game when it was looked at. The game sets those itself when it
	-- builds or refreshes the construction.
	local resolved, kept = {}, {}
	for _, r in ipairs(found) do
		local c = world.node_construction(env, r.node)
		if c then
			kept[#kept + 1] = tostring(r.node) .. " (construction " .. tostring(c) .. ")"
		else
			resolved[#resolved + 1] = r
		end
	end
	if #kept > 0 then opts.log("node configs left to the game at a construction: node " .. table.concat(kept, ", ")) end
	local left = #kept > 0 and string.format(", %d left to a construction", #kept) or ""
	if #resolved == 0 then
		opts.log("node configs: none of " .. total .. " could be placed" .. left)
		return 0, total
	end
	local ok_t, template = pcall(nodecfg.template, env, index, data)
	local send_opts = { log = opts.log, player = opts.player, template = ok_t and template or nil }
	local have = send_list(env, resolved, send_opts, "all " .. #resolved)
	if have < #resolved and #resolved > 1 then
		-- One configuration the game refuses must not cost the others: one proposal per node.
		have = 0
		for i, r in ipairs(resolved) do
			if world.has_node_config(env, r.node) then
				have = have + 1
			else
				have = have + send_list(env, { r }, send_opts, "node " .. i .. " (" .. tostring(r.node) .. ")")
			end
		end
	end
	opts.log(string.format("node configs result: %d/%d placed%s, %d not found here%s", have, total, left,
		total - #found - skipped, skipped > 0 and string.format(", %d left to the entrance", skipped) or ""))
	return have, total
end

return nodecfg

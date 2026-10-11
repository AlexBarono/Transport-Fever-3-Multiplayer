-- Focused capture, graph lookup and proposal regressions. No game commands are executed.
local MOD_ROOT = "mods/mp_probe/content"
local real_require, loaded = require, {}
function require(name)
	if name:sub(1, 1) ~= "/" then return real_require(name) end
	if not loaded[name] then loaded[name] = assert(loadfile(MOD_ROOT .. name))() end
	return loaded[name]
end
local build, world = require("/mp_probe/build.lua"), require("/mp_probe/world.lua")
local passed, failures = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function point(x, z) return { x = x, y = 0, z = z or 0 } end
local function graph()
	local comps, segments = {}, {}
	local g = {}
	function g.node(id, x, z)
		comps[id] = { BASE_NODE = { position = point(x, z) } }; segments[id] = {}
	end
	function g.edge(id, a, b, road)
		comps[id] = { BASE_EDGE = { node0 = a, node1 = b, roadType = road or 1 } }
		segments[a][#segments[a] + 1], segments[b][#segments[b] + 1] = id, id
	end
	g.env = { api = { type = { ComponentType = { BASE_NODE = "BASE_NODE", BASE_EDGE = "BASE_EDGE" } }, engine = {
		getComponent = function(id, ct) return comps[id] and comps[id][ct] end,
		system = { streetSystem = {
			getNode2SegmentMap = function() return segments end,
			getNodeSegments = function(id) return segments[id] end,
		} },
	} } }
	function g.index() return world.node_index(g.env) end
	function g.finder()
		local index = g.index()
		return {
			find_node = function(p) return world.find_node(index, p) end,
			find_edge = function(a, b) return world.find_edge(g.env, a, b) end,
			find_edge_at = function(p, q, kind) return world.find_edge_at(g.env, index, p, q, kind) end,
			find_construction = function() return nil end,
		}
	end
	return g
end
local function replacement()
	return assert(build.deserialize("B5 f1;0,0,0 f2;100,0,0 t1;road;style;- s-1;0;f1;f2;100,0,0;100,0,0;-1;1;0;1;-;- r;0,0,0;100,0,0;0"))
end
local function coincident()
	local g = graph()
	g.node(1, 0); g.node(2, 100); g.node(3, 0); g.node(4, 100)
	g.edge(20, 3, 4)
	local finder = g.finder()
	-- Choose the unrelated coincident gate nodes deterministically, as a nearest-node lookup can.
	finder.find_node = function(p) return p.x < 50 and 1 or 2 end
	return g, finder
end

test("unique connected endpoints repair coincident gate lookup and replacement references", function()
	local _, finder = coincident()
	local data = replacement()
	local ok, err, notes = build.resolve(data, finder)
	assert(ok, tostring(err))
	assert(data.removed_segments[1].entity == 20)
	assert(data.segments[1].node0 == 3 and data.segments[1].node1 == 4)
	assert(data.positions_of[3].x == 0 and data.positions_of[4].x == 100)
	assert(notes[1]:find("actual connected endpoints", 1, true))
end)

test("reverse edge direction keeps positions associated with their correct nodes", function()
	local g = graph(); g.node(1, 0); g.node(2, 100); g.edge(20, 2, 1)
	local edge, a, b = world.find_edge_at(g.env, g.index(), point(0), point(100), 0)
	assert(edge == 20 and a == 1 and b == 2)
end)

test("multiple nearby actual edges remain an explicit ambiguity", function()
	local g, finder = coincident(); g.node(5, 0); g.node(6, 100); g.edge(21, 5, 6)
	finder.find_edge_at = function(p, q, kind) return world.find_edge_at(g.env, g.index(), p, q, kind) end
	local ok, err = build.resolve(replacement(), finder)
	assert(not ok and err:find("ambiguous nearby road or track", 1, true), tostring(err))
end)

test("a nearby road under a missing bridge is never selected", function()
	local g = graph(); g.node(1, 0, 0); g.node(2, 100, 0); g.edge(20, 1, 2)
	assert(not world.find_edge_at(g.env, g.index(), point(0, 10), point(100, 10), 0))
end)

test("street and railway candidates use the requested segment category", function()
	local g = graph(); g.node(1, 0); g.node(2, 100); g.node(3, 0); g.node(4, 100)
	g.edge(20, 1, 2, 1); g.edge(21, 3, 4, 0)
	assert(world.find_edge_at(g.env, g.index(), point(0), point(100), 0) == 20)
	assert(world.find_edge_at(g.env, g.index(), point(0), point(100), 1) == 21)
	local edge, _, _, reason = world.find_edge_at(g.env, g.index(), point(0), point(100))
	assert(not edge and reason:find("ambiguous", 1, true))
end)

test("unreadable native category is not guessed for a removal", function()
	local g = graph(); g.node(1, 0); g.node(2, 100); g.edge(20, 1, 2)
	local get = g.env.api.engine.getComponent
	g.env.api.engine.getComponent = function(id, ct)
		if id == 20 then return { node0 = 1, node1 = 2 } end
		return get(id, ct)
	end
	assert(not world.find_edge_at(g.env, g.index(), point(0), point(100), 0))
end)

test("a genuinely missing edge stays rejected", function()
	local g = graph(); g.node(1, 0); g.node(2, 100)
	local ok, err = build.resolve(replacement(), g.finder())
	assert(not ok and err:find("does not exist here", 1, true))
end)

test("construction ownership still protects frozen roads after fallback", function()
	local _, finder = coincident(); finder.edge_construction = function(id) assert(id == 20); return 900 end
	local ok, err = build.resolve(replacement(), finder)
	assert(not ok and err:find("construction-owned", 1, true))
end)

test("demolished construction still owns its removal after graph lookup", function()
	local _, finder = coincident(); finder.edge_construction = function() return 900 end
	finder.find_construction = function() return 900 end
	local data = replacement(); data.demolished = { { file = "depot.con", position = point(0) } }
	assert(build.resolve(data, finder))
	assert(#data.removed_segments == 0 and data.segments[1].node0 == 3)
end)

test("explicit node removal follows the confirmed edge endpoint instead of an unrelated coincident gate", function()
	local _, finder = coincident(); local data = replacement()
	data.removed_nodes = { point(0), point(100) }
	assert(build.resolve(data, finder))
	assert(data.removed_nodes[1].entity == 3 and data.removed_nodes[2].entity == 4)
end)

test("demolition leaves construction-owned confirmed endpoint nodes to the native game", function()
	local _, finder = coincident(); local data = replacement()
	finder.edge_construction = function() return 900 end; finder.find_construction = function() return 900 end
	data.demolished = { { file = "depot.con", position = point(0) } }
	data.removed_nodes = { point(0), point(100) }
	assert(build.resolve(data, finder))
	assert(not data.removed_nodes[1].entity and not data.removed_nodes[2].entity)
end)

test("a node removal with conflicting confirmed graph identities is rejected even without foreign references", function()
	local data = replacement(); data.foreign, data.segments = {}, {}
	data.removed_segments[2] = { p0 = point(0), p1 = point(200), type = 0 }
	data.removed_nodes = { point(0) }
	local finder = { find_node = function(p) return p.x + 1 end, find_edge = function() end,
		find_edge_at = function(p, q) if q.x == 100 then return 20, 3, 4 else return 21, 5, 6 end end }
	local ok, err = build.resolve(data, finder)
	assert(not ok and err:find("ambiguous coincident node", 1, true))
end)

test("conflicting graph identities for the same wire node fail safely", function()
	local data = replacement(); data.removed_segments[2] = { p0 = point(0), p1 = point(200), type = 0 }
	local finder = { find_node = function(p) return p.x + 1 end, find_edge = function() end,
		find_edge_at = function(p, q) if q.x == 100 then return 20, 3, 4 else return 21, 5, 6 end end }
	local ok, err = build.resolve(data, finder)
	assert(not ok and err:find("ambiguous coincident node", 1, true))
end)

test("excessive nearby candidates are bounded without selecting any edge", function()
	local g = graph(); for i = 1, world.EDGE_CANDIDATE_LIMIT + 1 do g.node(i, 0) end; g.node(100, 100)
	g.edge(200, 1, 100)
	local edge, _, _, reason = world.find_edge_at(g.env, g.index(), point(0), point(100), 0)
	assert(not edge and reason:find("too many nearby", 1, true))
end)

test("excessive native incidence lists are bounded", function()
	local g = graph(); g.node(1, 0); g.node(2, 100)
	for i = 1, world.EDGE_CANDIDATE_LIMIT + 1 do g.edge(100 + i, 1, 2) end
	local edge, _, _, reason = world.find_edge_at(g.env, g.index(), point(0), point(100), 0)
	assert(not edge and reason:find("too many segments", 1, true))
end)

test("direct legacy lookup works without an optional graph fallback", function()
	local data = replacement()
	assert(build.resolve(data, { find_node = function(p) return p.x < 50 and 1 or 2 end,
		find_edge = function() return 20 end }))
	assert(data.segments[1].node0 == 1 and data.removed_segments[1].entity == 20)
end)

test("actual Rees payload after native split remains rejected instead of deleting replacement roads", function()
	local file = assert(io.open("tests/fixtures/depot-rees-v56.b5", "r"))
	local data = assert(build.deserialize(file:read("*l"))); file:close(); build.drop_access(data)
	local g = graph(); local coords = {}
	local function node(id, p)
		coords[id] = p
		g.node(id, p.x, p.z)
		-- This fixture's native poststate contains split segments, but not the removed original.
	end
	node(1, data.foreign.f1); node(2, data.foreign.f2); node(3, data.nodes[1].position)
	local finder = { find_node = function(p)
		for id, position in pairs(coords) do if build.near(p, position) then return id end end
	end, find_edge = function() return nil end, find_edge_at = function() return nil end }
	local ok, err = build.resolve(data, finder)
	assert(not ok and err:find("does not exist here", 1, true))
end)

-- The real API dump has api.type.enum.BaseEdgeType, not api.type.BaseEdgeType. Distinct
-- enum values and integer component readback also exercise the native binding boundary.
local function structure_api(wrapped)
	local types = wrapped and { NORMAL = {}, BRIDGE = {}, TUNNEL = {} } or { NORMAL = 0, BRIDGE = 1, TUNNEL = 2 }
	local codes = { [types.NORMAL] = 0, [types.BRIDGE] = 1, [types.TUNNEL] = 2 }
	local api = { type = { enum = { BaseEdgeType = types } }, res = {} }
	api.type.Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
	api.type.NodeAndEntity = { new = function() return { comp = { position = point(0) } } end }
	api.type.SegmentAndEntity = { new = function()
		local values = { type = 0, tangent0 = point(0), tangent1 = point(0), laneConfigs = {} }
		local comp = setmetatable({}, { __index = values, __newindex = function(_, key, value)
			if key == "type" then assert(codes[value] ~= nil, "native setter requires a known enum"); value = codes[value] end
			values[key] = value
		end })
		return { comp = comp }
	end }
	api.type.SimpleProposal = { new = function() return { streetProposal = {} } end }
	for _, kind in ipairs({ "BRIDGE", "TUNNEL" }) do
		api.res[kind == "BRIDGE" and "bridgeTypeRep" or "tunnelTypeRep"] = {
			getName = function(index) assert(index == 7); return kind:lower() .. ".lua" end,
			find = function(resource) assert(resource == kind:lower() .. ".lua"); return 23 end,
		}
	end
	return api
end

local function structure_proposal(code)
	return { addedNodes = {
		{ entity = 100, comp = { position = point(0, 10) } },
		{ entity = 101, comp = { position = point(100, 20) } },
	}, addedSegments = { { entity = 102, type = 1, comp = {
		type = code, typeIndex = 7, node0 = 100, node1 = 101, tangent0 = point(100, 10), tangent1 = point(100, 10),
		roadTemplate = "rail.template", roadStyle = "rail.style", roadType = 0, laneConfigs = {}, distance = 100,
	} } } }
end

local function capture_structure(api, code)
	return build.serialize(structure_proposal(code), { edge_structure = function(comp)
		return world.edge_structure({ api = api }, comp)
	end })
end

test("native enum namespace captures bridge and tunnel predecessors instead of dropping their builds", function()
	local api = structure_api(false)
	assert(api.type.BaseEdgeType == nil)
	for code, kind in ipairs({ "BRIDGE", "TUNNEL" }) do
		local line, info = capture_structure(api, code)
		local data = assert(build.deserialize(line))
		assert(info.nodes == 2 and info.segments == 1)
		assert(data.segments[1].structure.kind == kind and data.segments[1].structure.resource == kind:lower() .. ".lua")
		local proposal, check, errors = build.make_proposal({ api = api }, data, build.LAYOUTS[1])
		assert(check.complete and #errors == 0, check.text)
		local comp = proposal.streetProposal.edgesToAdd[1].comp
		assert(comp.type == code and comp.typeIndex == 23, "receiver resolves its own resource index")
		assert(comp.position0.z == 10 and comp.position1.z == 20, "bridge/tunnel height must survive")
	end
end)

test("wrapper enum constants accept numeric native capture and component readback", function()
	local api = structure_api(true)
	for code, kind in ipairs({ "BRIDGE", "TUNNEL" }) do
		local data = assert(build.deserialize(capture_structure(api, code)))
		local proposal, check, errors = build.make_proposal({ api = api }, data, build.LAYOUTS[1])
		assert(check.complete and #errors == 0, check.text)
		assert(build.edge_kind(api, proposal.streetProposal.edgesToAdd[1].comp.type) == kind)
		assert(world.edge_structure({ api = api }, { type = api.type.enum.BaseEdgeType[kind], typeIndex = 7 }).kind == kind)
	end
	assert(not world.edge_structure({ api = api }, { type = 0 }))
	assert(not world.edge_structure({ api = api }, { type = api.type.enum.BaseEdgeType.NORMAL }))
end)

test("unknown native structure type is rejected rather than becoming ground track", function()
	local ok, err = pcall(capture_structure, structure_api(true), 3)
	assert(not ok and tostring(err):find("unknown bridge/tunnel edge type 3", 1, true), tostring(err))
end)

test("missing local bridge resource still prevents a proposal", function()
	local api = structure_api(true)
	local data = assert(build.deserialize(capture_structure(api, 1)))
	api.res.bridgeTypeRep.find = function() return -1 end
	local ok, err = pcall(build.make_proposal, { api = api }, data, build.LAYOUTS[1])
	assert(not ok and tostring(err):find("bridge/tunnel resource missing", 1, true), tostring(err))
end)

test("losing a tunnel type in the finished proposal remains an incomplete proposal", function()
	local api = structure_api(true)
	local data = assert(build.deserialize(capture_structure(api, 2)))
	local layout = { new = build.LAYOUTS[1].new, read = build.LAYOUTS[1].read, fill = function(proposal, nodes, edges, errors, extra)
		build.LAYOUTS[1].fill(proposal, nodes, edges, errors, extra)
		proposal.streetProposal.edgesToAdd[1].comp.type = api.type.enum.BaseEdgeType.NORMAL
	end }
	local _, check = build.make_proposal({ api = api }, data, layout)
	assert(not check.complete and check.text:find("bridge/tunnel fields lost on edge 1", 1, true), check.text)
end)

print(string.format("Build regressions: %d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

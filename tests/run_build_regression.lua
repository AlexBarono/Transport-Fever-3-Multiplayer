-- Focused graph lookup regressions. No game commands are executed.
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

print(string.format("Build graph regressions: %d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

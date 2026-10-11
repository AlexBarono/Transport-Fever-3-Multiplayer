-- Station connection diagnostics against initial and upgrade Altlandsberg proposals from v57.
-- No native command is executed; the engine graph below models frozen/internal track nodes.
local MOD_ROOT = "mods/mp_probe/content"
local real_require, loaded = require, {}
function require(name)
	if name:sub(1, 1) ~= "/" then return real_require(name) end
	if not loaded[name] then loaded[name] = assert(loadfile(MOD_ROOT .. name))() end
	return loaded[name]
end
local build, weld = require("/mp_probe/build.lua"), require("/mp_probe/weld.lua")
local passed, failures = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function point(x) return { x = 111.759, y = x or 4488.678, z = 1.712 } end
local function graph(count, external, all_frozen)
	local g = { comps = {}, segments = {} }
	local frozen, edges = {}, {}
	for i = 1, count do
		g.comps[i] = { BASE_NODE = { position = point(4388.678 + i * 2) } }
		g.segments[i] = {}
		if all_frozen or i == 1 then frozen[#frozen + 1] = i end
	end
	local function edge(id, a, b)
		g.comps[id] = { BASE_EDGE = { node0 = a, node1 = b, roadType = 0 } }
		g.segments[a][#g.segments[a] + 1], g.segments[b][#g.segments[b] + 1] = id, id
	end
	for i = 1, count - 1 do local id = 1000 + i; edge(id, i, i + 1); edges[#edges + 1] = id end
	if external then
		g.comps[count + 1] = { BASE_NODE = { position = point(4500) } }; g.segments[count + 1] = {}
		edge(2000, count, count + 1)
	end
	g.comps[500] = { CONSTRUCTION = { frozenNodes = frozen, frozenEdges = edges } }
	g.env = { api = { type = { ComponentType = { CONSTRUCTION = "CONSTRUCTION", BASE_NODE = "BASE_NODE", BASE_EDGE = "BASE_EDGE" } },
		engine = {
			getComponent = function(id, ct) return g.comps[id] and g.comps[id][ct] end,
			forEachEntityWithComponent = function(fn, ct)
				for id, c in pairs(g.comps) do if c[ct] then fn(id) end end
			end,
			system = { streetSystem = {
				getNodeSegments = function(id) return g.segments[id] or {} end,
				getNode2SegmentMap = function() return g.segments end,
			}, streetConnectorSystem = { getNode2StreetConnectorMap = function() return {} end } },
		} } }
	return g
end
local function capture(file)
	local f = assert(io.open("tests/fixtures/" .. (file or "altlandsberg-station-v57.b5"), "rb"))
	local line = f:read("*a"):gsub("%s+$", ""); f:close()
	return assert(build.deserialize(line))
end

test("real v57 Altlandsberg source contains internal station configurations without captured outside access", function()
	local data = capture()
	assert(#data.constructions == 1 and #data.configs == 25)
	assert(#data.segments == 0 and next(data.gates) == nil and next(data.access) == nil)
	for _, c in ipairs(data.configs) do assert(#c.conns == 0 and #c.walks == 0) end
	assert(weld.connection_required(data) == false)
end)

test("open station track nodes do not fail a confirmed native build without a captured access requirement", function()
	local g = graph(25, false, true)
	local st = weld.status(g.env, 500, {}, weld.connection_required(capture()))
	assert(st.confirmed == true and st.connection_required == false)
	assert(st.welded == false, "do not claim an external connection that does not exist")
	assert(st.text:find("external network connection not required", 1, true), st.text)
end)

-- This is the later upgrade associated with an actual failed receipt, not the initial open
-- station build above. Its source was WELDED, but the preceding incoming track build (.64)
-- failed on the receiver. These connection errors must remain visible until that track exists.
test("real failed v57 Altlandsberg upgrade retains its mandatory outside connection after dropping native access", function()
	local data = capture("altlandsberg-upgrade-v57.b5")
	assert(#data.constructions == 1 and #data.demolished == 1)
	assert(#data.removed_segments == 30 and #data.configs == 38)
	assert(#data.segments == 1 and data.access[-1] and data.gates[-1])
	assert(weld.connection_required(data))
	data.gate_positions = weld.gate_positions(data)
	assert(#data.gate_positions == 1 and data.gate_positions[1].y == 4390.678)
	build.drop_access(data)
	assert(#data.segments == 0 and next(data.gates) == nil and next(data.access) == nil)
	assert(weld.connection_required(data), "native entrance ownership must not erase the source requirement")
	local g = graph(25, false, true)
	local st = weld.status(g.env, 500, data.gate_positions, weld.connection_required(data))
	assert(st.confirmed == false and st.welded == false,
		"a missing track approach remains a failed connection check: " .. st.text)
end)

test("real Altlandsberg upgrade is confirmed when its required outside track exists", function()
	local data = capture("altlandsberg-upgrade-v57.b5")
	local g = graph(25, true, true)
	local st = weld.status(g.env, 500, weld.gate_positions(data), weld.connection_required(data))
	assert(st.confirmed and st.welded == true, st.text)
end)

test("an explicit source gate keeps the outside connection mandatory", function()
	local g = graph(3, false)
	local data = { gate_positions = { point() } }
	assert(weld.connection_required(data))
	local st = weld.status(g.env, 500, data.gate_positions, weld.connection_required(data))
	assert(st.welded == false and st.confirmed == false)
end)

test("wire gate and access markers are both retained as source evidence", function()
	assert(weld.connection_required({ gates = { [-1] = true } }))
	assert(weld.connection_required({ access = { [-2] = true } }))
	assert(not weld.connection_required({ gates = {}, access = {}, gate_positions = {} }))
end)

test("a connected depot or station gate remains confirmed", function()
	local g = graph(3, true)
	local st = weld.status(g.env, 500, { point() }, true)
	assert(st.welded == true and st.confirmed == true and st.connection_required == true)
end)

test("saved checks without a source-expectation field remain strict", function()
	local g = graph(3, false)
	assert(weld.status(g.env, 500, {}).confirmed == false)
end)

test("missing constructions cannot be accepted by an optional outside-connection check", function()
	local g = graph(3, false); g.comps[500] = nil
	local st = weld.status(g.env, 500, {}, false)
	assert(not st.exists and not st.confirmed)
end)

test("the bounded search processes its last allowed node before deciding", function()
	local g = graph(weld.WALK_LIMIT, true)
	local st = weld.status(g.env, 500, {}, true)
	assert(st.welded == true and st.confirmed == true, st.text)
end)

test("search exhaustion means unknown instead of a proven disconnected construction", function()
	local g = graph(weld.WALK_LIMIT + 3, true)
	local st = weld.status(g.env, 500, {}, true)
	assert(st.welded == nil and st.limited and not st.confirmed)
	assert(st.text:find("search limit", 1, true) and st.text:find("UNKNOWN", 1, true), st.text)
end)

test("large optional station graphs still pass without inventing a connection", function()
	local g = graph(weld.WALK_LIMIT + 3, false)
	local st = weld.status(g.env, 500, {}, false)
	assert(st.welded == nil and st.limited and st.confirmed)
end)

test("large station diagnostics are bounded without dropping graph checks", function()
	local g = graph(25, false, true)
	local st = weld.status(g.env, 500, {}, false)
	assert(#st.gates == 25 and st.confirmed)
	assert(st.text:find("17 further frozen nodes", 1, true), st.text)
	assert(#st.text < 2000, #st.text)
end)

print(string.format("%d station regression tests passed; %d failed", passed, failures))
assert(failures == 0, "station regressions failed")

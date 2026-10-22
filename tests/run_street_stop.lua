-- Street-stop parcel regressions: native API boundaries, one atomic command, no game process.
local real_require, loaded = require, {}
function require(name)
	if name:sub(1, 1) ~= "/" then return real_require(name) end
	if not loaded[name] then loaded[name] = assert(loadfile("mods/mp_probe/content" .. name))() end
	return loaded[name]
end
local build = require("/mp_probe/build.lua")
local copy = require("/mp_probe/wire.lua").copy
local passed, failures = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function fixture()
	local f = assert(io.open("tests/fixtures/street-stop-parcel-v61.b5", "r"))
	local data = assert(build.deserialize(f:read("*l"))); f:close()
	assert(build.resolve(data, {
		find_node = function(p) return p.x > -900 and 70718 or 71018 end,
		find_edge = function() return 71019 end,
	}))
	return data
end
local function mock(options)
	options = options or {}
	local m = { sent = {}, constructed = {}, helpers = 0, logs = {}, payloads = {} }
	local function new() return {} end
	local types = { SimpleProposal = { new = function() return { streetProposal = {} } end },
		SimpleStreetProposal = { EdgeObject = { new = new } },
		Context = { new = new }, SegmentAndEntity = { new = function() return { comp = {} } end },
		LaneConfig = { new = new }, BaseEdgeStreet = { new = new }, PlayerOwned = { new = new },
		Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } }
	local parcel_data = options.parcels or { leftEntities = { 71042 }, rightParcels = {} }
	local engine = { system = {
		parcelSystem = { getParcelData = function(id) assert(id == 71019); return copy(parcel_data) end },
		townBuildingSystem = { hasBuilding = function(id)
			assert(id == 71042 or id == 71043); return options.occupied == true
		end },
	}, util = { proposal = { makeSegmentsRemoveProposal = function(ids)
		assert(#ids == 1 and ids[1] == 71019); m.helpers = m.helpers + 1
		-- Extra helpers' removals must never be adopted wholesale (e.g. occupied town houses).
		return { toRemove = options.cleanup or { 71042, 99000 } }
	end } } }
	local cmd = {}
	function cmd.makeWorldBuildProposalCmd(p, context, ignore, initiated)
		m.constructed[#m.constructed + 1] = { context = copy(context), initiated = initiated }
		local full
		if p.streetProposal then
			full = { toAdd = {}, toRemove = options.existing or {}, proposal = {
				addedSegments = copy(p.streetProposal.edgesToAdd),
				removedSegments = { { entity = 71019 } },
				edgeObjectsToAdd = copy(p.streetProposal.edgeObjectsToAdd),
			} }
		else full = copy(p) end
		if options.lose_removal and not p.streetProposal then full.toRemove = {} end
		if options.opaque then
			local command = setmetatable({}, {__index=function() if options.throw_on_preview then error("opaque command") end end})
			m.payloads[command] = full
			return command
		end
		return { proposal = full, context = copy(context) }
	end
	function cmd.sendCommand(c, callback)
		m.sent[#m.sent + 1] = c
		local included = false
		local full = m.payloads[c] or c.proposal
		for _, id in ipairs(full.toRemove) do if id == 71042 then included = true end end
		local critical = not included or options.reject == true
		if callback then callback({ resultEntities = critical and {} or { 191256 }, resultProposalData = {
			costs = critical and 0 or 100, errorState = { critical = critical,
				messages = critical and { "Unexpected parcel on a segment" } or {} } } }, not critical) end
	end
	m.env = { api = { type = types, engine = engine, cmd = cmd } }
	function m.run()
		local result
		local ok, message = build.replay(m.env, fixture(), { player = 63166,
			log = function(l) m.logs[#m.logs + 1] = l end,
			on_result = function(_, success, _, outcome) result = { success = success, outcome = outcome } end,
		})
		return ok, message, result
	end
	return m
end

test("recorded failure is a right-side ordinary street stop close to a junction", function()
	local data = fixture()
	assert(#data.segments == 1 and data.segments[1].type == 0)
	assert(data.segments[1].roadTemplate:find("town_old_small", 1, true))
	assert(data.removed_segments[1].entity == 71019 and #data.objects == 1)
	assert(data.objects[1].left == false and data.objects[1].param == 0.011329205706715584)
	assert(data.objects[1].name == "Haltestelle #25")
end)

test("the recorded stop removes its empty native parcel in one atomic build", function()
	local m = mock(); local ok, message, result = m.run()
	assert(ok, tostring(message)); assert(result.success and result.outcome.built)
	assert(#m.sent == 1 and #m.constructed == 2 and m.helpers == 1)
	local p = m.sent[1].proposal
	assert(#p.toRemove == 1 and p.toRemove[1] == 71042, "ignore unrelated native removals")
	assert(#p.proposal.addedSegments == 1 and #p.proposal.edgeObjectsToAdd == 1)
	assert(p.proposal.edgeObjectsToAdd[1].param == 0.011329205706715584)
	assert(p.proposal.edgeObjectsToAdd[1].left == false)
	assert(m.constructed[2].initiated == false and m.sent[1].context.cleanupStreetGraph == false)
	assert(table.concat(m.logs, "\n"):find("one atomic build", 1, true))
end)

test("existing native parcel removals are retained without creating another command", function()
	local m = mock({ existing = { 71042, 900 } }); assert(m.run())
	assert(#m.constructed == 1 and #m.sent == 1 and m.helpers == 0)
	assert(#m.sent[1].proposal.toRemove == 2)
end)

test("occupied additional parcels fail before any build or demolition is sent", function()
	local m = mock({ occupied = true }); local ok, message = m.run()
	assert(not ok and message:find("occupied town parcel 71042", 1, true), tostring(message))
	assert(#m.sent == 0 and m.helpers == 0)
end)

test("native helper must explicitly authorize the empty parcel removal", function()
	local m = mock({ cleanup = { 99999 } }); local ok, message = m.run()
	assert(not ok and message:find("did not prepare empty parcel 71042", 1, true), tostring(message))
	assert(#m.sent == 0)
end)

test("reprepared proposals that drop a required removal are never executed", function()
	local m = mock({ lose_removal = true }); local ok, message = m.run()
	assert(not ok and message:find("lost parcel removals", 1, true), tostring(message)); assert(#m.sent == 0)
end)

test("unknown occupancy is not interpreted as an empty parcel", function()
	local m = mock(); m.env.api.engine.system.townBuildingSystem.hasBuilding = function() return nil end
	local ok, message = m.run()
	assert(not ok and message:find("parcel occupancy unreadable", 1, true), tostring(message)); assert(#m.sent == 0)
end)

test("documented and symmetrical native parcel lists deduplicate one parcel", function()
	local m = mock({ parcels = { leftEntities = { 71042 }, leftParcels = { 71042 }, rightParcels = {}, rightEntities = {} } })
	assert(m.run()); assert(#m.sent == 1 and #m.sent[1].proposal.toRemove == 1)
end)

test("unreadable nonempty parcel data fails before a potentially unsafe build", function()
	local m = mock({ parcels = { unexpectedField = { 71042 } } }); local ok, message = m.run()
	assert(not ok and message:find("parcel lists unreadable", 1, true), tostring(message)); assert(#m.sent == 0)
end)

test("missing native helper fails before executing a street with unhandled parcels", function()
	local m = mock(); m.env.api.engine.util.proposal.makeSegmentsRemoveProposal = nil
	local ok, message = m.run()
	assert(not ok and message:find("helper unavailable", 1, true), tostring(message)); assert(#m.sent == 0)
end)

test("native rejection of the prepared stop is reported without a second execution", function()
	local m = mock({ reject = true }); local ok, message, result = m.run()
	assert(not ok and result.success == false and result.outcome.built == false, tostring(message))
	assert(#m.sent == 1)
end)

test("ordinary rail and construction commands bypass the stop-only composition", function()
	local m = mock(); local context = build.make_context(m.env, 63166)
	for _, source in ipairs({ { streetProposal = { edgesToAdd = { { type = 1 } }, edgesToRemove = { 71019 },
		edgeObjectsToAdd = { { model = "::/signals/rail/signal.mdl" } } } },
		{ constructionsToAdd = { { fileName = "station.con" } } } }) do
		local command = { unchanged = true }
		assert(build.prepare_stop_parcels(m.env, source, command, context) == command)
	end
	assert(m.helpers == 0 and #m.constructed == 0 and #m.sent == 0)
end)

test("opaque native commands execute the original build once without a preview nil error", function()
	for _, throws in ipairs({false,true}) do
		local m=mock({opaque=true,throw_on_preview=throws,existing={71042}})
		local ok,message,result=m.run()
		assert(ok and result.success and result.outcome.built,tostring(message))
		assert(#m.sent==1 and #m.constructed==1 and m.helpers==0)
		assert(table.concat(m.logs,"\n"):find("command preview unavailable",1,true))
	end
end)
test("an opaque native rejection remains a rejection without speculative demolition", function()
	local m=mock({opaque=true}); local ok,message,result=m.run()
	assert(not ok and result.success==false and #m.sent==1 and m.helpers==0,tostring(message))
	assert(not tostring(message):find("attempt to index",1,true))
end)

print(string.format("Street stop regressions: %d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) end

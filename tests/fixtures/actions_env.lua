-- Shared read-only engine/command fixture using the shipped TF3 signatures.
local dependencies = ... or {}
local wire = dependencies.wire or require("/mp_probe/wire.lua")
local actions = dependencies.actions or require("/mp_probe/actions.lua")
local function copy(v) return wire.copy(v) end
local function xyz(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
local function transform(x, y)
	return { { x = 1, y = 0, z = 0, w = 0 }, { x = 0, y = 1, z = 0, w = 0 },
		{ x = 0, y = 0, z = 1, w = 0 }, { x = x or 0, y = y or 0, z = 0, w = 1 } }
end
local function mock()
	local m = { entities = { [7] = { NAME = { name = "Transport AG" } } }, sent = {}, next_id = 1000, logs = {} }
	local ct = {}; for _, k in ipairs({ "NAME", "COLOR", "PLAYER_OWNED", "CONSTRUCTION", "LINE",
		"TRANSPORT_VEHICLE", "STATION_GROUP", "BASE_EDGE", "EDGE_OBJECT", "STATION", "CARRIAGE_LIST", "CARRIAGE",
		"ACCOUNT" }) do ct[k] = k end
	local function new() return {} end
	local function proposal() return { streetProposal = {} } end
	local t = { ComponentType = ct, Context = { new = new },
		SimpleProposal = { new = proposal, ConstructionEntity = { new = new } },
		Line = { new = new, Stop = { new = new }, StopConfig = { new = new } },
		LineVehicleInfo = { new = new }, VehiclePart = { new = new }, LoadConfig = { new = new },
		TransportVehiclePart = { new = new }, TransportVehicleConfig = { new = new },
		EdgeId = { new = new }, EdgePos = { new = new }, Waypoint = { new = new },
		StationTerminal = { new = function(s, terminal) return { station = s, terminal = terminal } end },
		Vec3f = { new = xyz }, Vec4f = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end },
		Mat4f = { cols = function(value, i) return copy(value[i]) end,
			new = function(a, b, c, d) return { a, b, c, d } end },
		enum = { TransportVehicleState = { IN_DEPOT = 0, EN_ROUTE = 1, AT_TERMINAL = 2, GOING_TO_DEPOT = 3 } },
		JournalEntry = { new = function() return { category = {} } end, Type = { LOAN = 4, OTHER = 9 } } }
	local engine = { util = { getPlayer = function() return 7 end }, system = {} }
	function engine.getComponent(id, c)
		assert(m.entities[id], "entity missing")
		-- Copy-on-read like the C++ bindings; a nested assignment must be written back.
		return m.entities[id][c] and copy(m.entities[id][c])
	end
	function engine.forEachEntityWithComponent(fn, c)
		if m.fail == c then error("simulated read failure") end
		for id, e in pairs(m.entities) do if e[c] then fn(id) end end
	end
	engine.system.lineSystem = { getLines = function()
		local list = {}; engine.forEachEntityWithComponent(function(id) list[#list + 1] = id end, "LINE"); return list
	end }
	engine.system.streetSystem = { getNode2SegmentMap = function()
		local map = {}; for id, e in pairs(m.entities) do if e.BASE_EDGE then map[id] = { id } end end; return map
	end }
	engine.system.streetConnectorSystem = {
		getConstructionEntityForDepot = function(id) return m.parents[id] end,
		getConstructionEntityForStation = function(id) return m.parents[id] end,
		getConstructionEntityForEdge = function() return -1 end,
	}
	engine.system.stationGroupSystem = { getStationGroup = function(id)
		assert(id ~= nil, "getStationGroup called with nil")
		return m.groups[id]
	end }
	local cmd = {}
	local signatures = { makeLineCreateCmd = 4, makeLineUpdateCmd = 2, makeLineDestroyCmd = 1,
		makeVehicleBuyCmd = 3, makeVehicleReplaceCmd = 2, makeVehicleSellCmd = 1,
		makeVehicleSetLineCmd = 3, makeVehicleSetStoppedByUserCmd = 2, makeVehicleSetManualDepartureCmd = 2,
		makeEntitySetNameCmd = 2, makeEntitySetColorCmd = 2, makeWorldBuildProposalCmd = 4,
		makeVehicleSendToDepotCmd = 2, makeVehicleReverseCmd = 1, makeJournalBookAssetCmd = 3,
		makeScriptingSendEventCmd = 4 }
	for name, n in pairs(signatures) do
		cmd[name] = function(...)
			assert(select("#", ...) == n, name .. " signature")
			return { name = name, args = { ... } }
		end
	end
	local function base(id, name)
		m.entities[id] = { NAME = { name = name or "" }, PLAYER_OWNED = { player = 7 } }
		return m.entities[id]
	end
	m.parents, m.groups = {}, {}
	function m.construction(id, x, y, file, params)
		local e = base(id, "Station " .. id)
		e.CONSTRUCTION = { fileName = file or "::/station.con", params = params or { seed = 3, year = 1850, modules = {} },
			transf = transform(x, y), depots = { id + 10000 }, stations = { id + 20000 } }
		m.parents[id + 10000], m.parents[id + 20000], m.groups[id + 20000] = id, id, id + 30000
		m.entities[id + 30000] = { STATION_GROUP = { stations = { id + 20000 } } }
		return e
	end
	-- A street stop: a station without construction that is an edge object (run 19).
	function m.street_stop(id, x, y)
		local e = base(id, "Stop " .. id)
		e.EDGE_OBJECT = { param = 0.5, transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, 2, 1 } }
		e.STATION = { catchmentAreas = { { position = xyz(x, y, 2), radius = 100 } } }
		m.parents[id], m.groups[id] = -1, id + 30000
		m.entities[id + 30000] = { STATION_GROUP = { stations = { id } } }
		return e
	end
	function m.line(id, name, station)
		local e = base(id, name or ("Line " .. id))
		e.COLOR = { color = xyz(1, 0.3, 0.5) }
		e.LINE = { customFilters = true, reservationPriority = 2, vehicleInfo = { transportModes = { [0] = true, [1] = false } }, stops = {} }
		if station then
			e.LINE.stops = { { stationGroup = m.groups[station], station = 0, terminal = 1, loadMode = 2,
				minWaitingTime = 3, maxWaitingTime = 30, maxAdditionalWaitingTime = 5, waypoints = {},
				alternativeTerminals = { { station = 0, terminal = 2 } },
				stopConfig = { load = { [0] = true, [1] = false }, maxLoad = { [0] = 1, [1] = 0.3 },
					forceUnload = true, destroyForConfigChange = false, destroyForRefresh = true } } }
		end
		return e
	end
	function m.config()
		return { vehicles = { { part = { modelId = 5, reversed = true,
			compartment2loadConfig = { [0] = -1 }, color = xyz(0.4, 0.5, 0.6) }, autoLoadConfig = { [0] = true } } },
			vehicleGroups = { 1 }, muFileNames = { "" } }
	end
	function m.vehicle(id, depot, line)
		local e = base(id, "Bus " .. id)
		e.TRANSPORT_VEHICLE = { transportVehicleConfig = m.config(), depot = depot or -1, line = line or -1,
			userStopped = false, autoDeparture = true, stopIndex = 0 }
		return e
	end
	-- A train driving (state EN_ROUTE) with one carriage that says which way it runs.
	function m.train(id, line)
		local e = m.vehicle(id, nil, line)
		e.TRANSPORT_VEHICLE.state = 1
		e.CARRIAGE_LIST = { carriages = { id + 500 } }
		m.entities[id + 500] = { CARRIAGE = { reversed = false } }
		return e
	end
	function m.account(loan)
		m.entities[7].ACCOUNT = { loan = loan or 0, balance = 1000000 }
	end
	function m.loan_script(obtained, free_id)
		ct.GAME_SCRIPT = "GAME_SCRIPT"
		m.entities[8] = { GAME_SCRIPT = { state = { availableLoans = {}, obtainedLoans = obtained or {}, freeId = free_id or 0 } } }
		engine.system.gameScriptSystem = { getEntityForGameScript = function(path)
			assert(path == "::/game_mechanics/finance/loan.gs", "wrong original loan script")
			return 8
		end }
	end
	function m.edge(id, x, y)
		local e = base(id)
		e.BASE_EDGE = { position0 = xyz(x, y), position1 = xyz(x + 10, y), tangent0 = xyz(10),
			tangent1 = xyz(10), roadTemplate = "::/small.street_template", roadStyle = "::/old.street" }
		return e
	end
	local function execute(c, callback)
		assert(not m.in_callback, "sendCommand called from a native callback")
		local a, result = c.args, {}
		m.sent[#m.sent + 1] = c
		if m.reject then callback({}, false); return end
		if c.name == "makeVehicleSetLineCmd" and m.required_stop ~= nil and a[3] ~= m.required_stop then
			callback({}, false); return
		end
		if c.name == "makeWorldBuildProposalCmd" then
			assert(a[4] == false, "remote builds must not be playerInitiated")
			local p = a[1]
			for _, id in ipairs(p.constructionsToRemove or {}) do m.entities[id] = nil end
			for _, id in ipairs(p.streetProposal.edgesToRemove or {}) do m.entities[id] = nil end
			for _, con in ipairs(p.constructionsToAdd or {}) do
				m.next_id = m.next_id + 1
				local e = m.construction(m.next_id, con.transf[4].x, con.transf[4].y, con.fileName, con.params)
				e.CONSTRUCTION.transf, e.NAME.name = copy(con.transf), con.name
				result.resultEntities = { { m.next_id, 1 } }
			end
		elseif c.name == "makeLineCreateCmd" then
			m.next_id = m.next_id + 1; local e = m.line(m.next_id, a[1])
			e.LINE, e.COLOR.color = copy(a[4]), copy(a[2]); result.resultEntity = m.next_id
		elseif c.name == "makeLineUpdateCmd" then m.entities[a[1]].LINE = copy(a[2])
		elseif c.name == "makeLineDestroyCmd" then m.entities[a[1]] = nil
		elseif c.name == "makeVehicleBuyCmd" then
			m.next_id = m.next_id + 1; local e = m.vehicle(m.next_id, a[2])
			e.TRANSPORT_VEHICLE.transportVehicleConfig = copy(a[3]); result.resultVehicleEntity = m.next_id
		elseif c.name == "makeVehicleReplaceCmd" then m.entities[a[1]].TRANSPORT_VEHICLE.transportVehicleConfig = copy(a[2])
		elseif c.name == "makeVehicleSellCmd" then for _, id in ipairs(a[1]) do m.entities[id] = nil end
		elseif c.name == "makeVehicleSetLineCmd" then
			local vehicle = m.entities[a[1]].TRANSPORT_VEHICLE
			vehicle.line, vehicle.stopIndex = a[2], a[3]
		elseif c.name == "makeVehicleSetStoppedByUserCmd" then m.entities[a[1]].TRANSPORT_VEHICLE.userStopped = a[2]
		elseif c.name == "makeVehicleSetManualDepartureCmd" then m.entities[a[1]].TRANSPORT_VEHICLE.autoDeparture = not a[2]
		elseif c.name == "makeVehicleSendToDepotCmd" then
			-- slow_state: the game shows the new state only a step later.
			local vehicle = m.entities[a[1]].TRANSPORT_VEHICLE
			if not m.slow_state then vehicle.state, vehicle.sellOnArrival = 3, a[2] end
		elseif c.name == "makeVehicleReverseCmd" then
			local carriage = m.entities[m.entities[a[1]].CARRIAGE_LIST.carriages[1]].CARRIAGE
			carriage.reversed = not carriage.reversed
		elseif c.name == "makeJournalBookAssetCmd" then
			assert(a[1] == 7 and a[2].category.type == 4, "not a loan booking for the player")
			assert(a[3].x == 0 and a[3].y == 0 and a[3].z == 0, "loan booking lacks original position")
			m.entities[7].ACCOUNT.loan = m.entities[7].ACCOUNT.loan + a[2].amount
		elseif c.name == "makeScriptingSendEventCmd" and a[2] == "Loan" then
			local loans, obtained = m.entities[8].GAME_SCRIPT.state, a[4][2]
			if not m.reject_loan_event then
				if a[3] == "Obtain" then
					local loan = copy(obtained); loan.id = loans.freeId; loans.freeId = loans.freeId + 1
					loan.timesPaid, loan.lastPayDay = 0, 0
					loans.obtainedLoans[#loans.obtainedLoans + 1] = loan
					m.entities[7].ACCOUNT.loan = m.entities[7].ACCOUNT.loan + loan.amount
				else
					for i, loan in ipairs(loans.obtainedLoans) do
						if loan.id == obtained.id then table.remove(loans.obtainedLoans, i); break end
					end
				end
			end
		elseif c.name == "makeEntitySetNameCmd" then m.entities[a[1]].NAME.name = a[2]
		elseif c.name == "makeEntitySetColorCmd" then m.entities[a[1]].COLOR.color = copy(a[2]) end
		m.in_callback = true
		callback(result, true)
		m.in_callback = false
	end
	cmd.sendCommand = function(c, callback)
		if m.defer then m.pending = { c, callback } else execute(c, callback) end
	end
	function m.complete()
		local p = m.pending; m.pending = nil; execute(p[1], p[2])
	end
	m.env = { api = { type = t, cmd = cmd, engine = engine,
		res = { modelRep = { getName = function(id) assert(id == 5 or id == 77); return "::/bus.mdl" end,
			find = function(name) return name == "::/bus.mdl" and 77 or -1 end } } } }
	local saved = {}
	m.state = { get = function() return copy(saved) end, set = function(_, s) saved = copy(s) end }
	function m.poll()
		local s = m.state:get(); actions.poll(m.env, s, function(msg) m.logs[#m.logs + 1] = msg end); m.state:set(s)
	end
	function m.drain()
		local s, out = m.state:get(), {}
		while true do local line = actions.next_line(s); if not line then break end; out[#out + 1] = assert(actions.decode(line)) end
		m.state:set(s); return out
	end
	function m.replay(action, offset)
		local ok = actions.replay(m.env, copy(action), m.state, "sender", offset or 0,
			function(msg) m.logs[#m.logs + 1] = msg end)
		if not m.defer then m.finish() end
		return ok
	end
	function m.finish()
		while #(m.state:get().action_work or {}) > 0 do
			actions.continue(m.env, m.state, function(msg) m.logs[#m.logs + 1] = msg end)
		end
	end
	return m
end

return { mock = mock, copy = copy, xyz = xyz, transform = transform }

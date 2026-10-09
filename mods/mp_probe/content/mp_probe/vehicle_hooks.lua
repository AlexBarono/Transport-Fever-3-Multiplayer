--- Pre-execution vehicle command interception, shared by the game GUI and game-script GUI.
-- Dependencies are injected when installed; callbacks never resolve another mod namespace.
local hooks = {}

hooks.VEHICLE_COMMANDS = { makeVehicleReverseCmd = "reverse", makeVehicleSetStoppedByUserCmd = "stopped",
	makeVehicleSendToDepotCmd = "depot", makeVehicleSetLineCmd = "line", makeVehicleSellCmd = "sell" }
hooks.VEHICLE_HOOKS = 6
--- Most commands in one batch.
hooks.MAX_BATCH = 40

--- What a maker's arguments mean for the simulation (plain data), or nil when they cannot travel.
function hooks.vehicle_args(command, a, b, c)
	local function id(v) return type(v) == "number" and v >= 0 and v % 1 == 0 end
	if command == "sell" then
		local list = {}
		local ok = pcall(function()
			for i = 1, #a do
				local v = a[i]
				assert(id(v)); list[i] = v
			end
		end)
		if not ok or #list == 0 then return nil end
		return { command = command, vehicles = list }
	end
	if not id(a) then return nil end
	if command == "line" then
		if type(b) ~= "number" or b % 1 ~= 0 then return nil end
		return { command = command, vehicle = a, value = b, stop = id(c) and c or 0 }
	end
	return { command = command, vehicle = a, value = b == true }
end

local function describe(t)
	if t.command == "sell" then return "sell of " .. #t.vehicles .. " vehicle(s)" end
	return t.command .. " for " .. tostring(t.vehicle)
end

function hooks.watch_vehicles(env, m, options)
	m.options = options
	if m.vehicle_hooks ~= nil then return end
	m.vehicle_hooks = 0
	m.marked = setmetatable({}, { __mode = "k" })
	m.batch = {}
	local cmd = env.api and env.api.cmd
	local missing = {}
	for maker, command in pairs(hooks.VEHICLE_COMMANDS) do
		local ok, err = pcall(function()
			local original = cmd[maker]
			assert(original ~= nil, maker .. " missing")
			local hook = function(a, b, c, ...)
				local made = original(a, b, c, ...)
				local args = hooks.vehicle_args(command, a, b, c)
				if args and made ~= nil then pcall(function() m.marked[made] = args end) end
				return made
			end
			cmd[maker] = hook
			assert(cmd[maker] == hook, "api.cmd did not keep the hook")
		end)
		if ok then m.vehicle_hooks = m.vehicle_hooks + 1 else missing[#missing + 1] = tostring(err):sub(1, 100) end
	end
	local ok, err = pcall(function()
		local send = cmd and cmd.sendCommand
		assert(send ~= nil, "sendCommand missing")
		m.send = send
		local hook = function(c, callback, ...)
			local args = c ~= nil and m.marked[c] or nil
			if args then m.marked[c] = nil end
			if args and m.options.timed() then
				-- A large manager selection must not let command 41 bypass the timeline.
				if #m.batch >= hooks.MAX_BATCH then hooks.flush_vehicles(env, m) end
				m.batch[#m.batch + 1] = { args = args, command = c, callback = callback, at = m.options.clock() }
				m.options.log("vehicle " .. describe(args) .. " clicked; both games run it at a common tick")
				if callback then
					-- As if it had run: TF3's windows count their open commands down in the callback.
					local ok_cb, why = pcall(callback, c, true, {})
					if not ok_cb then m.options.log("vehicle " .. args.command .. ": the window's callback failed (" .. tostring(why):sub(1, 120) .. ")") end
				end
				return
			end
			local result = send(c, callback, ...)
			if args and args.command == "reverse" then
				local sent, why = pcall(m.options.reverse, args.vehicle)
				if not sent then m.options.log("reverse: could not tell the simulation (" .. tostring(why):sub(1, 160) .. ")") end
			end
			return result
		end
		cmd.sendCommand = hook
		assert(cmd.sendCommand == hook, "api.cmd did not keep the sendCommand hook")
	end)
	if ok then m.vehicle_hooks = m.vehicle_hooks + 1 else missing[#missing + 1] = tostring(err):sub(1, 100) end
	m.options.log("vehicle hooks: " .. m.vehicle_hooks .. " of " .. hooks.VEHICLE_HOOKS .. " installed" ..
		(#missing > 0 and (" (" .. table.concat(missing, "; ") .. ")") or ""))
end

--- Every GUI step: hands the collected vehicle commands to the simulation as one script event.
-- If that is impossible, TF3's own commands run here at once and travel as before.
function hooks.flush_vehicles(env, m)
	local batch = m.batch
	if not batch or #batch == 0 then return end
	m.batch = {}
	local list = {}
	for i, entry in ipairs(batch) do list[i] = entry.args end
	local ok, err = pcall(function()
		local cmd = env.api.cmd
		local event = cmd.makeScriptingSendEventCmd("mp_probe", "mp_probe_vehicle", "mp_probe_vehicle",
			{ batch = m.options.encode(list) })
		assert(event ~= nil, "no script event")
		;(m.send or cmd.sendCommand)(event)
	end)
	if ok then
		m.options.log("vehicle commands handed over: " .. #list)
		return
	end
	m.options.log("vehicle commands: no script event (" .. tostring(err):sub(1, 120) .. "); running them here now")
	for _, entry in ipairs(batch) do
		local sent, why = pcall(m.send or env.api.cmd.sendCommand, entry.command)
		if not sent then m.options.log("vehicle " .. entry.args.command .. " failed: " .. tostring(why):sub(1, 120)) end
		if sent and entry.args.command == "reverse" then pcall(m.options.reverse, entry.args.vehicle) end
	end
end


return hooks

--- Runs in the main game GUI state, alongside the native vehicle windows and manager.
-- The normal game-script guiUpdate runs elsewhere and cannot intercept their commands.
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local entry = ug_require "::/gui/main/mod_entry_point.tl"
local hooks = ug_require "mp_probe_1::/mp_probe/vehicle_hooks.lua"
local economy_hooks = ug_require "mp_probe_1::/mp_probe/economy_hooks.lua"
local menu_hooks = ug_require "mp_probe_1::/mp_probe/menu_hooks.lua"
local wire = ug_require "mp_probe_1::/mp_probe/wire.lua"
local env, memory, economy_memory, menu_memory = { api = api, os = os }, {}, {}, {}
local function get(key)
	local ok, value = pcall(function() return os.getenv(key) end)
	return ok and value or ""
end
local function output(message)
	-- The main GUI has log.verbose/warning/error, but no log.info. Use the same
	-- stdout output as the game scripts; diagnostics must never break a GUI recipe
	-- or interrupt an intercepted command before its queued batch is flushed.
	if not pcall(debugPrint, message) then pcall(print, message) end
end
local function note(text) output("[mp_probe]vehicle UI: " .. text) end
local function economy_issue(label, reason)
	economy_memory.issue_seq = (economy_memory.issue_seq or 0) + 1
	local token = "gui_economy_" .. get("TF3MP_ROLE") .. "." .. economy_memory.issue_seq
	local function hex(s) return tostring(s):gsub(".", function(c) return string.format("%02x", c:byte()) end) end
	local issue = "I1 " .. token .. " none " .. hex(label:sub(1, 320)) .. " " .. hex(reason:sub(1, 240))
	output("[mp_probe]action issue local " .. issue)
	output("[mp_probe]net send " .. issue)
end
local function vehicle_issue(args, reason)
	memory.issue_seq = (memory.issue_seq or 0) + 1
	local labels = { line = "Linie zuweisen", stopped = "Anhalten/Fortsetzen", reverse = "Umkehren", depot = "Ins Depot schicken", sell = "Verkaufen" }
	local label = "Fahrzeug: " .. (labels[args.command] or tostring(args.command)) .. " (" ..
		(args.vehicles and table.concat(args.vehicles, ", ") or tostring(args.vehicle)) .. ")"
	local function hex(s) return tostring(s):gsub(".", function(c) return string.format("%02x", c:byte()) end) end
	local issue = "I1 gui_vehicle_" .. get("TF3MP_ROLE") .. "." .. memory.issue_seq .. " none " .. hex(label:sub(1, 320)) .. " " .. hex(reason:sub(1, 240))
	output("[mp_probe]action issue local " .. issue)
	output("[mp_probe]net send " .. issue)
end
local function step()
	menu_hooks.watch(env, menu_memory, { log = note, enabled = function()
		local role = get("TF3MP_ROLE")
		return (role == "host" or role == "client") and get("TF3MP_ORDERING") == "1"
	end, publish = function(text) output("[mp_probe]net state menu " .. text) end })
	hooks.watch_vehicles(env, memory, {
		log = note, encode = wire.encode, issue = vehicle_issue,
		clock = function() return os.clock() end,
		timed = function()
			local role = get("TF3MP_ROLE")
			-- Startup, a reconnect or a failed timeline cannot authorize an
			-- unshared assignment. The simulation reports unavailable planning.
			return (role == "host" or role == "client") and get("TF3MP_ORDERING") == "1"
		end,
		reverse = function(id)
			if get("TF3MP_ROLE") ~= "host" and get("TF3MP_ROLE") ~= "client" then return end
			memory.send(api.cmd.makeScriptingSendEventCmd("mp_probe", "mp_probe_reverse", "mp_probe_reverse", { vehicle = id }))
		end,
	})
	economy_hooks.watch(env, economy_memory, { log = note, issue = economy_issue, timed = function()
		-- An unhealthy/warming timeline must report or queue financial clicks,
		-- never let an unshared payout through to the original command.
		local role = get("TF3MP_ROLE")
		return (role == "host" or role == "client") and get("TF3MP_ORDERING") == "1"
	end })
	hooks.flush_vehicles(env, memory)
end

local module = {
	VehicleHooks = react.RegisterPluginRecipe(entry.ModEntryPointExtension, "TF3MPVehicleHooks", function()
		step() -- Install before any clicks; react.onStep flushes all commands from one frame.
		react.onStep(step)
		return builtin.BoxLayout { children = {} }
	end),
}

-- Lua resource files export through data(); ug_require callers use the returned table.
-- Supporting both matches the script-resource loader as well as the GUI module loader.
function data() return module end
return module

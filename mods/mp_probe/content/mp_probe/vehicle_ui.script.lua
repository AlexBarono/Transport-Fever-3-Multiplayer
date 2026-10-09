--- Runs in the main game GUI state, alongside the native vehicle windows and manager.
-- The normal game-script guiUpdate runs elsewhere and cannot intercept their commands.
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local entry = ug_require "::/gui/main/mod_entry_point.tl"
local hooks = ug_require "mp_probe_1::/mp_probe/vehicle_hooks.lua"
local wire = ug_require "mp_probe_1::/mp_probe/wire.lua"
local env, memory = { api = api, os = os }, {}
local function get(key)
	local ok, value = pcall(function() return os.getenv(key) end)
	return ok and value or ""
end
local function note(text) log.info("[mp_probe]vehicle UI: " .. text) end
local function step()
	hooks.watch_vehicles(env, memory, {
		log = note, encode = wire.encode,
		clock = function() return os.clock() end,
		timed = function()
			local role = get("TF3MP_ROLE")
			return (role == "host" or role == "client") and get("TF3MP_ORDERING") == "1" and
				get("TF3MP_PEER_CLOCK"):find("gt=", 1, true) ~= nil and
				get("TF3MP_OWN_CLOCK"):find("phase=failed", 1, true) == nil
		end,
		reverse = function(id)
			if get("TF3MP_ROLE") ~= "host" and get("TF3MP_ROLE") ~= "client" then return end
			memory.send(api.cmd.makeScriptingSendEventCmd("mp_probe", "mp_probe_reverse", "mp_probe_reverse", { vehicle = id }))
		end,
	})
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

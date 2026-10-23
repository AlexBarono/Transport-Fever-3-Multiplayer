--- Observe TF3's actual pause-menu lifecycle in the native GUI Lua state.
local hooks = {}

function hooks.watch(env, memory, options)
	if memory.installed ~= nil then return end
	memory.installed = false
	local ok, why = pcall(function()
		local game = env.api.gui.game
		local original = game.setInGameMenuPause
		assert(original ~= nil, "setInGameMenuPause missing")
		local function publish(open)
			if not options.enabled() then return end
			options.publish("open=" .. (open and "1" or "0"))
		end
		local hook = function(open, ...)
			-- Native menu transitions can synchronously issue a speed command
			-- before the bridge has echoed open=1 into the environment.
			local changing = memory.changing
			memory.changing = true
			local ok, result = pcall(original, open, ...)
			memory.changing = changing
			if not ok then error(result, 0) end
			memory.open = open == true
			publish(memory.open)
			return result
		end
		game.setInGameMenuPause = hook
		assert(game.setInGameMenuPause == hook, "menu API did not keep the hook")
		memory.installed, memory.open = true, false
		publish(false) -- Clear a menu from the previous world when this GUI is recreated.
	end)
	options.log(ok and "menu pause hook installed" or ("menu pause hook unavailable: " .. tostring(why):sub(1, 180)))
end

return hooks

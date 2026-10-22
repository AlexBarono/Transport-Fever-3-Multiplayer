--- TF3's GameSpeedHelper retries a throttled request every GUI frame. While its
-- callbacks are outstanding it does not read external speed changes back. A
-- remote pause/1x/2x can consequently be overwritten by its old 4x request.
local hooks = {}

-- Native buttons expose 0/1/2/4 only. Keep a settled capacity-limited engine
-- speed tied to the shared user request in the main GUI's readback. Simulation
-- and game-script GUI states continue to read the real component unchanged.
function hooks.display_speed(actual, text)
	if type(text) ~= "string" or actual == 0 then return actual end
	local fields = {}
	for key, value in text:gmatch("(%w+)=(%S+)") do fields[key] = tonumber(value) or value end
	local requested, target = fields.speed, fields.tg
	if fields.src ~= "gui" or type(requested) ~= "number" or requested < 1 or requested > 4
		or requested ~= math.floor(requested) or actual ~= target then return actual end
	return requested == 3 and 4 or requested
end

function hooks.watch(env, memory, options)
	if memory.installed ~= nil then return end
	memory.installed = false
	local undo = {}
	local ok, why = pcall(function()
		local game = env.api.gui.game
		local original = assert(game.getEstimatedMaximumGameSpeed, "speed estimate missing")
		local engine = env.api.engine
		local component = engine and engine.getComponent
		local hook = function(...)
			-- The native main GUI sends the player's full request. The separate
			-- game-script GUI retains the real native estimate and is the sole
			-- controller of the common cap. Two competing controllers continually
			-- queued the native helper's old request over incoming remote changes.
			if options.enabled() then return 4 end
			return original(...)
		end
		undo[#undo + 1] = function() game.getEstimatedMaximumGameSpeed = original end
		game.getEstimatedMaximumGameSpeed = hook
		assert(game.getEstimatedMaximumGameSpeed == hook, "speed estimate hook not retained")
		if component and options.shared then
			local speed_type = assert(env.api.type.ComponentType.GAME_SPEED, "game speed type missing")
			local read = function(id, kind, ...)
				local result = component(id, kind, ...)
				if result and kind == speed_type and options.enabled() then
					local shown = hooks.display_speed(result.speedup, options.shared())
					if shown ~= result.speedup then
						return setmetatable({speedup = shown}, {__index = function(_, key) return result[key] end})
					end
				end
				return result
			end
			undo[#undo + 1] = function() engine.getComponent = component end
			engine.getComponent = read
			assert(engine.getComponent == read, "speed display hook not retained")
		end
		memory.installed = true
	end)
	if not ok then for i = #undo, 1, -1 do pcall(undo[i]) end end
	options.log(ok and "speed capacity retry guard installed" or ("speed capacity retry guard unavailable: " .. tostring(why):sub(1, 180)))
end

return hooks

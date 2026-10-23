--- TF3's GameSpeedHelper retries a throttled request every GUI frame. While its
-- callbacks are outstanding it does not read external speed changes back. A
-- remote pause/1x/2x can consequently be overwritten by its old 4x request.
local hooks = {}

-- Native buttons expose 0/1/2/4 only. Keep their selection tied to the shared
-- user request, including while an older engine command is pending. Simulation
-- and game-script GUI states continue to read the real component unchanged.
function hooks.display_speed(actual, text)
	if type(text) ~= "string" or actual == 0 then return actual end
	local fields = {}
	for key, value in text:gmatch("(%w+)=(%S+)") do fields[key] = tonumber(value) or value end
	local requested = fields.speed
	if fields.src ~= "gui" or type(requested) ~= "number" or requested < 0 or requested > 4
		or requested ~= math.floor(requested) then return actual end
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
		-- Capture the native GUI's explicit request, even when its numeric
		-- readback already equals a throttled target (4x capped to 2x -> click 2x).
		-- The separate game-script GUI sends controller commands in another Lua
		-- state, so those commands cannot be mistaken for clicks here.
		if options.publish and env.api.cmd and env.api.cmd.makeGameSetSpeedCmd then
			local cmd = env.api.cmd
			local make = cmd.makeGameSetSpeedCmd
			local request = function(value, ...)
				local command = make(value, ...)
				if options.enabled() and (not options.held or not options.held()) then
					local speed = value == 3 and 4 or value
					if speed == 0 or speed == 1 or speed == 2 or speed == 4 then
						local seq = options.intent and tonumber((options.intent() or ""):match("seq=(%d+)")) or 0
						memory.intent_seq = math.max(memory.intent_seq or 0, seq or 0) + 1
						pcall(options.publish, "seq=" .. memory.intent_seq .. " speed=" .. speed)
					end
				end
				return command
			end
			undo[#undo + 1] = function() cmd.makeGameSetSpeedCmd = make end
			cmd.makeGameSetSpeedCmd = request
			assert(cmd.makeGameSetSpeedCmd == request, "speed request hook not retained")
		end
		memory.installed = true
	end)
	if not ok then for i = #undo, 1, -1 do pcall(undo[i]) end end
	options.log(ok and "speed capacity retry guard installed" or ("speed capacity retry guard unavailable: " .. tostring(why):sub(1, 180)))
end

return hooks

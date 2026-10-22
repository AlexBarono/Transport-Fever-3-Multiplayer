-- Model TF3 GameSpeedHelper's per-frame capacity retry and delayed callbacks.
local hooks = assert(loadfile("mods/mp_probe/content/mp_probe/speed_hooks.lua"))()
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function model(guard)
	local m = { actual = 3, selected = 4, throttle = 1, pending = 0, capacity = 3, ordered = true, queue = {} }
	local game = { getEstimatedMaximumGameSpeed = function() return m.capacity end }
	if guard then
		hooks.watch({ api = { gui = { game = game } } }, {}, {
			log = function() end, enabled = function() return m.ordered end,
		})
	end
	function m.native_frame()
		m.recipe = "GameSpeedHelper"
		-- The original helper suspends its readback until all callbacks arrive.
		if m.pending == 0 and m.actual > 0 and m.actual ~= m.selected - m.throttle then
			m.selected, m.throttle = m.actual, 0
		end
		if m.selected > game.getEstimatedMaximumGameSpeed() then
			local target = math.min(m.selected, game.getEstimatedMaximumGameSpeed())
			m.pending = m.pending + 1
			m.queue[#m.queue + 1] = function() m.actual = target; m.pending = m.pending - 1 end
		end
		m.recipe = nil
	end
	function m.flush()
		local queue = m.queue; m.queue = {}
		for _, fn in ipairs(queue) do fn() end
	end
	m.game = game
	return m
end

test("unmodified native capacity retries overwrite received 1x and 2x", function()
	for _, target in ipairs({1, 2}) do
		local m = model(false); m.native_frame(); m.actual = target; m.flush()
		assert(m.actual == 3, "reproduce v62 failure")
	end
end)
test("guard lets a received pause, 1x or 2x reach the simulation and survive subsequent frames", function()
	for _, target in ipairs({0, 1, 2, 3, 4}) do
		local m = model(true); m.native_frame(); m.actual = target
		for _ = 1, 10 do m.native_frame(); m.flush() end
		assert(m.actual == target and m.pending == 0)
	end
end)
test("native GUI sends full requests while a separate game-script GUI retains the real cap", function()
	local m = model(true)
	local separate = {getEstimatedMaximumGameSpeed = function() return m.capacity end}
	assert(m.game.getEstimatedMaximumGameSpeed() == 4)
	assert(separate.getEstimatedMaximumGameSpeed() == 3)
	m.ordered = false; assert(m.game.getEstimatedMaximumGameSpeed() == 3)
end)
test("single-player and disconnected ordering keep the native throttle", function()
	local m = model(true); m.ordered = false; m.native_frame(); assert(m.pending == 1)
	m.flush(); assert(m.actual == 3)
end)
test("callable native API and repeated installation retain one wrapper", function()
	local game = { getEstimatedMaximumGameSpeed = setmetatable({}, {__call = function() return 2 end}) }
	local mem, logs = {}, {}
	local options = { enabled = function() return false end,
		log = function(line) logs[#logs + 1] = line end }
	hooks.watch({api = {gui = {game = game}}}, mem, options)
	local installed = game.getEstimatedMaximumGameSpeed
	hooks.watch({api = {gui = {game = game}}}, mem, options)
	assert(mem.installed and #logs == 1 and game.getEstimatedMaximumGameSpeed == installed)
	assert(installed() == 2)
end)
test("shared 4x stays selected when capacity changes to 3x or 2x", function()
	for _, actual in ipairs({2,3,4}) do
		assert(hooks.display_speed(actual,"src=gui speed=4 tg="..actual)==4)
	end
	assert(hooks.display_speed(0,"src=gui speed=4 tg=0")==0)
	assert(hooks.display_speed(1,"src=gui speed=4 tg=3")==1,"new user click must remain visible")
	assert(hooks.display_speed(2,"src=sim speed=4 tg=2")==2)
	assert(hooks.display_speed(3,"src=gui speed=3 tg=3")==4)
end)
test("main GUI projection preserves calendar and leaves actual simulation data untouched", function()
	local real={speedup=3,millisPerDay=4000}
	local api={gui={game={getEstimatedMaximumGameSpeed=function()return 3 end}},
		engine={getComponent=function()return real end},type={ComponentType={GAME_SPEED=7}}}
	local enabled=true
	hooks.watch({api=api},{},{log=function()end,enabled=function()return enabled end,
		shared=function()return "src=gui speed=4 tg=3" end})
	local shown=api.engine.getComponent(1,7)
	assert(shown.speedup==4 and shown.millisPerDay==4000 and real.speedup==3)
	assert(api.engine.getComponent(1,8)==real)
	enabled=false; assert(api.engine.getComponent(1,7)==real)
end)
test("failed native component hook rolls back the capacity hook", function()
	local estimate=function()return 3 end
	local read=function()return {speedup=3} end
	local engine=setmetatable({}, {__index={getComponent=read},__newindex=function()error("read-only native API")end})
	local api={gui={game={getEstimatedMaximumGameSpeed=estimate}},engine=engine,type={ComponentType={GAME_SPEED=1}}}
	local memory={}
	hooks.watch({api=api},memory,{enabled=function()return true end,shared=function()return "" end,log=function()end})
	assert(not memory.installed and api.gui.game.getEstimatedMaximumGameSpeed==estimate and engine.getComponent==read)
end)
print(string.format("Speed hooks: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

-- Execute the actual GUI entry module in isolated environments, not the game-script GUI.
local original_require = require
local hooks = assert(loadfile("mods/mp_probe/content/mp_probe/vehicle_hooks.lua"))()
local wire = assert(loadfile("mods/mp_probe/content/mp_probe/wire.lua"))()
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
local function gui(role, connected)
	local g = { sent={}, logs={}, steps={}, registrations=0, now=0, role=role, connected=connected }
	local cmd = {}
	for maker, kind in pairs(hooks.VEHICLE_COMMANDS) do
		cmd[maker] = function(a,b,c) return {kind=kind,a=a,b=b,c=c} end
	end
	cmd.sendCommand=function(c,cb) g.sent[#g.sent+1]=c; if cb then cb(c,true,{}) end end
	cmd.makeScriptingSendEventCmd=function(src,id,name,p) return {kind="event",name=name,param=p} end
	local react={ RegisterPluginRecipe=function(ep,name,fn)
		assert(ep=="game-main"); g.registrations=g.registrations+1; return fn
	end, onStep=function(fn) g.steps[#g.steps+1]=fn end }
	local env=setmetatable({api={cmd=cmd},os={clock=function()return g.now end,getenv=function(k)
		if k=="TF3MP_ROLE" then return g.role end
		if k=="TF3MP_ORDERING" then return g.connected and "1" or "0" end
		if k=="TF3MP_PEER_CLOCK" then return g.connected and "gt=1000" or "" end
		if k=="TF3MP_OWN_CLOCK" then return "phase="..(g.failed and "failed" or "idle") end
	end},log={info=function(s)g.logs[#g.logs+1]=s end}}, {__index=_G})
	env.ug_require=function(path)
		if path=="::/gui/main/react.lua" then return react end
		if path=="::/gui/main/builtin.lua" then return {BoxLayout=function(p)return p end} end
		if path=="::/gui/main/mod_entry_point.tl" then return {ModEntryPointExtension="game-main"} end
		if path=="mp_probe_1::/mp_probe/vehicle_hooks.lua" then return hooks end
		if path=="mp_probe_1::/mp_probe/wire.lua" then return wire end
		error("unexpected GUI module: "..path)
	end
	local path="mods/mp_probe/content/mp_probe/vehicle_ui.script.lua"
	local module
	if setfenv then local fn=assert(loadfile(path)); setfenv(fn,env); module=fn()
	else module=assert(loadfile(path,"t",env))() end
	g.recipe=module.VehicleHooks; g.recipe(); g.cmd=cmd
	function g.step() for _, fn in ipairs(g.steps) do fn() end end
	return g
end

test("main GUI captures all five window command types before execution and flushes once",function()
	for _, role in ipairs({"host","client"}) do
		local g=gui(role,true); local cb=0
		local list={g.cmd.makeVehicleReverseCmd(7),g.cmd.makeVehicleSetStoppedByUserCmd(7,true),
			g.cmd.makeVehicleSendToDepotCmd(7,true),g.cmd.makeVehicleSetLineCmd(7,9,2),g.cmd.makeVehicleSellCmd({7,8})}
		for _, c in ipairs(list) do g.cmd.sendCommand(c,function(_,ok)assert(ok); cb=cb+1 end) end
		assert(#g.sent==0 and cb==5, "the original vehicle commands must not execute early")
		g.step(); assert(#g.sent==1 and g.sent[1].name=="mp_probe_vehicle")
		local batch=assert(wire.decode(g.sent[1].param.batch)); assert(#batch==5 and batch[4].stop==2)
		g.step(); assert(#g.sent==1, "no repeated dispatch")
	end
end)

test("normal vehicle manager selections above forty stay on the common timeline",function()
	local g=gui("client",true)
	for i=1,85 do g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(i,9,1)) end
	g.step(); assert(#g.sent==3)
	local total=0
	for _, c in ipairs(g.sent) do assert(c.kind=="event"); total=total+#assert(wire.decode(c.param.batch)) end
	assert(total==85)
end)

test("single-player and a failed timeline pass through, remounts do not stack interception",function()
	local solo=gui("off",false)
	solo.cmd.sendCommand(solo.cmd.makeVehicleReverseCmd(7)); solo.step()
	assert(#solo.sent==1 and solo.sent[1].kind=="reverse")
	local g=gui("host",true); g.recipe()
	g.cmd.sendCommand(g.cmd.makeVehicleReverseCmd(8)); g.step()
	assert(#g.sent==1 and g.sent[1].kind=="event")
	g.failed=true; g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(7,9,0))
	assert(#g.sent==2 and g.sent[2].kind=="line")
end)

test("GUI resource registers the actual recipe in the game's main extension point",function()
	local old=data; assert(loadfile("mods/mp_probe/content/mp_probe/vehicle_ui.res.lua"))()
	local value=data(); data=old
	assert(value.type=="react-plugin ::ModEntryPointExtension")
	assert(value.data.filePath=="mp_probe_1::/mp_probe/vehicle_ui.script@VehicleHooks")
end)

print(string.format("%d main-GUI vehicle tests passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end

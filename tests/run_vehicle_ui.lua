-- Execute the actual GUI entry module in isolated environments, not the game-script GUI.
local original_require = require
local hooks = assert(loadfile("mods/mp_probe/content/mp_probe/vehicle_hooks.lua"))()
local economy_hooks = assert(loadfile("mods/mp_probe/content/mp_probe/economy_hooks.lua"))()
local menu_hooks = assert(loadfile("mods/mp_probe/content/mp_probe/menu_hooks.lua"))()
local speed_hooks = assert(loadfile("mods/mp_probe/content/mp_probe/speed_hooks.lua"))()
local wire = assert(loadfile("mods/mp_probe/content/mp_probe/wire.lua"))()
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
local function gui(role, connected, logging)
	local g = { sent={}, logs={}, steps={}, registrations=0, now=0, role=role, connected=connected }
	local cmd = {}
	for maker, kind in pairs(hooks.VEHICLE_COMMANDS) do
		cmd[maker] = function(a,b,c) return {kind=kind,a=a,b=b,c=c} end
	end
	cmd.sendCommand=function(c,cb)
		g.sent[#g.sent+1]=c
		if cb then
			if c.kind=="event" and g.defer_events then g.pending_callback=cb
			else cb(c,c.kind~="event" or g.event_success~=false,{}) end
		end
	end
	cmd.makeScriptingSendEventCmd=function(src,id,name,p) return {kind="event",name=name,param=p} end
	cmd.makeEntitySetNameCmd=function(id,name) return {kind="name",entity=id,name=name} end
	cmd.makeGameSetSpeedCmd=function(speed)return {kind="speed",speed=speed}end
	local react={ RegisterPluginRecipe=function(ep,name,fn)
		assert(ep=="game-main"); g.registrations=g.registrations+1; return fn
	end, onStep=function(fn) g.steps[#g.steps+1]=fn end }
	local game={setInGameMenuPause=function(value)
		if g.native_menu_speed then cmd.sendCommand(cmd.makeGameSetSpeedCmd(value and 0 or 1))end
		g.menu=value
	end,
		getEstimatedMaximumGameSpeed=function() return g.capacity or 3 end}
	local env=setmetatable({api={cmd=cmd,gui={game=game},engine={util={getPlayer=function()return 7 end}}},os={clock=function()return g.now end,getenv=function(k)
		if k=="TF3MP_ROLE" then return g.role end
		if k=="TF3MP_OWN_GUI" then return g.own_gui or "speed=3 src=gui" end
		if k=="TF3MP_OWN_SPEEDUI" then return g.speedui end
		if k=="TF3MP_OWN_MENU" then return g.menu and "open=1" or "open=0" end
		if k=="TF3MP_OWN_CLOCKUI" then return g.clock_ui end
		if k=="TF3MP_ORDERING" then return g.connected and "1" or "0" end
		if k=="TF3MP_PEER_CLOCK" then return g.peer_clock or (g.connected and "gt=1000" or "") end
		if k=="TF3MP_OWN_CLOCK" then return "phase="..(g.failed and "failed" or "idle") end
	end},log={}, -- TF3's main GUI log has no info(), unlike the old test double.
	debugPrint=function(s)
		if logging=="broken" then error("diagnostic output unavailable") end
		g.logs[#g.logs+1]=s
		local text=s:match("^%[mp_probe%]net state speedui (.+)$");if text then g.speedui=text end
	end,
	print=function(s)
		if logging=="broken" then error("fallback output unavailable") end
		g.logs[#g.logs+1]=s
	end}, {__index=_G})
	if logging=="no-debug-print" then env.debugPrint=false end
	env.ug_require=function(path)
		if path=="::/gui/main/react.lua" then return react end
		if path=="::/gui/main/builtin.lua" then return {BoxLayout=function(p)return p end} end
		if path=="::/gui/main/mod_entry_point.tl" then return {ModEntryPointExtension="game-main"} end
		if path=="mp_probe_1::/mp_probe/vehicle_hooks.lua" then return hooks end
		if path=="mp_probe_1::/mp_probe/economy_hooks.lua" then return economy_hooks end
		if path=="mp_probe_1::/mp_probe/menu_hooks.lua" then return menu_hooks end
		if path=="mp_probe_1::/mp_probe/speed_hooks.lua" then return speed_hooks end
		if path=="mp_probe_1::/mp_probe/wire.lua" then return wire end
		error("unexpected GUI module: "..path)
	end
	local path="mods/mp_probe/content/mp_probe/vehicle_ui.script.lua"
	local module
	if setfenv then local fn=assert(loadfile(path)); setfenv(fn,env); module=fn()
	else module=assert(loadfile(path,"t",env))() end
	assert(type(env.data)=="function" and env.data()==module, "Lua script resource must export data()")
	g.recipe=env.data().VehicleHooks; g.recipe(); g.cmd=cmd; g.game=game
	function g.step() for _, fn in ipairs(g.steps) do fn() end end
	return g
end

test("world entry works without log.info and reports installed hooks",function()
	local g=gui("host",true)
	assert(#g.logs==5 and g.logs[1]=="[mp_probe]vehicle UI: speed capacity retry guard installed")
	assert(g.logs[2]=="[mp_probe]net state menu open=0")
	assert(g.logs[3]=="[mp_probe]vehicle UI: menu pause hook installed")
	assert(g.logs[4]=="[mp_probe]vehicle UI: vehicle hooks: 6 of 6 installed")
	assert(g.logs[5]=="[mp_probe]vehicle UI: economy hooks: 3 of 3 installed")
	assert(#g.steps==1 and #g.sent==0, "entering the world must not send vehicle commands")
end)

test("missing or failing diagnostic output cannot abort entry or lose held commands",function()
	for _, logging in ipairs({"no-debug-print","broken"}) do
		local g=gui("client",true,logging)
		if logging=="no-debug-print" then assert(#g.logs==5, "use print when debugPrint is unavailable") end
		local cb=0
		g.cmd.sendCommand(g.cmd.makeVehicleSetStoppedByUserCmd(7,true),function(_,ok)assert(ok); cb=cb+1 end)
		assert(#g.sent==0 and cb==0)
		g.step()
		assert(#g.sent==1 and g.sent[1].name=="mp_probe_vehicle" and cb==1)
		local batch=assert(wire.decode(g.sent[1].param.batch))
		assert(#batch==1 and batch[1].command=="stopped" and batch[1].value==true)
		g.step(); assert(#g.sent==1)
	end
end)

test("native menu lifecycle is observed once without replacing TF3's pause behavior",function()
	for _, role in ipairs({"host","client","off"}) do
		local g=gui(role,role~="off"); g.recipe()
		local n=#g.logs
		g.game.setInGameMenuPause(true); assert(g.menu==true)
		if role~="off" then assert(g.logs[#g.logs]=="[mp_probe]net state menu open=1") end
		g.game.setInGameMenuPause(false); assert(g.menu==false)
		assert(#g.logs==n+(role=="off" and 0 or 2), "no stacked hooks or single-player traffic")
	end
end)

test("main GUI captures all five window command types before execution and flushes once",function()
	for _, role in ipairs({"host","client"}) do
		local g=gui(role,true); local cb=0
		local list={g.cmd.makeVehicleReverseCmd(7),g.cmd.makeVehicleSetStoppedByUserCmd(7,true),
			g.cmd.makeVehicleSendToDepotCmd(7,true),g.cmd.makeVehicleSetLineCmd(7,9,2),g.cmd.makeVehicleSellCmd({7,8})}
		for _, c in ipairs(list) do g.cmd.sendCommand(c,function(_,ok)assert(ok); cb=cb+1 end) end
		assert(#g.sent==0 and cb==0, "the original vehicle commands must not execute early")
		g.step(); assert(#g.sent==1 and g.sent[1].name=="mp_probe_vehicle" and cb==5)
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

test("native manager callbacks receive command data and reachable-stop sentinel survives",function()
	local g=gui("client",true); local callbacks=0
	local function send(c, expected)
		g.cmd.sendCommand(c,function(result,ok)
			assert(ok)
			for key,value in pairs(expected) do assert(result[key]==value, "missing command result "..key) end
			callbacks=callbacks+1
		end)
	end
	send(g.cmd.makeVehicleSetLineCmd(7,9,-1),{vehicleEntity=7,lineEntity=9,stopIndex=-1})
	send(g.cmd.makeVehicleReverseCmd(7),{vehicleEntity=7})
	send(g.cmd.makeVehicleSetStoppedByUserCmd(7,true),{vehicleEntity=7,userStopped=true})
	send(g.cmd.makeVehicleSendToDepotCmd(7,true),{vehicleEntity=7,sellOnArrival=true})
	local sold={7,8}; send(g.cmd.makeVehicleSellCmd(sold),{vehicleEntities=sold})
	assert(callbacks==0, "callbacks wait until the script event is handed over")
	g.step(); assert(callbacks==5, "native callbacks must complete without missing entity fields")
	local batch=assert(wire.decode(g.sent[1].param.batch))
	assert(batch[1].stop==-1, "-1 asks TF3 for the next reachable stop; never force stop zero")
	for _,line in ipairs(g.logs) do assert(not line:find("callback failed",1,true),line) end
end)

test("single-player passes through and a failed session cannot bypass interception",function()
	local solo=gui("off",false)
	solo.cmd.sendCommand(solo.cmd.makeVehicleReverseCmd(7)); solo.step()
	assert(#solo.sent==1 and solo.sent[1].kind=="reverse")
	local g=gui("host",true); g.recipe()
	g.cmd.sendCommand(g.cmd.makeVehicleReverseCmd(8)); g.step()
	assert(#g.sent==1 and g.sent[1].kind=="event")
	g.failed=true; g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(7,9,0))
	assert(#g.sent==1); g.step()
	assert(#g.sent==2 and g.sent[2].name=="mp_probe_vehicle")
end)

test("a temporarily missing peer clock cannot execute an unshared assignment",function()
	local g=gui("client",true); g.peer_clock=""
	g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(7,9,-1))
	assert(#g.sent==0); g.step()
	assert(#g.sent==1 and g.sent[1].name=="mp_probe_vehicle")
end)

test("native callbacks wait for actual scripting acceptance and remain single-shot",function()
	local g=gui("client",true); g.defer_events=true
	local answers={}
	g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(7,9,-1),function(data,ok)
		assert(data.vehicleEntity==7 and data.lineEntity==9); answers[#answers+1]=ok
	end)
	g.step(); assert(#answers==0 and g.pending_callback)
	g.pending_callback({},true,{})
	g.pending_callback({},false,{})
	assert(#answers==1 and answers[1]==true)
end)

test("failed or rejected GUI handovers report failure on both PCs without local execution",function()
	for _, mode in ipairs({"maker","send","reject"}) do
		local g=gui("client",true); local answers={}
		if mode=="maker" then g.cmd.makeScriptingSendEventCmd=function()error("no script events")end
		elseif mode=="reject" then g.event_success=false
		else
			-- Interception saved the real sender during installation; replace it in
			-- a fresh direct hook environment to model a native submission error.
			local m={}; local env={api={cmd={}}}
			local cmd=env.api.cmd
			for maker in pairs(hooks.VEHICLE_COMMANDS) do cmd[maker]=function()return {}end end
			cmd.sendCommand=function()error("native send unavailable")end
			cmd.makeScriptingSendEventCmd=function()return {}end
			local issues={}
			hooks.watch_vehicles(env,m,{timed=function()return true end,log=function()end,
				encode=wire.encode,issue=function(args,why)issues[#issues+1]={args=args,why=why}end})
			cmd.sendCommand(cmd.makeVehicleSetLineCmd(7,9,-1),function(_,ok)answers[#answers+1]=ok end)
			hooks.flush_vehicles(env,m)
			assert(#answers==1 and answers[1]==false and #issues==1)
		end
		if mode~="send" then
			g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(7,9,-1),function(data,ok)
				assert(data.vehicleEntity==7); answers[#answers+1]=ok
			end)
			g.step(); assert(#answers==1 and answers[1]==false)
			for _,c in ipairs(g.sent) do assert(c.kind=="event", "no local fallback") end
			local local_issue,peer_issue
			for _,l in ipairs(g.logs) do
				local_issue=local_issue or l:match("^%[mp_probe%]action issue local (I1 gui_vehicle_client%.1 none %x+ %x+)$")
				peer_issue=peer_issue or l:match("^%[mp_probe%]net send (I1 .+)$")
			end
			assert(local_issue and local_issue==peer_issue)
		end
	end
end)

test("a manager callback may enqueue another assignment without losing or repeating it",function()
	local g=gui("host",true); local callbacks=0
	g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(7,9,-1),function(_,ok)
		assert(ok); callbacks=callbacks+1
		g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(8,9,-1),function(_,success)assert(success);callbacks=callbacks+1 end)
	end)
	g.step(); assert(#g.sent==1 and callbacks==1)
	g.step(); assert(#g.sent==2 and callbacks==2)
	assert(wire.decode(g.sent[1].param.batch)[1].vehicle==7)
	assert(wire.decode(g.sent[2].param.batch)[1].vehicle==8)
	g.step(); assert(#g.sent==2)
end)

test("selected teleport depot survives capture alongside the native callback data",function()
	local g=gui("host",true); local done=false
	g.cmd.sendCommand(g.cmd.makeVehicleSendToDepotCmd(7,false,123),function(data,ok)
		assert(ok and data.jumpToDepotEntity==123 and data.sellOnArrival==false); done=true
	end)
	g.step(); local batch=assert(wire.decode(g.sent[1].param.batch))
	assert(done and batch[1].jumpDepot==123 and batch[1].value==false)
	assert(hooks.vehicle_args("depot",7,false).jumpDepot==nil)
end)

test("GUI resource registers the actual recipe in the game's main extension point",function()
	local old=data; assert(loadfile("mods/mp_probe/content/mp_probe/vehicle_ui.res.lua"))()
	local value=data(); data=old
	assert(value.type=="react-plugin ::ModEntryPointExtension")
	assert(value.data.filePath=="mp_probe_1::/mp_probe/vehicle_ui.script@VehicleHooks")
end)

test("subsidy decisions and company renames are held from both PCs alongside vehicles",function()
	for _, role in ipairs({"host","client"}) do
		local g=gui(role,true); local calls=0
		for _, decision in ipairs({"onAccept","onDecline"}) do
			local p={uid=123}
			g.cmd.sendCommand(g.cmd.makeScriptingSendEventCmd("", "Subvention",decision,p),function(data,ok)
				assert(ok and data.id=="Subvention" and data.param==p); calls=calls+1
			end)
		end
		g.cmd.sendCommand(g.cmd.makeEntitySetNameCmd(7,"Süd & Küste"),function(data,ok)
			assert(ok and data.entity==7 and data.name=="Süd & Küste"); calls=calls+1
		end)
		assert(calls==3 and #g.sent==3)
		for _, e in ipairs(g.sent) do assert(e.name=="mp_probe_economy" and e.kind=="event") end
		assert(g.sent[1].param.uid==123 and g.sent[2].param.name=="onDecline" and g.sent[3].param.name=="Süd & Küste")
		g.cmd.sendCommand(g.cmd.makeVehicleSetLineCmd(8,9,-1)); g.step()
		assert(#g.sent==4 and g.sent[4].name=="mp_probe_vehicle")
	end
end)

test("other names, native replay events and single-player economy commands pass through",function()
	local g=gui("host",true)
	g.cmd.sendCommand(g.cmd.makeEntitySetNameCmd(88,"Station"))
	g.cmd.sendCommand(g.cmd.makeScriptingSendEventCmd("mp_probe_economy","Subvention","onAccept",{uid=5}))
	g.cmd.sendCommand(g.cmd.makeScriptingSendEventCmd("","Notifications","add",{}))
	assert(#g.sent==3 and g.sent[1].kind=="name" and g.sent[2].name=="onAccept" and g.sent[3].name=="add")
	local solo=gui("off",false)
	solo.cmd.sendCommand(solo.cmd.makeEntitySetNameCmd(7,"Company"))
	solo.cmd.sendCommand(solo.cmd.makeScriptingSendEventCmd("","Subvention","onAccept",{uid=5}))
	assert(#solo.sent==2 and solo.sent[1].kind=="name" and solo.sent[2].name=="onAccept")
end)

test("failed economic handover neither books locally nor disappears from the paired error log",function()
	local g=gui("client",true);local result
	local command=g.cmd.makeEntitySetNameCmd(7,"Süd AG")
	g.cmd.makeScriptingSendEventCmd=function()error("simulation event unavailable")end
	g.cmd.sendCommand(command,function(data,ok)assert(data.entity==7);result=ok end)
	assert(result==false and #g.sent==0,"never execute an unshared financial change")
	local local_issue,peer_issue
	for _,l in ipairs(g.logs) do
		local_issue=local_issue or l:match("^%[mp_probe%]action issue local (I1 gui_economy_client%.1 none %x+ %x+)$")
		peer_issue=peer_issue or l:match("^%[mp_probe%]net send (I1 .+)$")
	end
	assert(local_issue and local_issue==peer_issue)
end)

test("a failed timeline cannot bypass shared planning for financial clicks",function()
	local g=gui("host",true);g.failed=true
	g.cmd.sendCommand(g.cmd.makeScriptingSendEventCmd("","Subvention","onAccept",{uid=123}))
	assert(#g.sent==1 and g.sent[1].name=="mp_probe_economy")
end)

test("capacity has one controller only while the ordered GUI is active", function()
	for _, role in ipairs({"host","client","off"}) do
		local g=gui(role,role~="off")
		assert(g.game.getEstimatedMaximumGameSpeed()==(role=="off" and 3 or 4))
		g.own_gui=""; assert(g.game.getEstimatedMaximumGameSpeed()==3,"startup keeps native behavior")
		g.own_gui="src=gui speed=4"; g.capacity=2
		assert(g.game.getEstimatedMaximumGameSpeed()==(role=="off" and 2 or 4))
		g.connected=false; assert(g.game.getEstimatedMaximumGameSpeed()==2)
	end
end)

test("actual GUI entry publishes valid native speed choices on the bridge-sized state key",function()
	for _,role in ipairs({"host","client"})do
		local g=gui(role,true)
		for _,speed in ipairs({0,1,2,4})do g.cmd.sendCommand(g.cmd.makeGameSetSpeedCmd(speed))end
		assert(g.speedui=="seq=4 speed=4" and #g.sent==4)
		local count=0
		for _,line in ipairs(g.logs)do
			local key=line:match("^%[mp_probe%]net state (speedui) ")
			if key then count=count+1;assert(#key<=8,"native bridge state parser accepts at most eight letters")end
		end
		assert(count==4)
		g.menu=true;g.cmd.sendCommand(g.cmd.makeGameSetSpeedCmd(0));assert(g.speedui=="seq=4 speed=4")
		g.menu=false;g.clock_ui="hold=1 run=4";g.cmd.sendCommand(g.cmd.makeGameSetSpeedCmd(0))
		assert(g.speedui=="seq=4 speed=4","automatic action pause published as a click")
	end
end)
test("synchronous native menu speed commands are ignored before the bridge menu echo arrives",function()
	local g=gui("host",true);g.native_menu_speed=true
	g.game.setInGameMenuPause(true);assert(not g.speedui and #g.sent==1)
	g.game.setInGameMenuPause(false);assert(not g.speedui and #g.sent==2)
	g.cmd.sendCommand(g.cmd.makeGameSetSpeedCmd(2));assert(g.speedui=="seq=1 speed=2")
end)
print(string.format("%d main-GUI vehicle tests passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end

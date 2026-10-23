-- Native vehicle finance contract: acquisition time identifies retained parts;
-- newly purchased parts receive this world's time, never the source world's.
-- The real engine is not started. Prices and command settlement are simulated.
local original = require
function require(path)
	if path:sub(1,1) == "/" then return assert(loadfile("mods/mp_probe/content" .. path))() end
	return original(path)
end
local wire, actions = require("/mp_probe/wire.lua"), require("/mp_probe/actions.lua")
local fixture = assert(loadfile("tests/fixtures/actions_env.lua"))({wire=wire, actions=actions})
local passed, failed = 0, 0
local function test(name, fn)
	local ok, why = pcall(fn)
	if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name..": "..tostring(why)) end
end
local function setup()
	local s, d = fixture.mock(), fixture.mock()
	for _, m in ipairs({s,d}) do
		m.account(); m.construction(10,12,25)
		m.time = m == s and 9000000 or 8200600
		m.env.api.type.ComponentType.GAME_TIME = "GAME_TIME"
		m.env.api.engine.util.getWorld = function() return 1 end
		local read = m.env.api.engine.getComponent
		m.env.api.engine.getComponent = function(id,kind)
			if id == 1 and kind == "GAME_TIME" then return {gameTime=m.time} end
			return read(id,kind)
		end
	end
	local function part(m, stamp)
		local p=m.config().vehicles[1]; p.part.modelId=77; p.purchaseTime=stamp
		p.maintenanceState, p.maintenanceChange=0.35,0.02
		return p
	end
	s.part=function(t)return part(s,t)end; d.part=function(t)return part(d,t)end
	local send=d.env.api.cmd.sendCommand
	d.bookings=0
	-- Prices deliberately distinguish new, retained, and fully depreciated parts.
	d.env.api.cmd.sendCommand=function(command, callback)
		local a, name=command.args,command.name
		if name~="makeVehicleBuyCmd" and name~="makeVehicleReplaceCmd" then return send(command,callback) end
		local previous=name=="makeVehicleReplaceCmd" and d.entities[a[1]].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles or {}
		local config=name=="makeVehicleBuyCmd" and a[3] or a[2]
		local grouped=0;for _,count in ipairs(config.vehicleGroups)do grouped=grouped+count end
		assert(grouped==#config.vehicles,"native consist groups must cover every vehicle part")
		local cost, used=0,{}
		for _, p in ipairs(config.vehicles) do
			local keep
			for j, old in ipairs(previous) do
				if not used[j] and old.part.modelId==p.part.modelId and old.purchaseTime==p.purchaseTime then
					keep,used[j]=true,true; break
				end
			end
			if not keep then cost=cost+(p.purchaseTime==d.time and 1000 or 0) end
		end
		for j in ipairs(previous) do if not used[j] then cost=cost-200 end end
		if d.reject or cost>d.entities[7].ACCOUNT.balance then
			callback({},false); return
		end
		d.bookings=d.bookings+1; d.entities[7].ACCOUNT.balance=d.entities[7].ACCOUNT.balance-cost
		return send(command,function(result,success)
			callback(result,success)
			if d.duplicate_callback then callback(result,success) end
		end)
	end
	return s,d
end
local function existing(s,d, source_times, dest_times)
	for _, pair in ipairs({{s,30,source_times},{d,90,dest_times}}) do
		local m,id,times=pair[1],pair[2],pair[3]
		local v=m.vehicle(id,10010).TRANSPORT_VEHICLE
		v.transportVehicleConfig.vehicles={}
		for _, t in ipairs(times) do v.transportVehicleConfig.vehicles[#v.transportVehicleConfig.vehicles+1]=m.part(t) end
		v.transportVehicleConfig.vehicleGroups={#times}; m.entities[id].NAME.name="Train"
		m.poll()
	end
end
local function transfer(s,d)
	s.poll(); local list=s.drain(); assert(#list==1,"expected one vehicle action")
	d.replay(list[1]); return list[1]
end
test("a client purchase deducts the full native cost in the receiving world",function()
	local s,d=setup(); s.poll(); d.poll()
	local config=s.vehicle(30,10010).TRANSPORT_VEHICLE.transportVehicleConfig
	config.vehicles,config.vehicleGroups={s.part(s.time),s.part(s.time)},{2}
	transfer(s,d)
	assert(d.entities[7].ACCOUNT.balance==998000 and d.bookings==1)
	assert(d.entities[1001].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].purchaseTime==d.time)
	assert(table.concat(d.logs,"\n"):find("delta=-2000",1,true))
	d.poll(); assert(#d.drain()==0,"purchase echoed")
end)
test("same-model train renewal is detected and charged rather than disappearing from snapshots",function()
	local s,d=setup(); existing(s,d,{1000},{2000})
	s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles={s.part(s.time)}
	local a=transfer(s,d)
	assert(a.previous.config_changed and not next(a.previous.kept_parts))
	assert(d.entities[7].ACCOUNT.balance==999200 and d.bookings==1)
	assert(d.entities[90].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].purchaseTime==d.time)
	assert(table.concat(d.logs,"\n"):find("delta=-800",1,true))
	d.poll(); assert(#d.drain()==0,"renewal echoed")
end)
test("retained wagons keep local age and maintenance while only the added wagon is bought",function()
	local s,d=setup(); existing(s,d,{1000,2000},{3000,4000})
	local parts=s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles
	s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles={parts[2],s.part(s.time),parts[1]}
	s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicleGroups={3}
	transfer(s,d)
	local v=d.entities[90].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles
	assert(v[1].purchaseTime==4000 and v[2].purchaseTime==d.time and v[3].purchaseTime==3000)
	assert(v[1].maintenanceState==0.35 and v[3].maintenanceChange==0.02)
	assert(d.entities[7].ACCOUNT.balance==999000 and d.bookings==1)
	d.poll();assert(#d.drain()==0,"retained local timestamps must not echo a replacement")
end)
test("recoloring and reversing retained parts do not purchase the train again",function()
	local s,d=setup(); existing(s,d,{1000},{2000})
	local p=s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1]
	p.part.reversed=false; p.part.color.x=0.9
	transfer(s,d)
	assert(d.entities[7].ACCOUNT.balance==1000000 and d.bookings==1)
	assert(d.entities[90].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].purchaseTime==2000)
end)
test("identical wagon acquisition times are matched once each",function()
	local s,d=setup(); existing(s,d,{1000,1000},{2000,2000})
	table.insert(s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles,s.part(s.time))
	s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicleGroups={3}
	local a=transfer(s,d)
	assert(a.previous.kept_parts[1]~=a.previous.kept_parts[2] and not a.previous.kept_parts[3])
	assert(d.entities[7].ACCOUNT.balance==999000)
end)
test("rejected replacement leaves the account and existing train intact",function()
	local s,d=setup(); existing(s,d,{1000},{2000}); d.entities[7].ACCOUNT.balance=50
	s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles={s.part(s.time)}
	transfer(s,d)
	assert(d.entities[7].ACCOUNT.balance==50 and d.bookings==0)
	assert(d.entities[90].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].purchaseTime==2000)
end)
test("duplicate native callbacks cannot duplicate settings or fabricate another booking",function()
	local s,d=setup(); existing(s,d,{1000},{2000}); d.duplicate_callback=true
	s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles={s.part(s.time)}
	transfer(s,d)
	assert(d.bookings==1 and d.entities[7].ACCOUNT.balance==999200)
	local receipts=0; for _,l in ipairs(d.logs)do if l:find("native account:",1,true)then receipts=receipts+1 end end
	assert(receipts==1)
end)
test("invalid retained part aliases fail before a native replacement or a money mutation",function()
	local s,d=setup(); existing(s,d,{1000,1000},{2000,2000})
	s.entities[30].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].part.color.x=0.8
	s.poll(); local a=s.drain()[1]; a.previous.kept_parts={[1]=1,[2]=1}
	assert(not pcall(d.replay,a) and d.bookings==0 and #d.sent==0)
	assert(d.entities[7].ACCOUNT.balance==1000000)
end)
test("missing acquisition time rejects a purchase before a free or incorrectly aged train can be created",function()
	local s,d=setup();s.poll();d.poll();s.vehicle(30,10010);s.poll()
	local a=s.drain()[1]
	d.env.api.engine.util.getWorld=function()error("temporarily unreadable world")end
	local ok,why=pcall(d.replay,a)
	assert(not ok and tostring(why):find("acquisition time unreadable",1,true))
	assert(d.bookings==0 and #d.sent==0 and d.entities[7].ACCOUNT.balance==1000000)
end)
print(string.format("Vehicle finance: %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end

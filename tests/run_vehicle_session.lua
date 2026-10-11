-- Both actual mod event handlers, copying states and native-style ordered receipts.
-- Engine commands are mocked; no TF3 process or installed file is touched.
local original_require = require
local modules = {}
function require(path)
    if path:sub(1,1) ~= "/" then return original_require(path) end
    if not modules[path] then modules[path] = assert(loadfile("mods/mp_probe/content" .. path))() end
    return modules[path]
end
local wire, actions = require("/mp_probe/wire.lua"), require("/mp_probe/actions.lua")
local timeline, sync = require("/mp_probe/timeline.lua"), require("/mp_probe/sync.lua")
local gui = require("/mp_probe/gui.lua")
local transport = require("/mp_probe/transport.lua")
-- The fixture's state getter must copy, as the native state does. Repeatedly
-- parsing every saved state through the wire codec would benchmark that codec
-- instead of this session, especially with forty pending purchases. Actual
-- production actions/network payloads still use the unmodified wire module.
local function plain_copy(value)
    if type(value)~="table" then return value end
    local out={}
    for key,item in pairs(value) do out[key]=plain_copy(item) end
    return out
end
local fixture = assert(loadfile("tests/fixtures/actions_env.lua"))({wire={copy=plain_copy},actions=actions})
local current, packets, serial, logs, model = nil, {}, 0, {}, {}
function debugPrint(...)
    if not current then return end
    local message = table.concat({...}, "")
    logs[#logs+1] = current.role .. ": " .. message:sub(1,600)
    if #logs>512 then table.remove(logs,1) end
    local key, value = message:match("^%[mp_probe%]net state (%a+) (.*)$")
    if key then
        current.vars["TF3MP_OWN_" .. key:upper()] = value
        current.peer.vars["TF3MP_PEER_" .. key:upper()] = value
    end
    local line = message:match("^%[mp_probe%]net send (.+)$")
    local sequence,index,count,part=message:match("^%[mp_probe%]net upload (%d+) (%d+) (%d+) (.+)$")
    if sequence then
        index,count=tonumber(index),tonumber(count)
        assert(count>=2 and count<=math.ceil(transport.MAX_BYTES/transport.CHUNK) and index<count)
        assert(#part<=transport.CHUNK and (index==count-1 or #part==transport.CHUNK))
        local upload=current.uploads[sequence]
        if not upload then
            assert(index==0, "upload must start at fragment zero")
            upload={count=count,next=0,parts={}}
            current.uploads[sequence]=upload
        end
        assert(upload.count==count and index==upload.next, "upload fragments must remain ordered")
        upload.parts[index+1],upload.next=part,index+1
        if upload.next==count then
            line=table.concat(upload.parts)
            assert(#line<=transport.MAX_BYTES)
            current.uploads[sequence]=nil
            current.fragmented_messages=current.fragmented_messages+1
        end
    end
    if line then
        serial = serial + 1
        packets[#packets+1] = {target=current.peer, line=line, token="peer-"..current.role.."."..serial,
            ready_at=current.clock+(model.latency or 0)}
    end
    local token, result = message:match("^%[mp_probe%]net result ([%w_.%-]+) (%a+)")
    if token and packets[1] and packets[1].token == token then
        assert(result == "OK", message)
        table.remove(packets,1)
    end
end
assert(loadfile("mods/mp_probe/content/mp_probe/main.script.lua"))()
local main = data()

local function game(role, gt)
    local g = fixture.mock()
    g.role, g.gt, g.speed, g.clock, g.events = role, gt, model.speed or 0, 0, {}
    g.engine_pending, g.gui, g.assignments = {}, {speed={}}, 0
    g.uploads, g.fragmented_messages = {}, 0
    g.vars = {TF3MP_ROLE=role,TF3MP_ORDERING="1",TF3MP_WORLD=(role=="host" and "1" or "2").."-123-1"}
    g.vars.TF3MP_WORLD_ACK = g.vars.TF3MP_WORLD
    g.env.os = {getenv=function(key)return g.vars[key] end,clock=function()return g.clock end}
    g.env.api.type.ComponentType.GAME_TIME = "GAME_TIME"
    g.env.api.type.ComponentType.GAME_SPEED = "GAME_SPEED"
    g.env.api.engine.util.getWorld = function() return 1 end
    local component = g.env.api.engine.getComponent
    g.env.api.engine.getComponent = function(id, ct)
        if id==1 and ct=="GAME_TIME" then return {gameTime=g.gt} end
        if id==1 and ct=="GAME_SPEED" then return {speedup=g.speed,millisPerDay=4000} end
        return component(id,ct)
    end
    g.env.api.cmd.makeGameSetSpeedCmd = function(speed) return {name="speed",speed=speed} end
    local send = g.env.api.cmd.sendCommand
    local function execute(command, cb)
        if command.name=="makeScriptingSendEventCmd" then g.events[#g.events+1]=command.args; return end
        if command.name=="speed" then g.speed=command.speed; if cb then cb({},true) end; return end
        if command.name=="makeVehicleSetLineCmd" then
            if model.gui then assert(g.speed==0 and g.peer.speed==0, "both native engines must stay paused until assignment executes") end
            g.assignments=g.assignments+1
        end
        return send(command,cb)
    end
    g.env.api.cmd.sendCommand = function(command, cb)
        if model.engine_delay and command.name~="makeScriptingSendEventCmd" then
            g.engine_pending[#g.engine_pending+1]={command=command,cb=cb,at=g.clock+model.engine_delay}
            return
        end
        return execute(command,cb)
    end
    function g.run(fn)
        local saved_api, saved_os, saved_current = api, os, current
        api, os, current = g.env.api, g.env.os, g
        local ok, err = pcall(fn)
        api, os, current = saved_api, saved_os, saved_current
        assert(ok,err)
    end
    function g.complete_engine()
        while g.engine_pending[1] and g.engine_pending[1].at<=g.clock do
            local pending=table.remove(g.engine_pending,1)
            g.run(function()execute(pending.command,pending.cb)end)
        end
    end
    function g.event(args) g.run(function()main.handleEvent(nil,g.state,table.unpack(args))end) end
    return g
end
local function pair(options)
    packets, serial, logs, model = {}, 0, {}, options or {}
    local h,c = game("host",model.ht or 8200600),game("client",model.ct or 6798600)
    h.peer,c.peer = c,h
    for _, g in ipairs({h,c}) do
        g.construction(10,0,0); g.line(40,"Existing line"); g.vehicle(30,10010)
        g.run(function() main.loaded_state(g.env,g.state) end)
        g.poll()
        g.vars.TF3MP_PEER_CLOCK = "gt="..g.peer.gt.." phase=idle at=0 hold=0"
        g.vars.TF3MP_OWN_GUI="speed="..g.speed.." run="..g.speed.." tg="..g.speed
        if model.gui then
            g.vars.TF3MP_PEER_GUI=g.vars.TF3MP_OWN_GUI
        end
    end
    return h,c
end
local function step(h,c)
    for _, g in ipairs({h,c}) do
        g.clock=g.clock+.25
        if model.advance and g.speed>0 then g.gt=g.gt+math.floor(250*g.speed/200)*200 end
        g.complete_engine()
        if model.gui then g.run(function()gui.step(g.env,g.gui,g.clock)end) end
        while #g.events>0 do g.event(table.remove(g.events,1)) end
        g.run(function()main.paused_network_tick(g.env,g.state)end)
    end
    local p=packets[1]
    if p and not p.offered and p.ready_at<=p.target.clock and not p.target.state:get().network_work then
        p.offered=true
        p.target.event({"mp_probe","mp_probe_replay","mp_probe_replay",
            {line=p.line,number=p.token,source="net",offset=0}})
    end
end
local function finish(h,c)
    local function diagnostic()
        local tail={}
        for i=math.max(1,#logs-39),#logs do tail[#tail+1]=logs[i] end
        return table.concat(tail,"\n")
    end
    for count=1,model.max_rounds or 100 do
        step(h,c)
        local a,b=h.state:get(),c.state:get()
        local hu,cu=sync.decode(h.vars.TF3MP_OWN_CLOCKUI),sync.decode(c.vars.TF3MP_OWN_CLOCKUI)
        if #packets==0 and next(h.uploads)==nil and next(c.uploads)==nil
            and #h.events==0 and #c.events==0 and #h.engine_pending==0 and #c.engine_pending==0
            and not a.timeline.active and not b.timeline.active
            and #a.timeline.queue==0 and not a.network_work and not b.network_work
            and (not hu or hu.hold~=1) and (not cu or cu.hold~=1)
            and sync.decode(h.vars.TF3MP_OWN_CLOCK).hold==0 and sync.decode(c.vars.TF3MP_OWN_CLOCK).hold==0 then
            if a.timeline.error or b.timeline.error then error("timeline failed: "..diagnostic()) end
            return count
        end
    end
    error("session failed to release (last 40 bounded log entries): "..diagnostic())
end
local passed=0
for _, origin in ipairs({"host","client"}) do
    local h,c=pair(); local from=origin=="host" and h or c
    from.run(function()main.vehicle_intent(from.env,from.state,{command="line",vehicle=30,value=40,stop=-1})end)
    local rounds=finish(h,c)
    assert(rounds<=16, "existing assignment waited on simulation time")
    assert(h.entities[30].TRANSPORT_VEHICLE.line==40 and c.entities[30].TRANSPORT_VEHICLE.line==40)
    -- A real engine rejection stays visible but must release the barrier/next command.
    from.peer.reject=true
    from.run(function()main.vehicle_intent(from.env,from.state,{command="line",vehicle=30,value=40,stop=0})end)
    finish(h,c); from.peer.reject=false
    assert(table.concat(logs,"\n"):find("action issue local I1",1,true), "rejection was hidden")
    from.run(function()main.vehicle_intent(from.env,from.state,{command="stopped",vehicle=30,value=true})end)
    finish(h,c)
    assert(h.entities[30].TRANSPORT_VEHICLE.userStopped and c.entities[30].TRANSPORT_VEHICLE.userStopped)
    assert(h.state:get().timeline.last==3 and c.state:get().timeline.last==3)
    print("PASS "..origin..": existing assignment in "..(rounds*.25).." mock seconds; rejected command reported and next command released")
    passed=passed+1
end
for _, origin in ipairs({"host","client"}) do
    local h,c=pair(); local from=origin=="host" and h or c
    -- Buy five buses and create a line, then immediately click the manager's assignment.
    from.line(60,"New line")
    local batch={}
    for id=31,35 do from.vehicle(id,10010); batch[#batch+1]={command="line",vehicle=id,value=60,stop=-1} end
    from.run(function()main.vehicle_intent(from.env,from.state,{batch=wire.encode(batch)})end)
    local rounds=finish(h,c)
    assert(rounds<40, "assignment took more than ten mock seconds")
    for _,g in ipairs({h,c}) do
        local count=0
        for _,e in pairs(g.entities) do
            local v=e.TRANSPORT_VEHICLE
            if v and v.line>=0 then
                assert(g.entities[v.line].NAME.name=="New line" and v.stopIndex==-1)
                count=count+1
            end
        end
        assert(count==5, "every selected bus must be assigned exactly once on both PCs")
        assert(sync.decode(g.vars.TF3MP_OWN_CLOCK).hold==0)
    end
    -- A second command works without resync, with both game times still unchanged.
    from.run(function()main.vehicle_intent(from.env,from.state,{command="stopped",vehicle=31,value=true})end)
    finish(h,c)
    assert(h.state:get().timeline.last==2 and c.state:get().timeline.last==2)
    assert(h.gt==8200600 and c.gt==6798600)
    print("PASS "..origin..": new line + five new buses, assignment in "..(rounds*.25).." mock seconds; next command released")
    passed=passed+1
end

-- These run the real GUI pause/release code too. Delayed command callbacks
-- deliberately keep old speed visible for a while after PAUSE/RESUME was sent.
local function restored(h,c,speed,skew)
    for _,g in ipairs({h,c}) do
        local register=sync.decode(g.vars.TF3MP_OWN_GUI)
        assert(register.speed==speed, "automatic hold must not change the shared user speed")
        -- With a large gap the existing catch-up policy may temporarily run
        -- faster/slower than the chosen speed. It must never force pause.
        assert((speed==0 and g.speed==0) or (speed>0 and g.speed>0), "automatic pause was not released")
        if skew==0 then assert(g.speed==speed, "automatic pause must restore the previous speed") end
    end
end
for _,origin in ipairs({"host","client"}) do
    for _,speed in ipairs({0,1,4}) do
        for _,skew in ipairs({0,1402000}) do
            local h,c=pair({speed=speed,ht=8200600,ct=8200600+skew,gui=true,advance=true,
                latency=.35,engine_delay=.5,max_rounds=160})
            local from=origin=="host" and h or c
            from.run(function()main.vehicle_intent(from.env,from.state,{command="line",vehicle=30,value=40,stop=-1})end)
            local rounds=finish(h,c)
            assert(h.assignments==1 and c.assignments==1, "one native assignment per engine")
            assert(h.entities[30].TRANSPORT_VEHICLE.line==40 and c.entities[30].TRANSPORT_VEHICLE.line==40)
            restored(h,c,speed,skew)
            assert(rounds<60, "a simple assignment cannot wait for simulation catch-up")
            -- A native rejection must release the same pause with delayed
            -- callbacks; the next command still executes on both engines.
            from.peer.reject=true
            from.run(function()main.vehicle_intent(from.env,from.state,{command="line",vehicle=30,value=40,stop=0})end)
            finish(h,c); from.peer.reject=false
            assert(table.concat(logs,"\n"):find("action issue local I1",1,true), "native rejection must remain visible")
            restored(h,c,speed,skew)
            from.run(function()main.vehicle_intent(from.env,from.state,{command="stopped",vehicle=30,value=true})end)
            finish(h,c)
            assert(h.entities[30].TRANSPORT_VEHICLE.userStopped and c.entities[30].TRANSPORT_VEHICLE.userStopped)
            restored(h,c,speed,skew)
            print("PASS "..origin..": delayed engine/network, "..speed.."x, skew "..skew..
                ", assignment "..(rounds*.25).." mock seconds; rejection and resume verified")
            passed=passed+1
        end
    end
end

for _,origin in ipairs({"host","client"}) do
    local h,c=pair({gui=true,latency=.35,engine_delay=.25,max_rounds=400})
    local from=origin=="host" and h or c
    from.line(60,"Forty new buses")
    local batch={}
    for id=101,140 do from.vehicle(id,10010); batch[#batch+1]={command="line",vehicle=id,value=60,stop=-1} end
    from.run(function()main.vehicle_intent(from.env,from.state,{batch=wire.encode(batch)})end)
    local rounds=finish(h,c)
    assert(from.fragmented_messages>0, "forty-vehicle case must exercise stdout upload assembly")
    for _,g in ipairs({h,c}) do
        local count=0
        for _,e in pairs(g.entities) do
            local v=e.TRANSPORT_VEHICLE
            if v and v.line>=0 then
                assert(g.entities[v.line].NAME.name=="Forty new buses" and v.stopIndex==-1)
                count=count+1
            end
        end
        assert(count==40 and g.assignments==40, "forty targets must each execute exactly once")
        assert(g.state:get().timeline.last==1 and g.speed==0)
    end
    from.run(function()main.vehicle_intent(from.env,from.state,{command="stopped",vehicle=101,value=true})end)
    finish(h,c)
    assert(h.state:get().timeline.last==2 and c.state:get().timeline.last==2)
    print("PASS "..origin..": forty newly bought vehicles and new line, "..(rounds*.25)..
        " mock seconds; asynchronous commands, all targets assigned once and next command released")
    passed=passed+1
end

do
    local h,c=pair()
    h.run(function()main.vehicle_intent(h.env,h.state,{command="line",vehicle=30,value=40,stop=-1})end)
    finish(h,c)
    h.run(function()main.vehicle_intent(h.env,h.state,{command="stopped",vehicle=30,value=true})end)
    -- A manual shared reload can save an unfinished action. Neither the old
    -- role/sequence nor this pending request may continue after the load.
    c.state:set(h.state:get())
    for _,g in ipairs({h,c}) do
        g.gt=1000000
        g.vars.TF3MP_WORLD=(g.role=="host" and "1" or "2").."-123-2"
        g.vars.TF3MP_WORLD_ACK=g.vars.TF3MP_WORLD
        g.vars.TF3MP_PEER_CLOCK="gt=1000000 phase=idle at=0 hold=0"
        g.run(function()main.loaded_state(g.env,g.state)end)
        assert(not g.state:get().timeline and not g.state:get().actions)
        g.poll()
    end
    c.run(function()main.vehicle_intent(c.env,c.state,{command="line",vehicle=30,value=40,stop=0})end)
    finish(h,c)
    for _,g in ipairs({h,c}) do
        assert(g.state:get().timeline.last==1 and g.state:get().timeline.role==g.role)
        assert(g.entities[30].TRANSPORT_VEHICLE.stopIndex==0 and not g.entities[30].TRANSPORT_VEHICLE.userStopped)
    end
    print("PASS shared reload: unfinished old request discarded, earlier game time and both roles restart at sequence one")
    passed=passed+1
end
print(passed.." two-mod vehicle session checks passed (engine/network mocked; delays are scripted, not Internet measurements).")

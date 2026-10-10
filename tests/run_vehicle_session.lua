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
local fixture = assert(loadfile("tests/fixtures/actions_env.lua"))({wire=wire,actions=actions})
local current, packets, serial, logs = nil, {}, 0, {}
function debugPrint(...)
    if not current then return end
    local message = table.concat({...}, "")
    logs[#logs+1] = current.role .. ": " .. message
    local key, value = message:match("^%[mp_probe%]net state (%a+) (.*)$")
    if key then
        current.vars["TF3MP_OWN_" .. key:upper()] = value
        current.peer.vars["TF3MP_PEER_" .. key:upper()] = value
    end
    local line = message:match("^%[mp_probe%]net send (.+)$")
    if line then
        serial = serial + 1
        packets[#packets+1] = {target=current.peer, line=line, token="peer-"..current.role.."."..serial}
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
    g.role, g.gt, g.speed, g.clock, g.events = role, gt, 0, 0, {}
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
    g.env.api.cmd.sendCommand = function(command, cb)
        if command.name=="makeScriptingSendEventCmd" then g.events[#g.events+1]=command.args; return end
        if command.name=="speed" then g.speed=command.speed; if cb then cb({},true) end; return end
        return send(command,cb)
    end
    function g.run(fn)
        local saved_api, saved_os, saved_current = api, os, current
        api, os, current = g.env.api, g.env.os, g
        local ok, err = pcall(fn)
        api, os, current = saved_api, saved_os, saved_current
        assert(ok,err)
    end
    function g.event(args) g.run(function()main.handleEvent(nil,g.state,table.unpack(args))end) end
    return g
end
local function pair()
    packets, serial, logs = {}, 0, {}
    local h,c = game("host",8200600),game("client",6798600)
    h.peer,c.peer = c,h
    for _, g in ipairs({h,c}) do
        g.construction(10,0,0); g.line(40,"Existing line"); g.vehicle(30,10010)
        g.run(function() main.loaded_state(g.env,g.state) end)
        g.poll()
        g.vars.TF3MP_PEER_CLOCK = "gt="..g.peer.gt.." phase=idle at=0 hold=0"
        g.vars.TF3MP_OWN_GUI="speed=0 run=0 tg=0"
    end
    return h,c
end
local function step(h,c)
    for _, g in ipairs({h,c}) do
        g.clock=g.clock+.25
        while #g.events>0 do g.event(table.remove(g.events,1)) end
        g.run(function()main.paused_network_tick(g.env,g.state)end)
    end
    local p=packets[1]
    if p and not p.offered and not p.target.state:get().network_work then
        p.offered=true
        p.target.event({"mp_probe","mp_probe_replay","mp_probe_replay",
            {line=p.line,number=p.token,source="net",offset=0}})
    end
end
local function finish(h,c)
    for count=1,100 do
        step(h,c)
        local a,b=h.state:get(),c.state:get()
        if #packets==0 and #h.events==0 and #c.events==0 and not a.timeline.active and not b.timeline.active
            and #a.timeline.queue==0 and not a.network_work and not b.network_work
            and sync.decode(h.vars.TF3MP_OWN_CLOCK).hold==0 and sync.decode(c.vars.TF3MP_OWN_CLOCK).hold==0 then
            assert(not a.timeline.error and not b.timeline.error, table.concat(logs,"\n"))
            return count
        end
    end
    error("session failed to release: "..table.concat(logs,"\n"))
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
print(passed.." two-mod vehicle session checks passed (engine/network mocked).")

-- Execute the actual injected Lua with the main menu/app API mocked.
local source = assert(io.open('tools/game-autoload.lua', 'rb')):read('*a')
local hex = ('Meine Welt.2 ä'):gsub('.', function(c) return ('%02x'):format(c:byte()) end)
local function scenario(value, included, metadata_error)
    local steps, loads, pages, warnings = {}, {}, {}, {}
    local env = { string=string, tonumber=tonumber, table=table, pairs=pairs, pcall=pcall, tostring=tostring,
        os={getenv=function() return value end},
        log={warning=function(s) warnings[#warnings+1]=s end} }
    env.react = { useRef=function(initial) return { value=initial, get=function(s) return s.value end, set=function(s,v) s.value=v end } end,
        onStep=function(fn) steps[#steps+1]=fn end }
    local completed=false
    local info={mods=included and {{name='mp_probe_1'}} or {{name='other_mod'}}, mission=''}
    env.api={type={SavegameId={new=function() return {} end},mod={ModId={new=function() return {} end}},
        SaveGameData={SaveGameDetails={new=function(v) return {mods={table.unpack(v.mods)},mission=v.mission} end}}}}
    env.app={SaveGameNamespace={getSavegame=function() return 'local' end},
        findAllSavegames=function() return {{saveName='Meine Welt.2 ä',path='correct-path'}} end,
        getSavegameInfo=function(id) return {isCompleted=function() return completed end,get=function() return {info=info,errorMsg=metadata_error or ''} end} end,
        setWaitForStartReadyGame=function() end,
        loadGame=function(id,editor,details) loads[#loads+1]={id=id,details=details} end}
    env.setPage=function(page,params) pages[#pages+1]=page; params.onMount() end
    local attach = assert(load(source,'autoload','t',env))()
    attach(env.react,env.app,env.api,env.log,env.setPage)
    local function tick() for _,fn in ipairs(steps) do fn() end end
    tick(); tick(); assert(#loads==0,'loads before metadata is ready')
    completed=true; tick(); tick()
    return loads,pages,warnings,info
end
local loads,pages,warnings,info=scenario(hex,false)
assert(#loads==1 and #pages==1 and pages[1]=='ProgressPage')
assert(loads[1].id.saveGameName=='Meine Welt.2 ä' and loads[1].id.path=='correct-path')
assert(#loads[1].details.mods==2 and loads[1].details.mods[2].name=='mp_probe_1')
assert(#info.mods==1,'mutates original save metadata')
loads=scenario(hex,true); assert(#loads==1 and #loads[1].details.mods==1,'adds duplicate multiplayer mod')
loads,pages,warnings=scenario(hex,false,'broken'); assert(#loads==0 and #warnings==1)
for _,invalid in ipairs({'','abc','zz',string.rep('a',1442)}) do loads=scenario(invalid,false);assert(#loads==0) end
print('10 automatic-load checks passed; native game API mocked.')

-- Uses the bundled original subsidy event contract, with separate native state on each PC.
local base_require = require
function require(name)
	if name:sub(1, 1) == "/" then return assert(loadfile("mods/mp_probe/content" .. name))() end
	return base_require(name)
end
local wire, actions = require("/mp_probe/wire.lua"), require("/mp_probe/actions.lua")
local economy, transport = require("/mp_probe/economy.lua"), require("/mp_probe/transport.lua")
require("/mp_probe/main.script.lua")
local main = data()
local fixture = assert(loadfile("tests/fixtures/actions_env.lua"))({wire=wire,actions=actions})
local copy, passed, failed = fixture.copy, 0, 0
local logs = {}; function debugPrint(...) logs[#logs+1] = table.concat({...}, "") end
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
local function offer(uid, amount)
	return {id="::/game_mechanics/subventions/deliver_cargo/deliver_cargo.res",uid=uid or 123,spawnTime=200,
		data={name="Waren nach Süd",toDeliver=100,delivered=0,expireDuration=100000,expireDurationProposed=10000,
			stockListEntity={entity=201,revision={num={1,16,0}}},cargosToDeliver={5},
			upfront={{type="Money",params={amount=amount or 500000}}},complete={{type="Money",params={amount=2000000}}}}}
end
local function mock(role, offers)
	local m = fixture.mock(); m.account(); m.entities[7].NAME={name="Transport AG"}
	local ct=m.env.api.type.ComponentType; ct.GAME_SCRIPT="GAME_SCRIPT"
	m.entities[9]={GAME_SCRIPT={state={proposedSubventions=offers or {offer()},activeSubventions={},completedSubventions={},failedSubventions={}}}}
	m.env.api.engine.system.gameScriptSystem={getEntityForGameScript=function(path)assert(path==economy.SCRIPT);return 9 end}
	m.env.os={getenv=function(k) if k=="TF3MP_ROLE" then return role or "host" elseif k=="TF3MP_ORDERING" then return m.unordered and "0" or "1" end end}
	local native=m.env.api.cmd.sendCommand
	m.env.api.cmd.sendCommand=function(c,cb)
		if c.name~="makeScriptingSendEventCmd" or c.args[2]~="Subvention" then return native(c,cb) end
		assert(c.args[1]==economy.SOURCE and (c.args[3]=="onAccept" or c.args[3]=="onDecline" or c.args[3]=="subventionSpawn"))
		m.sent[#m.sent+1]=c
		if m.reject then cb({},false);return end
		if not m.ignore then
			local st=m.entities[9].GAME_SCRIPT.state
			if c.args[3]=="subventionSpawn" then
				local created=copy(m.spawnOffer or offer()); created.id=c.args[4].name
				created.uid,created.spawnTime=c.args[4].specific.uid,1001
				st.proposedSubventions[#st.proposedSubventions+1]=created; cb({},true); return
			end
			for i,v in ipairs(st.proposedSubventions) do
				if v.uid==c.args[4].uid then
					table.remove(st.proposedSubventions,i)
					if c.args[3]=="onAccept" then
						v.acceptedTime=1000;st.activeSubventions[#st.activeSubventions+1]=v
						m.entities[7].ACCOUNT.balance=m.entities[7].ACCOUNT.balance+economy.payout(v)
					end
					break
				end
			end
		end
		cb({},true)
	end
	function m.prepare(name,uid) return economy.prepare(m.env,{kind="subvention",name=name or "onAccept",uid=uid or 123}) end
	return m
end

local function targets(m)
	local ct=m.env.api.type.ComponentType
	ct.INDUSTRY,ct.TOWN,ct.BOUNDING_VOLUME="INDUSTRY","TOWN","BOUNDING_VOLUME"
	m.entities[200]={INDUSTRY={stockList=201},BOUNDING_VOLUME={bbox={min={x=10,y=20,z=0},max={x=20,y=30,z=10}}}}
	m.entities[201]={STOCK_LIST={}}
	m.env.api.engine.forEachEntityWithComponent=function(fn,kind)
		for id,e in pairs(m.entities) do if e[kind] then fn(id) end end
	end
	return m
end

test("accepting from either PC pays the original reward once on both PCs",function()
	for _, role in ipairs({"host","client"}) do
		local a,b=mock(role),mock(role=="host" and "client" or "host")
		local action=assert(actions.decode(actions.encode(a.prepare())))
		for _,m in ipairs({a,b}) do
			m.replay(action);assert(m.entities[7].ACCOUNT.balance==1500000)
			assert(#m.entities[9].GAME_SCRIPT.state.activeSubventions==1)
			m.replay(action);assert(m.entities[7].ACCOUNT.balance==1500000 and #m.sent==1)
			m.poll();assert(#m.drain()==0)
		end
	end
end)

test("declining travels once and books no reward, including duplicate decisions",function()
	local a,b=mock(),mock("client");local action=a.prepare("onDecline")
	for _,m in ipairs({a,b}) do
		m.replay(action);m.replay(action)
		assert(#m.sent==1 and #m.entities[9].GAME_SCRIPT.state.proposedSubventions==0 and m.entities[7].ACCOUNT.balance==1000000)
	end
end)

test("different local uid is resolved by the full offer, never by list position",function()
	local a,b=mock(),mock("client",{offer(999,42),offer(777)})
	b.replay(a.prepare());assert(b.sent[1].args[4].uid==777 and b.entities[7].ACCOUNT.balance==1500000)
	assert(b.entities[9].GAME_SCRIPT.state.proposedSubventions[1].uid==999)
end)

test("without a validated target different terms, missing offers and ambiguous matches cannot book money",function()
	local a=mock();local action=a.prepare()
	for _,offers in ipairs({{offer(123,42)},{},{offer(777),offer(888)}}) do
		local b=mock("client",offers);assert(not pcall(b.replay,action));assert(#b.sent==0 and b.entities[7].ACCOUNT.balance==1000000)
	end
end)

test("random reward and deadline differences still accept the same real target",function()
	local a,b=targets(mock()),targets(mock("client",{offer(777,120000)}))
	local action=a.prepare(); assert(action.value.specific)
	b.replay(action)
	assert(#b.entities[9].GAME_SCRIPT.state.activeSubventions==1 and b.entities[7].ACCOUNT.balance==1120000)
	assert(b.state:get().actions.subvention_money.key:find("deliver_cargo_123_200",1,true))
end)

test("a missing offer is spawned through TF3 then accepted once, without booking a second reward",function()
	local a,b=targets(mock()),targets(mock("client",{}))
	b.spawnOffer=offer(0,250000)
	local action=a.prepare(); b.replay(action); b.replay(action)
	assert(#b.entities[9].GAME_SCRIPT.state.activeSubventions==1 and b.entities[7].ACCOUNT.balance==1250000)
	assert(b.sent[1].args[3]=="subventionSpawn" and b.sent[2].args[3]=="onAccept" and #b.sent==2)
end)

test("missing subsidy target, ambiguous target and refused spawn stay explicit failures",function()
	local a=targets(mock()); local action=a.prepare()
	local b=targets(mock("client",{})); b.entities[200]=nil
	assert(not pcall(b.replay,action) and #b.sent==0)
	local c=targets(mock("client",{offer(777),offer(888)}))
	assert(not pcall(c.replay,action) and #c.sent==0)
	local d=targets(mock("client",{})); d.ignore=true
	assert(not pcall(d.replay,action) and d.entities[7].ACCOUNT.balance==1000000)
end)

test("a used or colliding native uid is replaced rather than paying a different offer",function()
	local a=targets(mock()); local b=targets(mock("client",{}))
	b.entities[9].GAME_SCRIPT.state.usedUids={[offer().id]={["123"]=false}}
	b.replay(a.prepare()); assert(b.sent[1].args[4].specific.uid==124)
	assert(b.entities[7].ACCOUNT.balance==1500000)
end)

test("all four native subsidy types recreate the target using local entity ids",function()
	for _,kind in ipairs({"deliver_workers","deliver_cargo","deliver_cargo_town","deliver_passengers"}) do
		local o=offer(); o.id="::/game_mechanics/subventions/"..kind.."/"..kind..".res"
		o.data.to,o.data.from,o.data.townEntity,o.data.cargoType={entity=200},{entity=400},{entity=400},"::/goods.cargo"
		if kind=="deliver_passengers" then o.data.to={entity=500} end
		local a,b=targets(mock("host",{o})),targets(mock("client",{}))
		local function town(x) return {TOWN={},BOUNDING_VOLUME={bbox={min={x=x,y=0,z=0},max={x=x+10,y=10,z=10}}}} end
		a.entities[400],a.entities[500]=town(1000),town(2000)
		b.entities[1400],b.entities[1500]=town(1000),town(2000)
		b.entities[300],b.entities[200]=b.entities[200],nil
		b.entities[300].INDUSTRY.stockList=301
		b.env.api.res.cargoTypeRep={find=function(name) assert(name=="::/goods.cargo"); return 5 end}
		b.spawnOffer=copy(o); b.spawnOffer.data.stockListEntity={entity=301}
		b.spawnOffer.data.to,b.spawnOffer.data.from,b.spawnOffer.data.townEntity={entity=300},{entity=1400},{entity=1400}
		if kind=="deliver_passengers" then b.spawnOffer.data.to={entity=1500} end
		local action=a.prepare(); assert(action.value.specific)
		b.replay(action)
		local params=b.sent[1].args[4].specific
		assert(params.target==(kind=="deliver_passengers" and 1500 or kind=="deliver_cargo_town" and 1400 or 300))
		if kind=="deliver_passengers" then assert(params.source==1400) end
		if kind=="deliver_cargo_town" then assert(params.cargoTypeId==5) end
		assert(#b.entities[9].GAME_SCRIPT.state.activeSubventions==1 and b.entities[7].ACCOUNT.balance==1500000)
	end
end)

test("host balance wins after either player accepts, including duplicate money events",function()
	for _,role in ipairs({"host","client"}) do
		local a,b=targets(mock("host")),targets(mock("client",{offer(777,120000)}))
		local action=(role=="host" and a or b).prepare("onAccept",role=="host" and 123 or 777)
		a.replay(action); b.replay(action)
		b.env.os.getenv=function(k)
			if k=="TF3MP_ROLE" then return "client" elseif k=="TF3MP_PEER_ECONOMY" then
				local r=a.state:get().actions.subvention_money
				return "key="..r.key.." money="..a.entities[7].ACCOUNT.balance
			end
		end
		b.env.api.cmd.sendCommand=function(c,cb)
			assert(c.name=="makeJournalBookAssetCmd" and c.args[2].category.type==9)
			b.entities[7].ACCOUNT.balance=b.entities[7].ACCOUNT.balance+c.args[2].amount; if cb then cb({},true) end
		end
		b.env.api.cmd.makeJournalBookAssetCmd=function(player,entry,pos) return {name="makeJournalBookAssetCmd",args={player,entry,pos}} end
		for i=1,4 do main.economy_tick(a.env,a.state) end
		local r=b.state:get().actions.subvention_money
		local send, param=main.send_replay_event,nil
		main.send_replay_event=function(_,value) param=value; return true end
		for i=1,4 do main.economy_tick(b.env,b.state) end
		main.send_replay_event=send
		assert(param and param.economy_money and param.key==r.key)
		local s=b.state:get(); s.sync={own_k=10,compared_k=5,pending_fix={money=123,date=1},fixes={money={amount=123}}}; b.state:set(s)
		main.economy_apply(b.env,b.state,param); main.economy_apply(b.env,b.state,param)
		assert(b.entities[7].ACCOUNT.balance==a.entities[7].ACCOUNT.balance)
		assert(not b.state:get().sync.pending_fix.money and not b.state:get().sync.fixes.money and b.state:get().sync.compared_k==10)
		main.economy_apply(a.env,a.state,{key=r.key,money=1})
		assert(a.entities[7].ACCOUNT.balance==1500000)
	end
end)

test("a stale subsidy balance cannot pay for a different decision",function()
	local b=targets(mock("client")); b.replay(b.prepare())
	local old=b.entities[7].ACCOUNT.balance
	main.economy_apply(b.env,b.state,{key="older_decision",money=90000000})
	assert(b.entities[7].ACCOUNT.balance==old and not b.state:get().actions.subvention_money.applied)
end)

test("balance alignment waits for active common actions and discards queued older deltas",function()
	local b=targets(mock("client")); b.replay(b.prepare())
	local s=b.state:get(); local key=s.actions.subvention_money.key
	s.actions.subvention_money.requested=true; s.action_busy=true; b.state:set(s)
	main.economy_apply(b.env,b.state,{key=key,money=2000000})
	assert(b.entities[7].ACCOUNT.balance==1500000 and not b.state:get().actions.subvention_money.requested)
	s=b.state:get(); s.action_busy=false; s.sync={}; b.state:set(s)
	b.env.api.engine.util.getWorld=function() return 10 end; b.env.api.type.ComponentType.GAME_TIME="GAME_TIME"
	b.entities[10]={GAME_TIME={gameTime=10000}}
	b.env.api.cmd.makeJournalBookAssetCmd=function(player,entry,pos) return {name="makeJournalBookAssetCmd",args={player,entry,pos}} end
	b.env.api.cmd.sendCommand=function(c,cb) b.entities[7].ACCOUNT.balance=b.entities[7].ACCOUNT.balance+c.args[2].amount; if cb then cb({},true) end end
	main.economy_apply(b.env,b.state,{key=key,money=2000000})
	main.sync_apply(b.env,b.state,{fix_money=9000000,fix_gt=9000})
	assert(b.entities[7].ACCOUNT.balance==2000000)
end)

test("native uid collisions cannot select a different offer",function()
	local a=mock();local b=mock("client",{offer(123,42),offer()})
	assert(not pcall(b.replay,a.prepare()));assert(#b.sent==0)
end)

test("progress changes do not change offer identity, older completed occurrences do",function()
	local a,b=mock(),mock();local action=a.prepare();b.entities[9].GAME_SCRIPT.state.proposedSubventions[1].data.delivered=5
	b.replay(action);assert(b.entities[7].ACCOUNT.balance==1500000)
	local c=mock("client",{});local old=offer();old.spawnTime=1
	c.entities[9].GAME_SCRIPT.state.completedSubventions={old}
	assert(not pcall(c.replay,action) and #c.sent==0)
end)

test("an older repeated acceptance cannot consume a new identical offer after receipts were reset",function()
	local m=mock();local action=m.prepare();m.replay(action)
	m.state:set({});local next_offer=offer(777);next_offer.spawnTime=400
	m.entities[9].GAME_SCRIPT.state.proposedSubventions={next_offer}
	m.replay(action)
	assert(#m.sent==1 and m.entities[7].ACCOUNT.balance==1500000)
	assert(#m.entities[9].GAME_SCRIPT.state.proposedSubventions==1)
end)

test("missing original script is rejected before an invalid native component lookup",function()
	local m=mock()
	m.env.api.engine.system.gameScriptSystem.getEntityForGameScript=function()return -1 end
	m.env.api.engine.getComponent=function()error("invalid native lookup attempted")end
	local ok,err=pcall(m.prepare);assert(not ok and tostring(err):find("subvention script missing",1,true))
end)

test("native Revision userdata preserves its fields even when its length is zero",function()
	local m=mock();local revision=assert(io.tmpfile());local meta=debug.getmetatable(revision)
	debug.setmetatable(revision,{__index={num={1,16,0}},__len=function()return 0 end})
	m.entities[9].GAME_SCRIPT.state.proposedSubventions[1].data.stockListEntity.revision=revision
	local read=m.env.api.engine.getComponent
	m.env.api.engine.getComponent=function(id,ct)if id==9 then return m.entities[9][ct] end;return read(id,ct)end
	local ok,action=pcall(m.prepare)
	debug.setmetatable(revision,meta);revision:close()
	assert(ok,action);assert(action.value.offer.data.stockListEntity.revision.num[2]==16)
	assert(actions.decode(actions.encode(action)))
end)

test("an ignored native decision fails verification, success callback alone is insufficient",function()
	local m=mock();m.ignore=true;local action=m.prepare()
	local ok,err=pcall(m.replay,action);assert(not ok and tostring(err):find("not applied",1,true))
	assert(not m.state:get().actions and m.entities[7].ACCOUNT.balance==1000000)
end)

test("opposite decisions on an already accepted offer are reported, never repay it",function()
	local m=mock();local accept,decline=m.prepare(),m.prepare("onDecline")
	m.replay(accept);assert(not pcall(m.replay,decline));assert(#m.sent==1 and m.entities[7].ACCOUNT.balance==1500000)
end)

test("company rename captures a native UI change, replays to local player and never echoes",function()
	local a,b=mock(),mock("client");a.poll();b.poll();a.entities[7].NAME.name="Süd & Küste 🚂"
	a.poll();local q=a.drain();assert(#q==1 and q[1].op=="company_update")
	b.replay(q[1]);assert(b.sent[1].args[1]==7 and b.entities[7].NAME.name=="Süd & Küste 🚂")
	b.poll();assert(#b.drain()==0);b.replay(q[1]);assert(#b.sent==1)
end)

test("company rename baseline and temporary missing name never synthesize actions",function()
	local m=mock();m.poll();assert(#m.drain()==0)
	m.entities[7].NAME=nil;m.poll();assert(#m.drain()==0)
	assert(not pcall(economy.company_name,"bad\nnet result forged OK"))
	assert(not pcall(economy.company_name,string.rep("x",1025)))
end)

test("both roles hand economic commands to the common timeline before execution",function()
	for _,role in ipairs({"host","client"}) do
		local m=mock(role)
		assert(main.economy_intent(m.env,m.state,{kind="subvention",name="onAccept",uid=123}))
		assert(#m.sent==0 and m.entities[7].ACCOUNT.balance==1000000)
		local t=m.state:get().timeline;assert(role=="host" and #t.queue==1 or role=="client" and t.pending_requests==1)
	end
end)

test("a subsidy clicked on either PC passes the two-clock barrier before native payout",function()
	local timeline=require("/mp_probe/timeline.lua")
	for _,origin in ipairs({"host","client"}) do
		local host,client=mock("host"),mock("client")
		local sender=origin=="host" and host or client
		main.economy_intent(sender.env,sender.state,{kind="subvention",name="onAccept",uid=123})
		local h=host.state:get().timeline or timeline.new("host")
		local c=client.state:get().timeline or timeline.new("client")
		local function pump()
			for _=1,100 do
				local a,b=timeline.take(h),timeline.take(c)
				if not a and not b then return end
				if a then assert(timeline.receive(c,a,0)) end
				if b then assert(timeline.receive(h,b,0)) end
			end
			error("message loop")
		end
		pump();assert(not timeline.step(h,0,0));pump();local at=h.active.at
		assert(#host.sent==0 and #client.sent==0)
		assert(not timeline.step(h,at,0));pump()
		assert(not timeline.step(c,at,at));pump()
		local hi=assert(timeline.step(h,at,at));pump();local ci=assert(timeline.step(c,at,at));pump()
		assert(hi.at==ci.at and hi.origin==origin and ci.origin==origin)
		for i,m in ipairs({host,client}) do
			local intent=i==1 and hi or ci
			transport.begin(m.state,"scheduled_"..origin.."."..intent.seq)
			assert(main.replay_line(m.env,intent.line,"scheduled_"..origin.."."..intent.seq,m.state,0))
			local wrapped=transport.env(m.env,m.state)
			actions.tick(wrapped,m.state,transport.action_log(m.state,function()end));transport.dispatched(m.state)
			transport.check(m.state,function()end,true)
			assert(m.state:get().network_work,"native state verification must gate the receipt")
			actions.tick(wrapped,m.state,transport.action_log(m.state,function()end));transport.check(m.state,function()end,true)
			assert(m.state:get().network_done.result=="OK" and not m.state:get().network_done.skipped)
			assert(m.entities[7].ACCOUNT.balance==1500000)
		end
	end
end)

test("missing offer preparation queues a labelled error; failed scheduling reports without touching other work",function()
	local m=mock();assert(main.economy_intent(m.env,m.state,{kind="subvention",name="onDecline",uid=999}))
	local a=assert(actions.decode(m.state:get().timeline.queue[1].line));assert(a.op=="economy_error")
	logs={};m.unordered=true;transport.begin(m.state,"unrelated.1")
	assert(not main.economy_intent(m.env,m.state,{kind="company",name="New AG"}))
	assert(m.state:get().network_work.token=="unrelated.1" and #m.sent==0)
	local found=false;for _,l in ipairs(logs) do if l:find("action issue local I1 economy_host.1 none",1,true) then found=true end end
	assert(found)
end)

test("subsidy and company failures use paired structured diagnostics including payout and name",function()
	for _,kind in ipairs({"subvention","company"}) do
		local m=mock();m.reject=true
		local action=kind=="subvention" and m.prepare() or economy.prepare(m.env,{kind="company",name="Neue Bahn"})
		transport.begin(m.state,"scheduled_client.1")
		assert(main.replay_line(m.env,actions.encode(action),"scheduled_client.1",m.state,0))
		actions.tick(transport.env(m.env,m.state),m.state,transport.action_log(m.state,function()end))
		transport.dispatched(m.state);local lines={};transport.check(m.state,function(l)lines[#lines+1]=l end,true)
		local issue=assert(lines[3]);local labelhex=assert(issue:match("none (%x+) %x+$") or issue:match("partial (%x+) %x+$"))
		local label=labelhex:gsub("..",function(h)return string.char(tonumber(h,16))end)
		assert(label:find(kind=="subvention" and "Auszahlung 500000" or "Neue Bahn",1,true))
		assert(m.state:get().network_done.skipped and not m.state:get().network_work)
	end
end)

print(string.format("%d economy tests passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end

# TPF2 multiplayer lockstep mod: code-level reference for a TF3 port

Source: `tpf2mp/` (MIT). The paths below are relative to `tpf2mp/mod/mp_lockstep_1/res/` unless they start with `docs/` or `native/`.
Line numbers refer to the checked-out revision. Excerpts are verbatim, trimmed with `...` where marked.

Main files:
- `config/game_script/lockstep.lua` (2112 lines): constants, the `update()` loop, the dispatcher, save and load.
- `scripts/mp/inject.lua` (1729): parses the native capture.
- `scripts/mp/net.lua` (1518): wire format, stamping, reliability, gap hold.
- `scripts/mp/roads.lua` (1760) and `geom.lua` (456): roads and tracks.
- `scripts/mp/cons.lua` (1905) and `conx.lua` (1516): constructions, edge demolish.
- `scripts/mp/stops.lua` (903): edge objects.
- `scripts/mp/vehicles.lua` (1314) and `lines.lua` (1040).
- `scripts/mp/hash.lua` (896), `pacing.lua` (1866), `io.lua` (134).
- Docs: `docs/ARCHITECTURE.md`, `docs/REPLICATION.md`, `docs/RESYNC.md`, `docs/re/PROPOSALS.md`, `docs/re/SCRIPT_API.md`, `native/src/slice/README.md`.

---

## 0. Architecture in one paragraph

This is pure command lockstep: world state never travels.

1. A player action is caught in native code before it executes, as a `make_cmd::*` factory call.
2. It is turned into a text line and cancelled.
3. The Lua game script converts it into an id-free `LSCMD` line and stamps it with a future game time.
4. The line is shipped over UDP by a native bridge plus a Python lobby.
5. Every instance, the originator included, applies it through the script API when its own sim clock reaches the stamp ("strict" mode).

Desync is detected with an id-free world hash and repaired by a coordinated save → transfer → reload of every world (`docs/ARCHITECTURE.md`, `docs/RESYNC.md`).

**Three replication modes** (`docs/REPLICATION.md`):
- **strict:** the native action is cancelled and everyone, the originator included, applies it at the stamp.
- **replay on peers:** the originator's native action stands and only the peers apply it later.
- **poll:** state is scanned and diffed, then shipped.

`K.STRICT_OPS` (`lockstep.lua:534`) lists which ops the originator itself must replay.

---

## 1. Capture and serialization

### 1.1 Native capture (not Lua)

`native/src/slice/README.md` describes `tpf2_slice.dll`, which hooks the engine's command factories:
- `make_cmd::BuildProposal`, at 0x9dc750 per `docs/re/PROPOSALS.md`.
- Buy, sell, line and other commands.
- `CommandList::Add`.

**The decode step.** The slice reads the in-memory proposal (struct offsets in `docs/re/PROPOSALS.md:1-60`, tool shapes table at 46–59). It classifies the proposal by shape and appends one text line per action to `lockstep_inject_<L>.txt`, where L is the instance letter.

| Prefix | Action |
|---|---|
| `ROADE` | road or track build/upgrade |
| `EDEMO` | edge demolish |
| `CDEMO` | construction demolish |
| `CONXP` | construction placement |
| `ROADC` | street payload of a construction |
| `CONUP` | construction upgrade |
| `STOPX` / `STOPXDEL` | edge object add / delete |
| `VBUY`, `VREPL`, `VSELL`, `VLINE`, ... | vehicles |
| `LCREATEX`, `LUPDATE`, `LDELETE` | lines |

**Cancel (`add_hook.inl`).** The slice fires the tool's completion callback, zeroes `Add`'s output handle and skips the call. It cancels only when `lockstep_status_<L>.txt` is under 15 s old and reports a peer. Before each capture it writes `ARMED 1` or `ARMED 0`, saying whether the native command was cancelled. If the decode fails, the native command runs and the slice writes `NATIVE`.

**The `ARMED` flag in Lua** (`inject.lua:106-206`):
- `ARMED 0`: the originator already has the result, so the shipped command carries `skipOrigin=1` and only the peers apply it.
- In solo play nothing is armed and lines are dropped.

**Native determinism patches** (`native/src/slice/README.md`):
- `station_weld.inl` (MergeTemplateStreet welds the template connector).
- `trainorder` (reservation order ranked by name).
- `moveorder` (ship and aircraft claim order).
- `roadspace` (road entry order).
- `hotjoin_order`.
- `constructions.inl` (reads construction params off the proposal).

### 1.2 Lua side: inject → command

`lockstep.lua:936-1418`, `update()`, runs every game-script tick in this order:
1. `pollEvents` (received lines).
2. `pollInject`.
3. Poll scans.
4. Heartbeat (1097–1110).
5. `paceTick`.
6. `retryQueue`.
7. Queue apply (1133–1267).

Each inject handler resolves the native ids into positions or keys, then calls `CM.scheduleLocal(op, args)`.

**Example: the ROADE format** (`inject.lua:268-279`):
```lua
-- ROADE <N> <etype> <stype> <ttype> <cat> <M> <rn> <re>
--       <id x y z>*N <a1 a2 t0x t0y t0z t1x t1y t1z>*M
--       <rmnodeid>*rn <a1 a2 t0x t0y t0z t1x t1y t1z>*re
--       [<btype bidx>*M]
-- Carries real edge topology, so a road CONNECTING to existing
-- infrastructure replicates. Negative endpoints are the proposal's
-- own placeholders; positive ones are real entities in the world.
-- Removed EDGES are full 8-token records now (same shape ROADC uses),
-- which is what makes the UPGRADE tool (caller 4790fc: N=0 added nodes,
-- M added edges, M removed edges, every endpoint an existing node)
-- replicable at all -- see the rm list built below.
--
-- Converted here into a purely POSITIONAL command. ...
```

### 1.3 Stamping and queuing

`net.lua:532-635`, `CM.scheduleLocal`:
- `lead = max(0, fastestPeerClock - now)`.
- `delay = execDelayCur + lead`. `execDelayCur` is auto-tuned from RTT: `K.EXEC_DELAY = 0.4` (`lockstep.lua:167`), min/max at 188–212, max 3.0 units, `MAX_LEAD = 15`.
- The stamp is ceil-snapped to the 0.2-unit sim step:
  `at = tonumber(string.format("%.4f", math.ceil(rawAt / K.SIM_STEP - 1e-6) * K.SIM_STEP))`.
- The originator **queues and does not execute** (`net.lua:597-601`):

```lua
	CM.queue[#CM.queue + 1] = c
	-- The originator does NOT execute now. It queues for the same stamp as
	-- everyone else -- that is the whole point. Applying locally and shipping a
	-- copy is what the old state-diff design did, and it is why the two worlds
	-- were never actually in step.
	local wire = encodeCmd(c)
	CM.recordSent(CM.seqNo, wire)
	CM.histPush(wire, at)
	local hi = string.format("LSHI o=%s s=%d at=%.4f", K.INSTANCE, CM.seqNo, at)
```

### 1.4 Wire format

`net.lua:477-497`, `encodeCmd`. The line is `LSCMD op=X at=%.4f origin=<letter> seq=%d`, then the remaining keys sorted, numbers as `%.4f`, and `params=` last as a greedy tail. That tail holds a serialized Lua table literal for constructions.

```lua
	table.sort(keys)
	local parts = { string.format("LSCMD op=%s at=%.4f origin=%s seq=%d",
		c.op, c.at, c.origin, c.seq) }
	for _, k in ipairs(keys) do
		local v = c[k]
		if type(v) == "number" then
			parts[#parts + 1] = string.format("%s=%.4f", k, v)
		else
			parts[#parts + 1] = k .. "=" .. tostring(v)
		end
	end
	if c.params then parts[#parts + 1] = "params=" .. c.params end
```

**Values cannot contain spaces.** Positions are packed as `x,y;x,y` and names are escaped (`CM.unescName`).

**`decodeCmd`** (`net.lua:499-527`):
- Strips the history tag ` hist=1 hfor=X`.
- Parses `params=` as the tail.
- Converts tokens with tonumber, except `name`.

### 1.5 Transport and receive

`io.lua`:
- `CM.broadcast(line)` (`io.lua:129`) does `appendLine(K.CAPTURE_FILE, line)`, writing `tpf2_capture_<L>.txt`.
- The native bridge DLL tails that file and forwards lines over UDP via the netpunch lobby.
- Received lines are appended to `tpf2_events_<L>.txt`.
- `CM.readFrom` (offset based, trims to the last newline) reads them in `pollEvents`.
- `CM.detectInstance` reads `tpf2_instance.txt` to learn the letter and set the paths.

**Reliability** (`net.lua`):
- Per-origin `seq`.
- `LSHI o= s= at=` announcements.
- `K.CMD_SEND_COPIES` (2) copies sent back to back, plus `K.CMD_REPEATS` repeats on the next ticks (`net.lua:602-620`).
- `LSNACK` on a gap.
- Dedup by `cmdKey = at|origin|seq` (`roads.lua:31-36`).
- **Gap hold** (`net.lua:1162-1279`): the sim is held at speed 0 while an announced seq is missing and its stamp is near.
- **History feed** (`LSNEED` / `LSHISTEND`): lets joiners and laggards replay commands since `savedAt`.

**Heartbeat** (`lockstep.lua:1097-1110`). `LSTICK` is sent every 2 ticks:
- `t` game time, `s` step.
- `hi` highest seq, `cu` catch-up, `ms`, `ha` hash.
- `e` echo for RTT, `hc` hash cost, `ak` acks.

### 1.6 Apply loop

`lockstep.lua:1133-1267`.

**Sorting.** The queue is sorted by `(at, origin, seq)` (`CM.cmdLess`, `roads.lua:31-36`).

**Pre-pass** (assigns `notBeforeStep`):
- VBUY: one buy per step, with `BIND_GUARD_STEPS = 10` after a buy before anything depending on it.
- LCREATE dependencies: `LINE_MATERIALIZE_STEPS = 5`.
- VLINE: lands on a 10-step grid (constants at `lockstep.lua:557-561`).

**Apply** (`lockstep.lua:1222`):
```lua
	elseif (c.notBeforeStep or CM.stepOf(c.at)) <= CM.stepOf(now) then
		if c.op == "VBUY" and buysThisTick >= 1 and not executed[CM.cmdKey(c)] then
			deferRest = true
			keep[#keep + 1] = c
		else
		local k = CM.cmdKey(c)
		...
		if not executed[k] then
			executed[k] = true
```

**Dispatcher.** `execute(c)` (`lockstep.lua:641-683`) maps each op to its handler:

| Op(s) | Handler |
|---|---|
| ROADP | `CM.execPolyline` |
| EDEMO | `cons.lua` |
| CONX / CONP | `CM.execConX` |
| CONU | `CM.execConU` |
| DEMOLISH | `CM.execDemolish` |
| STOP* | `stops.lua` |
| V* | `CM.execVehCmd` / `execVBuy` |
| L* | `CM.execLine` |
| SPEEDVOTE, HASHEVERY, LOAN, ... | various |

**Retries** advance by a fixed 5 steps from the agreed target, never from local time.

**Clock:**
- `game.interface.getGameTime().time` (`hash.lua:76-94` `gameTime`; `lockstep.lua:147` notes that these are not seconds).
- The clock advances 0.2 units per sim step (`K.SIM_STEP = 0.2`, `lockstep.lua:549`).
- `CM.stepOf(t) = floor(t/0.2 + 0.5)` (`io.lua:133`).

---

## 2. Roads and tracks

### 2.1 Id mapping: no ids on the wire

**Inject side** (`inject.lua:268-699`). It turns ROADE into **ROADP**:
- `realPos(id)` reads each positive (existing) node's `BASE_NODE.position`.
- Split detection is geometric (`findEdgeContaining`). The split halves the native tool made are dropped, because the replay recomputes them.
- `fv` lists fresh vertices.
- `rm` lists removals, positionally: `"x0,y0,x1,y1;..."`. Split parents are skipped.
- `br` / `bs` carry unchanged bridge companions.
- `etype`, `stype`, `ttype`, `cat` are the edge, street and track type and catenary.
- A **plan pass** runs `CM.execPolyline(..., true)` locally and ships its decisions as `xv` / `xh`, so peers resolve vertices the same way.

**Replay side** (`roads.lua:515-1742`, `CM.execPolyline`). Each polyline vertex goes through `resolve(i)` (`roads.lua:803`), in this order:
1. Fresh vertex.
2. Plan hint.
3. `CM.findNodeNear(isTrack, x, y, 1.5)`, which reuses an existing node within 1.5 m (horizontal).
4. Crossing node: within 4.0 m if a track crosses, else 1.5 m (`roads.lua:881`).
5. `findEdgeContaining` split.
6. New node.

`findEdgeContaining` (`geom.lua:279-350`) uses `SPLIT_EPS = 5.0` for roads, `SPLIT_EPS_TRACK = 2.0` for tracks and `SPLIT_MIN_DIST = 0.3`. A split point within 2.5 m of an edge end snaps to that end.

**New entities get placeholder ids**, which are local and deterministic (`roads.lua:669-688`):
```lua
		local function newNodeAt(x, y, z)
			nextNew = nextNew + 1
			-- Keep node placeholders dense and local to this proposal.
			-- The engine's crossing/cleanup path rejects the same graph when these
			-- use the large origin/sequence namespace (live parallel-track repro).
			local id = -nextNew
			local n = api.type.NodeAndEntity.new()
			n.entity = id
			n.comp.position = api.type.Vec3f.new(x, y, z)
			addNodes[#addNodes + 1] = n
			return id
		end

		local function newEdge()
			nextEdge = nextEdge + 1
			local e = api.type.SegmentAndEntity.new()
			e.entity = base - 500 - nextEdge
			return e
		end
```
Nodes are `-1, -2, ...`. Edges are `base-500-n`, where `base = -(200000 + originIdx*100000 + seq*10)` (`roads.lua:343`).

**`findNodeNear`** (`geom.lua:179-207`) iterates `api.engine.system.streetSystem.getNode2TrackEdgeMap()` / `getNode2StreetEdgeMap()` and reads `BASE_NODE` positions. It uses horizontal distance only.

### 2.2 Removals

**Removal matching** (`roads.lua:625-667`). Each shipped `rm` pair goes through `findNodeNear(…, 1.5)` at both ends; the edge is the one joining exactly those two nodes. **One unmatched removal skips the whole command**, because adding without removing doubles the edge.

```lua
		for _, r in ipairs(rms) do
			local nA = CM.findNodeNear(isTrack, r[1], r[2], 1.5)
			local nB = CM.findNodeNear(isTrack, r[3], r[4], 1.5)
			local eid
			if nA and nB and nA ~= nB then
				local mm
				...  mm = CM.netMap(isTrack)
				for _, cand in pairs((mm and mm[nA]) or {}) do
					local be
					pcall(function() be = api.engine.getComponent(cand, api.type.ComponentType.BASE_EDGE) end)
					if be and ((be.node0 == nA and be.node1 == nB)
					           or (be.node0 == nB and be.node1 == nA)) then
						eid = cand
						break
					end
				end
			end
			if not eid then
				... log(msg) ... return
			end
			dropEdge(eid)
```

The proposal is filled at `roads.lua:1531-1539`:
```lua
		for i, n in ipairs(addNodes) do sp.streetProposal.nodesToAdd[i] = n end
		for i, e in ipairs(addEdges) do sp.streetProposal.edgesToAdd[i] = e end
		...
		for i, rid in ipairs(removeEdges) do sp.streetProposal.edgesToRemove[i] = rid end
		for i, rid in ipairs(removeNodes) do sp.streetProposal.nodesToRemove[i] = rid end
```

**Upgrade shape** (`docs/re/PROPOSALS.md` tool table): N added segments replace N removed, with **no** added nodes and every endpoint an existing node. It replays through the same `rm` path.

**Bulldozing edges (EDEMO).**

Capture (`inject.lua:1574-1630`):
- Native format: `EDEMO <re> <rn> [<node0> <node1> <kind>]*re [<id> <x> <y> <z>]*rn`.
- Node ids are resolved to positions on the originator in the same tick; endpoints survive an edge-only bulldoze.
- Nodes that the bulldoze also removed travel with their own positions.

Replay (`cons.lua:721-961`):
- Builds a grid index of nodes and matches each end within **1 m** per kind (street or track).
- The edge is the intersection of both nodes' edge lists.
- **Refuses edges that carry objects** (stops or signals).
- Orphan nodes are removed too.
- The proposal is built at `cons.lua:929-935`:
```lua
		for i, eid in ipairs(rmList) do sp.streetProposal.edgesToRemove[i] = eid end
		for i, nid in ipairs(orphans) do sp.streetProposal.nodesToRemove[i] = nid end
		...
		ctx.cleanupStreetGraph = true
```
It is submitted with `api.cmd.make.buildProposal(sp, ctx, true)`.

### 2.3 Edge objects (stops, signals, waypoints)

**Carry-over on replace** (`roads.lua:287-332`, `CM.carryEdgeObjects`):
- When an edge with objects is removed and re-added one for one (an upgrade), the old `{id, side}` list goes into the new edge's `comp.objects`.
- If the new edge runs the other way, it is rebuilt in the old edge's direction: nodes swapped, tangents negated and swapped.
- Otherwise (a split or reroute), it **refuses**.
- Splits distribute objects to the halves by `u` (`roads.lua:760-774`).

```lua
			if reversed then
				local t0, t1 = hit.comp.tangent0, hit.comp.tangent1
				...
				hit.comp.node0, hit.comp.node1 = a, b
				hit.comp.tangent0 = api.type.Vec3f.new(-x1, -y1, -z1)
				hit.comp.tangent1 = api.type.Vec3f.new(-x0, -y0, -z0)
			end
			local list = {}
			for _, o in ipairs(objs) do list[#list + 1] = { o[1], o[2] } end
			hit.comp.objects = list
```
`CM.objectsOnEdge(eid)` (`stops.lua`) reads `BASE_EDGE.objects` as `{entityId, side}`.

**Rules for edge objects** (`docs/re/PROPOSALS.md:235-275`):
- Untouched objects keep their positive ids and are re-parented by listing them in the new edge's `objects`.
- `side` is 0, 1 or 2.
- `old2newEdgeObjects` is not settable from Lua.

**Capture** (`inject.lua:750-823`). STOPX becomes **STOPADD**, carrying:
- the edge end positions `ax, ay, bx, by`;
- `u`;
- the engine `left` byte as `eleft`, plus the tangent `tx, ty` used to flip the side if the peer's edge is reversed;
- the model **name**;
- `kind` and `oneWay`.

STOPXDEL becomes **STOPDEL** (`inject.lua:1668-1704`).

**Replay** (`stops.lua:674-841`, `execStopAdd`):
- Finds the edge by its ends within 2 m, or by `findEdgeContaining`.
- Flips the side by the tangent dot product.
- Calls `CM.nativeStopProposal` (`stops.lua:559-656`), which reproduces the native shape: the edge is removed and re-added with entity `-k`, survivors listed by positive id, and the new object listed as `{-1, side}`.

```lua
		local objs, n = CM.objectsOnEdge(eid)
		...
		local list = {}
		for _, o in ipairs(objs) do
			if not (remove and o[1] == remove.eo) then
				list[#list + 1] = { o[1], o[2] }
				survivors[#survivors + 1] = o[1]
			end
		end
		if add and eid == add.eid then
			list[#list + 1] = { -1, add.side }
		end
		e.comp.objects = list
		sp.streetProposal.edgesToAdd[k] = e
		sp.streetProposal.edgesToRemove[k] = eid
	end
	if remove then sp.streetProposal.edgeObjectsToRemove[1] = remove.eo end
	if add then
		local eo = api.type.SimpleStreetProposal.EdgeObject.new()
		eo.edgeEntity = -1
		eo.param = add.u
		eo.left = add.left and true or false
		eo.oneWay = add.oneWay and true or false
		eo.model = add.model
		eo.playerEntity = add.player or api.engine.util.getPlayer()
		eo.name = add.name or ""
		sp.streetProposal.edgeObjectsToAdd[1] = eo
```

The command is submitted with `api.cmd.make.buildProposal(sp, CM.buildContext(), true)`. The callback verifies every survivor id is still in `streetSystem.getEdgeObject2EdgeMap()`.

**Constraints:**
- `nativeEdgeCopy(eid, isTrack, -k)` copies the existing edge's components into a new `SegmentAndEntity`.
- `frozenOwnerOf` refuses edges frozen into a construction.
- Stop replays are serialized (`stopEnqueue` / `runQueued`).

### 2.4 Fields set on SegmentAndEntity and NodeAndEntity

The minimal example is `roads.lua:334-412`, `CM.execEdge`:
```lua
		local n0 = api.type.NodeAndEntity.new()
		n0.entity = nid0
		n0.comp.position = api.type.Vec3f.new(c.x0, c.y0, c.z0)
		...
		local e = api.type.SegmentAndEntity.new()
		e.entity = eid
		e.comp.node0 = nid0
		e.comp.node1 = nid1
		e.comp.tangent0 = api.type.Vec3f.new(dx, dy, dz)
		e.comp.tangent1 = api.type.Vec3f.new(dx, dy, dz)
		e.comp.type = 0          -- 0 ground / 1 bridge / 2 tunnel
		e.comp.typeIndex = -1    -- bridge/tunnel resource index, -1 on ground
		e.type = isRail and 1 or 0   -- 0 street, 1 track
		if isRail then
			e.trackEdge = api.type.BaseEdgeTrack.new()
			e.trackEdge.trackType = c.ttype or 1
			e.trackEdge.catenary = (c.cat == 1)
			-- A street edge is mandatory even on a track (ResTypeRep<StreetType>::Get(-1) asserts)
			e.streetEdge = api.type.BaseEdgeStreet.new()
			e.streetEdge.streetType = c.stype or 16
		else
			e.streetEdge = api.type.BaseEdgeStreet.new()
			e.streetEdge.streetType = c.stype or 16
			e.streetEdge.hasBus, e.streetEdge.tramTrackType = CM.streetProps(c, c.x0, c.y0, c.x1, c.y1)
		end
		sp.streetProposal.edgesToAdd[1] = e
```
(The comments are condensed from the source.)

**Full field list:**

NodeAndEntity:
- `entity`: a negative placeholder, or a positive existing id when it is referenced only by edges.
- `comp.position` (`Vec3f`).

SegmentAndEntity:
- `entity`: a negative placeholder.
- `comp.node0`, `comp.node1`: placeholders or existing ids.
- `comp.tangent0`, `comp.tangent1` (`Vec3f`): Hermite tangents. Splits are computed with Hermite math in `splitEdgeAt`.
- `comp.type` and `comp.typeIndex`: bridge/tunnel, copied from the source edge by `copyEdgeProps`.
- `comp.objects`: the `{id, side}` list.
- `type`: 0 street, 1 track.
- `trackEdge.trackType` and `trackEdge.catenary`.
- `streetEdge.streetType`, `streetEdge.hasBus` and `streetEdge.tramTrackType`. `geom.lua:367-388` inherits hasBus and tram from the replaced edge.
- `playerOwned`: an `api.type.PlayerOwned.new()` with `.player` (`geom.lua:417-425`, `applyEdgeOwner`).

`copyEdgeProps` (`geom.lua:417-453`) clones the owner, bridge/tunnel type, track and street props from an existing edge onto split halves and companions.

**Context** (`roads.lua:51-64`, `buildContext`):
```lua
		local c = api.type.Context:new()
		c.checkTerrainAlignment = false
		c.cleanupStreetGraph    = true
		c.gatherBuildings       = false
		c.gatherFields          = true
		c.player                = api.engine.util.getPlayer()
```
- `roadBuildContext` (`roads.lua:102-125`) is the same but with `gatherBuildings = true`.
- `conxContext` (`roads.lua:259-273`) uses `checkTerrainAlignment = true`.
- A nil Context builds for free **and** demolishes, so a road build is refused when no Context can be made (`roads.lua:394-399`).
- The `ignoreErrors` argument is `true`, as the native tool does. With `false`, collisions refuse the build instead of demolishing.

**Submission and diagnostics.** Builds go through `api.cmd.sendCommand(api.cmd.make.buildProposal(sp, ctx, true), function(res, success) ... end)`. On failure the code reads `res.resultProposalData.errorState.critical` / `.messages` and `collisionInfo`.

**Level crossings** (`docs/re/PROPOSALS.md:206-233`, `roads.lua` `crossingsFor`):
- The crossing edge is split and one node is shared.
- The node takes the road height when the z difference exceeds 0.25 m.
- `XING_MAX_DZ = 7` (`geom.lua`).

**Other details:**
- WELD v2 handles endpoints near existing nodes.
- Duplicate node pairs are deduplicated.
- Template connector: a script placement passes empty `nodes2snap`, so the connector is unwelded. The native `MergeTemplateStreet` patch fixes that (`docs/re/PROPOSALS.md`).

---

## 3. Constructions

### 3.1 Capture

**Placement** (`inject.lua:825-865`). `CONXP` carries:
- `file`;
- `t`, the 16-number transform;
- `ps`, the placement serial;
- `rc`;
- params read natively off the proposal (`constructions.inl`).

It is parked in `pendingCons`. The construction's street payload arrives separately as `ROADC` (`inject.lua:866-971`, parked in `pendingRoadc`) and the two are paired by `ps` or by frozen nodes (`cons.lua:1398`, `flushConPairs`).

**Shipping** (`cons.lua:1244-1316`). `shipConxPair` emits **CONX** with these fields:

| Field | Meaning |
|---|---|
| `file` | construction file |
| `t` | 16 × `%.4f` |
| `params` | Lua literal |
| `name` | name |
| `survivors` | town buildings that survived |
| `srad` | survivor radius |
| `cost`, `bal` | cost, balance |
| `cancelled` | 1 if the native build was cancelled |
| `snodes` | `id,x,y,z;` |
| `sedges` | `a,b,t0,t1,btype,bidx;` |
| `srm` | street removals |
| `spos` | positions of existing node ids |
| `etype`, `stype`, `ttype`, `cat` | edge, street and track types, catenary |

**Fallback.** If the native path isn't available, a poll path is used (`cons.lua:1160-1188`, `queueConCapture`). It reads `CONSTRUCTION` and `NAME` and keeps only `PLAYER_OWNED` constructions (`cons.lua:980-1006`).

**Params serialization** (`cons.lua:46-78`, `ser`):
- Sorted keys and `%q` strings, with a `\n` fix, so the output is deterministic.
- Deserialized with `load("return "..pstr, "params", "t", {})` (`cons.lua:123-141`) in an empty environment.
- `params.seed` must be present or buildProposal returns false (`docs/re/PROPOSALS.md:163-180`).

### 3.2 Replay

`conx.lua:110`, `CM.execConX`:
- Runs one construction at a time (`conxQueue` / `conxBusy`).
- **Originator, strict, not cancelled:** it bulldozes its native copy and rebuilds at the stamp, so all instances allocate at the same step.

The proposal (`conx.lua:254-289`):
```lua
		local sp = api.type.SimpleProposal.new()
		local ce = api.type.SimpleProposal.ConstructionEntity.new()
		ce.fileName = tostring(c.file)
		ce.params = params
		ce.transf = api.type.Mat4f.new(
			api.type.Vec4f.new(t[1], t[2], t[3], t[4]),
			api.type.Vec4f.new(t[5], t[6], t[7], t[8]),
			api.type.Vec4f.new(t[9], t[10], t[11], t[12]),
			api.type.Vec4f.new(t[13], t[14], t[15], t[16]))
		ce.playerEntity = api.engine.util.getPlayer()
		...
		-- The name goes IN the proposal. ... with ce.name set, the apply gives the
		-- construction AND its child entities (VEHICLE_DEPOT / stations) their NAME
		-- and PLAYER_OWNED ... Without it ... client crash on click.
		if tonumber(c.cancelled or 0) == 1 then
			local dn
			pcall(function() dn = CM.depotName(t[13], t[14], c.file) end)
			ce.name = (dn and dn ~= "") and dn or CM.unescName(c.name)
		else
			ce.name = CM.unescName(c.name)
		end
		sp.constructionsToAdd[1] = ce
```
`CM.depotName` (`conx.lua:70`) gives a deterministic "<nearest town> <type> #N".

**Street payload** (`conx.lua:319-630`):
- The removed edge is found under the split node position (`findEdgeContaining`). Its endpoint ids are mapped by orientation (`idmap`).
- Each `spos` existing id is mapped by `findNodeNear` within 1.5 m. A missing one skips the build and is logged as a DIVERGENCE.
- Apron edges with both ends new are dropped, because the template regenerates them (504–530).
- Segment entity ids continue below the minimum node id.
- Split halves get local tangents.

**Submit** (`conx.lua:668-697`):
- `ctx = CM.conxContext()`, with `gatherBuildings = true` when the native build was cancelled.
- The command is `api.cmd.make.buildProposal(sp, ctx, not selfRebuild)`.
- Fallback: `game.interface.buildConstruction` plus `setPlayer`.

**Callback:**
- `res.resultEntities[1]` is the new construction.
- Survivor diff: town buildings within `srad` that are not in `survivors` are bulldozed (`game.interface.bulldoze`).
- Company money is reconciled through a journal.

**On failure:**
1. Retry after clearing the footprint.
2. Bare probe.
3. Broadcast **CONFAIL**. `execConFail` (`conx.lua:1400`) makes the originator bulldoze its own copy (same file within 1 m).

### 3.3 Upgrade and module edit

`inject.lua:700-749` turns CONUP into **CONU** (strict), carrying a param diff from `CM.conDiff` (`cons.lua:94-121`: `top`/`topdel`/`mset`/`mdel` over modules).
- Native shape (`docs/re/PROPOSALS.md`): `toRemove[0]` is the old construction, `toAdd[0]` the new one.
- Replay (`cons.lua:242-329`, `execConU`): `findConNear` looks for the same file within **10 m** and applies the diff with `seed = nil`, then calls `game.interface.upgradeConstruction(rec.id, file, params)` (`cons.lua:303`).

### 3.4 Demolish

`inject.lua:1640-1665` turns CDEMO into **DEMOLISH** (strict), carrying `file` and `transf[13], transf[14]`.
- Replay (`cons.lua:622-701`, `execDemolish`): the same file within **2 m**, then `game.interface.bulldoze(id)` (`cons.lua:689`).
- In companies mode, `setBulldozeable` is called first.

**Keys.** Constructions are keyed by `conKey = "%.1f/%.1f"` of the position (`cons.lua:191`), plus the file.

---

## 4. Lines and vehicles

### 4.1 Keys, not ids

**Vehicle keys** (`vehicles.lua:17-106`):
- `origin:seq` for a vehicle bought in the session.
- `s:<id>` for one from the save (`primedVeh`). Ids of entities loaded from a save are identical on every instance.
- `vehKeyOf` / `vehIdOf` translate in each direction.

**Line keys** work the same way (`lines.lua:29-98`).

**Save.** Both registries ride in the game-script save (`lockstep.lua:1424-1449`; `vehicles.lua:131-178`; `lines.lua:112-161`). The save also carries `cm`, `vposOff`, `hashGrid`, `actionSounds` and `savedAt`.

**Binding** (`vehicles.lua:478-552`, `pollVehKeys`):
- Prefers `res.resultEntity` from the buy callback.
- Otherwise uses purchaseTime or enumeration order.

**Lines** (`lines.lua:580-639`, `pollLineKeys`) match fresh lines by stop signature and name. A line exists only one step after `createLine` (`docs/re/SCRIPT_API.md`).

### 4.2 Vehicle buy

**Capture** (`inject.lua:973-1161`). The config is decoded (model, rev, nl, loads, rgb, na, autos, groups) and shipped as:

| Field | Content |
|---|---|
| `parts` | `name~loads~r,g,b~autos~rev;...`, model as a **name** via `api.res.modelRep.getName` |
| `groups` | vehicle groups |
| `x`, `y`, `file` | the depot's parent construction, found by searching `co.depots` |
| `armed` | the ARMED flag |
| `cline` | the clone's line (from `VBUYLINE`) |
| `pt` | purchaseTime |

**Config** (`vehicles.lua:999-1059`, `CM.buildVehConfig`):
```lua
	local config = api.type.TransportVehicleConfig.new()
	...
		pcall(function() mid = api.res.modelRep.find(name) end)
		local part = api.type.VehiclePart.new()
		part.modelId = mid
		local lc = part.loadConfig
		for v in loads:gmatch("[^/]+") do n = n + 1; lc[n] = tonumber(v) or 0 end
		if n == 0 then error("part without load slots: " .. spec) end  -- native assert otherwise
		part.loadConfig = lc
		part.reversed = (rev == "1")
		part.color = api.type.Vec3f.new(tonumber(r) or -1, tonumber(g) or -1, tonumber(b) or -1)
		part.logo = ""
		local tvp = api.type.TransportVehiclePart.new()
		if pt and pt > 0 then tvp.purchaseTime = math.floor(pt)
		else tvp.purchaseTime = math.floor((tonumber(c.at) or 0) * 1000) end
		tvp.maintenanceState = 1.0
		tvp.targetMaintenanceState = 0
		... tvp.autoLoadConfig = alc   -- exactly one 0/1 per load slot or the engine asserts
		tvp.part = part
		config.vehicles[u] = tvp
	...
	config.vehicleGroups = grp   -- default {u}
```
If `purchaseTime` is 0, the engine asserts and writes a minidump on every replayed buy.

**Buy** (`vehicles.lua:1130-1239`):
- `findBuyDepot` (1087–1128) finds the construction by `conKey` + `file`, then takes `CONSTRUCTION.depots[1]`. buyVehicle wants the `VEHICLE_DEPOT` child.
- The command is `api.cmd.make.buyVehicle(who, target, config)` (`vehicles.lua:1206`).
- The key `origin:seq` is bound from `res.resultEntity`:
```lua
			api.cmd.sendCommand(cmd, function(res, success)
				...
				if success then
					local nid = nil
					pcall(function()
						local r = res and res.resultEntity
						if type(r) == "number" then nid = r elseif r ~= nil then nid = tonumber(tostring(r)) end
					end)
					if not (nid and nid > 0) then nid = nil end
					expectVehicle(key, depot, company, nid, bal0)
```

**Replace** (`vehicles.lua:1259-1313`). `api.cmd.make.replaceVehicle` is used, and the key is rebound if the id changes.

### 4.3 Other vehicle commands

`vehicles.lua:768-947` (`execVehCmd`):

| Op | Call |
|---|---|
| VSELL | `api.cmd.make.sellVehicle(id)` |
| VDEPOT | `api.cmd.make.sendToDepot(id, sell)` |
| VREV | `api.cmd.make.reverseVehicle(id)` |
| VSTOP | `api.cmd.make.setUserStopped(id, bool)` |
| VLINE | `api.cmd.make.setLine(id, line, stopIx)` (line 895), with an auto stop search |
| VNAME / VCOLOR | `setName` / color (for vehicles, lines and constructions) |

- Failed commands are retried on fixed steps.
- Parked vehicles are found with `api.engine.system.transportVehicleSystem.getVehiclesWithState(IN_DEPOT)` plus `TRANSPORT_VEHICLE.depot` (`vehicles.lua:35-56`).
- `deferVehCap` / `shipVehCap` (`vehicles.lua:240-318`): VLINE waits until both the vehicle and the line have keys; VSELL is atomic.

### 4.4 Lines

**Capture** (`inject.lua:1317-1528`).

LCREATEX ships `stops` as records `"sgx,sgy,station,terminal,loadMode,min,max[,sx,sy]"` separated by `;`. Here sg is the station group position and s the station position. It also ships `alts` (`st:term/...;;`), plus name, color and waypoints.

LUPDATE:
- Is decoded, or read back via `LREADBACK` 3 steps later.
- Is merged with pending edits.
- Carries an `asg` flag.
- Gets `lineApplyNow` when the line has no vehicles.

LDELETE is shipped as is.

**Station resolution:**
- `findStationGroupNear` scans `STATION_GROUP` via `game.interface.getEntities` within 20 m.
- `stationGroupPos` uses `game.interface.getEntity(sg).position`.
- The station inside the group is resolved by position within 10 m.

**Line object** (`lines.lua:789-858`):
```lua
	local lineObj = api.type.Line.new()
	lineObj.waitingTime = CM.waitNum(c.wait, 180)
	...
		local sg = findStationGroupNear(f[1], f[2])        -- within 20 m
		...  -- station index re-resolved by STATION_GROUP.stations positions (d < 10 m)
		local s = api.type.Line.Stop.new()
		s.stationGroup = sg
		s.station = idx
		s.terminal = f[4]
		s.loadMode = f[5]
		s.minWaitingTime = f[6]
		s.maxWaitingTime = f[7]
		... s.waypoints = target
		... local t = api.type.StationTerminal.new(); t.station = ..; t.terminal = ..; s.alternativeTerminals = at
		lineObj.stops[n] = s
```

**Execute** (`lines.lua:906-1039`):
- `api.cmd.make.createLine(name, color Vec3f, api.engine.util.getPlayer(), lineObj)` (996).
- `updateLine(lid, lineObj)` (958, 1019).
- `deleteLine(lid)`, `setName`, `setColor`.
- `retryLineDep`.

**Spare lines** (`lines.lua:641-773`):
- A hidden pool company is created with `game.interface.addPlayer`.
- Lines are pre-created on it in lockstep: `make.createLine(..., CM.poolPid, lineObj)` (722).
- A player's new line claims a spare, so no entity is ever allocated off-step. In the code's words: "an entity allocated off-step shifts every id allocated after it on that game".
- The GUI side requests a spare via `lockstep_lfire_req.txt`, and claims are written to `lspare`/`lclaim` files.

---

## 5. Determinism, pacing, money/date/speed, hash, resync

### 5.1 Determinism rules

1. Everything is applied at the same sim step, the originator included (strict).
2. **Nothing is allocated off-step.** This is why there are spare lines, one VBUY per step, bind guards and the VLINE grid.
3. Placeholder ids are derived from the command, never from local counters (`roads.lua:337-343`).
4. Ids never travel. References are positions, files or keys. Save-loaded ids are trusted to be identical.
5. Constructions and stop edits run serialized (one in flight).
6. Retries happen at agreed step offsets, never at local times.
7. `mod.lua` (`runFn` with `addModifier("loadGameScript")`) wraps `natural_town_growth`, `autosig2` and snowball fences to make them deterministic. `deterministic_script.lua` provides the game-time based helper.
8. Native patches handle engine-internal order nondeterminism (§1.1).
9. A loaded world orders entities differently from a running one. Resync therefore reloads **every** world, host included (`docs/RESYNC.md`).

### 5.2 Pacing and speed

**The leader is the clock.** Host `a` broadcasts `LSEFF`, the effective speed. The session speed is the mean of the `SPEEDVOTE` commands (`pacing.lua:133-200`).

**Followers** run a PID trim (`pacing.lua:785` onward, `pidPace`):
- Range 0.7–1.2x.
- kp .05, ki .015, kd .02.
- Deadband .3, slew .05.

**Catch-up:**
- A gap over 1.0 unit is closed at `1 + 0.35*gap`, capped at 2x.
- When more than 8 units behind, the follower catches up at up to 4x by replaying history.
- Player actions are disabled when more than 15 units behind and re-enabled at 2.

**Load gate** (`pacing.lua:10-36`, 1625–1752): the game is held at speed 0 until the history since `savedAt` has arrived.

**Setting the speed** (`pacing.lua:81-111`):
```lua
function CM.setDither(v)
	local want = (v and v ~= math.floor(v)) and string.format("%.4f", v) or ""
	...
	pcall(function()
		local p = K.BASE .. "tpf2_speed.txt"
		if want == "" then CM.clearFile(p) else local f = io.open(p, "w"); if f then f:write(want, "\n"); f:close() end end
	end)
end

function CM.setSpeed(v, why)
	v = tonumber(v) or 0
	CM.setDither(v)
	v = CM.leverOf(v)
	...
	pcall(function() api.cmd.sendCommand(api.cmd.make.setGameSpeed(v)) end)
```
The speed lever is integer-valued. Fractional speeds are written to `tpf2_speed.txt`, and the native bridge dithers the number of sim batches per frame.

**Date and calendar** (`pacing.lua:400-447`, `execCalendar`): `game.interface.setMillisPerDay` and `setDate`, stamped like any command.

**Money:**
- `LOAN` carries an absolute amount (`conx.lua:1462`, `execLoan`, journal type 0).
- Coop or companies mode reconciles build costs through the book journal (`cmBookJournal`, `cmSettleBuild`).
- Money only gets a detail lane in the hash, never the verdict.

### 5.3 Hash

`hash.lua`:
- Two Lehmer lanes (19–67).
- `worldHash` is at 612–893.

**Verdict lanes**, which are id-free:
- `v`: vehicle count.
- `c`: player constructions as `file@x,y:hash(params minus seed)`, plus player stops.
- `e`: edges by endpoint xyz at 0.1 m.

The verdict is computed at `hash.lua:821`:
```lua
	local verdict = hashStr("v" .. nv .. "|" .. hc .. "|" .. he)
```

**Detail lanes** (diagnosis only):
- `z`, `p`: vehicle positions. Drift over 10 m is a desync; the check is disabled above 200 vehicles.
- `r`: train names.
- `m`, `l`: money and loan.
- `t`: town construction count.
- `n`: people.
- `k`.

The lanes are documented at `docs/REPLICATION.md:183-192`.

**Cadence** (`hash.lua:448-610`):
- Starts at 12 units × (edges/2000 + 1), capped at ×64.
- The leader changes it with a stamped `HASHEVERY` command.
- A hash is published only for a stamp this game's clock actually crossed (`hashStampOf`).
- `checkHash` (`lockstep.lua:787-867`) compares the published hashes.

### 5.4 Resync and join

`docs/RESYNC.md`:
1. Host-initiated.
2. Every instance saves.
3. The host's save is transferred (netpunch `sync_operation.py`, `native_io.cpp`).
4. All instances, **host included**, reload.

Frozen joins use the same round.

---

## 6. What breaks without `io` (and without `game.interface`) in TF3

### 6.1 Every `io` use in the mod

| Use | Where | Purpose |
|---|---|---|
| Data dir discovery | `lockstep.lua:74-126` | `io.open` probing |
| Instance letter | `io.lua` `CM.detectInstance` | `tpf2_instance.txt` |
| **Inbound commands** | `io.lua` `CM.readFrom` → `tpf2_events_<L>.txt` | the entire receive path |
| **Outbound commands** | `io.lua:129` `CM.broadcast` → `tpf2_capture_<L>.txt` | the entire send path |
| **Native capture** | `inject.lua:106-206` → `lockstep_inject_<L>.txt` | the action source |
| Cancel arming | slice reads `lockstep_status_<L>.txt` | the peer-present flag |
| Fractional speed | `pacing.lua:81-93` `tpf2_speed.txt` | dither |
| Spare-line fire and claims | `lockstep_lfire_req.txt`, `lspare`/`lclaim` | the GUI ↔ engine channel |
| Dashboard | guiUpdate reads dash/status files | UI |
| Companies | `mp_company*` files | company assignment |
| Misc | `world_gen`, `hash_every`, dedicated flag, `egeo` dump, logs | config and debug |

`docs/re/SCRIPT_API.md` explains why files are used at all. `guiUpdate` and `guiHandleEvent` run in a **separate Lua state** from the game script, so files are the only channel between them, and the network is native. Without `io`, **the transport, the capture inbox and the GUI↔engine channel all need replacing.**

Candidates:
- A native plugin, if TF3 permits one.
- An engine-side message channel, if TF3 offers one.
- Command-based signaling through the game's own sync. TF3 being natively multiplayer is unconfirmed.

### 6.2 `game.interface` uses that need TF3 equivalents

| Call | Where |
|---|---|
| `getGameTime().time` (**the lockstep clock**) | `hash.lua:78`, `pacing.lua:402`, `deterministic_script.lua:68` |
| `getEntities` / `getEntity(id).position` | station-group search (`lines.lua`), town lookup |
| `getHeight` | `lockstep.lua:685` `groundAt` |
| `buildConstruction` | conx fallback |
| `upgradeConstruction` | `cons.lua:303`, 320, 1842 |
| `bulldoze` | `cons.lua:689`, `conx.lua:21`, 222, 1445, `companies.lua` |
| `setBulldozeable` | companies mode |
| `addPlayer`, `setPlayer` | spare-line pool, companies |
| `setDate`, `setMillisPerDay`, game speed reads | calendar |
| `getName` | naming |

**Likely TF3 substitutes:**
- **Removal:** build-proposal removal (`constructionsToRemove` / `edgesToRemove`).
- **Upgrade:** a proposal with remove plus add, which is exactly the native module-edit shape.
- **Bulldozable flag:** `makeWorldSetBulldozableCmd`.
- **Entity queries:** `api.engine.system.*` / `api.engine.getComponent`.
- **The clock:** must come from an engine component or system.

### 6.3 Capture model mismatch (the biggest design delta)

**TF2 captures commands before they execute and cancels them**, which lets the originator apply in step with everyone. TF3's `onPostBuildProposal` fires **after** the build has applied, so it cannot cancel. The result is effectively "replay on peers" (`skipOrigin=1`, the `ARMED 0` path). The TF2 code found this mode drifts:
- The originator allocates entity ids off-step.
- Town buildings and people demolished at a different time.

**Options:**
- (a) Originator undo and redo at the stamp: bulldoze its own result and rebuild through the proposal, as `execConX`'s strict self-rebuild does (`conx.lua`, `selfRebuild`). This costs one wasted allocation, but every instance then allocates at the stamp.
- (b) Accept optimistic replay and lean harder on the id-free hash plus resync.

Either way, the id-free design carries over unchanged:
- Positional road and edge matching (1.5 / 1 / 2 m tolerances).
- File + transform + params constructions.
- `origin:seq` keys for vehicles and lines.
- Station-group and station positions.

### 6.4 Native-only pieces with no Lua equivalent

- Terrain and asset grids (not expressible in a Lua SimpleProposal: `docs/re/PROPOSALS.md`). TF3's `makeWorldReplaceTerrainCmd` may cover terrain.
- Template connector weld (`MergeTemplateStreet`).
- Train reservation, ship and aircraft claim, and road-entry ordering patches.
- Speed dither.
- Save, transfer and reload for resync.
- UDP transport.

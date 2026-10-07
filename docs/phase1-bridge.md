# Phase 1: Brücke zwischen Lua-Mod und DLL

## Problem

Der TF2-Multiplayer-Mod (silver2127/tpf2-multiplayer) tauscht alle Daten zwischen Lua und DLL über Textdateien aus: Lua schreibt und liest sie mit `io.open`, die DLL liest sie mit. Die Bauaktionen fängt dort die DLL ab (Hooks auf feste Adressen in der TF2-exe), Lua spielt sie über `api.cmd` nach. Lua-C-API-Hooks benutzt der TF2-Mod nicht.

In TF3 fehlt `io` im Sandbox-Lua (Phase 0). Der Dateiweg aus TF2 geht also nicht. Verfügbar sind unter anderem `debugPrint`, `os.getenv`, `os.time`, `os.clock` und `load`.

## Kandidat ohne Reverse Engineering

| Richtung | Weg |
|---|---|
| Lua → DLL | Lua schreibt markierte Zeilen mit `debugPrint` nach `stdout.txt`. Die DLL liest die Datei laufend mit. |
| DLL → Lua | Die DLL setzt mit `_putenv_s` eine Umgebungsvariable (`TF3MP_IN`). Weil Spiel und DLL dieselbe C-Laufzeit (`ucrtbase.dll`) nutzen, sieht Lua sie über `os.getenv`. |

Beide Wege brauchen keine festen Adressen in der TF3-exe und überstehen damit Spiel-Updates.

## Test (Probe v5 + DLL v4)

- Probe v5 schreibt alle 50 Updates (10 s Spielzeit) `bridge out seq=N` ins Log und meldet jede Änderung von `os.getenv("TF3MP_IN")` als `bridge in TF3MP_IN=...`. Außerdem zeichnet sie Bauaktionen des Spielers vollständig auf.
- DLL v4 liest `stdout.txt` mit, schreibt jede gefundene `bridge out`-Zeile in `alut_proxy.log` und setzt danach `TF3MP_IN=ack <seq>`.
- Erfolg: Im Spiel-Log erscheinen `bridge in TF3MP_IN=ack N`-Zeilen, im DLL-Log die `bridge out`-Zeilen.

Falls `os.getenv` die Änderung nicht sieht (z. B. weil Lua eine eigene Kopie der Umgebung liest), ist der Rückweg der nächste offene Punkt. Alternativen dann: Lua-C-API in der exe finden und eine eigene Funktion registrieren, oder Befehle direkt in der DLL einspeisen wie in TF2.

## Ergebnis Lauf 5 (06.10.2026, Probe v5 + DLL v4)

Logs: [logs/probe-log-5-mp_probe.txt](../logs/probe-log-5-mp_probe.txt), [logs/proxy-log-5.txt](../logs/proxy-log-5.txt)

**Die Brücke funktioniert in beiden Richtungen.**

- Lua → DLL: Die DLL hat 82 Zeilen `bridge out seq=N` (311–392) aus `stdout.txt` gelesen, jeweils in derselben Sekunde, in der der Mod sie geschrieben hat. Das Spiel schreibt sein Log also sofort raus.
- DLL → Lua: `_putenv_s` aus `ucrtbase.dll` wirkt im Spielprozess. Der Mod hat zuerst `TF3MP_IN=hello` gelesen, danach bei jedem Tick `ack N`. `os.getenv("PATH")` liefert 976 Zeichen, der Mod sieht also die echte Prozessumgebung.
- Umlaufzeit: ein Bridge-Tick (`BRIDGE_EVERY = 50` Updates, etwa 2,5 s). Die DLL antwortet in unter 1 s; die Taktrate bestimmt also der Mod, nicht die DLL.

**Einfrieren beim Bahnhof:** Der Roh-Dump des Bahnhof-Vorschlags (`debugPrint` auf das ganze userdata) schrieb rund 84.000 Zeilen, dazu 9.000 für die Konstruktion. Das blockierte den Simulations-Thread rund 60 Sekunden. Probe v6 hat keine Roh-Dumps mehr und begrenzt jeden Dump auf 400 Zeilen.

## Aufgezeichnetes Bauformat (Lauf 5)

`onPostBuildProposal` liefert `param = {context, result, neueEntityIds, istSpielerbau}`. Ein Spielerbau hat `param[4] = true`.

```
param[1].proposal.addedNodes[i]    = { entity, comp.position{x,y,z} }
param[1].proposal.addedSegments[i] = { entity, type (0 Straße, 1 Gleis), params,
                                       comp{ type, node0, node1, tangent0{x,y,z},
                                             tangent1{x,y,z}, typeIndex, objects } }
param[1].proposal.removedSegments  = negative Entity-Ids der ersetzten Segmente
param[1].toAdd[i]                  = { fileName, params, transf, name, playerEntity }
param[2].costs                     = Preis, param[2].errorState{critical, messages, warnings}
```

Beispiele aus Lauf 5: Straße = 2 Segmente, 3 Knoten, 7.379; Gleis = 2 Segmente mit `type = 1`, 4.273; Bushaltestelle = `edgeObjectsToAdd` mit 2 Einträgen, ersetzt Segment −37903 durch 48725, 30.000; Bahnhof = `toAdd[1].fileName = "::/stations/rail/modular_station/modular_station.con"`, 24 Gleissegmente, 25 Knoten, 194.507.

## Wiederaufbau (Probe v6)

`mp_probe/build.lua` schreibt einen Spielerbau in eine Textzeile und baut ihn daraus wieder auf.

- Format: `B1 n-1;x,y,z … s-1;typ;knoten0;knoten1;t0x,t0y,t0z;t1x,t1y,t1z;typeIndex`. Entity-Ids des Spiels kommen nicht vor, neue Knoten und Segmente heißen −1, −2, … Eine Straße aus Lauf 5 passt in unter 400 Zeichen.
- Knoten, an die der Spieler angebaut hat, gehören nicht zu `addedNodes`; solche Zeilen zählt `foreign_nodes` und v6 speichert sie nicht für den Wiederaufbau. Das löst erst Phase 2 (Knoten über Positionen statt Ids).
- TF3 hat `api.type.Proposal.new`, `api.type.StreetProposal.new`, `api.type.SegmentAndEntity.new`, `api.type.NodeAndEntity.new` und `api.type.Context.new`. Das ist dasselbe Muster wie TF2, wo `SimpleProposal` hieß, was in TF3 `Proposal` heißt.
- Unbekannt ist, wie `api.cmd.makeWorldBuildProposalCmd` aufgerufen wird und ob der Eingabe-Vorschlag `streetProposal.edgesToAdd` oder `addedSegments` erwartet. v6 probiert beide Layouts und fünf Signaturen durch und schreibt ins Log, welche Variante angenommen wurde.
- Auslöser für den Test: Sobald die DLL `TF3MP_IN` auf einen Wert mit `replay` setzt, baut der Mod den letzten aufgezeichneten Bau erneut. Damit lässt sich der Kern von Phase 1 auf einem einzelnen PC prüfen.

## Ergebnis Lauf 6 (06.10.2026, Probe v6 + DLL v5)

Logs: [logs/probe-log-6-mp_probe.txt](../logs/probe-log-6-mp_probe.txt), [logs/probe-log-6-context.txt](../logs/probe-log-6-context.txt), [logs/proxy-log-6.txt](../logs/proxy-log-6.txt)

- Kein Hängen mehr. Jeder Dump dauert jetzt 0,00–0,03 s (`dump of onPostBuildProposal player #1 took 0.02 s`).
- **Aufzeichnung funktioniert.** Zwei Spielerbauten, beide ohne fremde Knoten:
  - `player #1` (Gleis, `type 1`): `B1 n-1;-2913.082,-3802.594,2.358 n-2;-2823.126,-3804.284,1.679 n-3;-2733.171,-3805.975,1 s-1;1;-1;-2;89.955,-1.69,-0.679;89.955,-1.69,-0.679;-1 s-2;1;-2;-3;89.955,-1.69,-0.679;89.955,-1.69,-0.679;-1` (198 Zeichen)
  - `player #2` (Straße, `type 0`): `B1 n-1;-2921.463,-3716.057,1.817 n-2;-2833.287,-3716.686,1.516 n-3;-2745.111,-3717.314,0.884 s-1;0;-1;-2;88.176,-0.629,-0.302;88.176,-0.629,-0.467;-1 s-2;0;-2;-3;88.176,-0.629,-0.467;88.176,-0.629,-0.631;-1` (206 Zeichen)
- **Die DLL hat den Wiederaufbau angefordert:** `the mod stored a build for replay` (14:29:03), 2 s später `TF3MP_IN=replay 319`. Der Mod hat das beim nächsten Tick gelesen (`bridge in TF3MP_IN=replay 319`). Nur der erste Bau (Gleis) wurde angefordert, für den zweiten kam kein `replay` mehr.
- **Der Wiederaufbau ist fehlgeschlagen**, und zwar schon beim Zusammenbauen des Vorschlags. Keine der fünf Signaturen von `makeWorldBuildProposalCmd` wurde überhaupt aufgerufen. Im Spiel entstand keine zweite Straße (vom Nutzer bestätigt). Vollständige Fehlerzeile (der Logger kürzt sie am Ende):

```
replay: failed,
  streetProposal: build.lua:122: no streetProposal field ||
  added: build.lua:131: attempt to get length of local 'node_list' (a nil va…
```

Bedeutung: Ein frisches `api.type.Proposal.new()` hat in TF3 weder `streetProposal` noch `addedNodes`/`addedSegments`. Der Vorschlag, den `onPostBuildProposal` meldet, ist also kein `Proposal`. Die api.type-Liste aus diesem Lauf enthält passende Kandidaten:

- `api.type.WorldBuildProposal.new` – passt vom Namen her zu `makeWorldBuildProposalCmd`, vermutlich der Typ von `param[1]` (Felder `proposal`, `toAdd`, `toRemove`).
- `api.type.StreetProposal.new` (mit `StreetProposal.EdgeObject`) – vermutlich der Typ von `param[1].proposal` mit `addedNodes`/`addedSegments`/`edgeObjectsToAdd`.
- `api.type.SimpleProposal.new`, `api.type.SimpleStreetProposal.new`, `api.type.ProposalData.new`.
- `api.type.Vector_NodeAndEntity.new`, `api.type.Vector_SegmentAndEntity.new` – die Listen sind wohl C++-Vektoren, keine Lua-Tabellen. Anhängen also eher über deren Methoden als über `list[#list + 1]`.

Nächster Schritt für Probe v7: `WorldBuildProposal.new()` bzw. `StreetProposal.new()` anlegen, die vorhandenen Felder und Methoden ins Log schreiben und die Listen über die Vector-Typen befüllen. Danach erst die Signaturen von `makeWorldBuildProposalCmd` durchprobieren.

## Probe v7 + DLL v6 (Antwort auf Lauf 6)

- `build.lua` probiert jetzt die drei Typen, die TF3 wirklich hat, in dieser Reihenfolge: `SimpleProposal` (TF2-Muster mit `streetProposal.nodesToAdd`/`edgesToAdd`), `WorldBuildProposal` (`proposal.addedNodes`/`addedSegments`, passt zum Namen von `makeWorldBuildProposalCmd`) und `StreetProposal`.
- Listen werden über `build.append` befüllt: erst `list[#list + 1]`, dann `push_back`, `add`, `append`, falls es C++-Vektoren sind.
- Jeder Fehlversuch steht in einer eigenen Logzeile (`replay attempt ...`), damit das Spiel-Log nichts mehr abschneidet.
- Vor dem ersten Wiederaufbau beschreibt der Mod frische Instanzen von `SimpleProposal`, `WorldBuildProposal`, `StreetProposal`, `Vector_NodeAndEntity` und `Vector_SegmentAndEntity` (`---- type ...`), damit die echten Felder im Log stehen.
- Die Kopie entsteht 40 m neben dem Original (rechtwinklig zum ersten Segment), damit man sie sieht.
- Schutz gegen eine Endlosschleife: höchstens 3 Wiederaufbauten pro Sitzung, und ein Bau, der innerhalb von 50 Updates nach einem Wiederaufbau kommt (die Kopie selbst), wird nicht aufgezeichnet.
- Jeder Spielerbau wird aufgezeichnet, auch wenn sein Dump wegen `BUILD_DUMPS` entfällt.
- DLL v6 fordert für jede neue Aufzeichnung einen Wiederaufbau an, nicht nur für die erste.

## Ergebnis Lauf 7 (06.10.2026, Probe v7 + DLL v6)

Logs: [logs/probe-log-7-mp_probe.txt](../logs/probe-log-7-mp_probe.txt), [logs/probe-log-7-context.txt](../logs/probe-log-7-context.txt), [logs/proxy-log-7.txt](../logs/proxy-log-7.txt)

Der Nutzer hat zwei Straßen und zwei Gleise auf freier Fläche gebaut. Kein Hängen, **aber im Spiel entstand keine Kopie.**

- Aufzeichnung: 4 Spielerbauten, alle mit `foreign_nodes=0` (Straße 4 Knoten/3 Segmente, Gleis 3/2, Straße 4/3, Straße 3/2). Dumps 0,02–0,03 s.
- DLL v6: hat für jede Aufzeichnung `TF3MP_IN=replay N` gesetzt (316, 329, 335, 354), jeweils 1–2 s nach `capture stored`.
- Mod: jedes Mal `replay: ok, SimpleProposal: sent with signature 1`, also hat `api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(SimpleProposal, Context, true))` keinen Lua-Fehler ausgelöst. Es gibt keine `replay attempt`-Zeilen, weil schon der erste Versuch durchlief.
- Trotzdem gab es danach **kein** `onPostBuildProposal`, auch kein `capture skipped`, und keine Warnung oder Fehlermeldung des Spiels. Der Befehl wurde angenommen und still verworfen, oder er wurde nie ausgeführt.

Beschreibung frischer Instanzen (`---- type`):

```
SimpleProposal.streetProposal.{edgesToAdd, edgesToRemove, nodesToAdd, nodesToRemove,
                               edgeObjectsToAdd, edgeObjectsToRemove}
SimpleProposal.{constructionsToAdd, constructionsToRemove}
WorldBuildProposal.proposal.proposal.{edgeObjectsToAdd, edgeObjectsToRemove, addedSegments,
    removedSegments, addedNodes, removedNodes, new2oldSegments, old2newSegments, frozenNodes}
WorldBuildProposal.proposal.{toAdd, toRemove}
WorldBuildProposal.context.{player = -1, cleanupStreetGraph = false, gatherBuildings = false,
                            gatherFields = true, checkTerrainAlignment = false}
StreetProposal.{edgeObjectsToAdd, …, frozenNodes}   (wie WorldBuildProposal.proposal.proposal)
Vector_NodeAndEntity, Vector_SegmentAndEntity = userdata ohne sichtbare Felder
```

Alle Listen sind Lua-Tabellen (`table (#0)`), keine Vektoren.

**Zweiter Befund: Der Mod läuft in mehreren Lua-Zuständen.** Bau-Events kommen im Thread „Simulation Thread“, die Bridge-Ticks dagegen in wechselnden „Sim Pool N“-Threads. Modul-Variablen (`main.pending_replay`, Replay-Zähler, „Typen schon beschrieben“) sind deshalb nicht geteilt:

- Die `---- type`-Beschreibung kam bei jedem Nachbau neu.
- Drei Nachbauten hießen `replay #1`, und alle drei bauten den **ersten** Bau (4 Knoten/3 Segmente) nach, auch nach dem Gleis (3/2). Erst der vierte (`replay #2`, Sim Pool 2) nahm den letzten Bau.
- Was zwischen den Zuständen ankommt, ist offenbar nur `state:get()/set()`, und das auch nur mit Verzögerung.

Folgerungen für Probe v8:
1. `sendCommand` mit Rückruf aufrufen (`api.cmd.sendCommand(cmd, function(res, success) … end)`) und `success` sowie `res.resultProposalData.errorState`/`costs` loggen. Erst dann wissen wir, ob und warum das Spiel den Befehl verwirft.
2. `context.player` auf die Spieler-Entity setzen (aus Lauf 5: 29125, besser aus `param[1].toAdd[i].playerEntity` bzw. dem Event lesen); der Standardwert ist −1 (kein Besitzer).
3. Auch `WorldBuildProposal` als eigenen Versuch senden, nicht nur als Rückfall, falls `SimpleProposal` ohne Fehler angenommen wird.
4. Prüfen, ob `sendCommand` aus einem „Sim Pool“-Thread überhaupt wirkt. Notfalls den Nachbau im Event-Handler (Simulation Thread) auslösen, etwa über ein Event per `makeScriptingSendEventCmd`.
5. Gemeinsamen Zustand (letzte Aufzeichnung, Zähler, Ruhezeit) nur über `state` führen, nicht über Modul-Variablen.

## Probe v8 (Antwort auf Lauf 7)

**Wahrscheinliche Hauptursache, warum keine Kopie entstand:** Der nachgebaute Vorschlag hatte keinen Straßen- oder Gleistyp. Im Roh-Dump aus Lauf 5 (`logs/probe-log-5-mp_probe.txt`, ab Zeile 2560) steht, wo TF3 ihn speichert: nicht wie in TF2 als `streetEdge.streetType` bzw. `trackEdge.trackType`, sondern direkt im Segment:

```
comp.roadTemplate = "::/infrastructure/street/town/town_old_small.street_template"   (Straße)
comp.roadStyle    = "::/infrastructure/street/town/town_old.street"
comp.roadType     = 1    (Straße; Gleis = 0, Template "::/infrastructure/track/simple/simple.street_template")
comp.distance     = 0    (Gleis: 5)
comp.laneConfigs, comp.position0/position1, playerOwned.player = 29125, params.precedenceNode0/1 = 2
```

Straßen und Gleise sind in TF3 also derselbe Segmenttyp; nur das Template unterscheidet sie.

Änderungen in v8:

- **Format B2:** Jedes Segment trägt `roadType`, `distance` und einen Verweis auf ein `t`-Token mit `roadTemplate;roadStyle`. Jedes Template steht nur einmal in der Zeile. Beispiel: `B2 n-1;x,y,z … t1;<template>;<style> s-1;0;-1;-2;t0;t1;-1;1;0;1`.
- Beim Nachbau werden `roadTemplate`, `roadStyle`, `roadType`, `distance`, `position0/1` und `playerOwned` (aktueller Spieler) gesetzt. Der Kontext bekommt `player`, `cleanupStreetGraph`, `gatherBuildings`, `gatherFields` und `checkTerrainAlignment = true`.
- `sendCommand` bekommt einen Rückruf. `replay result (...): success=...` und die Felder des Ergebnisses (`resultProposalData`, `errorState`, `costs`, `resultEntities`) stehen danach im Log, so dass ein still verworfener Befehl jetzt einen Grund hat.
- **Lua-Zustände:** Der Nachbau läuft jetzt in `handleEvent` (Simulation Thread), wo auch die Aufzeichnung liegt. `update` leitet die Anforderung der DLL nur als Skript-Event `mp_probe_replay` weiter (`makeScriptingSendEventCmd`, drei Signaturen). Klappt kein Event, baut `update` die Zeile aus dem Spielstand-Zustand nach (`last_build`). Welche Anforderung schon erledigt ist, steht im Spielstand-Zustand (`last_replay_request`), damit der nächste Sim-Pool-Zustand sie nicht noch einmal ausführt.
- Die Ruhezeit nach einem Nachbau läuft über die Spielzeit (10 s), nicht mehr über einen Update-Zähler.

## Ergebnis Lauf 8 (06.10.2026, Probe v8 + DLL v6)

Logs: [logs/probe-log-8-mp_probe.txt](../logs/probe-log-8-mp_probe.txt), [logs/probe-log-8-context.txt](../logs/probe-log-8-context.txt), [logs/proxy-log-8.txt](../logs/proxy-log-8.txt)

Der Nutzer hat eine Straße und ein Gleis gebaut. Keine Kopie, kein Hängen. **Der Nachbau wurde diesmal gar nicht versucht.**

- Aufzeichnung im Format B2 klappt, mit Vorlage:
  - Straße: `t1;::/infrastructure/street/town/town_old_small.street_template;::/infrastructure/street/town/town_old.street`, Segmente `…;-1;1;0;1`
  - Gleis: `t1;::/infrastructure/track/simple/simple.street_template;::/infrastructure/track/simple/simple.street`, Segmente `…;-1;0;5;1`
- Skript-Event funktioniert: Der Bridge-Tick (Sim Pool 2 bzw. 10) meldet `replay requested as script event (signature 1)`, und in derselben Sekunde kommt im Simulation Thread `replay event received (src=mp_probe id=mp_probe_replay)` an.
- Dort aber jedes Mal: `replay: nothing captured yet`. `main.pending_replay`, gesetzt in `capture_build` im Simulation Thread, ist beim Replay-Event (ebenfalls Simulation Thread, 3–4 s später) wieder `nil`. Auch der Zustand des Event-Handlers hält also keine Modul-Variablen zwischen zwei Events, oder das Replay-Event läuft in einem anderen Lua-Zustand als das Bau-Event, obwohl der Thread-Name gleich ist.
- Damit gab es keinen `replay #`-, `replay attempt`- oder `replay result`-Eintrag. Die Frage, ob die Vorlage das stille Verwerfen behebt, ist noch offen.
- Spiel-Warnungen rund um den Nachbau: keine.

Folgerung für Probe v9: Modul-Variablen gar nicht mehr für Daten zwischen Aufrufen verwenden. Der Replay-Zweig in `handleEvent` soll die Zeile aus `state:get().last_build` lesen und einen Marker wie `s.replayed_line` bzw. einen Zähler in `state` setzen, damit dieselbe Zeile nicht doppelt gebaut wird. Dasselbe gilt für `replays_done` und `quiet_until`. Achtung: `update` ruft bei jedem Update `state:set(s)` mit seiner eigenen Kopie auf. Kennt diese Kopie `last_build` noch nicht, könnte sie den Wert aus dem Event-Zustand wieder überschreiben. Daher in `update` nur die eigenen Felder ändern, oder die Replay-Daten in einem eigenen Feld führen, das nur der Event-Zustand schreibt.

## Probe v9 (Antwort auf Lauf 8)

- Keine Modul-Variablen mehr für Daten zwischen zwei Aufrufen. Lauf 8 zeigt, dass sie auch zwischen zwei `handleEvent`-Aufrufen im Simulation Thread verloren gehen.
- Die Aufzeichnung steht nur im Skript-Zustand (`s.last_build`). `update` liest sie beim Replay-Wunsch der DLL von dort und schickt sie **im Parameter des Skript-Events** mit (`{line, request, number}`). `handleEvent` baut direkt aus `param.line` nach. Kommt der Parameter nicht an, nimmt es `last_build` aus dem Skript-Zustand.
- Zähler (`replays_requested`, höchstens 3) und erledigte Anforderung (`last_replay_request`) führt `update` im Skript-Zustand. Die Ruhezeit für das Bau-Event der Kopie (`quiet_until`) schreibt der Nachbau in den Skript-Zustand.
- Die Offline-Tests laden das Skript jetzt für jeden Aufruf neu, wie es das Spiel offenbar tut. Damit wäre der Fehler aus Lauf 8 schon offline aufgefallen.

## Ergebnis Lauf 9 (06.10.2026, Probe v9 + DLL v6)

Logs: [logs/probe-log-9-mp_probe.txt](../logs/probe-log-9-mp_probe.txt), [logs/probe-log-9-context.txt](../logs/probe-log-9-context.txt), [logs/proxy-log-9.txt](../logs/proxy-log-9.txt)

Keine Kopie im Spiel (vom Nutzer bestätigt), kein Hängen, keine Warnungen des Spiels nach Ladeende. **Aber das Spiel führt den Nachbau jetzt aus und meldet Erfolg, mit einem leeren Vorschlag.**

- Die Zeile kommt im Event-Parameter an: `replay #1 requested as script event (signature 1, 321 characters)` (Sim Pool 8), danach im Simulation Thread `replay event received (… line 321 characters)` und `replay #1: 3 nodes, 2 segments, moved by -0.5,40.0, player 31578`.
- Der Rückruf meldet `replay result (SimpleProposal): success=true`. Angenommen wurde gleich die erste Variante, `makeWorldBuildProposalCmd(SimpleProposal, Context, true)`.
- Die vollständigen Felder des Ergebnisses (bei allen drei Nachbauten gleich):

```
res.proposal.proposal.{edgeObjectsToAdd, edgeObjectsToRemove, addedSegments, removedSegments,
                       addedNodes, removedNodes, new2oldSegments, old2newSegments, frozenNodes} = table (#0)
res.proposal.{toAdd, toRemove} = table (#0)
res.context = { player = 31578, cleanupStreetGraph = true, gatherBuildings = true,
                gatherFields = true, checkTerrainAlignment = true }
res.resultProposalData.costs = 0
res.resultProposalData.errorState = { critical = false, messages = #0, warnings = #0 }
res.resultEntities = table (#0)
```

**Ursache:** Der Vorschlag kam beim Spiel leer an (`addedNodes`/`addedSegments` #0, Kosten 0, keine neuen Entities). `build.make_proposal` holt sich `p.streetProposal.nodesToAdd` bzw. `edgesToAdd` und hängt dort an (`build.append`, Variante `list[#list + 1] = item`, die keinen Fehler wirft). Diese Listen sind beim Lesen aber Lua-Kopien des C++-Vektors (`table (#0)` in der Typbeschreibung). Das Anhängen ändert nur die Kopie, und der Vorschlag selbst bleibt leer.

Folgerung für Probe v10:
1. Knoten und Segmente in normalen Lua-Tabellen sammeln und als Ganzes zuweisen: `local sp = p.streetProposal; sp.nodesToAdd = nodes; sp.edgesToAdd = edges; p.streetProposal = sp`. Das Zurückschreiben von `sp` ist nötig, falls auch `streetProposal` eine Kopie ist.
2. Vor dem Senden zurücklesen und loggen: `#p.streetProposal.nodesToAdd` / `#p.streetProposal.edgesToAdd` müssen 3/2 sein. Sonst die nächste Zuweisungsart probieren (WorldBuildProposal: `w.proposal.proposal.addedNodes = …`, danach `w.proposal.proposal = pp`, `w.proposal = wp`).
3. Erfolg erkennt man an `costs > 0` und nicht leeren `resultEntities` im Ergebnis, nicht an `success`.

Nebenbefund: Kurz nach dem Gleis kamen drei Aufzeichnungen mit je 25 Knoten und 24 Segmenten, Abstände 2 m/16 m, mit `simple.street`. Das sind vermutlich Bahnsteig-Gleise eines Bahnhofs, den der Nutzer gebaut hat (`foreign_nodes = 0`). Bahnhöfe sollten als Konstruktion übertragen werden, nicht als lose Gleise. `is_player_build` bzw. `capture` sollten Bauten mit `toAdd` deshalb ausschließen.

## Probe v10 (Antwort auf Lauf 9)

- **Listen als Ganzes zuweisen.** Knoten und Segmente werden in normalen Lua-Tabellen gesammelt und dann als Ganzes in den Vorschlag geschrieben. Jede Ebene wird zurückgeschrieben (`sp = p.streetProposal; sp.nodesToAdd = nodes; sp.edgesToAdd = edges; p.streetProposal = sp`), denn TF3 gibt beim Lesen Kopien heraus. Dasselbe gilt in den Einträgen: `comp` wird gelesen, geändert und zurückgeschrieben. Positionen und Tangenten sind neue `api.type.Vec3f`.
- **Zweite Listenart.** Nimmt der Vorschlag keine Lua-Tabelle an, versucht der Mod TF3s eigene Typen `Vector_NodeAndEntity` und `Vector_SegmentAndEntity`.
- **Prüfung vor dem Senden.** Der Vorschlag wird zurückgelesen und als `proposal check <Variante>/<Listenart>: complete|INCOMPLETE, nodes 3/3, edges 2/2, node[1] … at x,y,z, edge[1] … nodes a->b tangent0 … template … owner …` geloggt. Ein unvollständiger Vorschlag wird nicht gesendet: falsche Anzahl, Position mehr als 0,5 m daneben oder falsche Knotenverweise. Felder, die das Spiel ablehnt, stehen in `<Variante> refused fields: …`.
- **Urteil aus dem Ergebnis.** `replay result (<Variante>): BUILT|NOTHING BUILT|UNKNOWN, success=…, costs …, new entities …, critical …`, danach jede Meldung und Warnung des Spiels als eigene Zeile. Gebaut heißt: neue Entities oder Kosten über 0 (`build.outcome`), nicht `success`.
- **Nächste Variante bei „nichts gebaut“.** Lauf 9 zeigt, dass das Spiel den Rückruf noch während `sendCommand` aufruft. Meldet er nichts gebaut, versucht `build.replay` gleich danach die nächste Variante (`SimpleProposal`, `WorldBuildProposal` mit eigenem Kontext, `StreetProposal`). Es gibt keinen Befehl innerhalb des Rückrufs.
- **Bestätigung unabhängig vom Rückruf.** Jedes Bau-Event in der Ruhezeit nach einem Nachbau wird als `build right after a replay (probably the copy, not captured): segments=… nodes=… constructions=… new entities=… player build=…` geloggt.
- **Nur Straßen und Gleise.** Bauten mit Konstruktionen (`toAdd`, z. B. Bahnhöfe) werden nicht aufgezeichnet (`capture skipped: the build contains N construction(s) …`). `param[4]` (vom Spiel gesetzt, in Lauf 5–9 immer `true` bei Spielerbauten und `false` bei Stadtbauten) entscheidet, ob ein Bau vom Spieler ist. Straßen, die eine Stadt baut, werden also nicht mehr kopiert.
- Mit einer neuen Probe-Version stehen einem Spielstand wieder 3 Nachbauten zu (`replays_requested` wird einmal zurückgesetzt).
- Die Offline-Tests bilden jetzt das Kopierverhalten nach: Gelesene Strukturen und Listen sind Kopien, und unbekannte Felder werfen einen Fehler. Der Fehler aus Lauf 9 wäre damit offline aufgefallen.

## Ergebnis Lauf 10 (06.10.2026, Probe v10 + DLL v6)

Logs: [logs/probe-log-10-mp_probe.txt](../logs/probe-log-10-mp_probe.txt), [logs/probe-log-10-context.txt](../logs/probe-log-10-context.txt), [logs/proxy-log-10.txt](../logs/proxy-log-10.txt)

Keine Kopie (vom Nutzer bestätigt), kein Hängen. Erstmals verarbeitet das Spiel den Vorschlag wirklich, bricht aber in der Straßengeometrie ab.

- `replay proposal check …: complete` für alle drei Layouts, z. B. `SimpleProposal/table: complete, nodes 3/3, edges 2/2, … template town_old_small.street_template owner 29125`. Die Listen sind jetzt gefüllt.
- `SimpleProposal`, Signaturen 1, 2, 3 und 5: `makeWorldBuildProposalCmd` wirft `Unknown exception`. Direkt davor meldet das Spiel:
  - Straße: `lane_config_util.cpp:157: StreetGeometry::SidewalkIdx0: Assertion '!laneConfigs.empty()' failed`
  - Gleis: `construction_util_graph.cpp:1215: street_util::AreSegmentsOfSameType: Assertion 'be.laneConfigs.size() == 1' failed`
- Signatur 4 bei allen Layouts: `bad argument #3 to 'makeWorldBuildProposalCmd' (Context expected, got boolean)`.
- `WorldBuildProposal` und `StreetProposal`, alle anderen Signaturen: `Error decoding argument #2: The lua object can't be cast to desired type`. Der Befehl nimmt also nur `SimpleProposal` als erstes Argument; mit einem Kontext an Position 2 bleibt `(SimpleProposal, Context, bool)` als Signatur.
- Ergebnis: `replay: failed, no layout could be filled and sent` (3×), danach `replay: limit of 3 reached`. Es gibt keine `refused fields`- und keine `replay result`-Zeilen.
- Die Zeilen `build right after a replay (… constructions=1–3 … player build=false)` sind Stadtgebäude aus der Ruhezeit nach dem Nachbau, nicht die Kopie. Eine davon war ein echter Spielerbau (`segments=3 nodes=4 … player build=true`, 17:02:48), der deshalb nicht aufgezeichnet wurde.

**Ursache:** Die Segmente haben keine Fahrspur-Konfiguration (`laneConfigs` leer). Die Vorlage `roadTemplate`/`roadStyle` als Pfad reicht offenbar nicht. Das Spiel braucht den Straßen- bzw. Gleistyp so, wie TF2 ihn im Kanten-Teil setzte (`entity.streetEdge.streetType = api.res.streetTypeRep.find(...)`, bei Gleisen `trackEdge.trackType = api.res.trackTypeRep.find(...)`). Für v11 also prüfen, ob `streetEdge`/`trackEdge` und die passenden `api.res.*Rep`-Einträge vorhanden sind (siehe Liste `api.res` in Lauf 5), und sie setzen. Den `streetEdge` eines echten Spielerbaus mit `probe.fields` ausgeben, um die Feldnamen zu erfahren.

## Probe v11 (Antwort auf Lauf 10)

Zur Ursache aus Lauf 10: TF3 hat kein `streetTypeRep`/`trackTypeRep` wie TF2 (`api.res` kennt nur `streetTemplateRep` und `streetStyleRep`), und `streetEdge` enthält in TF3 nur `precedenceNode0/1`. Die Fahrspuren stehen dafür im Bau-Event jedes Spielerbaus fertig in `comp.laneConfigs`, z. B. 4 Einträge für `town_old_small` (Gehweg, zwei Fahrspuren, Gehweg) und 1 Eintrag für ein Gleis. Das Spiel leitet sie beim Nachbau nicht aus der Vorlage ab, also reisen sie in der Zeile mit.

- **Format B3.** Das `t`-Token trägt die Spuren: `t1;<template>;<style>;<spur>|<spur>|…`. Jede Spur ist `speed,width,height,forward,modes,offset`, `forward` als 1/0, `modes` als Bitmaske der `transportModes` (Schlüssel 0–15, Bit k = Modus k). Jede Kombination aus Vorlage und Spuren steht nur einmal in der Zeile. Ohne Spuren steht dort `-`. Segmente haben zwei Felder mehr: `precedenceNode0,precedenceNode1` von `params` und von `streetEdge`, jeweils `-`, wenn es keine gibt (Gleise haben keine `params`). Eine Straße aus 2 Segmenten braucht etwa 430 Zeichen.
- **Nachbau der Spuren.** Pro Spur ein `api.type.LaneConfig` mit `speed`, `width`, `height`, `forward` und `offset`. `transportModes` wird über die Kopie des Spiels gesetzt und zurückgeschrieben; danach werden frische Tabellen mit Schlüsseln ab 0 und ab 1 versucht, jeweils mit Zurücklesen. Die Liste geht als Ganzes nach `comp.laneConfigs`, notfalls als `Vector_LaneConfig`. Fehlt `params`, legt der Mod ein `api.type.BaseEdgeStreet` an.
- **Prüfung.** Die Zeile `proposal check` endet jetzt mit `lanes 4/4 lane[1] width 3 modes 3`. Fehlen die Spuren oder stimmt die erste nicht, wird nicht gesendet. Direkt vor dem Senden steht der vollständige erste Segment-Eintrag im Log (`---- replay proposal SimpleProposal/table edge[1]`), mit Spuren und Vorrang.
- **Nur noch `SimpleProposal`.** `WorldBuildProposal` und `StreetProposal` sind entfernt, weil der Befehl sie nicht entschlüsseln kann. Wirft der Befehl einen inhaltlichen Fehler (`Unknown exception`), probiert der Mod keine weiteren Signaturen mehr. Das ergibt nur eine Fehlermeldung des Spiels pro Nachbau statt vier, und die Zeile lautet `replay: failed, SimpleProposal/table: the game rejected the proposal (…)`.
- **Ruhezeit enger.** Als Kopie gilt nur ein Bau in der Ruhezeit mit genauso vielen Segmenten wie der Nachbau und ohne Konstruktionen. Stadtgebäude und andere Spielerbauten in diesen 10 Sekunden werden normal behandelt.

## Ergebnis Lauf 11 (06.10.2026, Probe v11 + DLL v6)

Logs: [logs/probe-log-11-mp_probe.txt](../logs/probe-log-11-mp_probe.txt), [logs/probe-log-11-context.txt](../logs/probe-log-11-context.txt), [logs/proxy-log-11.txt](../logs/proxy-log-11.txt)

**Der Nachbau funktioniert.** Der Nutzer hat zwei Straßen gebaut, beide wurden 40 m daneben automatisch nachgebaut („hat geklappt“). Gleise wurden in diesem Lauf nicht getestet. Kein Hängen, keine Warnungen oder Assertions des Spiels nach dem Laden.

- Aufzeichnung im Format B3 mit Fahrspuren, z. B. 4 Knoten/3 Segmente (524 Zeichen):
  `t1;::/infrastructure/street/town/town_old_small.street_template;::/infrastructure/street/town/town_old.street;11.11,3,0.15,0,3,0.15|11.11,5,0,0,28,-0.5|11.11,5,0,1,28,0.5|11.11,3,0.15,1,3,-0.15`, Segment-Ende `;-1;1;0;1;2,2;2,2`
- Ablauf: DLL `TF3MP_IN=replay 329` → Sim Pool 11 `replay #1 requested as script event (signature 1, 524 characters)` → Simulation Thread `replay event received`, `replay #1: 4 nodes, 3 segments, moved by 0.2,40.0, player 29125`.
- `refused fields: edge.params: build.lua:310: cannot write to read only member (3x); edge.params: build.lua:224: no writable member 'params' (3x)`. Das ist harmlos, `params.precedenceNode0/1 = 2` stand trotzdem richtig drin.
- `replay proposal check SimpleProposal/table: complete, nodes 4/4, edges 3/3, … owner 29125, lanes 4/4 lane[1] width 3 modes 3`
- Kante 1 im gesendeten Vorschlag: `comp.{roadTemplate, roadStyle, roadType = 1, distance = 0, position0/1, laneConfigs (#4: width/speed/forward/height/offset/transportModes(#15)), roadDevelopmentLocked = false, edgeDecorations}`, `streetEdge.precedenceNode0/1 = 2`, `playerOwned.player = 29125`.
- `replay result (SimpleProposal/table): BUILT, success=true, costs 9054, new entities 0, critical false` (zweiter Nachbau: 2 Segmente, costs 8024). `res.proposal.proposal.addedSegments` #3 mit neuen Entity-Ids 32029/32031/32032, `addedNodes` #4, `errorState.messages/warnings` leer, `resultEntities` #0 (bei Straßen normal, das gilt nur für Konstruktionen).
- `build right after a replay (probably the copy, not captured): segments=3 nodes=4 … player build=false`. Das ist die Kopie selbst; sie wurde richtig nicht erneut aufgezeichnet.

Damit ist der Kern von Phase 1 auf einem PC gezeigt: Spielerbau → Textzeile → DLL → Mod → derselbe Bau im Spiel. Gültige Form: `api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(SimpleProposal, Context, true), callback)` mit ganzen Listen in `streetProposal.nodesToAdd/edgesToAdd` und `comp.laneConfigs` aus dem Original. Offen: Gleise (B3 mit `type 1`), Anschluss an bestehende Knoten (`foreign_nodes`), Bahnhöfe/Konstruktionen.

## Netzwerk-Übertragung (Probe v12 + DLL v7)

Lauf 11 hat gezeigt, dass eine aufgezeichnete Zeile auf einem PC wieder gebaut wird. Jetzt geht die Zeile über die DLL:

1. Der Mod schreibt nach jeder aufgezeichneten Straße ohne fremde Knoten `net send <Zeile>` ins Log.
2. Die DLL liest die Zeile aus `stdout.txt` und schickt sie per UDP an das andere Spiel (`TF3MP/1 LINE <token> <Zeile>`, Wiederholung jede Sekunde bis `TF3MP/1 GOT <token>`). Bei `mode=loopback` landet sie direkt im eigenen Eingang.
3. Die DLL bietet die älteste empfangene Zeile über `TF3MP_IN=line <token> <net|loop> <Zeile>` an. Der Mod liest sie im nächsten Brücken-Tick, bestätigt mit `net received token=<token>` (bei jedem Tick, solange die DLL sie noch anbietet) und baut sie genau einmal: Der Token steht im Spielstand-Zustand. Das Token enthält die Prozess-ID der sendenden DLL, damit nach einem Neustart keine Zeile verschluckt wird.
4. Gebaut wird wie bisher im Event-Zustand (Script-Event `mp_probe_replay`), `net` an derselben Stelle, `loop` 40 m daneben.

Kein Echo: Ein nachgebauter Bau kommt mit `isPlayerBuild=false` an (Lauf 11) und wird nicht aufgezeichnet. Der alte DLL-Auslöser `replay <seq>` entfällt; der Mod versteht ihn weiterhin.

Noch offen: Gleise, Straßen mit Anschluss an bestehende Knoten (Knoten-IDs unterscheiden sich zwischen den Spielen, Suche über die Position nötig), Bahnhöfe. Der Mitspieler bezahlt die nachgebaute Straße bisher selbst.

## Ergebnis Lauf 12 (06.10.2026, Probe v12 + DLL v7, Loopback über den Launcher)

Logs: [logs/probe-log-12-mp_probe.txt](../logs/probe-log-12-mp_probe.txt), [logs/probe-log-12-context.txt](../logs/probe-log-12-context.txt), [logs/proxy-log-12.txt](../logs/proxy-log-12.txt)

Der Nutzer hat mit `Start.bat` → „Allein testen“ installiert (`alut_proxy.ini`: `[net] mode=loopback port=47800`). Er hat eine Straße und ein Gleis gebaut, **beide Kopien sind erschienen.** Kein Hängen, keine Warnungen des Spiels außer den üblichen beim Laden.

- Straße: `capture stored` 17:46:04 → `net send B3 …` → DLL `net: line 40024.1 (423 characters) queued for this game (loopback)` → `TF3MP_IN=line 40024.1 loop …` → Mod `net received token=40024.1 kind=loop (423 characters)` 17:46:08 → `replay #40024.1: 3 nodes, 2 segments, moved by -3.6,39.8` → `BUILT, success=true, costs 5531`.
- Gleis (erstmals): Spur-Teil `27.777,4,0.53,1,16512,0`, `replay #40024.2: 2 nodes, 1 segments` → `BUILT, costs 1983`.
- Vom Bau bis zur Kopie vergehen etwa 3–4 s, also ein bis zwei Bridge-Ticks.
- Auffällig: Die DLL setzt `TF3MP_IN=line …` zweimal, bevor sie `the mod has line …` sieht. Gebaut wurde aber nur einmal, die Erkennung doppelter Zeilen über das Token wirkt.

## Ergebnis Lauf 12 bestätigt, Plan für Probe v13 (Schritt 1: Anschlüsse und Gebäude)

Der Nutzer will vor dem Test mit dem zweiten PC alles übertragen: Anschlüsse an bestehende Straßen, Gebäude, Abriss, Linien, Fahrzeuge, Geld/Datum/Tempo. Referenz, wie die TF2-Mod das löst: `docs/tf2mp-reference.md` (aus github.com/silver2127/tpf2-multiplayer, MIT).

Geplantes Zeilenformat B4 (Felder mit `;`, Text mit %-Kodierung für Leerzeichen, `;`, `|`, `%`):

- `n-<i>;x,y,z` neuer Knoten, `f<k>;x,y,z` bestehender Knoten (Empfänger sucht ihn im Umkreis 1,5 m, nur waagerecht)
- `s…` wie B3, Knoten auch als `f<k>`; 13. Feld: Kantenobjekte `o<k>/<side>|…` oder `-`
- `o<k>;<segment>;param;left;oneWay;model;name` neue Haltestelle/Signal
- `r;x,y,z;x,y,z;type` entfernte Kante (Empfänger sucht die Kante zwischen den beiden Knoten; fehlt eine, wird der ganze Bau übersprungen)
- `x;x,y,z` entfernter Knoten
- `c;file;name;t1,…,t16;params` neues Gebäude über `SimpleProposal.ConstructionEntity` (params als Lua-Literal, eigener Parser statt `load`)
- `d;file;x,y,z` abgerissenes Gebäude (Empfänger: gleiche Datei im Umkreis 2 m). Da `onPostBuildProposal` erst nach dem Abriss kommt, merkt sich der Mod Datei und Position aller Spieler-Gebäude im Skript-Zustand.

Bei Bauten mit Gebäude fallen Kanten weg, die einen eingefrorenen Knoten berühren (`frozenNodes` sind 0-basierte Indizes in `addedNodes`, Lauf 5); die erzeugt das Gebäude selbst. Bestehende Haltestellen auf einer geänderten Kante werden in v13 noch nicht unterstützt (Bau wird mit Hinweis übersprungen).

Allein-Test: `loop`-Zeilen werden immer um (0, 40 m) verschoben statt quer zur ersten Kante, damit Anschlüsse und Abriss die 40 m versetzte Kopie treffen. Testablauf: erst eine freie Straße A bauen (Kopie A'), dann an A anschließen, Haltestelle, Depot, Bahnhof an A, zum Schluss etwas abreißen.

### Probe v13 umgesetzt

- `build.lua`: Format B4 (`f`, `r`, `x`, `c`, `d` wie oben), `build.resolve` sucht Bestehendes über einen Finder, `build.make_construction` (Mat4f aus vier Vec4f, sonst Liste mit 16 Zahlen, jeweils zurückgelesen), `build.params_to_string`/`params_from_string` (eigener Parser).
- `world.lua`: Knoten-Raster (16 m Zellen) über `forEachEntityWithComponent(BASE_NODE)`, Kante zwischen zwei Knoten (`streetSystem.getNodeSegments`, sonst alle Kanten), Gebäude gleicher Datei im Umkreis 2 m, Spieler-Gebäude-Liste.
- `main.script.lua`: Gebäude werden nicht mehr übersprungen; Haltestellen/Signale werden noch weggelassen und im Log genannt. Allein-Test verschiebt immer um (0, +40 m). Bei Abriss-Ereignissen merkt sich der Mod Gebäude im Skript-Zustand (einmaliger Scan pro Spielstand, danach aus den Bau-Ereignissen).
- Bisher unbekannt und deshalb im Log: wie TF3 `transf` lesen und setzen lässt, ob ein Abriss als `onPostBuildProposal` mit `isPlayerBuild=true` kommt, welche Felder Kantenobjekte haben (die Dumps zeigen jetzt `edgeEntity`, `param`, `left`, `oneWay`, `model`).
## ChatGPT-Erweiterung: zusätzliche Aktionen (06.10.2026, in Probe v14 übernommen)

Aufbauend auf v12 wurde Code für vollständige Konstruktionen (Bahnhöfe/Depots und Änderungen), reinen Abriss, Linien und Fahrzeuge ergänzt. Neue A1-Daten nutzen die vorhandene DLL v7. 53 bestehende und 35 neue Offline-Tests sind erfolgreich; die neuen Aktionen sind noch nicht im echten Spiel bestätigt. Details, Grenzen und Übergabe an Claude: [phase2-actions.md](phase2-actions.md). Der Benutzer hat den Zwei-PC-Test ausdrücklich nach diese Erweiterungen eingeordnet.

### Probe v14: beides zusammengeführt

- Straßen, Gleise, Gebäude und Abriss kommen weiter als B4-Zeile aus dem Bau-Ereignis (`build.lua`, `world.lua`).
- Aus `actions.lua` (ChatGPT) werden nur Linien und Fahrzeuge abgefragt (`main.ACTION_KINDS = { "line", "vehicle" }`), damit Gebäude und Kanten nicht doppelt kopiert werden.
- Der Allein-Test verschiebt bei beiden um (0, +40 m); `edge_loop_offsets` entfällt, `actions.resolve` nutzt dann genau diesen Versatz.
- Tests: 56 (`run_tests.lua`) und 35 (`run_actions.lua`), unter Lua 5.4 und 5.2.

### Lauf 13 (v13): freie Straßen ja, angeschlossene nein

- Logs: `logs/run13-stdout.txt`, `logs/run13-alut_proxy.log`. Zwei freie Straßen wurden kopiert (Kosten 8027 und 9440).
- Zwei an eine bestehende Straße angeschlossene Straßen wurden richtig aufgezeichnet (`foreign_nodes=1`, `f1;…`), der Nachbau brach aber ab: `replay: lookup failed (world.lua:28: Cannot loop over this component type`. TF3 lässt `forEachEntityWithComponent(BASE_NODE)` nicht zu (`CONSTRUCTION` geht, 4 Spieler-Gebäude gefunden).
- Fix in v14: `world.lua` holt Knoten und Kanten aus `streetSystem.getNode2SegmentMap()`, sonst `forEachEntityWithComponent`, sonst `getEntitiesWithComponent`, jeweils mit `pcall`.

### Lauf 14 (v14): Anschlüsse und Bahnhöfe gehen

- Logs: `logs/run14-*`. Freie Straße, Anschluss am Ende, Anschluss in der Mitte (zweiter Versuch) und zwei modulare Bahnhöfe (`c;…modular_station.con`, Kosten 190903/189669) wurden kopiert. Depot und Abriss kommen im Log nicht vor (kein Bau-Ereignis).
- Erster Mitte-Anschluss: `removed segment -50806 has no node positions`; ein Endknoten war schon weg. Fix v15: `comp.position0/1` des entfernten Segments.
- Jede Bahnhofskopie hielt das Spiel ~23 s an: der Dump des Ergebnisses. Fix v15: `main.DUMP_REPLAY_RESULTS = false`.
- Ein echter Spielerbau mit gleicher Segmentzahl kurz nach einer Kopie wurde für die Kopie gehalten. Fix v15: nur Bauten mit `isPlayerBuild=false` gelten als Kopie.
- `actions.lua`: `api.type.Mat4f.cols` fehlt in TF3, und nicht jedes userdata hat `asTable`. Fix v15: `build.read_transf` und eigenes `to_plain`.
- Haltestellen auf Straßen: Bau-Ereignis entfernt die Kante und legt sie mit `comp.objects` neu an; `edgeObjectsToAdd[i]` hat `name`, `playerEntity`. Noch nicht übertragen.

### Probe v15: Haltestellen und Signale

Token `o;<segment>;<side>;<param>;x,y,z;<model>;<name>;<flags>` hinter dem Segment, auf dem das Objekt sitzt (flags: `n` neu, `l` links, `w` Einbahn, sonst `-`).
- Sender: Objekte aus `comp.objects` der neuen Segmente. Was schon auf einem entfernten Segment lag, gilt als bestehend; der Rest ist neu. Daten aus der Komponente `EDGE_OBJECT` (`param`, `transf`, `edgeObjectConstruction`), sonst `modelRep.getName(modelInstance.modelId)` aus `edgeObjectsToAdd`, dazu `left`/`name`.
- Empfänger: Objekte auf seinen entfernten Kanten werden über die Position (3 m) zugeordnet und mit ihrer Id in `comp.objects` übernommen. Nicht zugeordnete eigene Objekte kommen in `edgeObjectsToRemove` (der andere Spieler hat sie entfernt), nicht gefundene gesendete kommen in `edgeObjectsToAdd`.
- Nummerierung neuer Objekte in `comp.objects` ist nicht dokumentiert: `build.replay` versucht erst einen eigenen Zähler (-1, -2, …, wie die TF2-Mod), dann hinter Segmenten und Knoten.
- Das erste Objekt pro Version wird vollständig geloggt (`stop/signal … read: …`).

### Lauf 15 (v15) und Probe v16

- Logs: `logs/run15-*`. Kopiert: Straße B, Gleis, Depots (`c;…`, Kosten ~91000), ein Abriss eines Straßenstücks.
- Haltestellen und Signal abgelehnt: `street_util::EdgeObjectEntityToIndex: Assertion 'entity.GetId() <= -400000000 && entity.GetId() > -500000000'`. Neue Kantenobjekte haben einen eigenen Id-Bereich. v16 nummeriert ab -400000000 (sonst ab -400000001). Beim Signal kam `map_util.h:22: Get` (vermutlich dieselbe Ursache).
- Gelesene Daten: `edgeObjectConstruction` ist eine `.con` (`::/stations/street/small_stops/small_old.con`, `::/infrastructure/signal/signal_path_a.con`), Seite 1 für Haltestellen, 2 für Signale.
- Depot-Abriss: das Zufahrtsstück des Depots stand zusätzlich in `removedSegments` und wurde doppelt entfernt (`StreetProposal::RemoveSegment` Assertion), bzw. in der Kopie nicht gefunden. v16: Segmente, die zu einem abgerissenen Gebäude gehören (`streetConnectorSystem.getConstructionEntityForEdge`), oder die dabei nicht gefunden werden, überlässt der Mod dem Spiel; doppelte Segmente/Knoten werden nur einmal genannt.
- `actions.lua`: `LoadConfig` hat kein `asTable`; v16 liest bekannte Felder.

### Lauf 16 (v16) und Probe v17

- Logs: `logs/run16-*`. Kopiert: Straße, zwei Haltestellen, Abriss einer Haltestelle, Gleis, Signal (Objekt-Ids ab -400000000 funktionieren, Nummerierung `range0`).
- Depot: Kopie gebaut, aber nicht an die Straße angeschlossen. Das Zufahrtsstück hat genau einen eingefrorenen Knoten und wurde als Teil des Gebäudes weggelassen. v17: solche Segmente gehen in einer zweiten Zeile hinterher (alle Knoten über die Position), damit sie gebaut werden, wenn das Gebäude steht.
- Depot-Abriss der Kopie: `ProposalStreetGraph.cpp:152 GetBaseNodeConfig: Assertion '!ContainsEntity(m_proposal->removedNodes, entity)'`. v17 lässt die Endknoten eines nicht gefundenen Zufahrtsstücks stehen.
- Ein Straßenabriss mit Knoten: `map_util.h:22 Get`. v17 versucht einen abgelehnten Abriss noch einmal ohne `nodesToRemove` (die Straßengraph-Bereinigung räumt lose Knoten selbst ab).
- Abriss eines Stadtgebäudes ließ die ganze Aufzeichnung scheitern; v17 lässt es mit Hinweis weg.
- `actions.lua`: Busse an einem alten Depot gekauft (`vehicle_create`), im Allein-Test ohne Kopie des Depots erwartungsgemäß `construction reference not found`. `Invalid entity` beim Linien-Abbild: v17 behält für unlesbare Einträge das alte Abbild statt abzubrechen.

### Lauf 17 (v17) und Probe v18

- Logs: `logs/run17-*`. Kopiert: Straße, zwei Haltestellen, Linie und Bus (Linie zuweisen kam als `vehicle_update` an), Depot-Abriss, Straßenabriss. Keine Assertions.
- Depot: das Zufahrtsstück kam als eigene Zeile, das Spiel lehnte es ab („Bau nicht möglich“, Knoten 50968→49688, Vorlage `entrance_new.street_template`). v18 schickt es in derselben Zeile wie das Gebäude (Token `a;<segment>`), der eingefrorene Knoten ist ein neuer Knoten des Vorschlags. Lehnt das Spiel das Paar ab, baut der Mod das Gebäude ohne Zufahrt (`build.drop_access`).
- `vehicle_create` meldete einen Fehler als Tabelle; v18 schreibt deren Felder ins Log.
- Allein-Test: Kopie jetzt 100 m nördlich (Wunsch des Nutzers).

### Lauf 18 (v18) und Probe v19

- Logs: `logs/run18-*`, Bild der Depot-Kopie `logs/run18-depot-copy.png`. Depot mit Zufahrt im selben Vorschlag gebaut (Kosten 94891), aber die Kopie zeigt zwei Sackgassen-Wendeschleifen zwischen Straße und Tor.
- Deutung: Das Segment mit einem eingefrorenen Ende (Vorlage `entrance_new.street_template`) ist die eigene Zufahrt des Gebäudes. Das Bauwerkzeug schweißt ihr freies Ende an die Straße. Ein Skript-Vorschlag schweißt nicht (wie in TF2, siehe `docs/tf2mp-reference.md`, `MergeTemplateStreet`), und unsere zweite Zufahrt lag doppelt daneben.
- v19: Zuerst eine Zeile nur mit dem Gebäude (`opts.part = "constructions"`), dann eine Zeile mit den Straßen (`"streets"`), in der der Teilungsknoten der Straße das freie Ende der Gebäudezufahrt ist (`f`-Knoten über die Position). So wird die Straße am Knoten des Gebäudes geteilt.
- Bus im neuen Depot: `{1={cargoTypeId=-1, loadConfigIndex=0}}` abgelehnt. v19 baut `api.type.LoadConfig`-Einträge.

### Lauf 19 (v19) und Probe v20

- Logs: `logs/run19-*`. Das Depot allein wurde gebaut, die Straßenzeile übersprungen (`joins a road or track that does not exist here (node near -2848.9,-3885.8)`). Das Gebäude legt also keinen Knoten an der Straße an; der Bus erschien im kopierten Depot (`vehicle_create` mit `LoadConfig` geht).
- Vorschlag des Bauwerkzeugs für das Depot (Dump im Log): `addedNodes = {49777 Teilungsknoten, 39539 Tor}`, `proposal.frozenNodes = {1}` und `toAdd[1].frozenNodes = {1}` (0-basiert, also das Tor), Zufahrt 49944 von 49777 zum Tor mit Vorlage `entrance_new.street_template`, dazu die zwei Straßenhälften. Die Zufahrt baut das Werkzeug, nicht das Gebäude; das Gebäude übernimmt nur den Torknoten. Ein `SimpleProposal` hat dafür kein Feld.
- Linien: eine Linie über Straßenhaltestellen war unlesbar (`1 unreadable` bei jeder Abfrage), weil eine Straßenhaltestelle kein Gebäude hat. `SetLine` mit -1 für einen Bus ohne Linie gab `Unknown exception`.

Probe v20:
- Depot wieder in einer Zeile wie v18, die Zufahrt mit `a;<segment>` und ihr Torknoten mit `g;<knoten>`. Nach dem Bau prüft `weld.lua`, ob am Torknoten des Gebäudes (`CONSTRUCTION.frozenNodes`, sonst `streetConnectorSystem.getNode2StreetConnectorMap`) eine Straße von außen hängt, und loggt die Knoten an derselben Stelle (`weld check after build: …`).
- Ist das Tor nicht angeschweißt, versucht der Mod nacheinander: `api.engine.util.proposal.refreshConstruction(gebäude)` senden (der eigene Vorschlag der Engine), dann das Gebäude per `SimpleProposal` mit `old2new` durch sich selbst ersetzen. Nach jedem Schritt wird geprüft; am Ende steht `weld result …: WELDED/NOT WELDED (after …)`, einige Sekunden später noch einmal `weld check later: …`.
- Zur Diagnose: Beim Bauen des Originals wird geprüft, ob es angeschweißt ist (muss `WELDED` sein), und der Refresh-Vorschlag der Engine für das Original beschrieben und gedumpt, ohne ihn zu senden. Vor dem Senden der Kopie wird beschrieben, was das Spiel aus dem `SimpleProposal` gemacht hat (`weld command before sending: …`).
- Linien: Straßenhaltestellen reisen über ihre Position (`street_station`, aus `EDGE_OBJECT.transf`, sonst dem Einzugsgebiet) und werden beim Empfänger der nächsten Haltestelle innerhalb 3 m zugeordnet. Unlesbare Einträge werden nur noch gemeldet, wenn sich Anzahl oder Fehler ändern, mit dem ersten Fehlertext. Kein `SetLine(-1)` mehr nach einem Kauf ohne Linie.

### Gleiche-Stelle-Test (Launcher, ab v20)

Im Allein-Test steht die Kopie 100 m daneben, auf anderem Gelände. Der Gleiche-Stelle-Test baut an genau derselben Stelle nach, wie es der Mitspieler mit demselben Spielstand bekommt:
1. Im Launcher „Gleiche Stelle testen“ wählen und installieren. Die DLL läuft als Gastgeber ohne Partner (`mode=host`, dazu `test=samespot` nur für den Launcher).
2. Spielstand laden und bauen. Die Zeilen stehen als `[mp_probe]net send …` in `stdout.txt`.
3. Ohne Speichern ins Hauptmenü und denselben Spielstand neu laden (Spiel nicht beenden).
4. „Am selben Ort nachbauen“: `tools/same-spot.ps1` teilt `stdout.txt` an `Loading game from file …` in Sitzungen, nimmt die Zeilen der letzten früheren Sitzung mit Bauten und schickt sie als `TF3MP/1 LINE <token> <zeile>` an 127.0.0.1 (Port aus `alut_proxy.ini`), jeweils bis zur Antwort `GOT`. Die DLL reicht sie wie Zeilen vom Partner (`kind=net`) an den Mod, der sie ohne Versatz baut.
Ohne Launcher: `powershell -ExecutionPolicy Bypass -File tools\same-spot.ps1` (mit `-List` nur anzeigen).
Wichtig: Das Spiel erst starten, wenn „Gleiche Stelle testen“ installiert ist. In Lauf 20 startete das Spiel 4 s vor dem Schreiben der `alut_proxy.ini`, lief deshalb noch als Loopback und hörte nicht auf dem Port (Launcher-Meldung „Das Spiel antwortet nicht auf Port 47800“).

### Lauf 20b (v20, gleiche Stelle) und Probe v21

- Logs: `logs/run20b-*` (dazu die UI-Fehlerberichte als JSON). Straße und Depot wurden am selben Ort nachgebaut (Kosten 17294 und 94215).
- Depot: Die Kopie hatte zwei Zufahrten. Das kopierte Gebäude legt seine eigene Zufahrt (bei ihm ein eingefrorenes Segment, Tor 44205 → Knoten 50594), und unsere mitgeschickte Zufahrt endete in einem zweiten Knoten (50651) auf dem Tor. Der Refresh-Vorschlag der Engine wollte die Zufahrt an den Straßenknoten legen, scheiterte aber („Bau nicht möglich“), vermutlich an unserer doppelten Zufahrt. Auch beim Original gehört die Zufahrt zum Gebäude (`frozenEdges`), das Tor hat also nie ein Segment „von außen“; die Prüfung von v20 meldete deshalb auch das Original als `NOT WELDED`.
- Kreuzung: Klick auf die kopierte Einmündung brach das Spielfenster ab (`attempt to index local 'baseNodeConfig' (a nil value)`, `::/gui/entity_window/double_slip_switch.tl:44`, TrafficLightConfigWidget). Der Bauvorschlag des Spielers hat `proposal.nodeConfigsToAdd` mit einer `BaseNodeConfig` je Knoten (6 bei einer Straße mit 6 Knoten): Spurverbindungen (`laneConnections`: `segment0/lane0 → segment1/lane1`, `withRoad`, `withTram`), Zebrastreifen (`crosswalks`), Ampel (`trafficLightPreference`, `trafficLightConfig`). Die Kopie hatte keine, also keine Spurverbindungen.

Probe v21 (Zeilenformat B5):
- Knotenkonfigurationen reisen mit: `e<k>;<p0>;<p1>` nennt ein Segment über die Positionen seiner beiden Endknoten (neue, bestehende und die eigenen Segmente eines Gebäudes), `k;<position>;<flags>;<ampelvorgabe>;<ampeltyp>;<verbindungen>;<zebrastreifen>;<phasen>` eine Konfiguration. Verbindungen `a:spur0:b:spur1:rt` (a, b = Nummern der `e`-Token, `r` Straße, `t` Tram), Phasen `dauer:min:T/F:spur+spur`, leere Listen `-`, Flags `d` (Doppelkreuzungsweiche), `l`, `t` (vom Spieler geändert). Wird die Zeile länger als 14000 Zeichen, bleiben die Konfigurationen weg (Hinweis im Log).
- Der Empfänger setzt sie nach dem Bau und nach der Depot-Prüfung in einem eigenen `SimpleProposal` (`streetProposal.nodeConfigsToAdd`, vorhandene Konfigurationen derselben Knoten in `nodeConfigsToRemove`), siehe `nodecfg.lua`. Knoten ist der Knoten an der Position, an dem alle genannten Segmente enden; gibt es keinen, bekommt der Knoten mit den meisten die Verbindungen zwischen diesen. Lehnt das Spiel alle zusammen ab, geht jeder Knoten einzeln. Spurverbindungen werden als `api.type.LaneConnection` (falls vorhanden), als Lua-Tabelle oder als Kopie einer Verbindung eines bestehenden Knotens gesetzt und zurückgelesen. Ergebnis im Log: `node configs result: x/y placed`.
- Ein Bau, der nur Knotenkonfigurationen ändert (z. B. Ampel umgestellt), wird jetzt auch übertragen.
- Depot: Die mitgeschickte Zufahrt wird beim Empfänger weggelassen (`replay: 1 entrance segment(s) left out, the construction lays its own`); das Gebäude legt seine eigene. `weld.status` folgt jetzt den eigenen Segmenten des Gebäudes vom Tor aus und meldet `WELDED`, wenn ein Knoten auf dem Weg auch ein fremdes Segment (die Straße) hat; sonst steht im Log, wo die Zufahrt endet und welche Knoten dort liegen. Danach wie in v20 Refresh und Ersetzen, falls nicht angeschlossen.

### Lauf 21 (v21, gleiche Stelle) und Probe v22

- Logs: `logs/run21-*` (Notizen in `logs/run21-notes.md`). Vom Nutzer selbst installiert (git pull und Launcher).
- Straße: nachgebaut (Kosten 18276), danach `node configs result: 6/6 placed` mit Spurverbindungen als `LaneConnection.new`. Die Kreuzungsdaten kommen also an.
- Depot: nicht gebaut. Ohne die mitgeschickte Zufahrt enthielt der Vorschlag die geteilte Straße (ein neuer Knoten, zwei Hälften, alte Strecke und alter Knoten entfernt) und das Gebäude. Das Spiel brach beim Berechnen ab (`map_util.h:22: Get: Assertion 'it != map.end()'`, dann `Unknown exception`), der zweite Versuch ohne entfernten Knoten ebenso (`StreetShapeFactory::PrepareTransitions: Assertion '!cc.empty()'`). Mit der Zufahrt (Lauf 20b) ging derselbe Vorschlag durch.
- Aus Lauf 20b: Die eigene Zufahrt eines kopierten Depots ist ein 14,7 m langes Stück vom Tor, das 3 m vor der Straßenmitte endet. Der Refresh-Vorschlag der Engine (`refreshConstruction`) ersetzt es durch eine Zufahrt vom Tor bis zum Straßenknoten und setzt dabei selbst die Knotenkonfigurationen (`nodeConfigsToAdd` für Straßenknoten und Tor). In Lauf 20b scheiterte er, vermutlich an unserer doppelten Zufahrt am selben Platz.

Probe v22:
- Ein Bau mit Gebäude und Zufahrt, der zugleich Straßen baut, teilt oder entfernt (und kein Gebäude abreißt), wird in Schritten nachgebaut (`main.replay_in_steps`): erst die Straßen allein, dann ihre Knotenkonfigurationen (an der Teilungsstelle nur die Verbindungen entlang der Straße, die Zufahrt gibt es noch nicht), dann das Gebäude allein, dann die Prüfung der Zufahrt mit Refresh und Ersetzen wie bisher, zuletzt alle Knotenkonfigurationen noch einmal. Log: `replay in steps: …`, `replay streets: …`, `replay construction: …`.
- Ein Depot ohne Straßenänderung (nur Zufahrt) geht wie in v21 in einem Vorschlag.

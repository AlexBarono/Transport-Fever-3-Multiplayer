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

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

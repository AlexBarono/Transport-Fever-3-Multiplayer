# Phase 0: Ergebnisse

> Historische Forschung. Aktueller Einstieg: [Dokumentation](README.md). Die Originalprotokolle liegen im [Protokollarchiv](../logs/README.md).

## Lauf 1 (06.10.2026, Spielstand „Test Luna“, Probe v1)

Log: [logs/probe-log-1-mp_probe.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-1-mp_probe.txt), Kontext: [logs/probe-log-1-context.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-1-context.txt)

**Sandbox (Game Script, Thread „Sim Pool“):**

| Verfügbar | Gesperrt |
|---|---|
| Lua 5.2, `require`, `load`, `os.time/clock/date/getenv`, `debug.getinfo` | `io` komplett, `os.execute/remove/tmpname`, `package.loadlib/cpath/path`, `dofile`, `loadfile`, `string.dump`, `collectgarbage`, `debug.sethook`, `ffi`, `jit`, `socket` |

`require('socket')` scheitert mit „module 'socket' not found“. **Folge:** Ein Game Script kann weder Netzwerk noch Dateien nutzen. Die Netzwerkschicht muss als native Komponente außerhalb von Lua laufen (wie im Plan, Abschnitt 3).

**Engine-API im Game Script:** `api.cmd`, `api.engine`, `api.res`, `api.type`, `api.GameScriptStateNotificationHelper`, `api.GameScriptTableHelper`, `game.config`. **Nicht vorhanden:** `api.gui`, `game.interface` (gab es in TF2).

Für Multiplayer interessante Befehle in `api.cmd`:

- Bauen/Linien/Fahrzeuge: `makeWorldBuildProposalCmd`, `makeLineCreateCmd`, `makeLineUpdateCmd`, `makeLineDestroyCmd`, `makeVehicleBuyCmd`, `makeVehicleSellCmd`, `makeVehicleSetLineCmd`, `makeVehicleReplaceCmd`, `makeVehicleSendToDepotCmd`
- Mehrere Firmen: `makeGameAddPlayerCmd`, `makeEntitySetPlayerCmd`
- Zeitsteuerung: `makeGameSetSpeedCmd`, `makeGameSetCalendarSpeedCmd`, `makeGameSetDateCmd`, `api.cmd.debug.makeGamePerformSimulationStepsCmd`
- Skript-Kommunikation: `makeScriptingSendEventCmd`

`makeGameAddPlayerCmd` und `makeEntitySetPlayerCmd` deuten darauf hin, dass die Engine mehrere Spieler/Firmen kennt. `makeGamePerformSimulationStepsCmd` könnte für tick-genaues Lockstep nützlich sein.

**Events beim Game Script:** `initNewGame`, `TownDeveloper/OnInitialTownDevelop`, `TransportVehicleSystem/OnCargoLoaded`. Bauaktionen des Spielers kamen ohne Abonnement nicht an (Template nutzt `state:subscribeToEvent("onPostBuildProposal")`).

**Snapshots:** Alle mit `game_interface=ERR`, weil `game.interface` fehlt. Probe v2 liest über `api.engine`.

**Probe v2 (nächster Lauf) prüft:** vollständige Listen von `api.engine`, `api.type`, `api.res` (v1 wurde nach 400 Zeilen abgeschnitten), Snapshots über `api.engine`, Bau-Events abonnieren.

## Lauf 2 (06.10.2026, Spielstand „Test2“, Probe v2)

Log: [logs/probe-log-2-mp_probe.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-2-mp_probe.txt), Kontext: [logs/probe-log-2-context.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-2-context.txt)

**Snapshots über `api.engine` funktionieren.** Lesbar: Spielzeit (`GAME_TIME.gameTime`, 200 ms Spielzeit pro Update), Geld (`ACCOUNT.balance` des Spielers) und Anzahlen für `TRANSPORT_VEHICLE`, `STATION`, `CONSTRUCTION`, `TOWN`, `SIM_PERSON`. Nicht lesbar: `PLAYER.balance` (nil); `LINE` und `BASE_EDGE` lassen sich nicht mit `forEachEntityWithComponent` durchlaufen („Cannot loop over this component type“).

**Engine-Systeme (Auszug):** `api.engine.system.lineSystem.getLines/getLinesForPlayer`, `transportVehicleSystem.getVehicles/getLineVehicles`, `streetSystem`, `stationSystem`, `gameScriptSystem`; `api.engine.util.vehicle.getPosition`, `util.finance.getPlayersBalance`, `util.proposal.*` (u. a. `makeProposalData`, `createProposalRemove`). `getPlayersBalance` und `getLinesForPlayer` passen zu mehreren Spielern pro Spiel.

**Bauaktionen:** `onPostBuildProposal` kommt nach dem Abonnieren vom Absender `apply_command` an. Der Parameter ist ein Array; v2 hat Array-Einträge versehentlich ausgeblendet, deshalb fehlt sein Inhalt noch.

**Probe v3 (nächster Lauf):** Array-Einträge und Werte in Listings, die ersten 5 Bauvorschläge vollständig (Tiefe 7), Linien über `lineSystem.getLines()`, Prüfsumme über alle Fahrzeugpositionen (`vehicle_pos_sum`) für den Determinismus-Test.

## Determinismus-Test (mit Probe v3)

In einer Spielsitzung: Spielstand „Test2“ laden, 5 Minuten ohne Eingabe und ohne Geschwindigkeitsänderung laufen lassen, denselben Stand erneut laden, wieder 5 Minuten laufen lassen. Der Update-Zähler ist im Spielstand gespeichert, also beginnen beide Läufe bei derselben Zahl. Stimmen die `snapshot`-Zeilen beider Läufe (inkl. `vehicle_pos_sum`) überein, ist die Simulation bei gleicher Ausgangslage deterministisch.

## Lauf 3 (06.10.2026, „Test2“ zweimal geladen, Probe v3)

Log: [logs/probe-log-3-mp_probe.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-3-mp_probe.txt), Kontext: [logs/probe-log-3-context.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-3-context.txt)

**Determinismus-Vergleich nicht möglich:** „Test2“ wurde direkt vor dem zweiten Laden überschrieben (11:05:01 gespeichert, 11:05:08 geladen). Der zweite Lauf setzte deshalb beim Stand des ersten fort (Updates 3000–7800, dann 8100–11400) statt beim selben Startpunkt.

**Gelesen:** Geld über `ACCOUNT.balance`, Linien über `lineSystem.getLines()`. Die Zahl der Bahnhöfe stieg auch ohne Eingriff (16 → 19); das Spiel baut also selbst (vermutlich Städte, z. B. Haltestellen).

**Bauvorschläge:** `onPostBuildProposal` liefert `{userdata, userdata, {neue Entity-IDs}, false}`. Die beiden userdata (vermutlich Vorschlag und Kontext) lassen sich nicht mit `pairs` durchlaufen. Fünf Vorschläge kamen, bevor der Spieler etwas baute, also ebenfalls vom Spiel selbst.

**Fehler:** `transportVehicleSystem.getVehicles()` erwartet Argumente („Error decoding argument #2“).

**Probe v4:** Fahrzeuge über `forEachEntityWithComponent(TRANSPORT_VEHICLE)` sammeln, Prüfsummen über Positionen und `stopIndex`; bekannte Feldnamen aus TF2 (`streetProposal`, `edgesToAdd`, `constructionsToAdd`, …) gezielt auf den Bauvorschlag anwenden.

## Lauf 4 (06.10.2026, „Det“ zweimal geladen, Probe v4): Determinismus-Test

Log: [logs/probe-log-4-mp_probe.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-4-mp_probe.txt), Kontext: [logs/probe-log-4-context.txt](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/blob/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs/probe-log-4-context.txt)

**Ergebnis: Die Simulation war in diesem Test deterministisch.** „Det“ wurde einmal gespeichert und zweimal geladen (11:16:11 und 11:18:49), beide Läufe starten bei Update 11700 / `game_time` 2340000. Alle 8 Snapshots, die in beiden Läufen vorkommen (Updates 11700–13800, 7 Minuten Spielzeit), sind in jedem Wert identisch: `game_time`, `money`, `n_construction`, `n_line`, `n_sim_person`, `n_station`, `n_town`, `n_transport_vehicle`, `vehicle_stop_sum`. Das Geld allein ändert sich mit jeder Lieferung und jedem Kostenposten und stimmte trotzdem auf die Einheit.

**Grenzen:** Gleicher PC, gleiche Spielversion. Ob zwei verschiedene PCs (andere CPU) gleich rechnen, ist offen. Die Fahrzeugpositionen konnten noch nicht verglichen werden (`util.vehicle.getPosition` liefert nil).

**Bauvorschlag-Format** (`onPostBuildProposal`, `param` = `{context, result, neueEntityIds, false}`):

```
param[1].proposal: addedSegments, removedSegments, addedNodes, removedNodes,
                   edgeObjectsToAdd, edgeObjectsToRemove, new2oldSegments,
                   old2newSegments, frozenNodes
param[1].toAdd[i]: fileName, params, transf, name, playerEntity, frozenNodes
param[1].toRemove
param[2]: costs, errorState {critical, messages, warnings}, collisionInfo
param[3]: Liste der neu erzeugten Entity-IDs
```

`playerEntity = -1` und leere `fileName` bei den Vorschlägen ohne Spielereingriff passen dazu, dass das Spiel (Städte) selbst baut.

**Bewertung für den Plan:** Die Voraussetzung für Lockstep ist erfüllt, soweit ein einzelner PC das prüfen kann. Offene Phase-0-Punkte: nativer Einstiegspunkt (welche DLLs lädt TF3, ist ein Proxy-DLL-Ansatz möglich) und ein Determinismus-Test zwischen zwei PCs.

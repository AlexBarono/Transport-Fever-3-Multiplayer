# Phase 0: Ergebnisse

## Lauf 1 (06.10.2026, Spielstand „Test Luna“, Probe v1)

Log: [logs/probe-log-1-mp_probe.txt](../logs/probe-log-1-mp_probe.txt), Kontext: [logs/probe-log-1-context.txt](../logs/probe-log-1-context.txt)

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

Log: [logs/probe-log-2-mp_probe.txt](../logs/probe-log-2-mp_probe.txt), Kontext: [logs/probe-log-2-context.txt](../logs/probe-log-2-context.txt)

**Snapshots über `api.engine` funktionieren.** Lesbar: Spielzeit (`GAME_TIME.gameTime`, 200 ms Spielzeit pro Update), Geld (`ACCOUNT.balance` des Spielers) und Anzahlen für `TRANSPORT_VEHICLE`, `STATION`, `CONSTRUCTION`, `TOWN`, `SIM_PERSON`. Nicht lesbar: `PLAYER.balance` (nil); `LINE` und `BASE_EDGE` lassen sich nicht mit `forEachEntityWithComponent` durchlaufen („Cannot loop over this component type“).

**Engine-Systeme (Auszug):** `api.engine.system.lineSystem.getLines/getLinesForPlayer`, `transportVehicleSystem.getVehicles/getLineVehicles`, `streetSystem`, `stationSystem`, `gameScriptSystem`; `api.engine.util.vehicle.getPosition`, `util.finance.getPlayersBalance`, `util.proposal.*` (u. a. `makeProposalData`, `createProposalRemove`). `getPlayersBalance` und `getLinesForPlayer` passen zu mehreren Spielern pro Spiel.

**Bauaktionen:** `onPostBuildProposal` kommt nach dem Abonnieren vom Absender `apply_command` an. Der Parameter ist ein Array; v2 hat Array-Einträge versehentlich ausgeblendet, deshalb fehlt sein Inhalt noch.

**Probe v3 (nächster Lauf):** Array-Einträge und Werte in Listings, die ersten 5 Bauvorschläge vollständig (Tiefe 7), Linien über `lineSystem.getLines()`, Prüfsumme über alle Fahrzeugpositionen (`vehicle_pos_sum`) für den Determinismus-Test.

## Determinismus-Test (mit Probe v3)

In einer Spielsitzung: Spielstand „Test2“ laden, 5 Minuten ohne Eingabe und ohne Geschwindigkeitsänderung laufen lassen, denselben Stand erneut laden, wieder 5 Minuten laufen lassen. Der Update-Zähler ist im Spielstand gespeichert, also beginnen beide Läufe bei derselben Zahl. Stimmen die `snapshot`-Zeilen beider Läufe (inkl. `vehicle_pos_sum`) überein, ist die Simulation bei gleicher Ausgangslage deterministisch.

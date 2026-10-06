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

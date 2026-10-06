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

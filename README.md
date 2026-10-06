# Transport Fever 3 Multiplayer

Ziel: Mehrere Spieler bauen gleichzeitig in derselben Transport-Fever-3-Welt. TF3 hat keinen offiziellen Multiplayer; dieses Projekt versucht es als Community-Mod (nur PC).

Der Umsetzungsplan steht in [docs/plan.md](docs/plan.md). Aktuell läuft **Phase 0: Erkundung**.

## Aufbau

```
docs/plan.md        Machbarkeit und Umsetzungsplan
mods/mp_probe/      Phase-0-Erkundungsmod (verändert das Spiel nicht, schreibt nur ins Log)
tests/              Offline-Tests der Lua-Mods gegen eine Mini-Attrappe der Engine
tools/run_lua.py    Startet Lua-Dateien mit lupa, falls kein Lua installiert ist
```

## Tests

```bash
lua tests/run_tests.lua
# oder ohne Lua-Installation:
pip install lupa
python3 tools/run_lua.py tests/run_tests.lua
```

## Hinweis

Dieses Projekt ist nicht mit Urban Games oder Paradox Interactive verbunden. Transport Fever ist eine Marke von Urban Games.

# Transport Fever 3 Multiplayer

Ziel: Mehrere Spieler bauen gleichzeitig in derselben Transport-Fever-3-Welt. TF3 hat keinen offiziellen Multiplayer; dieses Projekt versucht es als Community-Mod (nur PC).

Der Umsetzungsplan steht in [docs/plan.md](docs/plan.md). Aktuell läuft **Phase 1: Befehle spiegeln**. Priorität: zusätzliche Spielaktionen ergänzen; der Zwei-PC-Spieltest folgt danach.

## Aufbau

```
docs/plan.md        Machbarkeit und Umsetzungsplan
mods/mp_probe/      Phase-0-Erkundungsmod, Anleitung in docs/probe-mod.md
tests/              Offline-Tests der Lua-Mods gegen eine Mini-Attrappe der Engine
tools/run_lua.py    Startet Lua-Dateien mit lupa, falls kein Lua installiert ist
```

## Tests

```bash
lua tests/run_tests.lua
# oder ohne Lua-Installation:
pip install lupa
python3 tools/run_lua.py tests/run_tests.lua
python3 tools/run_lua.py tests/run_actions.lua
```

## Hinweis

Dieses Projekt ist nicht mit Urban Games oder Paradox Interactive verbunden. Transport Fever ist eine Marke von Urban Games.

## Einrichten per Doppelklick (Test)

1. Den Ordner herunterladen (auf GitHub: Branch `probe-v2` wählen, dann „Code“ → „Download ZIP“) und entpacken.
2. TF3 beenden, dann **`Start.bat`** doppelklicken.
3. Im Fenster „Gastgeber“ oder „Mitspieler“ wählen (oder „Allein testen“ bzw. „Gleiche Stelle testen“ für einen Test auf einem PC). Als Mitspieler die IP-Adresse des Gastgebers eintragen, dann „Installieren / Speichern“.
4. „Spiel starten“, einen Spielstand laden und danach „Verbindung prüfen“. Steht dort „VERBUNDEN“, haben sich die beiden Spiele gefunden.
5. „Entfernen“ stellt das Original wieder her (oder Steam → „Dateien auf Fehler überprüfen“).

Das Fenster installiert die fertige DLL aus `launcher/bin/alut.dll` (kein Visual Studio nötig), schreibt `alut_proxy.ini` und kopiert den Mod `mods/mp_probe` in den lokalen Mod-Ordner von TF3. Übers Internet braucht der Gastgeber eine UDP-Portfreigabe (Standard 47800) oder beide ein gemeinsames VPN wie Tailscale oder ZeroTier.

Letzter Spielnachweis (v12): Straßen und Gleise wurden im Loopback erfolgreich kopiert. Die Übertragung zum Partner ist implementiert; beide müssen denselben Spielstand laden. Mit „Allein testen“ kommt jede eigene Straße bzw. jedes Gleis 100 m daneben zurück (ab v19). Mit „Gleiche Stelle testen“ (ab v20) baut man etwas, lädt denselben Spielstand ohne Speichern neu und lässt es mit „Am selben Ort nachbauen“ genau an derselben Stelle wieder entstehen, so wie es der Mitspieler bekäme.

**Aktualisierung Probe v13 (06.10.2026):** Der letzte tatsächliche Spieltest mit v12 hat auch Gleise im Loopback bestätigt. V13 ergänzt Code für Bahnhöfe/Depots samt modularen Parametern, Konstruktionserweiterungen, reinen Abriss, Linien (Anlegen, Änderungen, Löschen) und Fahrzeuge (Kauf, Konfiguration ersetzen, Verkauf, Linienzuordnung, Name, Start/Stopp und manuelle Abfahrt). Die neuen Aktionen sind bisher **offline getestet, noch nicht im Spiel bestätigt**. Straßenanschlüsse und gemischte Straßenumbauten bleiben offen. Anleitung, Grenzen und Übergabe für Claude: [docs/phase2-actions.md](docs/phase2-actions.md).

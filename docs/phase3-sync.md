# Probe v24: beide Spiele im Gleichschritt halten

Stand 07.10.2026. Bauten, Linien und Fahrzeuge kommen als Zeilen beim anderen Spiel an (Phase 1 und 2). Damit beide Spiele auch danach gleich bleiben, gleicht v24 ab:

- Pause und Spielgeschwindigkeit,
- Spielzeit (das Spiel, das zurückliegt, holt auf),
- Datum,
- Geld und Kredit (der Gastgeber gibt den Stand vor),
- und es meldet, wenn die Spiele auseinanderlaufen (Zahl der Linien, Fahrzeuge, Stationen, Gebäude).

## Kanal: Zustandstexte (DLL v8)

Bauzeilen gehen einzeln und zuverlässig in einer Warteschlange (`LINE`/`GOT`). Für den Abgleich zählt dagegen nur der neueste Stand, und er muss auch durchkommen, während das Spiel pausiert. Deshalb gibt es einen zweiten Weg:

- Der Mod schreibt `net state <schlüssel> <text>` ins Log (`stdout.txt`). Die DLL nimmt den Text, legt ihn in die Umgebungsvariable `TF3MP_OWN_<SCHLÜSSEL>` und schickt ihn als `TF3MP/1 STATE <schlüssel> <text>` an das andere Spiel: sofort bei einer Änderung und sonst jede Sekunde wieder. Nichts wird gepuffert, der neueste Text gewinnt.
- Beim anderen Spiel landet er in `TF3MP_PEER_<SCHLÜSSEL>`. Schweigt der Partner 10 Sekunden, leert die DLL diese Variablen.
- `TF3MP_ROLE` sagt dem Mod, ob er Gastgeber (`host`), Mitspieler (`client`), Allein-Test (`loopback`) oder aus (`off`) ist. Ohne DLL v8 fehlt die Variable, und der Mod gleicht nichts ab.

Schlüssel: `gui` (Geschwindigkeit, vom GUI-Skript) und `sim` (Prüfpunkt der Simulation). Format: `schlüssel=wert` durch Leerzeichen getrennt (`sync.encode`/`sync.decode`).

## Geschwindigkeit und Pause (`gui.lua`, `sync.speed_step`)

Die Simulationsskripte laufen nicht, solange das Spiel pausiert (`GameTime.updateCount` steht). Sie könnten weder eine eigene Pause bemerken noch eine Pause des anderen Spiels aufheben. Deshalb ist in `main.gs.lua` jetzt auch `guiUpdateScript = main.script@guiUpdate` eingetragen. Das GUI-Skript läuft in jedem Bild, auch in der Pause; es arbeitet alle 0,25 s.

- Die gemeinsame Geschwindigkeit ist ein Register mit Version. Ändert der Spieler die Geschwindigkeit (auch Pause = 0), steigt die Version, und das andere Spiel übernimmt den Wert. Bei gleicher Version gewinnt der Gastgeber. Beim Start übernimmt der Mitspieler die Geschwindigkeit des Gastgebers.
- Eigene Befehle (`makeGameSetSpeedCmd`) gelten nicht als Änderung durch den Spieler. Kommt einer nach 3 s nicht an, wird er bis zu dreimal wiederholt; danach folgt das Spiel nicht mehr (`could not be set`), gibt aber eigene Änderungen weiter.
- Aufholen: Liegt ein Spiel mehr als 30 s Spielzeit zurück, läuft es doppelt so schnell (höchstens 4x). Läuft das gemeinsame Tempo schon mit 4x, läuft stattdessen das vordere mit halber Geschwindigkeit. Mehr als 120 s voraus wartet das vordere Spiel mit Geschwindigkeit 0. Unter 5 s Abstand ist Schluss. Die Spielzeit des anderen Spiels wird ab seinem letzten Lebenszeichen (alle 2 s) mit seiner Geschwindigkeit hochgerechnet. Ohne Lebenszeichen seit 8 s, in der Pause oder bei mehr als 2 Stunden Abstand (anderer Spielstand?) wird nicht aufgeholt. Aufholen ändert die gemeinsame Geschwindigkeit nicht.
- Falls der Lua-Zustand des GUI-Skripts zwischen Aufrufen sein Gedächtnis verliert, holt `speed_step` das Register aus `TF3MP_OWN_GUI` zurück (`rs=` im Zustand zählt das).
- Läuft das GUI-Skript nicht (kein `TF3MP_OWN_GUI` mit `src=gui` nach 100 Updates), übernimmt die Simulation die Geschwindigkeit (`src=sim`); eine Pause des anderen Spiels kann sie dann nicht aufheben (Log: `the GUI script does not run here`).

Logzeilen: `gui script running: …` (was das GUI-Skript kann), `gui speed command test: 1x, success=true` (ein harmloser Befehl mit der aktuellen Geschwindigkeit), `sync speed changed here: paused (version 3)`, `sync speed from the other game: 2x (version 4, set by the host)`, `sync this game is 45 s of game time behind, catching up`, `sync caught up (…)`, und alle 2 s `net state gui by=… gt=… hb=… run=… speed=… src=gui tg=… ver=…`.

## Prüfpunkte, Geld, Datum, Abweichungen (`main.sync_tick`, `sync.compare`)

- Jede Minute Spielzeit (im ersten Update, in dem die Spielzeit eine volle Minute erreicht) schreibt die Simulation einen Prüfpunkt: `net state sim ck=<nr> con=… date=… gt=… lines=… loan=… money=… st=… veh=…`. Beide Spiele laden denselben Spielstand und haben deshalb dieselben Spielzeiten; Prüfpunkt `ck` gehört in beiden Spielen zur selben Spielzeit.
- Liegen von beiden Spielen Prüfpunkte mit derselben Nummer vor, werden sie verglichen: `sync check 52 (1900-03-14): same` oder `… differs in money, veh`. Die Reihenfolge ist egal (wer zurückliegt, vergleicht später).
- Eine Abweichung zählt erst, wenn sie an zwei aufeinanderfolgenden Prüfpunkten besteht (Geld, Kredit, Datum mit gleichem Vorzeichen). Ein Bau, der beim anderen Spiel ein paar Sekunden später ankommt, löst so nichts aus. Dann: `sync WARNING: the games differ: veh here 14, in the other game 15` in beiden Spielen, für denselben Unterschied erst nach 10 Prüfpunkten wieder.
- Nur der Mitspieler korrigiert. Lauf 25 zeigte: In `update()` lehnt das Spiel jeden Befehl mit Rückmeldung ab (`Callbacks are currently disallowed`). Ab v25 gehen die Korrekturen deshalb wie ein Nachbau als Skript-Ereignis an `handleEvent` (`main.sync_send_fix`, `main.sync_apply`), wo Rückmeldungen erlaubt sind:
  - Kredit: Buchung `JournalEntry.Type.LOAN` über die Differenz. Geld wartet in diesem Schritt, weil die Kreditbuchung das Geld mitbewegt.
  - Geld (Abweichung über 1000): Buchung `JournalEntry.Type.OTHER` (Unterart `CHEAT`, sonst `OTHER`/`MISC`, falls vorhanden) über `makeJournalBookAssetCmd`.
  - Datum: `makeGameSetDateCmd` mit dem heutigen Datum plus der Differenz in Tagen.
- Lehnt das Spiel eine Korrektur ab (`success=false`) oder lässt sich das Ereignis nicht schicken, wird das Feld sofort nicht mehr korrigiert. Gebuchtes Geld zählt der Mitspieler in `adj=` seines Prüfpunkts mit.
- Jede Korrektur wird am nächsten eigenen Prüfpunkt nachgeprüft: `the money correction by 5000 worked`, oder `… had no effect …; money is no longer corrected`. So kann eine falsch verstandene Buchung (Vorzeichen, Art) höchstens einmal passieren.
- Ein Eintrag, dessen Art sich nicht setzen lässt, wird nicht gebucht (er könnte sonst als Kredit oder Baukosten landen).
- Einmal pro Spielstand (v24) schreibt die Simulation, wie `JournalEntry` aussieht (`journal: Type: …; Other: …; amount=…`). Gebucht wird dafür nichts: Lehnt die Engine eine Buchung mit einer Assertion ab und beendet das Spiel, liefe der Test nach jedem Laden wieder, weil der Spielstand die Markierung nie speichern konnte. Ob Buchungen das Geld richtig bewegen, zeigt der Test mit dem simulierten Gastgeber.
- Lädt man einen Spielstand neu (Spielzeit geht zurück, oder `handleLegacy`), beginnen die Prüfpunkte von vorn.

## Kleinigkeit aus Lauf 24

Eine nachgebaute Linie wurde einmal als Änderung zurückgeschickt: Nachdem ein Bus auf die Kopie gesetzt war, trug das Spiel die Verkehrsarten der Linie (`vehicleInfo.transportModes`) ein, und die Momentaufnahme sah eine geänderte Linie. `actions.lua` vergleicht Linien jetzt ohne diese Verkehrsarten; mitgeschickt werden sie weiterhin.

## Test auf einem PC mit simuliertem Gastgeber

`tools/fake-partner.ps1` spielt den Gastgeber für ein Spiel, das als Mitspieler auf 127.0.0.1 eingestellt ist (`alut_proxy.ini`: `mode=client`, `host=127.0.0.1`, `port=47800`). Ablauf ab dem ersten Lebenszeichen des GUI-Skripts:

| Sekunde | Gastgeber | Erwartet im Spiel |
|---|---|---|
| 0 | folgt dem Spiel | `gui script running`, `sync check … same` |
| 60 | pausiert | Spiel pausiert, `speed from the other game: paused` |
| 80 | läuft mit 1x | Spiel läuft, `speed from the other game: 1x` |
| 100 | 90 s Spielzeit voraus | Spiel läuft mit 2x, `behind, catching up`, später `caught up` |
| danach | 5000 mehr Geld, bis das Spiel sie gebucht hat (`adj=` im Prüfpunkt) | `WARNING … money`, `booking it`, `money corrected by 5000, success=true`, dann `the money correction by 5000 worked` |
| ab dem vierten Prüfpunkt, zweimal | ein Fahrzeug mehr | `WARNING: the games differ: veh …` |

Im Launcher: "Test mit simuliertem Gastgeber" wählen und "Installieren / Speichern" klicken. Der Launcher stellt das Spiel als Mitspieler auf 127.0.0.1 ein und startet das Werkzeug in einem verkleinerten PowerShell-Fenster (2 Stunden); "Spiel starten" startet es wieder, falls das Fenster zu ist. Danach einen Spielstand laden, mit 1x etwa 8 Minuten laufen lassen und ohne Speichern beenden (das Spiel bucht 5000 Geld nach).

Pausiert der Spieler selbst, steht im Log des Werkzeugs `the game changed the speed: 0`. Bauzeilen des Spiels werden bestätigt und aufgehoben. Lädt das Spiel den Spielstand neu (seine Spielzeit springt um mehr als 30 s zurück), schickt das Werkzeug sie zurück, sobald das Spiel wieder 20 s läuft, eine nach der anderen mit neuen Tokens (`fh<pid>-<runde>.<n>`): das Spiel baut sie an derselben Stelle nach, wie bei "Gleiche Stelle testen", nur ohne Knopf. Das Werkzeug schreibt `tools/fake-partner.log`.

Offline wurde das Werkzeug gegen eine Nachbildung des Mitspielers geprüft (Mod-Code in Lua, DLL-Verhalten in Python).

## Lauf 25 (v24, simulierter Gastgeber)

Pause, Weiterlaufen und Aufholen (89 s Rückstand, nach 84 s aufgeholt) kamen im Spiel an; die GUI-Skripte laufen und dürfen `api.engine`, `sendCommand`, `os.getenv` und `os.clock` benutzen. Geld- und Fahrzeugunterschiede wurden erkannt. Die Geldbuchung selbst schlug fehl (`Callbacks are currently disallowed` in `update()`); `the money correction by 5000 worked` war falsch, weil der simulierte Gastgeber seinen Vorsprung nach zwei Prüfpunkten von selbst aufgab. Beides ist in v25 behoben (siehe oben). Logs: `logs/run25-*`.

## Offline-Prüfung

`python3 tools/run_lua.py tests/run_sync.lua` (32 Tests, die Befehle mit Rückmeldung in `update()` wie das Spiel ablehnen: Zustandstexte, Kalender, Prüfpunkte, Geschwindigkeitsregister mit Pause, gleichzeitigen Änderungen, verlorenen Befehlen, Aufholen, Warten, Gedächtnisverlust; zwei Spiele über eine nachgebildete DLL: Geld, Kredit, Datum, Abweichungen, Neuladen, Journal-Beschreibung, Ersatz ohne GUI-Skript). Dazu `tests/run_tests.lua` (78) und `tests/run_actions.lua` (40), unter Lua 5.2 und 5.4.

## Offen

- Ob TF3 das GUI-Skript aufruft und was dort erlaubt ist (`api.engine`, `api.cmd.sendCommand`, `os.getenv`, `os.clock`), zeigt erst der erste Lauf (`gui script running: …`).
- Ob `makeJournalBookAssetCmd` mit `JournalEntry.Type.OTHER` das Geld bewegt, zeigt der nächste Test mit dem simulierten Gastgeber (`money corrected by 5000, success=true`, dann `worked`).
- Ob das Abreißen einer Straße übertragen wird, ist seit Lauf 21 nicht mehr geprüft: In Lauf 24 kam kein Abriss im Log an (frühere Läufe haben Abrisse erfasst).
- Fahrzeugpositionen werden nicht verglichen (`getPosition` liefert in TF3 nil, siehe Phase 0).

# Multiplayer Probe (Phase 0)

Entwickler-Mod, der herausfindet, was die Lua-Umgebung von Transport Fever 3 erlaubt. Er verändert das Spiel nicht, sondern schreibt nur Zeilen mit `[mp_probe]` ins Spiel-Log.

Was er protokolliert:

1. **Sandbox:** Lua-Version und ob `io`, `os`, `package.loadlib`, `require('socket')`, `debug` usw. verfügbar sind, plus ein Test, ob eine Datei geschrieben werden kann.
2. **Engine-API:** alle sichtbaren Einträge unter `api` und `game` (3 Ebenen tief).
3. **Events:** jeden Event-Typ, der beim Game Script ankommt, einmal.
4. **Snapshots:** alle 300 Updates Spielzeit, Fahrzeuganzahl und Geld. Das ist die Grundlage für den Determinismus-Test.

Schritte 1 und 2 laufen einmal pro Spielstand.

## Installieren (Windows, Steam)

1. Den Ordner `mods/mp_probe` kopieren nach
   `C:\Program Files (x86)\Steam\userdata\<deine Steam-ID>\3493540\local\staging_area\mp_probe`
2. TF3 starten, im Mod-Menü **Multiplayer Probe (dev)** aktivieren und ein **neues** Spiel starten.
3. Ein paar Minuten spielen, etwas bauen (Straße, Bahnhof, Linie), dann beenden.
4. Die Log-Datei `stdout.txt` suchen. Bei TF2 lag sie unter `Steam\userdata\<ID>\<App-ID>\local\crash_dump\stdout.txt`, bei TF3 vermutlich unter `...\3493540\local\crash_dump\stdout.txt`.
5. Die Datei (oder alle Zeilen mit `[mp_probe]`) hier im Projekt hochladen.

## Determinismus-Test (Phase 0, Schritt 4)

1. Einen Spielstand speichern.
2. Ihn laden, Spiel 10 Minuten ohne Eingriff laufen lassen, beenden, `stdout.txt` sichern.
3. Denselben Stand erneut laden und genauso lange laufen lassen.
4. Die `snapshot`-Zeilen beider Läufe vergleichen. Sind sie identisch, spricht das für eine deterministische Simulation.

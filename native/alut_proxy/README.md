# alut.dll Test-Proxy

Testet, ob TF3 eine ausgetauschte `alut.dll` lädt (Phase 0, Schritt 3, siehe `docs/native-entry-point.md`).

- Die Proxy-DLL leitet alle 20 Exporte an `alut_orig.dll` (die umbenannte Original-DLL) weiter.
- Sie macht selbst nur eins: Beim Laden und Entladen schreibt sie eine Zeile nach `%LOCALAPPDATA%\TF3Multiplayer\proxy.log`.

## Bauen

Benötigt Visual Studio mit C++-Werkzeugen (x64).

```
build.bat
```

Ergebnis: `build\alut.dll`.

## Installieren / Entfernen

TF3 vorher beenden.

```
powershell -ExecutionPolicy Bypass -File install.ps1
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

`install.ps1` benennt die signierte Original-`alut.dll` in `alut_orig.dll` um und kopiert den Proxy als `alut.dll` in den Spielordner. `uninstall.ps1` stellt das Original wieder her. Alternativ stellt Steam über „Dateien auf Fehler überprüfen“ das Original wieder her (dann bleibt nur eine überflüssige `alut_orig.dll` liegen).

## Test

1. TF3 starten, bis ins Hauptmenü, wieder beenden.
2. `%LOCALAPPDATA%\TF3Multiplayer\proxy.log` sollte `loaded` und `unloaded` enthalten.
3. Ton im Spiel prüfen (alut ist für Audio zuständig).

# alut.dll Proxy (nativer Einstiegspunkt)

TF3 lädt `alut.dll` aus dem Spielordner. Dieser Proxy ersetzt sie (siehe `docs/native-entry-point.md`).

- Alle 20 Exporte werden an `alut_orig.dll` (die umbenannte Original-DLL) weitergeleitet (`forwards.h`).
- Log: `alut_proxy.log` neben der DLL im Spielordner. Im Spielprozess fehlt `LOCALAPPDATA`, deshalb kein Log dort.
- Ab v3: optionale UDP-Verbindung zwischen zwei Spielen (`net.c`, Phase 1, Schritt 2). Ohne `alut_proxy.ini` ist sie aus.

## Netzwerk-Test (v3)

`alut_proxy.ini` neben die `alut.dll` in den Spielordner legen.

PC 1 (Host):

```
[net]
mode=host
port=47800
```

PC 2 (Client), `host` = IP-Adresse von PC 1:

```
[net]
mode=client
port=47800
host=192.168.1.10
```

Beide Spiele starten. Windows fragt beim Host evtl. nach einer Firewall-Freigabe für TF3 (privates Netzwerk erlauben). Im Log sollte auf beiden Seiten `net: connected to ...` stehen. Bisher werden nur HELLO-Pakete alle 2 Sekunden ausgetauscht, noch keine Spieldaten.

Ohne Spiel und ohne zweiten PC: `test_net.ps1` lädt die DLL in zwei Prozessen auf 127.0.0.1.

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

`install.ps1` benennt beim ersten Mal die signierte Original-`alut.dll` in `alut_orig.dll` um und kopiert den Proxy als `alut.dll` in den Spielordner. `uninstall.ps1` stellt das Original wieder her. Alternativ stellt Steam über „Dateien auf Fehler überprüfen“ das Original wieder her (dann bleibt nur eine überflüssige `alut_orig.dll` liegen).

## Brückentest Lua ↔ DLL (v4)

`bridge.c` testet, wie der Lua-Mod und die DLL ohne `io` Daten austauschen können (siehe `docs/phase1-bridge.md`):

- Die DLL liest `stdout.txt` des Spiels mit und meldet jede Zeile `bridge out seq=N` des Mods `mp_probe` (v5) in `alut_proxy.log`.
- Danach setzt sie die Umgebungsvariable `TF3MP_IN=ack N` über `_putenv_s` aus `ucrtbase.dll`. Der Mod liest sie mit `os.getenv` und schreibt `bridge in TF3MP_IN=ack N` ins Spiel-Log.
- Gleich beim Start setzt die DLL `TF3MP_IN=hello`.

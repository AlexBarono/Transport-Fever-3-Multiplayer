# alut.dll Proxy (nativer Einstiegspunkt)

TF3 lädt `alut.dll` aus dem Spielordner. Dieser Proxy ersetzt sie (siehe `docs/native-entry-point.md`).

- Alle 20 Exporte werden an `alut_orig.dll` (die umbenannte Original-DLL) weitergeleitet (`forwards.h`).
- Log: `alut_proxy.log` neben der DLL im Spielordner. Im Spielprozess fehlt `LOCALAPPDATA`, deshalb kein Log dort.
- Ab v3: optionale UDP-Verbindung zwischen zwei Spielen (`net.c`, Phase 1, Schritt 2). Ohne `alut_proxy.ini` ist sie aus.
- Ab v7: überträgt gebaute Straßen zwischen den Spielen (Phase 1, Schritt 4, siehe unten).
- Ab v8: Zustandstexte für den Abgleich von Geschwindigkeit, Spielzeit, Geld und Datum (siehe unten und `docs/phase3-sync.md`).
- Ab v9: Warteschlangen für 128 statt 8 Bau-Zeilen je Richtung (vorher ging die neunte verloren, wenn das andere Spiel noch nicht da war), und eine empfangene Zeile steht sofort in `TF3MP_IN`, nicht erst beim nächsten Bridge-Tick. Der Mod (ab v25) schaut alle 10 Updates nach.

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

### Wiederaufbau-Test (v5)

Sobald der Mod `capture stored for replay` ins Log schreibt (also eine Straße oder ein Gleis aufgezeichnet hat), setzt die DLL beim nächsten Tick `TF3MP_IN=replay <seq>`. Der Mod baut daraufhin denselben Bau erneut auf. Im Spiel-Log steht dann `replay: ok, ...` mit dem Layout und der Signatur, die funktioniert hat, oder `replay: failed, ...` mit allen Fehlermeldungen.

Ab v7 gibt es diesen Auslöser nicht mehr; der Ein-PC-Test läuft über `mode=loopback` (unten).

## Bauten übertragen (v7)

Der Mod `mp_probe` (ab v12) schreibt jede Straße, die er nachbauen kann, als `net send <Zeile>` ins Spiel-Log. Die DLL liest die Zeile mit und

- schickt sie bei `mode=host` oder `mode=client` als UDP-Paket `TF3MP/1 LINE <token> <Zeile>` an das andere Spiel, jede Sekunde erneut, bis dort `TF3MP/1 GOT <token>` zurückkommt;
- legt sie bei `mode=loopback` direkt in den eigenen Eingang (Test auf einem PC, ohne Netzwerk).

Empfangene Zeilen bietet die DLL dem Mod über `TF3MP_IN=line <token> <net|loop> <Zeile>` an, bis der Mod `net received token=<token>` ins Log schreibt. Der Mod baut eine `net`-Zeile an derselben Stelle, eine `loop`-Zeile 40 m daneben. Ein Bau, den der Mod nachgebaut hat, meldet das Spiel nicht als Spielerbau, deshalb wird er nicht zurückgeschickt.

Allein testen:

```
[net]
mode=loopback
```

Im `alut_proxy.log` stehen dann `net: line <token> ... queued for this game (loopback)` und `bridge: the mod has line <token>`; bei zwei PCs `sent to the peer`, `delivered to the peer` und `received from the peer`. Beide Spiele müssen denselben Spielstand geladen haben. Eine Zeile darf höchstens 16383 Zeichen lang sein.

Die DLL findet `stdout.txt` über den Steam-Ordner aus der Registry (`HKCU\Software\Valve\Steam\SteamPath`), auch wenn das Spiel in einer anderen Steam-Bibliothek liegt.

## Zustandstexte (v8)

Schreibt der Mod `net state <schlüssel> <text>` ins Spiel-Log (Schlüssel: 1 bis 8 Kleinbuchstaben, Text bis 511 Zeichen), merkt sich die DLL den Text als neuesten Stand dieses Schlüssels:

- Sie setzt `TF3MP_OWN_<SCHLÜSSEL>` auf den Text (der Mod kann so nachlesen, was er zuletzt gesagt hat).
- Bei `mode=host` oder `mode=client` schickt sie ihn als `TF3MP/1 STATE <schlüssel> <text>` an das andere Spiel, sofort bei einer Änderung und sonst jede Sekunde wieder. Es gibt keine Warteschlange und kein `GOT`; es zählt nur der neueste Stand. Höchstens 4 Schlüssel.
- Vom anderen Spiel empfangene Texte setzt sie in `TF3MP_PEER_<SCHLÜSSEL>`. Schweigt das andere Spiel 10 Sekunden, leert sie diese Variablen.
- `TF3MP_ROLE` enthält beim Start `host`, `client`, `loopback` oder `off`.

Im `alut_proxy.log` stehen `bridge: TF3MP_ROLE=…`, `bridge: first state gui of the mod: …` und `net: state gui from the peer (1 so far): …`.

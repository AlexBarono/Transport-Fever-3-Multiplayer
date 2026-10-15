# Übergabe: Probe v30 / Proxy v10

> Historische Übergabe v30. Aktueller Einstieg: [Dokumentation](README.md). Die Originalprotokolle liegen im [Protokollarchiv](../logs/README.md); die benötigte Replay-Aufnahme liegt unter `tests/fixtures/run29-replay.log`.

Historischer Stand der Transport-Korrekturen. Run30 hat inzwischen alle 21 Aktionen bestätigt. Aktueller Stand v31/v11 und nächste Arbeit: [phase5-session-world.md](phase5-session-world.md).

Auftrag: Fehler aus run26 beheben, zuverlässige Übertragung und große Aktionen umsetzen, Launcher mit Gastgeber-/Beitreten-Ansichten für einen gemeinsamen VPN-Test verbessern. Grundlage ist Claudes Commit `3009beb` (v26/v9). Der Nutzer hat v27, v28 und v29 im Spiel getestet; v30 korrigiert den abgelehnten Bahnhofsumbau. Codex hat kein Spiel gestartet und keinen Zwei-PC-Spieltest durchgeführt. Die Änderungen liegen im gemeinsamen Arbeitsverzeichnis; keine automatischen Commits.

## Run29 und Korrekturen in v30

Gesichert unter `logs/run29-stdout.txt`, `run29-proxy.log`, `run29-proxy.status` und `run29-fake-host.log`. 21 Aktionen aufgenommen. Replay 1–11 bestätigt: Bahnhofabriss, dadurch entstandener ungültiger Linienhalt, Gleisbau, zwei neue Bahnhöfe, Depot/Anschluss und Signal. Aktion12 (`fh31660-1.12`) ist die erste Erweiterung des ersten Bahnhofs; Callback `success=false`, `critical=true`, Kosten0, Meldung „Bau nicht möglich“. Mit und ohne `old2new` identische Ablehnung. Die restlichen neun Aktionen wurden nicht ausgeführt.

Der konkrete Strukturunterschied: Originalerweiterung nutzt den vorhandenen Anschlussnode50927 und erstellt24 neue Nodes; der rekonstruierte `SimpleProposal` erzeugt25 neue Nodes. Der vorhandene Anschluss wird beim vollständigen Neubau nicht übernommen. Die generische Fehlermeldung beweist keine einzelne Kollisionsursache.

Die lokal installierte originale GUI (`base/content/gui.zip`, `gui/construction/construction.tl:1289–1301`) verwendet für Parameteränderungen `api.engine.util.proposal.createProposalReplaceConstruction(entity, modifiedParams)` und sendet den vollständigen Vorschlag ohne eigenen Context. Der Helper ist offiziell dokumentiert (`docs/tf3-api/tealdef/api/engine/util.d.tl:940–945`) und laut Sandbox-Dump verfügbar (stdout:733/6681). `params.upgrade` wird im ausgelieferten Bahnhofs-Lua nicht gelesen; das separate `upgradeFn` betrifft nur Gleismodultyp und Katenarie und wird für unsere fertige Modulmap nicht erneut aufgerufen.

v30 verwendet diesen nativen Generator gezielt bei einem reinen 1:1-Ersatz derselben Konstruktion mit unveränderter Transformation. Die bestehende Entity wird lokal aufgelöst; die fertigen aufgezeichneten Parameter gehen vollständig an die Engine. Gemischte Bauvorhaben und bewegte Konstruktionen bleiben im bestehenden Pfad. Ein vorhandener, aber fehlschlagender Generator wird nicht durch einen zweiten Neubauversuch verdeckt. Der vollständige Befehl verwendet Context=nil, ignoreErrors=false und playerInitiated=false, damit Replays keine Spieler-Aufnahmen erzeugen.

Nach dem nativen Ersatz werden keine weiteren Bau-/Konfigurationsbefehle gesendet. Die bestehenden Knotenkonfigurations- und verzögerten Anschlussprüfungen halten die Ausführungsquittung weiterhin zurück. Auch eine Ausnahme beim Auslesen der verzögerten Anschlussprüfung führt jetzt zu FAIL; zuvor wurden die Prüfungen dann nur gelöscht und die Aktion fälschlich bestätigt. Der echte 5070-Byte-Datensatz ist zusätzlich als `tests/fixtures/run29-station-extension.b5` gesichert. Run30 bestätigt inzwischen die drei Erweiterungen mit erhaltenem Anschluss und alle 21 Aktionen. DLL war für diesen v30-Test unverändert v10.

`Test-letzte-Aufnahme.bat` öffnet den Launcher mit `-ReplayLog tests/fixtures/run29-replay.log` und wählt Gleiche Stelle vor. Der Starter liest die gesicherten 21 Aktionen, ohne sie neu aufnehmen zu müssen. TF3 vollständig beenden, **Test starten**, den ursprünglichen Spielstand **Det** vor den Änderungen laden, Zeit laufen lassen und **Am selben Ort nachbauen** klicken. Vor dem Senden müssen Host-/Gleiche-Stelle-Konfiguration und laufendes Spiel passen. Der aktuell geladene Spielstand wird aus dem Live-Protokoll gelesen; alte Ladezeilen vor dem aktuellen Prozessstart und abweichende Spielstände werden abgelehnt. Die gespeicherte Aufnahme selbst wird dabei nicht verändert. Normale Launcher-Starts lesen weiterhin die frische Aufnahme aus stdout.

## Run28 und Korrekturen in v29

Gesichert unter `logs/run28-stdout.txt`, `run28-proxy.log`, `run28-proxy.status` und `run28-fake-host.log`. 26 Aktionen vollständig aufgenommen. Erster Replay (`fh48716-1.1`) reißt den vorhandenen Bahnhof ab: Callback `success=true`, Kosten 4698, keine neuen Entities, kein kritischer Fehler. Nutzer bestätigt den sichtbaren Abriss. Unsere v28-Prüfung meldet dennoch NOTHING BUILT und stoppt alle 25 Folgeaktionen.

- **Belegte Ursache:** `api.engine.entityExists` ist laut Sandbox-Dump eine aufrufbare Tabelle (stdout:446/5978). Der v28-Typguard erwartete eine Lua-Funktion und hat die Prüfung überhaupt nicht aufgerufen. v29 führt den tatsächlichen Aufruf im `pcall` aus. Regression bildet den Bahnhofabriss mit 24 von der Konstruktion verwalteten Knoten und einer API-Tabelle mit `__call` nach. Erfolgreiche Abrisse loggen die Anzahl bestätigter Entfernungen; Fehler nennen Entity-ID und Prüfungsgrund. Es gibt bisher keinen Beleg für verzögerte Entity-Löschung nach dem Callback; daher kein zusätzlicher zeitgesteuerter Retry.
- **Belegter Aufnahmefehler:** Drei spätere Bahnhofserweiterungen melden `capture leaves out demolished construction 43692` (stdout:5098/5608/5637). Bei wiederverwendeter ID hat `remember_constructions` die neue Konstruktion zuerst gespeichert und anschließend wieder entfernt. v29 löscht den alten Cacheeintrag nach der Aufnahme, bevor es die neuen Entity-Daten einliest. Regression prüft drei aufeinanderfolgende Upgrades derselben ID und anschließenden Abriss.
- **Folgeaktion nach Abriss:** Aufnahme2 enthält `line_update` mit leerer Stationsliste sowie `station=-1`, `terminal=-1` im gelöschten Halt. Der bisherige Mapper rief `getStationGroup(nil)` auf und hätte nach behobenem Abriss hier angehalten. v29 erhält den Platzhalter am bisherigen Haltindex; unbekannte gültige Stationen werden weiter abgelehnt.
- **Geld-Fix aus v28 im Spiel angenommen:** stdout:5718/5719 meldet `money corrected by 5000, success=true` und `time -1`. Vor dem nächsten Prüfpunkt wurde geladen; die spätere Wirkungsprüfung fehlt noch. Keine neuen Asserts oder unbekannten Ausnahmen im gesicherten run28.

Für den damaligen v29-Test war eine frische Aufnahme erforderlich: Fehlende `d;`-Tokens der Bahnhofserweiterungen lassen sich aus run28 nicht zuverlässig ersetzen. Dieser Test wurde als run29 durchgeführt; Abriss und die Folgeaktionen bis zur ersten Bahnhofserweiterung sind darin bestätigt. Die vollständige run29-Aufnahme lässt sich für v30 wiederverwenden. DLL bleibt unverändert v10.

## Run27 und Korrekturen in v28

Gesichert unter `logs/run27-stdout.txt`, `run27-proxy.log`, `run27-proxy.status` und `run27-fake-host.log`. Alle 20 Änderungen wurden vom simulierten Gastgeber empfangen. Replay 1–9 gelang: zwei Bahnhöfe, Gleise, Depot, Depotanschluss, Signal, Linie mit Halten und Fahrzeugkauf. Aktion `fh45112-1.10` (`vehicle_update`) scheiterte bei der Linienzuordnung: `action continuation line rejected by game`. Der Fehlerstopp verhinderte korrekt alle abhängigen Folgeaktionen. Die vier Bahnhofserweiterungen (11–14), zusätzlichen Gleise/Abrisse (15–19) und Umbenennung zu `abcd` (20) sind damit noch nicht im Spiel validiert.

- `actions.lua` überträgt jetzt `TRANSPORT_VEHICLE.stopIndex` und verwendet ihn bei `makeVehicleSetLineCmd`. Zuvor war der Zielhalt immer 0; normale Haltwechsel bleiben aus dem Änderungsvergleich ausgeschlossen. Persistierte Folgearbeit behält den Zielhalt; alte Payloads fallen auf 0 zurück. Die fehlende Erfassung ist sicher belegt, ihre Rolle bei genau dieser Ablehnung bleibt bis zum Spieltest eine Hypothese. Neue Ablehnungen loggen Fahrzeug, Linie und Zielhalt.
- `build.lua` bestätigt reinen Abriss durch `entityExists` vor und nach Ausführung. Alle vorgesehenen entfernten IDs müssen verschwunden sein. Null Kosten und Erstattungen funktionieren; No-op, Teilabriss, unbekannter Weltzustand und fehlender Ersatzbau zählen nicht als Erfolg.
- Build-Callbacks geben ausdrücklich `true` zurück, wenn sie die Ergebnisprüfung und Retries selbst übernehmen. `transport.env` setzt dann bei einem zwischenzeitlich abgelehnten Versuch keinen dauerhaften Fehler. Alle erschöpften/asynchronen Ablehnungen sowie Callback-Ausnahmen bleiben Fehler. Der bestehende Bahnhof-`old2new`-Retrytest prüft jetzt auch die echte Transporthülle und `DONE OK`.
- Geldkorrektur im Originaltest scheiterte am Assert `cmd.journalEntry.time == -1`. `sync.journal_entry` setzt diesen Wert explizit und sendet keine Buchung bei nicht beschreibbarem Feld.
- Der Fake-Host protokolliert `REPLAY FAILED at line X of Y` statt mit unbehandelter Exception zu verschwinden. Er beendet sich nach dem Fehler geordnet; keine Folgeaktion wird versandt. Ein UDP-Test mit Spiel-Stub prüft Aufnahme, Reload, Replay, Fehlerstopp, Meldung und geordnetes Prozessende.

Für v28 ist eine **frische Aufnahme** nötig: Das alte A1-Payload enthält den tatsächlichen Zielhalt nicht. TF3 vollständig beenden, über das Testlabor neu installieren/starten, Ausgangsspielstand laden und Änderungen erneut aufnehmen. Danach ohne Speichern den Ausgangsstand laden und den automatischen Nachbau prüfen. Native DLL bleibt unverändert v10.

## Was geändert wurde

- `gui.lua`: Modul-Speicher mit schwachen Umgebungsschlüsseln; kein Schreiben nach `_G`. Bei frischen Lua-Zuständen stellt `sync.speed_step` weiterhin aus `TF3MP_OWN_GUI` wieder her. Ein Test simuliert den globalen Schreibfehler aus beiden run26-Berichten.
- `build.escape`: explizite ASCII-Zeichenklassen statt sprachabhängigem `%w`. Die Umlaut-Regression besteht unter der normalen Windows-Locale.
- Launcher: dunkle Oberfläche, Ansichten Gastgeber/Beitreten/Testlabor, VPN-Adapter mit Namen, erneutes Einlesen der Adressen, kopierbares `IPv4:Port`, direkt einfügbarer Beitritt, Installation und Spielstart mit einem Knopf. Die Welt muss anschließend im Spiel geladen werden. Bestehende Spielstandübertragung und lokale Testwerkzeuge bleiben erhalten.
- Simulierter Gastgeber: versteckter Prozess; Bereitschaft über `PROBE <nonce>` / `READY <nonce> proto=2` am tatsächlichen Port statt Suche nach irgendeinem Prozessnamen. Fehlstart/Portkonflikt verhindert einen scheinbar erfolgreichen Start. Protokoll unter `%TEMP%/tf3mp-fake-<port>.log`.
- `_content.json` enthält die neue `transport.lua`; der Manifest-Test vergleicht alle tatsächlichen Mod-Dateien mit dem Inhaltsverzeichnis.

## Protokoll und Grenzen

Die gemeinsame Obergrenze beträgt **262144 Bytes (256 KiB)** pro B5-/A1-Aktion. Größere Aktionen werden vollständig abgelehnt und gemeldet. B5 lässt Knotenkonfigurationen nicht mehr wegen der Paketgröße weg. Der bestehende Fallback bei unlesbaren Engine-Feldern ist davon unabhängig und bleibt im Erfassungsprotokoll sichtbar.

`transport.lua` zerlegt ausgehende Nachrichten ab 6001 Bytes in `net upload <id> <index> <count> <payload>` mit höchstens 6000 Payload-Bytes. Die DLL setzt sie zusammen. Kurze Aufnahmen behalten `net send`, damit bestehende Aufnahmewerkzeuge funktionieren. `same-spot.ps1` setzt auch Upload-Zeilen wieder zusammen.

Die native Verbindung verwendet unabhängig davon **768 Payload-Bytes pro UDP-Fragment**:

```
FRAG <token> <index> <count> <payload>
PART <token> <index>       Fragment angenommen
GOT <token>              Ganze Nachricht in der Empfangswarteschlange
CHECK <token>            Ergebnis erneut anfordern
DONE <token> OK|FAIL      Ergebnis der Ausführung
RESET <token>            Empfang muss mit Fragment 0 neu beginnen
```

Die Präfixe bleiben `TF3MP/1`, die HELLO-Fähigkeit lautet `proto=2`. Beide PCs brauchen denselben aktuellen Mod (v30) mit DLL v10. Ein alter HELLO-Partner erhält eine sichtbare Versionsfehlermeldung. Das Token-Präfix bleibt über den gesamten Spielprozess stabil, damit die Fahrzeug-/Linienzuordnungen denselben Peer wiederfinden. Ein anderer Endpunkt übernimmt keine aktive Sitzung; nach einer Unterbrechung darf dieselbe IP einen neuen Quellport verwenden. Eine geänderte HELLO-Sitzungskennung verlangt einen gemeinsamen Neustart vom selben Spielstand.

Der Sender gibt eine Aktion **erst bei DONE OK** frei. Empfangsquittungen zählen nicht als Spielergebnis. Der Empfänger hält den Eintrag bis zum Ergebnis; die letzten 128 Ergebnisse bleiben für verlorene Quittungen abfragbar. Nur eine Nachricht je Richtung ist gleichzeitig unterwegs, sodass Fragment- und Ergebniswiederholungen idempotent bleiben. Dies ist keine globale Gastgeber-Reihenfolge für gleichzeitig auf beiden PCs ausgelöste Aktionen.

In der Lua-Brücke steht jeweils `part <token> <kind> <index> <count> <payload>` in `TF3MP_IN`, höchstens 6000 Payload-Bytes. Lua speichert die Teile im Script-State und quittiert `net partreceived`. Erst die vollständige Nachricht wird als Script-Event übergeben. Der Bridge-Poll läuft alle 100 ms, die Simulation liest zwischen ihren normalen Bridge-Ticks nach. Steuerzeilen werden nur direkt hinter `[mp_probe]` erkannt, nicht innerhalb eines protokollierten Namens oder einer Fehlermeldung.

## Ausführung, Fehler und Wiederaufnahme

`transport.lua` speichert aktive Transaktionen im Script-State. Eine lokale API-Hülle zählt tatsächliche `sendCommand`-Callbacks einschließlich der Linien-/Fahrzeug-Folgearbeiten. Abgelehnte Befehle, kritische Ergebnisse, Zuordnungsfehler oder fehlende Events ergeben FAIL. Ohne Simulationsevent wird im regulären Netzwerkpfad kein Bau aus `update()` erzwungen.

Mehrstufige Bauten warten auf die Callbacks der Straßen, setzen und prüfen danach deren Konfigurationen, bauen dann die Konstruktion und prüfen schließlich deren Konfigurationen und den Anschluss. Die spätere Anschlussprüfung wartet weiterhin auf die Engine-Aktualisierung. Ein negativer oder nicht bestätigter Anschluss führt zu FAIL. Die Bestätigung ersetzt keinen vollständigen Vergleich der beiden Weltzustände; die vorhandenen Prüfpunkte vergleichen weiterhin hauptsächlich Zähler, Geld, Datum und Spielzeit.

Jede native Warteschlange hat bis zu 128 Einträge und insgesamt 16 MiB Payload-Speicher. Überlaufende **ausgehende Aufnahmen** kommen geordnet nach `alut_proxy.queue` im Spielordner. Der Bridge-Thread liest weiter, damit Ergebnisrückmeldungen bei beidseitig vollen Warteschlangen verarbeitet werden. Beim Abarbeiten wird zuerst der ältere Rückstau eingereiht. Die Datei wird geleert, sobald der Rückstau abgearbeitet ist. Eine beim nächsten Prozessstart noch gefüllte Datei wird als `alut_pending_<tick>.bin` aufbewahrt und nicht automatisch in eine möglicherweise andere Welt eingespielt. Das Binärformat ist je Datensatz ein DWORD mit der Payload-Länge, gefolgt von den Payload-Bytes.

Netzwerkunterbrechungen bei weiterlaufenden Spielprozessen werden ohne verlorene oder doppelte Aktionen überbrückt. **Prozessneustarts sind keine automatische Wiederherstellung:** Die In-Memory-Warteschlange und Engine-Callbacks überleben sie nicht. Nach einem Fehler müssen beide Spieler einen gemeinsamen aktuellen Spielstand austauschen, beide Spiele beenden und denselben Stand neu starten. Es gibt noch keinen automatischen Resync oder eine komfortable Wiederherstellung einzelner fehlgeschlagener Aktionen.

`net reload` verhindert, dass aus einem neu geladenen Spielstand versehentlich offene Aktionen der vorherigen Welt weiterlaufen. Ausnahme: Im ausdrücklich gewählten `test=samespot` wird der noch unversandte Aufnahmestrom verworfen, weil das Testwerkzeug die Aufnahme aus stdout nach dem Neuladen selbst zurückspielt. Eine bereits laufende empfangene Aktion darf auch dort nicht über einen Reload hinweg weiterlaufen.

`alut_proxy.status` wird laufend geschrieben: PID, Version, Modus, Verbindung, Warteschlangen, Sperre, Fehler und Disk-Rückstau. Der Launcher zeigt den aktuellen Status und erkennt fehlende/veraltete Statusdateien. Die Datei ist eine lokale Anzeige, keine Netzwerk-Sitzungslobby.

## Prüfung

Unter Windows mit der normalen Locale erfolgreich:

- 103 Infrastruktur-/Brückentests, 50 Aktionstests, 34 Abgleichtests, 14 Transporttests: **201 Lua-Tests**.
- **32 Launcher-/Protokolltests**, darunter Adressprüfung, Script-Syntax, Inhaltsmanifest, große Aufnahmen, gespeicherte run29-Aufnahme und deren Prüfung gegen den aktuellen Spielstand und Prozessstart.
- **8 vorhandene Spielstandübertragungstests**.
- UDP-Integrationstest des simulierten Gastgebers: abgelehnte Replay-Aktion wird protokolliert, Folgeaktionen bleiben gestoppt, Prozess endet geordnet für einen Neustart.
- Native Tests gegen den echten `net.c` und `bridge.c`: 256-KiB-Rundlauf, verlorene Fragmente und Quittungen, doppelte Pakete, tatsächliche Ausführungsquittung, Unterbrechung über dem 10-s-Timeout, 140 Aktionen mit Disk-Rückstau, Reihenfolge, Fehlerstopp, Endpunktbindung, Versionsprüfung, Partner-Neustart, Reload-Schutz und Gleiche-Stelle-Ausnahme.
- Launcher-Vorschau für Gastgeber und Beitreten gerendert und visuell geprüft. Der simulierte Gastgeber wurde am ausgewählten Port gestartet, erneut erkannt und auf einem falschen Port nicht fälschlich erkannt.

Ausführen:

```powershell
python tools/run_lua.py tests/run_tests.lua
python tools/run_lua.py tests/run_actions.lua
python tools/run_lua.py tests/run_sync.lua
python tools/run_lua.py tests/run_transport.lua
python tests/run_fake_partner.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_save_transfer.ps1
cmd /c native\alut_proxy\build.bat
cmd /c tests\build_net_tests.bat
python tests/run_net.py
```

Die native Test-DLL wird in temporäre Verzeichnisse kopiert; TF3 wird dabei weder geladen noch verändert. `launcher/bin/alut.dll` muss zur jeweils aktuellen nativen Quelle passen. Nach Änderungen neu bauen und mit der gebauten DLL vergleichen.

## Nächste Arbeit für Claude

Dieser Nachtest ist als run30 erfolgreich: alle 21 Aktionen, einschließlich dreier Bahnhofserweiterungen und Linienumbenennung. Logs: `logs/run30-*`; Nutzer bestätigt den vollständigen sichtbaren Nachbau. Geldkorrektur muss weiterhin nach angenommener Buchung im nächsten Prüfpunkt `adj=5000` erreichen. Große Bahnhöfe/Zugverbände bleiben zusätzlich bis nahe an die neue Grenze zu prüfen. Die weitere Arbeit steht in [phase5-session-world.md](phase5-session-world.md).

Danach der vom Nutzer geplante Test mit zwei PCs im gemeinsamen VPN, identischem Spielstand und identischen Mods. Prüfen: Adresskopie/Beitritt, Spielstandtransfer, beide Baurichtungen, temporäre VPN-Unterbrechung und kontrollierter Fehlerfall. Offene größere Arbeiten bleiben Sitzungs-/Mod-/Save-Kompatibilitätsprüfung, detaillierter Weltvergleich, automatischer Resync, Gastgeber-Reihenfolge und Tick-Koordination. Keine dieser Funktionen wird durch die neue Empfangs-/Ausführungsquittung ersetzt.

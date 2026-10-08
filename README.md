# Transport Fever 3 Multiplayer

Experimenteller Community-Mod für zwei PCs: Straßen, Gleise, Haltestellen, Signale, Bahnhöfe, Depots, Abriss, Linien und Fahrzeuge werden zwischen zwei Spielen gespiegelt. Aktueller Stand: **Probe v31 / DLL v11**. v30 hat alle 21 aufgenommenen Aktionen im Spiel erfolgreich nachgebaut, einschließlich Bahnhofserweiterungen und Linienumbenennung. v31 ergänzt die gemeinsame Startprüfung und einen genaueren Weltvergleich; der Test mit zwei PCs steht aus.

## Starten über euer gemeinsames VPN

1. Dasselbe Paket auf beide PCs kopieren und entpacken, beide mit dem VPN verbinden, TF3 beenden und `Start.bat` öffnen. Das portable Paket liegt unter `release/TF3-Multiplayer-v31-Windows.zip`.
2. Gastgeber: **Gastgeber** auswählen, die Adresse des VPN-Adapters wählen und **Adresse kopieren**. Den Mitspieler diese Adresse einfügen lassen. **Als Gastgeber starten** bietet beim ersten Start die Auswahl eines Spielstands aus dem aktuellen Steam-Spielstandordner an und wartet auf den Mitspieler.
3. Mitspieler: **Beitreten** wählen, die kopierte Adresse einfügen (z. B. `100.80.12.4:47800`) und **Beitreten und Spiel starten** klicken. Der Launcher holt den Spielstand, vergleicht Spielversion, Multiplayer-Paket und zusätzliche Mods und bereitet eine gemeinsame Sitzung vor. Unterschiedliche Dateien werden konkret gemeldet. Auch installierte inaktive Zusatzmods werden verglichen.
4. Nach erfolgreicher Übertragung installieren beide Launcher den Mod und starten TF3. Beide laden den angezeigten Spielstand pausiert. Die Verbindung wartet auf den vereinbarten Stand auf beiden PCs; danach gemeinsam fortsetzen. Die Welt muss im Spiel selbst geladen werden.
5. Der Launcher zeigt Verbindung, ausstehende Aktionen, Weltprüfung und Fehler an. **Details prüfen** öffnet die letzten Meldungen. Ein späterer Start kann die vorbereitete Sitzung verwenden, solange ihre Dateien unverändert sind und beide wieder denselben Ausgangsstand laden.

Standard: UDP 47800 für Spieldaten und TCP 47800 für den Spielstand. Die Windows-Firewall muss TF3 und die Spielstandübertragung über den verwendeten VPN-Adapter zulassen. Im gemeinsamen VPN wird die erreichbare VPN-IPv4 des Gastgebers verwendet; eine Router-Portfreigabe ist dafür nicht erforderlich. **Mod entfernen** stellt die gesicherte Original-DLL wieder her.

## Neu in v31

- Gemeinsame Sitzungskennung und SHA-256-Prüfung von TF3, Multiplayer-Paket, zusätzlichen Moddateien und Ausgangsspielstand. Veränderte Dateien werden vor dem Start erneut erkannt.
- Die DLL prüft die Sitzung auf beiden PCs und wartet auf den richtigen geladenen Spielstand. Ein erneutes Laden oder Partnerneustart verlangt eine neue gemeinsame Vorbereitung.
- Vier Weltprüfsummen vergleichen Gebäude samt Modulen, Straßen/Gleise, Linien und Fahrzeuge. Gleiche Anzahlen mit anderem Inhalt werden erkannt. Anhaltende Unterschiede erscheinen nach zwei aufeinanderfolgenden Prüfpunkten; fehlende Lesezugriffe gelten als unbekannt.
- **Neu abgleichen** führt durch einen neuen gemeinsamen Spielstand: Gastgeber speichert, beide beenden TF3, teilen/holen den Stand und starten eine neue Sitzung. Speichern und Laden erfolgen weiterhin im Spiel.

Aktuelle Übergabe, Grenzen und VPN-Testablauf: [docs/phase5-session-world.md](docs/phase5-session-world.md).

## Korrekturen in v30

Run29 hat Abriss, Linienänderung, Gleise, beide Bahnhöfe, Depot und Signal erfolgreich nachgespielt (11 Aktionen). Die erste Bahnhofserweiterung scheiterte danach mit „Bau nicht möglich“; spätere Aktionen blieben deshalb stehen.

- Reine Erweiterungen einer bestehenden Konstruktion verwenden jetzt denselben Ersatzvorschlag-Generator wie die originale Spieloberfläche: `createProposalReplaceConstruction`. Damit verwaltet die Engine die vorhandenen Anschlussknoten und die vollständige Moduländerung.
- Die vom Ersatzvorschlag erzeugten Konfigurationen werden anschließend geprüft. Es wird kein zweiter Bau oder Überschreiben der Anschlusskonfigurationen ausgelöst.
- Abgelehnte Ersatzvorschläge bleiben ein sichtbarer Fehler. Run30 bestätigt den anschließenden Gleisbau und alle 21 Aktionen; die drei Bahnhofserweiterungen wurden mit erhaltenem Anschluss ausgeführt.

Die letzte Aufnahme kann mit `Test-letzte-Aufnahme.bat` wiederholt werden. TF3 vollständig beenden, den Starter öffnen und **Test starten** wählen. Im Spiel den ursprünglichen Stand **Det** vor den Änderungen laden und die Zeit laufen lassen. Danach im Launcher **Am selben Ort nachbauen** klicken. Die 21 gespeicherten Aktionen werden erneut ausgeführt; eine neue Bauaufnahme ist dafür nicht nötig. Der Launcher prüft den aktuell geladenen Spielstand anhand des neuen Spielprotokolls.

## Korrekturen in v29

Run28 hat 26 Aktionen aufgezeichnet. Bereits der erste Abriss wurde ausgeführt, aber von unserer Erfolgskontrolle fälschlich abgelehnt. Folgeaktionen blieben dadurch stehen.

- Abrissprüfung unterstützt die aufrufbaren API-Tabellen von TF3; Fehlermeldungen nennen jetzt die betroffene Entity und den Prüfungsfehler.
- Bahnhofserweiterungen behalten ihren Eintrag im Konstruktionscache, auch wenn die Engine dieselbe ID erneut verwendet. Dadurch werden weitere Erweiterungen vollständig aufgezeichnet.
- Linien behalten gelöschte Halte als ungültigen Platzhalter am bisherigen Index. Fehlende gültige Stationen bleiben ein Fehler.

Für den damaligen v29-Spieltest war eine **frische Aufnahme** nötig, da run28 bei mehreren Bahnhofserweiterungen die zu ersetzende Konstruktion nicht vollständig aufgezeichnet hat. Die inzwischen gesicherte run29-Aufnahme enthält diese Angaben und kann für v30 wiederverwendet werden.

## Korrekturen in v28

Run27 hat alle 20 Aktionen aufgezeichnet. Beim Nachspielen scheiterte die Zugzuordnung zur Linie (Aktion 10); Bahnhofserweiterung, zusätzliche Gleise, Abriss und Umbenennung wurden deshalb noch nicht ausgeführt.

- Fahrzeugzuordnungen übertragen den tatsächlichen Zielhalt statt immer Halt 0. Alte Aufnahmen enthalten diesen Wert nicht; für den erneuten Test eine frische Aufnahme erstellen.
- Ein erfolgreicher Bau-Retry gibt Folgeaktionen frei. Reiner Abriss wird anhand der tatsächlich verschwundenen Objekte bestätigt, auch bei null Kosten oder einer Erstattung.
- Geld- und Kreditkorrekturen setzen den von der Engine verlangten Buchungszeitwert `-1`.
- Der simulierte Gastgeber protokolliert abgelehnte Aktionen mit ihrer Position und beendet sich geordnet, damit er für den nächsten Versuch neu gestartet werden kann.

## Änderungen in v27 / v10

- GUI-Speicher ohne verbotene globale Variablen; sprachunabhängige UTF-8-Kodierung.
- Simulierter Gastgeber wird am richtigen UDP-Port auf Bereitschaft geprüft und im Hintergrund gestartet.
- Nachrichten bis **256 KiB**, zerlegt in kleine UDP-Pakete; auch die Lua/DLL-Brücke übergibt große Aktionen in begrenzten Stücken. Knotenkonfigurationen werden bei Größenüberschreitung nicht still weggelassen.
- Empfang und Ausführung sind getrennt: Erst ein positives Spielergebnis gibt die nächste Aktion frei. Mehrstufige Bauaktionen warten auf ihre vorherigen Befehle und prüfen anschließend Knotenkonfigurationen und Anschlüsse.
- Geordnete Wiederaufnahme nach Netzwerkunterbrechungen innerhalb derselben Spielprozesse. Volle Warteschlangen lagern weitere Aufnahmen auf den Datenträger aus.
- Bei abgelehnten Aktionen, Partner-Neustart oder Neuladen mit offenen Aktionen wird ein Abgleich verlangt. Beide Spiele dann beenden und vom gemeinsamen Spielstand neu starten. Automatischer Wiederabgleich nach Prozessneustart ist noch offen.

Frühere Transport-Korrekturen: [docs/phase4-reliable-transport.md](docs/phase4-reliable-transport.md). Frühere Spielnachweise: [docs/phase1-bridge.md](docs/phase1-bridge.md). Der übergeordnete Forschungsplan steht in [docs/plan.md](docs/plan.md).

## Tests auf einem PC

Im **Testlabor** bleiben Allein-Test (100 m daneben), Gleiche-Stelle-Test nach Neuladen und simulierter Gastgeber verfügbar. Diese Tests ersetzen den späteren gemeinsamen VPN-Spieltest nicht.

Offline-Tests mit Lua oder Python/lupa:

```powershell
python tools/run_lua.py tests/run_tests.lua
python tools/run_lua.py tests/run_actions.lua
python tools/run_lua.py tests/run_sync.lua
python tools/run_lua.py tests/run_transport.lua
python tools/run_lua.py tests/run_fingerprint.lua
python tests/run_fake_partner.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_save_transfer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_session.ps1
```

Native DLL und Netzwerktests bauen (Visual Studio C++ x64):

```powershell
cmd /c native\alut_proxy\build.bat
cmd /c tests\build_net_tests.bat
python tests/run_net.py
```

Der Launcher enthält die fertig gebaute DLL in `launcher/bin/alut.dll`; zum Einrichten ist Visual Studio nicht nötig.

Dieses Projekt ist nicht mit Urban Games oder Paradox Interactive verbunden.

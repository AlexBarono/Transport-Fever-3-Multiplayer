# Übergabe: Probe v31 / Proxy v11

Stand: 8. Oktober 2026. Der Nutzer hat Run30 im Spiel bestätigt: Alle 21 Aktionen wurden nachgebaut, die Linie wurde erstellt und umbenannt, die Bahnhöfe wurden erweitert und anschließende Gleisarbeiten ausgeführt. Die zugehörigen Protokolle liegen unter `logs/run30-stdout.txt`, `run30-proxy.log` und `run30-proxy.status`; alle 21 Ausführungsquittungen sind OK. Die neuen v31-Funktionen sind offline geprüft. Der gemeinsame VPN-Spieltest steht noch aus.

Die Änderungen liegen ohne neue Commits im gemeinsamen Arbeitsverzeichnis. Grundlage bleibt Claudes Commit `3009beb`. Es wurden weder TF3 gestartet noch Dateien der installierten Spielversion verändert. Das portable Testpaket ist `release/TF3-Multiplayer-v31-Windows.zip`; beide PCs benötigen dasselbe Paket.

## Gemeinsamer Startstand

`tools/session.ps1` bildet SHA-256-Fingerabdrücke der Spiel-EXE, des vollständigen Multiplayer-Mods samt DLL, der zusätzlichen installierten Mods und der ausgewählten SAV-Datei. Absolute Benutzerpfade und Änderungszeiten gehören nicht zu den Fingerabdrücken. Auch installierte inaktive Zusatzmods werden verglichen; die mitgelieferten `urbangames_*`, der eigene Probe-Mod und Textur-Caches werden aus der Zusatzmodliste ausgenommen. Eine abweichende Modliste wird konkret aufgeschlüsselt. Das ist eine konservative Dateiprüfung, keine Analyse der tatsächlich aktiven Modauswahl im gespeicherten Spiel.

Der Launcher wählt den Spielstandordner des aktuell angemeldeten Steam-Kontos. Bei mehreren Konten ohne eindeutig ermittelbares aktives Konto verlangt er eine eindeutige Steam-Anmeldung. Der Gastgeber muss die SAV-Datei direkt aus diesem Ordner auswählen; eine gleichnamige externe Sicherung genügt nicht. Diese Bindung wird vor dem späteren Start erneut geprüft. OneDrive-Platzhalter mit gesetztem ReparsePoint-Attribut sind zulässig, tatsächliche symbolische Verknüpfungen und Junctions werden abgelehnt.

Die Spielstandübertragung verwendet für normale Sitzungen `TF3MPSAVE2`: begrenzte UTF-8-Metadaten, Kompatibilitätsprüfung durch den Empfänger vor dem Schreiben und Prüfung des empfangenen Spielstandhashs vor der Übernahme. Erst nach erfolgreicher Übertragung und Bestätigung speichern beide Launcher `alut_session.json` mit gemeinsamer Sitzungskennung und lokalem Spielstandpfad. Bestehende Sicherung und Ablehnung des Überschreibens bleiben erhalten. Der alte Transfermodus bleibt nur für Aufrufe ohne Sitzungsmetadaten verfügbar.

Vor Installation und Spielstart prüft der Launcher die vorbereitete Sitzung erneut. Beim direkten Spielstart werden zusätzlich die installierten Moddateien, DLL und Sitzungsfelder der INI gegen die vorbereitete Sitzung geprüft. Die großen Startknöpfe führen bei fehlender Vorbereitung durch Teilen beziehungsweise Holen des Spielstands und starten danach das Spiel. Die Welt laden beide Spieler weiterhin selbst im Spiel.

### Abbrüche bei der Spielstandübertragung (8. Oktober 2026)

Erster VPN-Versuch: Der Gastgeber sah nur „Ausnahme beim Aufrufen von Write mit 3 Argument(en) … vom Remotehost geschlossen“. Der Mitspieler hatte die Verbindung mitten im Dateiversand geschlossen; seine Begründung ging verloren, weil er sofort schloss (Windows setzt die Verbindung dann hart zurück) und der Gastgeber nur schrieb, nicht las. Seitdem:

- Der Mitspieler schickt bei einem endgültigen Fehler Byte 0 plus Grund, schließt nur seine Senderichtung und liest bis zu 3 s weiter. Der Gastgeber prüft nach jedem Block, ob eine Antwort vorliegt, und zeigt „Der Mitspieler hat die Übertragung abgebrochen: <Grund>“.
- Netzwerkabbrüche (getrennte Verbindung, Zeitüberschreitung, beschädigt angekommene Datei) sind keine Endgültigkeit mehr: Der Gastgeber wartet auf den nächsten Versuch, der Mitspieler verbindet sich nach 3 s selbst neu, bis zu 5 Versuche. Teildateien werden dabei gelöscht.
- Statt der rohen .NET-Meldung erscheint ein deutscher Text mit den häufigen Ursachen. Das Übertragungsformat ist unverändert; ältere Launcher bleiben verträglich, zeigen aber selbst noch die alten Meldungen.
- Tests: `tests/run_save_transfer.ps1` stellt den ursprünglichen Fehler nach (Abbruch mitten in einer 40-MB-Datei, harter Verbindungsabbruch, Neuversuch von beiden Seiten).

## Freigabe durch die DLL

Die native DLL v11 verlangt bei normalen Gastgeber-/Beitreten-Sitzungen HELLO-Protokoll 3 mit passender Sitzungskennung sowie Spiel-, Paket-, Mod- und Spielstandhash. Beide Seiten müssen den vereinbarten Spielstand geladen und ihre Lua-Initialisierung abgeschlossen haben, bevor Spielnachrichten ausgetauscht werden. Die DLL erkennt den geladenen Namen anhand der originalen Ladezeile im aktuellen Spielprotokoll. Der Spielstandinhalt wird unmittelbar vor dem Start vom Launcher geprüft; die DLL dekodiert den geladenen Weltinhalt nicht erneut aus der Engine.

Fehlende oder widersprüchliche Sitzungsfelder, alte Protokollpartner, erneutes Laden oder ein Partnerneustart sperren die Sitzung sichtbar. Eine bloße Netzwerkunterbrechung bei weiterlaufenden Prozessen behält die Warteschlangen und kann die bestehende Sitzung fortsetzen. Bereits an die Engine übergebene Befehle lassen sich bei einer späteren Sperre nicht zurückholen. Die lokalen Testarten verwenden ausdrücklich weiterhin Protokoll 2.

## Weltvergleich

`fingerprint.lua` liest alle 60 Sekunden Spielzeit vier Gruppen frisch aus: Konstruktionen samt Parametern/Modulen und Transformation, Straßen/Gleise samt Geometrie und Konfiguration, Linien samt Name und Haltefolge sowie Fahrzeuge samt Konfiguration und Zuordnung. Die Hashes heißen `hcon`, `hedge`, `hline` und `hveh`. Sie entfernen lokale Entity-IDs, ordnen ungeordnete Datensätze stabil, berücksichtigen doppelte Datensätze und normalisieren räumliche Fließkommawerte auf 0,001. Sie funktionieren unter Lua 5.2 und 5.4.

Unvollständige oder fehlgeschlagene Lesezugriffe liefern für die betroffene Gruppe keinen gültigen Hash. Ein alter Snapshot wird nicht als aktueller Gleichstand ausgegeben. Unterschiede werden zunächst als laufende Prüfung angezeigt; derselbe Gruppenunterschied an zwei direkt aufeinanderfolgenden gemeinsamen Prüfpunkten wird als Weltabweichung gemeldet. Der Launcher zeigt Gleichstand nur an, wenn alle vier Gruppen vergleichbar sind. Ein bestätigter Gleichstand umfasst diese geprüften Daten, nicht die gesamte Simulation.

Nicht vollständig erfasst sind insbesondere Fahrzeugpositionen während der Fahrt, Ladung, Stadtbevölkerung und sämtliche Detailzustände der Simulation. Der Weltvergleich ersetzt weder tickgenaue Ausführung noch einen Determinismusnachweis. Laufzeit und Abdeckung auf großen echten Karten müssen noch geprüft werden.

## Geführter Neuabgleich

Die Schaltfläche **Neu abgleichen** erklärt den Ablauf passend zur Rolle: Gastgeber speichert den gewünschten gemeinsamen Stand pausiert, beide beenden TF3, Gastgeber teilt und Mitspieler holt den aktuellen Stand. Dabei entsteht eine neue Sitzungskennung. Beide starten anschließend und laden wieder denselben Stand pausiert. Sobald ein Neuabgleich begonnen wurde, lässt sich die alte Vorbereitung im geöffneten Launcher nicht versehentlich weiterverwenden.

Speichern, Beenden und Laden bleiben manuelle Schritte. Es gibt noch keinen automatischen Resync im laufenden Spiel. Eine Weltabweichung wird angezeigt und führt zum angebotenen Neuabgleich; sie löst keine automatische Änderung einer Spielwelt aus.

## Prüfung und Paket

- 225 Lua-Prüfungen bestanden: 104 Infrastruktur, 50 Aktionen, 14 Transport, 20 Weltfingerabdrücke und 37 Synchronisation. Fingerabdrücke und Synchronisation zusätzlich unter Lua 5.2 geprüft.
- 46 Launcher-Prüfungen, 10 Sitzungsprüfungen und 19 Spielstandtransfer-Prüfungen bestanden. Dazu gehören geänderte Dateien, falsche installierte Sitzung, externe gleichnamige SAV-Dateien, Kontenauswahl und OneDrive-Dateien.
- Zehn Gruppen nativer Integrationstests bestanden: Sitzungsfreigabe, falsche Spielstände, Neustart/Laden, Paketverlust, 256-KiB-Nachrichten, Wiederverbindung, Fehlerstopp und 140 geordnete Aktionen mit Dateirückstau.
- Der UDP-Test des simulierten Gastgebers prüft, dass eine fehlgeschlagene Aktion Folgeaktionen stoppt und der Hilfsprozess geordnet beendet wird.
- Die Produktions-DLL wurde frisch gebaut und mit `launcher/bin/alut.dll` abgeglichen. SHA-256: `7fe6ef6a631d88a3440544b986ad7c81eda2859fece4a796c48fcdf2431befc3`.

`tools/package.ps1` erzeugt im Entwicklungsprojekt das portable ZIP aus ausdrücklich ausgewählten Launcher-, Mod-, Hilfs- und Dokumentationsdateien. Es prüft Versionen, Mod-Inhaltsverzeichnis und DLL-Gleichheit und verifiziert jeden ZIP-Eintrag gegen die Quelle. Es enthält keine Spiel-EXE, persönlichen Spielstände oder Entwicklungs-Builds. Die Aufnahme Run29 liegt bei, damit `Test-letzte-Aufnahme.bat` weiter funktioniert. Zum Benutzen ist Visual Studio nicht erforderlich; ein erneuter Paketbau benötigt das Entwicklungsprojekt samt nativer Build-Ausgabe.

## Nächster Zwei-PC-Test im gemeinsamen VPN

1. Beide entpacken dasselbe v31-Paket, verbinden das VPN und beenden TF3. Gastgeber öffnet `Start.bat`, wählt **Gastgeber**, kopiert die VPN-Adresse und klickt **Als Gastgeber starten**. Einen kleinen vorhandenen Testspielstand auswählen.
2. Mitspieler öffnet `Start.bat`, wählt **Beitreten**, fügt die Adresse ein und klickt **Beitreten und Spiel starten**. Übertragung und Versionsprüfung müssen erfolgreich enden. Beide laden den angezeigten Spielstand pausiert; danach gemeinsam fortsetzen.
3. Zunächst baut jeweils nur einer: Gleis, Bahnhof, Bahnhofserweiterung, zusätzliche Gleise, Abriss, Depot, Linie, Fahrzeug und Linienumbenennung. Danach dieselbe Richtung vom zweiten PC aus prüfen. Die Änderungen müssen vollständig erscheinen und die Aktionswarteschlange muss leer werden.
4. Nach abgearbeiteten Aktionen keine weiteren Änderungen durchführen und mehrere Prüfintervalle bei laufender Spielzeit abwarten. Im Launcher sollen alle vier Weltgruppen übereinstimmen. Bei **unbekannt**, anhaltender Prüfung oder Abweichung die Details und beide Protokolle aufbewahren.
5. Eine kurze VPN-Unterbrechung bei weiterlaufenden Spielprozessen testen. Nach Wiederverbindung müssen ausstehende Aktionen ohne doppelte Bauten weiterlaufen. Ein Spielprozessneustart soll dagegen einen Neuabgleich verlangen.
6. **Neu abgleichen** mit einem eigens gespeicherten Teststand ausprobieren: speichern, beide Spiele beenden, neu teilen/holen, beide neu starten und denselben Stand laden. Danach wieder eine einzelne Bauaktion in jeder Richtung prüfen.

Optionaler Fehlertest mit einer Sicherung: absichtlich unterschiedliche Zusatzmoddateien müssen vor dem Start eine konkrete Ablehnung ergeben. Ein anderer geladener Spielstand muss die Sitzung sperren. Keine persönlichen Hauptspielstände für diese Fehlertests verwenden.

## Danach offen

Priorität haben zunächst dieser gemeinsame Spieltest und die Messung auf großen Karten. Die nächsten Implementierungen sind eine Gastgeber-Reihenfolge für gleichzeitig ausgelöste Aktionen, gemeinsame Tick-/Pausensteuerung und automatisches Speichern/Laden für einen Resync. Zuverlässige Übertragung allein garantiert noch keine deterministische Simulation auf beiden PCs. Weitere Weltbereiche können erst mit überprüften Engine-Lesezugriffen in die Inhaltsprüfung aufgenommen werden.

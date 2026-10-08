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

### Depot vom anderen PC (8. Oktober 2026, run31 bis run33)

Der erste Zwei-PC-Test mit Bauaktionen: Ein Straßendepot an einer bestehenden Straße wurde auf dem anderen PC nicht richtig übernommen, in beiden Richtungen.

- run31: Der Gastgeber lehnte das Depot des Mitspielers ab („game rejected … node configurations could not all be resolved“). Zwei Knotenkonfigurationen nannten die Zufahrt, die das Depot selbst legt und die deshalb nicht mitgebaut wird. Behoben in `51a6635`: `build.drop_access` merkt sich diese Zufahrt, `nodecfg.resolve` überlässt die zugehörigen Konfigurationen dem Depot. run33 bestätigt das („4/5 placed … 1 left to the entrance“).
- run32 und run33: Straße und Depot wurden gebaut, danach geschah nichts mehr. Die Zufahrt wurde nie an die Straße angeschlossen, keine Seite bekam eine Ausführungsquittung, beide Warteschlangen standen still und der Weltvergleich meldete eine Abweichung. Jede Stufe des Depotnachbaus wartete darauf, dass `update()` (Sim-Pool-Zustand) das Ende der vorigen Stufe sieht und das nächste Event schickt. Nach der Depotstufe kam dieses Event in beiden Läufen nicht mehr. Der Versuch in `bdc8cd3`, die Übergabe in `update()` abzusichern, half nicht (run33).
- Jetzt laufen die Stufen direkt nacheinander in demselben Event: Straßen, deren Konfigurationen, Prüfung, Depot, Anschluss der Zufahrt, Prüfung. So hat es v22 bis v26 schon gemacht (run23/24). TF3 ruft die Bau-Callbacks auf, bevor `sendCommand` zurückkehrt. Nur wenn ein Callback noch aussteht, bleibt der Rest wie bisher `update()` und dem nächsten Event überlassen.
- Der Gastgeber spielte in run33 pausiert. Die spätere Anschlussprüfung war nach 4 s Spielzeit fällig und wäre bei Pause nie gekommen. Sie ist jetzt auch nach 20 Aufrufen von `update()` fällig; die laufen bei Pause weiter.
- Neue Logzeilen: `net step <token>: <Stufe>` bei jeder Stufe, und alle 50 Updates `net waiting <token>: …`, solange eine empfangene Aktion noch nicht quittiert ist. Damit zeigt das Protokoll, worauf eine hängende Aktion wartet.
- Test: `tests/fixtures/run33-road-depot.b5` ist die echte Depotzeile aus run33 und läuft im Offline-Test bei pausierter Spielzeit vollständig bis zur Quittung.
- run34: Das Depot des Mitspielers wurde jetzt angeschlossen und quittiert („net result … OK“). Danach blieb die Aktion aber offen: Die Quittung kam aus `update()`, und der Schutz aus `bdc8cd3` schrieb bei jedem Speichern aus `update()` die offene Aktion zurück. Die Quittung wurde bei jedem Update erneut geloggt, und die nächste Aktion des Mitspielers (eine Linie) wurde nie angenommen („1 Vorgang wartet“). Danach liefen die Welten auseinander. Behoben: `main.store` übernimmt beim Speichern aus `update()` die Quittungsfelder immer aus dem aktuellen Zustand; `update()` ändert sie selbst nur noch über `transport.fail`/`transport.check` und das direkte Setzen der Anfrage im aktuellen Zustand. Der Depot-Test prüft jetzt, dass genau eine Quittung kommt und die nächste Aktion gebaut wird.

### Weltvergleich: welche Teile abweichen

run34 meldete „Weltabweichung (hcon,hedge)“ schon kurz nach dem Depot, das Protokoll zeigte aber nur die beiden Prüfsummen. Ab jetzt schickt jedes Spiel nach einer bestätigten Abweichung seine Einträge der betroffenen Gruppe an das andere (`W1 <Feld> <Teil> <Teile> <Prüfsumme> <Anzahl> <Hash>:<Beschreibung> …`, je Teil höchstens 5800 Bytes, also eine Bridge-Zeile). Der Empfänger loggt `world diff <Feld> only in this game: …` und `world diff <Feld> only in the other game: …` mit Datei, Position, Name und Kurzprüfsummen von Parametern und Drehung bzw. Straßentyp, Endpunkten und Tangenten. So zeigt schon das Protokoll eines PCs beide Seiten. Jede Liste geht pro Feld und eigener Prüfsumme nur einmal hinaus. W1-Zeilen werden ausgeführt wie Aktionen (Quittung OK), bauen aber nichts; `tools/same-spot.ps1` übergeht sie.

## Freigabe durch die DLL

Die native DLL v11 verlangt bei normalen Gastgeber-/Beitreten-Sitzungen HELLO-Protokoll 3 mit passender Sitzungskennung sowie Spiel-, Paket-, Mod- und Spielstandhash. Beide Seiten müssen den vereinbarten Spielstand geladen und ihre Lua-Initialisierung abgeschlossen haben, bevor Spielnachrichten ausgetauscht werden. Die DLL erkennt den geladenen Namen anhand der originalen Ladezeile im aktuellen Spielprotokoll. Der Spielstandinhalt wird unmittelbar vor dem Start vom Launcher geprüft; die DLL dekodiert den geladenen Weltinhalt nicht erneut aus der Engine.

Fehlende oder widersprüchliche Sitzungsfelder, alte Protokollpartner, erneutes Laden oder ein Partnerneustart sperren die Sitzung sichtbar. Eine bloße Netzwerkunterbrechung bei weiterlaufenden Prozessen behält die Warteschlangen und kann die bestehende Sitzung fortsetzen. Bereits an die Engine übergebene Befehle lassen sich bei einer späteren Sperre nicht zurückholen. Die lokalen Testarten verwenden ausdrücklich weiterhin Protokoll 2.

## Weltvergleich

`fingerprint.lua` liest alle 60 Sekunden Spielzeit vier Gruppen frisch aus: Konstruktionen samt Parametern/Modulen und Transformation, Straßen/Gleise samt Geometrie und Konfiguration, Linien samt Name und Haltefolge sowie Fahrzeuge samt Konfiguration und Zuordnung. Die Hashes heißen `hcon`, `hedge`, `hline` und `hveh`. Sie entfernen lokale Entity-IDs, ordnen ungeordnete Datensätze stabil, berücksichtigen doppelte Datensätze und normalisieren räumliche Fließkommawerte auf 0,001. Sie funktionieren unter Lua 5.2 und 5.4.

Unvollständige oder fehlgeschlagene Lesezugriffe liefern für die betroffene Gruppe keinen gültigen Hash. Ein alter Snapshot wird nicht als aktueller Gleichstand ausgegeben. Unterschiede werden zunächst als laufende Prüfung angezeigt; derselbe Gruppenunterschied an zwei direkt aufeinanderfolgenden gemeinsamen Prüfpunkten wird als Weltabweichung gemeldet. Der Launcher zeigt Gleichstand nur an, wenn alle vier Gruppen vergleichbar sind. Ein bestätigter Gleichstand umfasst diese geprüften Daten, nicht die gesamte Simulation.

Nicht vollständig erfasst sind insbesondere Fahrzeugpositionen während der Fahrt, Ladung, Stadtbevölkerung und sämtliche Detailzustände der Simulation. Der Weltvergleich ersetzt weder tickgenaue Ausführung noch einen Determinismusnachweis. Laufzeit und Abdeckung auf großen echten Karten müssen noch geprüft werden.

## Geführter Neuabgleich

Seit v32 ist **Neu abgleichen** ein Klick auf jedem PC:

- Meldet der Weltvergleich eine Abweichung (`health … status=diff`), speichert das GUI-Skript des Gastgebers das Spiel mit `app.saveGame` als `TF3MP-Neuabgleich`, danach höchstens alle drei Prüfpunkte erneut (`gui.lua`, `net state resync ck=N`). Ob TF3 das einem Mod erlaubt, ist noch ungetestet; das Protokoll zeigt `resync: saved …` oder `resync: … save by hand`.
- Gastgeber: Der Launcher nimmt den neuesten Spielstand, der seit dem Start von TF3 geschrieben wurde, und fragt einmal nach (Ja: nehmen, Nein: jetzt neu speichern, der Launcher erkennt die neue Datei selbst). Er wartet, bis die Datei fertig geschrieben ist, beendet TF3 (nach 20 Sekunden auf Nachfrage hart), schickt den Stand, richtet die neue Sitzung ein und startet TF3 neu.
- Mitspieler: Nach einer Rückfrage beendet der Launcher TF3 und wartet bis zu 10 Minuten auf den Gastgeber (`Receive-Savegame -WaitSeconds`). Ein gleichnamiger Spielstand wird ohne Rückfrage ersetzt und bleibt als `.bak` erhalten. Danach richtet er die Sitzung ein und startet TF3 neu.
- Laden bleibt ein Handgriff im Spiel: Beide laden den genannten Stand pausiert und setzen gemeinsam fort. Die Hilfen dafür stehen in `tools/resync.ps1` (Test: `tests/run_resync.ps1`).

Der Ablauf wurde ohne Windows mit zwei simulierten PCs durchgespielt (Ersatz-Dialoge, ein Ersatzprozess als TF3): Mitspieler klickt zuerst und wartet, Gastgeber nimmt den Stand des Mods oder speichert neu, Abbrechen lässt alles unverändert. Im echten Spiel ist er noch nicht getestet. Eine Weltabweichung ändert weiterhin keine Spielwelt von selbst.

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
6. **Neu abgleichen** (v32) ausprobieren: Beide klicken im laufenden Spiel **Neu abgleichen**. TF3 muss sich auf beiden PCs beenden und neu starten, danach laden beide den genannten Stand pausiert. Danach wieder eine einzelne Bauaktion in jeder Richtung prüfen.

Optionaler Fehlertest mit einer Sicherung: absichtlich unterschiedliche Zusatzmoddateien müssen vor dem Start eine konkrete Ablehnung ergeben. Ein anderer geladener Spielstand muss die Sitzung sperren. Keine persönlichen Hauptspielstände für diese Fehlertests verwenden.

## Danach offen

Priorität haben zunächst dieser gemeinsame Spieltest und die Messung auf großen Karten. Die nächsten Implementierungen sind eine Gastgeber-Reihenfolge für gleichzeitig ausgelöste Aktionen, gemeinsame Tick-/Pausensteuerung und automatisches Speichern/Laden für einen Resync. Zuverlässige Übertragung allein garantiert noch keine deterministische Simulation auf beiden PCs. Weitere Weltbereiche können erst mit überprüften Engine-Lesezugriffen in die Inhaltsprüfung aufgenommen werden.

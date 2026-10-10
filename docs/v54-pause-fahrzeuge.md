# v54: Pause nach Neuabgleich und langsame Fahrzeugbefehle

## Befund aus dem echten Lauf vom 10. Oktober 2026

Ausgewertet wurden der lokale Launcher, die Bridge und `crash_dump/stdout.txt`. Die Bridge/Launcher-Zeiten sind Ortszeit, die Spielausgaben UTC. Das Protokoll des anderen PCs liegt hier nicht vor.

- **23:13:41:** Der andere PC meldet für `scheduled_host.2` eine fehlende Fahrzeugreferenz bei der Zuweisung von Straßenfahrzeug 28. Die einzelne Aktion wurde übersprungen. Weshalb dieses Fahrzeug dort zuvor fehlte, ist ohne dessen Protokoll nicht vollständig nachweisbar.
- **23:25:10:** Eine Linienänderung vom anderen PC wird hier wegen `line reference not found` übersprungen. Auch diese Ablehnung allein blockierte die Sitzung nicht.
- **Nach Neuabgleich:** Der Gastgeber veröffentlichte weiter seinen gespeicherten Zeitplanzähler 2, der Mitspieler bereits Zähler 0. Im Code wurde der neue Ladezustand nur in einer Kopie zurückgesetzt; `main.store` setzte anschließend den alten Live-Zeitplan und die Ausführungsbestätigung wieder ein. Beim Mitspieler wurde der kopierte Gastgeber-Zeitplan zusätzlich wegen der anderen Rolle neu angelegt. So entstanden unterschiedliche Zähler.
- **23:29:02–23:29:03:** Fünf Straßenfahrzeuge sollten auf die Linie „Salzk. Lippstadt 2“. Der Gastgeber sendete Plan 3; der Mitspieler meldete `FAIL` für `54592-969346646.8`. Die native Warteschlange blockierte danach mit `peer rejected`. Die unterschiedlichen Planzähler erklären diese Protokollablehnung; der genaue dortige Lua-Fehler ist ohne Mitspielerprotokoll nicht belegt.
- **Nach Neuabgleich 23:31:** Die native Verbindung war wieder bereit. Der Gastgeber veröffentlichte ab 23:32:06 trotzdem den alten Plan 3 mit `at=8194400`, `phase=prepared`, `hold=1`. Dieser Plan war bereits in dem nun geladenen Spielstand gespeichert. Das erklärt die erneute Pause trotz grüner Verbindung und fehlender neuer Fehlermeldung.
- Unabhängig davon konnte die Veröffentlichung von `phase=idle hold=0` auf einen späteren Updatezähler warten. Steht die Simulation, kann dieser Zähler ausbleiben. Eine bereits erledigte Aktion ließ dadurch die GUI-Sperre bestehen.
- Große Spielzeitabstände waren real vorhanden: einmal **1402 Spielsekunden**. Ein Plan auf `max(beide Spielzeiten)+4000 ms` zwingt den langsameren PC erst zum Aufholen. Bei bewusst pausiertem Spiel kann er seinen zukünftigen Zeitstempel überhaupt nicht erreichen.
- Zusätzlich scheiterte der automatische erste Spielstart an `api.type.SaveGameData.SaveGameDetails`. Die lokale TF3-API exportiert den Typ direkt als `api.type.SaveGameDetails`.

Die Weltabweichungen bei Gleisen, Fahrzeugen und Geld beweisen weitere Unterschiede zwischen den Karten. Sie lösen weiterhin keine automatische Pause und keinen automatischen Neuabgleich aus. Schon fehlende Bauten/Fahrzeuge müssen durch einen gewünschten Neuabgleich oder erneutes Bauen korrigiert werden.

## Änderungen

1. Der Reset wird sofort im tatsächlichen Spielskriptzustand gespeichert, bevor ein Live-Zustand übernommen oder ein Ereignis ausgeführt wird. Er läuft sowohl im normalen Update als auch beim ersten GUI-Netzwerkereignis während einer Pause. Alte Ausführungsbestätigungen, Entitätszuordnungen, Eingangsfragmente und Gleisprüfungen werden verworfen.
2. Der erste neue Uhrzustand sowie jede Phasenänderung werden sofort veröffentlicht. `RELEASE` räumt die Pause ohne einen weiteren Simulationsschritt auf. Bei vorhandener GUI setzt diese zuerst die Kennzeichnung der automatischen Pause und dann das tatsächliche Tempo 0; der Simulationspfad pausiert nicht vorher. Ankunft an der Sperre wird erst bei tatsächlich angehaltener Engine bestätigt. So wird eine vorübergehende Aktionspause nicht als neue Benutzerpause übernommen. Die bisherigen Schutzmaßnahmen für verzögerte Fortsetzen-Befehle und überlappende Menüpausen bleiben bestehen.
3. Fahrzeugbefehle verwenden eine Bereitschaftssperre: beide stoppen an ihrem aktuellen Tick, bestätigen Vorbereitung und Ankunft, erhalten das gemeinsame GO und warten anschließend auf beide Ergebnisse. Unterschiedliche aktuelle Ticks sind dabei ausdrücklich erlaubt. Das garantiert keine identischen Fahrzeugpositionen oder deterministischen Welten.
4. Pausierte Bau-/Wirtschaftsaktionen und Aktionen bei mehr als vier Sekunden Spielzeitversatz nutzen dieselbe Sperre. Sonstige Bauaktionen behalten ihren zukünftigen gemeinsamen Spielzeitstempel. Kein Befehl wird vor der gemeinsamen Freigabe lokal ausgeführt.
5. Vor Linienzuweisungen werden Linien und Fahrzeuge erfasst. Die zugehörigen Änderungen/Käufe gehen im zuverlässigen FIFO vor dem Plan hinaus. Pro Netzwerkschritt werden bis zu acht wartende Änderungen abgegeben; ein neuer Plan wartet, solange weitere Abhängigkeiten ausstehen. Im pausierten Leerlauf wird ebenfalls erfasst.
6. Fehlende Zielreferenzen warten höchstens 16 statt 160 Prüfschritte (bei vier GUI-Schritten pro Sekunde ungefähr vier statt vierzig Sekunden), bevor der konkrete Ausführungsfehler gemeldet wird. Normale abgelehnte Aktionen werden weiterhin sichtbar übersprungen; fehlerhafte Zeitplanprotokolle werden nicht als Erfolg ausgegeben.
7. Die automatische Ladehilfe benutzt `api.type.SaveGameDetails.new`. Eine unveränderte eigene v53-Installation bekommt beim Einrichten die aktuelle Hilfe, ohne Originalbackup oder Ressourcenindex neu anzulegen.

## Automatische Prüfungen

- `tests/run_sync.lua` (**70 bestanden**): tatsächliches `main.update` und erstes pausiertes `handleEvent` mit kopierendem Skriptzustand, gespeichertem Gastgeber-Plan 3 und beiden Rollen; danach gemeinsame Wiederaufnahme auf 1×. Freigabe bei eingefrorenem Updatezähler 7 und Kennzeichnung der automatischen Pause vor dem Tempowechsel. Vorhandene Menü-/Aktionspausenprüfungen laufen weiter.
- `tests/run_timeline.lua` (**18 bestanden**): Befehle aus beiden Richtungen bei unveränderter Spielzeit und 1402 Sekunden Abstand, pausierte Bauten, bestätigte Enginepause, Abhängigkeiten, genau einmalige Ausführung und beidseitige Freigabe. Widersprüchliche Pläne werden weiter abgelehnt.
- `tests/run_vehicle_session.lua`: beide tatsächlichen Mod-Ereignisabläufe mit kopierenden Zuständen und geordneten, simulierten Netzwerkbestätigungen. Bestehende Linie zuweisen, fünf neu gekaufte Busse sofort auf eine neue Linie schicken, echte Befehlsablehnung simulieren und danach den nächsten Befehl ausführen. Beide Richtungen, keine fortschreitende Spielzeit. Eine bestehende Zuweisung benötigt in diesem Modell 2,5–2,75 Sekunden; das ist keine Messung im echten Netzwerk.
- `tests/run_autoload.lua` und `tests/run_game_start.ps1`: tatsächliche Ladehilfe mit API-Namen aus der lokalen TF3-Definition und Aktualisierung einer vorhandenen eigenen v53-Ladehilfe in einem temporären Spielordner.
- Übrige Prüfungen bestanden: 140 allgemeine Mod-, 63 Aktions-, 17 Transport-, 11 Halte-, 12 Fahrzeug-GUI-, 25 Wirtschafts-, 41 Weltvergleich- und 13 Schiffs-/Flugzeugprüfungen. Launcher 60, Lobby 26, Neuabgleich 34, Oberfläche 321, automatischer Start 21 und Aktionsfehler 29 Prüfungen bestanden; Ladehilfe 10 Prüfungen bestanden. Das entpackte v54-Paket lädt seine Launcher-Bibliothek und enthält 17 fehlerfrei geparste PowerShell-Quellen.
- `tests/run_net.py --internet` bestanden: tatsächliche native Bridge durch einen lokalen IPv6-TLS-Tunnel, verlorene Kontroll-/Datenpakete, 140 geordnete Aktionen, Rückstau, Wiederverbindung, beidseitiger Neuabgleich und frische Aktionsreihenfolge danach. Im Testaufbau wird ein freier TCP-**und**-UDP-Port gesucht, da Windows einen nur für TCP ausgewählten Testport für UDP sperren kann. Der Produkttransport wurde dafür nicht geändert.

Die Engine und Netzwerkvermittlung dieser neuen Mod-Tests sind simuliert. Ein echter Zwei-PC-Lauf und Fahrwegprüfung auf der konkreten Karte bleiben erforderlich. Bei den automatischen Prüfungen wird keine echte TF3-Installation verändert und kein echtes Spiel beendet oder gestartet.

## Nächster Zwei-PC-Test

Beide Spiele/Launcher schließen und auf beiden PCs das v54-Paket verwenden. Einen gemeinsamen Gastgeberstand bereitstellen und starten; bei bestehender Sitzung einmal manuell neu abgleichen. Danach:

1. Beide Karten laden lassen, beim Gastgeber 1× wählen. Beide Spiele müssen fortsetzen, ohne wieder von selbst in Pause zu springen. Gelbe Weltmeldungen dürfen das Bauen nicht stoppen.
2. Bei bewusst gewählter Pause aus beiden Richtungen Fahrzeuge einer bestehenden Linie zuweisen. Danach fünf Fahrzeuge kaufen, eine neue Linie erstellen und die fünf sofort zuweisen. Der Auftrag muss auch ohne Aufheben der Pause abgeschlossen werden.
3. Bei 1× und 4× jeweils Umdrehen, Start/Stopp und Linienwechsel aus Fahrzeugfenster und Fahrzeugverwaltung prüfen. Nach Abschluss soll das vorherige Tempo wieder gelten. Bewusst zuvor gewählte Pause bleibt Pause.
4. Menü auf einem PC öffnen: beide müssen stehen bleiben; nach Schließen beider Menüs fortsetzen. Das ist weiterhin eine absichtliche Sperre.
5. Noch einmal manuell neu abgleichen, nach dem Laden 1× wählen und eine weitere Linienzuweisung sowie einen Gleisbau ausführen. Die Protokolle dürfen keinen alten `phase=prepared hold=1`-Plan oder `peer rejected` zeigen.

Bei einer erneuten Ablehnung beide PC-Protokolle aufheben; der konkrete Fahrweggrund und fehlende Referenzen erscheinen im Aktionsprotokoll.

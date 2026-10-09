# Simulierter Gastgeber: Auswertung vom 9. Oktober 2026

Geprüft wurden der letzte Test aus `%TEMP%/tf3mp-fake-47800.log`, das dazugehörige `stdout.txt` und `alut_proxy.log`. TF3 lief als Mitspieler gegen den lokalen Testpartner. Der Spielstandname allein beweist keinen durchgeführten Neuabgleich.

## Beobachtet

- Pause und Fortsetzen wurden im Spiel übernommen.
- 90 Spielsekunden Rückstand wurden in etwa 83 echten Sekunden aufgeholt; das Spiel bestätigte anschließend keinen verbleibenden Rückstand.
- Die absichtlich vorgegebene Gelddifferenz von 5.000 wurde einmal erfolgreich gebucht. Danach meldete das Spiel `adj=5000`, die Prüfpunkte waren wieder gleich.
- Ein absichtlich zusätzlich gemeldetes Fahrzeug löste die erwartete Warnung aus. Das war ein Testreiz, kein echter zusätzlicher Fahrzeugbau.
- 15 Aktionen wurden übertragen und vom Testpartner gespeichert. Darunter wurde die Kreditaufnahme als originales Spielereignis erfasst. Der Testpartner führt diese Aktionen selbst nicht in einer zweiten Welt aus.
- Kein abgelehnter Nachbau war protokolliert. Das Spiel wurde normal beendet.

## Gefundene Lücken

- In diesem Lauf wurde der ursprüngliche Stand nicht erneut geladen und keine der 15 gespeicherten Aktionen zurückgesendet. Der Nachbau ist daher **offen**, nicht erfolgreich getestet.
- Der Weltvergleich konnte `hedge` (Gleise/Straßen), `hline` (Linien) und `hcargo` (Fracht) nicht erfassen. Die Engine meldete wiederholt `Cannot loop over this component type`. Der abschließende Weltstatus war `unknown`. Diese Spiellogik-Lücke bleibt zu beheben; die neue Auswertung macht sie sichtbar.
- Der Test lief mit `prepared=0` und `ordering=0`. Gemeinsame Aktionszeiten, unabhängige Weltentwicklung, VPN, parallele Spielstandübertragung und automatisches Neuladen auf zwei PCs sind dadurch nicht geprüft. Der simulierte Gastgeber spiegelt überwiegend Werte des echten Spiels.

## Verbessertes Verfahren

Im Testlabor **Simulierter Gastgeber** wählen. Nach dem Test auf **Details prüfen** klicken. Der Launcher zeigt für jeden Teil `OK`, `OFFEN`, `LUECKE`, `FEHLER` oder `UNGETESTET` und speichert die Auswertung neben dem Gastgeberprotokoll als `.report.txt`. Ein fehlendes oder nicht zuordenbares Spielprotokoll ergibt keine Erfolgsmeldung für die Weltprüfung.

1. Einen entbehrlichen Ausgangsspielstand laden und zunächst Tempo 1x lassen. Pause, Fortsetzen, Aufholen und Geldkorrektur abwarten.
2. Bauten und Fahrzeug-/Linienaktionen ausführen.
3. **Ohne Speichern** ins Hauptmenü gehen und genau den ursprünglichen Stand neu laden. TF3 dabei offen lassen. Nach 20 Spielsekunden beginnt der Nachbau.
4. **Details prüfen**: Alle zurückgesendeten Aktionen müssen bestätigt sein. Danach das Ergebnis auf der Karte prüfen. Bestätigung allein beweist keine vollständig identische Welt.
5. Ohne Speichern beenden und die Auswertung erneut abrufen. Für den echten Neuabgleich und die gemeinsame Aktionszeit anschließend mit zwei VPN-PCs testen.

Vor dem nächsten Start wird das vorherige Gastgeberprotokoll archiviert. Ein Nachbau ohne Übertragungsfortschritt bricht nach 180 Sekunden mit `REPLAY TIMEOUT` ab, statt unbemerkt endlos zu warten. Ablehnung und Zeitlimit stoppen Folgeaktionen. Neue Spielstand-Prüfpunkte werden nach einem erkannten Neuladen frisch beantwortet.

Das Protokoll wird mit gemeinsamem Lese-/Schreibzugriff geöffnet; kurze Sperren werden erneut versucht. Ein vorübergehend gesperrtes Diagnoseprotokoll beendet den Testpartner nicht mehr.

Automatische Gegenprüfung: 24 Fälle in `tests/run_fake_report.ps1`, drei reale lokale UDP-Szenarien in `tests/run_fake_partner.py` (erfolgreicher Nachbau, abgelehnte Aktion, fehlende Bestätigung) und 49 Launcherprüfungen in `tests/run_launcher.ps1` bestehen. TF3 wurde dafür nicht gestartet oder verändert.

## Nachtrag: Neuladefehler und v38

Im folgenden Lauf wurden 19 Aktionen aufgezeichnet und nach dem Neuladen zurückgesendet. Schon Aktion 1 (`line_update`, Linie 1) scheiterte mit `construction reference not found`: Ein Halt lag am weltgehörigen Bauernhof `::/industries/farm/farm.con`. Die Auflösung erlaubte bisher ausschließlich Konstruktionen des Spielers. Dadurch waren 0 von 19 Aktionen bestätigt; der anschließende echte Zwei-PC-Neuabgleich wartete vergeblich auf den lokalen Testpartner.

v38 erlaubt das lesende Finden weltgehöriger Konstruktionen ausschließlich als Eltern eines Linienhalts. Änderungen, Abriss und Depotaktionen behalten ihren Eigentumscheck. Die originale erste Aktion liegt als Regression in `tests/fixtures/run41-first-line.a1` und besteht mit einer nachgebildeten Zielwelt mit anderen Entity-IDs. Der Launcher startet in konfigurierten Testmodi keinen automatischen Zwei-PC-Neuabgleich mehr. Diese Korrektur behebt nicht die oben beschriebenen fehlenden Weltmessungen.

13 Schiffs-/Flugzeug-/Industriehaltfälle, 63 Aktionstests, 36 Fingerabdrucktests, 127 grundlegende Modprüfungen, 31 Neuabgleich-, 49 Launcher- und 24 Auswertungsprüfungen bestehen. Der vollständige Nachbau der 19 Aktionen im echten Spiel bleibt zu bestätigen. Beide PCs müssen für einen gemeinsamen Test dasselbe v38-Paket verwenden.

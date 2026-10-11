# v55: Baufehler, Geldangleichung und Weltvergleich

## Befund aus dem Lauf vom 11. Oktober 2026

Ausgewertet wurden der lokale Launcher, die native Bridge, das Internet-/Übertragungsprotokoll und `crash_dump/stdout.txt` mit Probe v54. Zeiten unten sind Ortszeit; das Spiel protokolliert UTC, hier zwei Stunden früher. Das vollständige Protokoll des Mitspielers liegt nicht vor.

- Die Verbindung lief bis zum normalen Spielende. Das Internetprotokoll meldet keine Wiederverbindung und keinen abschließenden Verbindungsfehler. Die Bridge war zuletzt bei Reihenfolge 1310, ohne Blockierung; dieser Zähler enthält auch Steuer- und Diagnosenachrichten.
- **00:11:36, Fliederweg:** Der gültige erste Haltestellen-Nachbau wurde mit „Bau nicht möglich“ abgelehnt. Danach versuchte die Mod eine alternative Objektnummerierung. Diese führte nachweislich zu TF3s internem Fehler `idx < edgeObjectsToAdd.size()`. Die ursprüngliche Platzierungsablehnung ist damit noch nicht erklärt. Die auf drei Nachkommastellen gerundete Position entlang eines Segments war eine zusätzliche vermeidbare Ungenauigkeit.
- Die folgende Buslinie konnte die fehlende Fliederweg-Haltestelle nicht finden. Ab **00:46:37** scheiterten außerdem Gleis-/Straßenaktionen an fehlenden vorhandenen Knoten; weitere Aktionen hingen wiederum davon ab. Die Entstehung sämtlicher fehlender Knoten ist aus diesem lokalen Protokoll nicht abschließend rekonstruierbar.
- Fünf Fahrzeugkäufe wurden abgelehnt. Beim ersten dieser Käufe war das lokale Konto bereits negativ, während das andere Spiel einen positiven Kontostand meldete. Das ist ein plausibler Einfluss, kein Nachweis der einzigen Ablehnungsursache: TF3 meldete nur die Ablehnung. Spätere Linienzuweisungen konnten dadurch auf fehlende Fahrzeuge treffen.
- **00:57:35:** Eine Arbeitersubvention über 3,81 Mio. scheiterte an der Zuordnung ihres Industrieziels. Die bisher verwendete Mitte des Industrieumrisses kann sich durch Felder und Wachstum verschieben. Ob das allein diesen konkreten Fehlschlag verursachte, bleibt offen.
- Acht spätere Anschlussprüfungen für **Neuenhagen Station West** fanden keinen Netzanschluss. In der übertragenen Bahnhofserweiterung war ein offenes Gleisende als Zugang markiert, weil sein äußerer Knoten bereits existierte. Bestehende offene Enden wurden anders behandelt als neu erzeugte offene Enden.
- Unterschiedliche native Kreditsalden verhinderten im Code auch die Geldkorrektur. Im Lauf lagen die Konten zeitweise bei etwa −3,17 Mio. und +17,16 Mio. Die ursprünglichen Kreditpläne und laufenden Raten bleiben Angelegenheit der jeweiligen TF3-Simulation.
- Der Weltvergleich scheiterte bei Linien an nativen Werten innerhalb einer Lua-Tabelle. Der Frachtscan verbrauchte das globale Abfragelimit; spätere Stadtprüfungen hatten dadurch kein Budget mehr. Ein Fahrzeug im Depot besitzt nicht immer eine auslesbare Fahrposition.
- Gemeinsame Fahrzeugaktionen hielten das Spiel teilweise 6–11 Sekunden, einmal rund 20 Sekunden an. Eine Menüpause blieb etwa 31 Minuten aktiv; das allein beweist keinen Fehler, da offene Menüs beide Spiele ausdrücklich anhalten sollen.
- Der Spielstandaustausch übertrug rund 73,5 MiB mit vier Datenströmen in rund 37 Sekunden. Reine Datenrate: **2,05 MiB/s**, kein Übertragungsabbruch in diesem Lauf. Der Transport wurde in v55 nicht geändert.

## Änderungen

1. **Haltestellen/Signale:** ausschließlich nullbasierte native Objektindizes. Kein unsicherer Ersatzversuch mit um eins verschobenen Indizes. Der Segmentparameter wird mit ausreichender Genauigkeit übertragen. Der echte Fliederweg-Befehl ist als Regressionstest gespeichert.
2. **Bahnhofserweiterungen:** Der Sender prüft, wie viele Segmente den beibehaltenen äußeren Knoten tatsächlich berühren. Ein bestätigtes offenes Ende mit nur einem Segment wird wie ein neu erzeugter Endstummel behandelt. Ein echter Anschluss mit weiteren Segmenten bleibt erhalten und wird weiter geprüft. Ist die Information nicht lesbar, wird kein offenes Ende geraten.
3. **Wirtschaft:** Unterschiedliche verwaltete Kreditsalden bleiben Diagnose, blockieren aber nicht mehr das Angleichen des verfügbaren Geldes an den Gastgeber. Native Kreditpläne werden dafür nicht durch Journalbuchungen ersetzt. Industrieziel-Referenzen enthalten zusätzlich festen Bauwerksanker und Ressource. Unterschiedliche Betriebe, fehlende Ziele und mehrdeutige Zuordnungen bleiben Fehler; es gibt keine freie Ersatzauszahlung.
4. **Fahrzeuge:** Abgelehnte Käufe protokollieren Depot, Kontostand, erstes Modell und den von TF3 berechneten Gesamtpreis, soweit lesbar. Der Ausführungsbeleg behält diese Diagnose, statt sie wieder durch `game command rejected` zu ersetzen. TF3s unspezifischer Fahrweggrund `Unkown` wird ausdrücklich als unspezifisch erklärt.
5. **Weltvergleich:** Native Linien-/Fahrzeugwerte werden vor der Prüfung in Daten umgewandelt. Komponenten werden innerhalb desselben unveränderlichen Erfassungszeitpunkts wiederverwendet. Fahrzeuge im Depot bekommen eine semantische Depotreferenz statt einer erfundenen Fahrposition. Fehlende Fahrpositionen fahrender Fahrzeuge bleiben unbekannt.
6. **Fracht und Budget:** Die nativen Lager- und Fahrzeugverzeichnisse werden bevorzugt verwendet, wenn beide verfügbar sind. Doppelte Frachteinträge werden entfernt; der Vergleich kennzeichnet die Abdeckung als `stocks_and_vehicles`. Das ist kein Nachweis über Fracht außerhalb dieser Verzeichnisse. Scheitert ein Teilverzeichnis, wird kein erfolgreicher Teilvergleich veröffentlicht. Kategorien haben maximal 6000 API-Aufrufe, die gesamte Erfassung weiterhin höchstens 16000. Zeit- und Größenlimits bleiben erhalten; native Einzelaufrufe lassen sich durch Lua nicht unterbrechen.
7. **Gemeinsame Aktionen:** Bis zu acht benachbarte Bestätigungen können eine zuverlässige Nachricht teilen. Anfragen und Ausführungspläne bleiben einzelne Nachrichten. Bereitschaft, bestätigte Pause, gemeinsame Freigabe und beidseitige Ausführungsbestätigung werden weiterhin einzeln geprüft. Während einer aktiven Aktion wird die GUI alle 0,1 statt 0,25 Sekunden geprüft; im Leerlauf bleibt das bisherige Intervall.

## Automatische Prüfungen

Bestanden: 143 allgemeine Mod-, 64 Aktions-, 26 Wirtschafts-, 44 Weltvergleich-, 71 Synchronisierungs-, 20 Zeitplan-, 17 Transport-, 11 Halte-, 10 Ladehilfe-, 12 Fahrzeugoberflächen- und 13 Schiffs-/Flugzeugprüfungen. Vier Tests verbinden die tatsächlichen Mod-Ereignisabläufe beider Rollen mit simulierter Engine und geordnetem Netzwerk. Sie prüfen Linienzuweisung, neue Linie plus fünf Käufe, Ablehnung und anschließende Freigabe des nächsten Befehls.

In diesem Netzwerkmodell benötigt eine bestehende Zuweisung 2,25–2,5 Sekunden, fünf neue Busse mit neuer Linie 7,5–7,75 Sekunden. **Das sind keine gemessenen Internet-Pausenzeiten.** Die echte TF3-Karte und deren Fahrwege müssen erneut geprüft werden.

Launcher-Prüfungen: 31 Aktionsfehler-, 60 Launcher/Protokoll-, 321 Layout-, 10 Sitzungs-, 21 Start-, 34 Neuabgleich- und acht Internetoberflächenprüfungen bestanden. Layouts wurden bei 100 %, 150 % und 200 % geprüft. Diese Prüfungen verwenden temporäre Spielordner und verändern weder das echte Spiel noch Firewall/Router.

`tests/run_net.py --internet` bestanden: echte native Bridge durch einen lokalen IPv6-TLS-Tunnel, verlorene Daten-/Kontrollpakete, 140 geordnete Aktionen, Rückstau, Wiederverbindung und beidseitiger Neuabgleich mit frischer Aktionsreihenfolge. Das ist ein Transporttest ohne TF3 und kein echter Zwei-PC-Kartentest. Das Paket enthält 84 geprüfte Dateien; 23 Lua-Quellen kompilieren und 17 PowerShell-Quellen sind fehlerfrei geparst.

Der Lua-Mikrobenchmark bleibt ausdrücklich ein Modell ohne native Enginekosten: kleiner Fall 20 Fahrzeuge/100 Frachtstücke/10 Städte vollständig; mittlerer Fall 200/2000/100 im gemeinsam mit anderen Tests ausgeführten Lauf mit unbekannter Fracht wegen des Zeitbudgets, aber erfassten Städten. Der große Fall 10000/100000/1000 lehnt die übergroßen Kategorien ab. Eine vollständige und ruckelfreie Erfassung großer echter Karten ist damit **nicht** nachgewiesen.

## Nächster Test auf beiden PCs

Beide verwenden v55. Einmal denselben Gastgeberstand laden oder bewusst gemeinsam **Neu abgleichen**. Vorhandene fehlende Bauten werden durch die Installation allein nicht wiederhergestellt.

1. Zwei Haltestellen nahe einer Kreuzung setzen, danach eine Linie durch beide erstellen. Auf beiden Karten prüfen. Auch einen Bahnhof an einem offenen Gleisende verlängern und anschließend dieses Ende mit dem Netz verbinden.
2. Eine neue Linie erstellen, fünf Fahrzeuge kaufen und sofort zuweisen. In beide Richtungen, bei Pause und bei 1×. Danach Umkehren testen: Nach Abschluss muss das vorherige Tempo wieder gelten; die nächste Bauaktion muss ankommen.
3. Eine Arbeitersubvention an einem Betrieb mit Feldern annehmen. Auftragsannahme und Geld auf beiden PCs prüfen. Danach einen Kredit bedienen/aufnehmen und beobachten, ob eine verbleibende Kreditabweichung die Geldkorrektur erneut blockiert.
4. Weltprüfungen abwarten: `hline`, Depotpositionen und `htown` sollen lesbar sein. `world scan` zeigt Erfassungszeit, Aufrufzahl, Fehler und gegebenenfalls `cargo_scope=stocks_and_vehicles`. Unbekannte Kategorien sind kein bestandener Weltvergleich.
5. Menü auf einem PC öffnen und schließen, danach weiterbauen. Gelbe Weltabweichungen dürfen weder einen automatischen Neuabgleich noch eine dauerhafte Pause auslösen.

Bei erneuter Ablehnung die Protokolle **beider** PCs sichern. Die tatsächliche Bauwerks-/Fahrweggeometrie und alle Ursachen der bereits fehlenden Knoten sind ohne den Gegentest nicht abschließend bestätigt. Neuabgleich bleibt eine ausdrückliche Gastgeberaktion.

# v61: Straßenhaltestellen und Linienfehler

## Befund vom 14. Oktober, etwa 20:39–20:53 Uhr

Die mit v60 automatisch übertragenen Mitspielerprotokolle enthalten **35 eindeutige fehlgeschlagene Aktionen**. Der Gastgeber hatte bis zu seinem Spielende 21 der zugehörigen Fehlermeldungen empfangen; die zusätzlichen Protokolldateien liefern die übrigen Befunde.

| Anzahl | Ursache | Folge |
| --- | --- | --- |
| 1 | Haltestelle #25 bei −839,5 / 6712,0 scheitert an `Unexpected parcel on a segment` | Straßenhalt fehlt beim Mitspieler. |
| 7 | Linie 5 findet den fehlenden Straßenhalt und danach ihre eigene Linienreferenz nicht | Erstellen und folgende Änderungen können nicht übernommen werden. |
| 27 | `station terminal tag 4/16 not found` bei Bus Lippstadt und Salat > Lippstadt 2 | Vorhandene Straßenhalte werden nicht richtig zugeordnet. |

Die ursprüngliche Bauaktion `7504-116062328.75` verwendet eine normale `town_old_small.street_template`. **Tram ist nicht die allgemeine Bauursache:** Mindestens 13 empfangene Bauaktionen mit Tramanteilen funktionieren in diesem Lauf, darunter Depot und elektrifizierte Straßen. Straßen-/Tramumbauten verändern allerdings die internen Tags einfacher Straßenhalte. Das war ein Fehler unserer Linienzuordnung.

Außerdem wurden reine Millimeteränderungen von Haltestellenpositionen sowie eine andere interne Stationslistenreihenfolge wieder als Linienbearbeitung verschickt. Dadurch entstanden unnötige Gegenänderungen und zusätzliche Ablehnungen.

Die initiale Spielstandübertragung wurde auf beiden PCs bestätigt: 105.961.161 Bytes in ungefähr 17,5 Sekunden, rund 5,8 MiB/s über vier Verbindungen. Kein neuer Lua- oder Fatalfehler ist im zugeordneten Lauf belegt. Beide Spiele enden mit normalem Abschluss. Der zuletzt noch wartende Auftrag ist ein Weltbericht kurz vor dem Gastgeber-Spielende; ein erneuter Quittierungsdeadlock ist daraus nicht belegt.

## Korrekturen

Bei einem Straßenhalt wird der Terminaltag nur dann weggelassen, wenn die Quelle genau ein Terminal und die Auswahl von Index 0 tatsächlich lesen konnte. Der Empfänger prüft ebenfalls, dass die zugeordnete Straßenhaltestelle genau ein Terminal besitzt. Haupt- und Alternativhalte werden nach der örtlichen Stationsreihenfolge zugeordnet. Modulare Bahnhöfe, Häfen, Flughäfen und Straßenstationen mit mehreren Terminals behalten die Tagprüfung. Fehlende oder mehrdeutige Daten erlauben keine willkürliche Auswahl.

Der Linienvergleich erlaubt höchstens 1 cm Positionszittern je Koordinatenachse ausschließlich bei Straßenhalten. Haltestellengruppen dürfen ihre Reihenfolge ändern, solange jede Referenz eindeutig dieselbe Station und Straßenseite bezeichnet. Ein Wechsel der Straßenseite oder von Halten, Wartezeiten, Frachtregeln, Bahnsteigen, Namen und Farben bleibt eine übertragene Änderung. Die tatsächlich gesendeten Koordinaten werden nicht gerundet.

Bei der betroffenen Art Straßenhaltestellenbau muss TF3 die Straße durch eine neue Straßen-ID ersetzen. Der Empfänger prüft vor dem Senden die örtlich angehängten Stadtparzellen. Fehlt eine leere Parzelle in den vorbereiteten Entfernungen, darf sie nur ergänzt werden, wenn TF3s eigener Straßenentfernungshelfer sie ausdrücklich vorbereitet. Belegte oder unlesbare Parzellen, fehlende Helfer und verlorene Rücklesedaten brechen vor der Ausführung ab. Das Ergebnis wird als ein vollständiger Bauauftrag neu vorbereitet und einmal gesendet. Die allgemeine Straßen-/Knotenbereinigung bleibt ausgeschaltet; es gibt keinen separaten Abriss und keine blinde Wiederholung eines begonnenen Baus.

## Aktualisieren und prüfen

Beide PCs auf **v61 / Bridge v16** bringen. Eine bereits fehlende Haltestelle oder Linie wird durch das Update allein nicht ergänzt. Einmal bewusst den vorhandenen Gastgeberstand über **Neu abgleichen** übernehmen.

Für den Gegentest neue Straßenhalte auf normalen Stadtstraßen und Tramstraßen bauen, besonders in bebauten Bereichen und nahe einem Straßenende. Beide Straßenseiten zu einer Linie hinzufügen und ändern. Danach Tramgleise oder Elektrifizierung umrüsten: Die Linie muss erhalten bleiben, ohne wiederholte Gegenupdates. Einen Halt absichtlich auf die andere Straßenseite setzen und Wartezeit/Namen ändern; diese echten Änderungen müssen weiterhin ankommen. Zum Schutz mehrteiliger Stationen auch eine vorhandene Bahn-/Schiffs-/Fluglinie ändern.

Die automatischen Prüfungen verwenden die reale fehlgeschlagene B5-Payload und simulierte native Antworten. **Die erweiterte Parzellenvorbereitung muss noch in TF3 auf zwei PCs gegengeprüft werden.** Bei besetzten oder unterschiedlichen Stadtparzellen ist eine verständliche Ablehnung weiterhin möglich. Weltabweichungen bleiben Hinweise; Neuabgleich bleibt auf Wunsch. Spielinstallation und laufende Spiele wurden für die Untersuchung nicht verändert.

**595 Lua-Prüfungen bestehen jeweils unter Lua 5.4 und Lua 5.2**, einschließlich zwölf Straßenhalt-/Parzellentests, zwölf Terminal-/Pollingregressionen und 33 Linienvergleichstests. Alle 24 Lua-Quellen kompilieren in beiden Runtimes. Zusätzlich bestehen 39 Aktionsfehler-, 71 Launcher-/Protokoll-, 321 Layout- und zehn Sitzungsprüfungen; die 18 PowerShell-Quellen sind syntaktisch geprüft.

# v56: Fahrzeugkäufe und Linienzuweisung

## Was im letzten echten Lauf schiefging

Im lokalen v54-Spielprotokoll vom 11. Oktober wurden fünf nachgebaute Fahrzeugkäufe abgelehnt. Danach fehlten unter anderem Bus 48/49/50 und Zug 7 bei den folgenden Linienzuweisungen. Mehrere Sammelzuweisungen bereits vorhandener Busse und Züge wurden dagegen erfolgreich bestätigt. Eine tatsächliche native Linienablehnung betraf Zug 6 mit dem unspezifischen TF3-Fahrweggrund 0.

Ein Geldmangel zum genauen Zeitpunkt jeder Ablehnung ist aus diesem alten Protokoll nicht bewiesen. Die verfügbaren Kontowerte stammen von benachbarten Messpunkten. Fehlende Gleise, Fahrzeug-/Depotunterschiede und abgelehnte Käufe bleiben ebenfalls mögliche Einflüsse. v55/v56 protokollieren deshalb den Kaufkontext unmittelbar vor dem Nachbau. Das vollständige Protokoll des anderen PCs fehlt weiterhin.

## Änderungen

- Bei einer Fahrzeugbarriere bestätigt der Mitspieler Vorbereitung und Ankunft gemeinsam, sobald seine native Pause sichtbar ist. Er bleibt bis zum COMMIT des Gastgebers vorbereitet. GO und beide Ausführungsbestätigungen bleiben erforderlich. Das spart einen Netzumlauf; normale Bauaktionen mit künftigem Zeitstempel behalten ihren bisherigen Ablauf.
- Nach einem Kauf wird der bestätigte native Fahrzeugzustand gelesen. Unveränderte Namen, Start-/Stopp- und Abfahrteinstellungen werden nicht nochmals gesendet. Ein nicht lesbarer Zustand behält die bisherigen Folgeeinstellungen; abweichende Werte werden weiterhin korrigiert.
- Stopindex `-1` für den nächsten erreichbaren Halt bleibt auch bei nachgebauten Fahrzeugkäufen und Änderungen erhalten. Bisher akzeptierte dieser Pfad nur nichtnegative Indizes, obwohl der gemeinsame Fahrzeugzeitplan bereits `-1` unterstützte.
- Neue gekaufte Teile erhalten die aktuelle Spielzeit dieses PCs als `TransportVehiclePart.purchaseTime`, entsprechend TF3s normalem Kaufablauf. Ist die Zeit nicht lesbar, bleibt der native Konstruktorstandard erhalten. Dieser Abgleich ist kein Beweis, dass die bisher fehlende Kaufzeit die realen Ablehnungen verursacht hat. Alters- und Wartungsübernahme bei späteren Fahrzeugersatz-/Kompositionsänderungen wird hier nicht neu gelöst.
- Der Kaufkontext nennt `ACCOUNT.balance` sowie TF3s verfügbare Geldmittel (`funds`, einschließlich unbegrenztem Geld), Neupreis und Modell. Wenn der Neupreis nicht lesbar ist, wird ein alternativ ausgelesener Teilpreis ausdrücklich als `part_fallback` bezeichnet. Die Mod füllt kein Gastgeberkonto auf, um einen Kauf zu erzwingen, und wiederholt keine möglicherweise bereits teilweise ausgeführte Aktion blind.
- Zurückgehaltene Fahrzeugbefehle können während des Verbindungsaufbaus oder nach einer fehlgeschlagenen Planung nicht mehr auf eine ungeteilte lokale Ausführung ausweichen. Rückmeldungen an die nativen Fahrzeugfenster laufen genau einmal nach bestätigter Übergabe. Fehler erscheinen als Aktionsfehler in beiden Protokollen; eine nachfolgende native Ausführungsablehnung bleibt separat sichtbar.
- Ein ausdrücklich gewähltes Depot beim nativen Teleport-/Depotbefehl wird über das zugehörige Bauwerk aufgelöst. Die Kennung des fremden PCs wird nicht direkt benutzt.
- Abgelehnte Linienzuweisungen ergänzen TF3s detaillierte Linienpunktprobleme, soweit lesbar: fehlender Fahrweg einschließlich Alternativterminal, inkompatibler oder doppelter Halt. Segment und Punkt bleiben entsprechend der nativen GUI gekennzeichnet, ohne Wegpunkte als Haltestellen zu zählen. Die Diagnose ist geschützt und begrenzt; sie ersetzt keine Prüfung der tatsächlichen Karte.
- Das kurze Warten auf nachgebaute Fahrzeugreferenzen richtet sich bevorzugt nach verstrichenen Sekunden. Das schnellere GUI-Intervall und zusätzliche Ereignisse verbrauchen die Frist nicht mehr allein durch ihre Anzahl. Bei fehlenden oder fehlerhaften Timern bleibt eine begrenzte Zahl von Prüfungen als Rückfall erhalten.

## Automatische Prüfung und Aussagegrenzen

Die Sitzungsprüfung verwendet beide tatsächlichen Mod-Ereignisabläufe und zusätzlich die wirkliche Lua-Logik für die GUI-Pause. Engine und Netzwerk bleiben simuliert. Verzögerte native Antworten, verspätet sichtbare Geschwindigkeitsänderungen und modellierte Netzlatenz werden ausdrücklich berücksichtigt. Getrennte Szenarien prüfen Gastgeber/Mitspieler, Pause/1×/4×, gleiche Uhren und 1.402.000 ms Zeitversatz sowie Sammelzuweisungen und einen gemeinsamen Reload mit unfertiger alter Aktion.

Im unveränderten einfachen Netzwerkmodell dauert eine bestehende Zuweisung jetzt 1,75–2,0 statt 2,25–2,5 Sekunden. Eine neue Linie mit fünf neuen Fahrzeugen benötigt 4,5–4,75 statt 7,5–7,75 Sekunden. **Das sind Modellwerte und keine Internetmessungen.** Im Modell mit 0,35 s Netzverzögerung und 0,5 s Engineantwort dauern einfache Zuweisungen je nach Rolle/Tempo 5,25–6,75 Sekunden. Beides sind verschiedene Modelle; ihre absoluten Zeiten dürfen nicht als reale Prognose verwendet werden.

Bestanden: insgesamt 466 Lua-Prüfungen, darunter 19 Sitzungsfälle. Die beiden 40-Fahrzeug-Fälle verwenden fragmentierte Nachrichten und verzögerte native Antworten: 35,25/36,0 Modellsekunden, jeweils genau eine Zuweisung pro Fahrzeug und Spiel, danach eine weitere erfolgreiche Aktion. Der Reloadfall verwirft den alten unfertigen Plan und beginnt für beide Rollen bei Reihenfolge 1. Zusätzlich bestanden 31 Aktionsfehler-, 60 Launcher/Protokoll-, 321 Layout-, 34 Neuabgleich-, 21 Start- und zehn Sitzungsprüfungen. Alle verwenden simulierte Spielumgebungen bzw. temporäre Ordner.

Die native Bridge wird separat durch einen lokalen IPv6-TLS-Tunnel geprüft, einschließlich verlorener Pakete, Rückstau, Wiederverbindung und gemeinsamem Neuabgleich. Das bestätigt den Transport, nicht TF3s echte Fahrwege. Auf diesem PC lief während der Implementierung kein TF3; ein zweites laufendes Spiel war nicht verfügbar. Ein echter Zwei-PC-Kartentest wurde deshalb nicht durchgeführt.

## Gezielt auf beiden PCs prüfen

Beide verwenden v56. Einen gemeinsamen Gastgeberstand laden; bereits fehlende Fahrzeuge oder Gleise werden durch ein Update nicht wiederhergestellt.

1. **Gastgeber bei 1×:** Eine neue Linie erstellen, fünf Fahrzeuge im angeschlossenen Depot kaufen und sofort gemeinsam zuweisen. Auf beiden PCs müssen fünf Fahrzeuge auf der richtigen Linie stehen und losfahren. Wartezeit vom Klick bis zum Ende der gemeinsamen Pause messen.
2. **Mitspieler bei Pause:** Dasselbe mit fünf weiteren Fahrzeugen durchführen. Die Zuweisung muss auch ohne laufende Spielzeit fertig werden; die vorher gewählte Pause bleibt bestehen. Danach auf 1× fortsetzen und prüfen, dass beide Spiele laufen.
3. **Zug und Fahrweg:** Einen Zug über einen frisch gebauten Depotanschluss auf eine neue Linie schicken. Bei Ablehnung die Meldung prüfen: War bereits der Kauf abgelehnt, fehlt ein Fahrzeug, oder meldet TF3 einen Fahrwegfehler? Danach einen funktionierenden Fahrzeugbefehl und eine kleine Bauaktion ausführen; beide müssen weiterhin übertragen werden.
4. **Pause und Neuabgleich:** Bei 1× und 4× ein Fahrzeug umkehren. Anschließend muss das vorherige Tempo wieder gelten; während eines offenen Menüs bleiben beide Spiele bewusst pausiert. Danach den manuellen Gastgeber-Neuabgleich durchführen und nochmals ein vorhandenes Fahrzeug zuweisen.

Bei einem Fehler die Spiel- und Launcherprotokolle **beider PCs** direkt sichern, bevor sie beim nächsten Start überschrieben werden. Relevante Spielzeilen: `action vehicle_create purchase`, `vehicle ... REJECTED`, `timeline ... waits`, `timeline execute`, `timeline result` und `action issue`. Die Zeitstempel dieser Zeilen zeigen Kauf-/Zuordnungsfolge und Verzögerungen. Kontoanzeigen und tatsächliche Depot-/Gleisverbindungen auf beiden Karten mitprüfen. Gelbe Weltabweichungen bleiben Hinweise; es gibt keinen automatischen Neuabgleich.

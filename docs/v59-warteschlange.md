# v59: Wartende Aktionen und sichere Übergabe

## Befund aus dem Lauf vom 11. Oktober

Die Verbindung war nach dem Laden zunächst bereit. Um **23:21:32** wurde Auftrag 171 mit der Kennung `62420-180487375.89` angenommen. Es handelt sich um eine vom Mitspieler gesendete Gleisabrissaktion. Ihre Ausführungsbestätigung vom Gastgeber fehlte im gesicherten Verlauf; die nachfolgenden Nachrichten warteten dahinter. Die Verbindung tauschte weiterhin Bereitschaftsnachrichten aus. Im zugeordneten Spielprotokoll wurde weder eine Aktionsablehnung noch ein Lua-Absturz gefunden.

Die letzte gesicherte Warteschlange enthält **53 Einträge: 21 Spieländerungen und 32 Weltberichte**. Die Spieländerungen umfassen 17 Bau-/Abrissnachrichten, eine Linienänderung, zwei Fahrzeugkäufe und einen Fahrzeugverkauf. Die bisherige Launcheranzeige zählte auch Weltberichte als Aktionen. Die gemeldeten Unterschiede bei Fahrzeugpositionen und Städten erklären den fehlenden Auftragsabschluss nicht und erzwingen weiterhin keinen Neuabgleich. In diesem Lauf wurden außerdem 13 Geldkorrekturen angefordert; bei zwölf wurde die Buchung im gesicherten Verlauf ausdrücklich beobachtet.

Der nachgereichte Text beginnt mit einem Spielstart vom 7. Oktober. Er enthält die aktuelle Gegenstelle des Auftrags 171 nicht. Deshalb ist der genaue Zustand der Gastgeber-Engine beim Hänger mit den vorhandenen Daten nicht abschließend bewiesen.

## Reproduzierter Fehler und Korrektur

Im bisherigen Empfangspfad konnte bereits das letzte Fragment die vollständige Nachricht quittieren. War gleichzeitig eine andere Spielaktion beschäftigt, kehrte Lua danach ohne Übergabe des neuen Auftrags zurück. Die Bridge bot die quittierte Nachricht nicht erneut an. Auch ein verlorenes internes Skriptereignis konnte nach einer vorzeitigen Empfangsquittung unbemerkt bleiben. Beide Fälle passen zum beobachteten Warten und sind unabhängig vom fehlenden Gastgeberprotokoll reproduzierbar.

v59 speichert eine vollständige, begrenzte Übergabe im Spielskriptzustand, bevor die letzte Fragment- und Empfangsquittung gesendet wird. Solange eine andere Ausführung diesen Zustand belegt, bleibt die Nachricht unquittiert und zustellbar. Ein noch nicht begonnenes Übergabeereignis wird mit derselben eindeutigen Kennung erneut zugestellt. Der Ereignishandler beansprucht diese Kennung vor dem ersten Engine-Befehl. Doppelte, verspätete oder zu einer früheren geladenen Welt gehörende Ereignisse dürfen dadurch keinen zweiten Bau auslösen. Rückmeldungen einer alten Ausführung dürfen den Zustand einer neuen Welt ebenfalls nicht verändern.

**Eine bereits gestartete Engineaktion wird bei fehlender Bestätigung weder automatisch wiederholt noch übersprungen.** Sie könnte teilweise ausgeführt worden sein. Stattdessen bleiben Kennung und Arbeitsschritt sichtbar; der Gastgeber entscheidet über einen Neuabgleich. Die Korrektur gilt auch beim pausierten Spiel und berücksichtigt kopierte Zustände sowie unmittelbar zugestellte Skriptereignisse.

## Neue Diagnose

Bridge v16 meldet getrennte Anzahlen für Spieländerungen und Diagnoseberichte, den aktiven Auftrag, Zeit seit dem letzten Protokollfortschritt, Fragment-/Empfangsstände und die Arbeitsschritte beider Spiele. Der Launcher meldet ab 30 Sekunden ohne Fortschritt, ob Daten, Übergabe, TF3-Rückmeldung, Fortsetzung, Anschlussprüfung oder Abschluss fehlen. Wiederholte identische Empfangsbestätigungen setzen diese Zeit nicht laufend zurück. Statusdateien werden als vollständige Momentaufnahme ersetzt.

Der um **23:27:43** gestartete manuelle Neuabgleich scheiterte später bei der Spielstandübertragung. Der erste gesicherte Empfangsfehler trat nach rund 28 MB auf; alle vier Verbindungen hatten Daten übertragen. Diese Unterbrechung begann mehrere Minuten nach dem Aktionshänger und ist damit ein eigener Befund. Die bisherigen Messprotokolle nennen überwiegend allgemeine Exceptiontypen und beweisen keine konkrete Router-, Gegenstellen- oder Leitungsursache.

Die neuen Übertragungsprotokolle ergänzen begrenzte innere Fehlertypen und Fehlercodes, den tatsächlichen Verbindungsversuch, die zuletzt beobachtete Phase sowie Byte- und Verbindungsfortschritt. Sie protokollieren keine Zugangsdaten oder rohen Exceptiontexte. Der Transport selbst wird dadurch nicht geändert; eine höhere Geschwindigkeit oder ein behobener Internetabbruch ist noch nicht nachgewiesen.

## Aktualisieren und gezielt prüfen

Beide PCs verwenden **v59 / Bridge v16** und starten eine neue gemeinsame Sitzung. Eine in v58 bereits verlorene Übergabe wird durch ein Paketupdate nicht rückwirkend ausgeführt. Bei unterschiedlichen Karten einmal bewusst den Gastgeberstand über **Neu abgleichen** übernehmen. Änderungen, die nur beim Mitspieler existieren, vorher auf der Karte prüfen und gegebenenfalls nach dem Abgleich erneut bauen.

Für den echten Gegentest mehrere Gleise bauen und abreißen, während der andere PC Fahrzeuge kauft und zuweist. Auch bei Pause und mehreren direkt folgenden Befehlen muss die Warteschlange wieder leer werden. Beide Karten auf fehlende und doppelte Bauten prüfen. Bei erneutem Warten die Protokolle beider PCs mit derselben Auftragskennung sichern. Ein absichtlich unterbrochener Übertragungstest muss den zuletzt beobachteten Fortschritt und Fehlercodes zeigen; der genaue Abbruchort darf bei fehlenden Daten unbekannt bleiben.

Die automatischen Prüfungen verwenden isolierte Netzwerkprozesse und simulierte Engineantworten. Ein vollständiger Gegentest auf zwei echten TF3-Karten bleibt erforderlich. Die laufende Spielinstallation wird für Entwicklung und Paketbau nicht verändert.

**538 Lua-Prüfungen bestehen jeweils unter Lua 5.4 und Lua 5.2**, einschließlich 18 neuer Übergaberegressionen. Alle 23 Lua-Quellen kompilieren in beiden Runtimes. Zusätzlich bestehen 71 Launcher-/Protokollprüfungen, 321 Layoutprüfungen bei 100/150/200 Prozent, 36 Aktionsfehler-, 34 Neuabgleich-, 21 Start- und zehn Sitzungsprüfungen sowie 44 echte TCP-Übertragungs- und sieben Übertragungsdiagnosetests. 338 native Einzelprüfungen sichern Reihenfolge, Statuspuffer und Zeitmessung ab. Ein weiterer Test verwendet zwei getrennte Windows-Prozesse mit der produktiven Netzwerkimplementierung und prüft gemeinsame Reihenfolge, verzögerte Bestätigungen und Duplikate.

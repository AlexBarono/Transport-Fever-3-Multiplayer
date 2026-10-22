# v63: Tempoänderungen, Geld und echte Simulationsgeschwindigkeit

## Befund vom 20. Oktober 2026

Ausgewertet wurden das örtliche Gastgeber-`stdout.txt` und das automatisch empfangene Mitspielerprotokoll unter `%LOCALAPPDATA%\TF3MP\Logs\Mitspieler`. Beide liefen mit v62 / Bridge v16. Das angegebene portable v62-Verzeichnis enthält selbst keine Sitzungsprotokolle. Eine örtliche Auswertungskopie bleibt unter `release/diagnostics-20261020-v62`, außerhalb von Git und Windows-Paket. Alle Uhrzeiten unten sind deutsche Ortszeit (UTC+2).

### Vorgabe kam an, Simulation blieb beim alten Tempo

| Zeitpunkt beim Mitspieler | Gemeinsame Vorgabe | Gelesenes `GAME_SPEED.speedup` | Beobachtung |
| --- | --- | --- | --- |
| 17:03:16 | 1×, Version 10 vom Gastgeber | 3 | Ziel 1, Befehl ausstehend |
| 17:03:18 | Pause, Version 11 vom Gastgeber | 3 | Ziel 0, Simulation läuft weiter |
| 17:03:25 | 2×, Version 15 vom Gastgeber | 3 | Ziel 2, Befehl ausstehend |
| 17:03:28 und 17:03:31 | 2× | 3 | Mod wiederholt den Befehl ohne sichtbaren Erfolg |

Damit ist ein Fehler nach dem Empfang belegt. Zusätzlich meldete TF3 örtliche Leistungsgrenzen von 2×/3×/4×. In einem längeren Abschnitt bei eingestellten 3× vergingen beim Mitspieler ungefähr 1,5 Simulationssekunden pro echter Sekunde. Laufende Aktionen und Pausen begrenzen die Aussage von Durchschnittswerten; daraus lässt sich keine bestimmte Hardwareursache ableiten.

Der installierte TF3-Quelltext `gui/main/game.tl`, `GameSpeedHelper`, enthält einen zweiten Regler: Ist die gemerkte Spielerwahl höher als die geschätzte Kapazität, sendet er in jedem GUI-Schritt erneut einen Geschwindigkeitsbefehl. Solange Rückmeldungen ausstehen, liest er externe Tempoänderungen nicht zurück. Ein gemerktes 4× bei Kapazität 3× kann dadurch die vom Mod gesetzten 1×/2× oder die Pause wieder überschreiben. Das erklärt den beobachteten Verlauf und ist im Modell reproduziert; einen nativen Befehlsmitschnitt sämtlicher TF3-internen Wiederholungen enthalten die alten Protokolle nicht.

### Geld und Folgefehler

Um 16:50:35 buchte der Mitspieler **+8.860.940**. Um 17:01:43 folgte **−6.183.317**, danach unter anderem **+3.461.113**. Die nativen Buchungen wurden angenommen; mehrere spätere Rückrufe beobachteten die Änderung direkt im Konto. Der Fehler ist daher nicht allgemein eine ausgefallene Journalbuchung.

Vergleiche erfolgten nach gleicher Simulationszeit. Bei abweichenden Uhren liegen gemeinsame Spieleraktionen aber auf unterschiedlichen Seiten dieses Messpunkts. Beim Vergleich 682 unterschieden sich zusätzlich Konstruktionen, Linien, Halte und Fahrzeuge. Eine Differenz solcher Konten darf nicht ungeprüft als laufender Wirtschaftsunterschied gebucht werden. Die alte Vergleichslogik berücksichtigte diese unterschiedlichen Aktionsstände nicht.

Um 16:59:22 scheiterte beim Gastgeber eine aus dem Mitspielerspiel übernommene Haltestelle bei ungefähr **−2606, −3131** schon vor dem nativen Bau: `street stop parcel cleanup: attempt to index local 'proposal' (a nil value)`. `Command<T>` ist in der ausgelieferten API undurchsichtig; der Inhalt steht erst im Ausführungsrückruf. Der bisherige Test hatte dagegen ein direkt lesbares `command.proposal` erfunden. Danach fehlte die Haltestelle für „Bus Lychen“ und eine neue Linie; weitere Umbenennungen und Fahrzeugzuweisungen konnten diese Linie ebenfalls nicht finden.

## Änderungen

- **Ein gemeinsamer Kapazitätsregler:** Die native Hauptoberfläche gibt während einer vorbereiteten Multiplayer-Sitzung die vollständige Spielerwahl weiter, ohne ihren eigenen Kapazitätsregler zusätzlich zu wiederholen. Nur der Mod begrenzt die Vorgabe gemeinsam anhand der wirklichen Schätzung beider PCs. Der Hook ist auf den Haupt-GUI-Lua-Zustand beschränkt; die getrennte Spielskript-GUI liest weiterhin die wirkliche Schätzung. Ohne aktive gemeinsame GUI, außerhalb von Gastgeber/Mitspieler oder ohne Reihenfolgemodus gilt das originale Verhalten.
- **Echter Zeitfortschritt:** Alle zehn Sekunden bei unverändertem Tempo wird die aus `GAME_TIME` gemessene Geschwindigkeit protokolliert. Automatische Pausen, Tempoänderungen, Laden und längere Unterbrechungen beginnen ein neues Messfenster. Die Messung ist Diagnose und erfindet keine zusätzliche Rechenleistung.
- **Vergleichbare Geldstände:** Wirtschaftsvergleiche enthalten die letzte abgeschlossene gemeinsame Aktionsnummer und einen Hinweis auf laufende Aktionen. Unterschiedliche Nummern, ausstehende Aktionen, unterschiedliche Bestandszahlen oder bekannte unterschiedliche dauerhafte Weltinhalte verhindern Geldbuchungen aus diesem Vergleich. Erst zwei aufeinanderfolgende passende Vergleiche erlauben die Korrektur. Vor der Ausführung wird erneut geprüft, ob weitere Aktionen oder andere Geldkorrekturen erfolgt sind. Ein veralteter Auftrag wird verworfen, ohne den Geldabgleich dauerhaft abzuschalten. Abweichende native Kreditpläne bleiben separat behandelt.
- **Undurchsichtige Baubefehle:** Fehlt die native Vorschau, wird der ursprüngliche Haltestellenbau genau einmal an TF3 übergeben. Es gibt keinen Lua-Zugriff auf ein fehlendes `proposal` und keinen vorgeschalteten Abriss. Ein echter nativer Parzellenkonflikt bleibt eine Ablehnung. Die zusätzliche Parzellenzusammenstellung ist nur bei tatsächlich lesbarer Vorschau möglich.

## Automatische Prüfung

**626 Prüfungen bestehen jeweils unter Lua 5.4 und Lua 5.2**, darunter 101 Synchronisierungs-, fünf Kapazitätsregler-, 18 Hauptoberflächen- und 14 Haltestellenprüfungen. Alle 25 ausgelieferten Lua-Quellen einschließlich Ladehilfe kompilieren in beiden Runtimes. Zusätzlich bestehen 71 Launcher-/Protokoll-, zehn Sitzungs-, 39 Aktionsfehler- und 321 Layoutprüfungen (100 %, 150 %, 200 %); alle 18 PowerShell-Quellen sind syntaktisch geprüft.

Zusätzlich wurde der unveränderte `GameSpeedHelper` aus der örtlich installierten TF3-Version in einer nachgebildeten GUI-Laufzeit ausgeführt, ausschließlich nach Entfernung der Teal-Typangaben. Ohne Korrektur überschreibt er die empfangenen Werte Pause/1×/2× wieder mit 3×. Mit Korrektur bleiben alle drei Werte auch über folgende GUI-Schritte bestehen. Diese Ausführung prüft den tatsächlichen TF3-Skriptcode mit simulierten nativen Befehlen; sie ersetzt keinen Test in der laufenden Engine oder mit zwei PCs.

## Grenzen und Gegentest

Beide PCs brauchen **v63 / Bridge v16**. Das neue Paket repariert bereits fehlende Bauten, Linien oder unterschiedlich gewachsene Städte nicht rückwirkend. Zum Test einen frischen Gastgeberstand teilen oder einmal ausdrücklich **Neu abgleichen**. Insbesondere die bereits fehlende Lychen-Haltestelle muss im gemeinsamen Ausgangsstand vorhanden sein.

Abwechselnd auf beiden PCs 1×, 2×, 4×, Pause und Fortsetzen wählen und jeweils etwa 15 Sekunden warten. Beim Mitspieler müssen sich die Fahrzeuge und die protokollierte Simulation tatsächlich entsprechend ändern. 4× darf an der gemeinsamen Kapazität begrenzt werden. Danach bei hohem Tempo einen Fahrzeugbefehl ausführen und ein Menü öffnen/schließen; die automatische Pause muss zurückkehren und wieder enden, ohne die Spielerwahl umzuschreiben.

Eine Haltestelle bauen und eine Linie darüber erstellen. TF3 kann unterschiedliche Parzellen weiterhin ablehnen, muss dann aber den nativen Fehler statt eines Lua-Fehlers melden. Fahrzeuge kaufen und Geld vergleichen: Unterschiedliche Aktionsstände sollen `money comparison deferred` auslösen; nach zwei passenden Vergleichspunkten soll der normale Geldabgleich weiterarbeiten. Dauerhaft unterschiedliche Bauten blockieren absichtlich einen auf diesen alten Konten beruhenden Geldabgleich und erfordern gegebenenfalls den ausdrücklichen Neuabgleich.

Gleiche Tempoeinstellung garantiert keine vollständig identische Wirtschaft, Fahrzeugposition oder Stadtentwicklung. Der reale Zwei-PC-Gegentest dieser Version steht noch aus. Die Untersuchung startet kein Spiel und verändert keine installierte Spielversion oder Spielstände.

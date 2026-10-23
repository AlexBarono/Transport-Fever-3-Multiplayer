# v69: Tempoauswahl, Straßenanschlüsse und längere Testfolgen

Stand: 23. Oktober 2026. Untersucht: Probe v68 / Bridge v16. Korrekturen: Probe v69 / Bridge v16.

## Protokollbefunde

Die privaten Kopien beider PCs liegen unter `release/diagnostics-20261023-v68/` und werden nicht veröffentlicht. Die zwei B5-Bauaufnahmen ohne Einladungen, Adressen oder Windows-Pfade liegen als Regressionen unter `tests/fixtures/road-extension-v68.b5` und `road-dependent-v68.b5`.

- **14:51:09 Ortszeit:** Der Gastgeber findet beim vom Mitspieler übernommenen Straßenbau den Anschluss nahe `-485.5, 1815.3` nicht. Die Ausführung wird vor einem Spielbefehl abgelehnt.
- **14:51:12:** Der nächste Bau benötigt den Anschluss nahe `-728.8, 1757.2`, der durch den vorherigen, fehlgeschlagenen Bau hätte entstehen sollen. Auch diese Aktion wird vor einem Spielbefehl abgelehnt.
- **15:00:01:** Der Mitspieler veröffentlicht `speed=3`, obwohl die Bedienung nur Pause, 1×, 2× und 4× anbietet. Vorher war die gemeinsame Auswahl 4×, bei tatsächlichen Zielwerten von 2×/3×. Der Gastgeber misst ungefähr 1,3–1,6× tatsächlichen Zeitfortschritt.
- Die Internetverbindung bleibt währenddessen bestehen. Die Protokolle zeigen außerdem zunehmende Unterschiede bei Fahrzeugen, Linien, Bauwerken und Geld. Diese Unterschiede werden durch die beiden korrigierten Suchfälle nicht rückwirkend beseitigt.

Die Bauaufnahme belegt eine auf der Empfängerseite fehlgeschlagene Knotensuche. Sie enthält keinen vollständigen Straßen-Graphen beider PCs zum Fehlerzeitpunkt. Daher lässt sich allein daraus nicht beweisen, ob der Knoten nur im Suchindex fehlt oder die Straße tatsächlich abweicht. Die Korrekturen unterscheiden diese Fälle weiterhin.

## Korrekturen

### Explizite Tempoauswahl

Die normale Spieloberfläche meldet jetzt die angeforderte Stufe mit einer laufenden Nummer über den bestehenden Bridge-Zustand `speedui`. Der getrennte Mod-GUI-Zustand verarbeitet jede neue Auswahl einmal und speichert die zuletzt verarbeitete Nummer in seinem bestehenden Zustand.

Dadurch funktioniert auch der bisher nicht erkennbare Fall **4× gewünscht, intern bereits auf 2× begrenzt, Benutzer klickt 2×**: Der tatsächliche Komponentenwert ändert sich dabei nicht, die ausdrückliche Auswahl wird trotzdem übertragen. Sobald dieser Weg aktiv ist, werden spätere ungemeldete Komponentenänderungen als mögliche verspätete Rückmeldungen behandelt und überschreiben keine neuere Auswahl. Ohne diesen Weg bleibt die bisherige Erkennung anhand der Komponentenwerte verfügbar.

Automatische Menü- und Aktionspausen werden nicht als ausdrückliche Benutzerauswahl veröffentlicht. Wiederaufnahme und ältere gespeicherte/empfangene 3×-Vorgaben werden in geordneten Sitzungen als gewünschte 4× behandelt. Der tatsächliche Zielwert darf weiterhin 3× sein: Das ist die Leistungsbegrenzung des Spiels, kein zusätzlicher Knopf. Die Änderung hebt diese Grenze nicht auf und garantiert keine tatsächlichen 4×.

### Anschlussknoten suchen

Bei einem Trefferfehler ergänzt die Suche den Straßenindex höchstens einmal pro Nachbau mit direkt lesbaren `BASE_NODE`-Entitäten, sofern die installierte API diese Aufzählung unterstützt. Die Suchentfernung bleibt gleich. Beschädigte, unvollständige und nicht endliche Knotenpositionen werden einzeln ausgeschlossen.

Die Auflösung vorhandener Knoten wird erst nach der Prüfung zu entfernender Segmente endgültig abgelehnt. Ein eindeutig bestätigtes Segment kann dadurch seine tatsächlichen Endknoten liefern, auch wenn die getrennte Suche keinen Treffer hatte. Schutz vor mehrdeutigen oder gebäudeeigenen Straßen bleibt erhalten.

Ein wirklich fehlender Straßenanschluss wird weiterhin abgelehnt. Es wird kein abgesetzter Ersatzknoten erzeugt und kein beliebiger Nachbaranschluss gewählt. Die zweite aufgezeichnete Aktion bleibt ohne ihren vorherigen Bau ebenfalls nicht ausführbar. Für einen bereits abweichenden Stand ist einmal ein ausdrücklich gewählter gemeinsamer Spielstand nötig; fehlende Abschnitte danach erneut bauen.

## Tests und Reproduktion

```powershell
python -m pip install lupa==2.8
python tests/run_lua_suites.py
```

Der Runner kompiliert 25 Lua-Quellen und führt alle 19 Suiten getrennt unter Lua 5.4 und Lua 5.2 aus. Jede Suite läuft in einem eigenen Prozess mit Zeitbegrenzung. Die verwendeten Laufzeiten stammen aus [Lupa](https://pypi.org/project/lupa/); die Windows-Releaseprüfung richtet Python mit [setup-python](https://github.com/actions/setup-python) ein.

Neue Abdeckung:

- Beide aufgezeichneten Straßenaktionen: vorhandener, aber im Index fehlender Anschluss; tatsächliches Fehlen; abhängiger Bau nach erfolgreichem Vorgänger und gemeinsamer Ausgangskarte.
- Eindeutige Segmentendpunkte trotz fehlendem Einzeltreffer, ungültige Knotenpositionen und nicht verfügbare zusätzliche API-Aufzählung.
- Tatsächlicher GUI-Einstieg mit nativen Tempo-Befehlen und einem zum Bridge-Protokoll passenden Zustandsnamen.
- Unveränderter 2×-Messwert bei einer neuen 2×-Auswahl, doppelte Anforderungsnummer, wiederhergestellter GUI-Zustand, interne 3×-Wiederaufnahme und verspätete alte Rückmeldungen.
- **16.000 GUI-Schritte** mit zwei simulierten PCs, wechselnden Leistungsgrenzen und 1.000 abwechselnden Tempoauswahlen einschließlich Pause.
- **10.000 Aktionsabschlüsse / 20.000 Befehlsrückmeldungen**, einschließlich doppelter und verspäteter Rückmeldungen sowie 103 absichtlich abgelehnter Aktionen. Jede Ablehnung wird einmal gemeldet; nachfolgende unabhängige Aktionen bleiben ausführbar.

Die Suiten umfassen insgesamt 646 bestandene Prüfungen je Lua-Laufzeit. Die wiederholten Schritte innerhalb der längeren Testfälle sind darin nicht als einzelne Prüfungen gezählt. Netzwerk und native Spielausführung werden dabei simuliert. Ein realer fehlerfreier Dauerlauf oder die Reparatur jedes abweichenden Stadtstraßen-Graphen ist damit nicht nachgewiesen.

## Nächster Gegentest

Beide PCs auf v69 aktualisieren und denselben gewünschten Spielstand laden. Pause, 1×, 2× und 4× in beiden Rollen prüfen; besonders 2× bei bereits auf 2× begrenzter 4×-Vorgabe und schnelle Wechsel. Danach die beiden Straßenverlängerungen ausführen und mindestens 60 Minuten mit Linien, Käufen, Bauaktionen und normalen Pausen protokollieren. Dieser reale Dauerlauf bleibt ein offener Punkt der [Roadmap](roadmap.md).

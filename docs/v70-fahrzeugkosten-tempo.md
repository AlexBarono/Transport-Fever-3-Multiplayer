# v70: Fahrzeugkosten, Erneuerung und Spieltempo

Stand: 23. Oktober 2026. Untersucht: Probe v69 / Bridge v16. Korrektur: Probe v70 / Bridge v16.

## Befunde aus beiden Protokollen

Die privaten Momentaufnahmen liegen unter `release/diagnostics-20261023-v69/` und werden nicht ins Paket oder Repository aufgenommen. Grundlage sind Gastgeber-stdout/Bridge-Status und die beim Gastgeber gespeicherten Mitspielerprotokolle vom gleichen Lauf.

- Um 16:20:45–16:21:14 Ortszeit wird „Zug 20“ zweimal einer Linie zugewiesen. TF3 lehnt beide Versuche **auf beiden PCs** ab und liefert keine konkrete Wegdiagnose. Der vorherige Kauf wird übernommen. Eine allein auf dem Empfänger fehlgeschlagene Übertragung ist damit nicht belegt; passende Depotanschlüsse, Elektrifizierung und erreichbare Halte bleiben zu prüfen.
- Um 16:39:53 und 16:40:22 lehnt der Gastgeber zwei empfangene Lager-/Bahnhofsumbauten mit **„Kollision“** ab. Die Preisvorschläge 301682 und 60126 sind keine Ausführungsbestätigung: `success=false`, keine neuen Entitäten. Die Weltstände unterscheiden sich bereits bei Bauwerken und Spielzeit. Die Ursache der konkreten geometrischen Kollision lässt sich ohne damalige Kartenansicht nicht genauer bestimmen.
- Die 4×-Vorgabe kommt beim Mitspieler an. Die Mod setzt jedoch selbst `tg=2` beziehungsweise `tg=3`, abgeleitet aus den geschätzten Leistungswerten. In längeren Abschnitten misst der Mitspieler trotz gewünschter 4× nur ungefähr 1,0–1,2× Simulationszeit pro realer Sekunde; der Gastgeber etwa 1,3–1,5×.
- Fahrzeugersatz wird bisher mit frisch erzeugten `TransportVehiclePart`-Werten ohne Kaufzeitpunkt gesendet. TF3s installierte native Fahrzeugverwaltung setzt neue Teile dagegen ausdrücklich auf die aktuelle Spielzeit. Zusätzlich vergleicht die Mod bisher nur Modell/Konfiguration; eine Erneuerung mit demselben Modell kann daher ganz ohne ausgehende Ersatzaktion bleiben. Die vorhandenen Protokolle enthalten keine Kontobelege einzelner Ersatzbefehle; die genaue historische Differenz ist daraus nicht nachträglich rekonstruierbar.

## Änderungen

### Fahrzeugkauf und Ersatz

Der Snapshot führt nun den Kaufzeitpunkt jedes Teils mit. Für einen Ersatz werden neue Teile und einmalig zugeordnete, weiterverwendete Teile unterschieden. Gleiches Modell und gleicher Kaufzeitpunkt identifizieren im sendenden Spiel einen weiterverwendeten Wagen. Der Empfänger setzt dafür **seine eigenen** bisherigen Kauf- und Wartungsdaten ein. Neue Teile erhalten die **aktuelle Zeit des empfangenden Spiels**, entsprechend TF3s eigener Fahrzeugverwaltung.

Ein geänderter Kaufzeitpunkt löst nun auch bei unverändertem Modell eine Ersatzaktion aus. Die allgemeine Fahrzeugidentität bleibt unabhängig von fremden Spielzeiten. Ohne lesbare lokale Erwerbszeit wird vor dem Kauf abgebrochen. Ungültige oder mehrfach zugeordnete Wagen werden vor dem nativen Befehl zurückgewiesen.

Die Mod bucht keine geschätzten Kaufpreise zusätzlich. Die native Kauf-/Ersatzfunktion berechnet Kosten und Erlöse; vorher/nachher gelesene Kontostände samt Differenz werden als `native account` protokolliert. Doppelte native Rückmeldungen führen nur einmal zu Folgeaktionen und Kontobelegen. Beim Versionswechsel setzt der bestehende Upgradepfad die Beobachtungsbasis zurück; vorhandene Fahrzeuge werden nicht als neue Käufe ausgegeben.

### Tempo

In geordneten Zwei-PC-Sitzungen wird die gemeinsame Stufe 0/1/2/4 unverändert gesendet. Geschätzte Leistungswerte bleiben Diagnosewerte und reduzieren den Befehl nicht ein zweites Mal. Das gilt ebenfalls für direkte GUI-Befehle, den Simulationsersatzweg und die Wiederaufnahme nach Menü-/Aktionspausen. Die native GUI-Wiederholung bleibt unterdrückt; Auswahl und ausdrückliche Benutzeranforderungen bleiben getrennt von verspäteten Komponentenwerten.

Dies fordert den vollen Faktor an, erhöht aber nicht die Rechenleistung der PCs. Gemessener Zeitfortschritt und gemeinsame Vorgabe werden weiterhin getrennt protokolliert. Bestehende Simulationstaktunterschiede oder Kartenabweichungen werden dadurch nicht rückwirkend repariert.

### Fehlgeschlagene Bauten

Die konkrete native Meldung wird in die Ablehnungsdiagnose übernommen, auch wenn TF3 unverbindliche positive Baukosten und einen nicht kritischen Fehler liefert. Eine abgelehnte Station wird nicht noch einmal als neuer Bau ausgeführt. Die beiden bestehenden Kollisionen werden durch diesen Diagnoseanteil nicht geometrisch behoben.

## Automatische Prüfung

`python tests/run_lua_suites.py` führt 20 Suiten mit insgesamt 658 Prüfungen je Lua-Version (5.4 und 5.2) aus; zusätzlich werden 25 Quelldateien kompiliert. Enthalten sind:

- Kauf mehrerer Teile mit vollständigen nativen Kaufdaten und geprüftem Kontostand;
- Erneuerung mit demselben Modell und Abrechnung des Ersatzes;
- Ergänzen, Umordnen und Weiterverwenden von Wagen mit lokaler Alterung/Wartung;
- reine Farb-/Richtungsänderungen ohne erneuten Kauf, identische Wagenzeiten, abgelehnter Ersatz, ungültige Zuordnungen, fehlende Spielzeit und doppelte Rückmeldungen;
- echte Mod-GUI-Steuerung mit getrennter nachgebildeter nativer Tempooberfläche, verzögerten Bridge-Echos und Befehlen, beiden Bedienrollen und geprüftem Simulationszeitfortschritt für Pause/1×/2×/4×;
- weiterhin 16.000 GUI-Schritte sowie 10.000 Aktionsabschlüsse mit absichtlich eingebauten Ablehnungen und doppelten Rückmeldungen;
- synchrone und asynchrone Bauablehnung „Kollision“ trotz positiver Preisvorschläge.

Native Spielausführung, Fahrzeugpreisberechnung und Netzübertragung werden in diesen Tests simuliert. Insbesondere ist damit weder die historische einzelne Fehlbuchung noch ein fehlerfreier Dauerlauf auf zwei realen PCs bewiesen. Der erforderliche Gegentest steht in der [Roadmap](roadmap.md).

## Anwenden

Beide PCs auf v70 aktualisieren und denselben gewünschten Gastgeberstand laden beziehungsweise ausdrücklich neu abgleichen. Anschließend Kauf und Zugersatz samt Kontobelegen sowie alle vier Tempostufen in beiden Rollen prüfen. Für die bereits abgelehnten Gebäudeumbauten die konkrete Kollision prüfen; ein Update ergänzt diese Bauten nicht nachträglich.

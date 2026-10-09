# v45: Linienzuweisung von Zug 5 und Auswertung der v44-Sitzung

## Beobachtet am 9. Oktober 2026

Die gesicherten lokalen Originale liegen unter `release/diagnose-v44-vpn/`. Zeiten hier sind Ortszeit (UTC+2). Die vier Kennungen `scheduled_client.1`, `scheduled_client.2`, `scheduled_host.3` und `scheduled_client.4` wurden zwischen 16:44:03 und 16:46:19 jeweils auf beiden PCs abgelehnt. Die acht Launcher-Einträge waren damit vier gescheiterte Versuche für Zug 5 auf der Linie „Holz -> Sägewerk“. Die Verbindung lief weiter, auch spätere Netzwerkaktionen wurden quittiert.

Das Protokoll bestätigt erstmals die Haupt-GUI-Hooks im echten Spiel: sechs installierte Hooks, abgefangene Linienbefehle und Übergabe an den gemeinsamen Zeitplan. Zug 5 hatte auf dem Gastgeber die Entity 112306, auf dem Mitspieler 120349. Die geplanten Pakete enthielten jeweils Halt 0. Den ursprünglichen Haltparameter vor dem Abfangen protokolliert v44 nicht; eine rein physische Fahrwegsperre ist deshalb als weitere Ursache noch nicht ausgeschlossen.

Zwei konkrete Fehler im Code sind unabhängig davon nachgewiesen:

1. TF3s mitgeliefertes GUI-Skript `gui/line_vehicle_mgmt/first_stop_to_send/scheme_nextreachable.script.tl` sendet absichtlich Halt `-1`. Sowohl der Fahrzeug-Hook als auch der Eingang in den Zeitplan ersetzten diesen gültigen Wert durch 0. Damit kann eine Zuweisung fehlschlagen, obwohl ein anderer Halt erreichbar wäre. V45 erhält `-1` an beiden Stellen; ein ausdrücklich gewählter Halt 0 bleibt 0.
2. Der native Fenster-Rückruf erwartet `VehicleSetLineCommandData` mit `vehicleEntity`, `lineEntity` und `stopIndex`. Der Mod übergab stattdessen das undurchsichtige `Command`-Objekt. Das Spielprotokoll bestätigt einen Konvertierungsfehler beim Lesen von `result.vehicleEntity` in `manager_window.tl:4727`. Die Hooks liefern jetzt die passenden Befehlsdaten für alle fünf abgefangenen Befehlsarten. Die frühe Freigabe des GUI-Callbacks bleibt eine Bestätigung der Übergabe; den tatsächlichen Ausführungserfolg prüft weiterhin separat die Transportquittung.

Zusätzlich wird der Erfassungsstand eines geplanten Fahrzeugbefehls erst nach positiver Spielantwort angepasst. Eine Ablehnung darf dort keine angewandte Linienzuweisung vortäuschen und dadurch einen gegenläufigen Änderungsbericht erzeugen. Bei einer abgelehnten Linienzuweisung fragt V45 `api.engine.util.line.getFailedPathReason` ab. Falls diese Diagnose verfügbar ist, enthält die Meldung beispielsweise fehlenden Fahrweg, fehlende Elektrifizierung und die Problemposition. Fehlt die Funktion im aktuellen Skriptzustand, wird das ausdrücklich protokolliert; der Fehler bleibt erhalten und spätere Aktionen dürfen weiterlaufen.

Der Launcher zählt beide PC-Meldungen derselben Kennung als eine fehlgeschlagene Aktion und behält beide Detailmeldungen. Neuabgleich startet weiterhin nur auf ausdrückliche Anfrage.

## Weitere Abweichungen und Grenzen

- Beim Straßendepot Fairborn stimmen Datei, Name, Position und Orientierung in den Diagnosen überein; die Parameter-Hashes sind unterschiedlich. Der ursprüngliche Bau enthält `modules={}`, `seed=0`, `year=1912`. Der Hash dieser Parameter entspricht dem lokalen Wert `226d8d30`. Die konkreten abweichenden Parameter des Mitspielers liegen nicht im lokalen Protokoll. Die Meldung allein beweist kein fehlendes Depot.
- Das Gleis-/Straßennetz hat unterschiedliche Hashes. Beide ausgetauschten Detaillisten sind gekürzt und nennen in diesem Vergleich keine konkret abweichende Kante. Daraus lässt sich kein bestimmtes fehlendes Gleis ableiten.
- Beim gemeinsamen Prüfpunkt wurden 2.917.503 gegenüber -543.025 Geld gemeldet. Das lokale Protokoll allein enthält keine vollständige Buchungshistorie des Mitspielers. Diese Differenz ist nicht als Folge der vier abgelehnten Linienzuweisungen nachgewiesen.
- Linien waren wegen `checkpoint value unreadable` weiter unbekannt. Fahrzeugpositionen wurden beim neuen Zug teilweise unlesbar; der Frachtscan erreichte die Grenze von 16.000 nativen Aufrufen, danach blieb auch der Städtevergleich unbekannt. Die Erfassung dauerte in diesem Lauf bis 54 ms. Das sind offene Diagnoseprobleme und kein Nachweis gleicher Welten.

V45 korrigiert die beschriebenen Fahrzeugbefehle und Fehlerberichte. Es gleicht bestehende Weltunterschiede nicht automatisch an und garantiert keinen befahrbaren Weg auf einer bereits abweichenden Karte. Für einen Vergleich kann bewusst derselbe Ausgangsstand geladen werden; ein manueller Neuabgleich übernimmt den Gastgeberstand.

## Gegenprüfung

Die Regressionen führen die tatsächliche GUI-Einstiegsdatei aus und prüfen die Datenfelder der fünf nativen Rückrufe. Ein weiterer Test führt die Wahl `-1` durch GUI-Intent, Zeitplanpaket und Nachbau auf beiden Rollen; auch der Rückfall ohne gemeinsamen Zeitplan erhält den Wert. Ablehnungen behalten den alten Erfassungsstand und liefern die native Fahrwegdiagnose, ohne einen Diagnosefehler zum Spielabbruch werden zu lassen.

Bestanden: 250 Lua-Prüfungen jeweils unter Lua 5.2 und 5.4 sowie 20 Diagnoseanzeigen- und 49 Launcher-/Protokoll-Prüfungen unter Windows PowerShell 5.1. Alle Lua-Dateien des Mods lassen sich unter beiden Versionen übersetzen. Der Launcher-Leser wurde außerdem direkt gegen das gesicherte Spielprotokoll geprüft: vier Aktionen, acht PC-Berichte. Der Paketbau prüft Versionsangaben, Ressourcenmanifest und jede Archivdatei gegen die Quelle.

Echter Test nach Installation von v45 auf beiden PCs: Zug 5 erneut der Linie zuweisen, zuerst vom Mitspieler, dann vom Gastgeber. „Nächsten erreichbaren Halt“ sowie einen ausdrücklich gewählten Halt prüfen. Die Ausfahrt beobachten und bei erneuter Ablehnung die neue Fahrwegmeldung einschließlich Koordinaten prüfen. Ein echter Zwei-PC-Nachweis der Korrektur steht noch aus.

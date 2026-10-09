# VPN-Test vom 9. Oktober 2026: Depotanschluss und weitere Auffälligkeiten

Ausgewertet wurden die lokalen Spiel-, Bridge- und Launcherprotokolle von Probe v40 / DLL v13. Die gesicherten Originale liegen lokal unter `release/diagnose-v40-vpn/` und werden nicht veröffentlicht. Zeiten unten sind Ortszeit (UTC+2); TF3 schreibt UTC.

## Beobachtet

- Die vorbereitete Sitzung lief bis zum Spielende gegen 14:10 Uhr weiter. Der letzte Bridge-Status war verbunden, ohne blockierte Warteschlange oder Fehler. Die letzte Ordnungsnummer war 842; diese zählt auch Diagnosepakete, nicht nur Bauaktionen. Kein automatischer Neuabgleich wurde angefordert.
- Um 13:57:53 und 13:57:54 wurden zwei Gleisänderungen gebaut, aber jeweils eine Knoteneinstellung danach nicht mehr gefunden. Betroffen waren `3777.544,-1096.472` und `3782.229,-1094.725`. Beide Einstellungen enthielten keine expliziten Verbindungen; dennoch benötigten spätere Bauten diese Knoten.
- Das Zugdepot Benbrook wurde um 13:59:06 gebaut. Sein Anschluss um 13:59:13 wurde vollständig übersprungen: Der vorhandene Netzknoten nahe `3782.2,-1094.7` fehlte hier. Es fehlte damit der Netzknoten aus der vorherigen Gleisänderung, nicht das Depot selbst.
- Um 13:59:56 lehnte TF3 eine Linienzuweisung für Fahrzeug 118525 ab. Ein Zusammenhang mit dem fehlenden Depotanschluss ist plausibel, aus dem Protokoll allein aber nicht bewiesen.
- Zwei weitere Gleis-/Signaländerungen um 14:02:23 und 14:02:26 konnten eine referenzierte Kante bei `3330.5,-708.5` nicht finden. Insgesamt wurden sechs Aktionen als fehlerhaft übersprungen. Die vier betroffenen Gleisänderungen waren bereits gebaut; nur ihre anschließende Prüfung scheiterte. Andere Aktionen liefen weiter.
- Vier GUI-Ereignisse konnten `::/mp_probe/build.lua` nicht laden. Die Module lagen korrekt im Mod; das verzögerte `require` im Klick-Callback verwendete den falschen Namensraum. Das verhinderte dort das Zurückhalten für einen gemeinsamen Bauzeitpunkt.
- Der Abschluss eines einzelnen Nachbaus wurde teilweise mehrfach ausgeführt, maximal sechsmal für Token `5708-2556468.200`. Dabei wurden dieselben Knoteneinstellungen erneut ersetzt.
- Der Weltvergleich zeigte Unterschiede bei Fahrzeugen, Positionen, Städten, Konstruktionen und Geld. Die Felder `hedge`, `hline`, `hcargo` waren weiter nicht auslesbar (`Cannot loop over this component type`). Die maximale beobachtete Erfassungsdauer war 28 ms, ein Hash-Schritt höchstens 5 ms; das ist kein Leistungsnachweis für große Karten.
- Der Launcher meldete für 90,1 MB Spielstand 137,5 Sekunden insgesamt; die reine Datenübertragung dauerte 83,5 Sekunden mit vier Verbindungen und etwa 1,1 MB/s. Der Lauf zeigt keinen Übertragungsabbruch. VPN-Durchsatz und Speichern/Laden sind getrennte Zeitanteile.

## Änderungen in v41 und Grenzen der Diagnose

1. Der Replay-Kontext setzt `cleanupStreetGraph=false`, auch für Knoteneinstellungen. Laut mitgelieferter TF3-API vereinfacht diese Option sonst Kanten und Knoten. Ein empfangener Bau enthält bereits das Ergebnis des ursprünglichen Bauvorschlags; eine zweite Vereinfachung kann weitere Knoten entfernen. Die zeitliche Folge im Protokoll passt zu dieser Ursache. Die eingehenden Pakete waren bisher abgeschnitten protokolliert, deshalb ist dies eine begründete Ursachenannahme und noch kein im echten Spiel nachgewiesener Fix.
2. Ein im gemeinsamen Skriptzustand gespeicherter Ausführungsschutz verhindert das erneute Betreten desselben Bauschritts durch verschachtelte Ereignisse. Er wird auch im Fehlerfall freigegeben. Ausstehende Befehle und spätere Prüfungen bleiben erhalten.
3. Der GUI-Abfangcode lädt `build`, `world`, `sync` und `wire` beim Laden des Moduls, während TF3 den Mod-Namensraum auflösen kann. In den GUI-Callbacks erfolgen keine weiteren Modulimporte.
4. Ein empfangener Bau wird einmal vollständig mit Token protokolliert. Wiederholte Zustellungen erzeugen keine weitere Ausführung. Das ermöglicht bei einem verbleibenden Fehler einen genauen Regressionstest aus dem Paket des anderen PCs.

Die tolerante Weltprüfung und der manuelle Neuabgleich aus v40 bleiben erhalten. Der Stand auf dem anderen PC und sichtbare Fahrwege lassen sich aus den lokalen Logs nicht vollständig prüfen. Bereits übersprungene Bauten werden nicht nachträglich rekonstruiert.

## Gegenprüfung mit zwei PCs

Beide PCs müssen v41 verwenden. Einen identischen Ausgangsstand laden oder einmal bewusst **Neu abgleichen**; ein bereits kaputter Gleisanschluss im alten Stand ist kein sauberer Ausgangstest.

1. Auf dem Mitspieler-PC ein Gleis mit mehreren Abschnitten verlegen und Abschnitte ändern, etwa elektrifizieren. Die Änderung am Gastgeber prüfen.
2. Ein Zugdepot neben das Netz setzen und mit dem zuvor geänderten Abschnitt verbinden. Anschluss und befahrbaren Weg auf beiden PCs prüfen.
3. Einen Zug kaufen, einer passenden Linie zuweisen und auf beiden PCs die Ausfahrt beobachten.
4. Danach an verschiedenen Stellen auf beiden PCs bauen. Gleise/Signale nochmals ändern und weiterbauen; die Warteschlange muss weiterlaufen.
5. Weltabweichungen dürfen weiter sichtbar sein und keinen ungefragten Neuabgleich starten. Einen manuellen Neuabgleich nur bei Bedarf prüfen.

Automatische Regressionen modellieren die zusätzliche Graphvereinfachung, den folgenden Depotanschluss, verschachtelte Abschlussereignisse und einen GUI-Callback ohne gültigen Modul-Namensraum. Sie ersetzen diesen echten VPN-Test nicht.

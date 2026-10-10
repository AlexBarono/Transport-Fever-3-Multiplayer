# v51: automatischer Beitritt und gemeinsamer Start

Der Gastgeber stellt einen Spielstand bereit. Auf dem Mitspieler-PC genügt es, unter **Beitreten** seine Adresse oder Interneteinladung einzufügen und den Launcher offen zu lassen. Ein eigener Beitritts-, Download- oder Startknopf entfällt.

1. **Warte auf Spielstand vom Gastgeber:** Empfang läuft im Hintergrund. Spielversion, Multiplayer-Paket, zusätzliche Mods und Dateiinhalt werden geprüft. Gleichnamige alte Spielstände bleiben als `.bak` gesichert; die Rückfrage entfällt.
2. **Warte auf das Starten des Gastgebers:** Der Stand liegt vollständig vor und die Mod ist eingerichtet. Der Mitspieler hat seine Bereitschaft bestätigt.
3. Beim Gastgeber ist **Spiel starten** zunächst grau. Nach der Bestätigung wird der Knopf grün und heißt **Spiel für beide starten**. Der Mitspieler öffnet TF3 über Steam und bestätigt die Startanforderung; darauf öffnet der Gastgeber sein TF3. Wiederholte Nachrichten starten keine zweite Instanz.
4. Beide wählen im Spiel den angezeigten gemeinsamen Stand und laden ihn pausiert. Der Launcher übernimmt den Programmstart; die erste Auswahl der Welt bleibt im TF3-Menü. Die Verbindung wartet auf beide geladenen Karten.

**Neu abgleichen** gibt es nur beim Gastgeber. Im laufenden Spiel löst er den Austausch und das Laden eines frischen Gastgeberstands auf beiden PCs aus. Der Mitspieler klickt nichts. Abweichungen bleiben Hinweise und erzwingen keinen Neuabgleich.

Die Oberfläche trennt Verbindung, gemeinsamen Start und Protokoll. Wichtige Statuswechsel, Übertragungen und fehlgeschlagene Aktionen mit Beschreibung, Ursache und Kennung erscheinen automatisch im Protokoll. **Details prüfen** bleibt für die Auswertung im Testlabor erhalten.

**Nur Einstellungen speichern** kopiert Mod und Bridge, schreibt Rolle, Verbindung und Sitzung, öffnet jedoch kein Spiel. Im normalen Ablauf geschieht das automatisch. **Am selben Ort nachbauen** wiederholt im Test *Gleiche Stelle* eine Bauaufnahme nach dem Neuladen des ursprünglichen Spielstands. Beide Werkzeuge stehen deshalb nur noch im Testlabor.

## Prüfung

`tests/run_lobby.ps1` verwendet echte TCP-Verbindungen, Hintergrundempfänger und den IPv6-TLS-Tunnel. Steamstart, Firewalländerungen und das Spiel sind dabei ersetzt. Geprüft werden automatischer Empfang mit Überschreiben/Sicherung, Bereitschaft nach Einrichtung, Startbestätigung, doppelte Start-/Neuabgleichnachrichten, falsche Startkennung, fremde Sitzung, Abbruch und Rollen der sichtbaren Bedienelemente. Auch gleichzeitige Launcher-/Spielkanal-Benachrichtigungen werden als derselbe Neuabgleich behandelt.

Bisher bestanden: 23 Lobby-/Start-, 60 Launcher-, 44 Übertragungs-, zehn Sitzungs-, 34 Neuabgleich-, 29 Aktionsdiagnose- und 140 Haupt-Mod-Prüfungen (Windows PowerShell 5.1 / Lua 5.4). Die bestehenden Übertragungs-, Sitzungs-, Launcher- und Neuabgleichtests bleiben zusätzlich relevant.

Ein echter Test mit zwei PCs bleibt nötig:

1. v51 auf beiden PCs verwenden. Erst den Mitspieler-Launcher öffnen und die Adresse einfügen, danach beim Gastgeber den Stand bereitstellen. Die Oberfläche muss während des Wartens bedienbar bleiben.
2. Beim Mitspieler bereits einen anderen gleichnamigen Teststand haben: keine Rückfrage, neue Datei stimmt, alte Datei als `.bak` vorhanden. Einen dafür entbehrlichen Teststand verwenden.
3. Gastgeberstart muss bis zur bestätigten Einrichtung grau bleiben. Grün anklicken: Steam/TF3 öffnet sich auf beiden PCs. Auf beiden denselben angezeigten Stand pausiert laden, dann bauen.
4. Gastgeber klickt im laufenden Spiel einmal **Neu abgleichen**. Beide Spiele müssen den frischen Stand laden; beim Mitspieler ist kein Klick nötig. Danach eine Bauaktion in jede Richtung prüfen.
5. Launcher-Verbindung vor dem Start unterbrechen: Start darf nicht freigegeben bleiben. Vor einem neuen Versuch TF3 schließen und den Stand erneut bereitstellen. Das Schließen des Launchers beendet seine Internetfreigabe; beide Launcher bleiben während der Sitzung offen.
6. Den Ablauf zusätzlich über die Interneteinladung von zwei Anschlüssen prüfen. Der lokale TLS-Test beweist keine externe Router-/Firewall-Erreichbarkeit.

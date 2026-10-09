# v47: Weiterlaufen trotz gelber Weltabweichung

## Befund im letzten lokalen Spielprotokoll

Im Lauf vom 9. Oktober war die Verbindung weiterhin aktiv: Die DLL meldete `connected=1`, `blocked=0`, einen leeren Fehlertext und `world_fields=hcon,hedge`. Die gelbe Weltmeldung allein war kein Grund für eine Pause.

Die letzten relevanten Ereignisse stehen im Spielprotokoll in UTC:

- 21:59:40: Für die gemeinsame Aktion 2 hielt der Zeitplan das Spiel an; die vorherige Laufgeschwindigkeit war 4x.
- 21:59:43: Dieser PC bestätigte seine Ausführung. Die Pause blieb bis zur gemeinsamen Freigabe bestehen.
- 22:00:02: Der Zeitplan wurde wieder frei. Die GUI entfernte ihren Pausenmarker unmittelbar beim Senden des Fortsetzen-Befehls.
- Noch um 22:00:02 wurde die weiterhin sichtbare automatische Pause als neue Benutzerentscheidung veröffentlicht: `speed=0`, Version 14.
- Bis 22:00:04 wechselten Pause und 4x über mehrere Versionen zwischen den PCs; zuletzt blieb `speed=0`, Version 18, bestehen.

Der Fortsetzen-Befehl kann später wirksam beziehungsweise in der GUI sichtbar werden als sein Aufruf. Der bisherige synchrone Test hatte diese Verzögerung nicht nachgestellt.

## Korrektur

Nach einer gemeinsamen Aktionspause bleibt die Wiederaufnahme als automatischer Vorgang markiert, bis das Spiel die Zielgeschwindigkeit anzeigt. Der Marker liegt auch im DLL-Zustandskanal, damit eine neu aufgebaute GUI-Lua-Umgebung die Pause ebenfalls nicht als Benutzerentscheidung weitergibt. Ein nach bestätigtem Fortsetzen gewähltes anderes Tempo wird übernommen. Fehlende Bestätigungen lösen nur eine begrenzte Zahl von Wiederholungen aus.

In einer normalen geordneten Zwei-PC-Sitzung hält das Aufholen den vorauslaufenden PC nicht mehr bei einem Zeitversatz über zwei Minuten an. Beschleunigen des rückständigen Spiels und gegebenenfalls langsameres Weiterlaufen bei Maximaltempo bleiben möglich. Die Simulation darf zusätzlich nicht allein wegen eines fehlgeschlagenen Zeitplans ohne geplante Aktion eine Pause erzwingen.

Gelbe Weltabweichungen bleiben Hinweise. Neuabgleich bleibt manuell. Eine laufende gemeinsame Aktion pausiert weiterhin bis zur nötigen Bestätigung beider Spiele; diese Sicherung wird durch die Korrektur nicht aufgehoben.

## Prüfung

Die Regressionstests stellen verzögert angewandte Geschwindigkeitsbefehle auf Gastgeber und Mitspieler, verlorenen GUI-Speicher, mehrere Minuten Zeitversatz bei gelber Weltabweichung sowie nachfolgende echte Pause- und Tempoänderungen nach. Die beiden Hauptfälle schlugen vor der Korrektur fehl und bestehen danach. Bestehende Prüfungen für gemeinsame Aktionspausen bleiben erhalten.

Beide PCs brauchen v47. Im echten Gegentest bei gelber Weltmeldung 1x, 2x und 4x wählen; das Spiel soll weiterlaufen. Anschließend eine gemeinsame Bauaktion auslösen: Nach ihrer Bestätigung muss die vorherige Geschwindigkeit wiederkommen. Eine danach bewusst gewählte Pause und deren Aufhebung müssen weiterhin auf beiden PCs ankommen. Für v47 wurde kein echter neuer Zwei-PC-Lauf gestartet.

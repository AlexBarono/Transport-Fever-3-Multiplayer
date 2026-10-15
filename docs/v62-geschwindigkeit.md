# v62: Gemeinsame Geschwindigkeit

## Befund vom 15. Oktober, etwa 16:17–16:29 Uhr

Gastgeberprotokoll und automatisch empfangenes Mitspielerprotokoll zeigen dieselben übertragenen Geschwindigkeitsversionen 1 bis 18. Der Kalender blieb bei 4000 ms pro Tag. Der Fehler entstand nach dem Empfang in unserer örtlichen Geschwindigkeitssteuerung:

| Zeitpunkt | Beobachtung |
| --- | --- |
| 16:19:53, Mitspieler | Gemeinsame Vorgabe 2×, örtliches Ziel 4× wegen 30 Sekunden Rückstand. |
| 16:22:12, Gastgeber | Gemeinsame Vorgabe 4×, örtliches Ziel 2× wegen 30 Sekunden Vorsprung. |
| 16:24:56, Mitspieler | Nach einer Subventionsaktion wird ein altes örtliches Aufholtempo 4× statt der gemeinsamen Vorgabe 3× wiederhergestellt. |
| 16:25:56 und danach, Mitspieler | Mehrere empfangene 1×-Vorgaben werden wegen 60 Sekunden Rückstand wieder zu 2×. |

TF3 meldete außerdem wechselnde Leistungsgrenzen von 3× und 4×. Eine verspätete Antwort auf einen eigenen Geschwindigkeitsbefehl konnte dabei als neue Spieleränderung veröffentlicht werden. In dieser Sitzung sind keine neuen abgelehnten Spielaktionen oder Lua-Abstürze belegt. Die letzten Aktionswarteschlangen sind leer; Fahrzeug- und Stadtabweichungen bleiben sichtbar.

## Korrekturen

Normale vorbereitete Zwei-PC-Sitzungen verwenden dieselbe Geschwindigkeitsvorgabe, ohne einen PC wegen seines Zeitversatzes eigenständig schneller oder langsamer laufen zu lassen. Der bisherige Aufholtest im Testlabor bleibt möglich. Das entspricht der gewünschten Priorität: gemeinsam bauen, Zeit- und Weltabweichungen zunächst tolerieren, nur bei Bedarf neu abgleichen.

Beide Spiele veröffentlichen unter `max` ihre örtliche TF3-Leistungsgrenze. Bei frischen Partnerdaten gilt die niedrigere Grenze gemeinsam. Die Spielerwahl bleibt davon getrennt gespeichert; wenn beide Spiele wieder mehr schaffen, kann das gewünschte Tempo ohne erfundene Benutzeränderung zurückkehren. Unterbrochene Verbindungen liefern keine dauerhafte fremde Leistungsgrenze.

Ausstehende Geschwindigkeitsbefehle und kurzzeitig erwartete verspätete Antworten bleiben im GUI-Zustand gespeichert. Dadurch kann auch ein neu erzeugter Lua-Zustand eigene Antworten zuordnen. Eine unterscheidbare neue Spieleränderung während eines ausstehenden Befehls wird unmittelbar berücksichtigt. Nach einer gemeinsamen Aktions- oder Menüpause wird die gemeinsame Vorgabe statt eines früheren örtlichen Aufholtempos verwendet und an der gemeinsamen Leistungsgrenze begrenzt.

Die Übertragung und Verarbeitung benötigen weiterhin Zeit; unterschiedliche Anzeigen während einer laufenden Änderung können kurz vorkommen. Ein ausdrücklicher Klick auf genau den Wert einer noch erwarteten eigenen Antwort lässt sich aus dem gelesenen `GAME_SPEED` allein nicht sicher unterscheiden. Gleiche Tempoeinstellung garantiert außerdem keine vollständig identische Simulation. Weltabweichungen lösen weiterhin keinen automatischen Neuabgleich aus.

## Gezielter Zwei-PC-Test

Beide PCs verwenden **v62 / Bridge v16** und laden denselben Gastgeberstand. Abwechselnd auf beiden PCs 1×, 2×, 4×, Pause und Fortsetzen wählen. Nach dem Empfang müssen beide dieselbe Vorgabe verwenden; wenn ein PC nur 3× schafft, müssen beide die gemeinsame Grenze berücksichtigen. Bei einem bestehenden Zeitversatz darf 1× nicht wieder von selbst zu 2× werden.

Bei 1× und 4× jeweils ein Fahrzeug zuweisen oder umdrehen, anschließend ein Spielmenü öffnen und schließen. Nach abgeschlossenen Aktionen und geschlossenen Menüs muss die vorherige gemeinsame Vorgabe zurückkehren. Eine bewusst gewählte Pause bleibt erhalten. Mehrere schnelle Tempoänderungen aus beiden Richtungen prüfen; gleichzeitig gewählte Änderungen verwenden weiterhin die höhere Version, bei Gleichstand den Gastgeberwert.

Automatische Prüfungen decken verzögerte Antworten, lokale und gemeinsame Leistungsgrenzen, veraltete Partnerdaten, neu erzeugte Lua-Zustände und überlappende Menü-/Aktionspausen ab. Der reale Zwei-PC-Gegentest nach dieser Korrektur steht noch aus. Spielinstallation und laufende Spiele wurden für die Untersuchung nicht verändert.

**612 Lua-Prüfungen bestehen jeweils unter Lua 5.4 und Lua 5.2**, darunter 95 Synchronisierungsprüfungen mit 17 neuen Regressionen. Alle 24 Lua-Quellen kompilieren in beiden Runtimes. Zusätzlich bestehen 71 Launcher-/Protokollprüfungen; die 18 PowerShell-Quellen sind syntaktisch geprüft. Eine unabhängige Gegenprüfung hat die Fälle mit bereits bestätigten und verspäteten Geschwindigkeitsantworten nochmals nachgestellt.

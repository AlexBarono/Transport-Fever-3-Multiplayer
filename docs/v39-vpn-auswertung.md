# VPN-Test v39 und Änderung in v40

Quelle: Gastgeberprotokolle `alut_launcher.log`, `alut_proxy.log` und `stdout.txt` vom 9. Oktober 2026. Uhrzeiten unten sind lokale Zeit (Europe/Berlin); `stdout.txt` schreibt UTC, zwei Stunden früher. Protokolle des anderen PCs lagen nicht vor. Die unveränderten lokalen Kopien liegen in `release/diagnose-v39-vpn` und sind nicht Teil des Git-Commits.

- **13:16:12:** erste gemeldete Positionsabweichung, ohne Neuabgleich.
- **13:17:58:** zusätzlich unterschiedlicher Fingerabdruck eines Straßendepots. Position, Name und Ausrichtung waren gleich, die Bauparameter unterschieden sich.
- **13:18:58:** erster automatischer Neuabgleich wegen `hcon` (Bauwerke). Übertragung erfolgreich, gemeinsamer Stand um **13:20:30** geladen.
- **13:27:38:** zweiter automatischer Neuabgleich wegen `hveh` (Fahrzeuge). Übertragung erfolgreich, gemeinsamer Stand um **13:29:06** geladen.
- **13:31:29:** erneute Fahrzeugabweichung: Bei zwei Straßenfahrzeugen waren Namen und Konfigurationen gegeneinander vertauscht. Ein strikter Fingerabdruckunterschied beweist daher allein keine fehlgeschlagene Bauaktion.
- **13:31:49:** eine weitere Linienänderung kam an. Der vorherige Auftrag wurde auf beiden PCs um 13:31:49 abgeschlossen. Der letzte empfangene Auftrag hatte vor dem Beenden noch kein Ergebnis.
- **13:31:54:** Proxy wurde beim Spielende entladen; **13:31:57:** Launcher geschlossen. Im lokalen Modprotokoll keine `FAIL`-/abgelehnte-Nachbau-Meldung gefunden. Die zwei Unterbrechungen davor waren erfolgreiche automatische Neuabgleiche, keine nachgewiesenen Verbindungsabbrüche.

In v40 lösen Weltunterschiede keinen automatischen Neuabgleich und keine vorsorgliche Speicherung mehr aus. Auch bei bleibenden Fahrzeug-/Bauwerksunterschieden wird weitergebaut. Ein tatsächlicher Aktionsfehler bleibt sichtbar und kann einen bewussten Neuabgleich erfordern; das ist von einer bloßen Weltwarnung getrennt.

Der Knopf **Neu abgleichen** verwendet bei laufender vorbereiteter Sitzung den vorhandenen Spielstandaustausch und das Laden im offenen Spiel. Die ausdrückliche Anfrage erreicht den anderen Launcher weiterhin. Abbruch oder Fehler starten keine ungefragten Wiederholungen. Ein bereits gemeinsam angeforderter, nur auf einem PC geladener Stand kann weiterhin nachgeladen werden.

Nächster Praxistest: Beide PCs mit v40 mindestens 15 Minuten weiterbauen, auch wenn Fahrzeugwarnungen erscheinen. Es darf ohne Klick weder `TF3MP-Neuabgleich` gespeichert noch ein Spielstand übertragen/geladen werden. Danach einmal bewusst **Neu abgleichen** drücken und prüfen, dass beide denselben Gastgeberstand laden und weitere Bauten übertragen werden.

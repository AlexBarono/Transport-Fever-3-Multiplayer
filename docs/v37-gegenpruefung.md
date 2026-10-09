# Übergabe und Gegenprüfung v37

Stand: 9. Oktober 2026. Ausgangspunkt ist Claudes Branch `claude/project-thread-bc2xev`, übernommen bis `c5f63de` durch Fast-forward auf `probe-v2`.

Claude hat in `f021ceb`, `9c66b53` und `c5f63de` die Ursachen aus Lauf 39 bearbeitet: abgelehnte Nachbauten werden in geordneten Sitzungen übersprungen, fehlerhafte Zeitplan-Nachrichten bleiben ein Stoppgrund. Strukturelle Abweichungen müssen über mehrere Prüfungen bestehen; bewegliche Weltzustände lösen keinen automatischen Neuabgleich aus. Speichern und Übertragen benutzen getrennte Dateien. Fehlgeschlagene Neuabgleiche werden mit Wartezeiten erneut versucht; eine einseitige Ladewiederholung kann nachgeholt werden. Diese Änderungen wurden übernommen.

Die beiden verbleibenden Punkte sind jetzt ergänzt: echte parallele Spielstandübertragung mit vier Datenverbindungen, bedienbare Wartephasen und Gegenprüfung des portablen v37-Pakets. Details, Protokoll und Grenzen stehen in [savegame-transfer.md](savegame-transfer.md). Der Paketbau schließt den benötigten C#-Helfer ausdrücklich ein und prüft jeden ZIP-Eintrag gegen seine Quelldatei.

Die Tests decken Mod, Übertragung, Launcher, Sitzungsprüfung, Neuabgleich und native UDP-Verbindung ab. Die DLL v13 wird aus dem vorhandenen Quellstand neu gebaut; ihre Spiellogik wurde für die neue Dateiübertragung nicht geändert. Keine installierten Spieldateien wurden verändert und TF3 wurde für diese Gegenprüfung nicht gestartet.

## Prüfergebnis

- 328 Lua-Prüfungen bestehen unter Lua 5.2 und 5.4: 127 Mod-/Bautests, 63 Aktionen, 12 Schiffs-/Flugzeugfälle, 36 Weltfingerabdrücke, 52 Synchronisierung, 13 Zeitplan, 15 Transport und 10 Bau-Anhalteprüfungen.
- 42 Dateiübertragungsfälle bestehen jeweils unter Windows PowerShell 5.1 und PowerShell 7. Die zusätzlichen Fälle prüfen insbesondere vier reale Datenverbindungen und die Abbruch-/Wiederholungswege.
- 49 Launcher-/Protokollprüfungen, 30 Neuabgleichprüfungen und 10 Sitzungsprüfungen bestehen.
- Die neu gebaute DLL besteht alle 15 nativen UDP-Testgruppen, einschließlich gleichzeitiger Aktionen, Paketverlust, Wiederverbindung, Warteschlangen und Neuabgleich im laufenden Spiel.
- SHA-256 der gebündelten DLL v13: `1ad8331a22f4a18070cceb5178fa9aa5a12dcae5b0cc58d9cd6a0c8cc037ed06`.

Das sind 459 unterschiedliche Lua-/PowerShell-Prüfungen plus 15 native Netzwerk-Testgruppen. Die Doppelprüfungen mit verschiedenen Laufzeiten sind dabei nicht doppelt gezählt. Das portable Paket wird vollständig gegen seine Quellen geprüft; der Launcher und die Übertragung werden danach auch aus einer entpackten Kopie geprüft.

## Nächster Test auf den zwei VPN-PCs

1. Beide entpacken dasselbe `TF3-Multiplayer-v37-Windows.zip` in einen neuen Ordner. Beide öffnen dessen `Start.bat` und bereiten eine neue gemeinsame Sitzung vor.
2. Einen größeren vorhandenen Testspielstand übertragen. Der Fortschritt muss weiterlaufen; Fenster und Abbrechen bleiben bedienbar. `alut_launcher.log` sollte nach erfolgreicher Übertragung „über 4 Verbindung(en)“ und die reine Datenrate nennen.
3. Eine Übertragung am Mitspieler abbrechen und erneut starten. Danach muss der vollständige Stand ankommen; ein vorhandener anderer Stand wird erst nach Zustimmung ersetzt.
4. Beide laden den gemeinsamen Stand. Nacheinander und anschließend gleichzeitig an verschiedenen Stellen bauen, Linien ändern und Fahrzeuge zuweisen. Eine übersprungene Aktion darf spätere Aktionen nicht mehr dauerhaft blockieren. Die bekannte Grenze bei TF3s eigenen Fahrzeugfenstern aus Claudes README gilt weiter.
5. Den Neuabgleich einmal bewusst auslösen. Er muss einen neuen Stand übertragen und auf beiden PCs laden. Bei einem Fehlversuch die Wartezeit für die automatische Wiederholung abwarten. Danach prüfen, dass weitere Aktionen wieder ankommen.

Die lokalen Netzwerktests belegen die korrekte Übertragung und Fehlerbehandlung. Sie liefern keinen Nachweis für eine bestimmte VPN-Geschwindigkeit oder einen langen fehlerfreien Zwei-PC-Spielbetrieb. Bei einem Fehler beide Launcher-Protokolle, Proxy-Protokolle und `stdout.txt` aufbewahren.

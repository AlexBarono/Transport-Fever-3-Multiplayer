# v52: Internetübertragung und Subventionen

Aktueller Launcher: [v53](v53-launcher-start.md) integriert die Verbindung und Spielstandauswahl ins Hauptfenster und lädt den gemeinsamen Stand automatisch. Die folgende Beschreibung dokumentiert den vorherigen Stand.

Beide PCs brauchen das v52-Paket. Mod v52, Bridge weiterhin v14. Der automatische Beitritt und der gemeinsame Start aus v51 bleiben erhalten.

## Gefundene Ursachen

Im ausgewerteten Lauf vom 10. Oktober wurden bei drei Internetversuchen jeweils alle rund 69 MiB übertragen. Die Abschlussbestätigung fehlte trotzdem. Der Tunnel setzte auch auf seinen lokalen TCP-Steuerverbindungen den sieben Sekunden langen Handshake-Timeout ein. Während die vier Datenverbindungen arbeiten, bleibt die Steuerverbindung länger still und wurde deshalb geschlossen. Bei späteren Versuchen kamen keine Verbindungen mehr beim neuen Gastgeber-Tunnel an. Die Protokolle beweisen dafür keine einzelne externe Ursache; neue Einladungen, Zieladresse und Routerfreigabe müssen zusammenpassen.

Die abgelehnten Subventionen hatten auf dem anderen PC kein Angebot mit denselben Bedingungen und Belohnungen. TF3 erzeugt diese Daten lokal mit Zufallswerten. Der bisherige vollständige Vergleich war deshalb zu streng.

## Übertragung und Diagnose

- Der Handshake bleibt auf sieben Sekunden begrenzt. Danach haben TCP-Datei- und Steuerkanäle keinen Leerlauf-Timeout; Abbrechen und Schließen beenden die zugehörigen Sockets weiterhin.
- Spielstände und der anschließende Launcher-Kanal verwenden standardmäßig direktes **TCP ohne Verschlüsselung**. Frische Zufalls-Challenges und HMAC prüfen beide Seiten anhand der Einladung; der Einladungsschlüssel wird nicht im Klartext übertragen. Die übertragenen Dateien bleiben durch Größe und SHA-256 geprüft. Die Dateiinhalte sind auf dem Übertragungsweg lesbar.
- Der Spielkanal und die Einladungsprüfung verwenden weiterhin TLS. Der bisherige TLS-Dateiweg bleibt für Kompatibilitätstests verfügbar. Beide Wege nutzen denselben öffentlichen TCP-Port, standardmäßig **47801**. Intern bleibt der Spielport 47800; zusätzliche öffentliche UDP-Freigaben sind für den Internetweg nicht nötig.
- Erneutes Starten desselben Gastgeberzugangs mit denselben Ports und derselben Adresse verwendet die bestehende Einladung weiter. Nach einem tatsächlichen Neustart oder Adress-/Portwechsel muss die neue Einladung beim Mitspieler eingefügt werden.
- Dauerhafte IPv6-Adressen stehen vor temporären Windows-Adressen. Die Routerfreigabe muss zur gewählten aktuellen IPv6 dieses PCs gehören. Ein passender Portbereich allein genügt bei einer anderen Zieladresse nicht.
- Eine vorhandene passende UPnP-TCP-Freigabe kann verwendet werden. Fremde/manuelle Regeln werden dabei nicht als eigene Freigabe übernommen oder beim Beenden gelöscht.
- Internetprotokolle erfassen jetzt auch während der Dateiübertragung Verbindungszahlen, Klartext-/TLS-Wege, öffentlichen Port, letzte Transportmeldung und eine aus dem Schlüssel abgeleitete Einladungskennung. Einladungen und Schlüssel selbst bleiben unprotokolliert. Übertragungsfehler nennen zusätzlich die letzte erreichte Phase.

## Subventionen

Die vier ursprünglichen Auftragsarten für Arbeiter, Fahrgäste, Industriefracht und Stadtfracht werden anhand ihrer echten Ziele zugeordnet. Komponenten und Positionen ersetzen die lokalen Entity-IDs. Unterschiedliche Belohnungen oder Fristen verhindern die Annahme desselben Ziels nicht mehr.

Fehlt ein entsprechendes Angebot, fordert der Mod dessen Erzeugung über TF3s originales `subventionSpawn` mit aufgelösten lokalen Zielen an. Erst nachdem das Angebot im Spielzustand vorhanden ist, wird es automatisch angenommen und die Annahme geprüft. Vorhandene UID-Kollisionen und die UID-Historie werden berücksichtigt. Ein fehlendes oder mehrdeutiges Ziel, eine vom Spiel verweigerte Erzeugung oder ein unbekannter Auftrag bleibt ein verständlicher Aktionsfehler; der Mod erfindet dafür keine Auszahlung.

Nach erfolgreicher Annahme auf beiden PCs wird der tatsächliche Gastgeber-Kontostand übertragen und der Mitspieler durch eine eigene Journalbuchung einmalig angeglichen. Das funktioniert unabhängig vom Weltvergleich und von unterschiedlichen Kreditangeboten. Der Abgleich wartet, solange eine gemeinsame Aktion läuft. Wiederholte Nachrichten buchen nicht doppelt, ältere Entscheidungen dürfen keine aktuelle Entscheidung bezahlen, und ältere Geldkorrekturen aus dem Weltvergleich werden verworfen. Buchungsfehler erscheinen über die vorhandene Aktionsdiagnose auf beiden PCs.

Fortschritt, spätere Abschlussprämien, Strafen und laufende Einnahmen werden weiterhin lokal simuliert. Dieser Abgleich ist an die Annahme gebunden; er garantiert keine dauerhaft identischen Simulationen. Ein Neuabgleich bleibt eine Entscheidung des Gastgebers.

## Prüfung

`tests/run_internet.ps1` prüft echte lokale IPv4-/IPv6-Verbindungen, Spielkanal, Einladungsprüfung, falsche Schlüssel und wiederholte Challenge-Antworten, lange stille Steuerkanäle, Halbabschluss und vier parallele Datenströme. Der Empfänger hält außerdem die abschließende Speicherbestätigung länger als neun Sekunden zurück; die Datei muss ohne Wiederholung vollständig bestätigt werden und die Sicherung erhalten bleiben. Der gleiche Test läuft mit `-EncryptedSaves` über den bisherigen TLS-Dateiweg. Router-/Firewalländerungen erfolgen nur mit dem separaten expliziten `-CheckRouter`-Schalter.

`tests/run_internet_launcher.ps1` prüft IPv6-Auswahl und Wiederverwendung des Zugangs ohne echte Router-/Firewalländerungen. `tests/run_economy.lua` prüft die vier nativen Auftragsverträge, unterschiedliche lokale IDs/Belohnungen, fehlende Angebote, UID-Historie, echte Ablehnungen, Gastgebervorrang und doppelte bzw. alte Geldnachrichten mit nachgebildetem Spielzustand.

Ein echter Zwei-PC-Test bleibt erforderlich: neue Einladung von v52 verwenden, die aktuelle dauerhafte Gastgeber-IPv6 im Router prüfen, eine Datei vollständig empfangen und beide Spiele starten. Anschließend eine Subvention vom Gastgeber und eine vom Mitspieler annehmen, die automatische Annahme auf dem anderen PC und den folgenden Kontostand prüfen. Lokale Tests bestätigen keine Erreichbarkeit von einem anderen Internetanschluss und ersetzen keinen Test in TF3.

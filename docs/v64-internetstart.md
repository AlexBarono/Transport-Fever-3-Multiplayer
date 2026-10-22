# v64: Automatischer Internetstart

Beim Gastgeber öffnet **Internet ohne VPN** die Verbindung automatisch. Die Adressliste bevorzugt öffentliche IPv6-Adressen, die Windows mit zufälligem Suffix erzeugt und die der Launcher als **temporär** bezeichnet. Ist keine solche Adresse verfügbar, wird eine vorhandene dauerhafte öffentliche IPv6 gewählt. Eine bewusst gewählte andere Adresse bleibt beim Aktualisieren ausgewählt, solange sie noch verfügbar ist.

Der Knopf **IPv4 automatisch** ist entfernt. **Einladung kopieren** verwendet den freien Platz. **Erneut verbinden** bleibt für einen fehlgeschlagenen Aufbau verfügbar. Die automatische Einrichtung prüft wie bisher die Windows-Regel und fordert die IPv6-Freigabe beim Router an; eine gegebenenfalls erforderliche Windows-Administratorabfrage bleibt erhalten.

Die Einrichtung beginnt nach ungefähr 1,5 Sekunden unveränderter Adress- und Portauswahl. Ein laufender Tunnel, ein verbundener Launcher, ein Spielstart oder eine laufende Übertragung werden nicht erneut eingerichtet. Bei einem Fehler bleibt die Meldung sichtbar. Weitere Zeitgeberschritte wiederholen nicht ständig die Einrichtung; ein anderer Port, eine andere Adresse, ein erneuter Wechsel in den Internetmodus oder **Erneut verbinden** erlauben einen neuen Versuch.

Beim Beitreten bleibt das Einfügen der Einladung der Auslöser für die automatische Verbindung. Vorschau und Testlabor starten keinen Internetgastgeber. Ein bereits laufendes TF3 wird durch den automatischen Aufbau nicht verändert; der Aufbau wartet bis zum Spielende. Ohne gespeicherte Einstellungen ist Internet vorausgewählt; eine bestehende VPN/LAN-Einstellung wird beibehalten.

Die Korrekturen für Spielgeschwindigkeit, Geld und Haltestellen aus [v63](v63-tempo-geld.md) sind enthalten. Beide PCs verwenden **v64 / Bridge v16**.

## Prüfung

28 Internet-Launcher-Prüfungen kontrollieren Adressreihenfolge, automatischen Start, Wartezeit, Wiederholung nach Fehlern, Adress-/Portwechsel und Ausschluss laufender Sitzungen, Spiele, Vorschauen und des Schließvorgangs. Diese Prüfungen verändern weder Router noch Windows-Regeln. 393 Layoutprüfungen decken 100 %, 150 % und 200 % ab. Zusätzlich bestehen die Launcher-/Protokollprüfungen und die Prüfung der Diagnoselifecycles. Die Oberfläche enthält keinen IPv4-Einrichtungsknopf mehr.

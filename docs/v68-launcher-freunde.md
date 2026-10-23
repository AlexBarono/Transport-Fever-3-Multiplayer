# v68: Launcher, Anleitung und Freunde

Stand: 23. Oktober 2026. Probe v68 / Bridge v16.

## Bedienung

Das Fenster lässt sich wieder maximieren und frei vergrößern. F11 wechselt zwischen maximiert und normal. Bei wenig Platz sind Navigation und Inhalt scrollbar. Die Updateknöpfe stehen in einem eigenen Bereich ohne überlagernde Schrittbeschriftungen.

Während der automatischen Internet-Einrichtung zeigt die Einladung einen Ladekreis und **Verbindung wird vorbereitet …**. Nach erfolgreicher Einrichtung erscheint **Einladung kopieren**. Fehlende Adressen und fehlgeschlagene Verbindungen erhalten eigene Texte ohne laufenden Ladekreis. **Erneut verbinden** bleibt der Weg für einen neuen Versuch.

Die neue Seite **Anleitung** erklärt Gastgeber, Beitreten, Freunde, Updates und Fehlersuche. Das Öffnen von Anleitung oder Freunden beendet keine laufende Sitzung.

## Freundeliste

1. Unter **Beitreten** die vollständige Einladung einfügen und **Freund speichern** anklicken. Alternativ direkt **Freunde** öffnen.
2. Einen Namen eingeben und speichern. Auch VPN-/LAN-IPv4-Adressen mit optionalem Port sind möglich.
3. Später unter **Freunde** den Namen anklicken oder ihn unter **Beitreten** auswählen. Der Launcher wechselt zum Beitreten, setzt die gespeicherte Einladung ein und stößt den bestehenden automatischen Verbindungsablauf an.
4. Über **…** rechts am Namen bearbeiten. Mit **Aus Liste entfernen** den ausgewählten Eintrag löschen. Ein laufendes Spiel oder eine laufende Übertragung/Installation blockiert den Wechsel zu einem anderen Gastgeber.

Die Liste ist ein lokales Adressbuch, ohne Onlinekonto oder Anwesenheitsanzeige. Einladungen enthalten Zugangsdaten. Deshalb liegt die Datei mit Windows-DPAPI für das aktuelle Benutzerkonto geschützt unter `%LOCALAPPDATA%\TF3MP\Friends\friends.dat`. Sie bleibt beim Paketwechsel erhalten; volle Einladungen werden nicht in das Launcherprotokoll geschrieben. Eine beschädigte Liste wird nicht stillschweigend überschrieben.

Die gespeicherten Einladungen folgen weiterhin den Regeln aus [v65](v65-tempo-ipv6-einladung.md): Solange öffentliche Adresse, Port und Gastgeberidentität gleich bleiben, kann derselbe Link erneut verwendet werden. Bei einer geänderten Internetadresse muss der Eintrag aktualisiert werden. Ein Vermittlungsdienst für solche Adresswechsel bleibt ein Punkt der [Roadmap](roadmap.md).

## Gestaltung und Umsetzung

Die Gestaltung orientiert sich an Microsoft Fluent 2: [Abstände und Layout](https://fluent2.microsoft.design/layout), [klare Haupt- und Nebenaktionen](https://fluent2.microsoft.design/components/web/react/core/button/usage) und [Ladezustände mit Beschriftung](https://fluent2.microsoft.design/components/web/react/core/spinner/usage). Die Oberfläche bleibt eine lokale Windows-Forms-Anwendung.

Die Schaltflächen werden vollständig in einem Durchgang gezeichnet. Dadurch liegt auf deaktivierten Knöpfen kein zusätzlicher nativer Text mehr unter der eigenen Beschriftung. Feste Breiten wurden durch verankerte und bei Größenänderung berechnete Zeilen ersetzt. Bei 150 % wird mit gebrochenen Skalierungsfaktoren gerechnet; eine implizite Ganzzahlrundung auf 200 % hatte den Inhalt über den sichtbaren Bereich hinaus verbreitert.

## Prüfungen

- `tests/run_friends.ps1`: 26 Prüfungen zu Speichern, Laden, Aktualisieren, Umbenennen, Entfernen, ungültigen Eingaben, geschützter Ablage, beschädigten Dateien und Verbindungszuständen.
- `tests/run_friends_ui.ps1`: 20 Prüfungen mit echten Windows-Forms-Steuerelementen und Ereignissen: Namen anklicken, über **…** bearbeiten, Schnellauswahl, Internet/VPN-Wechsel, Schutz laufender Vorgänge, Navigation und Rückkehr ohne Sitzungsabbruch sowie F11. Netzwerk und Spielstart sind isoliert bzw. ersetzt.
- `tests/run_launcher_view.ps1`: 15.408 Sichtbarkeits-, Treffer- und Layoutprüfungen bei 100/150/200 %, zwei anfänglichen Bildschirmgrößen und vier Fenstergrößen einschließlich Maximieren sowie scrollbaren schmalen Ansichten.
- Bestehende Launcher-, Internet- und Updatetests bleiben Bestandteil der Releaseprüfung. Der Updatetest übt Paketwechsel, Sicherung und Rücknahme mit einem eigenen Helferprozess.
- Gerenderte Gastgeber-, Freunde- und Anleitungsansichten wurden visuell kontrolliert. Die native Computer-Use-Schnittstelle konnte das isolierte Testfenster nicht erreichen; F11 und Maximieren wurden deshalb über die echten Form-Ereignisse geprüft.

Ein tatsächlicher Internetbeitritt zwischen zwei PCs über einen gespeicherten Freund ist noch als Gegentest offen. Die automatisierten Prüfungen bestätigen Auswahl, Ablage und Übergabe an den vorhandenen Verbindungsablauf.

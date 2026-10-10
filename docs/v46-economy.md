# v46: Subventionen und Unternehmensname

**Ergänzung v52:** Die strenge Angebotszuordnung und die Grenze für fehlende Angebote unten beschreiben v46. v52 ordnet nach dem tatsächlichen Ziel zu, erzeugt fehlende ursprüngliche Angebotsarten über TF3 und gleicht nach der Annahme das Mitspieler-Konto an den Gastgeber an. [Aktuelles Verhalten und Tests](v52-verbindung-subventionen.md).

## Verhalten

- Annehmen und Ablehnen im normalen TF3-Auftragsfenster werden vor ihrer Ausführung abgefangen und über den bestehenden gemeinsamen Zeitplan auf beiden PCs ausgeführt.
- Jeder PC löst das originale `Subvention.onAccept` beziehungsweise `Subvention.onDecline` aus. TF3 führt dabei seine eigenen Buchungen, Reputation und Auftragszustände weiter. Der Mod bucht die sofortige Geldbelohnung nicht zusätzlich.
- Die Zuordnung verwendet die Auftragsart, Zielangaben, Bedingungen und Belohnungen. Unterschiedliche lokale Kennungen sind erlaubt, wenn das Angebot eindeutig dieselben Bedingungen hat. Fehlende, mehrdeutige oder abweichende Angebote werden vor der Buchung abgelehnt. Der Fehler nennt Auftrag und vorgesehenen Geldbetrag.
- Der native Rückruf reicht als Erfolgsnachweis nicht aus: Anschließend muss die Annahme beziehungsweise das Verschwinden des abgelehnten Angebots im Auftragsskript sichtbar sein. Das ist eine Zustandsbestätigung, kein eigener Nachweis der Kontobuchung im echten Spiel.
- Wiederholte gemeinsame Entscheidungen erzeugen keine doppelte Auszahlung. Widersprüchliche Entscheidungen werden gemeldet. Fehlgeschlagene Übergaben lösen keine einseitige lokale Auszahlung aus.
- Den Namen im normalen Unternehmensfenster ändern. Die Änderung wird auf den lokalen Spieler beider PCs angewandt und gegen Rückübertragung unterdrückt. Eine zusätzliche Erfassung erkennt normale Namensänderungen auch ohne GUI-Abfangfunktion. Beim Laden wird nur ein Ausgangsstand erfasst.
- Das Fehlerprotokoll zeigt Name, Aktion und Grund auf beiden PCs. Bei Krediten steht zusätzlich Aufnahme oder Rückzahlung samt Betrag. Abgelehnte Aktionen halten die gesamte Sitzung nicht an; Neuabgleich bleibt auf Wunsch.

## Grenzen

Später zufällig erzeugte Angebote können zwischen den Simulationen unterschiedlich sein. v46 erzeugt oder ersetzt dafür keine Aufträge: Wenn eine gemeinsame Entscheidung deshalb nicht auf beiden PCs möglich ist, meldet das Protokoll die fehlende Zuordnung. Ein manueller Neuabgleich übernimmt auch die Aufträge des Gastgeber-Spielstands. Spätere Abschlussprämien, Strafen, Lieferfortschritt und laufende Einnahmen entstehen weiterhin in der jeweiligen Simulation; vollständig gleiche Konten sind damit nicht garantiert.

## Prüfung mit zwei PCs

Beide PCs mit dem v46-Paket starten und denselben gemeinsamen Spielstand laden. Für genaue Geldvergleiche laufende Einnahmen und Ausgaben berücksichtigen.

1. Ein auf beiden PCs angebotenes Geld-Auftragsangebot beim Gastgeber annehmen. Auf beiden PCs muss derselbe Auftrag aktiv werden und dieselbe sofortige Geldbelohnung hinzukommen. Mit einem weiteren Angebot die Annahme beim Mitspieler prüfen.
2. Ein anderes gemeinsames Angebot ablehnen, anschließend von der anderen Seite wiederholen. Es muss jeweils auf beiden PCs verschwinden und darf keine Annahmeprämie auszahlen.
3. Den Unternehmensnamen beim Gastgeber ändern, dann beim Mitspieler ändern. Beide Unternehmensfenster sollen den zuletzt gemeinsam ausgeführten Namen zeigen, auch mit Umlauten.
4. Einmal gleichzeitig auf beiden PCs denselben Auftrag annehmen. Es darf pro PC nur eine Auszahlung entstehen. Bei gleichzeitigem Annehmen und Ablehnen entscheidet die gemeinsame Reihenfolge; der widersprüchliche Versuch wird im Protokoll gemeldet.
5. Bei einem bereits unterschiedlichen Angebot Auftrag, vorgesehenen Betrag und Fehlermeldung unter „Details prüfen“ vergleichen. Danach eine normale Bauaktion ausführen; die Sitzung soll weiterlaufen. Bei Bedarf manuell neu abgleichen.
6. Einen Kredit aufnehmen und zurückzahlen. Die bestehende Kreditübertragung bleibt erhalten; mögliche Fehler sollen Vorgang und Betrag nennen.

Automatisch geprüft werden GUI-Abfangfunktion zusammen mit Fahrzeugbefehlen, beide Initiatoren des gemeinsamen Zeitplans, native Zustandsbestätigung, Auszahlung im Testmodell, Wiederholungen, widersprüchliche Entscheidungen, unterschiedliche Kennungen, fehlende und abweichende Angebote, Namensänderungen, Rückkopplung und die strukturierten Launcher-Fehler. Ein echter neuer Zwei-PC-/VPN-Lauf wurde für v46 nicht durchgeführt.

Die Lua-Prüfungen laufen mit Lua 5.2 und 5.4, einschließlich der Regressionen für Bauaktionen, Fahrzeuge, Weltvergleich und Zeitplan. Die PowerShell-Prüfungen für Launcher/Protokoll, Fehleranzeige, Neuabgleich und Sitzung bestehen ebenfalls. Das Paketwerkzeug vergleicht anschließend alle gepackten Dateien byteweise mit dem Quellstand und prüft die Versionsangaben sowie die DLL.

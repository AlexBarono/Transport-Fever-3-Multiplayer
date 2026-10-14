# Transport Fever 3 Multiplayer

Experimenteller Community-Mod für zwei PCs: Straßen, Gleise, Bahnhöfe, Depots, Abriss, Linien, Fahrzeuge und Unternehmensänderungen werden zwischen zwei Spielen übertragen. Aktueller Stand: **Probe v61 / DLL v16**. **Beide PCs brauchen das v61-Paket.** Der Mitspieler empfängt den gemeinsamen Spielstand automatisch; der Gastgeber startet danach beide Spiele. Abweichungen bleiben Hinweise. Ein Neuabgleich erfolgt auf Wunsch des Gastgebers.

[v61: Straßenhaltestellen und Linienfehler](docs/v61-strassenhaltestellen.md) · [v60: Protokolle des Mitspielers beim Gastgeber](docs/v60-mitspieler-protokolle.md) · [v59: Wartende Aktionen und sichere Übergabe](docs/v59-warteschlange.md) · [v58: Brücken, Tunnel und Bahnhofprüfung](docs/v58-bruecken-anschluesse.md) · [v57: Auswertung und Korrekturen](docs/v57-sitzung-fehler.md) · [v56: Fahrzeugkäufe und Linienzuweisung](docs/v56-fahrzeuge.md) · [v55: Baufehler, Geld und Weltvergleich](docs/v55-bau-wirtschaft-vergleich.md) · [v54: Pause, Neuabgleich und Fahrzeugbefehle](docs/v54-pause-fahrzeuge.md) · [v53: Launcher und automatischer Spielstart](docs/v53-launcher-start.md)

## Neu in v61

- **Straßenhalte werden zuverlässig zugeordnet:** Bei nachweislich genau einem Terminal verwenden beide PCs dessen lokalen Index. Straßen- und Tramumbauten können interne Spur-Tags ändern; diese werden dort nicht mehr als Bahnsteigkennung verwendet. Modulare und mehrteilige Stationen behalten ihre strengen Zuordnungsprüfungen.
- **Weniger unnötige Linienupdates:** Millimeteränderungen von Straßenhaltestellen und eine andere Reihenfolge innerhalb derselben Haltestellengruppe erzeugen keinen neuen Linienbefehl. Eine andere Straßenseite, neue Halte, Wartezeiten, Frachtregeln und Namen werden weiterhin übertragen. Bau- und Wegpunktkoordinaten bleiben unverändert.
- **Straßenhaltestellen mit zusätzlichen Stadtparzellen:** Vor der Ausführung werden fehlende leere Parzellen nur ergänzt, wenn TF3s eigener Straßenhelfer deren Entfernung vorbereitet. Belegte oder nicht sicher lesbare Parzellen werden nicht blind entfernt; die Ablehnung wird verständlich erklärt. Es wird ein einzelner Bauauftrag ausgeführt.
- **Beide PCs aktualisieren und vorhandene Lücken einmal bewusst über den Gastgeber neu abgleichen.** Die Korrekturen sind automatisch geprüft; der native Zwei-PC-Gegentest steht aus. [Befund und gezielter Prüfplan](docs/v61-strassenhaltestellen.md).

## Neu in v60

- **Mitspieler-Protokolle automatisch beim Gastgeber:** Bei Internet ohne VPN werden Spiel-, Bridge- und Launcherprotokoll, Status sowie Internet- und Spielstandmessungen im Hintergrund übertragen. Der Gastgeber sieht den Empfangsordner unter **Sitzung & Protokoll**. VPN/LAN bleibt unverändert.
- **Kein zusätzlicher Port:** Die Diagnose verwendet einen eigenen Kanal mit derselben geprüften Einladung über den vorhandenen Internetport. Wiederverbindungen übernehmen bestätigte Daten ohne doppelte Einträge. Datenrate und Dateigrößen sind begrenzt; Einladungen und bekannte Zugangsschlüssel werden vor dem Senden entfernt.
- **Beide PCs verwenden v60.** Beide Launcher bleiben geöffnet. [Dateien, Grenzen und Prüfplan](docs/v60-mitspieler-protokolle.md).

## Neu in v59

- **Übergabe an TF3 abgesichert:** Eine empfangene Aktion wird vor der abschließenden Quittung gespeichert. Ist eine andere Aktion beschäftigt, bleibt die Nachricht zustellbar. Ein verlorenes internes Übergabeereignis darf erneut zugestellt werden, bis TF3 die Aktion beginnt. Eindeutige Kennungen verhindern eine zweite Ausführung durch verspätete Ereignisse.
- **Wartezeiten verständlicher:** Spielaktionen und Diagnoseberichte werden getrennt gezählt. Nach 30 Sekunden ohne Protokollfortschritt zeigt der Launcher die betroffene Kennung, den zuständigen PC und den verfügbaren Arbeitsschritt. Native Protokolle unterscheiden fehlende Daten, Empfangs-, Spiel- und Abschlussbestätigungen. Die Anzeige überspringt oder wiederholt keinen gestarteten Bau.
- **Übertragungsfehler genauer protokolliert:** Messprotokolle ergänzen Verbindungsversuch, bisherige Phase, Bytefortschritt und begrenzte Fehlercodes. Zugangsdaten und rohe Fehlermeldungen werden dabei nicht aufgezeichnet. Das ist eine Diagnoseverbesserung; eine höhere Übertragungsrate oder behobene Internetabbrüche sind damit nicht nachgewiesen.
- **Beide PCs aktualisieren und einmal denselben gemeinsamen Stand laden.** Bereits fehlende Bauten werden durch das Update allein nicht ergänzt. Der Gastgeber kann bei Bedarf bewusst neu abgleichen. [Befund, Grenzen und Gegentest](docs/v59-warteschlange.md).

## Neu in v58

- **Brücken und Tunnel werden wieder erfasst:** TF3s tatsächlicher Enum-Namensraum und numerische Komponentenantworten werden berücksichtigt. Zehn erfolgreiche lokale Bauten wurden im letzten Lauf bisher vor dem Senden verworfen; nachfolgende Gleise fanden auf dem anderen PC ihre Anschlüsse nicht. Unbekannte Typen und fehlende Ressourcen bleiben Fehler.
- **Bahnhofprüfung präzisiert:** Interne Gleisknoten allein belegen keinen erforderlichen Außenanschluss. Ausdrücklich übertragene Zugänge bleiben verpflichtend; das gilt auch für die acht fehlgeschlagenen Altlandsberg-Umbauten. Native Bauergebnisse und Knotenreferenzen werden weiterhin geprüft. Ein ausgeschöpftes Suchlimit bedeutet unbekannt.
- **Bauverluste werden sichtbar:** Scheitert schon die Erfassung oder ist eine Bauaktion zu groß, melden beide Launcher den Fehler. Die laufende Aktionsbestätigung bleibt dabei erhalten. Fehlender Fahrweg, fehlender vorheriger Abschnitt und unbestätigter Depot-/Bahnhofsanschluss erhalten genauere Erklärungen.
- **Weltvergleich mit fairer Zeitverteilung:** Große Kategorien können das gemeinsame 80-ms-Budget nicht mehr vollständig vor kleinen Kategorien verbrauchen. Unvollständige Messungen bleiben unbekannt. Eine vollständige Erfassung großer Karten ist weiter offen.
- **Beide PCs aktualisieren und vorhandene Lücken einmal über den Gastgeber neu abgleichen.** Die Korrekturen sind automatisch geprüft; der echte Zwei-PC-Gegentest steht noch aus. [Auswertung und gezielter Prüfplan](docs/v58-bruecken-anschluesse.md).

## Neu in v57

- Auswertung des echten v56-Laufs: TF3 führte einen zurückgehaltenen Depotbau bereits aus, bevor dessen verspätete GUI-Bestätigung ankam. Der zusätzliche gemeinsame Nachbau scheiterte am schon entfernten alten Abschnitt. Normale Bauten werden jetzt ausschließlich nach ihrem erfolgreichen nativen Bau einmal übertragen. Die gemeinsame Fahrzeugzuweisung bleibt erhalten; ein exakt gleichzeitiger nativer Bau ist damit nicht zugesichert.
- Der Geldabgleich verwechselt neue Einnahmen/Ausgaben zwischen Messpunkten nicht mehr mit einer fehlgeschlagenen Buchung. Direkte native Antworten und Kontowerte prüfen die Buchung; der Mitspieler folgt weiterhin dem Gastgeberkonto. Tatsächlich abgelehnte Buchungen bleiben Fehler.
- TF3s eigene Leistungsgrenze für die Spielgeschwindigkeit wird berücksichtigt. Ein erlaubtes 3× statt angeforderter 4× schaltet die Geschwindigkeitsübernahme nicht mehr ab. Pausen werden passend freigegeben.
- Gleich benannte Fahrzeuge können bei gewöhnlichen Änderungen über die vorherige Linie und unveränderte Konfiguration unterschieden werden. Überlappende Depot-/Kreuzungsknoten erhalten eine zusätzliche Suche nach dem tatsächlich verbundenen Abschnitt. Mehrdeutige Ziele bleiben Fehler.
- Längere Linien erhalten ein Prüflimit pro Halt bei gleicher Gesamtgrößengrenze; Frachtdiagnosen verwenden wiederholte Referenzen nur einmal je Messpunkt und benennen ungültige Felder genauer.
- **Schiffe und die schnellere Fahrzeugzuweisung wurden laut Rückmeldung mit zwei PCs erfolgreich getestet.** Die Korrekturen aus v57 sind automatisch geprüft und brauchen noch den echten Gegentest. Bereits fehlende Bauten/Fahrzeuge einmal bewusst über den Gastgeber **Neu abgleichen**. [Befund, Grenzen und Prüfplan](docs/v57-sitzung-fehler.md).

## Neu in v56

- Fahrzeugzuweisungen benötigen einen Netzumlauf weniger. Bereitschaft und bestätigte native Pause reisen gemeinsam; beide Spiele müssen weiterhin bereit sein, bevor eine Aktion ausgeführt wird.
- Nach bestätigten Käufen werden nur Einstellungen nachgereicht, die vom tatsächlich gelesenen Fahrzeugzustand abweichen. Der native Stopindex `-1` bleibt auch im bisherigen Nachbau erhalten. Neue Fahrzeugteile bekommen die örtliche Kaufzeit wie beim Originalspiel.
- Eine fehlgeschlagene Übergabe führt den zurückgehaltenen Fahrzeugbefehl nicht mehr heimlich nur auf einem PC aus. Fahrzeugfenster bekommen eine bestätigte Übergaberückmeldung; Fehler erscheinen in beiden Protokollen. Ausdrücklich gewählte Depotziele bleiben erhalten.
- Kaufprotokolle zeigen zusätzlich das nach TF3-Regeln verfügbare Geld und den Neupreis, soweit lesbar. Bei einer Linienablehnung werden verfügbare native Haltestellen-/Fahrwegprobleme ergänzt.
- Die erweiterten Sitzungsprüfungen berücksichtigen verzögerte Engineantworten, Netzlatenz, größere Zeitunterschiede, Sammelzuweisungen und manuelles Neuladen. Der echte Zwei-PC-Kartentest bleibt erforderlich. **Neuabgleich bleibt auf Wunsch.** [Änderungen und gezielter Gegentest](docs/v56-fahrzeuge.md).

## Neu in v55

- Haltestellen und Signale verwenden ausschließlich die bestätigte native Nummerierung. Der Ersatzversuch nach einer Ablehnung, der im letzten Lauf einen internen TF3-Indexfehler ausgelöst hat, entfällt. Die Position entlang des Gleises/der Straße wird ohne die bisherige Rundung übertragen.
- Offene Gleisenden bleiben auch beim Verlängern eines Bahnhofs offene Enden. Ein beibehaltener Endknoten wird nicht mehr automatisch als fehlgeschlagener Netzanschluss geprüft; echte Anschlüsse bleiben prüfpflichtig.
- Unterschiedliche native Kreditpläne blockieren die Geldangleichung des Mitspielers an den Gastgeber nicht mehr. Subventionsziele werden nach Möglichkeit über den festen Bauwerksanker erkannt, damit wachsende Industriefelder die Zuordnung nicht verschieben.
- Abgelehnte Fahrzeugkäufe nennen Depot, Kontostand, Modell und den Kaufpreis, soweit TF3 diese Werte auslesen lässt. Unspezifische Fahrwegfehler werden auch so bezeichnet.
- Der Weltvergleich verarbeitet native Linienkonfigurationen und Fahrzeuge im Depot. Fracht kann über die nativen Lager-/Fahrzeugverzeichnisse erfasst werden; diese Abdeckung wird ausdrücklich gekennzeichnet. Kategorien haben getrennte Abfragelimits, damit ein aufwendiger Frachtscan nicht alle späteren Prüfungen aufbraucht. Unvollständige Messungen bleiben unbekannt.
- Benachbarte Bestätigungen des gemeinsamen Fahrzeugzeitplans werden in einer Nachricht übertragen; während einer gemeinsamen Aktion prüft die Oberfläche häufiger. Alle Bereitschafts- und Ergebnisprüfungen bleiben erhalten. Die reale Pausendauer muss beim Zwei-PC-Test gemessen werden.

Auf beiden PCs aktualisieren und einmal denselben Gastgeberstand laden oder bewusst **Neu abgleichen**. Bereits fehlende Bauten werden durch das Update allein nicht nachgebaut. Die ursprüngliche Platzierungsablehnung bei Fliederweg und die Ursache aller später fehlenden Gleisknoten sind noch nicht abschließend geklärt. [Befund, Prüfungen und Gegentest](docs/v55-bau-wirtschaft-vergleich.md).

## Neu in v54

- Beim Laden werden alte Aktionspläne, Ausführungsbestätigungen, Fahrzeug-/Linienzuordnungen und Gleisprüfungen vollständig zurückgesetzt, auch beim ersten Netzwerk-Schritt im pausierten Spiel. Eine gespeicherte, unerledigte Aktion darf keine neue Pause erzeugen.
- Die gemeinsame Aktionspause endet sofort nach der Bestätigung beider Spiele. Ihre Freigabe wartet auf keinen weiteren Simulationsschritt.
- Fahrzeugbefehle halten beide Spiele kurz an und laufen nach gemeinsamer Bereitschaft an ihrem jeweiligen aktuellen Spielzeitpunkt. Sie warten weder auf den bisherigen Vorlauf von vier Spielsekunden noch auf das Aufholen eines großen Zeitversatzes. Neue Linien und Fahrzeugkäufe werden davor übertragen. Auch andere Aktionen verwenden diese Bereitschaftssperre bei Pause oder mehr als vier Sekunden Zeitversatz; bei laufenden, ausreichend nahen Spielzeiten bleibt der gemeinsame Zeitstempel erhalten.
- Fehlende Fahrzeugreferenzen warten höchstens 16 Prüfschritte statt 160. Eine abgelehnte Ausführung bleibt im Fehlerprotokoll sichtbar; die nächste Aktion darf weiterlaufen. Echte Protokollfehler erfordern weiterhin einen manuellen Neuabgleich.
- Der automatische Spielstart verwendet den tatsächlichen TF3-Typ `api.type.SaveGameDetails`; eine verifizierte Ladeergänzung aus v53 wird beim Einrichten aktualisiert.

Nach dem Update einmal den gemeinsamen Stand laden bzw. manuell neu abgleichen. Alte fehlende Bauten werden durch das Update allein nicht wiederhergestellt. [Befund, automatische Prüfungen und Zwei-PC-Test](docs/v54-pause-fahrzeuge.md).

## Ohne VPN starten (v61)

1. Beide verwenden das [v61-Paket](release/TF3-Multiplayer-v61-Windows.zip) und öffnen `Start.bat`.
2. Gastgeber: Unter **Internet ohne VPN** eine öffentliche IPv6 auswählen und **Verbindung öffnen**. Alternativ öffentliche IPv4 eintragen oder **IPv4 automatisch** für die Routeranfrage wählen. Alles geschieht im Hauptfenster. Der dort angezeigte Internetport ist **TCP 47801**; der interne Spielport wird nicht mehr als freizugebender Internetport angezeigt.
3. Der Launcher prüft die Windows-Regel und fordert die Routerfreigabe an. Falls Windows Administratorrechte verlangt, bestätigen. **Einladung kopieren** und nur dem Mitspieler geben. Die Einladung gilt für diese laufende Verbindung. Routerfehler stehen im Protokoll. Bei IPv6 müssen beide Anschlüsse IPv6 unterstützen; bei IPv4 kann CGNAT/DS-Lite eine direkte Freigabe verhindern.
4. Mitspieler: **Beitreten**, die vollständige Einladung einfügen. Der Launcher verbindet sich automatisch. **Löschen** leert das Feld und beendet eine noch wartende Verbindung.
5. Erst sobald der andere Launcher verbunden ist, erscheinen beim Gastgeber Spielstandliste und **Spielstand bereitstellen**. Einen Stand auswählen und bereitstellen. Der Mitspieler empfängt und prüft ihn automatisch; alte gleichnamige Dateien bleiben als `.bak` erhalten. Ein noch laufendes TF3 wird für die neue Sitzung beendet.
6. Nach bestätigtem Empfang und Einrichtung wird **Spiel für beide starten** grün. Beide Spiele starten über Steam und laden den gemeinsamen Stand automatisch, einschließlich Aktivierung der Multiplayer-Mod. Ein bereits laufendes TF3 wird vorher geschlossen. Beide Launcher bleiben geöffnet.

Der Internetweg benötigt keinen Vermittlungsserver. Er ersetzt jedoch keine fehlende Erreichbarkeit. Steam-Relays sind hier nicht integriert. Spielaktionen laufen über TLS; Spielstände laufen seit v52 unverschlüsselt über denselben öffentlichen TCP-Port. Die Einladung wird in beiden Fällen geprüft. [Internettransport](docs/v49-internet.md).

## Starten über euer gemeinsames VPN

1. Dasselbe [v61-Paket](release/TF3-Multiplayer-v61-Windows.zip) auf beiden PCs öffnen und das VPN verbinden.
2. Gastgeber: **VPN / LAN**, passende Adresse auswählen, **Adresse kopieren**. Der Wartekanal öffnet automatisch. Für VPN/LAN gilt weiter **TCP + UDP 47800**; eine Routerfreigabe ist dafür nicht nötig.
3. Mitspieler: **Beitreten**, Adresse einfügen (z. B. `100.80.12.4:47800`). Sobald verbunden, wählt und teilt der Gastgeber den Spielstand direkt im Hauptfenster. Beide brauchen dieselbe Paketversion und passende zusätzliche Mods.
4. Der Gastgeber klickt den grünen Knopf **Spiel für beide starten**. Beide Spiele laden den geteilten Stand automatisch. Sobald beide Karten bereit sind, gemeinsam fortsetzen und bauen.
5. **Beide Launcher bleiben offen.** Wichtige Verbindungs-, Übertragungs- und Aktionsfehler erscheinen unter **Sitzung & Protokoll**. Gelbe Weltabweichungen erzwingen keinen Neuabgleich. **Neu abgleichen** gibt es nur beim Gastgeber und lädt seinen frischen Stand bei beiden im offenen Spiel.

Für das automatische Laden wird genau eine Ressource des TF3-Hauptmenüs über die Ressourcenliste ergänzt; das große Spielarchiv bleibt unverändert. Die originale Liste wird gesichert und beim **Mod entfernen** wiederhergestellt. Nach Steam-Updates gegebenenfalls die Mod entfernen und neu einrichten. [Technik, Grenzen und Testplan](docs/v53-launcher-start.md).

**Nur Einstellungen speichern** und **Am selben Ort nachbauen** stehen im Testlabor. Der erste Knopf installiert Mod/Bridge und schreibt die Einstellungen, ohne Steam zu öffnen. Der zweite spielt eine aufgezeichnete Baufolge im Test *Gleiche Stelle* nach dem Neuladen am ursprünglichen Ort ab. Im normalen Gastgeber-/Mitspielerablauf werden diese Werkzeuge nicht benötigt.

## Neu in v48

- **Spielmenü:** Öffnet einer von euch das Pausenmenü, bleiben beide Spiele angehalten. Tempoänderungen heben diese Pause nicht auf. Erst wenn beide Menüs geschlossen und gemeinsame Aktionen abgeschlossen sind, kommt das vorherige Tempo zurück. Eine vorher bewusst gewählte Pause bleibt erhalten.
- **Fahrzeuge umdrehen:** Auch bei verzögerten Geschwindigkeitsbefehlen und einer überlappenden Menüpause bleibt die Wiederaufnahme nach der gemeinsamen Aktion geschützt; getestet für Gastgeber und Mitspieler bei 0x, 1x, 2x und 4x.
- **Spielstand übertragen:** Vier kontinuierliche TCP-Datenströme senden weiter, während Empfangsbestätigungen getrennt gelesen werden. Ältere Übertragungsfähigkeiten werden bei der Verbindung erkannt. Größenprüfung, SHA-256, Abbrechen und Sicherung vorhandener Spielstände bleiben erhalten.
- **Messprotokolle:** Jeder Versuch schreibt unter `%LOCALAPPDATA%\TF3MP\Logs\save-transfer-*.jsonl` Datenrate, belegte Datenströme, Netzwerk- und Dateizeiten sowie Prüfdauer. `alut_launcher.log` verweist auf die jeweilige Datei. Der lokale Vergleich ist schneller; die tatsächliche VPN-Rate muss im nächsten Zwei-PC-Lauf gemessen werden. [Details und Prüfplan](docs/v48-menu-transfer.md).

## Neu in v47

- **Keine festhängende Pause nach einer gemeinsamen Aktion:** Das automatische Fortsetzen bleibt bis zur sichtbaren Bestätigung des Spiels geschützt. Die vorübergehende Pause wird dadurch nicht mehr als neue Benutzerpause zwischen beiden PCs hin- und hergeschickt.
- **Zeitversatz darf bestehen bleiben:** In einer normalen Zwei-PC-Sitzung pausiert das Aufholen den vorauslaufenden PC nicht mehr automatisch. Gelbe Weltmeldungen bleiben Hinweise, Neuabgleich bleibt auf Wunsch. Gemeinsame Aktionen behalten ihre notwendige Ausführungspause.
- Beide PCs brauchen v47. Bei gelber Meldung 1x, 2x und 4x testen, danach eine Bauaktion sowie echte Pause/Fortsetzen aus beiden Richtungen prüfen. [Befund und Prüfungen](docs/v47-pause-release.md).

## Neu in v46

- **Subventionen annehmen und ablehnen:** Die Klicks im normalen Auftragsfenster gehen über den gemeinsamen Zeitplan an beide PCs. Bei Annahme führt jeder PC den originalen TF3-Auftrag samt seiner sofortigen Geld- und sonstigen Belohnung aus. Eine Wiederholung löst keine zweite Auszahlung aus.
- Die Zuordnung prüft Auftragsart, Ziel, Bedingungen und Belohnungen. Fehlt der Auftrag oder hat er andere Bedingungen, erscheint ein konkreter Fehler mit Subventionsname und vorgesehener Auszahlung; die Sitzung läuft weiter. Zufällig später entstandene unterschiedliche Angebote werden nicht automatisch ersetzt. Abschlussprämien und Strafen bleiben Teil der lokalen Spielsimulation.
- **Unternehmen umbenennen:** Im normalen Unternehmensfenster den Namen ändern. Die Änderung wird auf beiden PCs ausgeführt. Das Fehlerprotokoll nennt den gewünschten Namen; Kreditfehler zeigen jetzt Aufnahme/Rückzahlung und Betrag an.
- Beide PCs brauchen v46. Annehmen, Ablehnen und Umbenennen jeweils vom Gastgeber und Mitspieler aus prüfen; bei einer Geldbelohnung den Kontozuwachs kontrollieren. Neuabgleich bleibt auf Wunsch. [Details und Prüfplan](docs/v46-economy.md).

## Neu in v45

- **Linienzuweisung aus Fahrzeugfenstern:** TF3s Wert `-1` für „nächsten erreichbaren Halt“ bleibt jetzt sowohl beim Abfangen als auch im gemeinsamen Zeitplan erhalten. Bisher wurde daraus Halt 0, der vom Depot aus unerreichbar sein kann. Die Fenster-Rückrufe bekommen die erwarteten Befehlsdaten mit Fahrzeug- und Linienkennung statt des undurchsichtigen Befehlsobjekts.
- Abgelehnte Fahrzeugbefehle werden nicht mehr als angewandte Änderung im Erfassungsstand vermerkt. Bei abgelehnter Linienzuweisung wird TF3s Fahrwegdiagnose abgefragt, einschließlich einer Problemposition, soweit verfügbar. Derselbe auf beiden PCs gescheiterte Versuch zählt im Launcher als eine Aktion; die Details beider PCs bleiben sichtbar.
- Beide PCs brauchen v45. Im Gegentest Zug 5 aus dem Depot auf die Linie schicken und dieselbe Zuweisung aus beiden Richtungen sowie aus Fahrzeugverwaltung und Fahrzeugfenster prüfen. Bestehende Gleis-, Depotparameter- oder Geldunterschiede werden durch diese Korrektur nicht automatisch beseitigt. Neuabgleich bleibt auf ausdrücklichen Wunsch. [Auswertung und Prüfungen](docs/v45-line-assignment.md).

## Neu in v44

- **Fehler beim Betreten einer Welt behoben:** Die neue Fahrzeug-Erweiterung aus v43 rief in der Hauptoberfläche `log.info` auf. Diese Funktion gibt es dort nicht; dadurch brach der Aufbau der Spieloberfläche ab. Die Erweiterung verwendet jetzt geschützte Ausgabe ins Spielprotokoll. Auch ein Ausgabefehler darf weder das Laden noch einen zurückgehaltenen Fahrzeugbefehl unterbrechen.
- Beide PCs brauchen v44. TF3 nach dem Fehler schließen, das neue Paket entpacken und dessen `Start.bat` verwenden. Danach die Welt einmal manuell laden und Start/Stopp aus einem Fahrzeugfenster testen. Der Startfehler ist automatisch reproduziert und die Korrektur geprüft; ein erneuter echter Spielstart wurde dafür nicht ausgelöst. [Befund und Prüfungen](docs/v44-world-entry-fix.md).

## Neu in v43

- **Fehlgeschlagene Aktionen sichtbar:** Eine dauerhafte Meldung unter den Startknöpfen führt zu den Details. Dort stehen Bau-/Aktionsart, Name bzw. Ort soweit verfügbar, Fehlerursache und Kennung. Die Meldung unterscheidet eine Ablehnung vor dem Baubefehl von einer möglicherweise teilweise ausgeführten Aktion. Auch der andere PC bekommt die Diagnose. Die Sitzung läuft weiter; es erfolgt kein blindes Wiederholen eines bereits teilweise gebauten Vorhabens. Beim Laden eines neuen gemeinsamen Stands beginnt die Fehlerliste neu.
- **Weltvergleich:** Linien kommen aus dem Linienverzeichnis, Gleise/Straßen aus dem deduplizierten Netzverzeichnis. Fracht wird über einen begrenzten Scan aller Entities gelesen; native Frachtvektoren werden per Index statt mit `pairs` gelesen. Diese Wege umgehen TF3s Fehler „Cannot loop over this component type“. Unvollständige oder zu langsame Messungen bleiben ausdrücklich unbekannt. Auf großen Karten kann insbesondere der vollständige Frachtscan weiter das Messbudget überschreiten.
- **Normale Fahrzeugfenster anbinden:** Eine GUI-Erweiterung installiert die Fahrzeug-Hooks im Lua-Zustand der eigentlichen Spieloberfläche, in dem auch Fahrzeugfenster und Fahrzeugverwaltung laufen. Umkehren, Start/Stopp, Depotfahrt, Linienzuweisung und Verkauf werden vor dem Ausführen an den gemeinsamen Zeitplan übergeben. Auch eine Auswahl von mehr als 40 Fahrzeugbefehlen lässt keinen Befehl vorzeitig durch. Fahrzeugkauf und Fahrzeugkonfiguration reisen weiterhin über den bisherigen Nachbau.
- **Neuabgleich bleibt auf Wunsch.** Die gemeinsame Ausführung erfolgt weiter über eine Spielzeit-Schranke; das ist kein Nachweis für dauerhaft identische Simulation oder exakte Engine-Ticks. Falls die GUI-Hooks oder der Zeitplan nicht verfügbar sind, bleibt der bisherige Nachbau als Rückfall erhalten.
- Beide PCs brauchen v43. Echter Gegentest: Fahrzeugbefehle aus dem Fahrzeugfenster und der Fahrzeugverwaltung in beide Richtungen, Sammelzuweisung, Weltprüffelder und Fehleranzeige kontrollieren. Die neuen GUI-Einbindungen sind automatisch gegen getrennte Skriptumgebungen geprüft; ihre Ausführung in TF3 muss noch bestätigt werden. [Umsetzung und Prüfungen](docs/v43-sync-diagnose.md).

## Neu in v42

- **Bahnhof über Feldern/Forstflächen:** Automatische Änderungen der Feldmodule werden dem bestehenden Betrieb zugeordnet und zuerst mit TF3s eigenem Änderungsbefehl ausgeführt. Erst nach dessen Bestätigung folgt der Bahnhof. Die gefrorene Zufahrt des Betriebs wird nicht separat abgerissen; ein fehlgeschlagener Änderungsbefehl stoppt diese Bauaktion ohne unsicheren Ersatzversuch. Das behebt den fehlerhaften Nachbaupfad des v41-Absturzes, der echte Zwei-PC-Gegentest steht noch aus.
- **Eisenbahnbrücken und Tunnel übertragen:** Zusätzlich zu Gleisverlauf und Höhe werden der Bauwerkstyp und die Brücken-/Tunnelressource übertragen. Die Ressource wird auf dem anderen PC nach Namen gesucht. Eine fehlende Ressource wird gemeldet, statt einen falschen ebenerdigen Abschnitt zu bauen.
- Leere Konstruktionseinträge bei automatischem Feldabriss werden nicht mehr als Gebäude an Position 0,0 übertragen. Industriegebäude werden für spätere Feldänderungen mit erfasst.
- Beide PCs brauchen v42. Zum Gegentest einen normalen Spielstand von **vor dem Absturz** verwenden: Bahnhof über Feld/Forstfläche setzen und anschließend eine Eisenbahnbrücke einschließlich Zufahrten bauen, am anderen PC prüfen. [Absturzanalyse und Tests](docs/v41-crash-auswertung.md).
- Weltabweichungen bleiben erlaubt; ein gemeinsamer Neuabgleich startet weiterhin nur auf ausdrücklichen Wunsch.

## Neu in v41

- **Gleisknoten beim Nachbau erhalten:** Empfangene Bauaktionen und anschließende Knoteneinstellungen vereinfachen das Netz nicht nochmals. Im v40-Test fehlte nach einem Gleisumbau der Knoten für den späteren Depotanschluss; dieser wurde deshalb übersprungen. Die Änderung verhindert diese zusätzliche Vereinfachung. Der echte Zwei-PC-Gegentest steht noch aus.
- **Bauschritte nur einmal ausführen:** Ein verschachteltes Spielereignis darf denselben Schritt nicht nochmals starten. Im Test wurden Knoteneinstellungen einer Aktion bis zu sechsmal gesetzt.
- Der Bau-Abfangcode lädt seine Module vor den GUI-Ereignissen. Im v40-Test konnte er `build.lua` während des Klicks nicht laden; das gemeinsame Planen des Baus wurde damit umgangen. Empfangene Bauten werden jetzt einmal vollständig protokolliert, damit verbleibende Anschlussfehler reproduziert werden können.
- Weltabweichungen bleiben wie in v40 Hinweise. **Neu abgleichen** startet weiterhin nur auf ausdrücklichen Wunsch einen gemeinsamen Spielstandaustausch. Bereits fehlende Gleise werden durch die Installation nicht nachträglich gebaut.
- Test auf beiden PCs: denselben Ausgangsstand laden, Gleisabschnitte ändern, ein Zugdepot anschließen, einen Zug auf eine Linie schicken und anschließend auf beiden PCs weiterbauen. [Auswertung des v40-Tests](docs/v40-vpn-auswertung.md).

## Neu in v40

- **Weiterspielen trotz Weltabweichungen:** Fahrzeuge, Positionen, Fracht, Städte und auch Unterschiede bei Bauwerken, Gleisen, Linien und Krediten lösen keinen automatischen Neuabgleich mehr aus. Die Diagnose bleibt sichtbar; Bauaktionen werden weiter übertragen.
- Auch die vorsorglichen Speicherungen bei Weltabweichungen entfallen. Ein blockierter Aktionszeitplan oder eine abgelehnte Aktion bleibt als Fehler sichtbar, startet aber keinen ungefragten Spielstandaustausch.
- **Neu abgleichen nach Bedarf:** In einer laufenden vorbereiteten Sitzung startet der Knopf einen bewussten Neuabgleich im offenen Spiel. Der andere Launcher folgt dieser ausdrücklichen Anfrage. Beide Launcher müssen geöffnet sein; der Gastgeberstand wird auf beide PCs geladen. Manuelle Anfragen sind nicht auf sechs Versuche begrenzt. Nach Abbruch oder Fehlschlag startet kein neuer Austausch ohne erneuten Klick; das Nachholen eines bereits angeforderten, nur einseitig geladenen Stands bleibt erhalten.
- Beide PCs müssen v40 verwenden, damit kein älterer Launcher wegen der Unterschiede einen automatischen Neuabgleich anfordert.

## Neu in v39

- **Kalendertempo während des Spiels übertragen:** Änderungen des Gastgebers oder Mitspielers werden auf den anderen PC übernommen, auch während einer Spielpause. Das Anhalten des Kalenders wird ebenfalls übertragen. Pause und Spieltempo bleiben davon unabhängig.
- Bei unterschiedlichen Anfangswerten und gleichzeitigen Änderungen gilt der Wert des Gastgebers. Danach gewinnt die neuere Änderung. Die Synchronisierung verwendet dieselbe Tageslänge und denselben Befehl wie TF3s eigener Kalendereditor.
- Automatische Prüfungen decken beide Richtungen, angehaltenen Kalender, Pause, gleichzeitige Änderungen, verlorenen Lua-Zustand, Wiederholungen und ungültige/veraltete Daten ab. Der echte VPN-Test steht noch aus: auf einem PC Kalendertempo ändern, Übernahme am anderen PC prüfen; danach die Gegenrichtung und Kalenderstopp testen.

## Neu in v38

- Linien können Halte an weltgehörigen Industriegebäuden (zum Beispiel Bauernhöfen und Ölplattformen) beim Nachbau wiederfinden. Bisher konnte schon die erste Linienänderung den gesamten Ein-PC-Nachbau stoppen. Der Eigentumscheck für Änderungen und Abriss von Gebäuden bleibt bestehen.
- Ein lokaler Test startet bei einer abgelehnten Aktion keinen Zwei-PC-Neuabgleich mehr: Der simulierte Gastgeber besitzt keinen eigenen Spielstand zum Teilen. Den Fehler zeigt **Details prüfen**.
- Der konkrete fehlgeschlagene Linienbefehl aus dem Test vom 9. Oktober wird automatisch gegengeprüft. Der erneute Nachbau im echten Spiel ist noch zu testen.

## Neu in v37

- **Sitzung läuft weiter (Lauf 39)**: Eine Linie des Mitspielers wurde beim Gastgeber abgelehnt. Bisher hielt die DLL daraufhin die ganze Sitzung an („game rejected“), alle weiteren Aktionen blieben liegen. Jetzt überspringt der Mod eine abgelehnte Aktion, meldet sie als erledigt (`net skipped …` im Protokoll), und alles läuft weiter. Fehlt dadurch etwas, gleicht der Launcher neu ab.
- **Neuabgleich nur, wenn es nötig ist**: Nur Abweichungen bei Bauwerken, Straßen/Gleisen, Linien, Fahrzeugen oder Krediten lösen ihn aus, und nur, wenn dieselbe Abweichung bei 3 Weltprüfungen hintereinander und mindestens eine Minute lang bleibt. Bleibt der gemeinsame Zeitplan stehen (beide Spiele angehalten), gleicht der Launcher nach 30 Sekunden neu ab. Abweichungen bei Fahrzeugpositionen, Fracht und Städten zeigt der Launcher nur noch als Hinweis, das Spiel läuft weiter. **Neu abgleichen** bleibt für Hand.
- **Neuer Versuch von selbst**: Klappt ein Neuabgleich nicht, versucht der Launcher es noch einmal, solange der Grund bleibt (nach 30, 60, 120 Sekunden …, höchstens 6-mal pro Spielstart). Hat nur ein PC den gemeinsamen Stand geladen, lädt der andere ihn von selbst nach.
- **Kein Anhalten mehr beim Speichern**: TF3 hielt an („Save game rename failed“), weil der Mod `TF3MP-Neuabgleich` alle 3 Prüfungen neu speicherte, während der Launcher die Datei schickte. Jetzt speichert der Mod selten, der Launcher fragt einen frischen Stand an, macht sofort eine eigene Kopie `TF3MP-Sync-<Zeit>` (das Original ist dafür nur etwa eine Sekunde offen) und schickt nur diese. Die zwei neuesten Kopien bleiben liegen, ältere löscht er.
- **Übertragung**: vier Datenverbindungen über denselben TCP-Port, zusätzlich eine Steuerverbindung. Dateien werden in getrennte Bereiche aufgeteilt und vor dem Übernehmen vollständig mit SHA-256 geprüft. Warten auf Kompatibilitätsprüfung, Daten und Empfangsbestätigung blockiert die Oberfläche nicht; Abbrechen beendet auch wartende Netzwerkzugriffe. Ein Partner ohne Parallel-Unterstützung verwendet weiter eine Datenverbindung. `alut_launcher.log` nennt die reine Datenrate und die Zahl der Datenverbindungen. [Technik und Tests](docs/savegame-transfer.md).
- **Bekannte Grenze**: Die Zeitplanung für Umdrehen, Start/Stopp, Depot, „Linie zuweisen“ und Verkaufen aus v35/v36 greift bei TF3s eigenen Fahrzeugfenstern nicht. Die laufen in einem eigenen Lua-Zustand, den der Mod nicht erreicht. Daher kommen die kleinen Abweichungen bei Fahrzeugpositionen, die v37 jetzt hinnimmt.

## Neu in v36

- **Busse auf eine Linie schicken (Lauf 38)**: Fünf gekaufte Busse, die auf einmal auf Linie 1 geschickt wurden, fuhren auf dem anderen PC nacheinander los, je eine Sekunde später. Danach wichen Fahrzeugpositionen, Fahrzeuge und Städte ab. Jetzt laufen „Linie zuweisen“ und Verkaufen wie Umdrehen über den gemeinsamen Zeitplan. Alle Befehle eines Klicks (z. B. alle Busse eines Fensters) gehen zusammen und starten auf beiden PCs zum selben Spielzeitpunkt. Der andere PC wartet dafür, bis er den gekauften Bus selbst hat.
- **Spielstand-Übertragung**: lief nur mit etwa 1 MB/s, weil der Windows-Standardpuffer (64 KB) bei VPN-Laufzeit nicht reicht. Jetzt 8 MB Puffer und größere Blöcke. Die erreichte Geschwindigkeit steht im Launcher-Protokoll.
- **Launcher-Protokoll**: Der Launcher schreibt `alut_launcher.log` in den Spielordner (Start, Ende, Übertragungen, Neuabgleich, Abweichungen ohne Neuabgleich). Er muss während des Spiels offen bleiben, sonst gibt es keinen Neuabgleich.

## Neu in v35

- **Zug umdrehen (Lauf 37)**: Ein umgedrehter Zug wurde nicht übertragen, wenn er gerade am Bahnhof stand, und lief danach auf beiden PCs verschieden. Jetzt fängt der Mod die Befehle Umdrehen, Start/Stopp und „ins Depot“ ab, wenn sie geklickt werden, und beide Spiele führen sie zum selben Spielzeitpunkt aus (etwa 4 Sekunden nach dem Klick). Ohne gemeinsamen Zeitplan laufen sie sofort und reisen wie bisher.
- **Ladeeinstellung**: Güterwagen mit automatischer Ladung bekommen ihre Ladung vom Spiel. Das galt bisher als Änderung und tauschte auf dem anderen PC den Zug aus. Jetzt wird es nicht mehr übertragen.
- **Neuabgleich im laufenden Spiel**: Startet auf ausdrücklichen Wunsch über **Neu abgleichen**. Der Gastgeber speichert einen gemeinsamen Stand, beide Spiele laden ihn und beginnen eine neue Runde ohne alte ausstehende Aktionen. Weltabweichungen bleiben Hinweise und lösen keinen automatischen Neuabgleich aus.

## Neu in v34

- **Gleichzeitig ausführen (Bauten)**: Ein Bau (Straße, Gleis, Bahnhof, Haltestelle, Depot, Abriss mit dem Bauwerkzeug) wird nicht mehr sofort ausgeführt. Das Spiel meldet kurz „TF3MP: wird gleich auf beiden PCs gleichzeitig gebaut“, der Mod schickt den Bau an den gemeinsamen Zeitplan, beide Spiele halten am vereinbarten Spielzeitpunkt kurz an, bauen ihn dort und laufen weiter. Kommt kein gemeinsamer Zeitpunkt zustande (Mitspieler fehlt, Zeitplan gestört, 30 Sekunden ohne Plan) oder führt TF3 den Bau trotz Ablehnung aus, schaltet der Mod das Anhalten ab und Bauten reisen wie in v33.
- **Warum v33 nichts angehalten hat (Run 36)**: Die Bau-Ereignisse kommen nur bei Skripten an, die sie abonnieren. v34 abonniert sie. Außerdem sind `api.cmd.sendCommand` und die Befehlsbauer in TF3 aufrufbare Tabellen, keine Funktionen.
- **Zeitplan**: Der gemeinsame Zeitpunkt ist jetzt eine Schranke. Ein Spiel, das ihn schon überschritten hat, hält sofort an und baut nach, statt den Plan abzubrechen.
- **Launcher**: Beim Start bleiben keine schwarzen Fenster mehr offen, und das normale X schließt den Launcher immer.

## Neu in v33

- **Kredit (Run 35)**: v32 hat auch die automatischen Monatsraten als neue Kreditänderung geschickt. Das andere Spiel lehnte die Buchung ab und die Übertragung blieb stehen („peer rejected“). Jetzt reist nur das Aufnehmen oder Zurückzahlen selbst, und zwar als dasselbe Ereignis, das die Kreditseite des Spiels schickt. Die Raten bucht jedes Spiel selbst.
- **Gleichzeitige Aktionen**: Die DLL v12 lässt immer nur eine fremde Aktion zur Zeit nachbauen, abwechselnd von beiden PCs. Bauen beide gleichzeitig an verschiedenen Stellen, kommen sich die Nachbauten nicht mehr in die Quere. Beide PCs brauchen dafür die DLL v12.
- **Neu abgleichen**: Das Spiel des Gastgebers speichert den Stand `TF3MP-Neuabgleich` jetzt wirklich selbst (Run 35 erkannte die Speicherfunktion nicht). Reagiert TF3 nicht auf Schließen, beendet der Launcher den Prozess nach 5 Sekunden.
- **Spielstand-Übertragung**: größere Lesepuffer, seltenere Fortschrittsanzeige, Anzeige von Geschwindigkeit und Restzeit; Abbrechen bleibt möglich.
- **Schiffe und Flugzeuge**: Häfen und Flughäfen werden über die Kennungen ihrer Stationen und Terminals zugeordnet, Wasser- und Luftlinien mit ihren Wegpunkten. Im Spiel noch nicht getestet.
- **Genauerer Weltvergleich**: Neben Bauwerken, Straßen/Gleisen, Linien und Fahrzeugen auch Fahrzeugpositionen, Fracht und Städte. Erfasst wird auf einem Spieltakt mit Zeitbudget; was nicht ins Budget passt, bleibt „unbekannt“ und wird im Protokoll als `world scan` gezeigt.
- **Gleichzeitig ausführen (Vorarbeit)**: Der gemeinsame Zeitplan (`timeline.lua`) ist fertig, braucht aber Aktionen, die vor dem Ausführen angehalten werden. Die Spielskripte von TF3 zeigen dafür die Ereignisse `builder.proposalPrepareForApply`/`builder.proposalApply` der Bauwerkzeuge. v33 protokolliert sie und prüft in **Allein testen** einmal, ob ein Bau angehalten und vom Mod später ausgeführt werden kann.

## Neu in v32

- **Ins Depot schicken** (auch „bei Ankunft verkaufen“), **Umkehren** während der Fahrt und das **Weiterfahren aus dem Depot** werden auf den anderen PC übertragen. Ein Fahrzeug, das „bei Ankunft verkauft“ wird, verkauft jedes Spiel selbst, sobald es im Depot ankommt.
- **Kredit**: Nimmt einer von euch einen Kredit auf oder zahlt ihn zurück, bucht das andere Spiel denselben Betrag. Bisher hat der Abgleich den Kredit des Mitspielers wieder zurückgesetzt.
- **Neu abgleichen mit einem Klick**: Findet der Weltvergleich eine Abweichung, speichert das Spiel des Gastgebers selbst den Stand `TF3MP-Neuabgleich`. Beide klicken danach im Launcher **Neu abgleichen**. Der Launcher des Gastgebers nimmt diesen Stand (oder bittet um ein neues Speichern), beendet TF3 und schickt ihn. Der Launcher des Mitspielers beendet TF3, wartet auf den Gastgeber und holt den Stand. Danach starten beide TF3 neu und laden den genannten Spielstand pausiert.
- „Automatisch ersetzen“ gibt es in der Spiel-Schnittstelle nicht. Manuelles Ersetzen eines Fahrzeugs wurde schon vorher übertragen.

## Neu in v31

- Gemeinsame Sitzungskennung und SHA-256-Prüfung von TF3, Multiplayer-Paket, zusätzlichen Moddateien und Ausgangsspielstand. Veränderte Dateien werden vor dem Start erneut erkannt.
- Die DLL prüft die Sitzung auf beiden PCs und wartet auf den richtigen geladenen Spielstand. Ein erneutes Laden oder Partnerneustart verlangt eine neue gemeinsame Vorbereitung.
- Vier Weltprüfsummen vergleichen Gebäude samt Modulen, Straßen/Gleise, Linien und Fahrzeuge. Gleiche Anzahlen mit anderem Inhalt werden erkannt. Anhaltende Unterschiede erscheinen nach zwei aufeinanderfolgenden Prüfpunkten; fehlende Lesezugriffe gelten als unbekannt.
- **Neu abgleichen** führt durch einen neuen gemeinsamen Spielstand: Gastgeber speichert, beide beenden TF3, teilen/holen den Stand und starten eine neue Sitzung. Speichern und Laden erfolgen weiterhin im Spiel.

Aktuelle Übergabe, Grenzen und VPN-Testablauf: [docs/phase5-session-world.md](docs/phase5-session-world.md).

## Korrekturen in v30

Run29 hat Abriss, Linienänderung, Gleise, beide Bahnhöfe, Depot und Signal erfolgreich nachgespielt (11 Aktionen). Die erste Bahnhofserweiterung scheiterte danach mit „Bau nicht möglich“; spätere Aktionen blieben deshalb stehen.

- Reine Erweiterungen einer bestehenden Konstruktion verwenden jetzt denselben Ersatzvorschlag-Generator wie die originale Spieloberfläche: `createProposalReplaceConstruction`. Damit verwaltet die Engine die vorhandenen Anschlussknoten und die vollständige Moduländerung.
- Die vom Ersatzvorschlag erzeugten Konfigurationen werden anschließend geprüft. Es wird kein zweiter Bau oder Überschreiben der Anschlusskonfigurationen ausgelöst.
- Abgelehnte Ersatzvorschläge bleiben ein sichtbarer Fehler. Run30 bestätigt den anschließenden Gleisbau und alle 21 Aktionen; die drei Bahnhofserweiterungen wurden mit erhaltenem Anschluss ausgeführt.

Die letzte Aufnahme kann mit `Test-letzte-Aufnahme.bat` wiederholt werden. TF3 vollständig beenden, den Starter öffnen und **Test starten** wählen. Im Spiel den ursprünglichen Stand **Det** vor den Änderungen laden und die Zeit laufen lassen. Danach im Launcher **Am selben Ort nachbauen** klicken. Die 21 gespeicherten Aktionen werden erneut ausgeführt; eine neue Bauaufnahme ist dafür nicht nötig. Der Launcher prüft den aktuell geladenen Spielstand anhand des neuen Spielprotokolls.

## Korrekturen in v29

Run28 hat 26 Aktionen aufgezeichnet. Bereits der erste Abriss wurde ausgeführt, aber von unserer Erfolgskontrolle fälschlich abgelehnt. Folgeaktionen blieben dadurch stehen.

- Abrissprüfung unterstützt die aufrufbaren API-Tabellen von TF3; Fehlermeldungen nennen jetzt die betroffene Entity und den Prüfungsfehler.
- Bahnhofserweiterungen behalten ihren Eintrag im Konstruktionscache, auch wenn die Engine dieselbe ID erneut verwendet. Dadurch werden weitere Erweiterungen vollständig aufgezeichnet.
- Linien behalten gelöschte Halte als ungültigen Platzhalter am bisherigen Index. Fehlende gültige Stationen bleiben ein Fehler.

Für den damaligen v29-Spieltest war eine **frische Aufnahme** nötig, da run28 bei mehreren Bahnhofserweiterungen die zu ersetzende Konstruktion nicht vollständig aufgezeichnet hat. Die inzwischen gesicherte run29-Aufnahme enthält diese Angaben und kann für v30 wiederverwendet werden.

## Korrekturen in v28

Run27 hat alle 20 Aktionen aufgezeichnet. Beim Nachspielen scheiterte die Zugzuordnung zur Linie (Aktion 10); Bahnhofserweiterung, zusätzliche Gleise, Abriss und Umbenennung wurden deshalb noch nicht ausgeführt.

- Fahrzeugzuordnungen übertragen den tatsächlichen Zielhalt statt immer Halt 0. Alte Aufnahmen enthalten diesen Wert nicht; für den erneuten Test eine frische Aufnahme erstellen.
- Ein erfolgreicher Bau-Retry gibt Folgeaktionen frei. Reiner Abriss wird anhand der tatsächlich verschwundenen Objekte bestätigt, auch bei null Kosten oder einer Erstattung.
- Geld- und Kreditkorrekturen setzen den von der Engine verlangten Buchungszeitwert `-1`.
- Der simulierte Gastgeber protokolliert abgelehnte Aktionen mit ihrer Position und beendet sich geordnet, damit er für den nächsten Versuch neu gestartet werden kann.

## Änderungen in v27 / v10

- GUI-Speicher ohne verbotene globale Variablen; sprachunabhängige UTF-8-Kodierung.
- Simulierter Gastgeber wird am richtigen UDP-Port auf Bereitschaft geprüft und im Hintergrund gestartet.
- Nachrichten bis **256 KiB**, zerlegt in kleine UDP-Pakete; auch die Lua/DLL-Brücke übergibt große Aktionen in begrenzten Stücken. Knotenkonfigurationen werden bei Größenüberschreitung nicht still weggelassen.
- Empfang und Ausführung sind getrennt: Erst ein positives Spielergebnis gibt die nächste Aktion frei. Mehrstufige Bauaktionen warten auf ihre vorherigen Befehle und prüfen anschließend Knotenkonfigurationen und Anschlüsse.
- Geordnete Wiederaufnahme nach Netzwerkunterbrechungen innerhalb derselben Spielprozesse. Volle Warteschlangen lagern weitere Aufnahmen auf den Datenträger aus.
- Bei abgelehnten Aktionen, Partner-Neustart oder Neuladen mit offenen Aktionen wird ein Abgleich verlangt. Beide Spiele dann beenden und vom gemeinsamen Spielstand neu starten. Automatischer Wiederabgleich nach Prozessneustart ist noch offen.

Frühere Transport-Korrekturen: [docs/phase4-reliable-transport.md](docs/phase4-reliable-transport.md). Frühere Spielnachweise: [docs/phase1-bridge.md](docs/phase1-bridge.md). Der übergeordnete Forschungsplan steht in [docs/plan.md](docs/plan.md).

## Tests auf einem PC

Im **Testlabor** bleiben Allein-Test (100 m daneben), Gleiche-Stelle-Test nach Neuladen und simulierter Gastgeber verfügbar. Diese Tests ersetzen den späteren gemeinsamen VPN-Spieltest nicht.

Beim simulierten Gastgeber zeigt **Details prüfen** jetzt bestätigte, offene und nicht prüfbare Testteile, einschließlich fehlender Weltmessungen. Aufgezeichnete Aktionen gelten erst nach bestätigtem Nachbau als geprüft. Frühere Protokolle bleiben beim Neustart erhalten; ein hängender Nachbau endet nach 180 Sekunden ohne Fortschritt. Siehe [Testlabor-Auswertung und Ablauf](docs/testlabor-auswertung.md).

Offline-Tests mit Lua oder Python/lupa:

```powershell
python tools/run_lua.py tests/run_tests.lua
python tools/run_lua.py tests/run_actions.lua
python tools/run_lua.py tests/run_sync.lua
python tools/run_lua.py tests/run_transport.lua
python tools/run_lua.py tests/run_fingerprint.lua
python tests/run_fake_partner.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_lobby.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_game_start.ps1
python tools/run_lua.py tests/run_autoload.lua
python tests/run_launch_request.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_save_transfer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_session.ps1
```

Native DLL und Netzwerktests bauen (Visual Studio C++ x64):

```powershell
cmd /c native\alut_proxy\build.bat
cmd /c tests\build_net_tests.bat
python tests/run_net.py
```

Der Launcher enthält die fertig gebaute DLL in `launcher/bin/alut.dll`; zum Einrichten ist Visual Studio nicht nötig.

Dieses Projekt ist nicht mit Urban Games oder Paradox Interactive verbunden.

# Roadmap: Transport Fever 3 Multiplayer

Stand: **22. Oktober 2026**, aktueller Stand **Probe v66 / Bridge v16**.

Ziel ist zunächst ein verlässliches gemeinsames Spiel für **zwei Windows-PCs mit einer Firma**. Die Reihenfolge unten richtet sich nach den beobachteten Problemen. Versionsnummern und Termine für kommende Schritte werden erst bei der Umsetzung festgelegt.

## Aktueller Stand

| Bereich | Stand |
| --- | --- |
| Internet/VPN, Einladung, gemeinsamer Spielstand und Start | Implementiert; automatische Prüfungen und frühere Zwei-PC-Läufe vorhanden. |
| Straßen, Gleise, Stationen, Linien, Fahrzeuge und Unternehmensaktionen | Implementiert; einzelne Baufehler und daraus folgende Weltabweichungen bleiben offen. |
| Gemeinsame Geschwindigkeit und Geldkorrekturen | v64-Lauf ausgewertet: 4×-Auswahl verliert bei Begrenzung auf 3× ihre Markierung. In v65 korrigiert; tatsächliche Geschwindigkeiten und Geld bleiben im Gegentest zu prüfen. |
| Automatischer Internetstart, temporäre IPv6 als Standard, IPv4-Knopf entfernt | In v64 umgesetzt; Automatik und Layout geprüft. |
| Dauerhafte IPv6 und Einladungen nach Neustart | v65: Routerfehler 606 nachgestellt und mit passender IPv6-Absenderbindung behoben; echte Freigabe/Verlängerung/Löschung geprüft. Einladungsidentität und verfügbare Adresse werden wiederverwendet. |
| Updates im Launcher | v66: GitHub-Release-Prüfung, ZIP-Import, geprüfter Paketwechsel, Sicherung, Rücknahme und Neustart implementiert. Release veröffentlicht; Erkennung und Download ohne Anmeldung mit allen 106 Paketdateien bestätigt. |
| Mitspielerprotokolle beim Gastgeber | Für Internetverbindungen vorhanden. Eigene Gastgeberprotokolle liegen zusätzlich an ihren ursprünglichen Orten; eine vollständige gemeinsame Sitzungsablage fehlt. |
| Neuabgleich | Auf ausdrücklichen Wunsch des Gastgebers vorhanden. Weltabweichungen lösen keinen automatischen Neuabgleich aus. |

Implementiert bedeutet hier nicht automatisch unter allen Bedingungen im echten Spiel bestätigt. Die aktuellen Pakete und Befunde stehen in der [Projektanleitung](../README.md) und der [v65-Auswertung](v65-tempo-ipv6-einladung.md). Die [v63-Auswertung](v63-tempo-geld.md) und der [v64-Internetstart](v64-internetstart.md) dokumentieren die vorausgehenden Änderungen.

## Nächste Schritte in Reihenfolge

### 1. V65 auf zwei PCs gegenprüfen — höchste Priorität

- [x] Den v64-Lauf vom 22. Oktober mit beiden Protokollen auswerten; leere 4×-Auswahl und falschen Straßenendpunkt bei Lippstadt nachstellen und als Regressionen absichern. [Befunde und Korrekturen](v65-tempo-ipv6-einladung.md).
- [ ] Mit demselben frischen Gastgeberstand beginnen und automatische Internetverbindung sowie vorausgewählte temporäre IPv6 prüfen.
- [ ] Auf beiden PCs abwechselnd Pause, 1×, 2× und 4× wählen. Tatsächlichen Zeitfortschritt und Fahrzeugbewegung mit den Protokollen vergleichen.
- [ ] Menü- und Aktionspausen einschließlich überlappender Vorgänge prüfen: Beide Spiele halten an und übernehmen anschließend wieder die gemeinsame Vorgabe.
- [ ] Auf beiden Seiten bauen, eine Linie erstellen, Fahrzeuge kaufen und zuweisen; Geld und Aktionsbestätigungen vergleichen.
- [ ] Einen ausdrücklichen Neuabgleich durchführen und prüfen, dass frühere ausstehende Vorgänge danach nicht erneut ausgeführt werden.
- [ ] Dauerhafte IPv6 von außen prüfen, beide Launcher neu starten und denselben v65-Einladungslink erneut verwenden.

**Erledigt, wenn:** Ein dokumentierter Lauf mit beiden Rollen und den zugehörigen Protokollen vorliegt. Tempoänderungen dürfen nach ihrer Übernahme nicht wieder vom alten Tempo überschrieben werden. Die tatsächliche Beschleunigung wird unter Berücksichtigung der gemeldeten Leistungsgrenze bewertet. Neue Fehler werden mit Zeitpunkt, Aktion und Ergebnis auf beiden PCs festgehalten.

### 2. Protokolle vollständig pro Sitzung sammeln

- [ ] Einen gemeinsamen Sitzungsordner für Gastgeber und Mitspieler anlegen, mit eindeutig getrennten Unterordnern für beide PCs.
- [ ] Eigene Spiel-, Bridge-, Launcher-, Status-, Internet- und Übertragungsprotokolle zusammen mit den bereits empfangenen Mitspielerprotokollen sichern.
- [ ] Paket-/Spielversion, Sitzungskennung, Zeitangaben und Hinweise auf fehlende oder gekürzte Dateien ergänzen; Einladungen und Zugangsschlüssel aussparen.
- [ ] Den Ordner im Launcher direkt öffnen und ein Diagnosepaket exportieren können.
- [ ] Festlegen, wie lange Sitzungen aufbewahrt werden und wie Größenbegrenzung und Protokollrotation sichtbar bleiben. VPN/LAN soll zumindest eine vollständige örtliche Ablage erhalten; die automatische Übernahme der Gegenseite ist dort gesondert umzusetzen.

**Erledigt, wenn:** Ein Diagnosepaket die Daten beider PCs aus derselben Internetsitzung enthält, ohne dass Dateien manuell in Steam-Verzeichnissen gesucht werden müssen. Fehlende Daten sind ausdrücklich gekennzeichnet.

### 3. Haltestellen und abhängige Linien zuverlässig nachbauen

- [x] Lippstadt-Aufnahme korrigieren: behaltene Anschlussknoten vor versetzten Segmentendpunkten verwenden; entfernte Knoten und native Ersatzpositionen weiter unterstützen. Regressionstests bestehen in v65.
- [ ] Lippstadt-Haltestelle und anschließende Linienänderung mit v65 in beiden Baurichtungen im echten Spiel bestätigen.
- [ ] Den Fall „Bus Lychen“ mit Haltestelle nahe einer Kreuzung erneut prüfen.
- [ ] Die Parzellenbehandlung an der tatsächlichen nativen API ausrichten. Der in v63 entfernte Zugriff auf eine fehlende Befehlsvorschau löst noch nicht jeden echten Parzellenkonflikt.
- [ ] Freie und besetzte Parzellen, beide Straßenseiten und Straßenumbauten unterscheiden; keine unkontrollierten Abrisse als Ersatzlösung verwenden.
- [ ] Abhängige Linien- und Fahrzeugaktionen bei fehlgeschlagenen Voraussetzungen gezielt zurückstellen oder verständlich ablehnen, statt eine Folge unklarer Zuordnungsfehler zu erzeugen.

**Erledigt, wenn:** Gültige Haltestellen und zugehörige Linien in beiden Baurichtungen funktionieren. Echte Konflikte werden auf beiden PCs nachvollziehbar gemeldet; es gibt weder Lua-Abstürze noch fälschliche Erfolgsbestätigungen.

### 4. Geldführung an gemeinsame Aktionen binden

- [ ] Käufe, Verkäufe, Baukosten, Kredite und Subventionen nach abgeschlossenen gemeinsamen Aktionen überprüfen.
- [ ] Den Abgleich bei versetzten Spieluhren und verspäteten Antworten absichern. Die v63-Sperre gegen ungeeignete Vergleichspunkte bleibt erhalten.
- [ ] Einen verlässlichen Abgleich nach gemeinsamen Aktionen ausarbeiten, damit dauerhaft unterschiedliche Messpunkte den Geldabgleich nicht unbegrenzt verhindern.
- [ ] Sofortige Aktionskosten von laufenden Simulationseinnahmen und nativen Kreditplänen unterscheiden. Bestätigungen müssen Doppelbuchungen ausschließen.

**Erledigt, wenn:** Nach derselben bestätigten Aktionsfolge der Geldabgleich nachvollziehbar zum Gastgeberkonto führt. Alte Vergleichspunkte dürfen Käufe weder zurückerstatten noch erneut abbuchen. Laufende wirtschaftliche Abweichungen bleiben getrennt messbar.

### 5. Große Karten, Weltvergleich und Dauerbetrieb prüfen

- [ ] Zeitkosten von Aktionsscans, Zustandskopien und Weltprüfungen messen; erst anhand dieser Messungen optimieren.
- [ ] Unlesbare Weltfelder und ausgeschöpfte Erfassungsbudgets untersuchen. Ein unvollständiger Vergleich darf nicht als Übereinstimmung gelten.
- [ ] Einen echten Dauerlauf von mindestens 60 Minuten mit Bauen, Fahrzeugen, hohen Tempowünschen und normalen Pausen protokollieren. Das ist ein Testziel, keine Zeitabschätzung für die Umsetzung.
- [ ] Warteschlangen, Speicherverbrauch, Protokollgröße, tatsächliches Spieltempo und Häufigkeit notwendiger Neuabgleiche auswerten.

**Erledigt, wenn:** Ein reproduzierbarer Bericht zu Belastung und Grenzen vorliegt und keine unerklärten dauerhaft wachsenden Warteschlangen bestehen. Verbleibende Leistungsgrenzen werden mit Messwerten beschrieben.

### 6. Verbindung und Wiederverbindung für den Alltag absichern

- [x] Updates im Launcher mit GitHub-Release und örtlichem ZIP-Import implementieren; Hintergrundjobs, Prüfsummen, Sicherung und Rücknahme automatisch prüfen (v66).
- [x] Erstes öffentliches Release bereitstellen und Download aus dem Launcher ohne GitHub-Anmeldung bestätigen (v66, alle 106 Dateien geprüft). [Ablauf](v66-launcher-updates.md).
- [x] Schlüssel und Zertifikat geschützt speichern; identischen Einladungslink nach Neustart eines eigenen Launcherprozesses per TLS prüfen (v65).
- [x] Routerfreigabe für temporäre und dauerhafte IPv6 mit passendem Absender, Verlängerung und Löschung am tatsächlichen Router prüfen (v65).
- [ ] Kurze Internetunterbrechungen, verlorene Diagnosedaten und Abbrüche der Spielstandübertragung im echten Zwei-PC-Lauf prüfen.
- [x] Noch verfügbare gespeicherte IPv6 und Internetport wiederherstellen; weggefallene gespeicherte Adressen sichtbar melden (v65).
- [ ] Einen beständigen Namen oder Vermittlungsdienst für Links bei geändertem Anbieterpräfix bzw. weggefallener temporärer IPv6 ausarbeiten. Wörtliche IP-Links können diese Adresswechsel bisher nicht überstehen.
- [ ] Wechsel zwischen Gastgeber, Beitreten und VPN/LAN sowie Schließen und Neustarten des Launchers prüfen.
- [ ] Verständliche Statusmeldungen und einen eindeutigen Weg zum erneuten Verbinden sicherstellen, ohne wiederholte automatische Einrichtungsversuche nach einem Fehler.

**Erledigt, wenn:** Nach einer Unterbrechung entweder eine bestätigte Wiederaufnahme oder eine klare Aufforderung zum erneuten Verbinden erfolgt. Spielaktionen dürfen dabei nicht doppelt ausgeführt werden.

## Danach: stabile Zwei-Spieler-Alpha

- [ ] Die oben bestätigten Ergebnisse und verbleibenden Grenzen in einer aktuellen Testmatrix festhalten.
- [ ] Ein aus dem geprüften Quellstand gebautes Paket auf beiden PCs verwenden; Installation, Aktualisierung und Entfernen erneut prüfen.
- [ ] Eine Alpha erst dann als stabil kennzeichnen, wenn die echten Zwei-PC-Nachweise vorliegen. Automatische Tests allein reichen dafür nicht aus.

## Spätere Erweiterungen

Mehr als zwei Spieler, getrennte Firmen, Chat, weitere Betriebssysteme und breitere Kompatibilität mit zusätzlichen Mods sind mögliche Ausbaustufen. Sie sind noch nicht begonnen oder terminlich zugesagt. Voraussetzung sind eine verlässliche Zwei-PC-Basis und eine gesonderte Prüfung der jeweiligen Architektur.

## Pflege der Roadmap

Nach jedem echten Testlauf werden Befund, verwendete Version und Protokollablage verlinkt. Ein Punkt wird erst abgehakt, wenn sein beschriebenes Ergebnis belegt ist. Neue Fehler bei Tempo, Geld oder Bauaktionen haben Vorrang vor zusätzlichen Funktionen.

Der [ursprüngliche Forschungsplan](plan.md) bleibt als historische Dokumentation erhalten. Diese Datei ist die aktuelle Entwicklungsroadmap.

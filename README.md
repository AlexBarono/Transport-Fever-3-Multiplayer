# Transport Fever 3 Multiplayer

Experimenteller Community-Mod für zwei PCs: Straßen, Gleise, Bahnhöfe, Depots, Abriss, Linien, Fahrzeuge und Unternehmensänderungen werden zwischen zwei Spielen übertragen. Aktueller Stand: **Probe v67 / DLL v16**. **Beide PCs brauchen das v67-Paket.** Der Mitspieler empfängt den gemeinsamen Spielstand automatisch; der Gastgeber startet danach beide Spiele. Abweichungen bleiben Hinweise. Ein Neuabgleich erfolgt auf Wunsch des Gastgebers.

[Roadmap](docs/roadmap.md) · [Dokumentation](docs/README.md) · [Versionsverlauf](docs/versionsverlauf.md) · [v67: Launcher und Freunde](docs/v67-launcher-freunde.md)

## Neu in v67

- **Maximieren und F11** funktionieren wieder. Das Fenster ist frei vergrößerbar; kleinere Fenster lassen sich scrollen.
- **Neue Oberfläche nach Microsoft Fluent 2:** klare Navigation, mehr Abstand und lesbare Schaltflächen. Der Updateknopf wird nicht mehr überdeckt. Während der Internet-Einrichtung zeigt die Einladung einen Ladekreis mit verständlichem Status.
- **Freunde:** Namen und vollständige Einladung einmal speichern. Später unter **Freunde** den Namen anklicken oder unter **Beitreten** auswählen; die Einladung wird eingesetzt und die Verbindung startet automatisch. Über **…** am Namen lassen sich Einträge bearbeiten. Die Liste bleibt bei Updates erhalten.
- **Anleitung:** Gastgeber, Beitreten, Freunde, Updates und Fehlersuche direkt im Launcher nachlesen.
- [Bedienung, Designquellen und Tests](docs/v67-launcher-freunde.md). Bei geänderter Internetadresse des Gastgebers muss der gespeicherte Link weiterhin aktualisiert werden.

## Updates seit v66

- **Updates direkt im Launcher:** Links auf **Auf Updates prüfen** und bei einer neuen Version auf **Update installieren** klicken. Der Launcher lädt das GitHub-Release, prüft es und startet nach dem Paketwechsel neu.
- **Update aus ZIP** funktioniert zusätzlich ohne GitHub-Anmeldung. ZIP auswählen, prüfen lassen und **Update installieren** klicken.
- Der vorherige Paketordner bleibt als Sicherung erhalten. Die gespeicherte Interneteinladung bleibt bestehen. Zum Installieren das Spiel und die gemeinsame Sitzung vorher beenden; beide PCs aktualisieren.
- Für Online-Downloads muss das Repository öffentlich sein und ein veröffentlichtes Release mit `update.json` und dem Windows-Paket enthalten. Der mitgelieferte GitHub-Workflow erstellt diese Dateien bei einem Versionstag automatisch. [Bedienung, Veröffentlichung und Tests](docs/v66-launcher-updates.md).

## Korrekturen aus v65

- **4× bleibt ausgewählt**, wenn TF3 das tatsächliche Tempo auf beispielsweise 3× begrenzt. Die native Oberfläche hatte dann keinen passenden Knopf und zeigte keine Auswahl. Die Leistungsgrenze bleibt wirksam.
- **Dauerhafte IPv6:** Die Routerfreigabe wird mit der ausgewählten IPv6 als Absender angefordert. Damit akzeptiert der hier getestete Router auch die zuvor mit Fehler 606 abgewiesene dauerhafte Adresse. Verlängerung und Schließen sind ebenfalls geprüft.
- **Einladungen bleiben nach Launcher-Neustarts gültig**, solange öffentliche Adresse und Port gleich bleiben. Der Launcher speichert Schlüssel und Zertifikat mit Windows-Benutzerschutz und verwendet die letzte noch verfügbare Adresse wieder. Beim Umstieg von v64 einmal die neue v65-Einladung teilen. Ändert sich die Internetadresse, muss der Link weiterhin aktualisiert werden.
- **Weniger fehlgeschlagene Haltestellenaktionen:** Beim Ersetzen einer Straße werden die tatsächlichen Anschlussknoten übertragen. Versetzte Segmentendpunkte hatten im letzten Lauf zwei Baufehler und anschließend fehlende Linienhalte verursacht.
- [Protokollbefunde, Tests und verbleibende Grenzen](docs/v65-tempo-ipv6-einladung.md). Bereits auseinanderlaufende Karten einmal über den Gastgeber **Neu abgleichen**.

## Korrekturen aus v64

- **Internetverbindung automatisch öffnen:** Beim Gastgeber startet „Internet ohne VPN“ nach Auswahl der Adresse automatisch. Eine verfügbare **temporäre IPv6-Adresse** ist vorausgewählt; ohne diese wird eine dauerhafte öffentliche IPv6 verwendet.
- Der Knopf **IPv4 automatisch** entfällt. **Einladung kopieren** ist direkt erreichbar; **Erneut verbinden** wiederholt einen fehlgeschlagenen Versuch. Laufende Verbindungen behalten ihre Einladung.
- Die Korrekturen für Spieltempo, Geld und Haltestellen aus v63 sind enthalten. [Internetstart und Prüfung](docs/v64-internetstart.md).

## Korrekturen aus v63

- **Tempoänderungen werden nicht mehr vom alten TF3-Tempo überschrieben:** Die gemeinsame Mod-Steuerung übernimmt die Leistungsgrenze. TF3s zusätzliche Wiederholung eines gedrosselten 4×-Befehls wird in der normalen Spieloberfläche unterdrückt. Pause und 1×/2× können dadurch auch beim Mitspieler wirksam bleiben.
- **Tatsächliches Tempo wird gemessen:** Das Protokoll zeigt zusätzlich, wie viel Simulationszeit tatsächlich pro Sekunde vergeht. Eine angezeigte 4×-Vorgabe garantiert auf einer großen Karte weiterhin keine vierfache Rechenleistung.
- **Geldabgleich:** Unterschiedliche oder noch laufende Spieleraktionen blockieren eine Buchung aus alten Vergleichspunkten. Vor der Buchung wird erneut geprüft, ob inzwischen weitere gemeinsame Aktionen oder Geldkorrekturen erfolgt sind.
- **Haltestellen:** Ein nicht auslesbarer nativer Baubefehl verursacht keinen Lua-Fehler mehr; TF3 prüft den ursprünglichen Bau. Bereits unterschiedliche Parzellen und fehlende Haltestellen können weiterhin einen bewussten Neuabgleich erfordern.
- Beide PCs aktualisieren. [Befunde vom 20. Oktober, Grenzen und Zwei-PC-Test](docs/v63-tempo-geld.md).

## Ohne VPN starten (v67)

1. Beide verwenden dasselbe v67-Windows-Paket und öffnen `Start.bat`.
2. Gastgeber: **Internet ohne VPN** öffnen. Beim ersten Start ist eine temporäre öffentliche IPv6 vorausgewählt, sofern verfügbar. Später wird die letzte noch verfügbare Adresse mit ihrem Internetport wiederhergestellt; die Verbindung öffnet automatisch. Bei Bedarf eine andere Adresse auswählen. Der öffentliche Internetport ist standardmäßig **TCP 47801**.
3. Der Launcher prüft die Windows-Regel und fordert die Routerfreigabe an. Falls Windows Administratorrechte verlangt, bestätigen. **Einladung kopieren** und nur dem Mitspieler geben. Bei gleicher öffentlicher Adresse und gleichem Port gilt sie auch nach Neustarts weiter. Routerfehler stehen im Protokoll. Bei IPv6 müssen beide Anschlüsse IPv6 unterstützen; bei IPv4 kann CGNAT/DS-Lite eine direkte Freigabe verhindern.
4. Mitspieler: **Beitreten**, die vollständige Einladung einfügen. Der Launcher verbindet sich automatisch. **Löschen** leert das Feld und beendet eine noch wartende Verbindung.
5. Erst sobald der andere Launcher verbunden ist, erscheinen beim Gastgeber Spielstandliste und **Spielstand bereitstellen**. Einen Stand auswählen und bereitstellen. Der Mitspieler empfängt und prüft ihn automatisch; alte gleichnamige Dateien bleiben als `.bak` erhalten. Ein noch laufendes TF3 wird für die neue Sitzung beendet.
6. Nach bestätigtem Empfang und Einrichtung wird **Spiel für beide starten** grün. Beide Spiele starten über Steam und laden den gemeinsamen Stand automatisch, einschließlich Aktivierung der Multiplayer-Mod. Ein bereits laufendes TF3 wird vorher geschlossen. Beide Launcher bleiben geöffnet.

Der Internetweg benötigt keinen Vermittlungsserver. Er ersetzt jedoch keine fehlende Erreichbarkeit. Steam-Relays sind hier nicht integriert. Spielaktionen laufen über TLS; Spielstände laufen seit v52 unverschlüsselt über denselben öffentlichen TCP-Port. Die Einladung wird in beiden Fällen geprüft. [Internettransport](docs/v49-internet.md).

## Starten über euer gemeinsames VPN

1. Dasselbe v67-Windows-Paket auf beiden PCs öffnen und das VPN verbinden.
2. Gastgeber: **VPN / LAN**, passende Adresse auswählen, **Adresse kopieren**. Der Wartekanal öffnet automatisch. Für VPN/LAN gilt weiter **TCP + UDP 47800**; eine Routerfreigabe ist dafür nicht nötig.
3. Mitspieler: **Beitreten**, Adresse einfügen (z. B. `100.80.12.4:47800`). Sobald verbunden, wählt und teilt der Gastgeber den Spielstand direkt im Hauptfenster. Beide brauchen dieselbe Paketversion und passende zusätzliche Mods.
4. Der Gastgeber klickt den grünen Knopf **Spiel für beide starten**. Beide Spiele laden den geteilten Stand automatisch. Sobald beide Karten bereit sind, gemeinsam fortsetzen und bauen.
5. **Beide Launcher bleiben offen.** Wichtige Verbindungs-, Übertragungs- und Aktionsfehler erscheinen unter **Sitzung & Protokoll**. Gelbe Weltabweichungen erzwingen keinen Neuabgleich. **Neu abgleichen** gibt es nur beim Gastgeber und lädt seinen frischen Stand bei beiden im offenen Spiel.

Für das automatische Laden wird genau eine Ressource des TF3-Hauptmenüs über die Ressourcenliste ergänzt; das große Spielarchiv bleibt unverändert. Die originale Liste wird gesichert und beim **Mod entfernen** wiederhergestellt. Nach Steam-Updates gegebenenfalls die Mod entfernen und neu einrichten. [Technik, Grenzen und Testplan](docs/v53-launcher-start.md).

**Nur Einstellungen speichern** und **Am selben Ort nachbauen** stehen im Testlabor. Der erste Knopf installiert Mod/Bridge und schreibt die Einstellungen, ohne Steam zu öffnen. Der zweite spielt eine aufgezeichnete Baufolge im Test *Gleiche Stelle* nach dem Neuladen am ursprünglichen Ort ab. Im normalen Gastgeber-/Mitspielerablauf werden diese Werkzeuge nicht benötigt.

## Paket erstellen

Das portable Windows-Paket wird aus dem Repository gebaut:

Nach einem frischen Git-Checkout zuerst die native DLL wie unter **Entwickeln und prüfen** bauen und nach `launcher/bin/alut.dll` übernehmen. Der Paketbau vergleicht beide Dateien; sie müssen übereinstimmen.

```powershell
powershell -NoProfile -File tools/package.ps1
```

Ausgabe: `release/TF3-Multiplayer-v67-Windows.zip` sowie die zugehörige `.update.json` mit Version, Größe und Prüfsumme. Die ZIP enthält außerdem eine vollständige Dateiliste mit Prüfsummen. Ein vorhandenes Paket lässt sich mit `-Force` ersetzen. Der Paketbau prüft Versionen, Moddateien und die mitgelieferte DLL; er verändert keine Spielinstallation. Die ZIP-Dateien werden lokal erzeugt und sind nicht im Git-Repository enthalten.

## Tests auf einem PC

Im **Testlabor** bleiben Allein-Test (100 m daneben), Gleiche-Stelle-Test nach Neuladen und simulierter Gastgeber verfügbar. Diese Tests ersetzen einen echten Zwei-PC-Test über Internet oder VPN nicht.

Beim simulierten Gastgeber zeigt **Details prüfen** bestätigte, offene und nicht prüfbare Testteile, einschließlich fehlender Weltmessungen. Aufgezeichnete Aktionen gelten erst nach bestätigtem Nachbau als geprüft. Frühere Protokolle bleiben beim Neustart erhalten; ein hängender Nachbau endet nach 180 Sekunden ohne Fortschritt. Siehe [Testlabor-Auswertung und Ablauf](docs/testlabor-auswertung.md).

## Entwickeln und prüfen

Offline-Tests mit Lua oder Python/lupa:

```powershell
python tools/run_lua.py tests/run_tests.lua
python tools/run_lua.py tests/run_actions.lua
python tools/run_lua.py tests/run_sync.lua
python tools/run_lua.py tests/run_transport.lua
python tools/run_lua.py tests/run_fingerprint.lua
python tests/run_fake_partner.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -STA -File tests/run_launcher_view.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_friends.ps1
powershell -NoProfile -ExecutionPolicy Bypass -STA -File tests/run_friends_ui.ps1
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
Copy-Item native\alut_proxy\build\alut.dll launcher\bin\alut.dll
cmd /c tests\build_net_tests.bat
python tests/run_net.py
```

Der Launcher enthält die fertig gebaute DLL in `launcher/bin/alut.dll`; zum Einrichten ist Visual Studio nicht nötig.

`main` enthält den aktuellen gemeinsamen Stand; `probe-v2` bleibt als Arbeitszweig erhalten. Frühere Arbeitszweige sind unter Tags mit dem Präfix `archive/` gesichert. Die ursprünglichen Diagnoseprotokolle bleiben im [Protokollarchiv](logs/README.md) zugänglich.

Dieses Projekt ist nicht mit Urban Games oder Paradox Interactive verbunden.

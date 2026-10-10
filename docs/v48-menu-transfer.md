# v48: Menüpause, Fortsetzen nach Fahrzeugaktionen, Spielstandübertragung

## Menüpause und vorheriges Tempo

TF3s `gui/main/pause_menu.tl` ruft beim Öffnen `api.gui.game.setInGameMenuPause(true)` und beim Schließen dieselbe Funktion mit `false` auf. Die Multiplayer-Erweiterung beobachtet diese Aufrufe direkt im nativen GUI-Kontext und veröffentlicht den zusätzlichen Zustand `menu`. Der bestehende DLL-v13-Kanal hat acht Plätze; mit diesem Zustand werden sieben verwendet. Eine neue DLL ist nicht erforderlich.

Die GUI auf beiden PCs hält die Geschwindigkeit bei 0, solange eines der Menüs offen ist. Ein Geschwindigkeitsklick hebt diesen Halt nicht auf. Wenn beide Menüs geschlossen sind, wird die gespeicherte Geschwindigkeit wiederhergestellt. Liegt gleichzeitig ein Halt für eine gemeinsame Aktion vor, wartet die Wiederaufnahme auch auf deren Freigabe. Eine vor dem Halt gewählte Pause bleibt erhalten. Die vorübergehende Pause überschreibt das gemeinsame Geschwindigkeitsregister nicht.

Für das Umdrehen von Fahrzeugen gilt weiterhin der gemeinsame Aktionszeitplan. Nach seiner Freigabe bleibt der automatische Halt so lange markiert, bis der Fortsetzen-Befehl bestätigt und tatsächlich sichtbar geworden ist. Auch ein sehr schnell geschlossenes Menü kann damit einen noch ausstehenden Pause-Befehl nicht als neue Benutzerpause veröffentlichen. v48 prüft zusätzlich die Überschneidung mit geöffneten Menüs und erhält das ursprünglich gespeicherte Tempo auch dann, wenn während eines noch laufenden Fortsetzen-Befehls ein neuer Halt beginnt.

Gelbe Weltabweichungen allein pausieren weiterhin nicht. Neuabgleich bleibt manuell.

## Befund zur bisherigen Übertragung

Die lokalen Launcher-Protokolle vom 9./10. Oktober melden vier Datenverbindungen und reine Datenraten von ungefähr 0,8–1,4 MiB/s. Die langsame Übertragung ist damit tatsächlich dokumentiert. Die Gesamtdauer enthält zusätzlich Warten, Dateiprüfung und gegebenenfalls Rückfragen.

Eine 16-MiB-Stichprobe aus dem aktuellen Spielstand ließ sich mit schneller Deflate-Kompression praktisch nicht verkleinern: 16.777.216 Bytes wurden zu 16.780.399 Bytes. Zusätzliche Kompression ist deshalb für diesen Spielstand keine sinnvolle Beschleunigung.

Das bisherige Verfahren wartet auf jeder Datenverbindung nach einem MiB auf eine Empfangsbestätigung. v48 vereinbart mit `bulk=1` das neue Nutzdatenformat `TF3MPDATA4` und die Datenverbindung `TF3MPRANGE2`: Vier TCP-Ströme senden kontinuierlich, während eigene Hintergrundaufgaben die Bestätigungen lesen. Der Fortschritt beim Gastgeber zählt weiterhin die vom Empfänger bestätigten Bytes. Die Bestätigung entfällt also nicht; ihr Eingang blockiert nur nicht mehr jeden nächsten Datenblock.

Unterstützt eine Seite das neue Verfahren nicht, wird bei der Verbindung automatisch `TF3MPDATA3` mit Blockbestätigungen oder der vorhandene Einzelstrom vereinbart. SHA-256, Größen- und Dateinamenprüfung, Abbruch, Wiederholungen und die Sicherung vorhandener Spielstände bleiben bestehen. Nach einem Abbruch gibt es keinen unbestätigten Geschwindigkeitswechsel des Übertragungsverfahrens mitten im Dateistrom.

## Messprotokolle

Jeder Aufruf erzeugt auf jedem PC eine eigene JSONL-Datei unter `%LOCALAPPDATA%\TF3MP\Logs\save-transfer-*.jsonl`. `alut_launcher.log` nennt ihren Pfad bereits am Anfang, sodass er auch nach einem Abbruch auffindbar bleibt. Erfasst werden:

- Zeitpunkte für Hash-Berechnung, Verbindung, Protokollvereinbarung, Nutzdaten, Prüfung, Rückfragen/Ersetzung und Abschluss beziehungsweise Fehler.
- Etwa einmal pro Sekunde: empfangene/bestätigte Bytes, Bytes je Datenstrom, aktuelle Phase und gemessene Datenrate seit Beginn der Hintergrundaufgabe.
- Netzwerk-Lese-/Schreibzeiten, Bestätigungs-Wartezeiten, Dateilese-/Schreibzeiten und tatsächlich eingestellte Socketpuffer.
- Am Ende: reine Datenzeit und MiB/s, SHA-Prüfdauer, tatsächlich verwendete Verbindungen und Verfahren. Größere Übertragungen unter 2 MiB/s erhalten `slow=true`.

Die Werte für Netzwerk und Dateien sind über alle parallelen Aufgaben summiert. Bei kontinuierlichem Senden überlappen Bestätigungs-Wartezeit und Datenübertragung; sie dürfen nicht als aufeinanderfolgende Zeiten addiert werden. Die Momentaufnahmen enthalten eine Durchschnittsrate seit Aufgabenbeginn, der abschließende `data_summary` die reine Datenrate. SHA-Prüfung und Warten auf den Mitspieler sind darin nicht enthalten. Protokolle enthalten keine Sitzungstoken, IP-Adressen, Spielstandnamen oder Dateiinhalte. Ein nicht beschreibbarer Protokollordner verhindert keine Übertragung.

Bleibt die reine Rate auch mit `method=continuous` bei ungefähr 1 MiB/s, zeigen die Protokolle beider PCs, ob die Zeit beim Netzwerkempfang, bei Bestätigungen oder bei Dateizugriffen liegt. Eine Ursache wie VPN-Weiterleitung oder begrenzter Upload ist bislang eine Vermutung, kein belegter Befund.

## Lokale Prüfung

Der reproduzierbare Vergleich `powershell -NoProfile -File tests/benchmark_save_transfer.ps1` überträgt dieselben 64 MiB auf vier Verbindungen über einen lokalen TCP-Relay, der Empfangsbestätigungen um 60 ms verzögert. Der gemessene Lauf ist in `logs/v48-transfer-benchmark.json` gespeichert:

| Verfahren | Reine Datenzeit | Datenrate | SHA-256 |
| --- | ---: | ---: | --- |
| Bisherige Blockbestätigung | 1,065 s | 60,08 MiB/s | bestanden |
| Kontinuierliche Übertragung | 0,141 s | 454,04 MiB/s | bestanden |

Dieser künstliche Vergleich belegt den Wegfall der Wartepausen und liefert keine Prognose für die echte VPN-Geschwindigkeit. Er zeigt auch, dass 60 ms Bestätigungsverzögerung allein die bisher gemessenen etwa 1 MiB/s nicht erklären.

Weitere Tests decken Übertragung zwischen zwei PowerShell-Prozessen, ungerade Dateigrößen und Unicode-Namen, Rückfall bei unterschiedlichen Fähigkeiten, beschädigte Nutzdaten in beiden Verfahren, abgebrochene Verbindungen, Abbrechen im Launcher-Callback und Schutz vorhandener Spielstände ab. Die Lua-Tests prüfen beide Menüöffner, zwei gleichzeitig offene Menüs, Tempoänderungen während des Halts, 0x/1x/2x/4x, überlappende Aktionspausen und verzögerte Fortsetzen-Befehle.

## Nächster echter Zwei-PC-Test

1. Auf beiden PCs v48 verwenden und einen Spielstand über den Launcher übertragen. Danach sind auf beiden PCs Messprotokolle vorhanden; der Eintrag `data_summary` muss `method=continuous` und `streams=4` zeigen. Datenrate und Wartezeiten beider PCs vergleichen.
2. Im Spiel 1x, 2x und 4x wählen. Jeweils beim Gastgeber und beim Mitspieler das Menü öffnen. Beide müssen pausiert bleiben, auch wenn der andere das Tempo anklickt. Erst nach dem Schließen aller Menüs soll das vorherige Tempo zurückkommen.
3. Ein Fahrzeug jeweils von beiden PCs aus umdrehen. Nach der gemeinsamen Aktion muss das vorherige Tempo zurückkommen. Zusätzlich während der Aktion ein Menü öffnen: Bis zum Schließen bleibt die Pause bestehen.
4. Den Ablauf auch mit vorher bewusst gewählter Pause prüfen. Gelbe Weltmeldungen dürfen ohne geöffnetes Menü oder laufende gemeinsame Aktion weiterhin keinen Halt erzwingen.

Für v48 wurde kein echter neuer Zwei-PC-/VPN-Lauf gestartet und kein laufendes Spiel automatisch beendet oder neu geladen.

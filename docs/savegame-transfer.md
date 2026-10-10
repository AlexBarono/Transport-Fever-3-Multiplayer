# Spielstand übertragen — v48

Stand: 10. Oktober 2026. Beide PCs verwenden dasselbe portable Paket und sind im gemeinsamen VPN. Der Gastgeber wählt den Spielstand; der Mitspieler holt ihn über die VPN-Adresse des Gastgebers. Der Launcher prüft vor der Übertragung Spielversion, Modpaket und zusätzliche Mods. Nach erfolgreicher Übertragung laden beide denselben Stand. Der manuell gestartete Neuabgleich im laufenden Spiel verwendet dieselbe Übertragung. [Änderungen und Messungen in v48](v48-menu-transfer.md).

Die Übertragung benutzt TCP auf dem eingestellten Port (Standard 47800). Die laufenden Spielaktionen benutzen UDP auf diesem Port. Für die zusätzlichen Verbindungen sind keine weiteren Ports nötig. Die Windows-Firewall muss den Launcher beziehungsweise PowerShell über den VPN-Adapter zulassen.

## Vier Datenverbindungen

Nach der Sitzungsprüfung vereinbaren die Launcher vier Datenverbindungen und behalten die ursprüngliche Verbindung für Steuerdaten und die abschließende Empfangsbestätigung. Jede Datei wird in vier disjunkte, möglichst gleich große Bereiche geteilt. Das gilt für den Spielstand und das optionale Vorschaubild, auch bei ungerader Dateigröße. Jeder Bereich wird an seiner vorgegebenen Position in die vorläufige Empfangsdatei geschrieben.

Die zusätzlichen Verbindungen müssen die IP-Adresse der Steuerverbindung, die zufällige Kennung dieses Übertragungsversuchs und einen freien Bereichsindex vorweisen. Eine andere Kennung belegt keinen Bereich. Es werden höchstens vier Datenverbindungen angenommen; ungültige Verbindungen und die Wartezeit auf fehlende Verbindungen sind begrenzt. Je Verbindung wird spätestens nach einem MiB Empfang bestätigt. Seit v48 liest eine eigene Hintergrundaufgabe diese Bestätigungen, während der Sender kontinuierlich weitersendet. Der gemeldete Fortschritt zählt bestätigte Daten und nicht bloß große Windows-Sendepuffer. Die Kennung ist eine Zuordnung innerhalb des VPN, keine Verschlüsselung des Spielstands.

Anschließend wird jede komplette Datei mit SHA-256 geprüft. Eine fehlende, doppelte, zu große oder beschädigte Datei ersetzt keinen vorhandenen Spielstand. Empfangene Dateien liegen zunächst als `.part` vor. Im Launcher v51 wird ein anderer gleichnamiger Spielstand automatisch ersetzt; die alte Datei bleibt als `.bak`. Die Versions- und SHA-Prüfung bleibt vorgeschaltet. Direkte Werkzeugaufrufe können über ihren Bestätigungs-Callback weiter ablehnen.

## Oberfläche und Abbruch

`tools/save-transfer-net.cs` führt Netzwerkzugriffe und Fingerabdruckprüfungen auf Hintergrundthreads aus. PowerShell ruft den Fortschritts- und Abbruch-Callback während wartender Zugriffe spätestens nach etwa 100 ms wieder auf. Die Hintergrundthreads greifen nicht auf WinForms zu. Das gilt auch für ausbleibende Kopfdaten, die Kompatibilitätsantwort, einen blockierten Schreibzugriff und die abschließende Bestätigung. Ein Abbruch schließt die betroffenen Verbindungen und wartet kurz auf deren Ende; vorläufige Dateien werden entfernt.

Bei getrennten Verbindungen versucht der Mitspieler den Empfang bis zu fünfmal neu. Der Gastgeber behält dafür seinen Listener. Zurückgebliebene Datenverbindungen verbrauchen das Wiederholungsbudget nicht. Jeder Versuch verwendet eine neue Kennung; unvollständige Dateien werden neu übertragen. Fortsetzen innerhalb einer Teildatei ist nicht implementiert.

Jeder Aufruf schreibt zusätzlich unter `%LOCALAPPDATA%\TF3MP\Logs\save-transfer-*.jsonl` ein Messprotokoll mit Phasen, Datenströmen, Netzwerk-/Dateizeiten und SHA-Prüfdauer. `alut_launcher.log` nennt den Pfad bereits am Anfang und nach erfolgreicher Übertragung die übertragenen Nutzdaten, die reine Datenzeit, MB/s und die tatsächliche Zahl der Datenverbindungen. Die Datenzeit umfasst weder das Warten auf den Partner noch die anschließende Dateiprüfung oder das Laden der Welt in TF3. Vier Verbindungen können eine Begrenzung pro TCP-Verbindung im VPN besser ausnutzen; die erreichbare Gesamtrate hängt weiter von VPN, Internetverbindung und Datenträger ab. Das Laden innerhalb von TF3 wird hierdurch nicht verändert.

## Verträglichkeit

Die Sitzungsprüfung verwendet weiterhin `TF3MPSAVE2`. Der Empfänger meldet seine Parallel-Unterstützung in der Kompatibilitätsantwort. Mit `bulk=1` vereinbaren beide die kontinuierliche Bereichsübertragung `TF3MPDATA4`; fehlt diese Fähigkeit, bleibt es bei `TF3MPDATA3` mit Warten auf Blockbestätigungen. Für den Vergleich lässt sich mit `-Continuous $false` gezielt das bisherige Bereichsverfahren wählen. Fehlt die Unterstützung auf einer Seite, bleibt es beim bisherigen Dateistrom über die Steuerverbindung. Lokale Aufrufe ohne Sitzung verwenden unverändert `TF3MPSAVE1`. Mit `-Connections 1` lässt sich der bisherige Dateistrom ausdrücklich wählen.

Spielstände werden aus dem Ordner des aktiven Steam-Kontos ermittelt. Bei mehreren Konten ohne eindeutige Anmeldung fordert der Launcher eine eindeutige Auswahl über Steam; er nimmt keinen beliebigen zuletzt geänderten Ordner.

## Gegenprüfung

`tests/run_save_transfer.ps1` prüft über echte lokale TCP-Verbindungen mit getrennten PowerShell-Prozessen: vollständige Dateien und Vorschauen, Sitzungsablehnung, falsche Hashes, Namens- und Größenprüfung, Überschreibschutz, vier tatsächliche Datenverbindungen, ungerade Bereiche und Unicode-Namen, Rückfall auf eine Verbindung, Abbruch in den Wartephasen, blockierte Schreibzugriffe, falsche Bereichskennungen, getrennte Datenverbindungen und Wiederholung samt Bereinigung. Der blockierte Schreibzugriff verwendet zusätzlich einen gezielt wartenden Test-Stream, damit der Test unabhängig von Windows-Socketpuffern ist.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_save_transfer.ps1
pwsh -NoProfile -File tests/run_save_transfer.ps1
```

Für parallele Testläufe kann ein anderer Testport mit `-Port 47970` gewählt werden; alle Datenverbindungen verwenden denselben Port. Diese Tests verändern keine installierten Spielstände und starten TF3 nicht. Die Geschwindigkeit und Bedienbarkeit müssen zusätzlich auf den beiden tatsächlichen VPN-PCs geprüft werden.

## Automatischer Beitritt und Start (v51)

`tools/lobby.ps1` empfängt in einem eigenen PowerShell-Runspace. Fortschritt und Abbruch werden über ein gemeinsames C#-Objekt weitergereicht; der Hintergrundcode greift nicht auf WinForms zu. Der Empfänger wartet auf das Bereitstellen des Spielstands, ohne die Oberfläche zu blockieren. Ein Wechsel von Adresse, Rolle oder Spielordner bricht den bisherigen Empfänger ab und schließt seine Verbindung.

Mit `-KeepConnection ([ref]$connection)` behalten Sender und Empfänger nach dem bestätigten Dateispeichern die bestehende TCP-Steuerverbindung. `tools/lobby-channel.cs` übernimmt sie für `READY`, `START`, `STARTED` und `RESYNC`. Kein zusätzlicher Port und keine zusätzliche Routerfreigabe sind nötig; der bestehende TLS-Tunnel trägt dieselbe Verbindung. Ohne diesen optionalen Parameter schließen die Werkzeuge ihre Verbindung wie bisher.

Nach Versionsprüfung, Speichern und Installation meldet der Mitspieler `READY`. Erst dann gibt der Gastgeber-Launcher den Start frei. Ein Start bekommt eine neue Kennung; die Bestätigung muss zu ihr passen. Doppelte Starts öffnen Steam nicht erneut. Die Nachrichten sind an die Sitzung gebunden, größenbegrenzt und auf erlaubte Befehle je Rolle beschränkt. Heartbeats erkennen einen Verbindungsverlust. Eine alte gespeicherte Sitzungsdatei löst keinen Start aus. Nach Verlust der Steuerverbindung braucht ein neuer gemeinsamer Start eine neue Übertragung. Ein laufender Spielkanal bleibt davon unabhängig.

Nur der Gastgeber bietet Neuabgleich an. Er benachrichtigt den Mitspieler über die Launcher-Verbindung; der bestehende Spielkanal kann die Anfrage ebenfalls weiterreichen. Beide Launcher tauschen den frischen Stand aus und laden ihn über die vorhandene Mod-/Bridge-Anbindung im offenen TF3. Weltabweichungen starten diesen Vorgang weiterhin nicht automatisch.

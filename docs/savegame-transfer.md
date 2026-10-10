# Spielstand übertragen — v48

Stand: 10. Oktober 2026. Beide PCs verwenden dasselbe portable Paket und sind im gemeinsamen VPN. Der Gastgeber wählt den Spielstand; der Mitspieler holt ihn über die VPN-Adresse des Gastgebers. Der Launcher prüft vor der Übertragung Spielversion, Modpaket und zusätzliche Mods. Nach erfolgreicher Übertragung laden beide denselben Stand. Der manuell gestartete Neuabgleich im laufenden Spiel verwendet dieselbe Übertragung. [Änderungen und Messungen in v48](v48-menu-transfer.md).

Die Übertragung benutzt TCP auf dem eingestellten Port (Standard 47800). Die laufenden Spielaktionen benutzen UDP auf diesem Port. Für die zusätzlichen Verbindungen sind keine weiteren Ports nötig. Die Windows-Firewall muss den Launcher beziehungsweise PowerShell über den VPN-Adapter zulassen.

## Vier Datenverbindungen

Nach der Sitzungsprüfung vereinbaren die Launcher vier Datenverbindungen und behalten die ursprüngliche Verbindung für Steuerdaten und die abschließende Empfangsbestätigung. Jede Datei wird in vier disjunkte, möglichst gleich große Bereiche geteilt. Das gilt für den Spielstand und das optionale Vorschaubild, auch bei ungerader Dateigröße. Jeder Bereich wird an seiner vorgegebenen Position in die vorläufige Empfangsdatei geschrieben.

Die zusätzlichen Verbindungen müssen die IP-Adresse der Steuerverbindung, die zufällige Kennung dieses Übertragungsversuchs und einen freien Bereichsindex vorweisen. Eine andere Kennung belegt keinen Bereich. Es werden höchstens vier Datenverbindungen angenommen; ungültige Verbindungen und die Wartezeit auf fehlende Verbindungen sind begrenzt. Je Verbindung wird spätestens nach einem MiB Empfang bestätigt. Seit v48 liest eine eigene Hintergrundaufgabe diese Bestätigungen, während der Sender kontinuierlich weitersendet. Der gemeldete Fortschritt zählt bestätigte Daten und nicht bloß große Windows-Sendepuffer. Die Kennung ist eine Zuordnung innerhalb des VPN, keine Verschlüsselung des Spielstands.

Anschließend wird jede komplette Datei mit SHA-256 geprüft. Eine fehlende, doppelte, zu große oder beschädigte Datei ersetzt keinen vorhandenen Spielstand. Empfangene Dateien liegen zunächst als `.part` vor. Vor dem Ersetzen eines anderen gleichnamigen Spielstands fragt der Launcher nach; bei Zustimmung bleibt die alte Datei als `.bak`. Der ausdrücklich gestartete Neuabgleich stimmt dem Ersetzen selbst zu und behält ebenfalls die Sicherung.

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

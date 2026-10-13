# v60: Protokolle des Mitspielers beim Gastgeber

Bei **Internet ohne VPN** überträgt der beigetretene Launcher die Diagnoseprotokolle automatisch an den Gastgeber. Es gibt keinen zusätzlichen Knopf, kein weiteres Fenster und keine neue Portfreigabe. Beide PCs brauchen v60 und lassen ihre Launcher geöffnet.

## Dateien und Ablage

Übertragen werden ausschließlich diese bekannten Quellen:

- Das zuletzt geschriebene TF3-Spielprotokoll `stdout.txt`.
- Bridgeprotokoll `alut_proxy.log` und Launcherprotokoll `alut_launcher.log`.
- Änderungen des Bridgezustands `alut_proxy.status` als zeitlich gekennzeichnete Momentaufnahmen.
- Das Internetmessprotokoll des laufenden Launchers.
- Das aktuelle Spielstandmessprotokoll dieses Launcherprozesses, auch während des Empfangs im Hintergrund.

Beim Gastgeber liegen die empfangenen Daten in einem eigenen Sitzungsordner unter **`%LOCALAPPDATA%\TF3MP\Logs\Mitspieler`**. Sobald Daten angekommen sind, steht der vollständige Pfad unter **Sitzung & Protokoll**. Die Dateien heißen `stdout.log`, `bridge.log`, `launcher.log`, `status.log`, `internet.log` und `transfer.log`; `session.txt` kennzeichnet den Empfang. Die bisherigen örtlichen Protokolle bleiben an ihrem üblichen Ort. Empfangenes Protokollmaterial wird ausschließlich als Datei gespeichert und niemals als Spielbefehl ausgeführt.

Einstellungen, Einladungsdateien und Spielstände gehören nicht zu den Diagnosequellen. Vollständige Interneteinladungen sowie die bekannten Verbindungsschlüssel werden vor dem Upload entfernt. Spiel- und Launcherprotokolle können weiterhin Namen von Spielständen, lokale Pfade und eingegebenen Spieltext enthalten.

## Verbindung und Grenzen

Die Diagnose läuft über einen separaten Kanal mit TLS und derselben geprüften Einladung auf dem bestehenden öffentlichen TCP-Port, normalerweise **47801**. Fehler im Diagnosekanal stoppen weder den Spielkanal noch die Spielstandübertragung. VPN/LAN überträgt diese zusätzlichen Dateien nicht.

Der Upload läuft außerhalb der Oberfläche und ist auf ungefähr **64 KiB pro Sekunde** begrenzt. Zu Beginn werden höchstens die letzten **2 MiB je Quelle** übernommen, danach neue Daten. Ein neuer Spielstart oder eine Protokollrotation wird berücksichtigt. Statusdateien werden als geänderte Momentaufnahmen höchstens alle zwei Sekunden übertragen. Zeilen über 512 KiB und ausgelassene ältere Daten erhalten einen ausdrücklichen Hinweis.

Bestätigte Dateiversätze verhindern doppelte Einträge nach einer Wiederverbindung. Der Gastgeber hält je Protokollart eine aktuelle Datei und eine `.previous`-Datei von jeweils höchstens 8 MiB; damit ist die Ablage eine begrenzte Diagnosehistorie, kein vollständiges Archiv aller früheren Sitzungen. Bei dauerhaft ausgefallener Verbindung können die letzten noch unübertragenen Daten fehlen. Beim Schließen des Launchers endet die Übertragung; ein Neustart beginnt eine neue Diagnosesitzung.

## Gegenprüfung

Mit zwei PCs ohne VPN verbinden. Beim Gastgeber muss nach den ersten Daten der Mitspielerordner erscheinen. Beim Mitspieler einen Bau ausführen und im Gastgeberordner die zugehörige Aktionskennung suchen. Danach manuell neu abgleichen und prüfen, dass auch das neue Spielstandmessprotokoll ankommt. Eine kurze Verbindungstrennung darf nach Wiederverbindung keine bereits bestätigten Zeilen doppelt eintragen. Im VPN-Modus darf kein Diagnoseempfang angelegt werden.

Die automatischen Prüfungen verwenden lokale TLS-Verbindungen und künstliche Protokolldateien. Ein echter Internetlauf mit zwei TF3-PCs bleibt erforderlich; die Funktion behebt keine Routerfreigaben oder verlorenen Spielaktionen.

Geprüft sind 19 Launcherprüfungen für Quellen, Rollenwechsel und VPN-Verhalten sowie zehn Prüfungen mit getrennten Gastgeber-/Mitspieler-Prozessen und echten TLS-Verbindungen. 28 weitere Diagnosetests decken Einladung, verlorene Bestätigung, Wiederverbindung, Datengrenzen, Redaktion, Quellenwechsel, Statusdateien, paralleles UDP und Schreibfehler ab. Die bisherigen 55 Internettransportprüfungen über IPv6 einschließlich vierfacher Spielstandübertragung und 45 Prüfungen über IPv4 bestehen ebenfalls, ebenso 71 Launcher-/Protokoll-, acht Internet-Launcher- und 321 Layoutprüfungen.

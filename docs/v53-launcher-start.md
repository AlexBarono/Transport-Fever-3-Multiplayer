# v53: Verbindung, Spielstand und Start in einem Fenster

## Ablauf

- Gastgeber wählt Internet ohne VPN oder VPN/LAN direkt im Hauptfenster. Internet zeigt den tatsächlichen öffentlichen TCP-Port, standardmäßig 47801. Der interne Spielport 47800 steht nur noch im Testlabor; bei VPN/LAN nennt der Verbindungsstatus TCP und UDP mit dem tatsächlich konfigurierten Port.
- Ein Wartekanal verbindet beide Launcher bereits vor der Spielstandübertragung. Erst dann erscheinen beim Gastgeber die Spielstandliste und „Spielstand bereitstellen“. Die Auswahl geschieht ebenfalls im Hauptfenster. Die Liste aktualisiert sich alle zehn Sekunden und behält die Auswahl bei.
- Beim Mitspieler verbindet sich das Adressfeld automatisch. „Löschen“ bricht den wartenden Auftrag ab, beendet den zugehörigen Internettunnel und leert das Feld. Der laufende gemeinsame Spielstart sperrt diese Eingabe.
- Nach Übertragung, SHA-Prüfung, Mod-Einrichtung und Vorbereitung des automatischen Ladens meldet der Mitspieler READY. Erst dann wird „Spiel für beide starten“ grün. START und STARTED sind an Sitzung und eindeutigen Auftrag gebunden; Wiederholungen öffnen das Spiel nicht nochmals.
- Ein vorher laufendes TF3 wird für die neue Sitzung geschlossen, mit denselben geprüften Prozessadaptern wie beim Neuabgleich. Nach dem gemeinsamen Start laden beide den vereinbarten Stand automatisch. „Neu abgleichen“ bleibt ein ausdrücklicher Gastgeberauftrag.

## Verbindung und Ports

Der Wartekanal verwendet denselben lokalen TCP-Port wie die spätere Dateiübertragung. Ein kurzer, versionierter Handshake und Heartbeats erkennen den Partner. Vor der Übertragung bestätigen beide den Wechsel, schließen den Wartekanal und verwenden das vorhandene Verfahren mit vier Datenströmen und einer Steuerverbindung. Es gibt keinen zusätzlichen freizugebenden Port. Bei Internet läuft das gesamte Verfahren über den vorhandenen authentifizierten Tunnel auf TCP 47801, bei VPN/LAN direkt über TCP 47800. Spielaktionen bleiben bei VPN/LAN UDP 47800.

Ein erneut geöffnetes Internetsetup mit derselben Adresse und denselben Ports behält seine Einladung. Das Neuladen der Adressliste allein unterbricht die Verbindung nicht. Eine andere ausgewählte Adresse oder Verbindungsart beendet die bisherige Vorbereitung; anschließend eine neue Einladung teilen.

## Automatisch den gemeinsamen Stand laden

TF3 bietet die dokumentierte `app.loadGame`-Funktion in seiner Menüoberfläche. Die normale Mod-GUI wird erst nach dem Laden einer Welt aktiv. Deshalb ergänzt der Launcher für den ersten automatischen Start die Hauptmenüressource:

1. TF3 muss beendet sein. Die originale `base/_content.json` wird als `.tf3mp-original` gesichert.
2. Nur der Indexeintrag `gui/menu/main_menu.tl` wechselt aus dem Archiv auf eine ergänzte lose Datei. Eine eigene kleine Lua-Hilfsdatei wird zusätzlich eingetragen. **Kein Spielarchiv wird geändert**; alle anderen Archivpositionen bleiben erhalten. Der originale Spielcode wird lokal gelesen und nicht im Paket verteilt.
3. Der Launcher schreibt einen einmaligen Ladeauftrag in `alut_proxy.launch`. DLL v15 nimmt nur einen höchstens fünf Minuten alten Auftrag an und löscht ihn beim Einlesen. Der Dateiname wird als UTF-8-Hex übertragen, inklusive Leerzeichen, Punkten und Umlauten.
4. Die Bridge übergibt den Auftrag auch an die bereits zwischengespeicherte C-Laufzeitumgebung, damit Lua ihn mit `os.getenv` sieht. Die Menüergänzung liest die Metadaten, aktiviert bei Bedarf `mp_probe_1` und öffnet TF3s eigene ProgressPage. Deren normaler Abschluss startet die geladene Welt. Beim ersten Weltladen wird der Auftrag aus der Lua-Umgebung entfernt.
5. Ein ungültiger Auftrag, ein Metadatenfehler oder eine Lua-Ausnahme löst keine wiederholten Ladeversuche aus. Das Hauptmenü bleibt bedienbar; das Spielprotokoll meldet `autoload failed`. Die Bridge übernimmt den Fehler in ihr eigenes Protokoll, und der Launcher zeigt ihn für den aktuellen Start an.

„Mod entfernen“ stellt die gesicherte Ressourcenliste wieder her und entfernt unveränderte eigene Ergänzungen. Fremde Änderungen werden nicht überschrieben. Hat Steam die Liste aktualisiert, bleibt diese neuere Liste beim Entfernen erhalten. Nach einem Steam-Update gegebenenfalls entfernen und neu einrichten. Eine andere vorhandene lose Hauptmenüerweiterung wird nicht überschrieben.

## Prüfungen

- `run_launcher_view.ps1`: 321 Prüfungen mit echtem WinForms-Hit-Test bei 100 %, 150 % und 200 %. Verbindung, Spielstandliste, Knöpfe und Löschen bleiben sichtbar; ohne Partner ist Teilen verborgen, der interne Port ist in normalen Ansichten verborgen.
- `run_lobby.ps1`: 26 Prüfungen über echte lokale VPN-Sockets und den IPv6-Internettunnel. Einschließlich Wartekanal, Dateiempfang, automatischer Sicherung, READY, gemeinsamen Startsignalen, Duplikaten, vorher laufendem Spiel mit gemocktem Stoppen, Adressänderung/Löschen und manuellem Neuabgleich. Steam, Firewall und Spielprozesse sind gemockt.
- `run_game_start.ps1`: 19 Prüfungen mit temporären Ressourcenlisten/Archiven, einschließlich unveränderten Archivpositionen, Wiederholung, Originalwiederherstellung, Steam-Update, fremder Menüdatei und einmaligem Prozessstopp.
- `run_autoload.lua`: 10 Prüfungen des echten Lade-Helfers gegen die nachgebildete Menü-API, einschließlich asynchroner Metadaten, richtiger Datei, Mod-Aktivierung, Wiederholung und ungültigen Aufträgen.
- `run_launch_request.py`: fünf Prüfungen mit der echten DLL in isolierten Prozessen. Einschließlich abgelaufenen/ungültigen Aufträgen und vorab gefüllter C-Laufzeitumgebung.
- Bestehende Prüfungen: Launcher 60, Internetintegration 8, Mod 140, Sync 67, Wirtschaft 25 und Neuabgleich 34 bestanden. DLL mit MSVC ohne Warnungen gebaut. Native Netzwerkprüfungen über den IPv6-Tunnel bestanden, einschließlich 140 geordneten Aktionen, Paketverlust, Wiederverbindung und Neuabgleich.

Der automatische erste Weltstart und die ergänzte Ressourcenliste brauchen noch einen echten TF3-/Zwei-PC-Durchlauf. Die automatisierten Prüfungen starten oder beenden kein echtes Spiel und ändern keine echte Spielinstallation, Firewall oder Routerfreigabe.

## Praxistest auf beiden PCs

1. Beide v53 entpacken. Gastgeber Verbindung öffnen und Einladung teilen, Mitspieler einfügen. Vorher ist „Spielstand bereitstellen“ verborgen; danach erscheinen Auswahl und Knöpfe.
2. Stand auswählen und bereitstellen. Der Mitspieler wartet nach dem Empfang auf den Gastgeber. Beide können testweise ein altes TF3 im Menü offen haben; für die neue Vorbereitung wird es beendet.
3. Den grünen Startknopf klicken. Beide Spiele sollten selbst in den geteilten Stand laden. Im Protokoll auf `autoload requested`, die tatsächliche Ladezeile und „Gemeinsamer Spielstand geladen“ achten. Bei `autoload failed` das Hauptmenü und Protokoll prüfen.
4. Eine Bauaktion aus jeder Richtung und anschließend einen manuellen Neuabgleich vom Gastgeber prüfen.

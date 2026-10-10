# v50 / DLL v14: Verbindung und Ladebereitschaft

## Befund vom 10.10.2026

Die Internetprotokolle von v49 zeigen fehlgeschlagene IPv6-Gegenproben. v49 startete den TLS-Listener, forderte für IPv6 aber keine Routerfreigabe an. Die Windows-Regel war ein separater Schritt ohne protokollierte Bestätigung. Die FRITZ!Box-Einstellung erlaubt einer Anwendung, einen bestimmten Port anzufordern; sie öffnet ihn allein noch nicht. [FRITZ!-Dokumentation](https://help.avm.de/fritzbox.php?deviceFeatures=1010001111111101011011111101111100011111111101101011111001&hardware=156&language=de&oem=avme&set=009&topic=hilfe_netzwerk_upnp&userSettings=1100).

Der Router dieses PCs meldet den Dienst `WANIPv6FirewallControl:1`, aktive Firewall und erlaubte eingehende Pinholes. Ein Test für TCP 47811 wurde mit 60 Sekunden Laufzeit erfolgreich angelegt und wieder gelöscht. Das bestätigt die Steuerung des Routers, noch keine Erreichbarkeit von einem anderen Internetanschluss.

Beim VPN-Test wurden die drei Spielstände über vier TCP-Datenverbindungen vollständig empfangen und per SHA geprüft (etwa 1,1–1,2 MB/s reine Übertragung). Der erste Spielstart meldete den geladenen Quellstand, aber keine Modinitialisierung. Ein späterer Start meldete lokale Bereitschaft, erhielt jedoch keine passende Partnerverbindung. Erneutes Laden sperrte anschließend die Sitzung erwartungsgemäß. Ohne das Protokoll des Gastgeber-PCs ist nicht belegt, ob dort Modbereitschaft, Rolle/Adresse oder UDP-Erreichbarkeit fehlte. Auf diesem PC sind TF3-TCP- und UDP-Firewallregeln vorhanden.

## Verhalten ab v50

- **Direkt starten** prüft zuerst eine passende Windows-TCP-Regel für den Launcher. Fehlt sie, wird der Windows-Administratorendialog angefordert und die eingerichtete Regel überprüft. Eine vorhandene passende Regel benötigt keine neue Abfrage. Zusätzliche Sperrregeln und Drittanbieter-Firewalls können die Verbindung weiterhin verhindern.
- Bei IPv6 entdeckt der Launcher den UPnP-Dienst des ausgewählten LAN-Gateways und fordert ausschließlich den ausgewählten TCP-Port für die IPv6 dieses PCs an. Er verlängert die 300-Sekunden-Freigabe alle 120 Sekunden und entfernt die zurückgegebene Kennung beim Schließen. Bei einem Prozessabbruch läuft die Freigabe spätestens fünf Minuten nach der letzten Verlängerung ab. Antworten anderer SSDP-Geräte und HTTP-Umleitungen werden nicht als Router akzeptiert. Die Umsetzung folgt [WANIPv6FirewallControl](https://upnp.org/specs/gw/UPnP-gw-WANIPv6FirewallControl-v1-Service.pdf).
- Lehnt der Router die Anfrage ab oder bietet den Dienst nicht an, zeigt der Dialog dies ausdrücklich samt Fehlercode. Dann im Router für genau diesen PC / diese IPv6 den angezeigten TCP-Port freigeben. Es wird keine erfolgreiche Freigabe vorgetäuscht. IPv4 mit UPnP bzw. manueller Freigabe bleibt verfügbar.
- Beim Start eines echten Mehrspielerlaufs prüft der Launcher außerdem die TF3-UDP-Regel. Der Gastgeber benötigt seinen Spielport, der Mitspieler Antworten an seinen dynamischen UDP-Port; beide Regeln sind auf die TF3-Programmdatei begrenzt.
- Die DLL gibt jeder originalen Weltladung eine neue Laufzeitkennung. Der Mod bestätigt sie beim ersten Simulationsupdate und wiederholt die Bestätigung bis zur Quittung. Damit ist die Bereitschaft unabhängig vom optionalen `handleLegacy`-Ereignis. Gespeicherte Aktionen und Korrekturaufträge aus einer früheren Welt werden verworfen. Die ursprüngliche Quellstandprüfung und die Sperre bei ungeplantem erneutem Laden bleiben bestehen.
- **Details prüfen** zeigt Quelle geladen, Mod bereit, Partner bereit sowie gesendete/empfangene UDP-Begrüßungen. Im VPN-Modus fragt ein separater, zustandsloser UDP-Test die Gastgeber-DLL ab. Dieser Test verändert weder Partnerkennung noch Warteschlange und kann bereits vor dem Laden der Welt antworten. Er läuft nicht durch den Internet-UDP-Tunnel, damit dessen lokales Spielziel unverändert bleibt.

## Prüfen mit zwei PCs

1. TF3 und alte Launcher schließen, v50 auf beiden PCs entpacken und starten. Gastgeber und Mitspieler wählen unterschiedliche Rollen.
2. Ohne VPN: Gastgeber startet Internet, bestätigt gegebenenfalls Windows und prüft den Routerstatus. Mitspieler prüft die neue vollständige Einladung von seinem Anschluss. Erst danach Spielstand teilen und beide pausiert laden.
3. Über VPN: normale VPN-Adresse verwenden, Spielstand teilen, über den großen Startknopf starten und denselben vereinbarten Stand einmal laden. Falls die Verbindung fehlt, auf dem Mitspieler-PC **Details prüfen** anklicken. „UDP-Test: Gastgeber-Spiel erreicht“ trennt die Erreichbarkeit von dessen Ladebereitschaft. Keine Antwort bedeutet, Rolle, Adresse und TF3-Firewall auf dem Gastgeber-PC zu prüfen; die erfolgreiche TCP-Spielstandübertragung beweist keinen offenen UDP-Weg.
4. Auf beiden PCs muss **Verbunden** erscheinen. Danach von beiden PCs bauen, Geschwindigkeit ändern und Menüpausen prüfen. Nicht wiederholt aus dem Spielmenü laden, um die Verbindung zu reparieren. Ein gewünschter Neuabgleich erfolgt über den Launcherknopf.

Internetdiagnosen: `%LOCALAPPDATA%\TF3MP\Logs\internet-*.jsonl` mit Windows-Bestätigung, Routerergebnis, Verlängerungen, Ablauf und Bereinigung, ohne Einladungsschlüssel oder IP-Adressen. Spielbereitschaft und UDP-Zähler: `alut_proxy.status` und `alut_proxy.log` im Spielordner.

## Automatische Gegenprüfungen

`tests/run_router.ps1` prüft echte lokale SOAP-Aufrufe mit Freigabe, Verlängerung, Ablauf nach Fehler, Ablehnung und einmaliger Bereinigung derselben Kennung. `-CheckRouter` ergänzt einen tatsächlichen kurz befristeten Routertest mit TLS-Listener und anschließender Löschung. Die Internettests prüfen weiterhin IPv4/IPv6-TLS und vollständige Spielstandübertragung. `tests/run_net.py` prüft fehlendes Legacy-Ereignis, wiederholte/veraltete Weltbestätigungen, echte Reloads und den zustandslosen UDP-Test mit der nativen DLL. Das ersetzt keinen erneuten Zwei-PC-Test.

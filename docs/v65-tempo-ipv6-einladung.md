# v65: Tempoauswahl, dauerhafte IPv6 und beständige Einladungen

Untersucht am **22. Oktober 2026**, Ausgangslauf **Probe v64 / Bridge v16**, Korrekturen **Probe v65 / Bridge v16**. Beide PCs müssen v65 verwenden.

## Befunde aus beiden Spielprotokollen

Die privaten Auswertungskopien liegen unter `release/diagnostics-20261022-v64/`. Sie werden nicht mit dem Paket verteilt. Der zuletzt empfangene Mitspielerlauf liegt unter `%LOCALAPPDATA%\TF3MP\Logs\Mitspieler\client-b9483dface904d978f04228ad0f7a5dc`.

- **22:31 Uhr Ortszeit:** Gemeinsame Vorgabe 4×, tatsächlicher nativer Zielwert 3× aufgrund der Leistungsgrenze. Der native `GameSpeedHelper` übernahm 3 als neue Auswahl. Seine Knöpfe kennen nur Pause, 1×, 2× und 4×; deshalb war danach nichts ausgewählt. Der Fehler ließ sich mit dem aus der installierten Spielversion gelesenen Helfer nachstellen.
- **22:37:34 und 22:37:47:** Zwei Straßen-/Haltestellenaktionen bei Lippstadt scheiterten am vermeintlich fehlenden Straßenabschnitt. Die Aufnahme enthielt als behaltenen Knoten `(3052.600,563.196,1.445)`, verwendete beim Abriss aber einen etwa zwölf Meter versetzten Segmentendpunkt `(3046.510,552.683,1.445)`.
- **22:38:28 und 22:38:49:** Die folgenden Änderungen an „Bus Lippstadt“ fanden den zuvor fehlgeschlagenen Halt nicht. Das sind vier neue örtlich gemeldete Fehler dieses Laufs; höhere Gesamtzähler enthalten ältere Einträge.

## Korrekturen

**Tempo:** Ausschließlich die normale Hauptoberfläche zeigt den tatsächlich übernommenen Zielwert als gemeinsame Benutzervorgabe an. Bei Vorgabe 4× und wirksamer Begrenzung auf 3× bleibt somit 4× ausgewählt. Die echten Komponenten der Simulation und der getrennten Mod-GUI behalten den tatsächlichen Wert. Pause und neue Benutzerklicks bleiben erkennbar. Wenn eine native Hook-Zuweisung fehlschlägt, werden bereits gesetzte Teile zurückgenommen.

Das macht die Berechnung nicht automatisch viermal schneller. Die vorhandenen Protokollmessungen zeigen weiterhin den tatsächlichen Zeitfortschritt; Leistungsgrenzen und noch unterschiedliche Simulationsgeschwindigkeiten müssen im echten Gegentest bewertet werden.

**Straßenersatz:** Die Aufnahme verwendet zuerst die Positionen ausdrücklich entfernter Knoten, danach lesbare behaltene Anschlussknoten und erst zuletzt die Segmentendpunkte. Das behebt den aufgezeichneten falschen Abrissbereich, ohne die Suchentfernung zu erweitern. Fehlende oder mehrdeutige Straßen bleiben Fehler. Bereits fehlende Haltestellen werden nicht nachträglich erraten; dafür den gemeinsamen Stand einmal neu abgleichen.

## Dauerhafte IPv6: nachgestellter Routerfehler

Der Listener antwortete auf diesem PC sowohl über die temporäre als auch über die dauerhafte öffentliche IPv6 per TLS. Über die bisherige IPv4-Routersteuerung akzeptierte der tatsächliche Router die temporäre Adresse und lehnte die dauerhafte mit **606** ab.

Der UPnP-Standard bezeichnet 606 als fehlende Autorisierung. Er empfiehlt für diese Freigaben, dass die angegebene interne IPv6 mit der Absenderadresse der Anfrage übereinstimmt. Derselbe Standard erlaubt das Verlängern einer bestehenden Freigabe durch erneutes `AddPinhole` mit identischem Verbindungstupel. [WANIPv6FirewallControl:1, Abschnitte 2.6.3 und 2.6.4](https://upnp.org/specs/gw/UPnP-gw-WANIPv6FirewallControl-v1-Service.pdf).

v65 ermittelt den Router am Adapter der ausgewählten IPv6. Die eigentliche Freigabeanforderung läuft bevorzugt über dessen IPv6 und bindet ihren Absender ausdrücklich an die ausgewählte öffentliche IPv6. Link-lokale Routeradressen behalten die Adapterkennung. Die Routeradresse stammt aus der örtlichen Routingtabelle; fremde URLs und Weiterleitungen bleiben gesperrt. Router mit ausschließlich über IPv4 erreichbarem Steuerdienst behalten den bisherigen Weg.

Der hier verwendete Router verweigert `UpdatePinhole` über IPv6 ebenfalls mit 606. Dann verlängert v65 dieselbe Freigabe über `AddPinhole`. Beim Schließen wird bei einer IPv6-Ablehnung die ursprüngliche, geprüfte IPv4-Steueradresse für genau die eigene Freigabekennung verwendet. Verweigert ein Router auch das, wird ausschließlich die identische Freigabe auf eine Sekunde verkürzt. Diagnosefelder machen diesen Fall sichtbar.

**Ergebnis am tatsächlichen Router:** Temporäre und dauerhafte IPv6 erhalten nun eine Freigabe, bestätigen deren Verlängerung und lassen die Testfreigabe anschließend vollständig löschen. Für beide Adressen ist der örtliche TLS-Test erfolgreich. Die Tests haben keine Windows-Firewallregel geändert. Eine Verbindung von einem anderen Internetanschluss ist damit noch nicht nachgewiesen.

## Einladung über Neustarts behalten

Der Launcher speichert unter `%LOCALAPPDATA%\TF3MP\Internet\`:

- `host-identity.dat`: Zertifikat mit privatem Schlüssel und Einladungsschlüssel, geschützt durch Windows-DPAPI für das aktuelle Windows-Benutzerkonto.
- `host-endpoint.json`: zuletzt verwendete öffentliche Adresse und Internetport, ohne Einladungsschlüssel.

Ein neuer Launcherprozess lädt dieselbe Identität und stellt eine weiterhin bevorzugte örtliche IPv6 wieder her. Ohne gültiges gespeichertes Ziel bleibt die temporäre IPv6 die erste Auswahl. Eine beschädigte Identitätsdatei wird als Fehler gemeldet und nicht stillschweigend ersetzt.

Beim Wechsel von v64 muss einmal eine v65-Einladung geteilt werden. Danach bleibt der komplette Link bei gleicher Adresse und gleichem Port auch nach einem Launcher-Neustart identisch. Die Identität ist an das Windows-Benutzerkonto gebunden und wird nicht im transportablen Paket verteilt.

Eine als „dauerhaft“ bezeichnete Windows-IPv6 hat einen stabileren Adressanteil, garantiert aber keinen festen Anbieterpräfix. Ein Link mit wörtlicher IP-Adresse kann einen Präfixwechsel oder den Wegfall einer temporären Adresse nicht überstehen. Ein vollständig unveränderlicher Link auch bei solchen Wechseln benötigt zusätzlich einen stabilen Namen mit aktualisierter Auflösung oder einen Vermittlungsdienst; das ist noch offen.

## Prüfung

| Prüfung | Ergebnis |
| --- | --- |
| 19 Lua-Suiten unter Lua 5.4 und 5.2 | Je 631 bestandene Prüfungen; je 25 Quelldateien kompilierbar |
| Installierter nativer GameSpeedHelper, örtlich extrahiert | Alte leere Auswahl nachgestellt; korrigierte 4×-Auswahl bei tatsächlichen 2×/3×/4× bestätigt; bisherige Pause-/1×-/2×-Prüfungen bestehen |
| Einladungsidentität | 12 Prüfungen einschließlich Neustart in eigenem Prozess, identischem Link, echter IPv6-TLS-Prüfung und beschädigter Datei |
| Internetlauncher | 37 Prüfungen einschließlich gespeichertem Ziel, Adresswegfall, temporärem Standard und automatischem Start |
| Routerfixture | 19 Prüfungen einschließlich IPv6-Absender, 606-Verlängerung, befristetem Schließen und Adapterkennung |
| IPv6 mit tatsächlichen Adressen und Router | 19 Prüfungen einschließlich temporärer/dauerhafter Adresse, Verlängerung, Löschung und örtlichem TLS |
| Launcherlayout | 393 Prüfungen bei 100 %, 150 % und 200 % Skalierung |
| Launcher/Protokoll | 71 Prüfungen |
| Internettransport mit vollständiger Spielstandübertragung | 55 Prüfungen einschließlich IPv6-TLS, UDP, Wartephase und vier parallelen Dateiströmen |
| Diagnoseübertragung | 28 Prüfungen; zusätzlich 10 Prüfungen der automatischen Protokollsitzung und 19 ihrer Launcherintegration |
| Lobby und gemeinsamer Start | 26 Prüfungen mit VPN-Sockets und IPv6-TLS; Steam-Aufrufe simuliert |

Die Lua-Suiten verwenden eine simulierte native API; auch die echten Router- und TLS-Prüfungen ersetzen keinen Zwei-PC-Spieltest. Der native Helfer bleibt als private Prüfkopie unter `release/`, nicht im Repository oder Paket.

Reproduzierbare gezielte Tests:

```powershell
python tools/run_lua.py tests/run_speed_hooks.lua
python tools/run_lua.py tests/run_build_regression.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_internet_identity.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_internet_launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_router.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_ipv6.ps1
```

`run_ipv6.ps1 -CheckLocalAddresses` prüft zusätzlich die gegenwärtigen öffentlichen IPv6-Adressen örtlich. `-CheckRouter` fordert für diese Adressen kurzlebige Freigaben am wirklichen Router an, prüft die Verlängerung und schließt sie danach. Nur dieser ausdrückliche Schalter verändert während des Tests Routerfreigaben.

## Nächster echter Gegentest

Beide PCs mit v65 aktualisieren und denselben Gastgeberstand verwenden. Pause, 1×, 2× und 4× in beiden Rollen wählen; Auswahl, wirklichen Zeitfortschritt und Wiederaufnahme nach Aktionspausen vergleichen. Die betroffene Straßenhaltestelle erneut bauen und anschließend die Buslinie ändern. Mit der dauerhaften IPv6 vom Mitspieler-PC verbinden, den Launcher später neu starten und denselben v65-Link erneut verwenden. Ergebnisse und Grenzen werden in der [Roadmap](roadmap.md) nachgetragen.

# Probe v13: zusätzliche Aktionen und Übergabe an Claude

Stand: 06.10.2026. Ausgangspunkt war `11f9eb7`, Probe v12 + Proxy-DLL v7. Vor Beginn war der Git-Arbeitsstand sauber. Die vorhandene Straßen-/Gleisübertragung und der Launcher wurden als Grundlage übernommen. Benutzerpriorität: **erst Bahnhöfe, Depots, Abriss, Fahrzeuge und Linien; danach der Zwei-PC-Test**.

## Implementierter Umfang

| Bereich | Erfassung und Nachbau im Code |
| --- | --- |
| Bahnhöfe / Depots | Vollständige Konstruktion mit Ressourcenname, Matrix, Name und allen Parametern, insbesondere `modules`, `seed`, `year`; keine losen Bahnsteiggleise |
| Konstruktionen ändern | Entfernen und neu anlegen mit `old2new`; auch ein ID-Wechsel an derselben Transformation wird als Ersatz erkannt |
| Abriss | Entfernte eigene Konstruktionen und reine Straßen-/Gleisabrisse; Ziele werden vorher vollständig im lokalen Spiel aufgelöst |
| Linien | Erstellen, Aktualisieren, Name/Farbe ändern, Löschen; Haltestellen, alternative Terminals, Lade-/Wartekonfiguration, Filter, Priorität und Wegpunkte |
| Fahrzeuge | Kaufen, Fahrzeugkonfiguration ersetzen, Verkaufen, Linie zuweisen/entfernen, Name, Start/Stopp, manuelle/automatische Abfahrt |

**Nachweisgrenze:** 53 vorhandene Offline-Tests und 35 neue Aktions-Tests sind erfolgreich. Diese prüfen Attrappen der Engine, keinen echten TF3-Lauf. Der letzte dokumentierte Spielnachweis bleibt Lauf 12 mit Straßen und Gleisen. Für v13 wurden keine Spielinstallation, DLL, Steam-Modkopie oder Spielstände verändert. Es gab keinen Zwei-PC-Test und keinen Push/Commit.

## Dateien und Aufbau

- `mods/mp_probe/content/mp_probe/actions.lua`: Aufnehmen/Diffen des Zustands, Referenzen auf lokale Entitäten, Erstellen der tatsächlichen API-Befehle, persistente Empfangs- und Folgeaktionen.
- `mods/mp_probe/content/mp_probe/wire.lua`: begrenztes Datenformat; keine Ausführung empfangenen Lua-Codes. Zeichenketten werden hexkodiert, damit Namen und Parameter keine zusätzlichen Logzeilen erzeugen.
- `mods/mp_probe/content/mp_probe/main.script.lua`: Probe-Version 13, Routing von A1 neben B3, Polling, Versand und Ausführung über das bewährte `mp_probe_replay`-Simulationsereignis. Speichert für den Straßen-Loopback den ursprünglichen seitlichen Versatz.
- `tests/run_actions.lua`: neue Tests. Bestehende Tests und `build.lua` bleiben unverändert.
- `mods/mp_probe/_content.json`: registriert die beiden neuen Lua-Module, damit der installierte Mod sie findet.

`A1 <Daten>` reist über exakt dieselben `net send`-/`line <token> <net|loop>`-Marker wie die B3-Straßen. Die Proxy-DLL v7 behandelt den Inhalt bereits als Text; ein DLL-Neubau ist dafür nicht nötig. Beide Teilnehmer brauchen den neuen Lua-Mod, ein v12-Mod versteht A1 nicht.

Das erste erfolgreiche Abbild jeder Kategorie ist nur der Ausgangszustand. Bereits vorhandene Gebäude, Linien und Fahrzeuge werden beim Laden nicht als neue Aktionen verschickt. Eigene Konstruktionen/Linien/Fahrzeuge werden alle 10 Updates abgefragt; der Straßenbestand alle 50. Neue A1-Zeilen werden einzeln bei einem Bridge-Tick aus der Lua-Warteschlange versandt. Abhängigkeiten werden zuerst angelegt und zuletzt entfernt. Die Aktualisierungsrate und Speicherlast großer Spielstände sind noch im Spiel zu prüfen.

Sender-IDs sind ausschließlich undurchsichtige Referenzschlüssel. Befehle erhalten aufgelöste lokale IDs. Neue Konstruktionen/Linien/Fahrzeuge werden über ihre Ergebnis-IDs zugeordnet. Bestehende Konstruktionen werden über Ressource/Transformation gefunden, Depot und Station über ihre Position in der Konstruktion. Haltestellenindizes werden an die Reihenfolge der lokalen Stationsgruppe angepasst. Bestehende Linien/Fahrzeuge brauchen einen eindeutigen Namen; bei Mehrdeutigkeit bricht die Aktion ab. Straßenabriss nutzt Positionen, Tangenten und Ressourcen.

Nach erfolgreichem Nachbau wird das Abbild der betroffenen lokalen Entität aktualisiert, damit sie nicht zurückgesendet wird. Bewegungen und normale Haltestellenwechsel von Fahrzeugen erzeugen keine Aktionen. Schlägt eine Abfrage fehl, bleibt das bisherige Abbild erhalten; ein Lesefehler erzeugt keinen Abriss/Verkauf. Keine Folgeaktion ruft `sendCommand` innerhalb eines nativen Rückrufs auf: Sie landet im Script-State und läuft im nächsten Simulationsereignis. Empfangene A1-Aktionen warten hinter vorherigen Folgeaktionen und asynchronen Rückrufen.

Im Loopback stehen Konstruktionen 40 m in **Y-Richtung** daneben; Straßen behalten den bisherigen Versatz quer zur ersten Kante. Linien/Fahrzeuge werden mit den kopierten Stationen/Depots verbunden. Eine bereits beim Laden vorhandene Station oder ein Depot besitzt im Loopback keine Kopie: dann wird nicht versehentlich das Original als Ziel benutzt. Beim Laden (`handleLegacy`) werden ausstehende lokale Aktionen verworfen und der Ausgangszustand neu gelesen; ein nativer Rückruf aus einer alten Sitzung kann nicht wieder aufgenommen werden.

## Herkunft der API-Signaturen

Es wurden die zum installierten TF3 gehörenden Deklarationen gelesen, keine TF2-Signaturen geraten:

`C:/Program Files (x86)/Steam/steamapps/common/Transport Fever 3/api/tealdef/api/`

- `cmd.d.tl`: `makeWorldBuildProposalCmd`, `makeLine*Cmd`, `makeVehicle*Cmd`, Name/Farbe.
- `type.d.tl`: `SimpleProposal.ConstructionEntity`, `Mat4f.cols`, Fahrzeugteile, Waypoint/EdgePos und `NativeLuaTable.asTable`.
- `engine.d.tl`: Konstruktion samt `params_native`, `Line.Stop/StopConfig`, `TransportVehicle.transportVehicleConfig` und Eigentümer.
- `engine/system.d.tl`: Stationsgruppen, Konstruktion/Depot/Station-Zuordnung und `streetSystem.getNode2SegmentMap`.
- `res.d.tl`: Modellnamen übertragen und mit `modelRep.find` lokal auflösen.

## Nächster Schritt für Claude: Ein-PC-Spielprüfung

1. Diff und diese Übergabe lesen. DLL v7 und Launcher sind unverändert. Zum Installieren v13 wie bisher `Start.bat` nutzen; automatische Installation wurde hier nicht vorgenommen.
2. Einen Testspielstand in „Allein testen“ laden, kurze Initialisierung abwarten, einen freistehenden Bahnhof und ein Depot bauen. Nach dem Nachbau müssen im Log `net send A1`, `action construction_create applied` und lokale Ergebnis-Zuordnungen erkennbar sein.
3. Bahnhof modular erweitern, danach eine neue Konstruktion abreißen. `construction_update/remove` prüfen, einschließlich `old2new` und tatsächlicher Entfernung im Spiel.
4. Zwischen neu gebauten Stationen eine Linie erstellen, Lade-/Wartewerte und alternative Terminals ändern, Linie umbenennen/färben und löschen. Bei Gruppenumordnung die Haltestellenindizes prüfen.
5. Fahrzeug in einem **neu gebauten und kopierten** Depot kaufen. Für den ersten Lauf den Kauf abwarten, bevor das Fahrzeug losgeschickt wird. Linie zuweisen, stoppen/starten, Konfiguration ersetzen und verkaufen; auf doppelte Fahrzeuge und Echo achten.
6. Eine neu gebaute, freistehende Straße und ein Gleis vollständig abreißen. Original und Kopie müssen verschwinden. Anschlüsse/Teilstückumbauten sind dafür kein geeigneter erster Test.
7. Fehler, Logs und tatsächlich nachgewiesene Fälle dokumentieren. Erst anschließend der vom Benutzer auf später verschobene Zwei-PC-Test.

Besonders im echten Spiel zu prüfen: vollständige `params_native:asTable()`-Daten modularer Bahnhöfe, schreibbare `constructionsToAdd/old2new`, Ergebnis-IDs als `{id, revision}`, Zeilen-/Fahrzeugtypen, Eigentümer-Komponenten und gruppierte Stationen. Bei `action capture … failed`, `action … rejected by game` oder `action continuation … failed` steht die konkrete Abbruchursache im Spiel-Log.

## Offene Grenzen

- Polling erfasst Zustandsänderungen. Bauen und Abreißen zwischen zwei Abfragen bleibt unsichtbar. Ein neu gekauftes Fahrzeug, das das Depot vor der ersten Erfassung verlassen hat, wird ausgelassen (`action NOT sent, vehicle …`, ab v26 ohne die übrigen Fahrzeuge aufzuhalten); sein tatsächliches Kaufdepot wird nicht geraten.
- Reiner Abriss ist implementiert. Straßenumbau, Anschließen/Teilen, Abriss mit gleichzeitig neu entstandenen Kanten und Edge-Objekte brauchen eine vollständige Übertragung des gemischten Vorschlags. Solche gemischten Kantenänderungen werden übersprungen, damit nicht nur ihre zerstörende Hälfte beim Partner ankommt.
- Die Loopback-Kopie kann wegen Gelände/Kollisionen abgelehnt werden. Fehlende oder mehrdeutige Referenzen brechen die betreffende Aktion ab; es gibt noch keinen automatischen Resync oder erneuten Versuch nach einem Spiel-Fehler.
- Die DLL bestätigt wie bisher Empfang, nicht erfolgreiche Ausführung. Ihre Queue fasst weiterhin acht Zeilen. Der gedrosselte A1-Versand ersetzt noch keine Rückstaukontrolle bei langer Trennung oder vielen B3-Bauten.
- Eine Zeile bleibt auf 16383 Zeichen beschränkt. Sehr große modulare Konstruktionen oder Linien werden mit Hinweis im Log ausgelassen (Aktionen: `action NOT sent`, Bauzeilen: `capture line TOO LONG`). Fragmentierung ist nicht implementiert.
- Kosten, tickgenaue Synchronisierung, Depot-Rückruf/Umkehren als einzelne Fahrzeugbefehle, getrennte Firmen und Netzwerkabsicherung gehören zu späteren Erweiterungen. Fahrzeugersatz überträgt die Baukonfiguration; Alter/Wartungszustand werden nicht synchronisiert.

## Offline-Prüfung

```powershell
python tools/run_lua.py tests/run_tests.lua
python tools/run_lua.py tests/run_actions.lua
```

Für diesen Lauf wurde eine separate Testumgebung unter `%TEMP%/tf3mp-codex-tests` mit `lupa` angelegt; kein globales Python-Paket wurde verändert. Auf diesem Rechner kann man beide Befehle auch mit deren `Scripts/python.exe` ausführen.

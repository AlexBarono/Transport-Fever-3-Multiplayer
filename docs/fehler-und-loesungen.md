# Fehler und Lösungen

Stand: 8. Oktober 2026. Diese Datei sammelt die Fehler, an denen Claude beim Multiplayer-Mod gearbeitet hat: was man im Spiel gesehen hat, woran es lag und wie es gelöst wurde. Die Läufe („Lauf 23“, „run34“) sind die Testrunden auf dem PC des Nutzers; ihre Protokolle liegen unter `logs/`. Die Kennungen wie `d3d90bc` sind Commits im Repository.

## So arbeitet der Mod (kurz)

Wer etwas baut, dessen Spiel beschreibt den Bau als eine Textzeile (Straßenstücke, Knoten, Gebäude, Einstellungen der Kreuzungen). Die Zeile geht über die DLL `alut.dll` und das Netzwerk an den anderen PC. Dort baut der Mod genau dasselbe nach und schickt eine Quittung zurück („net result … OK“). Erst nach der Quittung schickt der erste PC die nächste Aktion. Hängt eine Aktion, steht im Launcher „1 Vorgang wartet“.

Zwei Eigenheiten von TF3 stecken hinter vielen Fehlern:

- Der Mod läuft in mehreren getrennten Lua-Umgebungen. `update()` läuft in wechselnden „Sim Pool“-Umgebungen, Bau-Ereignisse und Rückrufe (`handleEvent`) im „Simulation Thread“. Gemeinsam haben sie nur den gespeicherten Zustand (`state:get()`/`state:set()`), und jede Seite bekommt davon eine Kopie. Wer eine alte Kopie zurückschreibt, löscht, was die andere Seite inzwischen eingetragen hat.
- Beim Lesen aus dem Spiel bekommt man Kopien. Wer an eine gelesene Liste etwas anhängt, ändert nur die Kopie, nicht den Bauvorschlag.

## 1. Depot wird nicht an die Straße angeschlossen

Das war der hartnäckigste Fehler. Ein Straßendepot an einer bestehenden Straße wurde auf dem anderen PC zwar gebaut, aber nicht oder falsch mit der Straße verbunden. Er hatte zwei Teile: zuerst das Nachbauen selbst (Lauf 16 bis 23, auf einem PC), dann die Übergabe zwischen zwei PCs (run31 bis run34).

### Teil A: Das Depot richtig nachbauen (Lauf 16 bis 23)

| Lauf | Was man sah | Ursache | Lösung |
|---|---|---|---|
| 16 | Depot-Kopie steht, aber ohne Verbindung zur Straße. | Das kurze Zufahrtsstück gehört halb zum Gebäude und wurde deshalb weggelassen. | v17: Zufahrt in einer zweiten Zeile hinterherschicken. |
| 17 | Spiel lehnt die Zufahrt ab („Bau nicht möglich“). | Allein gebaut passt die Zufahrt nicht, ihr Tor-Knoten gehört dem Gebäude. | v18: Zufahrt in derselben Zeile wie das Gebäude. |
| 18 | Zwei Sackgassen-Wendeschleifen zwischen Straße und Tor. | Das Bauwerkzeug des Spielers „schweißt“ die Zufahrt an die Straße, ein Skript-Bau tut das nicht. | v19/v20: Nach dem Bau prüfen, ob das Tor an der Straße hängt (`weld.lua`). Wenn nicht, den Anschluss vom Spiel selbst berechnen lassen: `refreshConstruction`. |
| 20b | Zwei Zufahrten. Klick auf die kopierte Kreuzung brach das Fenster ab. | Das Depot legt beim Bauen seine eigene Zufahrt, unsere war doppelt. Kreuzungen hatten keine Spurverbindungen, denn die stehen in eigenen „Knotenkonfigurationen“. | v21: Mitgeschickte Zufahrt weglassen. Knotenkonfigurationen werden mit übertragen und gesetzt (`nodecfg.lua`). |
| 21 | Depot gar nicht gebaut, Spiel-Assertion `map_util Get`. | Straße teilen und Depot in einem einzigen Vorschlag mag das Spiel nicht. | v22: In Schritten bauen: erst die Straßen, dann deren Konfigurationen, dann das Depot allein, dann der Anschluss per `refreshConstruction`. |
| 22 | Depot angeschlossen, sieben Sekunden später Absturz. | Die Knotenkonfigurationen wurden nach dem Anschluss noch einmal gesetzt. Dabei verlor ein Straßenstück seine Verkehrsdaten, und das Spiel stürzte ab. Außerdem nannten alte Konfigurationen noch das geteilte Straßenstück. | v23: Alte Konfigurationen im selben Bau entfernen. Knoten am Depot dem Spiel überlassen. Kein letzter Durchgang mehr. |
| 23 | Alles klappt, keine einzige Assertion. | | Depot an der Straße am selben Ort vollständig übertragbar (`0923713`). |

Kurz gesagt: Das Depot wird allein gebaut. Danach lässt der Mod das Spiel den Anschluss selbst berechnen (`refreshConstruction`), genau wie es das Bauwerkzeug tut, und prüft danach, ob das Tor wirklich an der Straße hängt.

### Teil B: Das Depot zwischen zwei PCs (8. Oktober, run31 bis run34)

**run31: „Abgleich erforderlich: game rejected“, wenn der Mitspieler ein Depot baut.**
- Ursache: Zwei Knotenkonfigurationen nannten die Zufahrt, die der Empfänger absichtlich nicht mitbaut, weil das Depot sie selbst legt (siehe Lauf 20b). Die strenge Prüfung aus v31 meldete deshalb einen Fehler, obwohl die Straßen schon standen.
- Lösung `51a6635`: Der Mod merkt sich, welche Teile zur weggelassenen Zufahrt gehören (`build.drop_access`). Die Konfigurationen dafür überlässt er dem Depot (`nodecfg.resolve`).

**run32 und run33: Straße und Depot stehen, aber das Depot wird nie angeschlossen. Keine Quittung, beide Seiten warten, „Weltabweichung“.**
- Ursache: Jeder Schritt des Depot-Nachbaus (Straßen, Prüfung, Depot, Anschluss) wartete darauf, dass `update()` den fertigen vorigen Schritt bemerkt und den nächsten anstößt. Nach dem Depot-Schritt kam dieser Anstoß nicht mehr.
- `bdc8cd3` war ein erster Versuch: `update()` sollte beim Speichern frischere Daten aus dem Zustand übernehmen. Das half nicht (run33).
- Lösung `d3d90bc`: Alle Schritte laufen jetzt direkt nacheinander im selben Ereignis (`main.network_run`). TF3 ruft die Bau-Rückrufe auf, bevor der Befehl zurückkehrt, also ist jeder Schritt sofort fertig.
- Außerdem: Der Gastgeber spielte pausiert. Die Anschlussprüfung war nach 4 Sekunden Spielzeit fällig, und die vergehen bei Pause nie. Jetzt ist sie auch nach 20 Aufrufen von `update()` fällig.
- Neue Protokollzeilen: `net step` und `net waiting` zeigen, worauf eine hängende Aktion wartet.

**run34: Depot angeschlossen und quittiert, danach „1 Vorgang wartet“ und ein Fehler beim nächsten Bau.**
- Was das Protokoll zeigte: Die Quittung für das Depot wurde bei jedem Update erneut geloggt. Die nächste Aktion des Mitspielers (eine Linie) wurde nie angenommen. Danach liefen die Welten auseinander.
- Ursache: Ausgerechnet der Schutz aus `bdc8cd3`. Die Quittung entsteht in `update()`, und dabei wird die erledigte Aktion gelöscht. Der Schutz holte aber beim Speichern aus `update()` die noch offene Aktion aus dem gespeicherten Zustand zurück. So blieb das Depot für immer „offen“, und die Linie stand dahinter in der Schlange.
- Lösung `edc2c7c`: Der Schutz ist entfernt. `main.store` übernimmt beim Speichern aus `update()` die Quittungsfelder immer aus dem aktuellen Zustand. `update()` ändert diese Felder selbst nur über `transport.fail` und `transport.check`, die direkt den aktuellen Zustand schreiben.
- Test: Der Depot-Test mit der echten Zeile aus run33 prüft jetzt, dass genau eine Quittung kommt und die nächste Aktion gebaut und quittiert wird. Mit dem alten Code schlägt er fehl („confirmed 6 times“).

## 2. Weitere Fehler vom 8. Oktober

**Spielstand übertragen: „Write mit 3 Argumenten … Verbindung vom Remotehost geschlossen“ (beim Gastgeber).**
- Ursache: Der empfangende PC brach ab und schloss die Verbindung. Der Gastgeber sah nur den Abbruch, nicht den Grund.
- Lösung `85456d4`: Der Empfänger schickt seinen Grund zurück, und der Gastgeber zeigt ihn an. Netzwerkabbrüche werden bis zu fünfmal wiederholt.

**Spielstand übertragen: „Die Eigenschaft ‚Text‘ wurde für dieses Objekt nicht gefunden“.**
- Ursache: Das war der eigentliche Grund für den Abbruch oben. Die Empfangsdatei hieß im Skript `$out`, genau wie das Textfeld des Launchers. Die Fortschrittsanzeige suchte `$out` und fand die Datei statt des Textfelds.
- Lösung `5281b3e`: Die Variable heißt jetzt anders. Die Tests benutzen eine Fortschrittsanzeige wie die des Launchers, damit so etwas auffällt.

**„Weltabweichung erkannt (hcon,hedge)“.**
- Was das bedeutet: Jedes Spiel bildet alle 60 Sekunden Spielzeit Prüfsummen über Gebäude (`hcon`), Straßen und Gleise (`hedge`), Linien (`hline`) und Fahrzeuge (`hveh`) und vergleicht sie mit dem anderen. Bisher stand im Protokoll aber nur, dass die Prüfsummen verschieden sind.
- In run34 kam die Abweichung direkt nach dem hängenden Depot. Sehr wahrscheinlich folgte sie aus dem Fehler oben: Die Linie und alles danach wurden auf einem PC nicht nachgebaut.
- Neu in `edc2c7c`: Nach einer bestätigten Abweichung schickt jedes Spiel seine Liste der betroffenen Teile an das andere (`W1`-Zeilen). Der Empfänger schreibt ins Protokoll, was nur bei ihm und was nur beim anderen existiert, mit Datei, Position und Namen (`world diff … only in this game: …`). Beim nächsten Mal zeigt also schon das Protokoll des Gastgebers, welche Teile abweichen.

## 3. Frühere Fehler (6. und 7. Oktober)

| Was man sah | Ursache | Lösung |
|---|---|---|
| Der Lua-Mod kann nichts übers Netzwerk schicken. | TF3 sperrt im Mod `io` und `socket`. | Eigene `alut.dll` neben dem Spiel. Der Mod schreibt Zeilen ins Spielprotokoll, die DLL liest sie mit. Zurück geht es über eine Umgebungsvariable (`TF3MP_IN`). |
| Das Spiel fror beim Bau eines Bahnhofs etwa 60 s ein (Lauf 5). | Ein Debug-Ausdruck des ganzen Bauvorschlags schrieb rund 84.000 Zeilen ins Protokoll. | v6: höchstens 400 Zeilen je Ausdruck. Seit v15 ist auch der Ausdruck nach jedem Nachbau aus (Lauf 14: 23 s Stillstand je Bahnhof). |
| Es wurde dreimal derselbe erste Bau nachgebaut. | Mehrere Lua-Umgebungen (siehe oben): Variablen im Modul gehen verloren. | v8/v9: Alles Wichtige steht im gespeicherten Zustand. Der Nachbau läuft über ein Skript-Ereignis im „Simulation Thread“. |
| Spiel meldet Erfolg, gebaut wird nichts. | Angehängt wurde an Kopien der Listen, der Vorschlag blieb leer. Und „Erfolg“ meldet das Spiel auch für einen leeren Bau. | v10: Listen als Ganzes zuweisen und jede Ebene zurückschreiben. Erfolg an den Kosten erkennen. |
| Spiel-Assertion `!laneConfigs.empty()`. | Straßenstücke brauchen ihre Fahrspuren, das Spiel leitet sie nicht aus dem Straßentyp ab. | v11: Spuren mitschicken. Lauf 11 war der erste gelungene Nachbau. |
| Angeschlossene Straßen wurden nicht nachgebaut. | TF3 lässt nicht alle Knoten so durchsuchen wie TF2. | v14: Knoten über die Knotenliste des Straßensystems suchen, über die Position zuordnen. |
| Haltestellen und Signale abgelehnt. | Neue Objekte auf Straßen brauchen Nummern ab −400000000. | v16. |
| Depot-Abriss scheiterte (Zufahrt doppelt entfernt). | Die Zufahrt gehört zum Gebäude, das Spiel entfernt sie selbst. | v16/v17: Teile eines abgerissenen Gebäudes dem Spiel überlassen. |
| Bus im kopierten Depot abgelehnt. | Ladung muss als `api.type.LoadConfig` angegeben werden. | v19. |
| Eine nachgebaute Linie kam als Änderung zurück (Lauf 24). | Nach dem ersten Bus trägt das Spiel die Verkehrsarten der Linie nach, das zählte als Änderung. | v24: Linien ohne diese Verkehrsarten vergleichen. |
| Geldausgleich wirkte nicht. | In `update()` verbietet TF3 Befehle mit Rückruf. | v25: Korrekturen als Skript-Ereignis über `handleEvent`. |
| Bahnhofserweiterung: Bahnhof doppelt. | Ein erweiterter Bahnhof ersetzt den alten. | v26: alten und neuen Bahnhof paaren (`old2new`). |
| Ein unlesbares Fahrzeug blockierte alle weiteren. | Ein Fehler stoppte die ganze Abfrage. | v26: jeden Eintrag einzeln absichern. |
| Spiel startete im falschen Modus (Lauf 20). | Das Spiel wurde gestartet, bevor der Launcher die Einstellung gespeichert hatte. | Bedienregel: erst im Launcher installieren, dann das Spiel starten. |

Die Fehler aus run27 bis run29 (Übertragung, Wiederaufnahme, Bahnhofsersatz) hat ChatGPT gelöst. Sie stehen in `docs/phase4-reliable-transport.md`.

## 4. Was daraus folgt

- Daten zwischen `update()` und `handleEvent` nur über den gespeicherten Zustand austauschen, und beim Zurückschreiben nie eine alte Kopie über frischere Daten legen.
- Was ein Ereignis in einem Zug erledigen kann, auch in einem Zug erledigen, statt auf `update()` zu warten.
- Nichts darf an Spielzeit hängen, solange das Spiel pausiert sein kann.
- Vom Spiel gelesene Listen sind Kopien: ganz zuweisen, dann zurücklesen.
- Gebäude mit Zufahrt allein bauen und den Anschluss vom Spiel berechnen lassen (`refreshConstruction`).
- Jeder Fehler aus einem Spieltest wird ein Offline-Test mit der echten Protokollzeile, bevor die Lösung ins Paket kommt.

## Mehr Details

- `docs/phase1-bridge.md`: Lauf 5 bis 26, jeder Fehler mit Protokollauszug.
- `docs/phase3-sync.md`: Geld, Datum, Geschwindigkeit.
- `docs/phase5-session-world.md`: Zwei-PC-Sitzung, run31 bis run34, Weltvergleich.
- `docs/savegame-transfer.md`: Spielstandübertragung.

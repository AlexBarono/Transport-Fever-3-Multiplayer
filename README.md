# Transport Fever 3 Multiplayer

Experimenteller Community-Mod für zwei PCs: Straßen, Gleise, Haltestellen, Signale, Bahnhöfe, Depots, Abriss, Linien und Fahrzeuge werden zwischen zwei Spielen gespiegelt. Aktueller Stand: **Probe v44 / DLL v13**. v30 hat alle 21 aufgenommenen Aktionen im Spiel erfolgreich nachgebaut, v31 lief mit zwei PCs über VPN. v32 überträgt zusätzlich Depotfahrten, Umkehren und Kredite und macht den Neuabgleich zu einem Klick. v33 behebt den Kreditfehler aus Run 35 und ordnet gleichzeitige Aktionen beider PCs. v34 baut Bauten auf beiden PCs zum selben Spielzeitpunkt. v35 macht das auch für Zug umdrehen, Start/Stopp und Depotfahrten und gleicht Abweichungen im laufenden Spiel neu ab. v36 macht das auch für „Linie zuweisen“ und Verkaufen und überträgt den Spielstand schneller. v37 hält die Sitzung bei einer abgelehnten Aktion nicht mehr an, gleicht nur noch bei bleibenden Abweichungen im Aufbau neu ab und versucht es nach einem Fehlschlag von selbst wieder. **Beide PCs brauchen das v44-Paket (DLL v13).**

## Starten über euer gemeinsames VPN

1. Dasselbe Paket auf beide PCs kopieren und entpacken, beide mit dem VPN verbinden, TF3 beenden und `Start.bat` öffnen. Das portable Paket liegt unter `release/TF3-Multiplayer-v44-Windows.zip`.
2. Gastgeber: **Gastgeber** auswählen, die Adresse des VPN-Adapters wählen und **Adresse kopieren**. Den Mitspieler diese Adresse einfügen lassen. **Als Gastgeber starten** bietet beim ersten Start die Auswahl eines Spielstands aus dem aktuellen Steam-Spielstandordner an und wartet auf den Mitspieler.
3. Mitspieler: **Beitreten** wählen, die kopierte Adresse einfügen (z. B. `100.80.12.4:47800`) und **Beitreten und Spiel starten** klicken. Der Launcher holt den Spielstand, vergleicht Spielversion, Multiplayer-Paket und zusätzliche Mods und bereitet eine gemeinsame Sitzung vor. Unterschiedliche Dateien werden konkret gemeldet. Auch installierte inaktive Zusatzmods werden verglichen.
4. Nach erfolgreicher Übertragung installieren beide Launcher den Mod und starten TF3. Beide laden den angezeigten Spielstand pausiert. Die Verbindung wartet auf den vereinbarten Stand auf beiden PCs; danach gemeinsam fortsetzen. Die Welt muss im Spiel selbst geladen werden.
5. Der Launcher zeigt Verbindung, ausstehende Aktionen, Weltprüfung und Fehler an. **Details prüfen** öffnet die letzten Meldungen. Ein späterer Start kann die vorbereitete Sitzung verwenden, solange ihre Dateien unverändert sind und beide wieder denselben Ausgangsstand laden.

Standard: UDP 47800 für Spieldaten und TCP 47800 für den Spielstand. Die Windows-Firewall muss TF3 und die Spielstandübertragung über den verwendeten VPN-Adapter zulassen. Im gemeinsamen VPN wird die erreichbare VPN-IPv4 des Gastgebers verwendet; eine Router-Portfreigabe ist dafür nicht erforderlich. **Mod entfernen** stellt die gesicherte Original-DLL wieder her.

## Neu in v44

- **Fehler beim Betreten einer Welt behoben:** Die neue Fahrzeug-Erweiterung aus v43 rief in der Hauptoberfläche `log.info` auf. Diese Funktion gibt es dort nicht; dadurch brach der Aufbau der Spieloberfläche ab. Die Erweiterung verwendet jetzt geschützte Ausgabe ins Spielprotokoll. Auch ein Ausgabefehler darf weder das Laden noch einen zurückgehaltenen Fahrzeugbefehl unterbrechen.
- Beide PCs brauchen v44. TF3 nach dem Fehler schließen, das neue Paket entpacken und dessen `Start.bat` verwenden. Danach die Welt einmal manuell laden und Start/Stopp aus einem Fahrzeugfenster testen. Der Startfehler ist automatisch reproduziert und die Korrektur geprüft; ein erneuter echter Spielstart wurde dafür nicht ausgelöst. [Befund und Prüfungen](docs/v44-world-entry-fix.md).

## Neu in v43

- **Fehlgeschlagene Aktionen sichtbar:** Eine dauerhafte Meldung unter den Startknöpfen führt zu den Details. Dort stehen Bau-/Aktionsart, Name bzw. Ort soweit verfügbar, Fehlerursache und Kennung. Die Meldung unterscheidet eine Ablehnung vor dem Baubefehl von einer möglicherweise teilweise ausgeführten Aktion. Auch der andere PC bekommt die Diagnose. Die Sitzung läuft weiter; es erfolgt kein blindes Wiederholen eines bereits teilweise gebauten Vorhabens. Beim Laden eines neuen gemeinsamen Stands beginnt die Fehlerliste neu.
- **Weltvergleich:** Linien kommen aus dem Linienverzeichnis, Gleise/Straßen aus dem deduplizierten Netzverzeichnis. Fracht wird über einen begrenzten Scan aller Entities gelesen; native Frachtvektoren werden per Index statt mit `pairs` gelesen. Diese Wege umgehen TF3s Fehler „Cannot loop over this component type“. Unvollständige oder zu langsame Messungen bleiben ausdrücklich unbekannt. Auf großen Karten kann insbesondere der vollständige Frachtscan weiter das Messbudget überschreiten.
- **Normale Fahrzeugfenster anbinden:** Eine GUI-Erweiterung installiert die Fahrzeug-Hooks im Lua-Zustand der eigentlichen Spieloberfläche, in dem auch Fahrzeugfenster und Fahrzeugverwaltung laufen. Umkehren, Start/Stopp, Depotfahrt, Linienzuweisung und Verkauf werden vor dem Ausführen an den gemeinsamen Zeitplan übergeben. Auch eine Auswahl von mehr als 40 Fahrzeugbefehlen lässt keinen Befehl vorzeitig durch. Fahrzeugkauf und Fahrzeugkonfiguration reisen weiterhin über den bisherigen Nachbau.
- **Neuabgleich bleibt auf Wunsch.** Die gemeinsame Ausführung erfolgt weiter über eine Spielzeit-Schranke; das ist kein Nachweis für dauerhaft identische Simulation oder exakte Engine-Ticks. Falls die GUI-Hooks oder der Zeitplan nicht verfügbar sind, bleibt der bisherige Nachbau als Rückfall erhalten.
- Beide PCs brauchen v43. Echter Gegentest: Fahrzeugbefehle aus dem Fahrzeugfenster und der Fahrzeugverwaltung in beide Richtungen, Sammelzuweisung, Weltprüffelder und Fehleranzeige kontrollieren. Die neuen GUI-Einbindungen sind automatisch gegen getrennte Skriptumgebungen geprüft; ihre Ausführung in TF3 muss noch bestätigt werden. [Umsetzung und Prüfungen](docs/v43-sync-diagnose.md).

## Neu in v42

- **Bahnhof über Feldern/Forstflächen:** Automatische Änderungen der Feldmodule werden dem bestehenden Betrieb zugeordnet und zuerst mit TF3s eigenem Änderungsbefehl ausgeführt. Erst nach dessen Bestätigung folgt der Bahnhof. Die gefrorene Zufahrt des Betriebs wird nicht separat abgerissen; ein fehlgeschlagener Änderungsbefehl stoppt diese Bauaktion ohne unsicheren Ersatzversuch. Das behebt den fehlerhaften Nachbaupfad des v41-Absturzes, der echte Zwei-PC-Gegentest steht noch aus.
- **Eisenbahnbrücken und Tunnel übertragen:** Zusätzlich zu Gleisverlauf und Höhe werden der Bauwerkstyp und die Brücken-/Tunnelressource übertragen. Die Ressource wird auf dem anderen PC nach Namen gesucht. Eine fehlende Ressource wird gemeldet, statt einen falschen ebenerdigen Abschnitt zu bauen.
- Leere Konstruktionseinträge bei automatischem Feldabriss werden nicht mehr als Gebäude an Position 0,0 übertragen. Industriegebäude werden für spätere Feldänderungen mit erfasst.
- Beide PCs brauchen v42. Zum Gegentest einen normalen Spielstand von **vor dem Absturz** verwenden: Bahnhof über Feld/Forstfläche setzen und anschließend eine Eisenbahnbrücke einschließlich Zufahrten bauen, am anderen PC prüfen. [Absturzanalyse und Tests](docs/v41-crash-auswertung.md).
- Weltabweichungen bleiben erlaubt; ein gemeinsamer Neuabgleich startet weiterhin nur auf ausdrücklichen Wunsch.

## Neu in v41

- **Gleisknoten beim Nachbau erhalten:** Empfangene Bauaktionen und anschließende Knoteneinstellungen vereinfachen das Netz nicht nochmals. Im v40-Test fehlte nach einem Gleisumbau der Knoten für den späteren Depotanschluss; dieser wurde deshalb übersprungen. Die Änderung verhindert diese zusätzliche Vereinfachung. Der echte Zwei-PC-Gegentest steht noch aus.
- **Bauschritte nur einmal ausführen:** Ein verschachteltes Spielereignis darf denselben Schritt nicht nochmals starten. Im Test wurden Knoteneinstellungen einer Aktion bis zu sechsmal gesetzt.
- Der Bau-Abfangcode lädt seine Module vor den GUI-Ereignissen. Im v40-Test konnte er `build.lua` während des Klicks nicht laden; das gemeinsame Planen des Baus wurde damit umgangen. Empfangene Bauten werden jetzt einmal vollständig protokolliert, damit verbleibende Anschlussfehler reproduziert werden können.
- Weltabweichungen bleiben wie in v40 Hinweise. **Neu abgleichen** startet weiterhin nur auf ausdrücklichen Wunsch einen gemeinsamen Spielstandaustausch. Bereits fehlende Gleise werden durch die Installation nicht nachträglich gebaut.
- Test auf beiden PCs: denselben Ausgangsstand laden, Gleisabschnitte ändern, ein Zugdepot anschließen, einen Zug auf eine Linie schicken und anschließend auf beiden PCs weiterbauen. [Auswertung des v40-Tests](docs/v40-vpn-auswertung.md).

## Neu in v40

- **Weiterspielen trotz Weltabweichungen:** Fahrzeuge, Positionen, Fracht, Städte und auch Unterschiede bei Bauwerken, Gleisen, Linien und Krediten lösen keinen automatischen Neuabgleich mehr aus. Die Diagnose bleibt sichtbar; Bauaktionen werden weiter übertragen.
- Auch die vorsorglichen Speicherungen bei Weltabweichungen entfallen. Ein blockierter Aktionszeitplan oder eine abgelehnte Aktion bleibt als Fehler sichtbar, startet aber keinen ungefragten Spielstandaustausch.
- **Neu abgleichen nach Bedarf:** In einer laufenden vorbereiteten Sitzung startet der Knopf einen bewussten Neuabgleich im offenen Spiel. Der andere Launcher folgt dieser ausdrücklichen Anfrage. Beide Launcher müssen geöffnet sein; der Gastgeberstand wird auf beide PCs geladen. Manuelle Anfragen sind nicht auf sechs Versuche begrenzt. Nach Abbruch oder Fehlschlag startet kein neuer Austausch ohne erneuten Klick; das Nachholen eines bereits angeforderten, nur einseitig geladenen Stands bleibt erhalten.
- Beide PCs müssen v40 verwenden, damit kein älterer Launcher wegen der Unterschiede einen automatischen Neuabgleich anfordert.

## Neu in v39

- **Kalendertempo während des Spiels übertragen:** Änderungen des Gastgebers oder Mitspielers werden auf den anderen PC übernommen, auch während einer Spielpause. Das Anhalten des Kalenders wird ebenfalls übertragen. Pause und Spieltempo bleiben davon unabhängig.
- Bei unterschiedlichen Anfangswerten und gleichzeitigen Änderungen gilt der Wert des Gastgebers. Danach gewinnt die neuere Änderung. Die Synchronisierung verwendet dieselbe Tageslänge und denselben Befehl wie TF3s eigener Kalendereditor.
- Automatische Prüfungen decken beide Richtungen, angehaltenen Kalender, Pause, gleichzeitige Änderungen, verlorenen Lua-Zustand, Wiederholungen und ungültige/veraltete Daten ab. Der echte VPN-Test steht noch aus: auf einem PC Kalendertempo ändern, Übernahme am anderen PC prüfen; danach die Gegenrichtung und Kalenderstopp testen.

## Neu in v38

- Linien können Halte an weltgehörigen Industriegebäuden (zum Beispiel Bauernhöfen und Ölplattformen) beim Nachbau wiederfinden. Bisher konnte schon die erste Linienänderung den gesamten Ein-PC-Nachbau stoppen. Der Eigentumscheck für Änderungen und Abriss von Gebäuden bleibt bestehen.
- Ein lokaler Test startet bei einer abgelehnten Aktion keinen Zwei-PC-Neuabgleich mehr: Der simulierte Gastgeber besitzt keinen eigenen Spielstand zum Teilen. Den Fehler zeigt **Details prüfen**.
- Der konkrete fehlgeschlagene Linienbefehl aus dem Test vom 9. Oktober wird automatisch gegengeprüft. Der erneute Nachbau im echten Spiel ist noch zu testen.

## Neu in v37

- **Sitzung läuft weiter (Lauf 39)**: Eine Linie des Mitspielers wurde beim Gastgeber abgelehnt. Bisher hielt die DLL daraufhin die ganze Sitzung an („game rejected“), alle weiteren Aktionen blieben liegen. Jetzt überspringt der Mod eine abgelehnte Aktion, meldet sie als erledigt (`net skipped …` im Protokoll), und alles läuft weiter. Fehlt dadurch etwas, gleicht der Launcher neu ab.
- **Neuabgleich nur, wenn es nötig ist**: Nur Abweichungen bei Bauwerken, Straßen/Gleisen, Linien, Fahrzeugen oder Krediten lösen ihn aus, und nur, wenn dieselbe Abweichung bei 3 Weltprüfungen hintereinander und mindestens eine Minute lang bleibt. Bleibt der gemeinsame Zeitplan stehen (beide Spiele angehalten), gleicht der Launcher nach 30 Sekunden neu ab. Abweichungen bei Fahrzeugpositionen, Fracht und Städten zeigt der Launcher nur noch als Hinweis, das Spiel läuft weiter. **Neu abgleichen** bleibt für Hand.
- **Neuer Versuch von selbst**: Klappt ein Neuabgleich nicht, versucht der Launcher es noch einmal, solange der Grund bleibt (nach 30, 60, 120 Sekunden …, höchstens 6-mal pro Spielstart). Hat nur ein PC den gemeinsamen Stand geladen, lädt der andere ihn von selbst nach.
- **Kein Anhalten mehr beim Speichern**: TF3 hielt an („Save game rename failed“), weil der Mod `TF3MP-Neuabgleich` alle 3 Prüfungen neu speicherte, während der Launcher die Datei schickte. Jetzt speichert der Mod selten, der Launcher fragt einen frischen Stand an, macht sofort eine eigene Kopie `TF3MP-Sync-<Zeit>` (das Original ist dafür nur etwa eine Sekunde offen) und schickt nur diese. Die zwei neuesten Kopien bleiben liegen, ältere löscht er.
- **Übertragung**: vier Datenverbindungen über denselben TCP-Port, zusätzlich eine Steuerverbindung. Dateien werden in getrennte Bereiche aufgeteilt und vor dem Übernehmen vollständig mit SHA-256 geprüft. Warten auf Kompatibilitätsprüfung, Daten und Empfangsbestätigung blockiert die Oberfläche nicht; Abbrechen beendet auch wartende Netzwerkzugriffe. Ein Partner ohne Parallel-Unterstützung verwendet weiter eine Datenverbindung. `alut_launcher.log` nennt die reine Datenrate und die Zahl der Datenverbindungen. [Technik und Tests](docs/savegame-transfer.md).
- **Bekannte Grenze**: Die Zeitplanung für Umdrehen, Start/Stopp, Depot, „Linie zuweisen“ und Verkaufen aus v35/v36 greift bei TF3s eigenen Fahrzeugfenstern nicht. Die laufen in einem eigenen Lua-Zustand, den der Mod nicht erreicht. Daher kommen die kleinen Abweichungen bei Fahrzeugpositionen, die v37 jetzt hinnimmt.

## Neu in v36

- **Busse auf eine Linie schicken (Lauf 38)**: Fünf gekaufte Busse, die auf einmal auf Linie 1 geschickt wurden, fuhren auf dem anderen PC nacheinander los, je eine Sekunde später. Danach wichen Fahrzeugpositionen, Fahrzeuge und Städte ab. Jetzt laufen „Linie zuweisen“ und Verkaufen wie Umdrehen über den gemeinsamen Zeitplan. Alle Befehle eines Klicks (z. B. alle Busse eines Fensters) gehen zusammen und starten auf beiden PCs zum selben Spielzeitpunkt. Der andere PC wartet dafür, bis er den gekauften Bus selbst hat.
- **Spielstand-Übertragung**: lief nur mit etwa 1 MB/s, weil der Windows-Standardpuffer (64 KB) bei VPN-Laufzeit nicht reicht. Jetzt 8 MB Puffer und größere Blöcke. Die erreichte Geschwindigkeit steht im Launcher-Protokoll.
- **Launcher-Protokoll**: Der Launcher schreibt `alut_launcher.log` in den Spielordner (Start, Ende, Übertragungen, Neuabgleich, Abweichungen ohne Neuabgleich). Er muss während des Spiels offen bleiben, sonst gibt es keinen Neuabgleich.

## Neu in v35

- **Zug umdrehen (Lauf 37)**: Ein umgedrehter Zug wurde nicht übertragen, wenn er gerade am Bahnhof stand, und lief danach auf beiden PCs verschieden. Jetzt fängt der Mod die Befehle Umdrehen, Start/Stopp und „ins Depot“ ab, wenn sie geklickt werden, und beide Spiele führen sie zum selben Spielzeitpunkt aus (etwa 4 Sekunden nach dem Klick). Ohne gemeinsamen Zeitplan laufen sie sofort und reisen wie bisher.
- **Ladeeinstellung**: Güterwagen mit automatischer Ladung bekommen ihre Ladung vom Spiel. Das galt bisher als Änderung und tauschte auf dem anderen PC den Zug aus. Jetzt wird es nicht mehr übertragen.
- **Neuabgleich im laufenden Spiel**: Findet die Weltprüfung eine Abweichung oder lehnt ein Spiel eine Aktion ab, schickt der Launcher des Gastgebers den Stand, den sein Spiel gerade gespeichert hat, der Launcher des Mitspielers holt ihn, und beide Spiele laden ihn, ohne dass TF3 beendet wird (DLL v13: neue Runde, alte Aktionen verfallen). Danach verbinden sich beide wieder. Höchstens dreimal pro Spielstart, mit 3 Minuten Abstand; sonst bleibt **Neu abgleichen**.

## Neu in v34

- **Gleichzeitig ausführen (Bauten)**: Ein Bau (Straße, Gleis, Bahnhof, Haltestelle, Depot, Abriss mit dem Bauwerkzeug) wird nicht mehr sofort ausgeführt. Das Spiel meldet kurz „TF3MP: wird gleich auf beiden PCs gleichzeitig gebaut“, der Mod schickt den Bau an den gemeinsamen Zeitplan, beide Spiele halten am vereinbarten Spielzeitpunkt kurz an, bauen ihn dort und laufen weiter. Kommt kein gemeinsamer Zeitpunkt zustande (Mitspieler fehlt, Zeitplan gestört, 30 Sekunden ohne Plan) oder führt TF3 den Bau trotz Ablehnung aus, schaltet der Mod das Anhalten ab und Bauten reisen wie in v33.
- **Warum v33 nichts angehalten hat (Run 36)**: Die Bau-Ereignisse kommen nur bei Skripten an, die sie abonnieren. v34 abonniert sie. Außerdem sind `api.cmd.sendCommand` und die Befehlsbauer in TF3 aufrufbare Tabellen, keine Funktionen.
- **Zeitplan**: Der gemeinsame Zeitpunkt ist jetzt eine Schranke. Ein Spiel, das ihn schon überschritten hat, hält sofort an und baut nach, statt den Plan abzubrechen.
- **Launcher**: Beim Start bleiben keine schwarzen Fenster mehr offen, und das normale X schließt den Launcher immer.

## Neu in v33

- **Kredit (Run 35)**: v32 hat auch die automatischen Monatsraten als neue Kreditänderung geschickt. Das andere Spiel lehnte die Buchung ab und die Übertragung blieb stehen („peer rejected“). Jetzt reist nur das Aufnehmen oder Zurückzahlen selbst, und zwar als dasselbe Ereignis, das die Kreditseite des Spiels schickt. Die Raten bucht jedes Spiel selbst.
- **Gleichzeitige Aktionen**: Die DLL v12 lässt immer nur eine fremde Aktion zur Zeit nachbauen, abwechselnd von beiden PCs. Bauen beide gleichzeitig an verschiedenen Stellen, kommen sich die Nachbauten nicht mehr in die Quere. Beide PCs brauchen dafür die DLL v12.
- **Neu abgleichen**: Das Spiel des Gastgebers speichert den Stand `TF3MP-Neuabgleich` jetzt wirklich selbst (Run 35 erkannte die Speicherfunktion nicht). Reagiert TF3 nicht auf Schließen, beendet der Launcher den Prozess nach 5 Sekunden.
- **Spielstand-Übertragung**: größere Lesepuffer, seltenere Fortschrittsanzeige, Anzeige von Geschwindigkeit und Restzeit; Abbrechen bleibt möglich.
- **Schiffe und Flugzeuge**: Häfen und Flughäfen werden über die Kennungen ihrer Stationen und Terminals zugeordnet, Wasser- und Luftlinien mit ihren Wegpunkten. Im Spiel noch nicht getestet.
- **Genauerer Weltvergleich**: Neben Bauwerken, Straßen/Gleisen, Linien und Fahrzeugen auch Fahrzeugpositionen, Fracht und Städte. Erfasst wird auf einem Spieltakt mit Zeitbudget; was nicht ins Budget passt, bleibt „unbekannt“ und wird im Protokoll als `world scan` gezeigt.
- **Gleichzeitig ausführen (Vorarbeit)**: Der gemeinsame Zeitplan (`timeline.lua`) ist fertig, braucht aber Aktionen, die vor dem Ausführen angehalten werden. Die Spielskripte von TF3 zeigen dafür die Ereignisse `builder.proposalPrepareForApply`/`builder.proposalApply` der Bauwerkzeuge. v33 protokolliert sie und prüft in **Allein testen** einmal, ob ein Bau angehalten und vom Mod später ausgeführt werden kann.

## Neu in v32

- **Ins Depot schicken** (auch „bei Ankunft verkaufen“), **Umkehren** während der Fahrt und das **Weiterfahren aus dem Depot** werden auf den anderen PC übertragen. Ein Fahrzeug, das „bei Ankunft verkauft“ wird, verkauft jedes Spiel selbst, sobald es im Depot ankommt.
- **Kredit**: Nimmt einer von euch einen Kredit auf oder zahlt ihn zurück, bucht das andere Spiel denselben Betrag. Bisher hat der Abgleich den Kredit des Mitspielers wieder zurückgesetzt.
- **Neu abgleichen mit einem Klick**: Findet der Weltvergleich eine Abweichung, speichert das Spiel des Gastgebers selbst den Stand `TF3MP-Neuabgleich`. Beide klicken danach im Launcher **Neu abgleichen**. Der Launcher des Gastgebers nimmt diesen Stand (oder bittet um ein neues Speichern), beendet TF3 und schickt ihn. Der Launcher des Mitspielers beendet TF3, wartet auf den Gastgeber und holt den Stand. Danach starten beide TF3 neu und laden den genannten Spielstand pausiert.
- „Automatisch ersetzen“ gibt es in der Spiel-Schnittstelle nicht. Manuelles Ersetzen eines Fahrzeugs wurde schon vorher übertragen.

## Neu in v31

- Gemeinsame Sitzungskennung und SHA-256-Prüfung von TF3, Multiplayer-Paket, zusätzlichen Moddateien und Ausgangsspielstand. Veränderte Dateien werden vor dem Start erneut erkannt.
- Die DLL prüft die Sitzung auf beiden PCs und wartet auf den richtigen geladenen Spielstand. Ein erneutes Laden oder Partnerneustart verlangt eine neue gemeinsame Vorbereitung.
- Vier Weltprüfsummen vergleichen Gebäude samt Modulen, Straßen/Gleise, Linien und Fahrzeuge. Gleiche Anzahlen mit anderem Inhalt werden erkannt. Anhaltende Unterschiede erscheinen nach zwei aufeinanderfolgenden Prüfpunkten; fehlende Lesezugriffe gelten als unbekannt.
- **Neu abgleichen** führt durch einen neuen gemeinsamen Spielstand: Gastgeber speichert, beide beenden TF3, teilen/holen den Stand und starten eine neue Sitzung. Speichern und Laden erfolgen weiterhin im Spiel.

Aktuelle Übergabe, Grenzen und VPN-Testablauf: [docs/phase5-session-world.md](docs/phase5-session-world.md).

## Korrekturen in v30

Run29 hat Abriss, Linienänderung, Gleise, beide Bahnhöfe, Depot und Signal erfolgreich nachgespielt (11 Aktionen). Die erste Bahnhofserweiterung scheiterte danach mit „Bau nicht möglich“; spätere Aktionen blieben deshalb stehen.

- Reine Erweiterungen einer bestehenden Konstruktion verwenden jetzt denselben Ersatzvorschlag-Generator wie die originale Spieloberfläche: `createProposalReplaceConstruction`. Damit verwaltet die Engine die vorhandenen Anschlussknoten und die vollständige Moduländerung.
- Die vom Ersatzvorschlag erzeugten Konfigurationen werden anschließend geprüft. Es wird kein zweiter Bau oder Überschreiben der Anschlusskonfigurationen ausgelöst.
- Abgelehnte Ersatzvorschläge bleiben ein sichtbarer Fehler. Run30 bestätigt den anschließenden Gleisbau und alle 21 Aktionen; die drei Bahnhofserweiterungen wurden mit erhaltenem Anschluss ausgeführt.

Die letzte Aufnahme kann mit `Test-letzte-Aufnahme.bat` wiederholt werden. TF3 vollständig beenden, den Starter öffnen und **Test starten** wählen. Im Spiel den ursprünglichen Stand **Det** vor den Änderungen laden und die Zeit laufen lassen. Danach im Launcher **Am selben Ort nachbauen** klicken. Die 21 gespeicherten Aktionen werden erneut ausgeführt; eine neue Bauaufnahme ist dafür nicht nötig. Der Launcher prüft den aktuell geladenen Spielstand anhand des neuen Spielprotokolls.

## Korrekturen in v29

Run28 hat 26 Aktionen aufgezeichnet. Bereits der erste Abriss wurde ausgeführt, aber von unserer Erfolgskontrolle fälschlich abgelehnt. Folgeaktionen blieben dadurch stehen.

- Abrissprüfung unterstützt die aufrufbaren API-Tabellen von TF3; Fehlermeldungen nennen jetzt die betroffene Entity und den Prüfungsfehler.
- Bahnhofserweiterungen behalten ihren Eintrag im Konstruktionscache, auch wenn die Engine dieselbe ID erneut verwendet. Dadurch werden weitere Erweiterungen vollständig aufgezeichnet.
- Linien behalten gelöschte Halte als ungültigen Platzhalter am bisherigen Index. Fehlende gültige Stationen bleiben ein Fehler.

Für den damaligen v29-Spieltest war eine **frische Aufnahme** nötig, da run28 bei mehreren Bahnhofserweiterungen die zu ersetzende Konstruktion nicht vollständig aufgezeichnet hat. Die inzwischen gesicherte run29-Aufnahme enthält diese Angaben und kann für v30 wiederverwendet werden.

## Korrekturen in v28

Run27 hat alle 20 Aktionen aufgezeichnet. Beim Nachspielen scheiterte die Zugzuordnung zur Linie (Aktion 10); Bahnhofserweiterung, zusätzliche Gleise, Abriss und Umbenennung wurden deshalb noch nicht ausgeführt.

- Fahrzeugzuordnungen übertragen den tatsächlichen Zielhalt statt immer Halt 0. Alte Aufnahmen enthalten diesen Wert nicht; für den erneuten Test eine frische Aufnahme erstellen.
- Ein erfolgreicher Bau-Retry gibt Folgeaktionen frei. Reiner Abriss wird anhand der tatsächlich verschwundenen Objekte bestätigt, auch bei null Kosten oder einer Erstattung.
- Geld- und Kreditkorrekturen setzen den von der Engine verlangten Buchungszeitwert `-1`.
- Der simulierte Gastgeber protokolliert abgelehnte Aktionen mit ihrer Position und beendet sich geordnet, damit er für den nächsten Versuch neu gestartet werden kann.

## Änderungen in v27 / v10

- GUI-Speicher ohne verbotene globale Variablen; sprachunabhängige UTF-8-Kodierung.
- Simulierter Gastgeber wird am richtigen UDP-Port auf Bereitschaft geprüft und im Hintergrund gestartet.
- Nachrichten bis **256 KiB**, zerlegt in kleine UDP-Pakete; auch die Lua/DLL-Brücke übergibt große Aktionen in begrenzten Stücken. Knotenkonfigurationen werden bei Größenüberschreitung nicht still weggelassen.
- Empfang und Ausführung sind getrennt: Erst ein positives Spielergebnis gibt die nächste Aktion frei. Mehrstufige Bauaktionen warten auf ihre vorherigen Befehle und prüfen anschließend Knotenkonfigurationen und Anschlüsse.
- Geordnete Wiederaufnahme nach Netzwerkunterbrechungen innerhalb derselben Spielprozesse. Volle Warteschlangen lagern weitere Aufnahmen auf den Datenträger aus.
- Bei abgelehnten Aktionen, Partner-Neustart oder Neuladen mit offenen Aktionen wird ein Abgleich verlangt. Beide Spiele dann beenden und vom gemeinsamen Spielstand neu starten. Automatischer Wiederabgleich nach Prozessneustart ist noch offen.

Frühere Transport-Korrekturen: [docs/phase4-reliable-transport.md](docs/phase4-reliable-transport.md). Frühere Spielnachweise: [docs/phase1-bridge.md](docs/phase1-bridge.md). Der übergeordnete Forschungsplan steht in [docs/plan.md](docs/plan.md).

## Tests auf einem PC

Im **Testlabor** bleiben Allein-Test (100 m daneben), Gleiche-Stelle-Test nach Neuladen und simulierter Gastgeber verfügbar. Diese Tests ersetzen den späteren gemeinsamen VPN-Spieltest nicht.

Beim simulierten Gastgeber zeigt **Details prüfen** jetzt bestätigte, offene und nicht prüfbare Testteile, einschließlich fehlender Weltmessungen. Aufgezeichnete Aktionen gelten erst nach bestätigtem Nachbau als geprüft. Frühere Protokolle bleiben beim Neustart erhalten; ein hängender Nachbau endet nach 180 Sekunden ohne Fortschritt. Siehe [Testlabor-Auswertung und Ablauf](docs/testlabor-auswertung.md).

Offline-Tests mit Lua oder Python/lupa:

```powershell
python tools/run_lua.py tests/run_tests.lua
python tools/run_lua.py tests/run_actions.lua
python tools/run_lua.py tests/run_sync.lua
python tools/run_lua.py tests/run_transport.lua
python tools/run_lua.py tests/run_fingerprint.lua
python tests/run_fake_partner.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_save_transfer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_session.ps1
```

Native DLL und Netzwerktests bauen (Visual Studio C++ x64):

```powershell
cmd /c native\alut_proxy\build.bat
cmd /c tests\build_net_tests.bat
python tests/run_net.py
```

Der Launcher enthält die fertig gebaute DLL in `launcher/bin/alut.dll`; zum Einrichten ist Visual Studio nicht nötig.

Dieses Projekt ist nicht mit Urban Games oder Paradox Interactive verbunden.

# v43: Fehleranzeige, Weltprüfung und Fahrzeugfenster

## Fehlgeschlagene Aktionen

Ein empfangener Bau erhält vor dem Nachbau eine Beschreibung aus dem tatsächlichen Baupaket: Gebäude-/Aktionsart, Name und Kartenkoordinaten soweit vorhanden. Linien-, Fahrzeug- und Kreditaktionen erhalten verständliche Bezeichnungen. Bei einem Fehler protokolliert der Mod zusätzlich zur bisherigen Ausführungsquittung eine begrenzte, hexkodierte `I1`-Diagnose. Sie enthält Kennung, Beschreibung, technischen Grund und die Information, ob bereits ein Spielbefehl gesendet wurde. Ein gesendeter Befehl beweist noch keine Veränderung, deshalb lautet die Anzeige ausdrücklich „möglicherweise teilweise ausgeführt“.

In normalen Zwei-PC-Sitzungen wird die Diagnose zuverlässig an den anderen PC übertragen. Ihr Empfang baut nichts und erzeugt keine weitere Diagnose als Antwort. Die bestehende Überspringen-Quittung bleibt erhalten: Eine abgelehnte Aktion blockiert spätere Bauaktionen nicht. Weder Diagnose noch Weltunterschied starten einen automatischen Neuabgleich.

Der Launcher liest das Spielprotokoll schrittweise (höchstens 256 KiB pro Aufruf), statt es bei jedem Tick vollständig einzulesen. Er behält die letzten 30 Fehler, zeigt in den Details die letzten zehn und nennt zusätzlich die Gesamtzahl seit dem Laden. Unvollständige Zeilen werden erst nach ihrem Abschluss ausgewertet; sehr lange Bau-/Dumpzeilen werden verworfen. Spielneustart, Dateikürzung und ein neues Laden setzen die Liste zurück. Die Anzeige unter den Startknöpfen bleibt bestehen und öffnet beim Anklicken die Details.

Die Diagnose beschreibt fehlgeschlagenen Nachbau. Sie ist keine Garantie, dass ein teilweise ausgeführter Bau automatisch zurückgenommen wurde. Ein erneutes Ausführen könnte Bauwerke doppelt setzen; deshalb erfolgt keine automatische Wiederholung. Ein ausdrücklich angeforderter Neuabgleich übernimmt wie bisher den Gastgeberstand.

## Weltvergleich

TF3s generische Komponenten-Auflistung scheitert im echten Spiel für `LINE`, `BASE_EDGE` und `SIM_CARGO` mit „Cannot loop over this component type“. Die Weltprüfung verwendet jetzt:

- `lineSystem.getLines()` für Linien;
- `streetSystem.getNode2SegmentMap()` für Straßen und Gleise, mit deduplizierten Kanten;
- `engine.forEachEntity()` mit gezieltem `SIM_CARGO`-Lesezugriff für den vollständigen Frachtsatz.

Die Indexeinträge werden auf Eigentum geprüft, bevor Spielerobjekte verglichen werden. Native Fahrzeug-Frachtvektoren werden per Länge/Index gelesen; ein unzulässiger Zugriff auf Index null wird abgefangen. Tabellen mit expliziten nullbasierten Schlüsseln bleiben unterstützt.

Zeit-, Aufruf-, Datensatz- und Hashbudgets bleiben bestehen. Gerade der vollständige Frachtscan kann auf großen Karten das Budget überschreiten: Dann ist `hcargo` weiterhin unbekannt, mit protokolliertem Grund. Es wird niemals nur der Anfang der Liste als vollständiger Gleichstand veröffentlicht. Unverändert stammen alle Daten eines Vergleichs aus demselben Spieltakt; nur das Hashen läuft über spätere Updates verteilt. Laufzeitmessungen auf großen echten Karten stehen noch aus.

## Gemeinsame Fahrzeugbefehle aus den normalen Fenstern

Die bisherigen Hooks liefen in der Game-Script-GUI. TF3s Fahrzeugfenster und Fahrzeugverwaltung laufen im Haupt-GUI-Zustand und erreichten diese Hooks nicht.

Die neue Ressource `vehicle_ui.res.lua` registriert ein Plugin für TF3s `::ModEntryPointExtension`. `vehicle_ui.script.lua` lädt seine Abhängigkeiten ausdrücklich aus `mp_probe_1::/` und installiert dieselben Hooks im Haupt-GUI-Zustand. Der gemeinsame Kern `vehicle_hooks.lua` wird auch vom bisherigen Game-Script-Code verwendet. Er fängt Umkehren, Start/Stopp, Depotfahrt, Linienzuweisung und Verkauf vor dem Senden ab, bündelt die Befehle eines Frames und übergibt sie über `mp_probe_vehicle` an den vorhandenen gemeinsamen Zeitplan. Bei mehr als 40 Befehlen werden mehrere geplante Pakete gebildet; der 41. Befehl wird nicht mehr sofort ausgeführt.

Die Originalbefehle werden beim normalen geplanten Ablauf nicht zusätzlich gesendet. Nicht betroffene Befehle bleiben durchlässig. Wiederholtes Rendern installiert keine weiteren Wrapper. Die vorhandenen GUI-Callbacks werden weiterhin sofort freigegeben, damit TF3s Fenster nicht auf einen im anderen Skriptzustand ausgeführten Befehl warten; die tatsächliche Ausführung kontrolliert separat die Transportquittung. Falls das Erstellen/Senden des Skriptereignisses scheitert, bleiben der protokollierte bisherige Rückfall und Nachbau erhalten.

Das ersetzt keinen Determinismusnachweis. Die Schranke plant eine gemeinsame Spielzeit, die Pause selbst ist weiterhin nicht an einen exakten nativen Engine-Tick gebunden. Kauf, Fahrzeugkonfiguration und automatische Ersetzung sind nicht Bestandteil der fünf neuen GUI-Befehlsarten.

## Nachweise und echter Gegentest

358 Lua-Prüfungen bestanden jeweils unter Lua 5.2 und 5.4, dazu 49 Launcher-/Protokoll-, 17 Diagnoseanzeigen-, 34 Neuabgleich- und zehn Sitzungsprüfungen unter Windows PowerShell 5.1. Neue Regressionen stellen die echten Komponenten-Auflistungsfehler nach, prüfen native Frachtvektoren, das Zeit-/Aufrufbudget, Diagnoseversand ohne Echo, Teilfehler, Logrotation und Sammelbefehle für 85 Fahrzeuge. Das tatsächliche Haupt-GUI-Modul wird in einer getrennten Skriptumgebung ausgeführt; Ressourcenregistrierung und Paketzuordnung werden ebenfalls geprüft.

Beide PCs benötigen v43. Nach Installation denselben Ausgangsstand laden oder ausdrücklich neu abgleichen:

1. Aus dem normalen Fahrzeugfenster umkehren, stoppen/fortsetzen und ins Depot schicken. Danach in der Fahrzeugverwaltung mehrere Fahrzeuge einer Linie zuweisen und verkaufen. Beide Baurichtungen prüfen. Im Protokoll sollen `vehicle UI: vehicle hooks: 6 of 6 installed`, `vehicle commands handed over` und anschließend `timeline execute` erscheinen. Das Installationsprotokoll allein beweist noch keinen abgefangenen Klick.
2. Nach einer Weltprüfung `world scan` und die Prüffelder kontrollieren. `hedge`, `hline` und bei ausreichendem Budget `hcargo` sollen lesbar sein. Überschrittene Grenzen müssen unbekannt bleiben; keine automatische Neuladung.
3. Falls eine Aktion abgelehnt wird: Hinweis und Details auf beiden PCs vergleichen, betroffenen Bau auf der Karte prüfen und danach weiterbauen. Kennung/Beschreibung/Ursache sollen übereinstimmen, der Empfangs-PC ist entsprechend gekennzeichnet. Dafür keine absichtlich gefährliche Bauaktion in einem wichtigen Spielstand provozieren.

Ein echter Zwei-PC-Nachweis der neuen Haupt-GUI-Hooks und Messwerte für große Karten liegen noch nicht vor. TF3 wurde für diese Änderung weder gestartet noch eine bestehende Installation überschrieben.

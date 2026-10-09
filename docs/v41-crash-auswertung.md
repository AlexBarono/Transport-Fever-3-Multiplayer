# Bahnhof über Forstfläche: Absturz vom 9. Oktober 2026

## Befund aus dem lokalen Spielprotokoll

TF3 stürzte um 14:57 Uhr Ortszeit beim empfangenen Bau `34244-4929562.528` ab. Der Screenshot nennt Entity 115277 und Component Type Index 3. Das Spielprotokoll ergänzt: Die fehlende Komponente war `TransportNetwork`; an der Entity waren noch `BaseEdge` und `BaseEdgeStreet` vorhanden. Unmittelbar davor scheiterte die Erstellung des Bauvorschlags in `StreetShapeFactory::PrepareTransitions` mit `!cc.empty()`.

Das vollständig protokollierte Paket enthielt:

- den neuen Bahnhof Avon Station Süd;
- eine aktualisierte Konstruktion des bestehenden Forstbetriebs Rose Hill Holzfällerlager mit reduzierter Liste von Feldmodulen;
- dessen entfernte Zufahrt und einen entfernten Anschlussknoten;
- **keine** alte Konstruktion für den Forstbetrieb. Der bisherige Erfassungs-Cache enthielt nur Spielergebäude, Forst-/Landwirtschaftsbetriebe gehören dem Spiel.

Der bisherige Nachbau ließ die neue Zufahrt der Konstruktion weg und startete mit dem separaten Entfernen der alten Zufahrt. Dabei blieb die bestehende Industriekonstruktion erhalten. Schon das Erzeugen dieses Straßenvorschlags brachte das Verkehrsnetz in den beschädigten Zustand. Das Abfangen der Lua-Ausnahme und Überspringen der Aktion konnte den folgenden nativen Absturz nicht verhindern.

Ein weiterer empfangener Bau, `34244-4929562.525`, war ein leerer Konstruktionseintrag (`c;;;…;{}`). TF3 verwendet solche Einträge bei bestimmten automatischen Flächenänderungen. Er wurde als ungültiges Paket übersprungen und darf nicht als neues Gebäude übertragen werden.

Die Originalprotokolle sind lokal unter `release/diagnose-v41-crash/` gesichert. Der relevante, vollständige Bau liegt als Regressionseingabe unter `tests/fixtures/v41-station-over-forest.b5`.

## Änderungen in v42

1. Der Erfassungs-Cache merkt neben Spielergebäuden auch Industriekonstruktionen. Dadurch reisen deren automatische Änderungen zusammen mit der Identität der alten Konstruktion.
2. Bestehende Industriegebäude werden anhand von Datei und Position zugeordnet. Ihre Feldmodule werden mit `api.engine.util.proposal.createProposalReplaceConstruction` geändert. Der vollständige native Vorschlag übernimmt die Zufahrt und deren Verbindungen. Auch das tatsächlich abgestürzte v41-Paket ohne alte Konstruktion wird so richtig zugeordnet.
3. Der Bahnhof folgt erst nach bestätigtem Abschluss der Feldänderung. Eine Ablehnung startet keinen unsicheren SimpleProposal-Ersatz. Bei verzögerten Antworten bleibt die Aktion offen; verschachtelte Ereignisse können weder den Schritt wiederholen noch die Aktion vorzeitig bestätigen.
4. Konstruktionseigene Kanten dürfen generell nicht einzeln entfernt werden, solange ihre zugehörige Konstruktion nicht ebenfalls entfernt oder ersetzt wird. Diese Prüfung geschieht vor dem Aufruf der nativen Bauvorschlagsfunktion.
5. Leere Konstruktionseinträge werden ausgelassen; die eigentlichen Entfernungen aus `toRemove` bleiben erhalten.

Die Feldänderung und der anschließende Bahnhofsbau sind zwei bestätigte Schritte. Sollte erst der Bahnhofsbau abgelehnt werden, kann die Feldänderung bereits ausgeführt sein. Die Aktion wird dann als Fehler gemeldet; es gibt keinen ungeprüften Rückbau.

## Brücken und Tunnel

Die bisherige Übertragung enthielt `SegmentAndEntity.type` (Straße oder Schiene) und `BaseEdge.typeIndex`, aber nicht `BaseEdge.type` (normal, Brücke, Tunnel). Ein Gleis auf Brückenhöhe konnte damit als normales Gleis rekonstruiert werden. Im aktuellen Protokoll findet sich kein empfangener Bau mit gültigem Brücken-/Tunnelindex; deshalb gibt es daraus keinen bestätigten Brückentest.

v42 überträgt für Brücken und Tunnel zusätzlich einen B5-Token `b<segment>;BRIDGE|TUNNEL;<resource>`. Er enthält den Ressourcennamen statt einer nur lokal gültigen Repository-Nummer. Der Empfänger sucht die Ressource in `bridgeTypeRep` bzw. `tunnelTypeRep`, setzt beide BaseEdge-Felder und prüft sie im fertigen Vorschlag. Eine fehlende Ressource führt zur Ablehnung vor dem Senden des Baubefehls. Die Paket-Kompatibilitätsprüfung verlangt v42 auf beiden PCs.

## Prüfungen und echter Gegentest

Die automatischen Regressionen verwenden das tatsächliche Absturzpaket und prüfen die Zuordnung der Industrie, das Entfernen ihrer losen Geometrie aus dem Nachbau, den nativen Änderungsbefehl, verzögerte Antworten, abgelehnte Befehle und die anschließende Reihenfolge des Bahnhofbaus. Brücken und Tunnel werden mit unterschiedlichen Ressourcennummern auf Sender und Empfänger sowie einer fehlenden Ressource geprüft. Verlauf, Höhe und Steigung bleiben dabei erhalten.

Bestanden: 346 Lua-Prüfungen jeweils unter Lua 5.2 und 5.4 sowie 49 Launcher-/Protokoll- und 34 Neuabgleich-Prüfungen unter Windows PowerShell 5.1.

Diese Prüfungen ersetzen keinen echten Zwei-PC-Test in TF3. Auf beiden PCs v42 installieren und einen normalen Spielstand von vor dem Absturz verwenden. Der beim Absturz gespeicherte Stand kann bereits das beschädigte Verkehrsnetz enthalten.

1. Mitspieler baut einen Bahnhof über Feld-/Forstmodulen. Beim Gastgeber prüfen: Bahnhof sichtbar, betroffene Feldmodule entfernt, Betrieb und Zufahrt weiterhin gültig, weitere Bauaktion möglich.
2. Mitspieler baut eine Eisenbahnbrücke mit Auf- und Abfahrt. Beim Gastgeber prüfen: Brückentyp, Höhe, Pfeiler, durchgängige Gleise und befahrbarer Weg.
3. Brückenabschnitt ändern oder abreißen und erneut bauen. Danach die Gegenrichtung Gastgeber → Mitspieler und einen Tunnel prüfen.
4. Weltabweichungen dürfen weiter angezeigt werden, ohne einen ungefragten Neuabgleich auszulösen.

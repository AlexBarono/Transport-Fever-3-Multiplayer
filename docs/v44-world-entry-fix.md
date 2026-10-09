# v44: Fehler beim Betreten einer Welt

## Ursache

Das lokale TF3-Spielprotokoll vom 9. Oktober 2026 bestätigt beim Aufbau von `TF3MPVehicleHooks` den Fehler `attempt to call field 'info' (a nil value)`. Der Aufruf stammt aus Zeile 13 von `vehicle_ui.script.lua`, während `watch_vehicles` die installierten Fahrzeug-Hooks protokolliert. TF3s Hauptoberfläche stellt `log.info` nicht bereit. Die mitgelieferten GUI-Skripte in `base/content/gui.zip` verwenden unter anderem `log.verbose`, `log.warning`, `log.error` und `debugPrint`.

Die bisherigen isolierten GUI-Tests hatten fälschlich `log.info` bereitgestellt. Dadurch prüften sie die Fahrzeugbefehle, verdeckten aber den tatsächlichen Fehler beim Weltstart. Mit einer GUI-Testumgebung ohne diese Funktion scheiterten vor der Korrektur fünf Tests mit genau dieser Fehlermeldung.

## Korrektur

Die Fahrzeug-Erweiterung protokolliert mit `debugPrint` ins Spielprotokoll, wie die übrigen Mod-Skripte. Wenn die Ausgabe fehlschlägt oder die Funktion fehlt, folgt ein geschützter `print`-Versuch. Beide Ausgaben sind mit `pcall` geschützt: Ein Diagnosefehler darf weder die GUI-Rezeptfunktion abbrechen noch einen zurückgehaltenen Fahrzeugbefehl vor der Übergabe an den gemeinsamen Zeitplan unterbrechen. Es werden keine sonstigen Fehler der Fahrzeug-Erweiterung versteckt.

Paket, Mod und Launcher tragen Probe v44; die DLL bleibt v13. Fehleranzeige, Weltvergleich und manueller Neuabgleich behalten das Verhalten aus v43. Es wird kein automatischer Neuladeversuch ausgelöst.

## Prüfung

Die tatsächliche GUI-Einstiegsdatei wird ohne `log.info` ausgeführt. Die Tests prüfen die Initialisierung, die Meldung über sechs installierte Hooks, das Verhalten bei fehlendem `debugPrint` und bei Ausfall beider Ausgabefunktionen. Auch dann bleibt Start/Stopp zurückgehalten, wird einmal als Skriptereignis übergeben und löst seinen GUI-Callback genau einmal aus. Die bestehenden Prüfungen für alle fünf Fahrzeugbefehle, 85 Sammelbefehle, erneutes Rendern, Einzelspieler, einen gestörten Zeitplan und den Ressourcenexport bleiben erhalten.

Bestanden: sechs Haupt-GUI-, elf Hold- und 13 Zeitplan-Prüfungen jeweils unter Lua 5.2 und 5.4 sowie 49 Launcher-/Protokoll-Prüfungen unter Windows PowerShell 5.1. Alle Lua-Dateien des Mods lassen sich unter beiden Lua-Versionen übersetzen. Das portable Paket wird mit `tools/package.ps1` erstellt; dabei werden Versionsangaben, Ressourcenmanifest und sämtliche Archivdateien gegen ihre Quelldateien geprüft.

Der echte Spielstart wurde nicht automatisch wiederholt. Gegentest: Auf beiden PCs v44 entpacken, TF3 schließen und über die neue `Start.bat` starten. Die Welt manuell laden; danach Start/Stopp, Umkehren und Depotfahrt aus dem Fahrzeugfenster in beide Richtungen prüfen. Ein echter Zwei-PC-Nachweis der Haupt-GUI-Hooks steht weiterhin aus.

# v66: Updates direkt im Launcher

Stand: **22. Oktober 2026**, **Probe v66 / Bridge v16**. Die Korrekturen aus [v65](v65-tempo-ipv6-einladung.md) sind enthalten.

## Benutzung

Das v66-Paket einmal entpacken und dessen `Start.bat` öffnen. Ältere Launcher besitzen noch keinen Updateknopf.

1. Das Spiel und die gemeinsame Sitzung beenden.
2. Links **Auf Updates prüfen** klicken.
3. Wenn eine neuere Version angezeigt wird, **Update installieren** klicken. Download und Prüfung laufen im Hintergrund; der Launcher bleibt bedienbar.
4. Nach erfolgreicher Prüfung schließt der Launcher, sichert seinen bisherigen Paketordner und startet mit der neuen Version wieder am selben Pfad.

Beide PCs aktualisieren. Beim nächsten gemeinsamen Spielstart übernimmt der normale Launcherablauf die aktualisierte Mod und Bridge in die Spielinstallation.

Zusätzlich gibt es **Update aus ZIP**: Ein neueres Windows-Paket auswählen, prüfen lassen und anschließend **Update installieren** klicken. Dafür sind Internet, Git und ein GitHub-Konto nicht erforderlich.

Die Interneteinladung wird unter `%LOCALAPPDATA%\TF3MP\Internet` gespeichert und bleibt beim Paketwechsel erhalten. Die vorherige Launcherfassung liegt neben dem Paketordner unter `<Paketordner>.previous-v<Version>-<Kennung>`. Zusätzliche persönliche Dateien aus dem bisherigen Paketordner bleiben ebenfalls in dieser Sicherung. Spielstände und Spielprotokolle werden durch das Update nicht verschoben.

## GitHub als Updatequelle

Verwendet wird das Repository `AlexBarono/Transport-Fever-3-Multiplayer`. Die Prüfung lädt die kleine Release-Datei über:

```text
https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/releases/latest/download/update.json
```

GitHub unterstützt diesen festen Downloadpfad zum jeweils neuesten Release-Asset. Der Launcher benötigt dadurch keine REST-API-Abfrage und keinen Zugangsschlüssel. [GitHub-Dokumentation zu Release-Links](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases).

**Voraussetzung für Mitspieler ohne Anmeldung:** Das Repository ist öffentlich und mindestens ein vollständiges Release ist veröffentlicht. Solange es privat ist oder `update.json` fehlt, meldet die Prüfung dies im Launcherprotokoll. ZIP-Updates bleiben verfügbar. Die Anwendung ändert die Sichtbarkeit des Repositorys nicht.

Ein Release enthält:

- `TF3-Multiplayer-v66-Windows.zip` für v66, entsprechend benannt für spätere Versionen.
- `update.json` mit Schema, Versionsnummer, ZIP-Größe und SHA-256.

Der Downloadlink zur ZIP wird aus der geprüften Versionsnummer und dem festgelegten Repository gebildet. Beliebige URLs aus einer heruntergeladenen JSON-Datei werden nicht ausgeführt.

## Neue Version veröffentlichen

Der lokale Paketbau erzeugt neben der ZIP die passende Datei `TF3-Multiplayer-v66-Windows.update.json`. Bei manueller Veröffentlichung diese als **update.json** gemeinsam mit der ZIP an das passende GitHub-Release `v66` anhängen und das Release veröffentlichen.

Der Workflow `.github/workflows/release.yml` übernimmt das für neue Versionstags automatisch:

1. Den vollständig geprüften Quellstand einschließlich Workflow im Repository bereitstellen.
2. Den dazu passenden Tag, beispielsweise `v67` für Quellversion 67, pushen.
3. Der Windows-Job prüft den Updater, baut die Bridge, erstellt und prüft das Paket und lädt beide Release-Dateien zunächst in einen Entwurf.
4. Erst nach erfolgreichem Upload wird dieser Entwurf als neuestes Release veröffentlicht.

Quellversion und Tag müssen übereinstimmen. Ein bereits veröffentlichtes Release wird durch den Workflow nicht stillschweigend überschrieben. Benutzer benötigen für den Download keinen GitHub-Account; der Release-Job verwendet den auf GitHub bereitgestellten Repository-Token ausschließlich zur Veröffentlichung.

## Prüfung und Rücknahme

- Online-Downloads müssen zur angekündigten Größe und SHA-256 passen. Die entpackte Dateiliste wird zusätzlich vollständig gegen `package-manifest.json` geprüft.
- Version, Mod-Metadaten, Bridge-Angaben, Mod-Dateiliste und notwendige Launcherdateien werden verglichen. Gleiche und ältere Versionen werden abgelehnt.
- Pfade außerhalb des Pakets, doppelte Windows-Dateinamen, symbolische Links, reservierte Dateinamen und übergroße Archive werden zurückgewiesen.
- Vor dem Wechsel wird erneut geprüft, ob TF3 gestartet wurde und ob sich Paket oder ZIP geändert haben. Die ZIP wird unmittelbar vor dem Wechsel erneut geprüft und frisch entpackt.
- Der Helfer wartet, bis der alte Launcherprozess beendet ist. Schlägt der zweite Ordnerwechsel fehl, wird der bisherige Ordner an seinen ursprünglichen Platz zurückgesetzt.
- Updates in einem Git-Checkout werden abgelehnt. Die Funktion aktualisiert das transportable Windows-Paket.

Automatische Prüfungen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_update.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_update_ui.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_launcher_view.ps1
```

**51 Updateprüfungen**, **9 Prüfungen der Updateoberfläche** und **573 Layoutprüfungen** bei 100 %, 150 % und 200 % Skalierung bestehen. Die Updateprüfung testet vollständigen Paketwechsel, Sicherung, Rücknahme bei einem erzwungenen Ordnerfehler, Elternprozess-Handoff, echten Neustart eines harmlosen Fixture-Launchers, erhaltene Einladung, beschädigte Downloads und manipulierte ZIP-Inhalte. Die UI-Prüfung verwendet echte Hintergrundjobs und simulierte Release-Antworten. Ein öffentlicher GitHub-Download muss nach Veröffentlichung des ersten Release zusätzlich bestätigt werden.

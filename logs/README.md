# Diagnoseprotokolle

Neue Sitzungsprotokolle und Messdaten bleiben lokal und werden nicht in Git aufgenommen. Die Launcherprotokolle liegen im Spielordner und unter `%LOCALAPPDATA%\TF3MP\Logs`; private Auswertungskopien und Windows-Pakete gehören nach `release/`.

Die 117 historischen Dateien aus diesem Ordner wurden beim Aufräumen am 15. Oktober 2026 außerhalb des Repositories gesichert. Sie bleiben außerdem vollständig im [Git-Stand vor der Bereinigung](https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/tree/bda25222c171ea4dd776f75cc8e132d80b7c2553/logs) erhalten. Der Tag `archive/pre-cleanup-v62-20261015` bezeichnet denselben Stand. Namen wie `logs/run30-stdout.txt` in historischen Dokumenten beziehen sich auf dieses Archiv.

Ein einzelnes altes Protokoll lässt sich ohne Änderung des Arbeitsverzeichnisses lesen:

```powershell
git show archive/pre-cleanup-v62-20261015:logs/run30-stdout.txt
```

Für **Test-letzte-Aufnahme.bat** wird ausschließlich die kleine, unveränderte Folge der 21 Run29-Aktionen in [tests/fixtures/run29-replay.log](../tests/fixtures/run29-replay.log) benötigt. Sie ist Teil des Windows-Pakets. Die großen ursprünglichen Diagnoseprotokolle werden weder zum Spielen noch für den Paketbau benötigt.

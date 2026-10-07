# Spielstand an den Mitspieler schicken (Launcher)

Beide Spiele müssen denselben Spielstand laden. Damit der Mitspieler ihn nicht per Chat oder USB-Stick bekommen muss, kann der Launcher ihn übertragen (`tools/save-transfer.ps1`).

1. Gastgeber: im Launcher "Gastgeber" wählen, auf "Spielstand übertragen" klicken und den Spielstand auswählen. Der Launcher wartet bis zu 10 Minuten. Beim ersten Mal fragt Windows evtl. nach einer Firewall-Freigabe für PowerShell: erlauben.
2. Mitspieler: "Mitspieler" wählen, die IP des Gastgebers eintragen und auf "Spielstand übertragen" klicken.
3. Danach laden beide diesen Spielstand. Wer früher fertig ist, wartet im Spiel automatisch (Abgleich der Spielzeit, siehe `docs/phase3-sync.md`).

Ein zweiter Klick auf den Knopf (er heißt dann "Abbrechen") bricht ab.

## Technik

- TCP auf demselben Port wie das Spiel (Standard 47800; das Spiel selbst nutzt UDP). Übers Internet braucht der Gastgeber deshalb eine Portfreigabe für UDP **und** TCP, oder beide nutzen ein VPN wie Tailscale oder ZeroTier.
- Spielstände liegen in `<Steam>\userdata\<Konto>\3493540\local\save\` als `<name>.sav` mit Vorschaubild `<name>.jpg` (Lauf 25: `Det.sav` 33 MB, `Det.jpg` 0,8 MB; die größten Spielstände rund 80 MB). Bei mehreren Steam-Konten nimmt der Launcher den Ordner mit dem zuletzt geänderten Spielstand.
- Übertragen werden `.sav` und, falls vorhanden, `.jpg`. Der Mitspieler prüft jede Datei mit SHA-256, schreibt sie zuerst als `.part` und legt sie erst danach unter dem richtigen Namen ab. Dateinamen vom Gastgeber dürfen keinen Pfad enthalten und müssen auf `.sav` oder `.jpg` enden.
- Gibt es beim Mitspieler schon einen anderen Spielstand mit diesem Namen, fragt der Launcher. Bei "Ja" bleibt der alte als `<datei>.bak` liegen.

Offline-Test: `pwsh -File tests/run_save_transfer.ps1` (8 Tests, zwei PowerShell-Prozesse über 127.0.0.1).

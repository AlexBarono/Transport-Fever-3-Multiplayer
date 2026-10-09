# A fake peer retains commands but has no independently simulated TF3 world.
function Get-FakeHostReport($HostLines, $GameLines = @()) {
    $hostText = $HostLines -join "`n"
    $gameText = $GameLines -join "`n"
    $checks = New-Object System.Collections.ArrayList
    function Add-Check($name, $status, $detail) {
        [void]$checks.Add([pscustomobject]@{ Name=$name; Status=$status; Detail=$detail })
    }
    function Check-Response($name, $command, $response) {
        $start = [regex]::Match($hostText, $command)
        if (-not $start.Success) { Add-Check $name 'OFFEN' 'Testphase noch nicht erreicht'; return }
        if ($hostText.Substring($start.Index) -match $response) { Add-Check $name 'OK' 'Antwort des Spiels beobachtet' }
        else { Add-Check $name 'OFFEN' 'Befehl gesendet, passende Antwort fehlt' }
    }
    Check-Response 'Pause' 'HOST sets speed 0' 'game speed state: by=host [^\r\n]*run=0 speed=0'
    Check-Response 'Fortsetzen' 'HOST sets speed 1' 'game speed state: by=host [^\r\n]*run=1 speed=1'
    if ($hostText -match 'did NOT catch up') { Add-Check 'Aufholen' 'FEHLER' 'Zeitlimit beim Aufholen erreicht' }
    elseif ($hostText -match 'caught up after (\d+) s') { Add-Check 'Aufholen' 'OK' "90 Spielsekunden Rueckstand in $($matches[1]) Sekunden aufgeholt" }
    else { Add-Check 'Aufholen' 'OFFEN' 'Erfolgreiches Aufholen noch nicht bestaetigt' }
    if ($hostText -match 'checkpoint [^\r\n]*adj=5000[^\r\n]*host answers with same values') {
        Add-Check 'Geldkorrektur' 'OK' 'Spiel meldet die Buchung von 5000 und anschliessend gleiche Werte'
    } else { Add-Check 'Geldkorrektur' 'OFFEN' 'Buchung von 5000 noch nicht bestaetigt' }
    $recorded = [regex]::Matches($hostText, 'recorded build ').Count
    $applied = [regex]::Matches($hostText, 'game APPLIED line ').Count
    if ($hostText -match 'REPLAY FAILED|REPLAY TIMEOUT') { Add-Check 'Nachbau' 'FEHLER' "Nachbau abgebrochen ($applied bestaetigt)" }
    elseif ($hostText -notmatch 'the game loaded a savegame again') {
        Add-Check 'Nachbau' 'OFFEN' "$recorded Aktionen nur aufgezeichnet; urspruenglichen Stand ohne Speichern neu laden"
    } elseif ($recorded -eq 0) { Add-Check 'Nachbau' 'OFFEN' 'Keine Aktionen aufgezeichnet' }
    else {
        $rounds = [regex]::Matches($hostText, '(\d+) build line\(s\) of the session before')
        $expected = 0
        foreach ($round in $rounds) { $expected += [int]$round.Groups[1].Value }
        if ($expected -gt 0 -and $applied -eq $expected) { Add-Check 'Nachbau' 'OK' "$applied Aktionen vom echten Spiel bestaetigt; Ergebnis auf der Karte pruefen" }
        else { Add-Check 'Nachbau' 'OFFEN' "$applied von $expected zurueckgesendeten Aktionen bestaetigt" }
    }
    # Match the first heartbeat to avoid evaluating an unrelated, newer stdout.txt.
    $first = [regex]::Match($hostText, 'game speed state: ([^\r\n]+)')
    $sameRun = $first.Success -and $gameText.Contains($first.Groups[1].Value.Trim())
    if ($sameRun) {
        $scans = [regex]::Matches($gameText, '\[mp_probe\]world scan [^\r\n]+')
        $failed = @()
        foreach ($field in 'hcon','hedge','hline','hveh','hpos','hcargo','htown') {
            if ($scans.Count -gt 0 -and $scans[$scans.Count-1].Value -match ("\b" + $field + '=')) { $failed += $field }
        }
        if ($failed.Count -gt 0) { Add-Check 'Weltvergleich' 'LUECKE' ("Nicht auslesbar: " + ($failed -join ', ')) }
        elseif ($scans.Count -eq 0) { Add-Check 'Weltvergleich' 'OFFEN' 'Keine Weltmessung im Spielprotokoll' }
        else { Add-Check 'Weltvergleich' 'TEILWEISE' 'Messung vorhanden; Gastgeber spiegelt Werte, keine unabhaengige zweite Welt' }
        if ($hostText -match 'one vehicle more' -and $gameText -match 'sync WARNING: the games differ: veh ') {
            Add-Check 'Absichtliche Abweichung' 'OK' 'Zusaetzliches Fahrzeug wurde als Abweichung erkannt'
        } else { Add-Check 'Absichtliche Abweichung' 'OFFEN' 'Warnung im Spiel noch nicht belegt' }
        $errors = [regex]::Matches($gameText, '\[mp_probe\][^\r\n]*(?:net skipped|game rejected|peer rejected|replay failed|success=false)[^\r\n]*')
        if ($errors.Count -gt 0) { Add-Check 'Aktionsfehler' 'FEHLER' "$($errors.Count) Fehler/uebersprungene Aktionen im Spielprotokoll" }
        else { Add-Check 'Aktionsfehler' 'OK' 'Keine abgelehnten Aktionen im zugeordneten Spielprotokoll gefunden' }
        if ($gameText -match 'Normal shutdown\. Bye!') { Add-Check 'Spielende' 'OK' 'Normaler Spielabschluss protokolliert' }
        else { Add-Check 'Spielende' 'OFFEN' 'Spiel laeuft noch oder normaler Abschluss fehlt' }
        $maxCapture = 0; $maxStep = 0
        foreach ($scan in $scans) {
            if ($scan.Value -match '\bcapture_ms=(\d+)') { $maxCapture = [Math]::Max($maxCapture, [int]$matches[1]) }
            if ($scan.Value -match '\bmax_step_ms=(\d+)') { $maxStep = [Math]::Max($maxStep, [int]$matches[1]) }
        }
        if ($scans.Count -gt 0) { Add-Check 'Messkosten' 'INFO' "Maximal $maxCapture ms Erfassung, $maxStep ms Hash-Schritt in diesem Lauf; kein Nachweis fuer grosse Karten" }
    } else {
        Add-Check 'Spielprotokoll' 'OFFEN' 'Fehlt oder gehoert nicht zu diesem Testlauf; keine Erfolgsaussage daraus'
    }
    Add-Check 'Zwei-PC-Verfahren' 'UNGETESTET' 'Gemeinsame Aktionszeit, VPN, Spielstanduebertragung und automatischer Neuabgleich brauchen einen echten zweiten PC'
    $lines = @('Auswertung: simulierter Gastgeber', 'OK gilt nur fuer beobachtete Antworten; OFFEN/LUECKE ist kein bestandener Test.', '')
    $lines += @($checks | ForEach-Object { "[$($_.Status)] $($_.Name): $($_.Detail)" })
    return [pscustomobject]@{ Checks=@($checks); Text=($lines -join "`r`n") }
}

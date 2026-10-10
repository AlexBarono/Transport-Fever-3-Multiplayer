# UI state belongs to this launcher run; an old alut_session.json never starts a game.
$script:lobby = $null
$script:lobbyJob = $null
$script:retiredLobbyJobs = New-Object Collections.Generic.List[object]
$script:lobbyPhase = 'idle'
$script:lobbyPeerReady = $false
$script:lobbySession = ''
$script:lobbyStart = ''
$script:lobbyStarted = ''
$script:lobbyError = ''
$script:lobbyKey = ''
$script:lobbyChanged = [DateTime]::UtcNow
$script:lobbyGameSeen = $false
$script:lobbyPreparing = $false
$script:presence = $null
$script:lobbyLoadSeen = $false

function Register-LobbyInputEvents {
    foreach($field in @($ipBox,$portBox,$gameBox)){
        $field.Add_TextChanged({
            if(-not $script:lobbyPreparing -and -not $script:transferBusy -and -not $script:liveBusy){
                Close-LauncherLobby; $script:lobbyKey=''; $script:lobbyChanged=[DateTime]::UtcNow; Update-Fields
            }
        })
    }
}

function Close-LauncherLobby {
    if($script:presence){$script:presence.Dispose(); $script:presence=$null}
    if ($script:lobbyJob) {
        $script:lobbyJob.Progress.Cancel = $true
        $script:retiredLobbyJobs.Add($script:lobbyJob)
        $script:lobbyJob = $null
    }
    if ($script:lobby) { $script:lobby.Dispose(); $script:lobby = $null }
    $script:lobbyPeerReady = $false; $script:lobbyPhase = 'idle'
    $script:lobbySession = ''; $script:lobbyStart = ''; $script:lobbyStarted = ''
    $script:lobbyError = ''; $script:lobbyGameSeen = $false
    $script:lobbyLoadSeen=$false
    $progressBar.Value = 0
}

function Clear-LauncherJoinAddress {
    Close-LauncherLobby
    if($script:internetRole -eq 'client'){Stop-LauncherInternet}
    $ipBox.Clear(); [void]$ipBox.Focus(); Update-Fields
}

function Set-LauncherProgress([string]$Text, [long]$Done, [long]$Total) {
    $workflowHint.Text = $Text
    if ($Total -gt 0) {
        $progressBar.Value = [int][Math]::Min(100, 100.0 * $Done / $Total)
        if ($Done -gt 0) { $workflowHint.Text += ('  |  {0:N1} / {1:N1} MB' -f ($Done/1MB), ($Total/1MB)) }
    }
}

function Set-LobbyConnection($Connection, $Session, [bool]$IsHost) {
    if ($script:lobby) { $script:lobby.Dispose() }
    $script:lobby = New-Object TF3MP.LobbyChannel($Connection, $Session.SessionId, $IsHost)
    $script:lobbySession = $Session.SessionId
    $script:lobbyKey="$($clientRadio.Checked)|$($hostRadio.Checked)|$($ipBox.Text.Trim())|$($portBox.Text.Trim())|$($gameBox.Text.Trim())"
    $script:lobbyPhase = 'ready'; $script:lobbyError = ''
    $script:lobbyPeerReady = -not $IsHost
    if (-not $IsHost) { $script:lobby.Send('READY', '') }
}

function Test-LobbyCanStart {
    return $hostRadio.Checked -and $script:lobbyPhase -eq 'ready' -and $script:lobbyPeerReady -and $script:lobby -and $script:lobby.Connected -and -not $script:transferBusy -and -not $script:liveBusy
}

function Get-LauncherResyncReason($Values) {
    # The same host request travels through launcher TCP and the game's UDP bridge.
    # Consume the bridge notification, but let the session-bound launcher message own it.
    $reason=Get-LiveResyncReason $Values $script:liveMemory ([DateTime]::UtcNow)
    if($reason -and $reason.Kind -eq 'peer' -and $script:lobby -and $script:lobby.Connected){return $null}
    return $reason
}

function Start-BothGames {
    if (-not (Test-LobbyCanStart)) { return }
    try {
        $session = Get-LaunchSession $gameBox.Text.Trim() $steam -Installed
        if ($session.SessionId -ne $script:lobbySession) { throw 'Die vorbereitete Sitzung hat sich geändert. Spielstand erneut bereitstellen.' }
        $script:lobbyStart = [Guid]::NewGuid().ToString('N')
        $script:lobbyStartTime = [DateTime]::UtcNow
        $script:lobbyPhase = 'starting'
        $script:lobby.Send('START', $script:lobbyStart)
        Write-LauncherLog 'Gemeinsamer Start angefordert. Warte auf die Startbestätigung des Mitspielers.'
    } catch { $script:lobbyPhase='error'; $script:lobbyError=$_.Exception.Message; Show-Error $_.Exception.Message }
    Update-Fields
}

function Update-LauncherLobby {
    # Cancelled receivers finish outside the UI thread, including closing any retained socket.
    for ($i=$script:retiredLobbyJobs.Count-1; $i -ge 0; $i--) {
        $job=$script:retiredLobbyJobs[$i]
        if ($job.Async.IsCompleted) {
            try { $unused=Complete-LobbyReceiver $job; if ($unused.Connection) { $unused.Connection.Close() } } catch {}
            $script:retiredLobbyJobs.RemoveAt($i)
        }
    }
    if ($Preview -or $script:transferBusy -or $script:liveBusy -or $script:lobbyPreparing) { return }
    $key = "$($clientRadio.Checked)|$($hostRadio.Checked)|$($ipBox.Text.Trim())|$($portBox.Text.Trim())|$($gameBox.Text.Trim())"
    if ($script:lobbyKey -ne $key) {
        Close-LauncherLobby; $script:lobbyKey=$key; $script:lobbyChanged=[DateTime]::UtcNow
    }
    if ($script:lobby -and -not $script:lobby.Connected) {
        Write-LauncherLog "Launcher-Verbindung getrennt: $($script:lobby.Error). Ein neuer gemeinsamer Start braucht eine erneute Spielstandübertragung. Ein laufendes Spiel nutzt weiterhin seinen eigenen Spielkanal."
        $script:lobby.Dispose(); $script:lobby=$null; $script:lobbyPeerReady=$false
        $script:lobbyPhase='idle'; $script:lobbyStart=''; $script:lobbyChanged=[DateTime]::UtcNow
    }
    if ($script:lobby) {
        while ($message=$script:lobby.Take()) {
            $command,$argument=$message.Split('|',2)
            switch ($command) {
                'READY' {
                    $script:lobbyPeerReady=$true
                    Write-LauncherLog 'Mitspieler bereit: Spielstand geprüft, gespeichert und Multiplayer eingerichtet. Du kannst jetzt beide Spiele starten.'
                }
                'START' {
                    try {
                        if ($script:lobbyStarted -eq $argument) { $script:lobby.Send('STARTED',$argument); break }
                        if ($script:lobbyPhase -ne 'ready') { throw 'Ein Spielstart ist in diesem Zustand nicht möglich.' }
                        $script:lobbyPreparing=$true; Update-Fields
                        $session=Get-LaunchSession $gameBox.Text.Trim() $steam -Installed
                        if ($session.SessionId -ne $script:lobbySession) { throw 'Die Sitzung hat sich seit der Übertragung geändert.' }
                        Start-LauncherGame
                        $script:lobbyStarted=$argument; $script:lobbyPhase='started'; $script:lobbyStartTime=[DateTime]::UtcNow
                        $script:lobby.Send('STARTED',$argument)
                        Write-LauncherLog "Gastgeber hat gestartet. TF3 lädt '$($session.SaveName)' automatisch."
                    } catch {
                        $script:lobbyPhase='error'; $script:lobbyError=$_.Exception.Message
                        $script:lobby.Send('ERROR','Spielstart fehlgeschlagen. Protokoll am Mitspieler-PC prüfen.')
                        Write-LauncherLog "Spielstart fehlgeschlagen: $($_.Exception.Message)"
                    } finally { $script:lobbyPreparing=$false }
                }
                'STARTED' {
                    if ($script:lobbyPhase -eq 'starting' -and $argument -eq $script:lobbyStart) {
                        try { $script:lobbyPreparing=$true; Start-LauncherGame; $script:lobbyPhase='started'; Write-LauncherLog 'Beide Spiele starten und laden den gemeinsamen Spielstand automatisch.' }
                        catch { $script:lobbyPhase='error'; $script:lobbyError=$_.Exception.Message; Write-LauncherLog "Gastgeber-Spielstart fehlgeschlagen: $($_.Exception.Message)" }
                        finally { $script:lobbyPreparing=$false }
                    }
                }
                'RESYNC' {
                    if($script:lobbyLastResync -eq $argument){break}
                    $script:lobbyLastResync=$argument
                    if (Test-GameRunning) {
                        $values=Read-ProxyStatusValues (Join-Path $gameBox.Text.Trim() 'alut_proxy.status')
                        Invoke-LiveResync $values @{ Kind='peer'; Detail=$argument }
                    } else { $script:lobby.Send('ERROR','Neuabgleich: TF3 läuft beim Mitspieler noch nicht. Beide Karten laden.') }
                }
                'ERROR' {
                    $script:lobbyError=$argument
                    if ($script:lobbyPhase -eq 'starting' -or $script:lobbyPhase -eq 'ready') { $script:lobbyPhase='error'; $script:lobbyPeerReady=$false }
                    Write-LauncherLog "Mitspieler meldet: $argument"
                }
            }
        }
        if ($script:lobbyPhase -eq 'starting' -and ([DateTime]::UtcNow-$script:lobbyStartTime).TotalSeconds -gt 90) {
            $script:lobbyPhase='error'; $script:lobbyError='Startbestätigung fehlt. Protokoll beim Mitspieler prüfen; vor einem neuen Versuch TF3 beenden und den Stand erneut bereitstellen.'
            Write-LauncherLog $script:lobbyError
        }
    }
    if($script:presence -and $script:presence.Connected -and (-not $script:saveChoicesAt -or ([DateTime]::UtcNow-$script:saveChoicesAt).TotalSeconds -gt 10)){
        Refresh-SaveChoices; $script:saveChoicesAt=[DateTime]::UtcNow
    }
    if ($script:lobbyJob) {
        $snapshot=$script:lobbyJob.Progress.Snapshot()
        Set-LauncherProgress $snapshot[0] $snapshot[1] $snapshot[2]
        if ($script:lobbyJob.Async.IsCompleted) {
            $job=$script:lobbyJob; $script:lobbyJob=$null; $connection=$null
            $script:lobbyPreparing=$true; Update-Fields
            try {
                $received=Complete-LobbyReceiver $job; $connection=$received.Connection
                $script:LastSaveTransfer=$received.Stats
                $result=$received.Transfer
                Save-PreparedSession (Join-Path $gameBox.Text.Trim() 'alut_session.json') $result.Session $result.SavePath | Out-Null
                $script:forceNewSession=$false
                Stop-LauncherGameForStart { param($text,$done,$total) Set-LauncherProgress $text $done $total; [Windows.Forms.Application]::DoEvents(); return $false }
                Install-LauncherSettings
                Install-GameAutoload $gameBox.Text.Trim()
                Initialize-GameFirewall
                Set-LobbyConnection $connection $result.Session $false; $connection=$null
                $script:transferOK=$true
                Write-LauncherLog "Spielstand '$($result.Session.SaveName)' empfangen und geprüft. Gleichnamige alte Dateien bleiben als .bak erhalten. Warte auf das Starten des Gastgebers."
                if ($received.Stats) { Write-LauncherLog ('Übertragung: {0:N1} MB, {1:N1} s, {2} Verbindungen. Messprotokoll: {3}' -f ($received.Stats.Bytes/1MB),$received.Stats.Seconds,$received.Stats.Streams,$received.Stats.LogPath) }
            } catch {
                if ($connection) { $connection.Close() }
                $script:lobbyPhase='error'; $script:lobbyError=$_.Exception.Message
                Write-LauncherLog "Spielstand konnte nicht vorbereitet werden: $($_.Exception.Message). Adresse oder Spielordner korrigieren; bei Versionsfehlern beide Launcher aktualisieren. Danach links Beitreten erneut auswählen."
            } finally { $script:lobbyPreparing=$false }
        }
    }
    $gameRunning=Test-GameRunning
    if($script:lobbyPhase -eq 'started' -and -not $script:lobbyGameSeen -and -not $gameRunning -and ([DateTime]::UtcNow-$script:lobbyStartTime).TotalSeconds -gt 120){
        $script:lobbyPhase='error'; $script:lobbyError='TF3 wurde nach dem Steamstart noch nicht erkannt. Steam und das Spielprotokoll prüfen. Für einen neuen gemeinsamen Start den Stand erneut bereitstellen.'
        Write-LauncherLog $script:lobbyError
    }
    if ($script:lobbyPhase -eq 'started' -and $gameRunning) { $script:lobbyGameSeen=$true }
    if($script:lobbyPhase -eq 'started' -and $gameRunning -and -not $script:lobbyLoadSeen){
        $values=Read-ProxyStatusValues (Join-Path $gameBox.Text.Trim() 'alut_proxy.status')
        if($values.loaded -eq '1' -and $values.initialized -eq '1'){
            if($script:lobbyError -like 'Automatisches Laden fehlgeschlagen:*'){$script:lobbyError=''}
            $script:lobbyLoadSeen=$true; Write-LauncherLog 'Gemeinsamer Spielstand geladen. Die Verbindung wartet auf beide spielbereiten Karten.'
        } elseif(-not $script:autoloadCheckAt -or ([DateTime]::UtcNow-$script:autoloadCheckAt).TotalSeconds -ge 5){
            $script:autoloadCheckAt=[DateTime]::UtcNow
            $failure=Get-GameAutoloadFailure $gameBox.Text.Trim() $script:lobbyStartTime
            if($failure -and -not $script:lobbyError){
                $script:lobbyError="Automatisches Laden fehlgeschlagen: $failure. Gemeinsamen Stand im TF3-Hauptmenü auswählen."
                Write-LauncherLog $script:lobbyError
            }
        }
    }
    if ($script:lobbyPhase -eq 'started' -and $script:lobbyGameSeen -and -not $gameRunning) {
        Write-LauncherLog 'TF3 wurde beendet. Für die nächste Sitzung stellt der Gastgeber den Spielstand erneut bereit.'
        Close-LauncherLobby
    }
    if($hostRadio.Checked -and -not $script:presence -and -not $script:lobby -and $script:lobbyPhase -eq 'idle' -and ($connectionMode.SelectedIndex -eq 1 -or $script:internetRole -eq 'host')){
        try {
            $script:lobbyPreparing=$true
            if(-not $script:internetTunnel){[void](Enable-InternetFirewall ([int]$portBox.Text))}
            Refresh-SaveChoices
            $script:presence=New-Object TF3MP.LobbyPresence([int]$portBox.Text)
            Write-LauncherLog 'Verbindung offen. Warte auf den Mitspieler; danach wird Spielstand bereitstellen angezeigt.'
        } catch { $script:lobbyPhase='error'; $script:lobbyError=$_.Exception.Message; Write-LauncherLog "Verbindung konnte nicht geöffnet werden: $script:lobbyError" }
        finally {$script:lobbyPreparing=$false}
    }
    if ($clientRadio.Checked -and -not $script:lobbyJob -and -not $script:lobby -and $script:lobbyPhase -eq 'idle' -and ([DateTime]::UtcNow-$script:lobbyChanged).TotalSeconds -gt 1.5 -and $script:retiredLobbyJobs.Count -eq 0) {
        if (-not $ipBox.Text.Trim() -or -not $gameBox.Text.Trim()) { return }
        try {
            $script:lobbyPreparing=$true; Update-Fields
            $endpoint=Resolve-LauncherEndpoint $ipBox.Text $portBox.Text
            Assert-LauncherInternetMode 'client' $endpoint.Port ''
            $manifest=Get-LauncherManifest $gameBox.Text.Trim() $steam
            $script:lobbyJob=Start-LobbyReceiver $Root $endpoint.Address $endpoint.Port (Get-SaveFolder $steam) $manifest
            $script:lobbyPhase='receiving'
            Write-LauncherLog 'Verbinde mit dem Gastgeber. Danach werden Spielstand und gemeinsamer Start automatisch übernommen.'
        } catch { $script:lobbyPhase='error'; $script:lobbyError=$_.Exception.Message; Write-LauncherLog $script:lobbyError }
        finally { $script:lobbyPreparing=$false }
    }
    Update-Fields
}

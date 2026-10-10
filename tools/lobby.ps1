# Background reception keeps the joining screen responsive while the host chooses a save.
if (-not ('TF3MP.LobbyChannel' -as [type])) { Add-Type -Path @((Join-Path $PSScriptRoot 'lobby-channel.cs'), (Join-Path $PSScriptRoot 'lobby-presence.cs')) }

function Start-LobbyReceiver([string]$Root, [string]$Address, [int]$Port, [string]$SaveDir, $Manifest, [bool]$WaitForHost = $true) {
    $lobbyProgress = New-Object TF3MP.LobbyProgress
    $worker = [PowerShell]::Create()
    [void]$worker.AddScript({
        param($root, $address, $port, $saveDir, $manifest, $lobbyProgress, $waitForHost)
        $ErrorActionPreference = 'Stop'
        . (Join-Path $root 'tools\save-transfer.ps1')
        $connection = $null
        $tick = { param($text, $done, $total) $lobbyProgress.Publish($text, $done, $total); return $lobbyProgress.Cancel }
        try {
            if ($waitForHost) { [TF3MP.LobbyPresence]::WaitForTransfer($address, $port, $lobbyProgress) }
            $result = Receive-Savegame $address $port $saveDir $tick { param($question) $true } -LocalManifest $manifest -WaitSeconds 86400 -WaitText 'Warte auf Spielstand vom Gastgeber' -KeepConnection ([ref]$connection)
            if ($lobbyProgress.Cancel) { throw 'Abgebrochen.' }
            [pscustomobject]@{ Transfer=$result; Connection=$connection; Stats=$script:LastSaveTransfer }
        } catch { if ($connection) { $connection.Close() }; throw }
    }).AddArgument($Root).AddArgument($Address).AddArgument($Port).AddArgument($SaveDir).AddArgument($Manifest).AddArgument($lobbyProgress).AddArgument($WaitForHost)
    try { $async = $worker.BeginInvoke() } catch { $worker.Dispose(); throw }
    return @{ Worker=$worker; Async=$async; Progress=$lobbyProgress }
}

function Complete-LobbyReceiver($Job) {
    if (-not $Job.Async.IsCompleted) { throw 'Die Übertragung läuft noch.' }
    try {
        $result = $Job.Worker.EndInvoke($Job.Async)
        if ($Job.Worker.Streams.Error.Count) { throw $Job.Worker.Streams.Error[0] }
        if ($result.Count -ne 1) { throw 'Die Übertragung hat kein eindeutiges Ergebnis geliefert.' }
        return $result[0]
    } finally { $Job.Worker.Dispose() }
}

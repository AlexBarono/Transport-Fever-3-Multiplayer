# Internet-only protocol sharing. File reads and uploads run in the tunnel worker.
# The launcher supplies a fixed set of local sources, never a peer-selected path.
$script:internetProtocolState = $null

function Reset-InternetProtocolSharing {
    $script:internetProtocolState = $null
}

function Get-InternetProtocolSources([string]$GameDir, [string]$SteamRoot, [datetime]$Since = [datetime]::MinValue, [string]$LogDirectory = '') {
    $sources = [ordered]@{}
    if ($GameDir) {
        foreach ($entry in @(@('bridge','alut_proxy.log'),@('launcher','alut_launcher.log'),@('status','alut_proxy.status'))) {
            $sources[$entry[0]] = Join-Path $GameDir $entry[1]
        }
    }
    if ($SteamRoot) {
        try { $sources.stdout = Find-SameSpotLog $SteamRoot } catch {} # TF3 may not have started yet.
    }
    $internetPath = Get-Variable internetLogPath -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($internetPath) { $sources.internet = [string]$internetPath }
    if (-not $LogDirectory) { $LogDirectory = Join-Path $env:LOCALAPPDATA 'TF3MP\Logs' }
    # The receive worker has its own runspace. Its live trace is not available through
    # this script's SaveTransferTrace, but belongs to this same Windows process ID.
    $transferPaths = @()
    if (Test-Path -LiteralPath $LogDirectory -PathType Container) {
        $transferPaths += @(Get-ChildItem -LiteralPath $LogDirectory -File -Filter "save-transfer-*-$PID-*.jsonl" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $Since } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    }
    foreach ($variable in @('SaveTransferTrace','LastSaveTransfer')) {
        $trace = Get-Variable $variable -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        $tracePath = if ($trace -and $variable -eq 'SaveTransferTrace') { $trace.Path } elseif ($trace) { $trace.LogPath } else { '' }
        if ($tracePath -and (Test-Path -LiteralPath $tracePath -PathType Leaf)) {
            $item = Get-Item -LiteralPath $tracePath
            if ($item.LastWriteTimeUtc -ge $Since) { $transferPaths += $item }
        }
    }
    $latest = $transferPaths | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $sources.transfer = $latest.FullName }
    return $sources
}

function Update-InternetProtocolSharing([string]$GameDir = '', [string]$SteamRoot = '') {
    $t = $script:internetTunnel
    $role = $script:internetRole
    if (-not $t -or $role -notin @('host','client')) { Reset-InternetProtocolSharing; return }
    $now = [datetime]::UtcNow
    $s = $script:internetProtocolState
    if (-not $s -or -not [object]::ReferenceEquals($s.Tunnel,$t) -or $s.Role -ne $role) {
        $s = @{ Tunnel=$t; Role=$role; Since=$now.AddMinutes(-1); CheckedAt=[datetime]::MinValue; Configured=$false; SourceKey=''; Directory=''; Error='' }
        $script:internetProtocolState = $s
    }
    if (($now - $s.CheckedAt).TotalSeconds -lt 5) { return }
    $s.CheckedAt = $now # Before callbacks/logging, so nested WinForms ticks stay bounded.
    try {
        if ($role -eq 'host') {
            if (-not $s.Configured) {
                $folder = Join-Path $env:LOCALAPPDATA 'TF3MP\Logs\Mitspieler'
                $t.EnableDiagnosticReceiver($folder)
                $s.Configured = $true
                Write-LauncherLog 'Internet-Protokolle: Der Mitspieler überträgt seine Diagnosedaten automatisch. Der Empfangsordner wird nach den ersten Daten hier angezeigt.'
            }
            if ($t.DiagnosticBytesReceived -gt 0 -and $t.DiagnosticDirectory -and $t.DiagnosticDirectory -ne $s.Directory) {
                $s.Directory = $t.DiagnosticDirectory
                Write-LauncherLog "Protokolle des Mitspielers werden gespeichert: $($s.Directory)"
            }
        } else {
            $sources = Get-InternetProtocolSources $GameDir $SteamRoot $s.Since
            $kinds = [string[]]@($sources.Keys)
            $paths = [string[]]@($sources.Values)
            $sourceKey = ($kinds -join "`0") + "`0" + ($paths -join "`0")
            if (-not $s.Configured -or $sourceKey -cne $s.SourceKey) {
                $t.SetDiagnosticSources($kinds,$paths)
                if (-not $s.Configured) {
                    Write-LauncherLog 'Internet-Protokolle werden automatisch an den Gastgeber übertragen: Spiel, Bridge, Launcher, Status, Internet und Spielstandmessungen. Einladungen und Zugangsschlüssel werden vor dem Senden entfernt.'
                }
                $s.Configured = $true; $s.SourceKey = $sourceKey
            }
        }
        $problem = [string]$t.DiagnosticLastError
        if ($problem -and $problem -ne $s.Error) { Write-LauncherLog "Protokollübertragung: $problem. Der Spielkanal läuft unabhängig weiter." }
        $s.Error = $problem
    } catch {
        # A diagnostic configuration/disk error must not interrupt game or save transfer.
        $problem = $_.Exception.GetType().Name
        if ($problem -ne $s.Error) { Write-LauncherLog "Protokollübertragung konnte nicht eingerichtet werden ($problem). Der Spielkanal läuft unabhängig weiter." }
        $s.Error = $problem
    }
}

function Get-InternetProtocolSummary {
    $t = $script:internetTunnel
    if (-not $t) { return '' }
    if ($script:internetRole -eq 'host') {
        if ($t.DiagnosticBytesReceived -gt 0) {
            return "Mitspieler-Protokolle: $([Math]::Round($t.DiagnosticBytesReceived/1KB,1)) KiB empfangen. Ordner: $($t.DiagnosticDirectory)."
        }
        return 'Mitspieler-Protokolle: Warte auf Diagnosedaten des Mitspielers.'
    }
    if ($script:internetRole -eq 'client') {
        $state = if ($t.DiagnosticConnected) { 'verbunden' } else { 'wartet auf Verbindung' }
        return "Protokolle an Gastgeber: $state, $([Math]::Round($t.DiagnosticBytesSent/1KB,1)) KiB übertragen."
    }
    return ''
}

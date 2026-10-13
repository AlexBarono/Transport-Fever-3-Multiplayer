$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\internet.ps1')
. (Join-Path $root 'tools\internet-diagnostics.ps1')
Initialize-InternetTransport
$script:passed = 0
function Check($ok, $message) { if (-not $ok) { throw $message }; $script:passed++ }
function Contents($path) { if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' } }
function Write-LauncherLog([string]$text) { $script:notices.Add($text) }
$script:notices = [Collections.Generic.List[string]]::new()
$testDir = Join-Path $env:TEMP ('tf3mp-protocol-session-' + [Guid]::NewGuid().ToString('N'))
$originalLocal = $env:LOCALAPPDATA
$client = $null; $game = $null; $script:internetTunnel = $null
$clock = [Diagnostics.Stopwatch]::StartNew()
function Wait-Until($condition) {
    while (-not (& $condition)) {
        Update-InternetProtocolSharing
        if ($client -and $client.HasExited) { throw ('Client fixture exited: ' + (Contents (Join-Path $testDir 'error.txt'))) }
        if ($clock.Elapsed.TotalSeconds -gt 30) { throw 'Automatic protocol sharing fixture timed out' }
        Start-Sleep -Milliseconds 50
    }
}
try {
    [IO.Directory]::CreateDirectory($testDir) | Out-Null
    $env:LOCALAPPDATA = Join-Path $testDir 'host-local'
    $game = [Net.Sockets.UdpClient]::new(0)
    $script:internetTunnel = [TF3MP.Internet.Tunnel]::StartHost(0, $game.Client.LocalEndPoint.Port)
    $script:internetRole = 'host'
    Update-InternetProtocolSharing
    Check ($script:internetProtocolState.Configured -and $script:internetTunnel.DiagnosticDirectory -eq (Join-Path $env:LOCALAPPDATA 'TF3MP\Logs\Mitspieler')) 'Host helper did not automatically configure its own protocol directory'
    $config = Join-Path $testDir 'connection.json'
    @{ Root=$root; Fixture=$testDir; Port=$script:internetTunnel.Port; Pin=$script:internetTunnel.Fingerprint; Key=$script:internetTunnel.Key } |
        ConvertTo-Json | Set-Content -LiteralPath $config -Encoding UTF8
    $childPath = Join-Path $testDir 'client.ps1'
    $child = @'
param([string]$Config)
$ErrorActionPreference = 'Stop'
$c = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
$t = $null
try {
    $env:LOCALAPPDATA = Join-Path $c.Fixture 'client-local'
    . (Join-Path $c.Root 'tools\internet.ps1')
    . (Join-Path $c.Root 'tools\same-spot.ps1')
    . (Join-Path $c.Root 'tools\internet-diagnostics.ps1')
    function Write-LauncherLog([string]$text) { [IO.File]::AppendAllText((Join-Path $c.Fixture 'client-notices.txt'), $text + "`n") }
    Initialize-InternetTransport
    $gameDir = Join-Path $c.Fixture 'client-game'
    $steamRoot = Join-Path $c.Fixture 'client-steam'
    $stdoutDir = Join-Path $steamRoot 'userdata\123456\3493540\local\crash_dump'
    $logDir = Join-Path $env:LOCALAPPDATA 'TF3MP\Logs'
    foreach ($dir in @($gameDir,$stdoutDir,$logDir)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    $invitation = 'tf3mp-internet://127.0.0.1:' + $c.Port + '/' + $c.Pin + '/' + $c.Key
    [IO.File]::WriteAllText((Join-Path $stdoutDir 'stdout.txt'), "GAME INITIAL: Häfen, Grüße`n" + $invitation + "`n")
    [IO.File]::WriteAllText((Join-Path $gameDir 'alut_proxy.log'), "BRIDGE INITIAL`n")
    [IO.File]::WriteAllText((Join-Path $gameDir 'alut_launcher.log'), "LAUNCHER INITIAL key=" + $c.Key + "`n")
    [IO.File]::WriteAllText((Join-Path $gameDir 'alut_proxy.status'), 'mode=client loaded=0 initialized=0 ready=0 peer_ready=0')
    $script:internetLogPath = Join-Path $logDir 'internet-current.jsonl'
    [IO.File]::WriteAllText($script:internetLogPath, '{"event":"INTERNET INITIAL","pin":"' + $c.Pin + '"}' + "`n")
    $transfer = Join-Path $logDir ("save-transfer-session-$PID-first.jsonl")
    [IO.File]::WriteAllText($transfer, "TRANSFER INITIAL`n")
    [IO.File]::WriteAllText((Join-Path $logDir 'save-transfer-session-1-unrelated.jsonl'), "UNRELATED PROCESS MUST NOT UPLOAD`n")
    $reserve = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $reserve.Start(); $clientPort=$reserve.LocalEndpoint.Port; $reserve.Stop()
    $t = [TF3MP.Internet.Tunnel]::StartClient('127.0.0.1',$c.Port,$c.Pin,$c.Key,$clientPort)
    $script:internetTunnel=$t; $script:internetRole='client'
    Update-InternetProtocolSharing $gameDir $steamRoot
    @{ Pid=$PID; GameDir=$gameDir; Stdout=(Join-Path $stdoutDir 'stdout.txt'); Transfer=$transfer; LogDir=$logDir } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $c.Fixture 'client-ready.json') -Encoding UTF8
    $limit=[DateTime]::UtcNow.AddSeconds(25)
    while (-not (Test-Path -LiteralPath (Join-Path $c.Fixture 'stop')) -and [DateTime]::UtcNow -lt $limit) {
        Update-InternetProtocolSharing $gameDir $steamRoot
        Start-Sleep -Milliseconds 100
    }
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $c.Fixture 'error.txt') -Encoding UTF8
    exit 1
} finally { if($t) { $t.Dispose() } }
'@
    [IO.File]::WriteAllText($childPath, $child, [Text.UTF8Encoding]::new($true))
    $client = Start-Process (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $childPath + '"'),'-Config',('"' + $config + '"'))
    $readyPath = Join-Path $testDir 'client-ready.json'
    Wait-Until { Test-Path -LiteralPath $readyPath }
    $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
    Wait-Until { $script:internetTunnel.DiagnosticBytesReceived -gt 0 }
    $folder = $script:internetTunnel.DiagnosticDirectory
    $expected = @{ stdout='GAME INITIAL: Häfen, Grüße'; bridge='BRIDGE INITIAL'; launcher='LAUNCHER INITIAL'; status='ready=0'; internet='INTERNET INITIAL'; transfer='TRANSFER INITIAL' }
    Wait-Until {
        $missing = @($expected.Keys | Where-Object { -not (Contents (Join-Path $folder ($_ + '.log'))).Contains($expected[$_]) })
        $missing.Count -eq 0
    }
    Check ($ready.Pid -ne $PID -and (Split-Path $folder -Parent) -eq (Join-Path $env:LOCALAPPDATA 'TF3MP\Logs\Mitspieler')) 'Protocol sharing did not isolate host/client processes and storage'
    Check ($expected.Count -eq 6) 'All six automatically discovered sources were not observed'
    [IO.File]::AppendAllText($ready.Stdout, "GAME APPENDED`n")
    [IO.File]::AppendAllText($ready.Transfer, "TRANSFER LAST FAILURE`n")
    $nextTransfer = Join-Path $ready.LogDir ("save-transfer-session-$($ready.Pid)-second.jsonl")
    [IO.File]::WriteAllText($nextTransfer, "TRANSFER NEXT ATTEMPT`n")
    Wait-Until { (Contents (Join-Path $folder 'stdout.log')).Contains('GAME APPENDED') -and (Contents (Join-Path $folder 'transfer.log')).Contains('TRANSFER NEXT ATTEMPT') }
    $transfers = Contents (Join-Path $folder 'transfer.log')
    Check ($transfers.Contains('TRANSFER LAST FAILURE') -and $transfers.IndexOf('TRANSFER LAST FAILURE') -lt $transfers.IndexOf('TRANSFER NEXT ATTEMPT')) 'Automatic transfer rediscovery lost earlier failure lines'
    Wait-Until { @($script:notices | Where-Object { $_.Contains($folder) }).Count -gt 0 }
    Check ((Get-InternetProtocolSummary).Contains($folder)) 'Host protocol summary omitted the received session directory'
    $allLogs = (@(Get-ChildItem -LiteralPath $folder -File | ForEach-Object { Contents $_.FullName }) -join "`n")
    Check (-not $allLogs.Contains('tf3mp-internet://') -and -not $allLogs.Contains($script:internetTunnel.Key) -and -not $allLogs.Contains($script:internetTunnel.Fingerprint)) 'Session protocol sharing leaked an invitation or access secret'
    Check (-not $allLogs.Contains('UNRELATED PROCESS MUST NOT UPLOAD')) 'Automatic discovery included another launcher process transfer log'
    Check ($game.Available -eq 0 -and (Contents (Join-Path $ready.GameDir 'alut_proxy.status')) -eq 'mode=client loaded=0 initialized=0 ready=0 peer_ready=0') 'Diagnostics sent game packets or altered readiness without a running game'
    Check ((Contents (Join-Path $testDir 'client-notices.txt')).Contains('automatisch an den Gastgeber')) 'Client automatic protocol notice was not emitted'
    [IO.File]::WriteAllText((Join-Path $testDir 'stop'),'stop')
    Check ($client.WaitForExit(3000) -and $client.ExitCode -eq 0) 'Client protocol fixture did not stop normally'
    Write-Host "Automatic Internet protocol session: $script:passed checks passed (separate processes, six sources, append, transfer rediscovery, redaction, host notice and no game)."
} finally {
    if ($client -and -not $client.HasExited) { $client.Kill(); $client.WaitForExit() }
    if ($script:internetTunnel) { $script:internetTunnel.Dispose() }
    if ($game) { $game.Close() }
    Reset-InternetProtocolSharing
    $env:LOCALAPPDATA=$originalLocal
    $resolved=[IO.Path]::GetFullPath($testDir); $tempRoot=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if ($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

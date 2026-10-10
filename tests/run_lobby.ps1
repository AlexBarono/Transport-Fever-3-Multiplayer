# Real sockets and transfer workers; Steam, the game and firewall changes are mocked.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'launcher\launcher.ps1') -LibraryOnly
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'launcher\launcher.ps1'),[ref]$null,[ref]$null)
foreach($fn in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in 'Update-Fields','Write-LauncherLog'},$true)){Invoke-Expression $fn.Extent.Text}
. (Join-Path $root 'launcher\view.ps1')
. (Join-Path $root 'launcher\lobby-ui.ps1')
$Preview=$false
$form.Show(); [Windows.Forms.Application]::DoEvents()
$passed=0
function Check($ok,$message){if(-not $ok){throw $message}; $script:passed++}
function Wait-Until($test){$deadline=[DateTime]::UtcNow.AddSeconds(15); while(-not (& $test)){if([DateTime]::UtcNow -gt $deadline){throw 'Timeout'}; Start-Sleep -Milliseconds 30}}
function Free-Port {
    for($attempt=0;$attempt -lt 30;$attempt++){
        $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Server.ExclusiveAddressUse=$true; $l.Start(); $p=$l.LocalEndpoint.Port
        $u=New-Object Net.Sockets.UdpClient([Net.Sockets.AddressFamily]::InterNetwork); $u.Client.ExclusiveAddressUse=$true
        try {$u.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$p))); return $p} catch {$lastPortError=$_.Exception.Message} finally {$u.Close();$l.Stop()}
    }
    throw "No shared TCP/UDP port available: $lastPortError"
}
$base=Join-Path $env:TEMP ('tf3mp-lobby-test-'+[Guid]::NewGuid().ToString('N'))
$hostDir=Join-Path $base 'host'; $clientDir=Join-Path $base 'client'; $gameDir=Join-Path $base 'game'
foreach($dir in @($hostDir,$clientDir,$gameDir)){[void][IO.Directory]::CreateDirectory($dir)}
$savePath=Join-Path $hostDir 'Gemeinsam.sav'
$bytes=New-Object byte[] 2100003; (New-Object Random 42).NextBytes($bytes); [IO.File]::WriteAllBytes($savePath,$bytes)
[IO.File]::WriteAllText((Join-Path $clientDir 'Gemeinsam.sav'),'older world')
$manifest=[pscustomobject]@{Protocol=3; GameHash=('a'*64);PackageHash=('b'*64);ModsHash=('c'*64);Mods=@()}
$session=New-MultiplayerSession $manifest $savePath
$script:testGameRunning=$false; $script:launchCount=0; $script:resyncCount=0; $script:installCount=0
function Test-GameRunning{return $script:testGameRunning}
function Get-LauncherManifest{return $manifest}
function Get-SaveFolder{return $clientDir}
function Get-LaunchSession{return $session}
function Install-LauncherSettings{$script:installCount++; $script:installOK=$true; $ipBox.Text='127.0.0.1'; Update-LauncherLobby}
function Initialize-GameFirewall{}
function Install-GameAutoload{}
function Enable-InternetFirewall{return 'mocked'}
function Stop-LauncherGameForStart{if($script:testGameRunning){$script:testGameRunning=$false; $script:stopCount++}}
function Start-LauncherGame{$script:launchCount++; Update-LauncherLobby}
function Invoke-LiveResync{$script:resyncCount++}
$remote=$null; $hostTunnel=$null; $clientTunnel=$null
Register-LobbyInputEvents
try {
    $gameBox.Text=$gameDir; $portBox.Text="$(Free-Port)"; $ipBox.Text="127.0.0.1:$($portBox.Text)"
    $clientRadio.Checked=$true; $script:lobbyKey=""; Update-LauncherLobby
    $script:lobbyChanged=[DateTime]::UtcNow.AddSeconds(-5); Update-LauncherLobby
    Check ($script:lobbyJob -and $script:lobbyPhase -eq 'receiving') 'Joining did not automatically wait in a background worker'
    Check (-not $primary.Visible -and -not $recover.Visible -and -not $check.Visible -and -not $transfer.Visible) 'Joining still exposes manual transfer/start/resync/details buttons'
    Check ($joinStatus.Text -eq 'Warte auf Verbindung zum Gastgeber') 'Wrong initial joining status'
    $waitingHost=New-Object TF3MP.LobbyPresence([int]$portBox.Text)
    Wait-Until {$waitingHost.Connected}; Update-LauncherLobby
    Check ($joinStatus.Text -eq 'Warte auf Spielstand vom Gastgeber') 'Connected joining launcher does not wait for the save'
    $waitingHost.BeginTransfer(); $waitingHost.Dispose()
    $connection=$null
    Send-Savegame $savePath ([int]$portBox.Text) {param($t,$d,$n) if($script:lobbyJob.Async.IsCompleted -and $script:lobbyJob.Worker.Streams.Error.Count){throw $script:lobbyJob.Worker.Streams.Error[0]}; $false} -waitSeconds 15 -Session $session -KeepConnection ([ref]$connection) | Out-Null
    $remote=New-Object TF3MP.LobbyChannel($connection,$session.SessionId,$true)
    Wait-Until {$script:lobbyJob.Async.IsCompleted}; $script:testGameRunning=$true; Update-LauncherLobby
    Check ($script:stopCount -eq 1 -and -not $script:testGameRunning) 'Joining left the previous game running while preparing the shared start'
    Check ($script:lobbyPhase -eq 'ready' -and $script:installCount -eq 1) 'Receive did not automatically prepare the game'
    Check ((Get-SessionFileHash (Join-Path $clientDir 'Gemeinsam.sav')) -eq $session.SaveHash) 'Save not verified/committed'
    Check ([IO.File]::ReadAllText((Join-Path $clientDir 'Gemeinsam.sav.bak')) -eq 'older world') 'Automatic overwrite lost the backup'
    Check ($joinStatus.Text -eq 'Warte auf das Starten des Gastgebers') 'Joining does not wait for the host start'
    $script:seen=''; Wait-Until {$script:seen=$remote.Take(); $script:seen -eq 'READY|'}
    $start=[Guid]::NewGuid().ToString('N'); $remote.Send('START',$start); $remote.Send('START',$start)
    Wait-Until {Update-LauncherLobby; $script:launchCount -eq 1}
    Wait-Until {$remote.Take() -eq "STARTED|$start"}
    $remote.Send('START',$start); Start-Sleep -Milliseconds 100; Update-LauncherLobby
    Check ($script:launchCount -eq 1) 'Repeated START opened the game again'
    $script:testGameRunning=$true
    $resync=[Guid]::NewGuid().ToString('N'); $remote.Send('RESYNC',$resync); $remote.Send('RESYNC',$resync)
    Wait-Until {Update-LauncherLobby; $script:resyncCount -eq 1}
    Start-Sleep -Milliseconds 100; Update-LauncherLobby
    Check ($script:resyncCount -eq 1) 'Host resync was not automatic or executed twice'
    $script:liveMemory=New-LiveResyncMemory
    $status=@{mode='client';pid='fixture';ready='1';resync='';resync_peer='0'}
    [void](Get-LauncherResyncReason $status)
    $status.resync_peer='1'
    Check ($null -eq (Get-LauncherResyncReason $status) -and $script:liveMemory.PeerReq -eq '1') 'Bridge notification duplicates the lobby resync'
    $remote.Dispose(); Wait-Until {-not $script:lobby.Connected}; $status.resync_peer='2'
    Check ((Get-LauncherResyncReason $status).Kind -eq 'peer') 'Bridge fallback lost a host request after lobby disconnect'
    $script:testGameRunning=$false
    $remote.Dispose(); $remote=$null; Close-LauncherLobby

    # Host start stays disabled until the joining launcher confirms installation.
    $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Start()
    $peer=New-Object Net.Sockets.TcpClient; $peer.Connect('127.0.0.1',$l.LocalEndpoint.Port); $accepted=$l.AcceptTcpClient(); $l.Stop()
    $hostRadio.Checked=$true; Set-LobbyConnection $accepted $session $true; Update-Fields
    $remote=New-Object TF3MP.LobbyChannel($peer,$session.SessionId,$false)
    Check (-not $startBoth.Enabled -and $startBoth.Text -eq 'Spiel starten') 'Host can start before peer READY'
    $remote.Send('READY',''); Wait-Until {Update-LauncherLobby; $startBoth.Enabled}
    Check ($startBoth.Text -eq 'Spiel für beide starten' -and $startBoth.BackColor -eq $Accent) 'Host start was not enabled/green after READY'
    $badRole=$false; try {$remote.Send('START',[Guid]::NewGuid().ToString('N'))}catch{$badRole=$true}
    Check $badRole 'A joining launcher can send a host-only start command'
    Start-BothGames
    Check ($script:launchCount -eq 1 -and $script:lobbyPhase -eq 'starting') 'Host launched before peer start acknowledgement'
    $script:seen=''; Wait-Until {$script:seen=$remote.Take(); $script:seen -like 'START|*'}
    $remote.Send('STARTED',[Guid]::NewGuid().ToString('N')); Start-Sleep -Milliseconds 70; Update-LauncherLobby
    Check ($script:launchCount -eq 1) 'Wrong request ID launched the host'
    $remote.Send('STARTED',$script:lobbyStart); Wait-Until {Update-LauncherLobby; $script:launchCount -eq 2}
    $script:testGameRunning=$true; Update-Fields
    Check ($recover.Visible -and $recover.Enabled -and -not $check.Visible) 'Host resync unavailable after shared start'
    $script:testGameRunning=$false; $remote.Dispose(); $remote=$null; Close-LauncherLobby

    # Session-bound messages cannot drive a different lobby.
    $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Start()
    $peer=New-Object Net.Sockets.TcpClient; $peer.Connect('127.0.0.1',$l.LocalEndpoint.Port); $accepted=$l.AcceptTcpClient(); $l.Stop()
    $a=New-Object TF3MP.LobbyChannel($accepted,$session.SessionId,$true)
    $b=New-Object TF3MP.LobbyChannel($peer,([Guid]::NewGuid().ToString('N')),$false)
    try {$b.Send('READY',''); Wait-Until {-not $a.Connected}; Check (-not $a.Take()) 'Foreign session message accepted'} finally {$a.Dispose();$b.Dispose()}

    $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Start()
    $peer=New-Object Net.Sockets.TcpClient; $peer.Connect('127.0.0.1',$l.LocalEndpoint.Port); $accepted=$l.AcceptTcpClient(); $l.Stop()
    $a=New-Object TF3MP.LobbyChannel($accepted,$session.SessionId,$true)
    try {
        $wire=New-Object IO.BinaryWriter($peer.GetStream()); $wire.Write([int]2147483647); $wire.Flush()
        Wait-Until {-not $a.Connected}; Check (-not $a.Take()) 'Oversized control frame was accepted'
    } finally {$a.Dispose();$peer.Close()}

    $job=Start-LobbyReceiver $root '127.0.0.1' (Free-Port) $clientDir $manifest
    Start-Sleep -Milliseconds 500; $job.Progress.Cancel=$true
    Wait-Until {$job.Async.IsCompleted}
    $cancelled=$false; try {Complete-LobbyReceiver $job | Out-Null}catch{$cancelled=$_.Exception.Message -like '*Abgebrochen*'}
    Check $cancelled 'Waiting receiver could not be cancelled'

    $script:lobbyJob=Start-LobbyReceiver $root '127.0.0.1' (Free-Port) $clientDir $manifest
    $oldJob=$script:lobbyJob; $script:lobbyPhase='receiving'; $ipBox.Text='127.0.0.2'
    Check ($oldJob.Progress.Cancel -and -not $script:lobbyJob -and $script:lobbyPhase -eq 'idle') 'Editing the address leaves the old receive session active'
    Wait-Until {$oldJob.Async.IsCompleted}; try {Complete-LobbyReceiver $oldJob | Out-Null}catch{}
    $script:retiredLobbyJobs.Clear()
    $script:lobbyJob=Start-LobbyReceiver $root '127.0.0.1' (Free-Port) $clientDir $manifest
    $oldJob=$script:lobbyJob; $script:lobbyPhase='receiving'; Clear-LauncherJoinAddress
    Check ($ipBox.Text -eq '' -and $oldJob.Progress.Cancel -and -not $script:lobbyJob) 'Clear address did not cancel the waiting connection'
    Wait-Until {$oldJob.Async.IsCompleted}; try {Complete-LobbyReceiver $oldJob | Out-Null}catch{}
    $script:retiredLobbyJobs.Clear()

    # The retained save connection also carries lobby control over the existing TLS tunnel.
    Initialize-InternetTransport
    $port=Free-Port; $hostTunnel=[TF3MP.Internet.Tunnel]::StartHost(0,$port)
    $clientPort=Free-Port
    $clientTunnel=[TF3MP.Internet.Tunnel]::StartClient('::1',$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$clientPort)
    $job=Start-LobbyReceiver $root '127.0.0.1' $clientPort $clientDir $manifest
    $waitingHost=New-Object TF3MP.LobbyPresence($port)
    Wait-Until {$waitingHost.Connected}; $waitingHost.BeginTransfer(); $waitingHost.Dispose()
    $connection=$null; Send-Savegame $savePath $port {param($t,$d,$n) $false} -Session $session -KeepConnection ([ref]$connection) | Out-Null
    Wait-Until {$job.Async.IsCompleted}; $received=Complete-LobbyReceiver $job
    $a=New-Object TF3MP.LobbyChannel($connection,$session.SessionId,$true)
    $b=New-Object TF3MP.LobbyChannel($received.Connection,$session.SessionId,$false)
    try {
        $b.Send('READY',''); Wait-Until {$a.Take() -eq 'READY|'}
        $a.Send('START',$start); Wait-Until {$b.Take() -eq "START|$start"}
        $b.Send('STARTED',$start); Wait-Until {$a.Take() -eq "STARTED|$start"}
        $a.Send('RESYNC',$resync); Wait-Until {$b.Take() -eq "RESYNC|$resync"}
        Start-Sleep -Seconds 4
        Check ($a.Connected -and $b.Connected) 'TLS lobby heartbeat failed'
        Check ($clientTunnel.TcpBytes -gt $bytes.Length) 'Save/control did not use the TLS transport'
    } finally {$a.Dispose();$b.Dispose()}
    Write-Host "$passed lobby/automatic-launch checks passed, 0 failed (VPN sockets + IPv6 TLS; Steam mocked)"
} finally {
    if($remote){$remote.Dispose()}; Close-LauncherLobby
    if($clientTunnel){$clientTunnel.Dispose()}; if($hostTunnel){$hostTunnel.Dispose()}
    $form.Dispose()
}

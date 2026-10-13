$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\internet.ps1')
Initialize-InternetTransport
Add-Type -Path (Join-Path $PSScriptRoot 'internet_diagnostics_fixture.cs')
$script:passed=0
function Check($ok,$message) { if(-not $ok){throw $message}; $script:passed++ }
function Wait-Until($check,[int]$seconds=15) { $limit=[DateTime]::UtcNow.AddSeconds($seconds); while(-not (& $check)){if([DateTime]::UtcNow -gt $limit){throw 'Diagnostic fixture timed out'}; Start-Sleep -Milliseconds 50} }
function Free-Port {
    for($i=0;$i -lt 30;$i++) {
        $udp=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetwork); $udp.Client.ExclusiveAddressUse=$true
        $tcp=$null
        try {
            $port=Get-Random -Minimum 20000 -Maximum 45000
            $udp.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,$port))
            $tcp=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port); $tcp.Start(); return $port
        } catch {if($i -eq 29){throw}} finally {$udp.Close();if($tcp){$tcp.Stop()}}
    }
    throw 'No isolated fixture port'
}
function Contents($path) {
    if(-not (Test-Path -LiteralPath $path)){return ''}
    $file=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]'ReadWrite,Delete')
    $reader=[IO.StreamReader]::new($file)
    try {$reader.ReadToEnd()} finally {$reader.Dispose()}
}
$testDir=Join-Path $env:TEMP ('tf3mp-log-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDir) | Out-Null
$hostTunnel=$null;$clientTunnel=$null;$manual=$null;$game=$null;$udp=$null
try {
    $gamePort=Free-Port; $clientPort=Free-Port
    $hostTunnel=[TF3MP.Internet.Tunnel]::StartHost(0,$gamePort)
    $received=Join-Path $testDir 'received'; $hostTunnel.EnableDiagnosticReceiver($received)
    Check ($hostTunnel.DiagnosticDirectory -eq $received -and -not $hostTunnel.DiagnosticConnected) 'Receiver must be ready before the game starts'
    $session='a'*32; $source='b'*32
    foreach($wrong in @(@(('c'*64),$hostTunnel.Key),@($hostTunnel.Fingerprint,('c'*64)))) {
        $rejected=$false; try {$manual=[DiagnosticLogFixture]::new($hostTunnel.Port,$wrong[0],$wrong[1],$session)} catch {$rejected=$true} finally {if($manual){$manual.Dispose();$manual=$null}}
        Check $rejected 'LOG/1 accepted a wrong pin or key'
    }
    $manual=[DiagnosticLogFixture]::new($hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$session)
    $folder=$hostTunnel.DiagnosticDirectory
    $manualFolder=$folder
    Check ((Split-Path $folder -Parent) -eq $received -and (Split-Path $folder -Leaf) -match '^client-[0-9a-f]{32}$') 'Remote data controlled a host path'
    $data=[Text.Encoding]::UTF8.GetBytes("ACK lost fixture`n")
    $before=$hostTunnel.DiagnosticBytesReceived
    $manual.Send(1,$source,0,$data)
    Wait-Until {$hostTunnel.DiagnosticBytesReceived -eq $before+$data.Length}
    $manual.Dispose();$manual=$null
    Wait-Until {-not $hostTunnel.DiagnosticConnected}
    $manual=[DiagnosticLogFixture]::new($hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$session)
    Check ($manual.Append(1,$source,0,$data) -eq $data.Length) 'Reconnect did not acknowledge an already written chunk'
    Check ($hostTunnel.DiagnosticDirectory -eq $folder -and $hostTunnel.DiagnosticBytesReceived -eq $before+$data.Length -and (Contents (Join-Path $folder 'stdout.log')) -eq "ACK lost fixture`n") 'Lost ACK caused duplicated bytes or a new folder'
    $manual.Dispose();$manual=$null; Wait-Until {-not $hostTunnel.DiagnosticConnected}
    foreach($scenario in 0..4) {
        $manual=[DiagnosticLogFixture]::new($hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$session)
        Check ($manual.Malformed($scenario)) 'Malformed diagnostic frame accepted'
        $manual.Dispose();$manual=$null; Wait-Until {-not $hostTunnel.DiagnosticConnected}
    }
    Check (@(Get-ChildItem -LiteralPath $folder -File).Count -eq 2) 'Malformed kinds created a local file'
    $stdout=Join-Path $testDir 'stdout.txt'; $status=Join-Path $testDir 'status.txt'; $transfer=Join-Path $testDir 'transfer1.jsonl'
    [IO.File]::WriteAllText($stdout,"First UTF8: Häfen, Schiffe, Grüße`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($status,'mode=client ready=1')
    [IO.File]::WriteAllText($transfer,"old transfer started`nold transfer failed`n")
    $clientTunnel=[TF3MP.Internet.Tunnel]::StartClient('127.0.0.1',$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$clientPort)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $clientTunnel.SetDiagnosticSources(@('stdout','status','transfer'),@($stdout,$status,$transfer))
    Check ($watch.ElapsedMilliseconds -lt 1000) 'Source configuration blocked on I/O'
    Wait-Until {$clientTunnel.DiagnosticConnected -and $clientTunnel.GameChannelConnected -and $hostTunnel.DiagnosticDirectory -ne $folder}
    $folder=$hostTunnel.DiagnosticDirectory; $out=Join-Path $folder 'stdout.log'; $state=Join-Path $folder 'status.log'; $traces=Join-Path $folder 'transfer.log'
    Wait-Until {(Contents $out).Contains('Häfen, Schiffe, Grüße') -and (Contents $state).Contains('ready=1') -and (Contents $traces).Contains('old transfer failed')}
    Check ($clientTunnel.DiagnosticBytesSent -gt 0 -and $hostTunnel.DiagnosticConnected) 'Automatic early log upload missing'
    $game=[Net.Sockets.UdpClient]::new($gamePort);$game.Client.ReceiveTimeout=5000
    $udp=[Net.Sockets.UdpClient]::new(0);$udp.Client.ReceiveTimeout=5000
    $payload=[Text.Encoding]::ASCII.GetBytes('UDP stays independent of LOG/1')
    [void]$udp.Send($payload,$payload.Length,[Net.IPEndPoint]::new([Net.IPAddress]::Loopback,$clientPort))
    $from=[Net.IPEndPoint]::new([Net.IPAddress]::Any,0);$actual=$game.Receive([ref]$from)
    Check ([Text.Encoding]::ASCII.GetString($actual) -eq 'UDP stays independent of LOG/1' -and $clientTunnel.GameChannelConnected) 'Diagnostic upload blocked or substituted game readiness'
    # One invitation spans file reads and upload frames; it must be redacted as a complete line.
    $invitation='tf3mp-internet://[2001:db8::1]:47801/'+$hostTunnel.Fingerprint+'/'+$hostTunnel.Key
    [IO.File]::AppendAllText($stdout,('x'*32750)+' '+$invitation.Substring(0,40),[Text.UTF8Encoding]::new($false))
    Start-Sleep -Milliseconds 1000
    Check (-not (Contents $out).Contains('tf3mp-internet://')) 'Partial invitation leaked before newline'
    [IO.File]::AppendAllText($stdout,$invitation.Substring(40)+" standalone "+$hostTunnel.Key+' '+$hostTunnel.Fingerprint+"`nSECRET-END`n",[Text.UTF8Encoding]::new($false))
    Wait-Until {(Contents $out).Contains('SECRET-END')}
    $safe=Contents $out
    Check ($safe.Contains('[invitation redacted]') -and $safe.Contains('[key redacted]') -and $safe.Contains('[pin redacted]') -and -not $safe.Contains($hostTunnel.Key) -and -not $safe.Contains($hostTunnel.Fingerprint)) 'Invitation/key/pin redaction failed across a boundary'
    $statusTmp=$status+'.next';[IO.File]::WriteAllText($statusTmp,'mode=client ready=0');[IO.File]::Replace($statusTmp,$status,($status+'.old'))
    Wait-Until {(Contents $state).Contains('ready=0')}
    Check ((Contents $state).Contains('ready=1') -and (Contents $state).Contains('TF3MP status UTC')) 'Atomic same-size status snapshot was not preserved'
    # Retiring paths must drain unread lines before changing to a new transfer attempt.
    [IO.File]::AppendAllText($transfer,"last failure before path change`n")
    $nextTransfer=Join-Path $testDir 'transfer2.jsonl';[IO.File]::WriteAllText($nextTransfer,"new transfer complete`n")
    $clientTunnel.SetDiagnosticSources(@('stdout','status','transfer'),@($stdout,$status,$nextTransfer))
    Wait-Until {(Contents $traces).Contains('new transfer complete')}
    Check ((Contents $traces).Contains('last failure before path change') -and (Contents $traces).IndexOf('last failure before path change') -lt (Contents $traces).IndexOf('new transfer complete')) 'Changed source path discarded previous failure lines'
    [IO.File]::WriteAllText($stdout,"TRUNCATED NEW RUN`n")
    Wait-Until {(Contents $out).Contains('TRUNCATED NEW RUN')}
    Check ((Contents $out).Contains('source replaced/truncated')) 'Source truncation was not marked'
    $newStdout=$stdout+'.new';[IO.File]::WriteAllText($newStdout,"REPLACED NEW RUN`n");[IO.File]::Replace($newStdout,$stdout,($stdout+'.old'))
    Wait-Until {(Contents $out).Contains('REPLACED NEW RUN')}
    Check ((Contents $out).Contains('TRUNCATED NEW RUN')) 'Source replacement overwrote earlier host diagnostics'
    # Large valid B5 payload lines survive; larger-than-limit lines are clearly omitted.
    [IO.File]::AppendAllText($stdout,'B5 '+('z'*260000)+" BIG-LINE-END`n"+('q'*530000)+"`nAFTER-LIMIT`n")
    Wait-Until {(Contents $out).Contains('AFTER-LIMIT')} 35
    Check ((Contents $out).Contains('BIG-LINE-END') -and (Contents $out).Contains('oversized line omitted (>512 KiB)') -and -not (Contents $out).Contains('q'*100)) 'Long line preservation/omission bounds failed'
    foreach($entry in @(@('unknown',$stdout),@('stdout',''))) {
        $rejected=$false;try {$clientTunnel.SetDiagnosticSources(@($entry[0]),@($entry[1]))}catch{$rejected=$true};Check $rejected 'Invalid local source configuration accepted'
    }
    $clientTunnel.Dispose();$clientTunnel=$null;Wait-Until {-not $hostTunnel.DiagnosticConnected}
    Wait-Until {-not $hostTunnel.GameChannelConnected}
    Check (-not $hostTunnel.GameChannelConnected) 'Disposed collector retained the game channel'
    # Exercise retention without sending 16 MiB through the intentionally throttled collector.
    $retained=Join-Path $testDir 'retention.log';$block=[Text.Encoding]::ASCII.GetBytes(('r'*32742)+"`n")
    [DiagnosticLogFixture]::ExerciseRetention($retained,$block,530)
    $sizes=(Get-Item -LiteralPath $retained).Length+(Get-Item -LiteralPath ($retained+'.previous')).Length
    Check ($sizes -le 16MB -and (Contents $retained).StartsWith('[TF3MP diagnostics: older bytes rotated')) 'Host retention limit/rotation gap marker failed'
    # Receiver disk errors stay outside the game's LastError and UDP state.
    $locked=Join-Path $manualFolder 'stdout.log';$holder=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $oldError=$hostTunnel.LastError
        $manual=[DiagnosticLogFixture]::new($hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$session)
        $failed=$false;try {[void]$manual.Append(1,$source,$data.Length,[Text.Encoding]::ASCII.GetBytes("locked file append`n"))}catch{$failed=$true}
        $manual.Dispose();$manual=$null;Wait-Until {-not $hostTunnel.DiagnosticConnected}
        Check ($failed -and $hostTunnel.DiagnosticLastError -ne '' -and $hostTunnel.LastError -eq $oldError) 'Receiver disk error contaminated game errors or was hidden'
    } finally {$holder.Dispose()}
    $blockedRoot=Join-Path $testDir 'not-a-directory';[IO.File]::WriteAllText($blockedRoot,'file blocks the receiver folder')
    $badHost=[TF3MP.Internet.Tunnel]::StartHost(0,(Free-Port))
    try {
        $badHost.EnableDiagnosticReceiver($blockedRoot)
        $failed=$false;try {$manual=[DiagnosticLogFixture]::new($badHost.Port,$badHost.Fingerprint,$badHost.Key,$session)}catch{$failed=$true}finally{if($manual){$manual.Dispose();$manual=$null}}
        Wait-Until {$badHost.DiagnosticLastError -ne ''}
        Check ($failed -and $badHost.LastError -eq '' -and $badHost.Running) 'Invalid receiver root blocked or corrupted the main tunnel'
    } finally {$badHost.Dispose()}
    Write-Host "Internet diagnostics: $script:passed checks passed (TLS authentication, automatic collector, lost ACK, bounds, redaction, retirement, snapshots and independent UDP)."
} finally {
    if($manual){$manual.Dispose()};if($clientTunnel){$clientTunnel.Dispose()};if($hostTunnel){$hostTunnel.Dispose()};if($udp){$udp.Close()};if($game){$game.Close()}
    $resolved=[IO.Path]::GetFullPath($testDir);$temp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}

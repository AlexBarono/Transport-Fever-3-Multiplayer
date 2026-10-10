param([switch]$SkipSave, [ValidateSet('127.0.0.1','::1')][string]$TunnelAddress = '::1', [switch]$CheckRouter, [switch]$EncryptedSaves)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\internet.ps1')
. (Join-Path $root 'tools\save-transfer.ps1')
Initialize-InternetTransport
$passed=0
function Check($ok,$message) { if(-not $ok) { throw $message }; $script:passed++ }
function Wait-Until($check) { $deadline=[DateTime]::UtcNow.AddSeconds(12); while(-not (& $check)) { if([DateTime]::UtcNow -gt $deadline) { throw 'Timeout' }; Start-Sleep -Milliseconds 50 } }
function Free-Port {
    for($attempt=0;$attempt -lt 30;$attempt++) {
        $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Server.ExclusiveAddressUse=$true; $l.Start(); $p=$l.LocalEndpoint.Port
        $u=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetwork); $u.Client.ExclusiveAddressUse=$true
        try { $u.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$p))); return $p } catch {} finally { $u.Close(); $l.Stop() }
    }
    throw 'No shared TCP/UDP test port available'
}
$pin='a'*64; $key='b'*64
foreach($address in @('127.0.0.1','100.80.12.4','::1','2001:db8::1')) {
    $invite=New-InternetInvitation $address 47801 $pin $key
    $value=Read-InternetInvitation $invite
    Check ($value.Address -eq ([Net.IPAddress]::Parse($address)).ToString() -and $value.Port -eq 47801 -and $value.Key -eq $key -and $value.Fingerprint -eq $pin) 'Invitation roundtrip'
}
foreach($bad in @(('tf3mp-internet://example.org:47801/'+$pin+'/'+$key),('tf3mp-internet://127.1:47801/'+$pin+'/'+$key),
    ('tf3mp-internet://0.0.0.0:47801/'+$pin+'/'+$key),('tf3mp-internet://[::]:47801/'+$pin+'/'+$key),
    ('tf3mp-internet://[fe80::1]:47801/'+$pin+'/'+$key),('tf3mp-internet://[ff02::1]:47801/'+$pin+'/'+$key),
    ('tf3mp-internet://127.0.0.1:1/'+$pin+'/'+$key),('tf3mp-internet://127.0.0.1:99999/'+$pin+'/'+$key),
    ('tf3mp-internet://127.0.0.1:47801/'+$pin+'/x'),('tf3mp-internet://user@127.0.0.1:47801/'+$pin+'/'+$key))) {
    $failed=$false; try { [void](Read-InternetInvitation $bad) } catch { $failed=$true }; Check $failed 'Malformed invitation accepted'
}
foreach($entry in @(@('192.168.1.1',$false),@('100.64.1.1',$false),@('fd51::1',$false),@('fe80::1',$false),@('2001:0::1',$false),@('2606:4700::1',$true),@('8.8.8.8',$true))) {
    Check ((Test-PublicInternetAddress ([Net.IPAddress]::Parse($entry[0]))) -eq $entry[1]) 'Public IP classification'
}
$rule=Get-InternetFirewallArguments 47801 (Get-Process -Id $PID).Path
Check ($rule.Protocol -eq 'TCP' -and $rule.LocalPort -eq 47801 -and $rule.Program -eq (Get-Process -Id $PID).Path -and $rule.Direction -eq 'Inbound') 'Firewall scope'

$gameReservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,(Free-Port)); $gameReservation.Server.ExclusiveAddressUse=$true; $gameReservation.Start()
$hostPort=$gameReservation.LocalEndpoint.Port
$hostTunnel=[TF3MP.Internet.Tunnel]::StartHost(0,$hostPort)
$clientPort=0
$clientTunnel=$null; $udp=$null; $game=$null; $receiver=$null
$testDir=Join-Path $env:TEMP ('tf3mp-internet-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDir) | Out-Null
try {
    [TF3MP.Internet.Tunnel]::Probe('127.0.0.1',$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key); $passed++
    [TF3MP.Internet.Tunnel]::Probe('::1',$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key); $passed++
    foreach($wrong in @(@($pin,$hostTunnel.Key),@($hostTunnel.Fingerprint,$key))) {
        $failed=$false; try { [TF3MP.Internet.Tunnel]::Probe('::1',$hostTunnel.Port,$wrong[0],$wrong[1]) } catch { $failed=$true }; Check $failed 'Wrong certificate/key accepted'
    }
    Check ($hostTunnel.Rejected -ge 1) 'Rejected invitation not counted'
    # Begin tunnelling before TF3 exists, then create the game endpoint later.
    $clientPort=Free-Port
    $clientTunnel=[TF3MP.Internet.Tunnel]::StartClient($TunnelAddress,$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$clientPort,[bool]$EncryptedSaves)
    $gameReservation.Stop()
    Wait-Until { $clientTunnel.GameChannelConnected }
    Start-Sleep -Seconds 16
    Check ($clientTunnel.GameChannelConnected -and $hostTunnel.GameChannelConnected -and $clientTunnel.Reconnects -eq 0) 'Idle TLS heartbeat did not keep the game channel healthy'
    $udp=New-Object Net.Sockets.UdpClient(0); $udp.Client.ReceiveTimeout=7000
    $target=New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$clientPort)
    $bytes=[Text.Encoding]::ASCII.GetBytes('TF3MP/1 HELLO before_game')
    [void]$udp.Send($bytes,$bytes.Length,$target); Start-Sleep -Milliseconds 150
    $game=New-Object Net.Sockets.UdpClient($hostPort); $game.Client.ReceiveTimeout=7000
    foreach($size in @(32,1200,65000)) {
        $bytes=New-Object byte[] $size; (New-Object Random 13).NextBytes($bytes)
        [void]$udp.Send($bytes,$bytes.Length,$target)
        $from=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0); $got=$game.Receive([ref]$from)
        Check ([TF3MP.Internet.Tunnel]::Hash($got) -eq [TF3MP.Internet.Tunnel]::Hash($bytes)) 'UDP host payload corrupted'
        [void]$game.Send($got,$got.Length,$from)
        $reply=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0); $answer=$udp.Receive([ref]$reply)
        Check ([TF3MP.Internet.Tunnel]::Hash($answer) -eq [TF3MP.Internet.Tunnel]::Hash($bytes) -and $reply.Port -eq $clientPort) 'UDP client reply corrupted'
    }
    Check ($clientTunnel.UdpPackets -ge 6 -and $hostTunnel.UdpPackets -ge 6) 'UDP counters missing'
    $nativePeerPort=$from.Port
    $clientTunnel.Dispose(); Wait-Until { -not $hostTunnel.GameChannelConnected }
    [TF3MP.Internet.Tunnel]::Probe('127.0.0.1',$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key)
    $clientTunnel=[TF3MP.Internet.Tunnel]::StartClient($TunnelAddress,$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$clientPort,[bool]$EncryptedSaves)
    Wait-Until { $clientTunnel.GameChannelConnected }
    $bytes=[Text.Encoding]::ASCII.GetBytes('TF3MP/1 HELLO reconnected'); [void]$udp.Send($bytes,$bytes.Length,$target)
    $from=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0); $got=$game.Receive([ref]$from)
    Check ([Text.Encoding]::ASCII.GetString($got) -eq 'TF3MP/1 HELLO reconnected') 'Reconnect lost UDP channel'
    Check ($from.Port -eq $nativePeerPort) 'Internet reconnect changed the native pinned UDP peer'
    $waiting=New-Object Net.Sockets.TcpClient
    try {
        $waiting.Connect('127.0.0.1',$clientPort); $waiting.ReceiveTimeout=7000
        $reader=New-Object IO.BinaryReader($waiting.GetStream())
        Check ($reader.ReadString() -eq 'TF3MPWAIT') 'Internet gateway hid the not-yet-ready save host'
    } finally { $waiting.Close() }
    Add-Type -TypeDefinition @'
using System; using System.IO; using System.Net; using System.Net.Sockets; using System.Security.Cryptography; using System.Threading.Tasks;
public static class InternetPlainAuthFixture {
    static string Read(Stream s) { string result=""; for(int i=0;i<160;i++){int b=s.ReadByte(); if(b<0) throw new EndOfStreamException(); if(b==10) return result; result+=(char)b;} throw new IOException(); }
    static void Line(Stream s,string value) { byte[] b=System.Text.Encoding.ASCII.GetBytes(value+"\n"); s.Write(b,0,b.Length); }
    static string Mac(string key,string nonce,string other,string pin) { using(HMACSHA256 h=new HMACSHA256(System.Text.Encoding.ASCII.GetBytes(key))) return BitConverter.ToString(h.ComputeHash(System.Text.Encoding.ASCII.GetBytes("TF3MP-PLAIN/1|TCP|client|"+nonce+"|"+other+"|"+pin))).Replace("-","").ToLowerInvariant(); }
    public static bool Refuse(int port,string key,string pin,bool replay) {
        string nonce=new string('a',64), proof=null;
        if(replay) using(TcpClient c=new TcpClient("127.0.0.1",port)) {
            c.ReceiveTimeout=7000; Stream s=c.GetStream(); Line(s,"TF3MP-PLAIN/1"); Line(s,nonce);
            string challenge=Read(s); Read(s); proof=Mac(key,nonce,challenge,pin);
        }
        using(TcpClient c=new TcpClient("127.0.0.1",port)) {
            c.ReceiveTimeout=7000; Stream s=c.GetStream(); Line(s,"TF3MP-PLAIN/1"); Line(s,nonce);
            string challenge=Read(s); Read(s); Line(s,replay ? proof : Mac(key,nonce,challenge,pin));
            try { return s.ReadByte()==-1; } catch(IOException) {return true;}
        }
    }
}
public static class InternetHalfCloseFixture {
    public static Task IdleReply(int port) {
        TcpListener listener=new TcpListener(IPAddress.Loopback,port); listener.Start();
        return Task.Factory.StartNew(delegate {
            try { using(TcpClient c=listener.AcceptTcpClient()) {
                Stream s=c.GetStream(); if(s.ReadByte()!=42) throw new IOException("Bad idle request");
                System.Threading.Thread.Sleep(9500); s.WriteByte(43);
            }} finally { listener.Stop(); }
        });
    }
    public static Task Start(int port) {
        TcpListener listener=new TcpListener(IPAddress.Loopback,port); listener.Start();
        return Task.Factory.StartNew(delegate {
            try { using(TcpClient c=listener.AcceptTcpClient()) {
                c.ReceiveTimeout=7000; Stream s=c.GetStream(); MemoryStream input=new MemoryStream(); byte[] b=new byte[1024]; int n;
                while((n=s.Read(b,0,b.Length))>0) input.Write(b,0,n);
                using(SHA256 sha=SHA256.Create()) { byte[] hash=sha.ComputeHash(input.ToArray()); s.Write(hash,0,hash.Length); }
            }} finally { listener.Stop(); }
        });
    }
}
'@
    $refusals=$hostTunnel.Rejected
    Check ([InternetPlainAuthFixture]::Refuse($hostTunnel.Port,('b'*64),$hostTunnel.Fingerprint,$false)) 'Wrong plain TCP invitation key accepted'
    Check ([InternetPlainAuthFixture]::Refuse($hostTunnel.Port,$hostTunnel.Key,$hostTunnel.Fingerprint,$true)) 'Replayed plain TCP proof accepted'
    Wait-Until {$hostTunnel.Rejected -ge $refusals+2}
    Check ($clientTunnel.InvitationId -eq $hostTunnel.InvitationId) 'Invitation identifiers differ'
    # The control channel is silent while the data sockets transfer the save.
    $idleReply=[InternetHalfCloseFixture]::IdleReply($hostPort)
    $socket=New-Object Net.Sockets.TcpClient
    try {
        $socket.Connect('127.0.0.1',$clientPort); $socket.ReceiveTimeout=20000
        $stream=$socket.GetStream(); $stream.WriteByte(42)
        Check ($stream.ReadByte() -eq 43) 'Idle save control socket closed before the final reply'
        Check ($idleReply.Wait(12000) -and -not $idleReply.IsFaulted) 'Idle responder failed'
    } finally {$socket.Close()}
    $halfClose=[InternetHalfCloseFixture]::Start($hostPort)
    $request=[Text.Encoding]::ASCII.GetBytes('decline save; retain the final reply')
    $socket=New-Object Net.Sockets.TcpClient
    try {
        $socket.Connect('127.0.0.1',$clientPort); $socket.ReceiveTimeout=7000; $stream=$socket.GetStream()
        $stream.Write($request,0,$request.Length); $socket.Client.Shutdown([Net.Sockets.SocketShutdown]::Send)
        $reply=New-Object IO.MemoryStream; $buffer=New-Object byte[] 100
        while(($n=$stream.Read($buffer,0,$buffer.Length)) -gt 0) { $reply.Write($buffer,0,$n) }
        Check (([BitConverter]::ToString($reply.ToArray()).Replace('-','').ToLowerInvariant()) -eq [TF3MP.Internet.Tunnel]::Hash($request)) 'Directional EOF lost the final response'
        Check ($halfClose.Wait(10000) -and -not $halfClose.IsFaulted) 'Half-close responder did not finish'
    } finally { $socket.Close() }
    if(-not $SkipSave) {
        $sendDir=Join-Path $testDir 'host'; $receiveDir=Join-Path $testDir 'client'; [IO.Directory]::CreateDirectory($sendDir) | Out-Null; [IO.Directory]::CreateDirectory($receiveDir) | Out-Null
        $save=Join-Path $sendDir 'Internet.sav'; $photo=Join-Path $sendDir 'Internet.jpg'
        $bytes=New-Object byte[] (16MB); (New-Object Random 23).NextBytes($bytes); [IO.File]::WriteAllBytes($save,$bytes); [IO.File]::WriteAllBytes($photo,$bytes[0..9999])
        [IO.File]::WriteAllText((Join-Path $receiveDir 'Internet.sav'),'older save')
        $manifest=[pscustomobject]@{ Protocol=3; GameHash='a'*64; PackageHash='b'*64; ModsHash='c'*64; Mods=@() }
        $session=New-MultiplayerSession $manifest $save
        $manifestPath=Join-Path $testDir 'manifest.json'; $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        $output=Join-Path $testDir 'received.json'; $errors=Join-Path $testDir 'errors.txt'
        $waitObserved=Join-Path $testDir 'wait-observed.txt'
        $child=Join-Path $testDir 'receive.ps1'
        $childScript=@"
`$ErrorActionPreference='Stop'
. '$((Join-Path $root 'tools\save-transfer.ps1').Replace("'","''"))'
`$script:SaveTransferLogDirectory='$($testDir.Replace("'","''"))'
try {
  `$m=Get-Content -LiteralPath '$($manifestPath.Replace("'","''"))' -Raw | ConvertFrom-Json
  `$result=Receive-Savegame '127.0.0.1' $clientPort '$($receiveDir.Replace("'","''"))' { param(`$t,`$d,`$n) if(`$t -like 'Warte auf den Gastgeber*'){[IO.File]::WriteAllText('$($waitObserved.Replace("'","''"))','yes')}; `$false } { Start-Sleep -Milliseconds 9500; `$true } -LocalManifest `$m -WaitSeconds 15
  `$script:LastSaveTransfer | ConvertTo-Json | Set-Content -LiteralPath '$($output.Replace("'","''"))' -Encoding UTF8
} catch { `$_ | Out-String | Set-Content -LiteralPath '$($errors.Replace("'","''"))'; exit 1 }
"@
        [IO.File]::WriteAllText($child,$childScript,(New-Object Text.UTF8Encoding($true)))
        $script:SaveTransferLogDirectory=$testDir
        $receiver=Start-Process (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$child`"")
        Wait-Until { (Test-Path -LiteralPath $waitObserved) -or $receiver.HasExited }
        Check (Test-Path -LiteralPath $waitObserved) 'Delayed Internet host did not retain the receiver waiting policy'
        $result=Send-Savegame $save $hostPort { param($t,$d,$n) $false } -Session $session -waitSeconds 20 -MaxAttempts 1
        Check ($receiver.WaitForExit(20000) -and $receiver.ExitCode -eq 0) ('Internet save receiver failed: '+$(if(Test-Path $errors){Get-Content $errors -Raw}))
        Check ((Get-FileHash $save).Hash -eq (Get-FileHash (Join-Path $receiveDir 'Internet.sav')).Hash) 'Save hash mismatch'
        Check ((Get-FileHash $photo).Hash -eq (Get-FileHash (Join-Path $receiveDir 'Internet.jpg')).Hash) 'Preview hash mismatch'
        Check ([IO.File]::ReadAllText((Join-Path $receiveDir 'Internet.sav.bak')) -eq 'older save') 'Slow final confirmation lost the backup'
        $trace=@(Get-Content -LiteralPath $script:SaveTransferTrace.Path | ForEach-Object {$_ | ConvertFrom-Json})
        Check (@($trace | Where-Object event -eq 'attempt_failed').Count -eq 0) 'Slow final confirmation forced a retransmission'
        $stats=Get-Content $output -Raw | ConvertFrom-Json
        Check ($stats.Streams -eq 4 -and $stats.Method -eq 'continuous') 'Four save streams not used'
        Check ($hostTunnel.TcpBytes -ge 16MB -and $clientTunnel.TcpBytes -ge 16MB) 'Transfer bytes missing'
        Check ($clientTunnel.SaveEncrypted -eq [bool]$EncryptedSaves) 'Wrong save encryption mode'
        if($EncryptedSaves){Check ($hostTunnel.TlsConnections -ge 5) 'TLS compatibility path not exercised'}
        else {Check ($hostTunnel.ClearConnections -ge 5 -and $hostTunnel.TlsConnections -eq 0) 'Save bytes still use TLS'}
    }
    if($CheckRouter) {
        $lan=Get-InternetLanIPv4; $owner='TF3MP test '+[Guid]::NewGuid().ToString('N')
        try {
            $mapping=Invoke-InternetUpnp Add $hostTunnel.Port $lan $owner
            Check ($mapping.Port -eq $hostTunnel.Port) 'Router did not return the requested mapping'
            Write-Host ('Router mapping created; public WAN IPv4: '+(Test-PublicInternetAddress ([Net.IPAddress]::Parse($mapping.Address)))+'. External inbound reachability still needs the other PC.')
        } finally { Invoke-InternetUpnp Remove $hostTunnel.Port $lan $owner }
        $query=Invoke-InternetUpnp Query $hostTunnel.Port $lan $owner
        Check (-not $query.Occupied) 'Test router mapping was not removed'
    }
    Write-Host "Internet transport: $passed checks passed ($TunnelAddress, save TLS=$EncryptedSaves; authenticated invitation, idle control, UDP, half-close and four save streams)."
} catch { Write-Host $_.ScriptStackTrace; Write-Host ('Passed: '+$passed+' Ports: '+$hostPort+'/'+$hostTunnel.Port+'/'+$clientPort+' Accepted: '+$hostTunnel.Accepted+' KeysEqual: '+($hostTunnel.Key -eq $clientTunnel.Key)+' PinsEqual: '+($hostTunnel.Fingerprint -eq $clientTunnel.Fingerprint)+' Rejected: '+$hostTunnel.Rejected+' Host: '+$hostTunnel.GameChannelConnected+' '+$hostTunnel.LastError+' Client: '+$clientTunnel.GameChannelConnected+' '+$clientTunnel.LastError); throw } finally {
    $gameReservation.Stop()
    if($receiver -and -not $receiver.HasExited) { $receiver.Kill(); $receiver.WaitForExit() }
    if($clientTunnel) { $clientTunnel.Dispose() }; $hostTunnel.Dispose(); if($udp) { $udp.Close() }; if($game) { $game.Close() }
    $resolved=[IO.Path]::GetFullPath($testDir); $temp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

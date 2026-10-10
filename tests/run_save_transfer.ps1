# Offline-Test der Spielstand-Übertragung (tools\save-transfer.ps1) über 127.0.0.1.
# Aufruf aus dem Hauptordner: pwsh -File tests\run_save_transfer.ps1  (oder powershell -File ...)
[CmdletBinding()]
param([string]$Only = '', [int]$Port = 47950)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\save-transfer.ps1')

$passed = 0; $failed = 0
function Test($name, $fn) {
	if ($Only -and $name -notlike $Only) { return }
	try { & $fn; $script:passed++ } catch { $script:failed++; Write-Host "FAIL ${name}: $($_.Exception.Message)" }
}
function Assert($cond, $msg) { if (-not $cond) { throw "assertion failed: $msg" } }

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("tf3mp-save-test-" + [Guid]::NewGuid().ToString('N'))
$hostDir = Join-Path $base 'host'; $clientDir = Join-Path $base 'client'
New-Item -ItemType Directory -Force $hostDir, $clientDir | Out-Null
$script:SaveTransferLogDirectory = Join-Path $base 'metrics'
$rng = New-Object System.Random 7
function New-RandomFile($path, $size) {
	$bytes = New-Object byte[] $size
	$rng.NextBytes($bytes)
	[System.IO.File]::WriteAllBytes($path, $bytes)
}
New-RandomFile (Join-Path $hostDir 'Det.sav') 3000000
New-RandomFile (Join-Path $hostDir 'Det.jpg') 80000

# Der Mitspieler läuft in einem zweiten PowerShell-Prozess.
$shell = (Get-Process -Id $PID).Path
$testPeers = New-Object System.Collections.Generic.List[System.Diagnostics.Process]
function Start-Receiver($answer, $manifest = $null, $preparedPath = '', [int]$Connections = 4, [string]$StatsPath = '', [string]$TracePath = '', [bool]$Continuous = $true) {
	$manifestPath = ''
	if ($manifest) { $manifestPath = Join-Path $base 'receiver-manifest.json'; $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 }
	$script = @"
`$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false)
. '$((Join-Path $root 'tools\save-transfer.ps1').Replace("'", "''"))'
`$script:SaveTransferLogDirectory = '$((Join-Path $base 'receiver-metrics').Replace("'", "''"))'
try {
	Start-Sleep -Milliseconds 500
	`$manifest = if ('$($manifestPath.Replace("'", "''"))') { Get-Content -LiteralPath '$($manifestPath.Replace("'", "''"))' -Raw | ConvertFrom-Json } else { `$null }
	`$out = [pscustomobject]@{ Text = '' }  # wie das Textfeld im Launcher
	`$t = Receive-Savegame '127.0.0.1' $port '$($clientDir.Replace("'", "''"))' { param(`$a, `$b, `$c) `$out.Text = `$a; if ('$($TracePath.Replace("'", "''"))') { [IO.File]::AppendAllText('$($TracePath.Replace("'", "''"))', "`$a`r`n") }; `$false } { param(`$q) `$$answer } -LocalManifest `$manifest -Connections $Connections -Continuous `$$Continuous
	if ('$($StatsPath.Replace("'", "''"))') { `$script:LastSaveTransfer | ConvertTo-Json | Set-Content -LiteralPath '$($StatsPath.Replace("'", "''"))' -Encoding UTF8 }
	if ('$($preparedPath.Replace("'", "''"))' -and `$t.Session) { Save-PreparedSession -Path '$($preparedPath.Replace("'", "''"))' -Session `$t.Session -SavePath `$t.SavePath | Out-Null }
	`$text = if (`$t.Session) { `$t.Text } else { `$t }
	Write-Output "OK `$text"
} catch { Write-Output "ERROR `$(`$_.Exception.Message)" }
"@
	$file = Join-Path $base 'receiver.ps1'
	Set-Content -Path $file -Value $script -Encoding UTF8
	$out = Join-Path $base ('receiver-' + [Guid]::NewGuid().ToString('N') + '.txt')
	$hidden = @{}
	if ($IsWindows -ne $false) { $hidden.WindowStyle = 'Hidden' }  # Windows PowerShell 5.1 kennt $IsWindows nicht
	$p = Start-Process -FilePath $shell -ArgumentList '-NoProfile', '-File', $file -RedirectStandardOutput $out -PassThru @hidden
	$testPeers.Add($p)
	return @{ Process = $p; Out = $out }
}
function Wait-Receiver($r) {
	if (-not $r.Process.WaitForExit(60000)) { $r.Process.Kill(); throw 'receiver hangs' }
	return (Get-Content $r.Out -Raw -Encoding UTF8).Trim()
}
$ticks = 0
# Wie im Launcher schreibt der Fortschritt in ein Textfeld $out. Im ersten VPN-Versuch hieß der
# Dateistrom des Mitspielers ebenfalls $out, und der Callback schrieb in den falschen.
$out = [pscustomobject]@{ Text = '' }
$tick = { param($text, $done, $total) $script:ticks++; $out.Text = $text; $false }

Test 'a save and its preview arrive intact' {
	$r = Start-Receiver 'true'
	$answer = Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30
	$got = Wait-Receiver $r
	Assert ($got -like "OK Spielstand 'Det' gespeichert*") $got
	Assert ($answer -like "Spielstand 'Det' gespeichert*") $answer
	foreach ($f in 'Det.sav', 'Det.jpg') {
		Assert (Test-SameBytes (Get-FileSha256 (Join-Path $hostDir $f)) (Get-FileSha256 (Join-Path $clientDir $f))) $f
	}
	Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'no .part left'
	Assert ($ticks -gt 0) "progress ticks $ticks"
}

Test 'payload progress is throttled but initial and final bytes are shown' {
	$seen = @{ Calls = 0; First = -1; Last = -1 }
	$meter = New-SaveProgress
	$paint = { param($text, $done, $total) if (-not $seen.Calls) { $seen.First = $done }; $seen.Last = $done; $seen.Calls++; $false }
	for ($i = 1; $i -le 1500; $i++) { Write-SaveProgress $meter $paint 'payload' $i 1500 | Out-Null }
	Assert ($seen.First -eq 1 -and $seen.Last -eq 1500) 'first/final progress'
	Assert ($seen.Calls -lt 20) "avoids per-chunk UI repaint ($($seen.Calls) calls)"
	$meter.LastMs = -100
	Assert (Write-SaveProgress $meter { $true } 'payload' 1 2) 'cancel preserved'
}

function New-StalledTransferPair {
	$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
	$listener.Server.ReceiveBufferSize = 1024
	$listener.Start()
	try {
		$client = New-Object Net.Sockets.TcpClient
		$client.SendBufferSize = 1024
		$client.Connect('127.0.0.1', $listener.LocalEndpoint.Port)
		$server = $listener.AcceptTcpClient()
		return @{ Client = $client; Server = $server }
	} finally { $listener.Stop() }
}

Test 'the receiver can cancel while a connected sender stops delivering bytes' {
	$pair = New-StalledTransferPair
	try {
		$err = ''; $started = [DateTime]::UtcNow
		try { Read-SaveData $pair.Client.GetStream() (New-Object byte[] 1024) 1024 (New-SaveProgress) { $true } 'Empfange ...' 0 1024 | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -eq 'Abgebrochen.') $err
		Assert (([DateTime]::UtcNow - $started).TotalSeconds -lt 2) 'cancel is responsive without socket data'
	} finally { $pair.Client.Close(); $pair.Server.Close() }
}

Test 'a receiver that cannot make progress reaches the bounded network timeout' {
	$fakeStream = [pscustomobject]@{ Closed = $false; Operation = [pscustomobject]@{ AsyncWaitHandle = (New-Object Threading.ManualResetEvent($false)) } }
	$fakeStream | Add-Member ScriptMethod BeginRead { param($buffer, $offset, $count, $callback, $state) return $this.Operation }
	$fakeStream | Add-Member ScriptMethod EndRead { throw 'not completed' }
	$fakeStream | Add-Member ScriptMethod Close { $this.Closed = $true }
	$err = ''; $started = [DateTime]::UtcNow
	try { Read-SaveData $fakeStream (New-Object byte[] 100) 100 (New-SaveProgress) { $false } 'Empfange ...' 0 100 -TimeoutSeconds 0 | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*keine Datenübertragung*') $err
	Assert ($fakeStream.Closed -and ([DateTime]::UtcNow - $started).TotalSeconds -lt 2) 'timed out pending read is cancelled'
}

Test 'the same save again needs no question' {
	$r = Start-Receiver 'false'
	Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 | Out-Null
	$got = Wait-Receiver $r
	Assert ($got -like 'OK *') $got
	Assert (-not (Test-Path (Join-Path $clientDir 'Det.sav.bak'))) 'no backup'
}

Test 'a different save with the same name stays when the player says no' {
	New-RandomFile (Join-Path $hostDir 'Det.sav') 2000000
	$before = Get-FileSha256 (Join-Path $clientDir 'Det.sav')
	$r = Start-Receiver 'false'
	$err = $null
	try { Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 | Out-Null } catch { $err = $_.Exception.Message }
	$got = Wait-Receiver $r
	Assert ($err -like '*wollte seinen Spielstand*') "sender: $err"
	Assert ($got -like 'ERROR Nicht gespeichert*') $got
	Assert (Test-SameBytes $before (Get-FileSha256 (Join-Path $clientDir 'Det.sav'))) 'kept'
	Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'no .part left'
}

Test 'and is replaced, with a backup, when the player says yes' {
	$old = Get-FileSha256 (Join-Path $clientDir 'Det.sav')
	$r = Start-Receiver 'true'
	Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 | Out-Null
	$got = Wait-Receiver $r
	Assert ($got -like 'OK *') $got
	Assert (Test-SameBytes (Get-FileSha256 (Join-Path $hostDir 'Det.sav')) (Get-FileSha256 (Join-Path $clientDir 'Det.sav'))) 'new'
	Assert (Test-SameBytes $old (Get-FileSha256 (Join-Path $clientDir 'Det.sav.bak'))) 'backup'
}

Test 'a save without preview, with a space at the end of its name' {
	New-RandomFile (Join-Path $hostDir 'Zweiter Stand .sav') 500000
	$r = Start-Receiver 'true'
	Send-Savegame (Join-Path $hostDir 'Zweiter Stand .sav') $port $tick 30 | Out-Null
	$got = Wait-Receiver $r
	Assert ($got -like "OK Spielstand 'Zweiter Stand ' gespeichert*") $got
	Assert (Test-Path -LiteralPath (Join-Path $clientDir 'Zweiter Stand .sav')) 'saved'
}

Test 'file names from the other side cannot leave the save folder' {
	Assert (Test-SaveFileName 'Det.sav' 'Det') 'plain'
	Assert (Test-SaveFileName 'Det.JPG' 'Det') 'preview'
	Assert (-not (Test-SaveFileName '..\Det.sav' 'Det')) 'parent'
	Assert (-not (Test-SaveFileName 'C:\x\Det.sav' 'Det')) 'absolute'
	Assert (-not (Test-SaveFileName 'Det.dll' 'Det')) 'extension'
	Assert (-not (Test-SaveFileName 'Other.sav' 'Det')) 'other name'
	Assert (-not (Test-SaveFileName '' 'Det')) 'empty'
}

Test 'without a host the player gets a clear message' {
	$err = $null
	try { Receive-Savegame '127.0.0.1' ($port + 1) $clientDir $tick { $true } | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*Keine Verbindung*' -or $err -like '*refused*' -or $err -like '*verweigert*' -or $err -like '*actively*') "message: $err"
}

Test 'a single save account remains usable without active Steam account metadata' {
	$steam = Join-Path $base 'steam'
	$a = Join-Path $steam 'userdata\1\3493540\local\save'; $b = Join-Path $steam 'userdata\2\3493540\local\save'
	New-Item -ItemType Directory -Force $a | Out-Null
	Set-Content (Join-Path $a 'x.sav') 'a'
	Assert ((Get-SaveFolder $steam) -eq $a) 'single unambiguous account'
}

Test 'the active Steam account wins over a newer save in a different account' {
	$steam = Join-Path $base 'steam'
	$a = Join-Path $steam 'userdata\1\3493540\local\save'; $b = Join-Path $steam 'userdata\2\3493540\local\save'
	New-Item -ItemType Directory -Force $b | Out-Null; Set-Content (Join-Path $b 'y.sav') 'b'
	(Get-Item (Join-Path $a 'x.sav')).LastWriteTime = (Get-Date).AddDays(-1)
	$originalActive = (Get-Item Function:\Get-ActiveSteamAccount).ScriptBlock
	try {
		function Get-ActiveSteamAccount { return '1' }
		Assert ((Get-SaveFolder $steam) -eq $a) 'active older account'
		function Get-ActiveSteamAccount { return '3' }
		Assert ($null -eq (Get-SaveFolder $steam)) 'known active account cannot borrow another account save folder'
	} finally { Set-Item Function:\Get-ActiveSteamAccount $originalActive }
}

Test 'multiple accounts without active Steam metadata require explicit resolution' {
	$err = ''
	try { Get-SaveFolder (Join-Path $base 'steam') | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like 'Mehrere Steam-Konten*') $err
}

Test 'registry account information applies only to the matching Steam installation' {
	$registeredSteam = Join-Path $base 'registered-steam'
	$script:testRegisteredSteam = $registeredSteam
	$script:testActiveUser = 42
	try {
		function Get-ItemProperty {
			param($Path, $ErrorAction)
			if ($Path -like '*ActiveProcess') { return [pscustomobject]@{ ActiveUser = $script:testActiveUser } }
			return [pscustomobject]@{ SteamPath = $script:testRegisteredSteam }
		}
		Assert ((Get-ActiveSteamAccount $registeredSteam) -eq '42') 'matching registry root'
		Assert ($null -eq (Get-ActiveSteamAccount (Join-Path $base 'fixture-steam'))) 'isolated unrelated root'
		$script:testActiveUser = -1
		Assert ((Get-ActiveSteamAccount $registeredSteam) -eq '4294967295') 'unsigned registry DWORD account'
	} finally { Remove-Item Function:\Get-ItemProperty; Remove-Variable testRegisteredSteam, testActiveUser -Scope Script }
}

$manifest = [pscustomobject]@{ Protocol = 3; GameHash = ('a' * 64); PackageHash = ('b' * 64); ModsHash = ('c' * 64); Mods = @([pscustomobject]@{ Key = 'staging/track_pack'; Hash = ('d' * 64) }) }
$session = New-MultiplayerSession $manifest (Join-Path $hostDir 'Det.sav')
Test 'session transfer verifies compatibility and only successful results become prepared' {
	$clientPrepared = Join-Path $base 'client-session.json'; $hostPrepared = Join-Path $base 'host-session.json'
	$r = Start-Receiver 'true' $manifest $clientPrepared
	$result = Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 -Session $session
	$got = Wait-Receiver $r
	Assert ($got -like 'OK *') $got
	Assert ($result.Session.SessionId -eq $session.SessionId) 'sender metadata returned'
	Save-PreparedSession $hostPrepared $result.Session $result.SavePath | Out-Null
	foreach ($p in $hostPrepared, $clientPrepared) {
		$record = Read-PreparedSession $p
		Assert ((Assert-PreparedSession $record $manifest).SessionId -eq $session.SessionId) 'both have same prepared session'
	}
}

foreach ($field in 'GameHash', 'PackageHash', 'ModsHash') {
	Test "different $field rejects before writing save files or a prepared session" {
		$other = $manifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json; $other.$field = ('e' * 64)
		$before = Get-FileSha256 (Join-Path $clientDir 'Det.sav')
		$prepared = Join-Path $base 'rejected-session.json'
		$r = Start-Receiver 'true' $other $prepared
		$err = ''
		try { Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 -Session $session | Out-Null } catch { $err = $_.Exception.Message }
		$got = Wait-Receiver $r
		Assert ($err -like '*Sitzung wurde vom Mitspieler abgelehnt*') "host: $err"
		Assert ($got -like 'ERROR *') $got
		Assert (-not (Test-Path -LiteralPath $prepared)) 'no preparation on rejection'
		Assert (Test-SameBytes $before (Get-FileSha256 (Join-Path $clientDir 'Det.sav'))) 'existing world untouched'
		Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'no partial files'
	}
}

Test 'legacy hosts are refused by the session launcher' {
	$r = Start-Receiver 'true' $manifest
	$err = ''
	try { Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 | Out-Null } catch { $err = $_.Exception.Message }
	$got = Wait-Receiver $r
	Assert ($got -like '*alten Launcher ohne Sitzungsprüfung*') $got
	Assert ($err.Length -gt 0) 'sender observes rejection'
}

Test 'changed source save is refused before accepting a connection' {
	[IO.File]::AppendAllText((Join-Path $hostDir 'Det.sav'), 'changed')
	$err = ''
	try { Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 1 -Session $session | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*passt nicht mehr zur Sitzung*') $err
}

Test 'declining a replacement does not prepare the new session' {
	$newSession = New-MultiplayerSession $manifest (Join-Path $hostDir 'Det.sav')
	$prepared = Join-Path $base 'declined-session.json'
	$r = Start-Receiver 'false' $manifest $prepared
	$err = ''
	try { Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 -Session $newSession | Out-Null } catch { $err = $_.Exception.Message }
	$got = Wait-Receiver $r
	Assert ($got -like 'ERROR Nicht gespeichert*' -and $err -like '*wollte seinen Spielstand*') "$got / $err"
	Assert (-not (Test-Path -LiteralPath $prepared)) 'no preparation after declining'
}

Test 'a transferred hash that contradicts the session cannot replace the saved world' {
	$wrongSession = $session | ConvertTo-Json -Depth 6 | ConvertFrom-Json; $wrongSession.SaveHash = ('f' * 64)
	$before = Get-FileSha256 (Join-Path $clientDir 'Det.sav')
	$prepared = Join-Path $base 'wrong-hash-session.json'
	$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port)
	$listener.Start(); $client = $null
	try {
		$r = Start-Receiver 'true' $manifest $prepared
		$client = $listener.AcceptTcpClient(); $client.ReceiveTimeout = 10000; $client.SendTimeout = 10000
		$writer = New-Object IO.BinaryWriter($client.GetStream(), [Text.Encoding]::UTF8)
		$reader = New-Object IO.BinaryReader($client.GetStream(), [Text.Encoding]::UTF8)
		$metadata = [Text.Encoding]::UTF8.GetBytes(($wrongSession | ConvertTo-Json -Depth 6 -Compress))
		$writer.Write($SaveSessionMagic); $writer.Write([int]$metadata.Length); $writer.Write([byte[]]$metadata); $writer.Flush()
		Assert ($reader.ReadByte() -eq 1) 'game and mod compatibility accepted'; $reader.ReadString() | Out-Null
		$writer.Write('Det'); $writer.Write([int]1); $writer.Write([int64]1); $writer.Write('Det.sav'); $writer.Write([int64]1)
		$writer.Write([byte[]](Get-FileSha256 (Join-Path $hostDir 'Det.sav'))); $writer.Flush()
		Assert ($reader.ReadByte() -eq 0) 'file mismatch rejected'
		Assert ($reader.ReadString() -like '*Datei-Fingerabdruck passt nicht*') 'specific reason'
		$got = Wait-Receiver $r
		Assert ($got -like 'ERROR *') $got
		Assert (-not (Test-Path -LiteralPath $prepared)) 'no preparation'
		Assert (Test-SameBytes $before (Get-FileSha256 (Join-Path $clientDir 'Det.sav'))) 'world untouched'
	} finally { if ($client) { $client.Close() }; $listener.Stop() }
}

# Weitere Gegenstellen als eigene PowerShell-Prozesse (Gastgeber läuft blockierend in diesem Prozess).
function Start-Peer($body) {
	$script = @"
`$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false)
. '$((Join-Path $root 'tools\save-transfer.ps1').Replace("'", "''"))'
try {
$body
} catch { Write-Output "ERROR `$(`$_.Exception.Message)" }
"@
	$file = Join-Path $base ('peer-' + [Guid]::NewGuid().ToString('N') + '.ps1')
	Set-Content -Path $file -Value $script -Encoding UTF8
	$out = Join-Path $base ('peer-' + [Guid]::NewGuid().ToString('N') + '.txt')
	$hidden = @{}
	if ($IsWindows -ne $false) { $hidden.WindowStyle = 'Hidden' }
	$p = Start-Process -FilePath $shell -ArgumentList '-NoProfile', '-File', $file -RedirectStandardOutput $out -PassThru @hidden
	$testPeers.Add($p)
	return @{ Process = $p; Out = $out }
}
# Liest Kopf und den Anfang der ersten Datei wie ein Mitspieler, danach entscheidet $then.
$readSome = @"
	Start-Sleep -Milliseconds 300
	`$c = New-Object Net.Sockets.TcpClient; `$c.Connect('127.0.0.1', $port); `$c.ReceiveTimeout = 10000
	`$s = `$c.GetStream(); `$r = New-Object IO.BinaryReader(`$s, [Text.Encoding]::UTF8); `$w = New-Object IO.BinaryWriter(`$s, [Text.Encoding]::UTF8)
	`$null = `$r.ReadString(); `$null = `$r.ReadString(); `$null = `$r.ReadInt32(); `$null = `$r.ReadInt64()
	`$null = `$r.ReadString(); `$null = `$r.ReadInt64(); `$null = `$r.ReadBytes(32); `$null = `$r.ReadBytes(200000)
"@
# Größer als die Socket-Puffer, damit der Gastgeber beim Abbruch noch mitten im Senden ist.
New-RandomFile (Join-Path $hostDir 'Abbruch.sav') 40000000

Test 'a player who aborts mid-file tells the host why' {
	$r = Start-Peer ($readSome + "`n	`$VerbosePreference = 'Continue'; Send-ReceiverAbort `$c `$w 'Testgrund: Festplatte voll'; `$c.Close(); Write-Output 'OK'")
	$err = ''
	try { Send-Savegame (Join-Path $hostDir 'Abbruch.sav') $port $tick 30 -MaxAttempts 1 | Out-Null } catch { $err = $_.Exception.Message }
	$peer = Wait-Receiver $r
	Assert ($err -like '*Mitspieler hat die Übertragung abgebrochen*Testgrund: Festplatte voll*') "host: $err / peer: $peer"
}

Test 'an abrupt close mid-file gives a readable message instead of the raw Write error' {
	$r = Start-Peer ($readSome + "`n	`$c.Client.LingerState = New-Object Net.Sockets.LingerOption(`$true, 0); `$c.Close(); Write-Output 'OK'")
	$err = ''
	try { Send-Savegame (Join-Path $hostDir 'Abbruch.sav') $port $tick 30 -MaxAttempts 1 | Out-Null } catch { $err = $_.Exception.Message }
	Wait-Receiver $r | Out-Null
	Assert ($err -like '*Verbindung zum Mitspieler*abgebrochen*' -and $err -notlike '*Write*') "host: $err"
}

Test 'after a broken connection the host waits and the next attempt succeeds' {
	Remove-Item -LiteralPath (Join-Path $clientDir 'Abbruch.sav') -ErrorAction SilentlyContinue
	$broken = Start-Peer ($readSome + "`n	`$c.Client.LingerState = New-Object Net.Sockets.LingerOption(`$true, 0); `$c.Close(); Write-Output 'OK'")
	$retry = Start-Peer @"
	Start-Sleep -Seconds 4
	`$out = [pscustomobject]@{ Text = '' }  # wie das Textfeld im Launcher
	`$t = Receive-Savegame '127.0.0.1' $port '$($clientDir.Replace("'", "''"))' { param(`$a, `$b, `$c) `$out.Text = `$a; `$false } { param(`$q) `$true }
	Write-Output "OK `$t"
"@
	$answer = Send-Savegame (Join-Path $hostDir 'Abbruch.sav') $port $tick 30
	Wait-Receiver $broken | Out-Null
	$got = Wait-Receiver $retry
	Assert ($got -like 'OK *gespeichert*') $got
	Assert ($answer -like '*gespeichert*') $answer
	Assert (Test-SameBytes (Get-FileSha256 (Join-Path $hostDir 'Abbruch.sav')) (Get-FileSha256 (Join-Path $clientDir 'Abbruch.sav'))) 'same bytes'
}

Test 'the player reconnects by itself when the host drops the connection' {
	Remove-Item -LiteralPath (Join-Path $clientDir 'Abbruch.sav') -ErrorAction SilentlyContinue
	$r = Start-Receiver 'true'
	$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port)
	$listener.Start()
	try {
		$client = $listener.AcceptTcpClient()
		$writer = New-Object IO.BinaryWriter($client.GetStream(), [Text.Encoding]::UTF8)
		$writer.Write($SaveMagic); $writer.Write('Abbruch'); $writer.Write([int]1); $writer.Write([int64]40000000)
		$writer.Write('Abbruch.sav'); $writer.Write([int64]40000000); $writer.Write([byte[]](Get-FileSha256 (Join-Path $hostDir 'Abbruch.sav')))
		$writer.Write((New-Object byte[] 100000)); $writer.Flush()
		$client.Client.LingerState = New-Object Net.Sockets.LingerOption($true, 0); $client.Close()
	} finally { $listener.Stop() }
	Send-Savegame (Join-Path $hostDir 'Abbruch.sav') $port $tick 30 | Out-Null
	$got = Wait-Receiver $r
	Assert ($got -like 'OK *gespeichert*') $got
	Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'no .part left'
}

Test 'Neuabgleich: the player clicks first and waits until the host sends' {
	Remove-Item -LiteralPath (Join-Path $clientDir 'Det.sav') -ErrorAction SilentlyContinue
	$r = Start-Peer @"
	`$out = [pscustomobject]@{ Text = '' }  # wie das Textfeld im Launcher
	`$seen = @{ waiting = 0 }
	`$t = Receive-Savegame '127.0.0.1' $port '$($clientDir.Replace("'", "''"))' { param(`$a, `$b, `$c) if (`$a -like 'Warte auf den Gastgeber*') { `$seen.waiting++ }; `$out.Text = `$a; `$false } { param(`$q) `$true } -WaitSeconds 30
	Write-Output "OK waited=`$(`$seen.waiting -gt 0) `$t"
"@
	Start-Sleep -Seconds 5
	$answer = Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30
	$got = Wait-Receiver $r
	Assert ($got -like 'OK waited=True *gespeichert*') $got
	Assert ($answer -like '*gespeichert*') $answer
	Assert (Test-SameBytes (Get-FileSha256 (Join-Path $hostDir 'Det.sav')) (Get-FileSha256 (Join-Path $clientDir 'Det.sav'))) 'same bytes'
}

Test 'Neuabgleich: without a host the waiting player stops after its time' {
	$started = [DateTime]::UtcNow
	$err = $null
	try { Receive-Savegame '127.0.0.1' ($port + 1) $clientDir $tick { $true } -WaitSeconds 3 | Out-Null } catch { $err = $_.Exception.Message }
	$took = ([DateTime]::UtcNow - $started).TotalSeconds
	Assert ($err -like '*Keine Verbindung*') "message: $err"
	Assert ($took -ge 2.5 -and $took -lt 25) "waited $took s"
	Assert ($out.Text -like 'Warte auf den Gastgeber*' -or $out.Text -like 'Verbinde mit*') "tick: $($out.Text)"
}

Test 'parallel: four connections transfer odd file sizes and unicode names with verified hashes' {
	$path = Join-Path $hostDir 'Parallel ä .sav'; New-RandomFile $path 12000007
	New-RandomFile ([IO.Path]::ChangeExtension($path, '.jpg')) 123457
	$newSession = New-MultiplayerSession $manifest $path
	$statsPath = Join-Path $base 'parallel-stats.json'
	$r = Start-Receiver 'true' $manifest '' 4 $statsPath
	Send-Savegame $path $port $tick 30 -Session $newSession | Out-Null
	$got = Wait-Receiver $r
	Assert ($got -like 'OK *gespeichert*') $got
	$remoteStats = Get-Content -LiteralPath $statsPath -Raw | ConvertFrom-Json
	Assert ($script:LastSaveTransfer.Streams -eq 4 -and $remoteStats.Streams -eq 4) 'four actual streams on both peers'
	Assert ($script:LastSaveTransfer.Bytes -eq 12123464 -and $remoteStats.Bytes -eq 12123464) 'exact disjoint ranges'
	Assert ($script:LastSaveTransfer.Seconds -gt 0 -and $remoteStats.Seconds -gt 0) 'data-only telemetry'
	Assert ($script:LastSaveTransfer.Method -eq 'continuous' -and $remoteStats.Method -eq 'continuous') 'new streaming protocol negotiated on both peers'
	Assert (($script:LastSaveTransfer.LaneBytes | Measure-Object -Sum).Sum -eq 12123464) 'all sender progress is receiver-confirmed'
	foreach ($stats in $script:LastSaveTransfer, $remoteStats) {
		$rows = @(Get-Content -LiteralPath $stats.LogPath | ForEach-Object { $_ | ConvertFrom-Json })
		Assert (@($rows | Where-Object event -eq 'complete').Count -eq 1) 'completed trace survives worker teardown'
		$summary = @($rows | Where-Object event -eq 'data_summary')[0]
		Assert ($summary.bytes -eq 12123464 -and $summary.streams -eq 4 -and $summary.mib_per_s -gt 0) 'measured byte counts, streams and throughput'
		Assert ((Get-Content -LiteralPath $stats.LogPath -Raw) -notmatch 'Parallel|127\.0\.0\.1|[a-f0-9]{64}') 'trace has no save names, IPs or tokens'
	}
	foreach ($f in 'Parallel ä .sav','Parallel ä .jpg') { Assert (Test-SameBytes (Get-FileSha256 (Join-Path $hostDir $f)) (Get-FileSha256 (Join-Path $clientDir $f))) $f }
	Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'no parts'
}

Test 'parallel: a single-stream receiver keeps the session protocol compatible' {
	$newSession = New-MultiplayerSession $manifest (Join-Path $hostDir 'Det.sav')
	$r = Start-Receiver 'true' $manifest '' 1
	Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 -Session $newSession | Out-Null
	Assert ((Wait-Receiver $r) -like 'OK *gespeichert*') 'legacy payload after capability negotiation'
	Assert ($null -eq $script:LastSaveTransfer) 'parallel mode was not used'
}

Test 'parallel: continuous mode falls back when either side only supports block acknowledgements' {
	$newSession = New-MultiplayerSession $manifest (Join-Path $hostDir 'Det.sav')
	foreach ($newSender in $true,$false) {
		$r = Start-Receiver 'true' $manifest -Continuous (-not $newSender)
		Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 -Session $newSession -Continuous $newSender | Out-Null
		Assert ((Wait-Receiver $r) -like 'OK *gespeichert*') 'mixed capability transfer succeeds'
		Assert ($script:LastSaveTransfer.Method -eq 'block-ack' -and $script:LastSaveTransfer.Streams -eq 4) 'compatible DATA3 fallback'
	}
}

Test 'parallel: a broken diagnostic directory cannot abort a verified transfer' {
	$previous = $script:SaveTransferLogDirectory
	try {
		$script:SaveTransferLogDirectory = Join-Path (Join-Path $hostDir 'Det.sav') 'not-a-directory'
		$newSession = New-MultiplayerSession $manifest (Join-Path $hostDir 'Det.sav')
		$r = Start-Receiver 'true' $manifest
		Send-Savegame (Join-Path $hostDir 'Det.sav') $port $tick 30 -Session $newSession | Out-Null
		Assert ((Wait-Receiver $r) -like 'OK *gespeichert*') 'diagnostics cannot block network or filesystem result'
		Assert ($script:LastSaveTransfer.LogPath -eq '') 'unavailable trace is not advertised'
	} finally { $script:SaveTransferLogDirectory = $previous }
}

Test 'parallel: the sender can cancel while the peer never answers compatibility' {
	$newSession = New-MultiplayerSession $manifest (Join-Path $hostDir 'Det.sav')
	$r = Start-Peer @"
	`$c = New-Object Net.Sockets.TcpClient; `$c.Connect('127.0.0.1', $port)
	`$br = New-Object IO.BinaryReader(`$c.GetStream(), [Text.Encoding]::UTF8)
	`$null = `$br.ReadString(); `$n = `$br.ReadInt32(); `$null = `$br.ReadBytes(`$n)
	Start-Sleep -Seconds 2; `$c.Close(); Write-Output 'OK'
"@
	$watch = [Diagnostics.Stopwatch]::StartNew(); $err = ''
	try { Send-Savegame (Join-Path $hostDir 'Det.sav') $port { param($text) $text -like '*Kompatibilitätsprüfung*' } 30 -Session $newSession -MaxAttempts 1 | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -eq 'Abgebrochen.' -and $watch.Elapsed.TotalSeconds -lt 5) "responsive compatibility cancel: $err"
	Wait-Receiver $r | Out-Null
}

Test 'parallel: the receiver can cancel while the sender never supplies a header' {
	$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port); $listener.Start()
	try {
		$watch = [Diagnostics.Stopwatch]::StartNew(); $err = ''
		try { Receive-Savegame '127.0.0.1' $port $clientDir { param($text) $text -like '*Übertragungsdaten*' } { $true } -LocalManifest $manifest -MaxAttempts 1 | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -eq 'Abgebrochen.' -and $watch.Elapsed.TotalSeconds -lt 3) "responsive header cancel: $err"
	} finally { if ($listener.Pending()) { $listener.AcceptTcpClient().Close() }; $listener.Stop() }
}

Test 'parallel: a refused replacement preserves the existing world and clears every part' {
	$path = Join-Path $hostDir 'Parallel ä .sav'; New-RandomFile $path 9000001
	$before = Get-FileSha256 (Join-Path $clientDir 'Parallel ä .sav')
	$newSession = New-MultiplayerSession $manifest $path
	$r = Start-Receiver 'false' $manifest
	$err = ''; try { Send-Savegame $path $port $tick 30 -Session $newSession | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*wollte seinen Spielstand*') $err
	Assert ((Wait-Receiver $r) -like 'ERROR Nicht gespeichert*') 'refused'
	Assert (Test-SameBytes $before (Get-FileSha256 (Join-Path $clientDir 'Parallel ä .sav'))) 'original unchanged'
	Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'all parts deleted'
}

Test 'parallel: cancelling a receiver stops all sockets and never replaces its existing save' {
	$path = Join-Path $hostDir 'Abbruch.sav'; $newSession = New-MultiplayerSession $manifest $path
	$target = Join-Path $clientDir 'Abbruch.sav'; [IO.File]::WriteAllText($target, 'keep existing world')
	$before = Get-FileSha256 $target
	$manifestPath = Join-Path $base 'cancel-manifest.json'; $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
	$r = Start-Peer @"
	`$manifest = Get-Content -LiteralPath '$($manifestPath.Replace("'", "''"))' -Raw | ConvertFrom-Json
	Receive-Savegame '127.0.0.1' $port '$($clientDir.Replace("'", "''"))' { param(`$text) `$text -like 'Empfange *Datenverbindungen*' } { `$true } -LocalManifest `$manifest -MaxAttempts 1 | Out-Null
"@
	$err = ''; try { Send-Savegame $path $port $tick 30 -Session $newSession -MaxAttempts 1 | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err.Length -gt 0) 'host observes cancellation'
	Assert ((Wait-Receiver $r) -like 'ERROR Abgebrochen.*') 'receiver cancellation'
	Assert (Test-SameBytes $before (Get-FileSha256 $target)) 'original remains'
	Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'no orphan worker files'
	# Reuse the same port and names immediately: no orphan listeners/files from the cancelled attempt.
	$r = Start-Receiver 'true' $manifest
	Send-Savegame $path $port $tick 30 -Session $newSession | Out-Null
	Assert ((Wait-Receiver $r) -like 'OK *gespeichert*') 'next attempt succeeds'
}

Test 'parallel: invalid stream counts are rejected before opening files or sockets' {
	foreach ($n in 0,5,-1) {
		$err = ''; try { Send-Savegame 'does-not-exist.sav' $port $tick -Connections $n | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -like '*zwischen 1 und 4*') $err
	}
}

Test 'parallel: a blocked writer remains cancellable' {
	Add-Type -TypeDefinition @'
public sealed class TF3MPStalledWriter : System.IO.MemoryStream {
    private volatile bool closed;
    public override void Write(byte[] b, int offset, int count) {
        while (!closed) System.Threading.Thread.Sleep(10);
        throw new System.IO.IOException("cancelled blocked write");
    }
    protected override void Dispose(bool disposing) { closed = true; base.Dispose(disposing); }
}
'@
	$stalled = New-Object TF3MPStalledWriter
	try {
		$err = ''; $watch = [Diagnostics.Stopwatch]::StartNew()
		try { Write-SaveData $stalled (New-Object byte[] 1000) 0 1000 (New-SaveProgress) { $true } 'Schicke ...' 0 1000 } catch { $err = $_.Exception.Message }
		Assert ($err -eq 'Abgebrochen.' -and $watch.Elapsed.TotalSeconds -lt 3) "write cancellation: $err"
	} finally { $stalled.Dispose() }
}

Test 'parallel: cancellation works while waiting for the final confirmation' {
	$path = Join-Path $hostDir 'Ack.sav'; New-RandomFile $path 1000
	$r = Start-Peer @"
	`$c = New-Object Net.Sockets.TcpClient; `$c.Connect('127.0.0.1', $port); `$c.ReceiveTimeout = 5000
	`$br = New-Object IO.BinaryReader(`$c.GetStream(), [Text.Encoding]::UTF8)
	`$null = `$br.ReadString(); `$null = `$br.ReadString(); `$null = `$br.ReadInt32(); `$null = `$br.ReadInt64()
	`$null = `$br.ReadString(); `$null = `$br.ReadInt64(); `$null = `$br.ReadBytes(32); `$null = `$br.ReadBytes(1000)
	Start-Sleep -Seconds 2; `$c.Close(); Write-Output 'OK'
"@
	$seen = @{ Waiting = 0 }; $err = ''; $watch = [Diagnostics.Stopwatch]::StartNew()
	try { Send-Savegame $path $port { param($text) if ($text -like '*Bestätigung*') { $seen.Waiting++ }; $seen.Waiting -ge 3 } 30 -MaxAttempts 1 | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -eq 'Abgebrochen.' -and $watch.Elapsed.TotalSeconds -lt 5 -and $seen.Waiting -ge 3) "confirmation cancel: $err"
	Wait-Receiver $r | Out-Null
}

Test 'parallel: wrong data tokens are refused and valid connections still succeed' {
	$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $listener.Start()
	$sendJob = $null; $receiveJob = $null; $bad = $null
	try {
		$path = Join-Path $hostDir 'Det.sav'; $token = ('a' * 64)
		$source = New-Object TF3MP.TransferFile; $source.Path = $path; $source.Name = 'Det.sav'; $source.Length = (Get-Item $path).Length; $source.Hash = Get-FileSha256 $path
		$dest = New-Object TF3MP.TransferFile; $dest.Path = Join-Path $clientDir 'token-check.part'; $dest.Name = 'Det.sav'; $dest.Length = $source.Length; $dest.Hash = $source.Hash
		$sendJob = [TF3MP.TransferJob]::Send($listener, [Net.IPAddress]::Loopback, $token, [TF3MP.TransferFile[]]@($source), 4)
		$bad = New-Object Net.Sockets.TcpClient; $bad.Connect('127.0.0.1', $listener.LocalEndpoint.Port)
		$writer = New-Object IO.BinaryWriter($bad.GetStream(), [Text.Encoding]::UTF8); $writer.Write('TF3MPRANGE1'); $writer.Write(('b' * 64)); $writer.Write([int]0); $writer.Flush()
		$receiveJob = [TF3MP.TransferJob]::Receive('127.0.0.1', $listener.LocalEndpoint.Port, $token, [TF3MP.TransferFile[]]@($dest), 4)
		Wait-SaveJob $sendJob $tick 'Schicke ...' $source.Length | Out-Null
		Wait-SaveJob $receiveJob $tick 'Empfange ...' $source.Length | Out-Null
		Assert ($sendJob.Streams -eq 4 -and $receiveJob.Streams -eq 4) 'wrong token consumed no slot'
		Assert (Test-SameBytes $source.Hash (Get-FileSha256 $dest.Path)) 'valid ranges intact'
		Remove-Item -LiteralPath $dest.Path
	} finally { if ($bad) { $bad.Close() }; if ($sendJob) { $sendJob.Cancel() }; if ($receiveJob) { $receiveJob.Cancel() }; $listener.Stop() }
}

Test 'parallel: corrupted payloads fail the worker hash check' {
	foreach ($continuous in $false,$true) {
	$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $listener.Start()
	$sendJob = $null; $receiveJob = $null
	try {
		$path = Join-Path $hostDir 'Det.sav'; $token = ('c' * 64)
		$source = New-Object TF3MP.TransferFile; $source.Path = $path; $source.Name = 'Det.sav'; $source.Length = (Get-Item $path).Length; $source.Hash = Get-FileSha256 $path
		$dest = New-Object TF3MP.TransferFile; $dest.Path = Join-Path $clientDir 'hash-check.part'; $dest.Name = 'Det.sav'; $dest.Length = $source.Length; $dest.Hash = [byte[]]$source.Hash.Clone(); $dest.Hash[0] = $dest.Hash[0] -bxor 255
		$sendJob = [TF3MP.TransferJob]::Send($listener, [Net.IPAddress]::Loopback, $token, [TF3MP.TransferFile[]]@($source), 4, $continuous)
		$receiveJob = [TF3MP.TransferJob]::Receive('127.0.0.1', $listener.LocalEndpoint.Port, $token, [TF3MP.TransferFile[]]@($dest), 4, $continuous)
		Wait-SaveJob $sendJob $tick 'Schicke ...' $source.Length | Out-Null
		$err = ''; try { Wait-SaveJob $receiveJob $tick 'Empfange ...' $source.Length | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -like '*kam beschädigt an*') $err
		Remove-Item -LiteralPath $dest.Path
	} finally { if ($sendJob) { $sendJob.Cancel() }; if ($receiveJob) { $receiveJob.Cancel() }; $listener.Stop() }
	}
}

Test 'parallel: a dropped data connection is retried with clean parts on the same port' {
	$path = Join-Path $hostDir 'Det.sav'; $newSession = New-MultiplayerSession $manifest $path
	$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port); $listener.Start(); $sockets = @()
	try {
		$tracePath = Join-Path $base 'retry-progress.log'
		$r = Start-Receiver 'true' $manifest '' 4 '' $tracePath
		$c = $listener.AcceptTcpClient(); $sockets += $c; $c.ReceiveTimeout = 5000
		$writer = New-Object IO.BinaryWriter($c.GetStream(), [Text.Encoding]::UTF8); $reader = New-Object IO.BinaryReader($c.GetStream(), [Text.Encoding]::UTF8)
		$metadata = [Text.Encoding]::UTF8.GetBytes(($newSession | ConvertTo-Json -Depth 6 -Compress))
		$writer.Write($SaveSessionMagic); $writer.Write([int]$metadata.Length); $writer.Write($metadata); $writer.Flush()
		Assert ($reader.ReadByte() -eq 1) 'compatible'; Assert ($reader.ReadString() -like '*parallel=4*') 'four lanes advertised'
		$writer.Write($SaveParallelMagic); $writer.Write('Det'); $writer.Write([int]1); $writer.Write([int64](Get-Item $path).Length)
		$writer.Write(('d' * 64)); $writer.Write([int]4); $writer.Write('Det.sav'); $writer.Write([int64](Get-Item $path).Length); $writer.Write([byte[]](Get-FileSha256 $path)); $writer.Flush()
		$deadline = [DateTime]::UtcNow.AddSeconds(10)
		while ($sockets.Count -lt 5) { if ([DateTime]::UtcNow -gt $deadline) { throw 'missing data socket' }; if ($listener.Pending()) { $sockets += $listener.AcceptTcpClient() } else { Start-Sleep -Milliseconds 10 } }
		foreach ($socket in $sockets) { $socket.Close() }
		# The real host keeps its listener for retries, too. Avoid a loopback/Any rebind race
		# in the test fixture while old accepted Windows sockets are still closing.
		$deadline = [DateTime]::UtcNow.AddSeconds(15)
		# Cancellation of the failed attempt may finish a late data-lane connection.
		# Such a lane sends its preamble first; the retry control waits for our greeting.
		$retryClient = $null
		while (-not $retryClient) {
			if ([DateTime]::UtcNow -gt $deadline) { throw 'receiver did not retry' }
			if (-not $listener.Pending()) { Start-Sleep -Milliseconds 50; continue }
			$candidate = $listener.AcceptTcpClient(); $sockets += $candidate
			if ($candidate.Client.Poll(100000, [Net.Sockets.SelectMode]::SelectRead)) { $candidate.Close(); continue }
			$retryClient = $candidate
		}
		$files = Get-SaveFiles $path; $hashes = @{}; $total = [int64]0
		foreach ($f in $files) { $hashes[$f.Name] = Get-FileSha256 $f.FullName; $total += $f.Length }
		Send-SaveToClient $retryClient $newSession $metadata 'Det' $files $hashes $total $tick $listener 4 | Out-Null
	} finally { foreach ($socket in $sockets) { $socket.Close() }; $listener.Stop() }
	$got = Wait-Receiver $r; Assert ($got -like 'OK *gespeichert*') $got
	Assert ($script:LastSaveTransfer.Streams -eq 4) 'retry uses parallel transfer'
	Assert (Test-SameBytes (Get-FileSha256 $path) (Get-FileSha256 (Join-Path $clientDir 'Det.sav'))) 'retry bytes intact'
	Assert (@(Get-ChildItem $clientDir -Filter '*.part').Count -eq 0) 'failed attempt removed every part'
}

Test 'parallel: wire text lengths are bounded before allocation' {
	$memory = New-Object IO.MemoryStream; $writer = New-Object IO.BinaryWriter($memory, [Text.Encoding]::UTF8)
	$writer.Write(('x' * 1000)); $writer.Flush(); $memory.Position = 0
	$reader = New-Object IO.BinaryReader($memory, [Text.Encoding]::UTF8)
	$job = [TF3MP.TransferJob]::Read($reader, 'text', 32)
	$err = ''; try { Wait-SaveJob $job $tick 'Kopf ...' | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*Übertragungstext zu lang*') $err
}

Test 'parallel: leftover data sockets do not consume the host retry budget' {
	$path = Join-Path $hostDir 'Det.sav'; $newSession = New-MultiplayerSession $manifest $path
	$stray = Start-Peer @"
	`$c = New-Object Net.Sockets.TcpClient; `$c.Connect('127.0.0.1', $port)
	`$writer = New-Object IO.BinaryWriter(`$c.GetStream(), [Text.Encoding]::UTF8)
	`$writer.Write('TF3MPRANGE1'); `$writer.Write(('e' * 64)); `$writer.Write([int]0); `$writer.Flush()
	Start-Sleep -Seconds 1; `$c.Close(); Write-Output 'OK'
"@
	$r = Start-Receiver 'true' $manifest
	Send-Savegame $path $port $tick 30 -Session $newSession -MaxAttempts 1 | Out-Null
	Assert ((Wait-Receiver $r) -like 'OK *gespeichert*') 'real control connection succeeds on first attempt'
	Wait-Receiver $stray | Out-Null
}

$resolvedBase = [IO.Path]::GetFullPath($base)
foreach ($peerProcess in $testPeers) { if (-not $peerProcess.HasExited) { $peerProcess.Kill(); $peerProcess.WaitForExit() } }
if (-not $resolvedBase.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped TEMP.' }
Remove-Item -LiteralPath $resolvedBase -Recurse -Force
Write-Host "$passed save transfer tests passed, $failed failed"
if ($failed -gt 0) { exit 1 }

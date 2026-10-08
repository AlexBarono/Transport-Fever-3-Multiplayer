# Offline-Test der Spielstand-Übertragung (tools\save-transfer.ps1) über 127.0.0.1.
# Aufruf aus dem Hauptordner: pwsh -File tests\run_save_transfer.ps1  (oder powershell -File ...)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\save-transfer.ps1')

$passed = 0; $failed = 0
function Test($name, $fn) {
	try { & $fn; $script:passed++ } catch { $script:failed++; Write-Host "FAIL ${name}: $($_.Exception.Message)" }
}
function Assert($cond, $msg) { if (-not $cond) { throw "assertion failed: $msg" } }

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("tf3mp-save-test-" + [Guid]::NewGuid().ToString('N'))
$hostDir = Join-Path $base 'host'; $clientDir = Join-Path $base 'client'
New-Item -ItemType Directory -Force $hostDir, $clientDir | Out-Null
$rng = New-Object System.Random 7
function New-RandomFile($path, $size) {
	$bytes = New-Object byte[] $size
	$rng.NextBytes($bytes)
	[System.IO.File]::WriteAllBytes($path, $bytes)
}
New-RandomFile (Join-Path $hostDir 'Det.sav') 3000000
New-RandomFile (Join-Path $hostDir 'Det.jpg') 80000
$port = 47950

# Der Mitspieler läuft in einem zweiten PowerShell-Prozess.
$shell = (Get-Process -Id $PID).Path
function Start-Receiver($answer, $manifest = $null, $preparedPath = '') {
	$manifestPath = ''
	if ($manifest) { $manifestPath = Join-Path $base 'receiver-manifest.json'; $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 }
	$script = @"
`$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false)
. '$((Join-Path $root 'tools\save-transfer.ps1').Replace("'", "''"))'
try {
	Start-Sleep -Milliseconds 500
	`$manifest = if ('$($manifestPath.Replace("'", "''"))') { Get-Content -LiteralPath '$($manifestPath.Replace("'", "''"))' -Raw | ConvertFrom-Json } else { `$null }
	`$t = Receive-Savegame '127.0.0.1' $port '$($clientDir.Replace("'", "''"))' { param(`$a, `$b, `$c) `$false } { param(`$q) `$$answer } -LocalManifest `$manifest
	if ('$($preparedPath.Replace("'", "''"))' -and `$t.Session) { Save-PreparedSession -Path '$($preparedPath.Replace("'", "''"))' -Session `$t.Session -SavePath `$t.SavePath | Out-Null }
	`$text = if (`$t.Session) { `$t.Text } else { `$t }
	Write-Output "OK `$text"
} catch { Write-Output "ERROR `$(`$_.Exception.Message)" }
"@
	$file = Join-Path $base 'receiver.ps1'
	Set-Content -Path $file -Value $script -Encoding UTF8
	$out = Join-Path $base ('receiver-' + [Guid]::NewGuid().ToString('N') + '.txt')
	$p = Start-Process -FilePath $shell -ArgumentList '-NoProfile', '-File', $file -RedirectStandardOutput $out -PassThru -WindowStyle Hidden
	return @{ Process = $p; Out = $out }
}
function Wait-Receiver($r) {
	if (-not $r.Process.WaitForExit(60000)) { $r.Process.Kill(); throw 'receiver hangs' }
	return (Get-Content $r.Out -Raw -Encoding UTF8).Trim()
}
$ticks = 0
$tick = { param($text, $done, $total) $script:ticks++; $false }

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
	Assert ($ticks -gt 10) "progress ticks $ticks"
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

Remove-Item -Recurse -Force $base
Write-Host "$passed save transfer tests passed, $failed failed"
if ($failed -gt 0) { exit 1 }

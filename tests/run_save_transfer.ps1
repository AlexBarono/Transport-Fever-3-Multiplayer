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
function Start-Receiver($answer) {
	$script = @"
`$ErrorActionPreference = 'Stop'
. '$((Join-Path $root 'tools\save-transfer.ps1').Replace("'", "''"))'
try {
	Start-Sleep -Milliseconds 500
	`$t = Receive-Savegame '127.0.0.1' $port '$($clientDir.Replace("'", "''"))' { param(`$a, `$b, `$c) `$false } { param(`$q) `$$answer }
	Write-Output "OK `$t"
} catch { Write-Output "ERROR `$(`$_.Exception.Message)" }
"@
	$file = Join-Path $base 'receiver.ps1'
	Set-Content -Path $file -Value $script -Encoding UTF8
	$out = Join-Path $base ('receiver-' + [Guid]::NewGuid().ToString('N') + '.txt')
	$p = Start-Process -FilePath $shell -ArgumentList '-NoProfile', '-File', $file -RedirectStandardOutput $out -PassThru -NoNewWindow
	return @{ Process = $p; Out = $out }
}
function Wait-Receiver($r) {
	if (-not $r.Process.WaitForExit(60000)) { $r.Process.Kill(); throw 'receiver hangs' }
	return (Get-Content $r.Out -Raw).Trim()
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

Test 'the save folder is the one with the newest save' {
	$steam = Join-Path $base 'steam'
	$a = Join-Path $steam 'userdata\1\3493540\local\save'; $b = Join-Path $steam 'userdata\2\3493540\local\save'
	New-Item -ItemType Directory -Force $a, $b | Out-Null
	Set-Content (Join-Path $a 'x.sav') 'a'; Set-Content (Join-Path $b 'y.sav') 'b'
	(Get-Item (Join-Path $a 'x.sav')).LastWriteTime = (Get-Date).AddDays(-1)
	Assert ((Get-SaveFolder $steam) -eq $b) (Get-SaveFolder $steam)
}

Remove-Item -Recurse -Force $base
Write-Host "$passed save transfer tests passed, $failed failed"
if ($failed -gt 0) { exit 1 }

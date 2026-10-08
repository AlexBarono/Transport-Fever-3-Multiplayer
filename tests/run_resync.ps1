# Offline-Test der Neuabgleich-Helfer (tools\resync.ps1): Spielstand finden, fertig geschrieben, Spiel beenden.
# Aufruf aus dem Hauptordner: pwsh -File tests\run_resync.ps1  (oder powershell -File ...)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\resync.ps1')

$passed = 0; $failed = 0
function Test($name, $fn) {
	try { & $fn; $script:passed++ } catch { $script:failed++; Write-Host "FAIL ${name}: $($_.Exception.Message)" }
}
function Assert($cond, $msg) { if (-not $cond) { throw "assertion failed: $msg" } }

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("tf3mp-resync-test-" + [Guid]::NewGuid().ToString('N'))
$saves = Join-Path $base 'save'
New-Item -ItemType Directory -Force $saves | Out-Null
function New-Save($name, [datetime]$writtenUtc, $size = 1000) {
	$path = Join-Path $saves $name
	[IO.File]::WriteAllBytes($path, (New-Object byte[] $size))
	(Get-Item -LiteralPath $path).LastWriteTimeUtc = $writtenUtc
	return $path
}
$ticks = New-Object System.Collections.ArrayList
$tick = { param($text, $done, $total) [void]$ticks.Add($text); $false }
$now = [DateTime]::UtcNow
$started = $now.AddMinutes(-30)

Test 'the newest save written since the game started is the resync save' {
	New-Save 'Alt.sav' $started.AddMinutes(-5) | Out-Null
	New-Save 'Mein Stand.sav' $started.AddMinutes(10) | Out-Null
	New-Save "$ResyncSaveName.sav" $started.AddMinutes(20) | Out-Null
	New-Save "$ResyncSaveName.jpg" $started.AddMinutes(25) | Out-Null
	New-Save 'Teil.sav.part' $started.AddMinutes(26) | Out-Null
	New-Save 'Kopie.savx' $started.AddMinutes(27) | Out-Null
	$file = Find-ResyncSave $saves $started
	Assert ($file -and $file.Name -eq "$ResyncSaveName.sav") "found $($file.Name)"
	Assert ($null -eq (Find-ResyncSave $saves $started.AddMinutes(21))) 'nothing newer'
	Assert ((Find-ResyncSave $saves ([datetime]::MinValue)).Name -eq "$ResyncSaveName.sav") 'newest of all'
	Assert ($null -eq (Find-ResyncSave (Join-Path $base 'fehlt') $started)) 'missing folder'
}

Test 'a finished save is taken after a quiet moment' {
	$file = Get-Item -LiteralPath (Join-Path $saves "$ResyncSaveName.sav")
	$t0 = [DateTime]::UtcNow
	$got = Wait-SaveWritten $file $tick 10 0.5
	Assert ($got.FullName -eq $file.FullName) 'same file'
	Assert (([DateTime]::UtcNow - $t0).TotalSeconds -ge 0.4) 'waited for the quiet moment'
}

Test 'a save that still grows is taken only when it stops growing' {
	$path = New-Save 'Wachsend.sav' ([DateTime]::UtcNow) 10
	$writer = Start-Job -ScriptBlock {
		param($p)
		for ($i = 0; $i -lt 6; $i++) { [IO.File]::AppendAllText($p, ('x' * 1000)); Start-Sleep -Milliseconds 300 }
	} -ArgumentList $path
	try {
		Start-Sleep -Milliseconds 200
		$got = Wait-SaveWritten (Get-Item -LiteralPath $path) $tick 30 1
		Wait-Job $writer -Timeout 30 | Out-Null
		Assert ($got.Length -eq 6010) "length $($got.Length)"
	} finally { Remove-Job $writer -Force }
}

Test 'a save that never settles stops with a clear message' {
	$path = New-Save 'Endlos.sav' ([DateTime]::UtcNow) 10
	$writer = Start-Job -ScriptBlock {
		param($p)
		for ($i = 0; $i -lt 40; $i++) { [IO.File]::AppendAllText($p, 'x'); Start-Sleep -Milliseconds 100 }
	} -ArgumentList $path
	try {
		Start-Sleep -Milliseconds 300
		$err = ''
		try { Wait-SaveWritten (Get-Item -LiteralPath $path) $tick 1 1 | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -like "*'Endlos' wird noch geschrieben*") $err
	} finally { Stop-Job $writer -ErrorAction SilentlyContinue; Remove-Job $writer -Force }
}

Test 'without a fresh save the launcher waits for the player to save' {
	$since = [DateTime]::UtcNow
	$writer = Start-Job -ScriptBlock {
		param($p)
		Start-Sleep -Seconds 2
		[IO.File]::WriteAllBytes($p, (New-Object byte[] 5000))
	} -ArgumentList (Join-Path $saves 'Gerade gespeichert.sav')
	try {
		$ticks.Clear()
		$got = Wait-NewSave $saves $since $tick 30 0.5
		Assert ($got.Name -eq 'Gerade gespeichert.sav') "found $($got.Name)"
		Assert (@($ticks | Where-Object { $_ -like 'Bitte jetzt im Spiel speichern*' }).Count -gt 0) 'asked to save'
	} finally { Remove-Job $writer -Force }
	$err = ''
	try { Wait-NewSave $saves ([DateTime]::UtcNow.AddMinutes(5)) $tick 1 | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*kein neuer Spielstand*') $err
}

Test 'cancelling while waiting for a save stops at once' {
	$err = ''
	try { Wait-NewSave $saves ([DateTime]::UtcNow.AddMinutes(5)) { $true } 30 | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -eq 'Abgebrochen.') $err
}

# Ein Programm unter eigenem Namen spielt TF3 (ohne Fenster, also nur hart zu beenden).
$fakeName = 'tf3mpfakegame'
$sleep = (Get-Command sleep -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ($sleep -and $IsLinux) {
	$fake = Join-Path $base $fakeName
	Copy-Item -LiteralPath $sleep -Destination $fake
	Test 'a game that does not close by itself is closed hard only after asking' {
		$p = Start-Process -FilePath $fake -ArgumentList '300' -PassThru
		try {
			Start-Sleep -Milliseconds 300
			Assert ($null -ne (Get-GameStartTime $fakeName)) 'start time'
			$err = ''
			try { Stop-GameForResync $tick { $false } 1 $fakeName | Out-Null } catch { $err = $_.Exception.Message }
			Assert ($err -like 'TF3 läuft noch*' -and -not $p.HasExited) "refused: $err"
			$asked = @{ n = 0 }
			$stopped = Stop-GameForResync $tick { $asked.n++; $true } 1 $fakeName
			Assert ($stopped -and $asked.n -eq 1 -and $p.HasExited) 'closed after one question'
			Assert (-not (Stop-GameForResync $tick { throw 'not asked' } 1 $fakeName)) 'nothing to close'
			Assert ($null -eq (Get-GameStartTime $fakeName)) 'no start time'
		} finally { if (-not $p.HasExited) { $p.Kill() } }
	}
} else { Write-Host 'skip: closing the game (needs Linux sleep)' }

Remove-Item -Recurse -Force $base
Write-Host "$passed resync tests passed, $failed failed"
if ($failed -gt 0) { exit 1 }

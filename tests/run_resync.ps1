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

# Die Prozessadapter testen denselben Ablauf auf Windows, ohne TF3 oder ein anderes Programm zu
# beenden. Auch Zugriffsfehler und ein Prozess, der trotz Beenden weiterläuft, sind reproduzierbar.
$originalAdapters = @{}
foreach ($name in 'Get-ResyncGameProcesses', 'Close-ResyncGameWindow', 'Stop-ResyncGameProcess') { $originalAdapters[$name] = (Get-Item "Function:\$name").ScriptBlock }
function Set-FakeResync([int[]]$Ids = @(41)) {
	$script:fakeResync = @{ Remaining = @{}; Window = $true; CloseExits = $false; IgnoreStop = $false; StopError = ''; CloseCalls = 0; StopCalls = 0 }
	foreach ($id in $Ids) { $script:fakeResync.Remaining[$id] = $true }
}
try {
	function Get-ResyncGameProcesses($ProcessName) { foreach ($id in @($script:fakeResync.Remaining.Keys)) { [pscustomobject]@{ Id = $id } } }
	function Close-ResyncGameWindow($Process) {
		$script:fakeResync.CloseCalls++
		if ($script:fakeResync.CloseExits) { $script:fakeResync.Remaining.Remove($Process.Id) }
		return $script:fakeResync.Window
	}
	function Stop-ResyncGameProcess($Process) {
		$script:fakeResync.StopCalls++
		if ($script:fakeResync.StopError) { throw $script:fakeResync.StopError }
		if (-not $script:fakeResync.IgnoreStop) { $script:fakeResync.Remaining.Remove($Process.Id) }
	}
	Test 'a game that already exited needs no close or force operation' {
		Set-FakeResync @()
		Assert (-not (Stop-GameForResync { throw 'no progress needed' })) 'already gone'
		Assert ($script:fakeResync.CloseCalls -eq 0 -and $script:fakeResync.StopCalls -eq 0) 'nothing touched'
	}
	Test 'normal window close is allowed to finish before forcing' {
		Set-FakeResync; $script:fakeResync.CloseExits = $true
		Assert (Stop-GameForResync $tick) 'closed'
		Assert ($script:fakeResync.CloseCalls -eq 1 -and $script:fakeResync.StopCalls -eq 0) 'no forced stop'
	}
	Test 'a windowless game is forced immediately after the confirmed resync' {
		Set-FakeResync @(41, 42); $script:fakeResync.Window = $false
		$t0 = [DateTime]::UtcNow
		Assert (Stop-GameForResync $tick -waitSeconds 5) 'stopped'
		Assert ($script:fakeResync.StopCalls -eq 2) 'all TF3 processes stopped'
		Assert (([DateTime]::UtcNow - $t0).TotalSeconds -lt 1) 'no pointless window wait'
	}
	Test 'an optional caller may still decline the forced stop' {
		Set-FakeResync
		$err = ''; try { Stop-GameForResync $tick { $false } 0 | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -like 'TF3 läuft noch*' -and $script:fakeResync.StopCalls -eq 0) $err
	}
	Test 'force access denied is surfaced with a useful rights explanation' {
		Set-FakeResync; $script:fakeResync.StopError = 'Access denied (PID 41)'
		$err = ''; try { Stop-GameForResync $tick -waitSeconds 0 | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -like '*Access denied*' -and $err -like '*denselben Rechten*') $err
		Assert ($script:fakeResync.StopCalls -eq 1) 'no silent retry'
	}
	Test 'a process that survives force is bounded by the force deadline' {
		Set-FakeResync; $script:fakeResync.IgnoreStop = $true
		$err = ''; try { Stop-GameForResync $tick -waitSeconds 0 -forceWaitSeconds 0 | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -like '*läuft nach dem Beenden weiter*41*') $err
		Assert ($script:fakeResync.StopCalls -eq 1) 'one force operation'
	}
	Test 'cancellation before closing leaves the process untouched' {
		Set-FakeResync
		$err = ''; try { Stop-GameForResync { $true } | Out-Null } catch { $err = $_.Exception.Message }
		Assert ($err -eq 'Abgebrochen.' -and $script:fakeResync.CloseCalls -eq 0 -and $script:fakeResync.StopCalls -eq 0) $err
	}
} finally { foreach ($name in $originalAdapters.Keys) { Set-Item "Function:\$name" $originalAdapters[$name] } }

$resolvedBase = [IO.Path]::GetFullPath($base)
if (-not $resolvedBase.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped TEMP.' }
Remove-Item -LiteralPath $resolvedBase -Recurse -Force
Write-Host "$passed resync tests passed, $failed failed"
if ($failed -gt 0) { exit 1 }

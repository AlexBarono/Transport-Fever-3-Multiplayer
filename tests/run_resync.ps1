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

# ---------- v35: Neuabgleich im laufenden Spiel ----------
function Live($extra) {
	$v = @{ pid = '41'; mode = 'host'; ready = '1'; world = 'same'; world_peer = 'same'; error = ''; resync = '-'; resync_peer = ''; epoch = '0' }
	foreach ($k in $extra.Keys) { $v[$k] = $extra[$k] }
	return $v
}
# v37: eine Abweichung im Aufbau bei $LiveResyncConfirmChecks Weltprüfungen hintereinander und
# $LiveResyncConfirmSeconds lang. Gibt den Grund der letzten Abfrage zurück.
function Confirm-Diff($m, [datetime]$t, $extra = @{}) {
	$r = $null
	for ($i = 0; $i -lt $LiveResyncConfirmChecks; $i++) {
		$v = @{ world = 'diff'; world_fields = 'hcon'; world_ck = [string](5 + $i) }
		foreach ($k in $extra.Keys) { $v[$k] = $extra[$k] }
		$r = Get-LiveResyncReason (Live $v) $m $t.AddSeconds($i * ($LiveResyncConfirmSeconds + 1) / ($LiveResyncConfirmChecks - 1))
	}
	return $r
}
function Check($m, [datetime]$t, [string]$ck, [string]$fields, [string]$world = 'diff') {
	return Get-LiveResyncReason (Live @{ world = $world; world_fields = $fields; world_ck = $ck }) $m $t
}
Test 'live resync starts on a lasting difference in the build-up, not on drift' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	Assert ($null -eq (Get-LiveResyncReason (Live @{}) $m $t)) 'nothing while the worlds agree'
	for ($i = 0; $i -lt 10; $i++) { Assert ($null -eq (Check $m $t.AddMinutes($i) ([string](5 + $i)) 'hpos,htown,hcargo')) "drift $i" }
	Assert ($null -eq (Get-LiveResyncReason (Live @{ world_peer = 'diff'; world_ck = '20' }) $m $t.AddMinutes(20))) 'only the partner sees it: its launcher asks'
	$m = New-LiveResyncMemory
	Assert ($null -eq (Check $m $t '5' 'hpos,hcon')) 'first check'
	Assert ($null -eq (Check $m $t.AddSeconds(20) '6' 'hcon,hpos')) 'second check'
	Assert ($null -eq (Check $m $t.AddSeconds(40) '7' 'hcon')) 'third check, but too short'
	$r = Check $m $t.AddSeconds($LiveResyncConfirmSeconds + 1) '7' 'hcon'
	Assert ($r.Kind -eq 'diff' -and $r.Detail -eq 'hcon') "reason $($r.Kind) $($r.Detail)"
	$m = New-LiveResyncMemory
	Assert ($null -eq (Check $m $t '5' 'hline')) 'one'
	Assert ($null -eq (Check $m $t.AddSeconds(90) '5' 'hline')) 'the same check does not count twice'
	Assert ($null -eq (Check $m $t.AddSeconds(100) '6' 'hline')) 'two'
	Assert ((Check $m $t.AddSeconds(110) '7' 'hline' 'checking').Kind -eq 'diff') 'three, also while the mod still says checking'
	foreach ($field in 'hedge', 'hline', 'hveh', 'loan') { Assert ((Confirm-Diff (New-LiveResyncMemory) $t @{ world_fields = $field }).Kind -eq 'diff') $field }
	Assert ($null -eq (Confirm-Diff (New-LiveResyncMemory) $t @{ mode = 'loopback' })) 'not in the solo test'
	Assert ($null -eq (Confirm-Diff (New-LiveResyncMemory) $t @{ ready = '0' })) 'not before the world is ready'
	Assert ($null -eq (Confirm-Diff (New-LiveResyncMemory) $t @{ resync = 'armed' })) 'not while a reload is armed'
}
Test 'short differences in different fields do not add up' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	$fields = 'hveh', 'hline', 'hveh', 'hline', 'hveh', 'hline'
	for ($i = 0; $i -lt $fields.Count; $i++) {
		Assert ($null -eq (Check $m $t.AddSeconds(60 * $i) ([string](10 + $i)) "hpos,$($fields[$i])")) "check $i"
	}
	Assert ($null -eq (Check $m $t.AddSeconds(400) '16' 'hpos,hline')) 'hline twice in a row'
	Assert ((Check $m $t.AddSeconds(460) '17' 'hpos,hline').Kind -eq 'diff') 'three times in a row'
}
Test 'a difference that goes away in between starts counting again' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	$null = Check $m $t '5' 'hveh'
	$null = Check $m $t.AddSeconds(30) '6' 'hveh'
	$null = Check $m $t.AddSeconds(60) '7' '' 'same'
	Assert ($null -eq (Check $m $t.AddSeconds(90) '8' 'hveh')) 'seen again: first time'
	Assert ($null -eq (Check $m $t.AddSeconds(120) '9' 'hveh')) 'second'
	Assert ($null -eq (Check $m $t.AddSeconds(150) '10' 'hpos')) 'now drift only'
	Assert ($null -eq (Check $m $t.AddSeconds(180) '11' 'hveh')) 'first time again'
	Assert ($null -eq (Check $m $t.AddSeconds(210) '12' 'hveh')) 'second again'
	Assert ((Check $m $t.AddSeconds(240) '13' 'hveh').Kind -eq 'diff') 'lasting'
}
Test 'a stopped common timeline resyncs after half a minute without world checks' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	Assert ($null -eq (Check $m $t '9' 'clock')) 'just stopped'
	Assert ($null -eq (Check $m $t.AddSeconds(20) '9' 'clock')) 'not yet'
	$r = Check $m $t.AddSeconds($LiveResyncClockSeconds + 1) '9' 'clock'
	Assert ($r.Kind -eq 'clock') "reason $($r.Kind)"
	$m = New-LiveResyncMemory
	$null = Check $m $t '9' 'clock'
	$null = Check $m $t.AddSeconds(20) '10' 'hpos'
	Assert ($null -eq (Check $m $t.AddSeconds(40) '10' 'clock')) 'gone in between: counts again'
}
Test 'a reload request left hanging by a failed attempt does not stop the next one' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	$hanging = Live @{ error = 'game rejected 1-2-3'; resync = 'armed' }
	Assert ($null -eq (Get-LiveResyncReason $hanging $m $t)) 'armed while nothing failed: TF3 is loading'
	Register-LiveResync $m $t
	Complete-LiveResync $m $false $t.AddSeconds(130)
	Assert ((Get-LiveResyncReason $hanging $m $t.AddSeconds(130 + $LiveResyncRetrySeconds + 1)).Kind -eq 'error') 'tried again'
}
Test 'live resync starts on a rejected action but not on a broken session' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	Assert ((Get-LiveResyncReason (Live @{ error = 'peer rejected 41-7-3' }) $m $t).Kind -eq 'error') 'peer rejected'
	Assert ((Get-LiveResyncReason (Live @{ error = 'save reloaded with pending actions; restart' }) $m $t).Kind -eq 'error') 'pending reload'
	Assert ($null -eq (Get-LiveResyncReason (Live @{ error = 'multiplayer package differs; use the same release' }) $m $t)) 'package differs'
}
Test 'live resync waits between attempts and stops after the most per game' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	$broken = Live @{ error = 'game rejected 1-2-3' }
	for ($i = 1; $i -le $LiveResyncMax; $i++) {
		Assert ((Get-LiveResyncReason $broken $m $t).Kind -eq 'error') "attempt $i"
		Register-LiveResync $m $t
		Complete-LiveResync $m $true $t.AddSeconds(20)
		Assert ($null -eq (Get-LiveResyncReason $broken $m $t.AddSeconds(100))) "cooldown $i"
		$t = $t.AddSeconds($LiveResyncCooldownSeconds + 21)
	}
	Assert ($null -eq (Get-LiveResyncReason $broken $m $t)) 'no attempt beyond the most'
	Assert ((Get-LiveResyncReason (Live @{ error = 'game rejected 1-2-3'; pid = '42' }) $m $t).Kind -eq 'error') 'a new TF3 starts again'
}
Test 'a failed live resync is tried again soon, each further failure waits longer' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	$broken = Live @{ error = 'game rejected 1-2-3' }
	$expected = @($LiveResyncRetrySeconds, ($LiveResyncRetrySeconds * 2), ($LiveResyncRetrySeconds * 4), $LiveResyncCooldownSeconds)
	foreach ($pause in $expected) {
		Assert ((Get-LiveResyncReason $broken $m $t).Kind -eq 'error') "attempt before pause $pause"
		Register-LiveResync $m $t
		$t = $t.AddSeconds(90)
		Complete-LiveResync $m $false $t
		Assert ((Get-LiveResyncPause $m) -eq $pause) "pause $(Get-LiveResyncPause $m), expected $pause"
		Assert ($null -eq (Get-LiveResyncReason $broken $m $t.AddSeconds($pause - 1))) "still waiting before $pause"
		$t = $t.AddSeconds($pause + 1)
	}
	Register-LiveResync $m $t
	Complete-LiveResync $m $true $t
	Assert ((Get-LiveResyncPause $m) -eq $LiveResyncCooldownSeconds -and $m.Failures -eq 0) 'success resets'
	# A difference has to last again after a reload.
	$m = New-LiveResyncMemory
	Assert ((Confirm-Diff $m $t).Kind -eq 'diff') 'difference'
	Register-LiveResync $m $t.AddSeconds(200)
	Complete-LiveResync $m $false $t.AddSeconds(220)
	Assert ($null -eq (Check $m $t.AddSeconds(260) '5' 'hcon')) 'counts again from the start'
	Assert ($null -eq (Check $m $t.AddSeconds(290) '6' 'hcon')) 'second'
	Assert ((Check $m $t.AddSeconds(330) '7' 'hcon').Kind -eq 'diff') 'still there: again'
}
Test 'a request of the partner counts once' {
	$m = New-LiveResyncMemory; $t = [DateTime]::UtcNow
	Assert ($null -eq (Get-LiveResyncReason (Live @{ mode = 'client'; resync_peer = '' }) $m $t)) 'nothing yet'
	$r = Get-LiveResyncReason (Live @{ mode = 'client'; resync_peer = '1' }) $m $t
	Assert ($r.Kind -eq 'peer') 'first request'
	Register-LiveResync $m $t
	$t = $t.AddSeconds($LiveResyncCooldownSeconds + 1)
	Assert ($null -eq (Get-LiveResyncReason (Live @{ mode = 'client'; resync_peer = '1' }) $m $t)) 'same request again'
	Assert ((Get-LiveResyncReason (Live @{ mode = 'client'; resync_peer = '2' }) $m $t).Kind -eq 'peer') 'next request'
	# A request that is already there when the launcher (or a new TF3) starts is old.
	$fresh = New-LiveResyncMemory
	Assert ($null -eq (Get-LiveResyncReason (Live @{ mode = 'client'; resync_peer = '7' }) $fresh $t)) 'old request at the start'
	# Both games noticed it themselves: the partner's request inside the waiting time is used up.
	$m2 = New-LiveResyncMemory; $t2 = [DateTime]::UtcNow
	Assert ((Confirm-Diff $m2 $t2).Kind -eq 'diff') 'own difference'
	Register-LiveResync $m2 $t2
	Assert ($null -eq (Get-LiveResyncReason (Live @{ resync_peer = '5' }) $m2 $t2.AddSeconds(5))) 'inside the waiting time'
	Assert ($null -eq (Get-LiveResyncReason (Live @{ resync_peer = '5' }) $m2 $t2.AddSeconds($LiveResyncCooldownSeconds + 1))) 'not again later'
}
Test 'the epoch of the partner comes from the DLL log of this TF3' {
	$dir = Join-Path $base 'epoch'; New-Item -ItemType Directory -Force $dir | Out-Null
	$log = Join-Path $dir 'alut_proxy.log'
	Assert ((Get-PeerEpoch $log '41') -eq -1) 'no log'
	[IO.File]::WriteAllText($log, ("2026-10-09 10:00:00 [41] net: peer in resync epoch 1, this game in 0`r`n" +
		"2026-10-09 10:00:01 [77] net: peer in resync epoch 9, this game in 9`r`n" +
		"2026-10-09 10:00:02 [41] net: in-game resync 1 armed`r`n" +
		"2026-10-09 10:00:03 [41] net: peer in resync epoch 2, this game in 1`r`n"))
	Assert ((Get-PeerEpoch $log '41') -eq 2) 'latest of this TF3'
	Assert ((Get-PeerEpoch $log '77') -eq 9) 'other process'
	Assert ((Get-PeerEpoch $log '5') -eq -1) 'never logged'
	Assert ((Get-PeerEpoch $log '41' 60) -eq 2) 'from the tail only'
}
Test 'a resync that worked only on the partner is caught up once with the last shared save' {
	$dir = Join-Path $base 'catch'; New-Item -ItemType Directory -Force $dir | Out-Null
	$save = Join-Path $dir 'TF3MP-Sync-20261009-100000.sav'; [IO.File]::WriteAllText($save, 's')
	$m = New-LiveResyncMemory; $m.LastSave = $save
	$behind = Live @{ connected = '0'; epoch = '1' }
	Assert ($null -eq (Get-EpochCatchUp $behind $m -1)) 'partner epoch unknown'
	Assert ($null -eq (Get-EpochCatchUp $behind $m 1)) 'same epoch'
	Assert ($null -eq (Get-EpochCatchUp $behind $m 3)) 'more than one ahead'
	Assert ($null -eq (Get-EpochCatchUp (Live @{ connected = '1'; epoch = '1' }) $m 2)) 'connected'
	Assert ((Get-EpochCatchUp (Live @{ connected = '0'; epoch = '1'; resync = 'armed' }) $m 2) -eq $save) 'one ahead (a stuck reload request does not matter): load the last shared save'
	Assert ($null -eq (Get-EpochCatchUp $behind $m 2)) 'only once'
	$m2 = New-LiveResyncMemory; $m2.LastSave = (Join-Path $dir 'fehlt.sav')
	Assert ($null -eq (Get-EpochCatchUp $behind $m2 2)) 'no save, nothing to load'
	Assert ($null -eq (Get-EpochCatchUp (Live @{ connected = '0'; epoch = '1'; mode = 'loopback' }) $m 2)) 'not in the solo test'
}
Test 'the copy waits while TF3 is still saving' {
	$dir = Join-Path $base 'busy'; New-Item -ItemType Directory -Force $dir | Out-Null
	$orig = Join-Path $dir "$ResyncSaveName.sav"; [IO.File]::WriteAllText($orig, 'alt')
	[IO.File]::WriteAllText("$orig.tmp", 'neu')
	$writer = Start-Job -ScriptBlock { param($p) Start-Sleep -Milliseconds 800; Remove-Item -LiteralPath "$p.tmp"; [IO.File]::WriteAllText($p, 'neu') } -ArgumentList $orig
	try {
		$t0 = [DateTime]::UtcNow
		$copy = Copy-SaveSnapshot (Get-Item -LiteralPath $orig) $dir (Get-Date) 10
		Wait-Job $writer -Timeout 30 | Out-Null
		Assert (([DateTime]::UtcNow - $t0).TotalSeconds -ge 0.5) 'waited for TF3'
		Assert ((Get-Content -LiteralPath $copy.FullName -Raw) -eq 'neu') 'copied the finished save'
	} finally { Remove-Job $writer -Force }
}
Test 'the host sends its own copy of the fresh save' {
	$dir = Join-Path $base 'snap'; New-Item -ItemType Directory -Force $dir | Out-Null
	$orig = Join-Path $dir "$ResyncSaveName.sav"
	$bytes = New-Object byte[] 300000; (New-Object Random 7).NextBytes($bytes)
	[IO.File]::WriteAllBytes($orig, $bytes); [IO.File]::WriteAllText((Join-Path $dir "$ResyncSaveName.jpg"), 'bild')
	$written = [DateTime]::UtcNow.AddMinutes(-3); [IO.File]::SetLastWriteTimeUtc($orig, $written)
	$when = Get-Date -Year 2026 -Month 10 -Day 9 -Hour 1 -Minute 2 -Second 3
	$copy = Copy-SaveSnapshot (Get-Item -LiteralPath $orig) $dir $when
	Assert ($copy.Name -eq 'TF3MP-Sync-20261009-010203.sav') $copy.Name
	Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($copy.FullName)) -eq [Convert]::ToBase64String($bytes)) 'same bytes'
	Assert ((Get-Content -LiteralPath ([IO.Path]::ChangeExtension($copy.FullName, '.jpg')) -Raw) -eq 'bild') 'preview copied'
	Assert ([Math]::Abs(($copy.LastWriteTimeUtc - $written).TotalSeconds) -lt 2) 'time of the original'
	$second = Copy-SaveSnapshot (Get-Item -LiteralPath $orig) $dir $when
	Assert ($second.Name -eq 'TF3MP-Sync-20261009-010203-2.sav') $second.Name
	Remove-Item -LiteralPath (Join-Path $dir "$ResyncSaveName.jpg")
	$third = Copy-SaveSnapshot (Get-Item -LiteralPath $orig) $dir $when.AddSeconds(1)
	Assert (-not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($third.FullName, '.jpg')))) 'no preview, none copied'
	$gone = New-Object IO.FileInfo (Join-Path $dir 'fehlt.sav')
	$err = ''; try { Copy-SaveSnapshot $gone $dir $when.AddSeconds(2) | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*nicht für den Neuabgleich kopiert*') $err
	Assert (@(Get-ChildItem -LiteralPath $dir -Filter '*.part').Count -eq 0) 'no part file left'
	# Opened the way the copy opens it, the save can still be deleted (on Windows this needs FileShare Delete;
	# whether TF3's rename over an open save works depends on Windows, so the copy keeps it open only briefly).
	$reader = [IO.File]::Open($orig, 'Open', 'Read', [IO.FileShare]'ReadWrite, Delete')
	try {
		$deleted = $true; try { [IO.File]::Delete($orig) } catch { $deleted = $false }
		Assert $deleted 'TF3 can replace the save while the launcher reads it'
	} finally { $reader.Dispose() }
}
Test 'old sync copies are cleaned up, the newest stay' {
	$dir = Join-Path $base 'clean'; New-Item -ItemType Directory -Force $dir | Out-Null
	$t = [DateTime]::UtcNow
	for ($i = 1; $i -le 4; $i++) {
		$p = Join-Path $dir "TF3MP-Sync-2026100$i.sav"; [IO.File]::WriteAllText($p, "$i"); [IO.File]::SetLastWriteTimeUtc($p, $t.AddMinutes($i))
		[IO.File]::WriteAllText([IO.Path]::ChangeExtension($p, '.jpg'), 'j')
	}
	[IO.File]::WriteAllText((Join-Path $dir 'Mein Stand.sav'), 'x')
	[IO.File]::SetLastWriteTimeUtc((Join-Path $dir 'Mein Stand.sav'), $t.AddMinutes(-10))
	$keep = Join-Path $dir 'TF3MP-Sync-20261001.sav'
	Assert ((Remove-OldSyncSaves $dir 2 $keep) -eq 1) 'one removed'
	$left = @(Get-ChildItem -LiteralPath $dir -Filter '*.sav' | ForEach-Object { $_.Name } | Sort-Object)
	Assert (($left -join '|') -eq 'Mein Stand.sav|TF3MP-Sync-20261001.sav|TF3MP-Sync-20261003.sav|TF3MP-Sync-20261004.sav') ($left -join '|')
	Assert (-not (Test-Path -LiteralPath (Join-Path $dir 'TF3MP-Sync-20261002.jpg'))) 'its preview too'
	Assert ((Remove-OldSyncSaves $dir 2) -eq 1) 'without the exception'
	Assert ((Remove-OldSyncSaves (Join-Path $dir 'fehlt') 2) -eq 0) 'missing folder'
}
Test 'the game saving by itself gets its own waiting text' {
	$dir = Join-Path $base 'leer'; New-Item -ItemType Directory -Force $dir | Out-Null
	$seen = New-Object System.Collections.ArrayList
	$err = ''; try { Wait-NewSave $dir ([DateTime]::UtcNow) { param($a, $b, $c) [void]$seen.Add($a); $true } 30 -waitText 'Das Spiel speichert ...' | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -eq 'Abgebrochen.' -and $seen[0] -eq 'Das Spiel speichert ...') "$err / $($seen[0])"
}
Test 'requests for the DLL and the reload name' {
	$dir = Join-Path $base 'game'; New-Item -ItemType Directory -Force $dir | Out-Null
	$path = Write-ProxyRequest $dir 'alut_proxy.reload' 'name=TF3MP-Neuabgleich'
	Assert ((Get-Content -LiteralPath $path -Raw) -eq "name=TF3MP-Neuabgleich`r`n") 'request text'
	Assert (-not (Test-Path -LiteralPath "$path.tmp")) 'no temp file left'
	Assert ((Get-LiveReloadName (Join-Path $saves 'TF3MP-Neuabgleich.sav')) -eq 'TF3MP-Neuabgleich') 'name'
	$err = ''; try { Get-LiveReloadName 'C:\x\a"b.sav' | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*geht nicht*') $err
}
Test 'the launcher waits for the reload and explains a refused one' {
	$dir = Join-Path $base 'game'; $status = Join-Path $dir 'alut_proxy.status'
	[IO.File]::WriteAllText($status, "mode=host`r`nepoch=1`r`nresync=-`r`n")
	Assert (Wait-LiveReload $status 0 $tick 5) 'epoch went up'
	[IO.File]::WriteAllText($status, "mode=host`r`nepoch=1`r`nresync=-`r`n")
	$reload = Join-Path $dir 'alut_proxy.reload'
	if (Test-Path $reload) { Remove-Item $reload }
	$t0 = [DateTime]::UtcNow
	$err = ''; try { Wait-LiveReload $status 1 $tick 30 $reload | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*nicht angenommen*') $err
	Assert (([DateTime]::UtcNow - $t0).TotalSeconds -lt 10) 'refusal noticed quickly'
	[IO.File]::WriteAllText($status, "mode=host`r`nepoch=1`r`nresync=armed`r`n")
	$err = ''; try { Wait-LiveReload $status 1 $tick 1 | Out-Null } catch { $err = $_.Exception.Message }
	Assert ($err -like '*nicht geladen*') $err
	Assert ((Read-ProxyStatusValues $status).resync -eq 'armed') 'status values'
	Assert ((Read-ProxyStatusValues (Join-Path $dir 'fehlt')).Count -eq 0) 'missing status'
}

$resolvedBase = [IO.Path]::GetFullPath($base)
if (-not $resolvedBase.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped TEMP.' }
Remove-Item -LiteralPath $resolvedBase -Recurse -Force
Write-Host "$passed resync tests passed, $failed failed"
if ($failed -gt 0) { exit 1 }

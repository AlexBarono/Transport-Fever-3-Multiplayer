# Neuabgleich mit einem Klick (Launcher, Probe v32).
# Findet der Weltvergleich eine Abweichung, speichert der Mod des Gastgebers das Spiel selbst als
# 'TF3MP-Neuabgleich' (mods\mp_probe\content\mp_probe\gui.lua). 'Neu abgleichen' nimmt beim Gastgeber
# den neuesten Spielstand, der seit dem Spielstart geschrieben wurde, beendet TF3, schickt ihn und
# startet neu. Der Mitspieler beendet TF3, wartet auf den Gastgeber, holt den Stand und startet neu.
# Ohne Fenster, damit tests\run_resync.ps1 die Teile auch ohne Windows prüfen kann.

if (-not (Get-Command Test-SessionLink -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'session.ps1') }

$ResyncSaveName = 'TF3MP-Neuabgleich'
$GameProcessName = 'TransportFever3'

# Startzeit (UTC) des laufenden TF3, $null wenn es nicht läuft oder Windows sie nicht verrät.
function Get-GameStartTime([string]$ProcessName = $GameProcessName) {
	try {
		$game = Get-Process -Name $ProcessName -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1
		if ($game) { return $game.StartTime.ToUniversalTime() }
	} catch {}
	return $null
}

# Der neueste Spielstand (*.sav) im Ordner, geschrieben ab $since (UTC); $null, wenn es keinen gibt.
function Find-ResyncSave([string]$saveDir, [datetime]$since) {
	$files = @(Get-ChildItem -LiteralPath $saveDir -Filter '*.sav' -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Extension -ieq '.sav' -and $_.LastWriteTimeUtc -ge $since -and -not (Test-SessionLink $_) } |
		Sort-Object LastWriteTimeUtc -Descending)
	if ($files.Count -eq 0) { return $null }
	return $files[0]
}

# Ob niemand mehr in die Datei schreibt (das Spiel hält sie beim Speichern offen).
function Test-FileClosed([string]$path) {
	try { $stream = [IO.File]::Open($path, 'Open', 'Read', 'None'); $stream.Dispose(); return $true } catch { return $false }
}

# Wartet, bis der Spielstand fertig geschrieben ist: 2 Sekunden gleich groß und nicht mehr geöffnet.
# $tick (Text, erledigt, gesamt) gibt $true zurück, wenn abgebrochen werden soll.
function Wait-SaveWritten($file, $tick, [int]$timeoutSeconds = 180, [double]$quietSeconds = 2) {
	$deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
	$lastSize = [int64]-1; $lastTime = [datetime]::MinValue; $stableSince = [DateTime]::UtcNow
	while ($true) {
		$file.Refresh()
		$size = if ($file.Exists) { [int64]$file.Length } else { [int64]-1 }
		$time = if ($file.Exists) { $file.LastWriteTimeUtc } else { [datetime]::MinValue }
		if ($size -ne $lastSize -or $time -ne $lastTime) { $lastSize = $size; $lastTime = $time; $stableSince = [DateTime]::UtcNow }
		elseif ($size -gt 0 -and ([DateTime]::UtcNow - $stableSince).TotalSeconds -ge $quietSeconds -and (Test-FileClosed $file.FullName)) { return $file }
		if ([DateTime]::UtcNow -gt $deadline) { throw "Der Spielstand '$($file.BaseName)' wird noch geschrieben. Bitte warten, bis das Spiel fertig gespeichert hat, und erneut 'Neu abgleichen' klicken." }
		if (& $tick "Warte, bis '$($file.BaseName)' fertig gespeichert ist ..." 0 0) { throw 'Abgebrochen.' }
		Start-Sleep -Milliseconds 200
	}
}

# Wartet auf einen Spielstand, den der Spieler jetzt im Spiel speichert (geschrieben ab $since, UTC).
function Wait-NewSave([string]$saveDir, [datetime]$since, $tick, [int]$timeoutSeconds = 900, [double]$quietSeconds = 2) {
	$deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
	while ($true) {
		$file = Find-ResyncSave $saveDir $since
		if ($file) { return Wait-SaveWritten $file $tick -quietSeconds $quietSeconds }
		if ([DateTime]::UtcNow -gt $deadline) { throw 'Es wurde kein neuer Spielstand gespeichert. Der Neuabgleich ist abgebrochen.' }
		if (& $tick "Bitte jetzt im Spiel speichern (Esc, dann Speichern). Der Name ist egal, der Launcher erkennt den neuen Spielstand von selbst und beendet danach TF3." 0 0) { throw 'Abgebrochen.' }
		Start-Sleep -Milliseconds 500
	}
}

# Kleine Prozessadapter erlauben auch auf Windows Tests ohne das echte Spiel zu schließen.
function Get-ResyncGameProcesses([string]$ProcessName) { return @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) }
function Close-ResyncGameWindow($Process) {
	try { if ($Process.HasExited) { return $true }; return [bool]$Process.CloseMainWindow() } catch { return $false }
}
function Stop-ResyncGameProcess($Process) {
	try { Stop-Process -Id $Process.Id -Force -ErrorAction Stop }
	catch {
		if (-not (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue)) { return }
		throw "TF3-Prozess $($Process.Id) konnte nicht beendet werden: $($_.Exception.Message)"
	}
}

# Der ausdrücklich bestätigte Neuabgleich darf nach gesichertem Gastgeber-Spielstand TF3 beenden.
# Zuerst normal schließen, nach kurzer Frist direkt beenden; kein verschluckter Zugriffsfehler.
# Ein optionales $askForce bleibt für andere Aufrufer erhalten; ohne Callback gilt die Bestätigung
# des Neuabgleichs. Während der Wartezeit bleibt die Oberfläche bedienbar.
function Stop-GameForResync($tick, $askForce = $null, [double]$waitSeconds = 5, [string]$ProcessName = $GameProcessName, [double]$forceWaitSeconds = 10) {
	$processes = @(Get-ResyncGameProcesses $ProcessName)
	if (-not $processes.Count) { return $false }
	if (& $tick 'Beende TF3 für den bestätigten Neuabgleich ...' 0 0) { throw 'Abgebrochen.' }
	$windowRequested = $false
	foreach ($process in $processes) { if (Close-ResyncGameWindow $process) { $windowRequested = $true } }
	$deadline = [DateTime]::UtcNow.AddSeconds($(if ($windowRequested) { $waitSeconds } else { 0 }))
	$forced = $false
	while ($true) {
		$processes = @(Get-ResyncGameProcesses $ProcessName)
		if (-not $processes.Count) { return $true }
		if ([DateTime]::UtcNow -ge $deadline) {
			$ids = ($processes | ForEach-Object { $_.Id }) -join ', '
			if ($forced) { throw "TF3 läuft nach dem Beenden weiter (Prozess $ids). Bitte im Task-Manager beenden und erneut 'Neu abgleichen' klicken." }
			if ($askForce -and -not (& $askForce)) { throw "TF3 läuft noch. Bitte das Spiel selbst beenden und erneut auf 'Neu abgleichen' klicken." }
			if (& $tick "TF3 reagiert nicht auf Schließen. Beende Prozess $ids ..." 0 0) { throw 'Abgebrochen.' }
			$errors = @()
			foreach ($process in $processes) { try { Stop-ResyncGameProcess $process } catch { $errors += $_.Exception.Message } }
			if ($errors.Count -and @(Get-ResyncGameProcesses $ProcessName).Count) {
				throw (($errors -join "`r`n") + "`r`nBitte TF3 im Task-Manager beenden. TF3 und Launcher anschließend mit denselben Rechten starten (beide ohne Administrator).")
			}
			$forced = $true
			$deadline = [DateTime]::UtcNow.AddSeconds($forceWaitSeconds)
		}
		$left = [int][Math]::Ceiling([Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalSeconds))
		$text = if ($forced) { "Warte auf das Ende des TF3-Prozesses (höchstens noch $left Sekunden) ..." } else { "TF3 wird geschlossen (höchstens noch $left Sekunden) ..." }
		if (& $tick $text 0 0) { throw 'Abgebrochen.' }
		Start-Sleep -Milliseconds 100
	}
}

# ---------- v35: Neuladen im laufenden Spiel ----------
# Bei einer kleinen Abweichung bleibt TF3 offen: Der Gastgeber schickt den Stand, den sein Spiel gerade
# gespeichert hat, der Mitspieler holt ihn, und beide Launcher bitten über die DLL (alut_proxy.reload,
# DLL v13) das laufende Spiel, ihn zu laden (gui.lua, app.loadGame). Höchstens $LiveResyncMax-mal pro
# Spielstart und mit $LiveResyncCooldownSeconds Abstand; danach bleibt der Knopf 'Neu abgleichen'.
$LiveResyncCooldownSeconds = 180
$LiveResyncMax = 3
# Fehler, nach denen beide Welten noch geladen sind und ein gemeinsamer Stand weiterhilft.
$LiveResyncErrors = '^(peer rejected|game rejected|save reloaded with pending)'

# Die Zeilen von alut_proxy.status als Hashtable; leer, wenn die Datei fehlt.
function Read-ProxyStatusValues([string]$Path) {
	$values = @{}
	if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
	foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) { if ($line -match '^(\w+)=(.*)$') { $values[$matches[1]] = $matches[2] } }
	return $values
}

function New-LiveResyncMemory { return @{ Pid = ''; Count = 0; LastUtc = [datetime]::MinValue; PeerReq = '' } }

# Warum dieses Spiel jetzt im laufenden Spiel neu abgleichen soll: @{Kind='diff'|'error'|'peer'; Detail}
# oder $null. Kind 'peer': der Launcher des Mitspielers hat einen Neuabgleich verlangt (DLL-Status
# resync_peer, neu seit dem letzten Mal). Zählt nichts mit; das macht Register-LiveResync beim Start.
function Get-LiveResyncReason($Values, $Memory, [datetime]$NowUtc) {
	if (-not $Values -or ($Values.mode -ne 'host' -and $Values.mode -ne 'client')) { return $null }
	# Ein neu gestartetes TF3 (andere Prozessnummer) beginnt wieder bei null.
	if ($Values.pid -and $Values.pid -ne $Memory.Pid) {
		$Memory.Pid = $Values.pid; $Memory.Count = 0; $Memory.LastUtc = [datetime]::MinValue; $Memory.PeerReq = ''
	}
	$peerReq = [string]$Values.resync_peer
	$peerNew = $peerReq -and $peerReq -ne $Memory.PeerReq
	# Eine Bitte gilt einmal, auch wenn sie in die Wartezeit fällt (dann gleichen beide schon ab).
	if ($peerReq) { $Memory.PeerReq = $peerReq }
	if ($Values.resync -eq 'armed' -or $Values.ready -ne '1') { return $null }
	if ($Memory.Count -ge $LiveResyncMax) { return $null }
	if (($NowUtc - $Memory.LastUtc).TotalSeconds -lt $LiveResyncCooldownSeconds) { return $null }
	if ($Values.world -eq 'diff' -or $Values.world_peer -eq 'diff') { return @{ Kind = 'diff'; Detail = [string]$Values.world_fields } }
	if ([string]$Values.error -match $LiveResyncErrors) { return @{ Kind = 'error'; Detail = [string]$Values.error } }
	if ($peerNew) { return @{ Kind = 'peer'; Detail = $peerReq } }
	return $null
}

function Register-LiveResync($Memory, [datetime]$NowUtc) { $Memory.Count++; $Memory.LastUtc = $NowUtc }

# Bittet die DLL neben dem Spiel um etwas (alut_proxy.save oder alut_proxy.reload); sie nimmt die Datei
# etwa einmal pro Sekunde und löscht sie.
function Write-ProxyRequest([string]$GameDir, [string]$Name, [string]$Text = '') {
	$path = Join-Path $GameDir $Name
	$temp = "$path.tmp"
	[IO.File]::WriteAllText($temp, "$Text`r`n", (New-Object Text.ASCIIEncoding))
	Move-Item -LiteralPath $temp -Destination $path -Force
	return $path
}

# Name des Spielstands für alut_proxy.reload: so, wie TF3 ihn beim Laden ins Protokoll schreibt.
function Get-LiveReloadName([string]$SavePath) {
	$name = [IO.Path]::GetFileNameWithoutExtension($SavePath)
	if (-not $name -or $name -match '[\\/:"]' -or $name -match '[\x00-\x1f]' -or $name.Length -gt 250) { throw "Dieser Spielstandname geht nicht für das Neuladen im Spiel: '$name'" }
	return $name
}

# Wartet, bis die DLL das Neuladen angenommen (resync=armed) und das Spiel den Stand geladen hat
# (epoch größer als vorher). $true = geladen; wirft mit Erklärung, wenn nicht.
function Wait-LiveReload([string]$StatusPath, [int]$EpochBefore, $tick, [int]$TimeoutSeconds = 120, [string]$ReloadPath = '') {
	$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
	$armed = $false; $takenAt = $null
	while ($true) {
		$values = Read-ProxyStatusValues $StatusPath
		if ($values.epoch -match '^\d+$' -and [int]$values.epoch -gt $EpochBefore) { return $true }
		if ($values.resync -eq 'armed') { $armed = $true }
		# Die DLL hat die Bitte genommen, aber nicht angenommen (steht dann in alut_proxy.log).
		if (-not $armed -and $ReloadPath -and -not (Test-Path -LiteralPath $ReloadPath)) {
			if (-not $takenAt) { $takenAt = [DateTime]::UtcNow }
			elseif (([DateTime]::UtcNow - $takenAt).TotalSeconds -ge 3) { $deadline = [DateTime]::MinValue }
		}
		if ([DateTime]::UtcNow -gt $deadline) {
			if ($ReloadPath -and (Test-Path -LiteralPath $ReloadPath)) { Remove-Item -LiteralPath $ReloadPath -Force -ErrorAction SilentlyContinue }
			if ($armed) { throw 'TF3 hat den gemeinsamen Spielstand nicht geladen. Bitte auf beiden PCs "Neu abgleichen" klicken.' }
			throw 'Die Multiplayer-DLL hat das Neuladen nicht angenommen (alte DLL oder Fehler in der Sitzung). Bitte auf beiden PCs "Neu abgleichen" klicken.'
		}
		$text = if ($armed) { 'TF3 lädt den gemeinsamen Spielstand ...' } else { 'Bitte TF3, den gemeinsamen Spielstand zu laden ...' }
		if (& $tick $text 0 0) { throw 'Abgebrochen.' }
		Start-Sleep -Milliseconds 250
	}
}

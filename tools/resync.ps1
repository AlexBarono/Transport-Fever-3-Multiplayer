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
# v37: für einen Augenblick geöffnet, mit FileShare Delete (stört TF3 so wenig wie möglich).
function Test-FileClosed([string]$path) {
	try { $stream = [IO.File]::Open($path, 'Open', 'Read', 'Delete'); $stream.Dispose(); return $true } catch { return $false }
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
# $waitText ersetzt den Hinweis, wenn das Spiel selbst speichert (Neuabgleich im laufenden Spiel).
function Wait-NewSave([string]$saveDir, [datetime]$since, $tick, [int]$timeoutSeconds = 900, [double]$quietSeconds = 2, [string]$waitText = '') {
	$deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
	if (-not $waitText) { $waitText = "Bitte jetzt im Spiel speichern (Esc, dann Speichern). Der Name ist egal, der Launcher erkennt den neuen Spielstand von selbst und beendet danach TF3." }
	while ($true) {
		$file = Find-ResyncSave $saveDir $since
		if ($file) { return Wait-SaveWritten $file $tick -quietSeconds $quietSeconds }
		if ([DateTime]::UtcNow -gt $deadline) { throw 'Es wurde kein neuer Spielstand gespeichert. Der Neuabgleich ist abgebrochen.' }
		if (& $tick $waitText 0 0) { throw 'Abgebrochen.' }
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
# v37: mehr Versuche, weil ein fehlgeschlagener Neuabgleich jetzt von selbst wiederholt wird.
$LiveResyncMax = 6
# Fehler, nach denen beide Welten noch geladen sind und ein gemeinsamer Stand weiterhilft.
$LiveResyncErrors = '^(peer rejected|game rejected|save reloaded with pending)'
# v37 (Lauf 39): Nur Abweichungen im Aufbau lösen einen Neuabgleich aus: Bauwerke, Straßen/Gleise,
# Linien, Fahrzeuge, Kredite. Fahrzeugpositionen, Fracht und Städte laufen mit der Zeit auseinander,
# weil TF3s eigene Fenster Fahrzeugbefehle sofort ausführen; dafür ging jedes Mal das Spiel kurz aus
# der Hand. Sie bleiben ein Hinweis, 'Neu abgleichen' bleibt für Hand.
$LiveResyncStructural = @('hcon', 'hedge', 'hline', 'hveh', 'loan')
# Jedes dieser Felder muss für sich bei so vielen Weltprüfungen hintereinander abweichen und so
# lange. Eine Aktion, die beim Mitspieler gerade erst ankommt (ein gekaufter Bus, eine geänderte
# Linie), ist bis dahin auch dort; zwei verschiedene solche Momente zählen nicht zusammen.
$LiveResyncConfirmChecks = 3
$LiveResyncConfirmSeconds = 60
# Der gemeinsame Zeitplan ist stehen geblieben (world_fields 'clock'): Beide Spiele halten an und
# es gibt keine Weltprüfungen mehr, deshalb zählt hier nur die Zeit.
$LiveResyncClockSeconds = 30
# Nach einem fehlgeschlagenen Neuabgleich versucht der Launcher es nach dieser Zeit noch einmal,
# solange der Grund bleibt (statt auf einen Klick zu warten); jeder weitere Fehlschlag verdoppelt sie
# bis zur normalen Wartezeit.
$LiveResyncRetrySeconds = 30
# Eigene Namen für die Kopien, die der Gastgeber schickt; die neuesten bleiben liegen.
$LiveResyncSavePrefix = 'TF3MP-Sync-'
$LiveResyncKeepSaves = 2

# Die Zeilen von alut_proxy.status als Hashtable; leer, wenn die Datei fehlt.
function Read-ProxyStatusValues([string]$Path) {
	$values = @{}
	if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
	foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) { if ($line -match '^(\w+)=(.*)$') { $values[$matches[1]] = $matches[2] } }
	return $values
}

function New-LiveResyncMemory {
	return @{ Pid = ''; Count = 0; LastUtc = [datetime]::MinValue; PeerReq = ''; Failures = 0
		Ck = $null; Fields = @{}; ClockSinceUtc = [datetime]::MinValue; LastSave = ''; CatchUp = '' }
}

# Die Felder aus world_fields, die mehr als Drift sind (siehe $LiveResyncStructural), als Liste.
function Get-StructuralDifference([string]$Fields) {
	return @(@($Fields -split '[,\s]+') | Where-Object { $_ -and $LiveResyncStructural -contains $_ })
}

# Führt bei jeder neuen Weltprüfung (world_ck) mit, seit wann und bei wie vielen Prüfungen
# hintereinander jedes Feld im Aufbau abweicht. Gibt die bestätigten Felder zurück.
function Update-LiveResyncDifference($Values, $Memory, [datetime]$NowUtc) {
	$ck = [string]$Values.world_ck
	if ($ck -ne $Memory.Ck) {
		$Memory.Ck = $ck
		$listed = @()
		if ($Values.world -eq 'diff' -or $Values.world -eq 'checking') { $listed = @(Get-StructuralDifference ([string]$Values.world_fields)) }
		$next = @{}
		foreach ($field in $listed) {
			if ($Memory.Fields.ContainsKey($field)) { $entry = $Memory.Fields[$field]; $entry.Checks++; $next[$field] = $entry }
			else { $next[$field] = @{ Checks = 1; SinceUtc = $NowUtc } }
		}
		$Memory.Fields = $next
	}
	$confirmed = @()
	foreach ($field in $LiveResyncStructural) {
		$entry = $Memory.Fields[$field]
		if ($entry -and $entry.Checks -ge $LiveResyncConfirmChecks -and ($NowUtc - $entry.SinceUtc).TotalSeconds -ge $LiveResyncConfirmSeconds) { $confirmed += $field }
	}
	return $confirmed
}

# Warum dieses Spiel jetzt im laufenden Spiel neu abgleichen soll: @{Kind='diff'|'clock'|'error'|'peer'; Detail}
# oder $null. Kind 'peer': der Launcher des Mitspielers hat einen Neuabgleich verlangt (DLL-Status
# resync_peer, neu seit dem letzten Mal). Zählt nichts mit; das macht Register-LiveResync beim Start.
# v37: 'diff' nur bei einer Abweichung im Aufbau, die dieses Spiel selbst sieht und die bleibt
# (Update-LiveResyncDifference). Sieht nur der Mitspieler sie, fragt sein Launcher (dann 'peer').
# 'clock': der gemeinsame Zeitplan dieses Spiels steht seit $LiveResyncClockSeconds.
function Test-AutomaticResyncEnabled($Values, $Config) {
	# Local test peers cannot transfer and load a second world's savegame.
	return $Values.mode -in @('host', 'client') -and -not $Config.test
}

function Get-LiveResyncReason($Values, $Memory, [datetime]$NowUtc) {
	if (-not $Values -or ($Values.mode -ne 'host' -and $Values.mode -ne 'client')) { return $null }
	# Ein neu gestartetes TF3 (andere Prozessnummer) oder ein neu gestarteter Launcher beginnt wieder
	# bei null. Eine Bitte des Mitspielers, die schon dasteht, ist älter und gilt nicht mehr.
	if ($Values.pid -and $Values.pid -ne $Memory.Pid) {
		$fresh = New-LiveResyncMemory
		foreach ($key in @($fresh.Keys)) { $Memory[$key] = $fresh[$key] }
		$Memory.Pid = $Values.pid; $Memory.PeerReq = [string]$Values.resync_peer
	}
	$peerReq = [string]$Values.resync_peer
	$peerNew = $peerReq -and $peerReq -ne $Memory.PeerReq
	# Eine Bitte gilt einmal, auch wenn sie in die Wartezeit fällt (dann gleichen beide schon ab).
	if ($peerReq) { $Memory.PeerReq = $peerReq }
	# Wie lange die Abweichungen schon bestehen; zählt auch während der Wartezeit weiter.
	$structural = @(Update-LiveResyncDifference $Values $Memory $NowUtc)
	$clock = $Values.world -eq 'diff' -and @([string]$Values.world_fields -split '[,\s]+') -contains 'clock'
	if (-not $clock) { $Memory.ClockSinceUtc = [datetime]::MinValue }
	elseif ($Memory.ClockSinceUtc -eq [datetime]::MinValue) { $Memory.ClockSinceUtc = $NowUtc }
	# Eine angenommene Bitte zum Neuladen wartet auf TF3. Ist der letzte Versuch gescheitert, hängt sie
	# nur noch; die DLL nimmt eine neue an.
	if (($Values.resync -eq 'armed' -and $Memory.Failures -le 0) -or $Values.ready -ne '1') { return $null }
	if ($Memory.Count -ge $LiveResyncMax) { return $null }
	if (($NowUtc - $Memory.LastUtc).TotalSeconds -lt (Get-LiveResyncPause $Memory)) { return $null }
	if ($structural.Count) { return @{ Kind = 'diff'; Detail = ($structural -join ',') } }
	if ($clock -and ($NowUtc - $Memory.ClockSinceUtc).TotalSeconds -ge $LiveResyncClockSeconds) { return @{ Kind = 'clock'; Detail = 'clock' } }
	if ([string]$Values.error -match $LiveResyncErrors) { return @{ Kind = 'error'; Detail = [string]$Values.error } }
	if ($peerNew) { return @{ Kind = 'peer'; Detail = $peerReq } }
	return $null
}

# Wartezeit nach dem letzten Neuabgleich: nach Erfolg $LiveResyncCooldownSeconds, nach Fehlschlägen
# $LiveResyncRetrySeconds, mit jedem weiteren Fehlschlag doppelt so lang (höchstens die normale).
function Get-LiveResyncPause($Memory) {
	if ($Memory.Failures -le 0) { return $LiveResyncCooldownSeconds }
	return [Math]::Min($LiveResyncCooldownSeconds, $LiveResyncRetrySeconds * [Math]::Pow(2, [Math]::Min(10, $Memory.Failures - 1)))
}

function Register-LiveResync($Memory, [datetime]$NowUtc) {
	$Memory.Count++; $Memory.LastUtc = $NowUtc
	# Nach dem Neuladen zählen Abweichungen neu.
	$Memory.Ck = $null; $Memory.Fields = @{}; $Memory.ClockSinceUtc = [datetime]::MinValue
}

# v37: Nach einem fehlgeschlagenen Neuabgleich kommt der nächste Versuch früher (Get-LiveResyncPause).
function Complete-LiveResync($Memory, [bool]$Success, [datetime]$NowUtc) {
	if ($Success) { $Memory.Failures = 0 } else { $Memory.Failures++ }
	$Memory.LastUtc = $NowUtc
}

# v37: Die Runde (epoch), in der das Spiel des Mitspielers ist, aus dem Protokoll der DLL
# ("net: peer in resync epoch P, this game in E", nur von diesem TF3-Prozess); -1, wenn unbekannt.
function Get-PeerEpoch([string]$LogPath, [string]$ProcessId, [int]$TailBytes = 262144) {
	if (-not $LogPath -or -not $ProcessId -or -not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return -1 }
	try {
		$stream = [IO.File]::Open($LogPath, 'Open', 'Read', [IO.FileShare]'ReadWrite, Delete')
		try {
			$start = [Math]::Max([int64]0, $stream.Length - $TailBytes)
			[void]$stream.Seek($start, 'Begin')
			$reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII)
			$tail = $reader.ReadToEnd()
		} finally { $stream.Dispose() }
	} catch { return -1 }
	$found = [regex]::Matches($tail, '\[' + [regex]::Escape($ProcessId) + '\] net: peer in resync epoch (\d+), this game in (\d+)')
	if ($found.Count -eq 0) { return -1 }
	return [int]$found[$found.Count - 1].Groups[1].Value
}

# v37: Ein Neuabgleich, der nur auf einem PC geklappt hat, lässt die beiden DLLs in verschiedenen
# Runden; sie verbinden sich dann nie wieder. Ist der Mitspieler genau eine Runde weiter, hat er den
# Stand geladen, den beide zuletzt ausgetauscht haben (der Mitspieler bestätigt erst nach dem
# Speichern, der Gastgeber lädt erst danach). Dieses Spiel lädt ihn dann auch. Gibt den Pfad
# zurück oder $null; einmal pro Rundenpaar.
function Get-EpochCatchUp($Values, $Memory, [int]$PeerEpoch) {
	if (-not $Values -or ($Values.mode -ne 'host' -and $Values.mode -ne 'client')) { return $null }
	# Eine hängende Bitte zum Neuladen (resync=armed) stört nicht: die DLL nimmt eine neue an.
	if ($Values.connected -eq '1' -or $Values.ready -ne '1') { return $null }
	if ($Values.epoch -notmatch '^\d+$' -or $PeerEpoch -ne [int]$Values.epoch + 1) { return $null }
	$pair = "$($Values.epoch)>$PeerEpoch"
	if ($Memory.CatchUp -eq $pair -or -not $Memory.LastSave -or -not (Test-Path -LiteralPath $Memory.LastSave -PathType Leaf)) { return $null }
	$Memory.CatchUp = $pair
	return $Memory.LastSave
}

# v37 (Lauf 39): Der Gastgeber schickt eine eigene Kopie des frischen Spielstands. TF3 schreibt beim
# Speichern <name>.sav.tmp und benennt die Datei dann über <name>.sav; hält jemand <name>.sav in
# diesem Moment offen, scheitert das und TF3 hält das Spiel an. In Lauf 39 war das Original während
# der ganzen Übertragung offen; jetzt nur für die Kopie (etwa eine Sekunde, mit ReadWrite|Delete
# geöffnet), und nicht, solange TF3 gerade speichert (<name>.sav.tmp da). Gesendet wird die Kopie.
# Gibt die neue .sav als FileInfo zurück; die Vorschau (.jpg) kommt mit, wenn es sie gibt.
function Copy-SaveSnapshot($File, [string]$SaveDir, [datetime]$NowLocal = (Get-Date), [int]$BusyWaitSeconds = 30) {
	$until = [DateTime]::UtcNow.AddSeconds($BusyWaitSeconds)
	while ((Test-Path -LiteralPath "$($File.FullName).tmp") -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 200 }
	$base = $LiveResyncSavePrefix + $NowLocal.ToString('yyyyMMdd-HHmmss')
	$name = $base; $n = 1
	while (Test-Path -LiteralPath (Join-Path $SaveDir "$name.sav")) { $n++; $name = "$base-$n" }
	$copies = @()
	try {
		foreach ($ext in @('.sav', '.jpg')) {
			$source = [IO.Path]::ChangeExtension($File.FullName, $ext)
			if ($ext -eq '.jpg' -and -not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
			$target = Join-Path $SaveDir ($name + $ext)
			$part = "$target.part"
			$reader = [IO.File]::Open($source, 'Open', 'Read', [IO.FileShare]'ReadWrite, Delete')
			try {
				$writer = [IO.File]::Open($part, 'CreateNew', 'Write', 'None')
				try { $reader.CopyTo($writer, 1MB) } finally { $writer.Dispose() }
			} finally { $reader.Dispose() }
			Move-Item -LiteralPath $part -Destination $target
			$copies += $target
			# Gleiche Zeit wie das Original, damit 'Neu abgleichen' die Reihenfolge richtig sieht.
			try { [IO.File]::SetLastWriteTimeUtc($target, [IO.File]::GetLastWriteTimeUtc($source)) } catch {}
		}
	} catch {
		foreach ($path in @($copies) + @(Join-Path $SaveDir "$name.sav.part") + @(Join-Path $SaveDir "$name.jpg.part")) {
			Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
		}
		throw "Der Spielstand '$($File.BaseName)' konnte nicht für den Neuabgleich kopiert werden: $($_.Exception.Message)"
	}
	return Get-Item -LiteralPath (Join-Path $SaveDir "$name.sav")
}

# v37: Löscht ältere Neuabgleich-Kopien (TF3MP-Sync-*), die neuesten $Keep bleiben. $Except (voller
# Pfad) bleibt immer, auch wenn er älter ist. Gibt die Zahl der gelöschten Spielstände zurück.
function Remove-OldSyncSaves([string]$SaveDir, [int]$Keep = $LiveResyncKeepSaves, [string]$Except = '') {
	$saves = @(Get-ChildItem -LiteralPath $SaveDir -Filter "$LiveResyncSavePrefix*.sav" -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Extension -ieq '.sav' -and $_.Name.StartsWith($LiveResyncSavePrefix, [StringComparison]::OrdinalIgnoreCase) } |
		Sort-Object LastWriteTimeUtc -Descending)
	$removed = 0
	foreach ($save in @($saves | Select-Object -Skip $Keep)) {
		if ($Except -and $save.FullName -ieq [IO.Path]::GetFullPath($Except)) { continue }
		try {
			Remove-Item -LiteralPath $save.FullName -Force -ErrorAction Stop
			Remove-Item -LiteralPath ([IO.Path]::ChangeExtension($save.FullName, '.jpg')) -Force -ErrorAction SilentlyContinue
			$removed++
		} catch {}
	}
	return $removed
}

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
	# Windows PowerShell 5 wirft bei unerlaubten Zeichen schon hier.
	try { $name = [IO.Path]::GetFileNameWithoutExtension($SavePath) } catch { $name = '' }
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
			if ($armed) { throw 'TF3 hat den gemeinsamen Spielstand nicht geladen.' }
			throw 'Die Multiplayer-DLL hat das Neuladen nicht angenommen (alte DLL oder Fehler in der Sitzung).'
		}
		$text = if ($armed) { 'TF3 lädt den gemeinsamen Spielstand ...' } else { 'Bitte TF3, den gemeinsamen Spielstand zu laden ...' }
		if (& $tick $text 0 0) { throw 'Abgebrochen.' }
		Start-Sleep -Milliseconds 250
	}
}

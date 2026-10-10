# Spielstand vom Gastgeber zum Mitspieler übertragen (TCP, gleicher Port wie das Spiel über UDP).
# Wird vom Launcher eingebunden; beide Spiele müssen denselben Spielstand laden.
#
# Ablauf: Der Gastgeber wählt einen Spielstand und wartet (Send-Savegame), der Mitspieler verbindet
# sich (Receive-Savegame). Übertragen werden <name>.sav und, falls vorhanden, das Vorschaubild
# <name>.jpg. Der Mitspieler prüft jede Datei mit SHA-256 und legt sie erst danach in seinen
# Spielstand-Ordner. Ein vorhandener, anderer Spielstand mit demselben Namen wird nur nach Rückfrage
# ersetzt und bleibt als <datei>.bak liegen.
#
# Protokoll (BinaryWriter, UTF-8): "TF3MPSAVE1", Name, Anzahl Dateien, Gesamtlänge (Int64), je
# Datei: Dateiname, Länge (Int64), SHA-256 (32 Bytes), Inhalt. Antwort des Mitspielers: Byte 1 (gespeichert) oder 0,
# dazu ein Text.
# Version 2 (Launcher-Sitzung): "TF3MPSAVE2", Metadatenlänge (Int32), UTF-8-JSON der Sitzung,
# Kompatibilitätsantwort (Byte/Text), danach derselbe Dateiablauf. Eine Version-2-Anfrage wird
# vor Dateiempfang abgelehnt, wenn Spiel, Paket oder installierte zusätzliche Mods abweichen.
# v37: Antwort mit parallel=4 vereinbart TF3MPDATA3 (Dateibereiche auf vier Datenverbindungen).
# Ohne diese Vereinbarung bleiben der alte Dateistrom und lokale Version-1-Tests unverändert.
# v48: Zusätzlich bulk=1 vereinbart TF3MPDATA4: kontinuierliche Datenströme mit
# nebenläufig gelesenen Empfangsbestätigungen statt Warten nach jedem MiB.

$SaveMagic = 'TF3MPSAVE1'
$SaveSessionMagic = 'TF3MPSAVE2'
$SaveParallelMagic = 'TF3MPDATA3'
$SaveContinuousMagic = 'TF3MPDATA4'
# Additional streams share the already opened TCP port. One control socket + four data sockets.
if (-not ('TF3MP.TransferJob' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'save-transfer-net.cs') }
$script:LastSaveTransfer = $null
$script:SaveTransferTrace = $null

# JSONL remains readable after cancellation or a disconnected VPN. No session tokens,
# IP addresses, save names or file content are recorded. Logging can never abort IO.
function Start-SaveTransferTrace([string]$Role) {
	try {
		$option = Get-Variable SaveTransferLogDirectory -Scope Script -ErrorAction SilentlyContinue
		$dir = if ($option) { $option.Value } else { '' }
		if (-not $dir) { $dir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TF3MP\Logs' }
		[IO.Directory]::CreateDirectory($dir) | Out-Null
		$path = Join-Path $dir ('save-transfer-{0}-{1}-{2}.jsonl' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID, [Guid]::NewGuid().ToString('N').Substring(0,8))
		$script:SaveTransferTrace = @{ Path = $path; Role = $Role; Clock = [Diagnostics.Stopwatch]::StartNew() }
		Write-SaveTransferTrace 'start' @{ socket_buffer_bytes = 8MB }
		if (Get-Command Write-LauncherLog -ErrorAction SilentlyContinue) { Write-LauncherLog "Spielstand-Messprotokoll: $path" }
	} catch { $script:SaveTransferTrace = $null }
}
function Write-SaveTransferTrace([string]$Event, $Fields = @{}) {
	if (-not $script:SaveTransferTrace) { return }
	try {
		$trace = $script:SaveTransferTrace
		$row = [ordered]@{ utc = [DateTime]::UtcNow.ToString('o'); elapsed_s = [Math]::Round($trace.Clock.Elapsed.TotalSeconds,3); role = $trace.Role; event = $Event }
		foreach ($key in $Fields.Keys) { $row[$key] = $Fields[$key] }
		[IO.File]::AppendAllText($trace.Path, (($row | ConvertTo-Json -Depth 5 -Compress) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
	} catch {}
}
function Write-SaveJobTrace($Job, [string]$Event, $Watch) {
	if ($Job.Kind -notin 'send','receive','hash') { return }
	Write-SaveTransferTrace $Event @{
		kind = $Job.Kind; phase = $Job.Phase; method = $Job.Method; streams = $Job.Streams
		bytes = $Job.Bytes; seconds = [Math]::Round($Watch.Elapsed.TotalSeconds,3)
		mib_per_s = [Math]::Round(($Job.Bytes / 1MB / [Math]::Max(0.001, $Watch.Elapsed.TotalSeconds)),3)
		lane_bytes = @($Job.LaneBytes); file_read_ms = [Math]::Round($Job.FileReadMs,1); file_write_ms = [Math]::Round($Job.FileWriteMs,1)
		network_read_ms = [Math]::Round($Job.NetworkReadMs,1); network_write_ms = [Math]::Round($Job.NetworkWriteMs,1); ack_wait_ms = [Math]::Round($Job.AckWaitMs,1)
		verify_s = [Math]::Round($Job.VerifySeconds,3); data_s = [Math]::Round($Job.Seconds,3)
		send_buffer_bytes = $Job.SendBufferBytes; receive_buffer_bytes = $Job.ReceiveBufferBytes
	}
}
$SaveChunk = 1MB
# v36: Socketpuffer. Ein Puffer von 64 KB erlaubt nur 64 KB unterwegs; über ein VPN mit etwa 60 ms Ping sind das
# rund 1 MB/s (Lauf 38). 8 MB reichen auch bei hohem Ping für über 50 MB/s.
$SaveSocketBuffer = 8MB
# Größe eines einzelnen Socket-Schreibvorgangs; dazwischen prüft der Gastgeber auf eine Absage.
$SaveWriteSize = 256KB
# Größter Spielstand, den der Mitspieler annimmt (die größten bisher: rund 80 MB).
$SaveMaxBytes = 1GB

# Sitzung nur im neuen Launcher-Ablauf; direkte lokale Tests dürfen weiterhin Version 1 nutzen.
if (-not (Get-Command Assert-SessionMetadata -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'session.ps1') }

# Das aktive Konto gehört nur zur tatsächlich laufenden Steam-Installation. So beeinflusst die
# Windows-Registry weder portable Kopien noch die isolierten Testordner.
function Get-ActiveSteamAccount($steam) {
	try {
		$settings = Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop
		$registeredRoot = if ($settings.SteamPath) { [string]$settings.SteamPath } else { [string]$settings.InstallPath }
		if (-not $registeredRoot) {
			$machine = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop
			$registeredRoot = [string]$machine.InstallPath
		}
		if (-not $registeredRoot -or [IO.Path]::GetFullPath([string]$steam).TrimEnd('\', '/') -ine [IO.Path]::GetFullPath($registeredRoot).TrimEnd('\', '/')) { return $null }
		$active = Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess' -ErrorAction Stop
		# Registry DWORDs can arrive as signed Int32 for account IDs with the high bit set.
		$account = if ([int64]$active.ActiveUser -lt 0) { [uint64][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$active.ActiveUser), 0) } else { [uint64]$active.ActiveUser }
		if ($account -gt 0 -and $account -le [uint32]::MaxValue) { return $account.ToString([Globalization.CultureInfo]::InvariantCulture) }
	} catch {}
	return $null
}

# Ordner der Spielstände: <Steam>\userdata\<aktives Konto>\3493540\local\save. Ohne aktive
# Kontoinformation darf nur ein eindeutiger TF3-Ordner verwendet werden, nie der jüngste zufällige.
function Get-SaveFolder($steam) {
	$userdata = Join-Path $steam 'userdata'
	if (-not (Test-Path $userdata)) { return $null }
	$activeAccount = Get-ActiveSteamAccount $steam
	if ($activeAccount) {
		$activeDir = Join-Path $userdata "$activeAccount\3493540\local\save"
		if (Test-Path -LiteralPath $activeDir -PathType Container) { return $activeDir }
		return $null
	}
	$folders = @()
	foreach ($account in Get-ChildItem $userdata -Directory) {
		$dir = Join-Path $account.FullName '3493540\local\save'
		if (Test-Path -LiteralPath $dir -PathType Container) { $folders += $dir }
	}
	if ($folders.Count -gt 1) { throw 'Mehrere Steam-Konten mit TF3-Spielständen gefunden. Bitte Steam mit dem gewünschten Konto anmelden und den Launcher erneut öffnen; das aktive Konto konnte nicht bestimmt werden.' }
	if ($folders.Count -eq 1) { return $folders[0] }
	return $null
}

function Get-SaveFiles($savPath) {
	$files = @((Get-Item -LiteralPath $savPath))
	$jpg = [System.IO.Path]::ChangeExtension($savPath, '.jpg')
	if (Test-Path -LiteralPath $jpg) { $files += Get-Item -LiteralPath $jpg }
	return $files
}

function Get-FileSha256($path, $tick = $null) {
	if ($tick) {
		$job = [TF3MP.TransferJob]::Hash([IO.Path]::GetFullPath($path))
		return ,(Wait-SaveJob $job $tick "Prüfe Fingerabdruck von '$(Split-Path -Leaf $path)' ..." (Get-Item -LiteralPath $path).Length)
	}
	$sha = [System.Security.Cryptography.SHA256]::Create()
	$stream = [System.IO.File]::OpenRead($path)
	try { return ,$sha.ComputeHash($stream) } finally { $stream.Dispose(); $sha.Dispose() }
}

function Test-SameBytes($a, $b) {
	if ($a.Length -ne $b.Length) { return $false }
	for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
	return $true
}

# Ein Dateiname, wie ihn der Gastgeber schicken darf: kein Pfad, Endung .sav oder .jpg.
function Test-SaveFileName($name, $base) {
	if ([string]::IsNullOrEmpty($name) -or $name.Length -gt 200) { return $false }
	if ($name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
	if ($name -eq '.' -or $name -eq '..') { return $false }
	$ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
	if ($ext -ne '.sav' -and $ext -ne '.jpg') { return $false }
	return [System.IO.Path]::GetFileNameWithoutExtension($name) -eq $base
}

# Netzwerkfehler (Abbruch, Zeitüberschreitung, getrennte Verbindung) dürfen neu versucht werden.
# PowerShell verpackt sie in "Ausnahme beim Aufrufen von ..."; hier zählt die eigentliche Ursache.
function Get-TransferNetworkError($exception) {
	for ($e = $exception; $e; $e = $e.InnerException) {
		if ($e -is [System.IO.IOException] -or $e -is [System.Net.Sockets.SocketException] -or $e -is [System.IO.EndOfStreamException] -or $e -is [System.ObjectDisposedException]) { return $e }
	}
	return $null
}

function New-TransferBreak($text) { return New-Object System.IO.IOException($text) }

# Der Gastgeber wartet (noch) nicht: Mit -WaitSeconds versucht der Mitspieler es weiter, sonst endgültig.
function New-NoHostError($text) {
	$e = New-Object System.Exception($text)
	$e.Data['TF3MPNoHost'] = $true
	return $e
}
function Test-NoHostError($exception) { return [bool]($exception -and $exception.Data -and $exception.Data['TF3MPNoHost']) }

$SaveRetryHint = 'Häufige Gründe: VPN kurz getrennt, Launcher des Mitspielers geschlossen oder abgebrochen, Firewall/Virenschutz.'

# Fortschritt höchstens zehnmal pro Sekunde zeichnen. Früher wurden bei einem 92-MB-Spielstand
# rund 1400 WinForms-Neuzeichnungen/DoEvents auf jedem PC im eigentlichen Dateitransfer ausgeführt.
# Erster Stand und Ende werden immer gemeldet; die übertragenen Bytes und SHA-Prüfung bleiben gleich.
function New-SaveProgress { return @{ Clock = [Diagnostics.Stopwatch]::StartNew(); LastMs = [int64]-100; LastDone = [int64]-1 } }
function Write-SaveProgress($State, $Tick, [string]$Text, [int64]$Done, [int64]$Total) {
	$now = $State.Clock.ElapsedMilliseconds
	if ($State.LastDone -lt 0 -or $now - $State.LastMs -ge 100 -or ($Done -eq $Total -and $Done -ne $State.LastDone)) {
		$State.LastMs = $now; $State.LastDone = $Done
		return [bool](& $Tick $Text $Done $Total)
	}
	return $false
}

# All potentially blocking headers, writes, hashes and parallel IO run off the UI thread.
# Only this polling callback touches WinForms; closing the worker's sockets cancels blocked IO.
function Wait-SaveJob($Job, $Tick, [string]$Text, [int64]$Total = 0, [int64]$BaseDone = 0, $ControlClient = $null, $ControlReader = $null) {
	$meter = New-SaveProgress
	$jobClock = [Diagnostics.Stopwatch]::StartNew(); $sampleAt = [int64]0
	Write-SaveJobTrace $Job 'job_start' $jobClock
	try {
		while (-not $Job.Work.Wait(100)) {
			if ($jobClock.ElapsedMilliseconds - $sampleAt -ge 1000) { $sampleAt = $jobClock.ElapsedMilliseconds; Write-SaveJobTrace $Job 'sample' $jobClock }
			if (Write-SaveProgress $meter $Tick $Text ($BaseDone + $Job.Bytes) $Total) { throw 'Abgebrochen.' }
			if ($ControlClient -and $ControlClient.GetStream().DataAvailable) {
				$replyByte = New-Object byte[] 1
				[void]$ControlClient.Client.Receive($replyByte, 0, 1, [Net.Sockets.SocketFlags]::Peek)
				# A fast receiver may already have finished hashing. Keep its success for the final receipt.
				if ($replyByte[0] -eq 1) { continue }
				$reason = Read-ReceiverAbort $ControlClient $ControlReader 3000 $Tick
				if ($reason) { throw "Der Mitspieler hat die Übertragung abgebrochen: $reason" }
				throw (New-TransferBreak 'Unerwartete Antwort des Mitspielers während der Übertragung.')
			}
		}
		if ($Job.Error) { throw $Job.Error }
		if (Write-SaveProgress $meter $Tick $Text ($BaseDone + $Job.Bytes) $Total) { throw 'Abgebrochen.' }
		Write-SaveJobTrace $Job 'job_done' $jobClock
		return ,$Job.Result
	} catch {
		$Job.Cancel()
		[void]$Job.Work.Wait(3000)
		Write-SaveJobTrace $Job 'job_failed' $jobClock
		throw
	}
}

function Read-SaveHeader($Reader, [string]$Kind, $Tick, [string]$Text, [int]$Limit = 4096) {
	$job = [TF3MP.TransferJob]::Read($Reader, $Kind, $Limit)
	return ,(Wait-SaveJob $job $Tick $Text)
}

function Write-SaveData($Stream, [byte[]]$Buffer, [int]$Offset, [int]$Count, $Progress, $Tick, [string]$Text, [int64]$Done, [int64]$Total) {
	$job = [TF3MP.TransferJob]::Write($Stream, $Buffer, $Offset, $Count)
	try {
		while (-not $job.Work.Wait(100)) {
			if (Write-SaveProgress $Progress $Tick $Text $Done $Total) { throw 'Abgebrochen.' }
		}
		if ($job.Error) { throw $job.Error }
	} catch { $job.Cancel(); [void]$job.Work.Wait(3000); throw }
}

function Set-SaveTransferStats($Job) {
	$rate = if ($Job.Seconds -gt 0) { $Job.Bytes / 1MB / $Job.Seconds } else { 0 }
	$tracePath = if ($script:SaveTransferTrace) { $script:SaveTransferTrace.Path } else { '' }
	$script:LastSaveTransfer = [pscustomobject]@{ Bytes = $Job.Bytes; Seconds = $Job.Seconds; Streams = $Job.Streams; Method = $Job.Method; VerifySeconds = $Job.VerifySeconds; LogPath = $tracePath; LaneBytes = @($Job.LaneBytes) }
	Write-SaveTransferTrace 'data_summary' @{ bytes = $Job.Bytes; data_s = $Job.Seconds; mib_per_s = [Math]::Round($rate,3); streams = $Job.Streams; method = $Job.Method; slow = ($Job.Bytes -ge 8MB -and $rate -lt 2); verify_s = $Job.VerifySeconds }
}

# Asynchroner Nutzdatenempfang hält den Abbrechen-Knopf auch bei einem stehenden VPN bedienbar.
# Die BinärWriter-Kopfdaten und das bestehende Sitzungsprotokoll ändern sich dadurch nicht.
function Read-SaveData($Stream, [byte[]]$Buffer, [int]$Count, $Progress, $Tick, [string]$Text, [int64]$Done, [int64]$Total, [int]$TimeoutSeconds = 60) {
	$operation = $Stream.BeginRead($Buffer, 0, $Count, $null, $null)
	$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
	$cancelOperation = $false
	try {
		while (-not $operation.AsyncWaitHandle.WaitOne(100)) {
			if (Write-SaveProgress $Progress $Tick $Text $Done $Total) { $cancelOperation = $true; throw 'Abgebrochen.' }
			if ([DateTime]::UtcNow -ge $deadline) { $cancelOperation = $true; throw (New-TransferBreak "Seit $TimeoutSeconds Sekunden keine Datenübertragung. $SaveRetryHint") }
		}
		return $Stream.EndRead($operation)
	} catch { if ($cancelOperation) { $Stream.Close() }; throw }
	finally { $operation.AsyncWaitHandle.Close() }
}

# Gastgeber: Hat der Mitspieler mitten in der Übertragung etwas geschickt, ist es seine Absage (Byte 0 + Grund).
function Read-ReceiverAbort($client, $reader, [int]$waitMs, $tick = { $false }) {
	try {
		$client.ReceiveTimeout = $waitMs
		$ok = Read-SaveHeader $reader 'byte' $tick 'Prüfe Antwort des Mitspielers ...'
		$text = Read-SaveHeader $reader 'text' $tick 'Prüfe Antwort des Mitspielers ...'
		if ($ok -eq 0 -and $text) { return $text }
	} catch {
		if ($_.Exception.Message -eq 'Abgebrochen.') { throw }
		Write-Verbose "Die Antwort des Mitspielers konnte nicht gelesen werden: $($_.Exception.Message)"
	}
	return $null
}

# Gastgeber: ein einzelner Übertragungsversuch über eine angenommene Verbindung.
function Send-SaveToClient($client, $Session, $metadata, $name, $files, $hashes, [int64]$total, $tick, $listener = $null, [int]$Connections = 4, [bool]$Continuous = $true) {
	$client.SendTimeout = 30000
	$client.SendBufferSize = $SaveSocketBuffer
	$client.NoDelay = $true
	# Der Mitspieler kann noch gefragt werden, ob er einen gleichnamigen Spielstand ersetzen will.
	$client.ReceiveTimeout = 600000
	$stream = $client.GetStream()
	$writer = New-Object System.IO.BinaryWriter($stream, [System.Text.Encoding]::UTF8)
	$reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
	try {
		if ($Session) {
			$writer.Write($SaveSessionMagic)
			$writer.Write([int]$metadata.Length); $writer.Write([byte[]]$metadata); $writer.Flush()
			$compatible = Read-SaveHeader $reader 'byte' $tick 'Warte auf die Kompatibilitätsprüfung des Mitspielers ...'
			$compatibilityText = Read-SaveHeader $reader 'text' $tick 'Warte auf die Kompatibilitätsprüfung des Mitspielers ...'
			if ($compatible -ne 1) { throw "Die Sitzung wurde vom Mitspieler abgelehnt: $compatibilityText" }
		} else { $writer.Write($SaveMagic) }
		$parallel = $Session -and $listener -and $Connections -gt 1 -and $compatibilityText -match '(?:^| )parallel=([2-4])(?: |$)'
		$bulk = $parallel -and $Continuous -and $compatibilityText -match '(?:^| )bulk=1(?: |$)'
		if ($parallel) {
			$null = $compatibilityText -match '(?:^| )parallel=([2-4])(?: |$)'
			$streams = [Math]::Min($Connections, [int]$Matches[1])
			$token = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
			$writer.Write($(if ($bulk) { $SaveContinuousMagic } else { $SaveParallelMagic }))
		}
		Write-SaveTransferTrace 'negotiated' @{ method = $(if ($bulk) { 'continuous' } elseif ($parallel) { 'block-ack' } else { 'legacy' }); streams = $(if ($parallel) { $streams } else { 1 }); total_bytes = $total }
		$writer.Write($name)
		$writer.Write([int]$files.Count)
		$writer.Write([int64]$total)
		if ($parallel) { $writer.Write($token); $writer.Write([int]$streams) }
		$done = [int64]0
		$buffer = New-Object byte[] $SaveChunk
		$progress = New-SaveProgress
		$plans = @()
		foreach ($f in $files) {
			$writer.Write($f.Name)
			$writer.Write([int64]$f.Length)
			$writer.Write([byte[]]$hashes[$f.Name])
			if ($parallel) {
				$spec = New-Object TF3MP.TransferFile
				$spec.Name = $f.Name; $spec.Path = $f.FullName; $spec.Length = $f.Length; $spec.Hash = $hashes[$f.Name]
				$plans += $spec
				continue
			}
			$in = [System.IO.File]::OpenRead($f.FullName)
			try {
				while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
					# Socket writes of $SaveWriteSize with an abort check after each: a very large pending
					# write could hide a receiver's refusal before it closes.
					$offset = 0
					while ($offset -lt $n) {
						$sendCount = [Math]::Min($SaveWriteSize, $n - $offset)
						Write-SaveData $stream $buffer $offset $sendCount $progress $tick "Schicke '$name' ..." $done $total
						$offset += $sendCount; $done += $sendCount
						# Vor dem Ende antwortet der Mitspieler nur, wenn er abbricht.
						if ($stream.DataAvailable) {
							$reason = Read-ReceiverAbort $client $reader 5000 $tick
							if ($reason) { throw "Der Mitspieler hat die Übertragung abgebrochen: $reason" }
							throw (New-TransferBreak 'Unerwartete Antwort des Mitspielers während der Übertragung.')
						}
						if (Write-SaveProgress $progress $tick "Schicke '$name' ..." $done $total) { throw 'Abgebrochen.' }
					}
				}
			} finally { $in.Dispose() }
		}
		$writer.Flush()
		if ($parallel) {
			$job = [TF3MP.TransferJob]::Send($listener, $client.Client.RemoteEndPoint.Address, $token, [TF3MP.TransferFile[]]$plans, $streams, [bool]$bulk)
			Wait-SaveJob $job $tick "Schicke '$name' über $streams Datenverbindungen ..." $total 0 $client $reader | Out-Null
			Set-SaveTransferStats $job
			$done = $job.Bytes
		}
	} catch {
		# Schreibfehler: Meist hat der Mitspieler die Verbindung geschlossen. Seine Begründung steht dann noch im Empfangspuffer.
		if (Get-TransferNetworkError $_.Exception) {
			$reason = Read-ReceiverAbort $client $reader 3000 $tick
			if ($reason) { throw "Der Mitspieler hat die Übertragung abgebrochen: $reason" }
			throw (New-TransferBreak "Die Verbindung zum Mitspieler ist während der Übertragung abgebrochen. $SaveRetryHint")
		}
		throw
	}
	if (& $tick "Warte auf die Bestätigung des Mitspielers ..." $done $total) { throw 'Abgebrochen.' }
	Write-SaveTransferTrace 'confirmation_wait'
	try {
		$ok = Read-SaveHeader $reader 'byte' $tick 'Warte auf die Bestätigung des Mitspielers ...'
		$text = Read-SaveHeader $reader 'text' $tick 'Warte auf die Bestätigung des Mitspielers ...'
	} catch {
		if (Get-TransferNetworkError $_.Exception) { throw (New-TransferBreak "Der Mitspieler hat den Empfang nicht bestätigt, die Verbindung ist abgebrochen. $SaveRetryHint") }
		throw
	}
	if ($ok -ne 1) { throw "Der Mitspieler hat den Spielstand nicht gespeichert: $text" }
	Write-SaveTransferTrace 'complete' @{ total_bytes = $total }
	return $text
}

# Gastgeber: wartet bis zu $waitSeconds auf den Mitspieler und schickt ihm den Spielstand.
# $tick wird regelmäßig aufgerufen (Text, erledigte Bytes, Gesamtbytes) und gibt $true zurück,
# wenn abgebrochen werden soll. Mit -Session kommt {Text, Session, SavePath} zurück, sonst Text.
# Reißt die Verbindung ab, wartet der Gastgeber weiter; der Mitspieler versucht es selbst erneut.
function Send-Savegame($savPath, [int]$port, $tick, [int]$waitSeconds = 600, $Session = $null, [int]$MaxAttempts = 5, [int]$Connections = 4, [bool]$Continuous = $true) {
	if ($Connections -lt 1 -or $Connections -gt 4) { throw 'Die Zahl der Datenverbindungen muss zwischen 1 und 4 liegen.' }
	$script:LastSaveTransfer = $null
	Start-SaveTransferTrace 'host'
	Write-SaveTransferTrace 'settings' @{ streams = $Connections; continuous = $Continuous }
	$files = Get-SaveFiles $savPath
	$name = [System.IO.Path]::GetFileNameWithoutExtension($savPath)
	$hashes = @{}
	foreach ($f in $files) { $hashes[$f.Name] = Get-FileSha256 $f.FullName $tick }
	Write-SaveTransferTrace 'hash_ready'
	$metadata = $null
	if ($Session) {
		Assert-SessionMetadata $Session
		$saveHash = ([BitConverter]::ToString($hashes[[IO.Path]::GetFileName($savPath)])).Replace('-', '').ToLowerInvariant()
		if ($Session.SaveName -cne $name -or $Session.SaveHash -ne $saveHash) { throw 'Der angebotene Spielstand passt nicht mehr zur Sitzung. Bitte erneut vorbereiten.' }
		$metadata = [Text.Encoding]::UTF8.GetBytes(($Session | ConvertTo-Json -Depth 6 -Compress))
		if ($metadata.Length -gt 1MB) { throw 'Die Sitzungsbeschreibung ist zu groß.' }
	}
	$total = [int64]0
	foreach ($f in $files) { $total += $f.Length }

	$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
	$listener.Start()
	try {
		$waitText = "Warte auf den Mitspieler (Port $port) ..."
		$lastBreak = ''
		$straySockets = 0
		for ($attempt = 1; ; $attempt++) {
			$deadline = [DateTime]::UtcNow.AddSeconds($waitSeconds)
			while (-not $listener.Pending()) {
				if ([DateTime]::UtcNow -gt $deadline) {
					if ($lastBreak) { throw "$lastBreak`r`nDer Mitspieler hat sich danach nicht erneut gemeldet ($waitSeconds Sekunden)." }
					throw "Der Mitspieler hat sich nicht gemeldet ($waitSeconds Sekunden)."
				}
				if (& $tick $waitText 0 $total) { throw 'Abgebrochen.' }
				Start-Sleep -Milliseconds 100
			}
			$client = $listener.AcceptTcpClient()
			# A cancelled parallel attempt may leave closed/unaccepted lane sockets queued.
			# Primary clients wait for our greeting; only data lanes send first. Ignore these
			# leftovers without spending the retry budget before the peer reconnects.
			if ($client.Client.Poll(100000, [Net.Sockets.SelectMode]::SelectRead)) {
				$client.Close(); $attempt--; $straySockets++
				if ($straySockets -gt 16) { throw 'Zu viele unerwartete Datenverbindungen. Bitte die Übertragung auf beiden PCs neu starten.' }
				continue
			}
			try {
				Write-SaveTransferTrace 'attempt' @{ number = $attempt }
				$text = Send-SaveToClient $client $Session $metadata $name $files $hashes $total $tick $listener $Connections $Continuous
				if ($Session) { return [pscustomobject]@{ Text = $text; Session = $Session; SavePath = [IO.Path]::GetFullPath($savPath) } }
				return $text
			} catch {
				Write-SaveTransferTrace 'attempt_failed' @{ number = $attempt; error_type = $_.Exception.GetType().Name }
				$break = Get-TransferNetworkError $_.Exception
				if (-not $break -or $attempt -ge $MaxAttempts) { if ($break) { throw $break.Message }; throw }
				$lastBreak = $break.Message
				$waitText = "$lastBreak`r`nWarte auf den nächsten Versuch des Mitspielers (Port $port, Versuch $($attempt + 1) von $MaxAttempts) ..."
			} finally { $client.Close() }
		}
	} catch {
		Write-SaveTransferTrace 'failed' @{ error_type = $_.Exception.GetType().Name }
		throw
	} finally {
		$listener.Stop()
	}
}

# Mitspieler: Absage an den Gastgeber schicken und dabei die Verbindung sauber schließen. Ohne das
# Leerlesen setzt Windows die Verbindung hart zurück und der Gastgeber sieht nur einen Schreibfehler.
function Send-ReceiverAbort($client, $writer, $text) {
	try {
		# On Windows TcpClient.GetStream() can reject the half-closed socket after Shutdown(Send).
		# Keep the existing stream first so remaining payload is drained before closing it.
		$stream = $client.GetStream()
		$client.SendTimeout = 3000
		$writer.Write([byte]0); $writer.Write([string]$text); $writer.Flush()
		$client.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send)
		$client.ReceiveTimeout = 500
		$drain = New-Object byte[] 65536
		$until = [DateTime]::UtcNow.AddSeconds(3)
		while ([DateTime]::UtcNow -lt $until) {
			try { if ($stream.Read($drain, 0, $drain.Length) -le 0) { break } } catch { break }
		}
	} catch { Write-Verbose "Die Absage an den Gastgeber konnte nicht gesendet werden: $($_.Exception.Message)" }
}

# Mitspieler: ein Übertragungsversuch. Netzwerkfehler kommen als IOException zurück, alles andere ist endgültig.
function Receive-SaveOnce($hostIp, [int]$port, $saveDir, $tick, $confirm, $LocalManifest, $partsRef, [int]$Connections = 4, [bool]$Continuous = $true) {
	$client = New-Object System.Net.Sockets.TcpClient
	$writer = $null
	$session = $null
	try {
		$async = $client.BeginConnect($hostIp, $port, $null, $null)
		try {
			$deadline = [DateTime]::UtcNow.AddSeconds(15)
			while (-not $async.AsyncWaitHandle.WaitOne(100)) {
				if ([DateTime]::UtcNow -gt $deadline) { throw (New-NoHostError "Keine Verbindung zu $($hostIp):$port. Hat der Gastgeber auf 'Spielstand übertragen' geklickt?") }
				if (& $tick "Verbinde mit $($hostIp):$port ..." 0 0) { throw 'Abgebrochen.' }
			}
			# No connection: final unless Receive-Savegame was asked to wait for the host.
			try { $client.EndConnect($async) } catch { throw (New-NoHostError "Keine Verbindung zu $($hostIp):$port. Hat der Gastgeber auf 'Spielstand übertragen' geklickt? ($((Get-TransferNetworkError $_.Exception).Message))") }
		} finally { $async.AsyncWaitHandle.Close() }
		$client.ReceiveTimeout = 60000
		Write-SaveTransferTrace 'connected'
		$client.SendTimeout = 30000
		$client.ReceiveBufferSize = $SaveSocketBuffer
		$stream = $client.GetStream()
		$reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
		$writer = New-Object System.IO.BinaryWriter($stream, [System.Text.Encoding]::UTF8)
		$headerText = 'Warte auf die Übertragungsdaten des Gastgebers ...'
		$magic = Read-SaveHeader $reader 'text' $tick $headerText 32
		if ($magic -eq $SaveSessionMagic) {
			if (-not $LocalManifest) { throw 'Der Gastgeber verlangt die neue Kompatibilitätsprüfung. Bitte denselben aktuellen Launcher verwenden.' }
			$metadataLength = Read-SaveHeader $reader 'int' $tick $headerText
			if ($metadataLength -lt 2 -or $metadataLength -gt 1MB) { throw 'Ungültige Sitzungsbeschreibung vom Gastgeber.' }
			$metadata = Read-SaveHeader $reader 'bytes' $tick $headerText $metadataLength
			if ($metadata.Length -ne $metadataLength) { throw (New-TransferBreak 'Die Sitzungsbeschreibung wurde unvollständig übertragen.') }
			try { $session = [Text.Encoding]::UTF8.GetString($metadata) | ConvertFrom-Json } catch { throw 'Die Sitzungsbeschreibung ist beschädigt.' }
			Assert-SessionCompatibility $session $LocalManifest
			$capability = if ($Connections -gt 1) { " parallel=$Connections" } else { '' }
			if ($Connections -gt 1 -and $Continuous) { $capability += ' bulk=1' }
			$writer.Write([byte]1); $writer.Write("Kompatibilität geprüft.$capability"); $writer.Flush()
		} elseif ($magic -eq $SaveMagic) {
			if ($LocalManifest) { throw 'Der Gastgeber verwendet einen alten Launcher ohne Sitzungsprüfung. Bitte auf beiden PCs dieselbe aktuelle Version verwenden.' }
		} else { throw 'Die Gegenstelle ist kein Launcher dieses Mods.' }
		$name = Read-SaveHeader $reader 'text' $tick $headerText 800
		$bulk = $name -eq $SaveContinuousMagic
		if ($bulk -and -not $Continuous) { throw 'Nicht vereinbarte kontinuierliche Übertragung.' }
		$parallel = $name -eq $SaveParallelMagic -or $bulk
		if ($parallel) {
			if (-not $session -or $Connections -lt 2) { throw 'Nicht vereinbarte parallele Übertragung.' }
			$name = Read-SaveHeader $reader 'text' $tick $headerText 800
		}
		if ($session -and $session.SaveName -cne $name) { throw 'Der übertragene Spielstandname passt nicht zur vorbereiteten Sitzung.' }
		$count = Read-SaveHeader $reader 'int' $tick $headerText
		if ($count -lt 1 -or $count -gt 2) { throw "Ungültige Anzahl Dateien: $count" }
		$total = Read-SaveHeader $reader 'long' $tick $headerText
		if ($total -lt 0 -or $total -gt (2 * $SaveMaxBytes)) { throw "Ungültige Gesamtgröße: $total" }
		if ($parallel) {
			$token = Read-SaveHeader $reader 'text' $tick $headerText 64
			$streams = Read-SaveHeader $reader 'int' $tick $headerText
			if ($token -cnotmatch '^[0-9a-f]{64}$' -or $streams -lt 2 -or $streams -gt $Connections -or $streams -gt 4) { throw 'Ungültige parallele Übertragungsbeschreibung.' }
		}
		Write-SaveTransferTrace 'negotiated' @{ method = $(if ($bulk) { 'continuous' } elseif ($parallel) { 'block-ack' } else { 'legacy' }); streams = $(if ($parallel) { $streams } else { 1 }); total_bytes = $total }
		$received = @()
		$plans = @()
		$buffer = New-Object byte[] $SaveChunk
		$done = [int64]0
		$progress = New-SaveProgress
		for ($i = 0; $i -lt $count; $i++) {
			$fileName = Read-SaveHeader $reader 'text' $tick $headerText 800
			$length = Read-SaveHeader $reader 'long' $tick $headerText
			$hash = Read-SaveHeader $reader 'bytes' $tick $headerText 32
			if (-not (Test-SaveFileName $fileName $name)) { throw "Ungültiger Dateiname vom Gastgeber: '$fileName'" }
			if ($hash.Length -ne 32) { throw (New-TransferBreak 'Ein Datei-Fingerabdruck wurde unvollständig übertragen.') }
			if (@($received | Where-Object Name -eq $fileName).Count) { throw "Datei doppelt übertragen: '$fileName'" }
			if ($session -and [IO.Path]::GetExtension($fileName) -ieq '.sav' -and ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant() -ne $session.SaveHash) { throw 'Der Datei-Fingerabdruck passt nicht zur vorbereiteten Sitzung.' }
			if ($length -lt 0 -or $length -gt $SaveMaxBytes) { throw "Ungültige Größe: $length" }
			$part = Join-Path $saveDir ($fileName + '.part')
			$partsRef.Value += $part
			if ($parallel) {
				$spec = New-Object TF3MP.TransferFile
				$spec.Name = $fileName; $spec.Path = [IO.Path]::GetFullPath($part); $spec.Length = $length; $spec.Hash = $hash
				$plans += $spec
				$received += @{ Name = $fileName; Part = $part; Hash = $hash }
				$done += $length
				continue
			}
			$sha = [System.Security.Cryptography.SHA256]::Create()
			# Nicht out nennen: Der Fortschritts-Callback des Launchers schreibt in sein Textfeld $out
			# und sähe sonst (dynamischer Gültigkeitsbereich) diesen Dateistrom.
			try { $partFile = [System.IO.File]::Create($part) }
			catch { $sha.Dispose(); throw "Der Spielstand kann nicht in '$saveDir' gespeichert werden: $($_.Exception.Message)" }
			try {
				$left = $length
				while ($left -gt 0) {
					$want = [int][Math]::Min([int64]$buffer.Length, $left)
					$n = Read-SaveData $stream $buffer $want $progress $tick "Empfange '$name' ..." $done $total
					if ($n -le 0) { throw (New-TransferBreak 'Der Gastgeber hat die Verbindung während der Übertragung getrennt.') }
					$partFile.Write($buffer, 0, $n)
					[void]$sha.TransformBlock($buffer, 0, $n, $null, 0)
					$left -= $n
					$done += $n
					if (Write-SaveProgress $progress $tick "Empfange '$name' ..." $done $total) { throw 'Abgebrochen.' }
				}
				[void]$sha.TransformFinalBlock($buffer, 0, 0)
				if (-not (Test-SameBytes $sha.Hash $hash)) { throw (New-TransferBreak "Die Datei '$fileName' kam beschädigt an.") }
			} finally { $partFile.Dispose(); $sha.Dispose() }
			$received += @{ Name = $fileName; Part = $part; Hash = $hash }
		}
		if ($done -ne $total -or @($received | Where-Object { [IO.Path]::GetExtension($_.Name) -ieq '.sav' }).Count -ne 1) { throw 'Die übertragenen Dateien stimmen nicht mit der angekündigten Spielstandgröße überein.' }
		if ($parallel) {
			$job = [TF3MP.TransferJob]::Receive($hostIp, $port, $token, [TF3MP.TransferFile[]]$plans, $streams, [bool]$bulk)
			Wait-SaveJob $job $tick "Empfange '$name' über $streams Datenverbindungen ..." $total | Out-Null
			Set-SaveTransferStats $job
		}
		# Gibt es schon einen anderen Spielstand mit diesem Namen?
		Write-SaveTransferTrace 'replacement_check'
		$replace = @()
		foreach ($r in $received) {
			$target = Join-Path $saveDir $r.Name
			if ((Test-Path -LiteralPath $target) -and -not (Test-SameBytes (Get-FileSha256 $target $tick) $r.Hash)) { $replace += $r.Name }
		}
		if ($replace.Count -gt 0 -and -not (& $confirm "Es gibt schon einen anderen Spielstand '$name'. Ersetzen? (Der alte bleibt als .bak erhalten.)")) {
			throw "Nicht gespeichert: Der Mitspieler wollte seinen Spielstand mit diesem Namen behalten ('$name')."
		}
		foreach ($r in $received) {
			$target = Join-Path $saveDir $r.Name
			if ($replace -contains $r.Name) { Move-Item -LiteralPath $target -Destination ($target + '.bak') -Force }
			Move-Item -LiteralPath $r.Part -Destination $target -Force
		}
		$partsRef.Value = @()
		$text = "Spielstand '$name' gespeichert ($([Math]::Round($done / 1MB, 1)) MB)."
		$writer.Write([byte]1); $writer.Write($text); $writer.Flush()
		Write-SaveTransferTrace 'complete' @{ total_bytes = $total }
		if ($session) { return [pscustomobject]@{ Text = $text; Session = $session; SavePath = (Join-Path $saveDir ($name + '.sav')) } }
		return $text
	} catch {
		Write-SaveTransferTrace 'receive_failed' @{ error_type = $_.Exception.GetType().Name }
		# Endgültige Gründe gehen an den Gastgeber, damit er sie anzeigen kann; Netzwerkfehler versucht der Aufrufer erneut.
		if ($writer -and -not (Get-TransferNetworkError $_.Exception)) { Send-ReceiverAbort $client $writer $_.Exception.Message }
		throw
	} finally {
		$client.Close()
	}
}

# Mitspieler: holt den Spielstand vom Gastgeber und legt ihn in $saveDir ab.
# $confirm (Text) gibt $true zurück, wenn ein anderer Spielstand mit demselben Namen ersetzt werden darf.
# -LocalManifest verlangt Version 2 und liefert {Text, Session, SavePath} erst nach dem Speichern.
# Reißt die Verbindung ab, verbindet er sich bis zu $MaxAttempts-mal neu; der Gastgeber wartet so lange.
# -WaitSeconds (Neuabgleich): Wartet der Gastgeber noch nicht, versucht er es so lange alle 2 Sekunden erneut.
function Receive-Savegame($hostIp, [int]$port, $saveDir, $tick, $confirm, $LocalManifest = $null, [int]$MaxAttempts = 5, [int]$WaitSeconds = 0, [int]$Connections = 4, [bool]$Continuous = $true) {
	if ($Connections -lt 1 -or $Connections -gt 4) { throw 'Die Zahl der Datenverbindungen muss zwischen 1 und 4 liegen.' }
	$script:LastSaveTransfer = $null
	Start-SaveTransferTrace 'client'
	Write-SaveTransferTrace 'settings' @{ streams = $Connections; continuous = $Continuous }
	$parts = @()
	$waitUntil = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
	try {
		for ($attempt = 1; ; $attempt++) {
			try {
				Write-SaveTransferTrace 'attempt' @{ number = $attempt }
				return Receive-SaveOnce $hostIp $port $saveDir $tick $confirm $LocalManifest ([ref]$parts) $Connections $Continuous
			} catch {
				if ((Test-NoHostError $_.Exception) -and [DateTime]::UtcNow -lt $waitUntil) {
					# Kein Versuch verbraucht: Es wurde noch nichts übertragen.
					$attempt--
					$until = [DateTime]::UtcNow.AddSeconds(2)
					while ([DateTime]::UtcNow -lt $until) {
						$left = [int][Math]::Max(0, ($waitUntil - [DateTime]::UtcNow).TotalSeconds)
						if (& $tick "Warte auf den Gastgeber ($($hostIp):$port). Er klickt ebenfalls auf 'Neu abgleichen' (noch $left Sekunden) ..." 0 0) { throw 'Abgebrochen.' }
						Start-Sleep -Milliseconds 100
					}
					continue
				}
				$break = Get-TransferNetworkError $_.Exception
				if (-not $break -or $attempt -ge $MaxAttempts) {
					if ($break) { throw "Die Übertragung ist $attempt-mal abgebrochen: $($break.Message)`r`n$SaveRetryHint" }
					throw
				}
				foreach ($p in $parts) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
				$parts = @()
				$until = [DateTime]::UtcNow.AddSeconds(3)
				while ([DateTime]::UtcNow -lt $until) {
					if (& $tick "Verbindung abgebrochen ($($break.Message)). Neuer Versuch $($attempt + 1) von $MaxAttempts ..." 0 0) { throw 'Abgebrochen.' }
					Start-Sleep -Milliseconds 100
				}
			}
		}
	} catch {
		Write-SaveTransferTrace 'failed' @{ error_type = $_.Exception.GetType().Name }
		throw
	} finally {
		foreach ($p in $parts) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
	}
}

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

$SaveMagic = 'TF3MPSAVE1'
$SaveSessionMagic = 'TF3MPSAVE2'
$SaveChunk = 1MB
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

function Get-FileSha256($path) {
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
function Read-ReceiverAbort($client, $reader, [int]$waitMs) {
	try {
		$client.ReceiveTimeout = $waitMs
		$ok = $reader.ReadByte()
		$text = $reader.ReadString()
		if ($ok -eq 0 -and $text) { return $text }
	} catch { Write-Verbose "Die Antwort des Mitspielers konnte nicht gelesen werden: $($_.Exception.Message)" }
	return $null
}

# Gastgeber: ein einzelner Übertragungsversuch über eine angenommene Verbindung.
function Send-SaveToClient($client, $Session, $metadata, $name, $files, $hashes, [int64]$total, $tick) {
	$client.SendTimeout = 30000
	# Der Mitspieler kann noch gefragt werden, ob er einen gleichnamigen Spielstand ersetzen will.
	$client.ReceiveTimeout = 600000
	$stream = $client.GetStream()
	$writer = New-Object System.IO.BinaryWriter($stream, [System.Text.Encoding]::UTF8)
	$reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
	try {
		if ($Session) {
			$writer.Write($SaveSessionMagic)
			$writer.Write([int]$metadata.Length); $writer.Write([byte[]]$metadata); $writer.Flush()
			$compatible = $reader.ReadByte(); $compatibilityText = $reader.ReadString()
			if ($compatible -ne 1) { throw "Die Sitzung wurde vom Mitspieler abgelehnt: $compatibilityText" }
		} else { $writer.Write($SaveMagic) }
		$writer.Write($name)
		$writer.Write([int]$files.Count)
		$writer.Write([int64]$total)
		$done = [int64]0
		$buffer = New-Object byte[] $SaveChunk
		$progress = New-SaveProgress
		foreach ($f in $files) {
			$writer.Write($f.Name)
			$writer.Write([int64]$f.Length)
			$writer.Write([byte[]]$hashes[$f.Name])
			$in = [System.IO.File]::OpenRead($f.FullName)
			try {
				while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
					# Keep the proven 64-KiB socket writes and abort checks even with larger disk
					# reads. A large pending write can hide a receiver's refusal before it closes.
					$offset = 0
					while ($offset -lt $n) {
						$sendCount = [Math]::Min(65536, $n - $offset)
						$writer.Write($buffer, $offset, $sendCount)
						$offset += $sendCount; $done += $sendCount
						# Vor dem Ende antwortet der Mitspieler nur, wenn er abbricht.
						if ($stream.DataAvailable) {
							$reason = Read-ReceiverAbort $client $reader 5000
							if ($reason) { throw "Der Mitspieler hat die Übertragung abgebrochen: $reason" }
							throw (New-TransferBreak 'Unerwartete Antwort des Mitspielers während der Übertragung.')
						}
						if (Write-SaveProgress $progress $tick "Schicke '$name' ..." $done $total) { throw 'Abgebrochen.' }
					}
				}
			} finally { $in.Dispose() }
		}
		$writer.Flush()
	} catch {
		# Schreibfehler: Meist hat der Mitspieler die Verbindung geschlossen. Seine Begründung steht dann noch im Empfangspuffer.
		if (Get-TransferNetworkError $_.Exception) {
			$reason = Read-ReceiverAbort $client $reader 3000
			if ($reason) { throw "Der Mitspieler hat die Übertragung abgebrochen: $reason" }
			throw (New-TransferBreak "Die Verbindung zum Mitspieler ist während der Übertragung abgebrochen. $SaveRetryHint")
		}
		throw
	}
	& $tick "Warte auf die Bestätigung des Mitspielers ..." $done $total | Out-Null
	try {
		$ok = $reader.ReadByte()
		$text = $reader.ReadString()
	} catch {
		if (Get-TransferNetworkError $_.Exception) { throw (New-TransferBreak "Der Mitspieler hat den Empfang nicht bestätigt, die Verbindung ist abgebrochen. $SaveRetryHint") }
		throw
	}
	if ($ok -ne 1) { throw "Der Mitspieler hat den Spielstand nicht gespeichert: $text" }
	return $text
}

# Gastgeber: wartet bis zu $waitSeconds auf den Mitspieler und schickt ihm den Spielstand.
# $tick wird regelmäßig aufgerufen (Text, erledigte Bytes, Gesamtbytes) und gibt $true zurück,
# wenn abgebrochen werden soll. Mit -Session kommt {Text, Session, SavePath} zurück, sonst Text.
# Reißt die Verbindung ab, wartet der Gastgeber weiter; der Mitspieler versucht es selbst erneut.
function Send-Savegame($savPath, [int]$port, $tick, [int]$waitSeconds = 600, $Session = $null, [int]$MaxAttempts = 5) {
	$files = Get-SaveFiles $savPath
	$name = [System.IO.Path]::GetFileNameWithoutExtension($savPath)
	$hashes = @{}
	foreach ($f in $files) { $hashes[$f.Name] = Get-FileSha256 $f.FullName }
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
			try {
				$text = Send-SaveToClient $client $Session $metadata $name $files $hashes $total $tick
				if ($Session) { return [pscustomobject]@{ Text = $text; Session = $Session; SavePath = [IO.Path]::GetFullPath($savPath) } }
				return $text
			} catch {
				$break = Get-TransferNetworkError $_.Exception
				if (-not $break -or $attempt -ge $MaxAttempts) { if ($break) { throw $break.Message }; throw }
				$lastBreak = $break.Message
				$waitText = "$lastBreak`r`nWarte auf den nächsten Versuch des Mitspielers (Port $port, Versuch $($attempt + 1) von $MaxAttempts) ..."
			} finally { $client.Close() }
		}
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
function Receive-SaveOnce($hostIp, [int]$port, $saveDir, $tick, $confirm, $LocalManifest, $partsRef) {
	$client = New-Object System.Net.Sockets.TcpClient
	$writer = $null
	$session = $null
	try {
		$async = $client.BeginConnect($hostIp, $port, $null, $null)
		$deadline = [DateTime]::UtcNow.AddSeconds(15)
		while (-not $async.AsyncWaitHandle.WaitOne(100)) {
			if ([DateTime]::UtcNow -gt $deadline) { throw (New-NoHostError "Keine Verbindung zu $($hostIp):$port. Hat der Gastgeber auf 'Spielstand übertragen' geklickt?") }
			if (& $tick "Verbinde mit $($hostIp):$port ..." 0 0) { throw 'Abgebrochen.' }
		}
		# Keine Verbindung: Der Gastgeber wartet nicht oder die Adresse stimmt nicht (endgültig ohne -WaitSeconds).
		try { $client.EndConnect($async) } catch { throw (New-NoHostError "Keine Verbindung zu $($hostIp):$port. Hat der Gastgeber auf 'Spielstand übertragen' geklickt? ($((Get-TransferNetworkError $_.Exception).Message))") }
		$client.ReceiveTimeout = 60000
		$client.SendTimeout = 30000
		$client.ReceiveBufferSize = 1MB
		$stream = $client.GetStream()
		$reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
		$writer = New-Object System.IO.BinaryWriter($stream, [System.Text.Encoding]::UTF8)
		$magic = $reader.ReadString()
		if ($magic -eq $SaveSessionMagic) {
			if (-not $LocalManifest) { throw 'Der Gastgeber verlangt die neue Kompatibilitätsprüfung. Bitte denselben aktuellen Launcher verwenden.' }
			$metadataLength = $reader.ReadInt32()
			if ($metadataLength -lt 2 -or $metadataLength -gt 1MB) { throw 'Ungültige Sitzungsbeschreibung vom Gastgeber.' }
			$metadata = $reader.ReadBytes($metadataLength)
			if ($metadata.Length -ne $metadataLength) { throw (New-TransferBreak 'Die Sitzungsbeschreibung wurde unvollständig übertragen.') }
			try { $session = [Text.Encoding]::UTF8.GetString($metadata) | ConvertFrom-Json } catch { throw 'Die Sitzungsbeschreibung ist beschädigt.' }
			Assert-SessionCompatibility $session $LocalManifest
			$writer.Write([byte]1); $writer.Write('Kompatibilität geprüft.'); $writer.Flush()
		} elseif ($magic -eq $SaveMagic) {
			if ($LocalManifest) { throw 'Der Gastgeber verwendet einen alten Launcher ohne Sitzungsprüfung. Bitte auf beiden PCs dieselbe aktuelle Version verwenden.' }
		} else { throw 'Die Gegenstelle ist kein Launcher dieses Mods.' }
		$name = $reader.ReadString()
		if ($session -and $session.SaveName -cne $name) { throw 'Der übertragene Spielstandname passt nicht zur vorbereiteten Sitzung.' }
		$count = $reader.ReadInt32()
		if ($count -lt 1 -or $count -gt 2) { throw "Ungültige Anzahl Dateien: $count" }
		$total = $reader.ReadInt64()
		if ($total -lt 0 -or $total -gt (2 * $SaveMaxBytes)) { throw "Ungültige Gesamtgröße: $total" }
		$received = @()
		$buffer = New-Object byte[] $SaveChunk
		$done = [int64]0
		$progress = New-SaveProgress
		for ($i = 0; $i -lt $count; $i++) {
			$fileName = $reader.ReadString()
			$length = $reader.ReadInt64()
			$hash = $reader.ReadBytes(32)
			if (-not (Test-SaveFileName $fileName $name)) { throw "Ungültiger Dateiname vom Gastgeber: '$fileName'" }
			if ($hash.Length -ne 32) { throw (New-TransferBreak 'Ein Datei-Fingerabdruck wurde unvollständig übertragen.') }
			if (@($received | Where-Object Name -eq $fileName).Count) { throw "Datei doppelt übertragen: '$fileName'" }
			if ($session -and [IO.Path]::GetExtension($fileName) -ieq '.sav' -and ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant() -ne $session.SaveHash) { throw 'Der Datei-Fingerabdruck passt nicht zur vorbereiteten Sitzung.' }
			if ($length -lt 0 -or $length -gt $SaveMaxBytes) { throw "Ungültige Größe: $length" }
			$part = Join-Path $saveDir ($fileName + '.part')
			$partsRef.Value += $part
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
		# Gibt es schon einen anderen Spielstand mit diesem Namen?
		$replace = @()
		foreach ($r in $received) {
			$target = Join-Path $saveDir $r.Name
			if ((Test-Path -LiteralPath $target) -and -not (Test-SameBytes (Get-FileSha256 $target) $r.Hash)) { $replace += $r.Name }
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
		if ($session) { return [pscustomobject]@{ Text = $text; Session = $session; SavePath = (Join-Path $saveDir ($name + '.sav')) } }
		return $text
	} catch {
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
function Receive-Savegame($hostIp, [int]$port, $saveDir, $tick, $confirm, $LocalManifest = $null, [int]$MaxAttempts = 5, [int]$WaitSeconds = 0) {
	$parts = @()
	$waitUntil = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
	try {
		for ($attempt = 1; ; $attempt++) {
			try {
				return Receive-SaveOnce $hostIp $port $saveDir $tick $confirm $LocalManifest ([ref]$parts)
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
	} finally {
		foreach ($p in $parts) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
	}
}

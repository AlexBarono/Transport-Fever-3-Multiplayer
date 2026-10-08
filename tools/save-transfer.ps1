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
$SaveChunk = 65536
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

# Gastgeber: wartet bis zu $waitSeconds auf den Mitspieler und schickt ihm den Spielstand.
# $tick wird regelmäßig aufgerufen (Text, erledigte Bytes, Gesamtbytes) und gibt $true zurück,
# wenn abgebrochen werden soll. Mit -Session kommt {Text, Session, SavePath} zurück, sonst Text.
function Send-Savegame($savPath, [int]$port, $tick, [int]$waitSeconds = 600, $Session = $null) {
	$files = Get-SaveFiles $savPath
	$name = [System.IO.Path]::GetFileNameWithoutExtension($savPath)
	if ($Session) {
		Assert-SessionMetadata $Session
		if ($Session.SaveName -cne $name -or $Session.SaveHash -ne (Get-SessionFileHash $savPath)) { throw 'Der angebotene Spielstand passt nicht mehr zur Sitzung. Bitte erneut vorbereiten.' }
		$metadata = [Text.Encoding]::UTF8.GetBytes(($Session | ConvertTo-Json -Depth 6 -Compress))
		if ($metadata.Length -gt 1MB) { throw 'Die Sitzungsbeschreibung ist zu groß.' }
	}
	$total = [int64]0
	foreach ($f in $files) { $total += $f.Length }
	$hashes = @{}
	foreach ($f in $files) { $hashes[$f.Name] = Get-FileSha256 $f.FullName }

	$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
	$listener.Start()
	$client = $null
	try {
		$deadline = [DateTime]::UtcNow.AddSeconds($waitSeconds)
		while (-not $listener.Pending()) {
			if ([DateTime]::UtcNow -gt $deadline) { throw "Der Mitspieler hat sich nicht gemeldet ($waitSeconds Sekunden)." }
			if (& $tick "Warte auf den Mitspieler (Port $port) ..." 0 $total) { throw 'Abgebrochen.' }
			Start-Sleep -Milliseconds 100
		}
		$client = $listener.AcceptTcpClient()
		$client.SendTimeout = 30000
		# Der Mitspieler kann noch gefragt werden, ob er einen gleichnamigen Spielstand ersetzen will.
		$client.ReceiveTimeout = 600000
		$stream = $client.GetStream()
		$writer = New-Object System.IO.BinaryWriter($stream, [System.Text.Encoding]::UTF8)
		$reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
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
		foreach ($f in $files) {
			$writer.Write($f.Name)
			$writer.Write([int64]$f.Length)
			$writer.Write([byte[]]$hashes[$f.Name])
			$in = [System.IO.File]::OpenRead($f.FullName)
			try {
				while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
					$writer.Write($buffer, 0, $n)
					$done += $n
					if (& $tick "Schicke '$name' ..." $done $total) { throw 'Abgebrochen.' }
				}
			} finally { $in.Dispose() }
		}
		$writer.Flush()
		& $tick "Warte auf die Bestätigung des Mitspielers ..." $done $total | Out-Null
		$ok = $reader.ReadByte()
		$text = $reader.ReadString()
		if ($ok -ne 1) { throw "Der Mitspieler hat den Spielstand nicht gespeichert: $text" }
		if ($Session) { return [pscustomobject]@{ Text = $text; Session = $Session; SavePath = [IO.Path]::GetFullPath($savPath) } }
		return $text
	} finally {
		if ($client) { $client.Close() }
		$listener.Stop()
	}
}

# Mitspieler: holt den Spielstand vom Gastgeber und legt ihn in $saveDir ab.
# $confirm (Text) gibt $true zurück, wenn ein anderer Spielstand mit demselben Namen ersetzt werden darf.
# -LocalManifest verlangt Version 2 und liefert {Text, Session, SavePath} erst nach dem Speichern.
function Receive-Savegame($hostIp, [int]$port, $saveDir, $tick, $confirm, $LocalManifest = $null) {
	$client = New-Object System.Net.Sockets.TcpClient
	$parts = @()
	$stream = $null
	$writer = $null
	$session = $null
	try {
		$async = $client.BeginConnect($hostIp, $port, $null, $null)
		$deadline = [DateTime]::UtcNow.AddSeconds(15)
		while (-not $async.AsyncWaitHandle.WaitOne(100)) {
			if ([DateTime]::UtcNow -gt $deadline) { throw "Keine Verbindung zu $($hostIp):$port. Hat der Gastgeber auf 'Spielstand übertragen' geklickt?" }
			if (& $tick "Verbinde mit $($hostIp):$port ..." 0 0) { throw 'Abgebrochen.' }
		}
		$client.EndConnect($async)
		$client.ReceiveTimeout = 30000
		$client.SendTimeout = 30000
		$stream = $client.GetStream()
		$reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
		$writer = New-Object System.IO.BinaryWriter($stream, [System.Text.Encoding]::UTF8)
		$magic = $reader.ReadString()
		if ($magic -eq $SaveSessionMagic) {
			if (-not $LocalManifest) { throw 'Der Gastgeber verlangt die neue Kompatibilitätsprüfung. Bitte denselben aktuellen Launcher verwenden.' }
			$metadataLength = $reader.ReadInt32()
			if ($metadataLength -lt 2 -or $metadataLength -gt 1MB) { throw 'Ungültige Sitzungsbeschreibung vom Gastgeber.' }
			$metadata = $reader.ReadBytes($metadataLength)
			if ($metadata.Length -ne $metadataLength) { throw 'Die Sitzungsbeschreibung wurde unvollständig übertragen.' }
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
		for ($i = 0; $i -lt $count; $i++) {
			$fileName = $reader.ReadString()
			$length = $reader.ReadInt64()
			$hash = $reader.ReadBytes(32)
			if (-not (Test-SaveFileName $fileName $name)) { throw "Ungültiger Dateiname vom Gastgeber: '$fileName'" }
			if ($hash.Length -ne 32) { throw 'Ein Datei-Fingerabdruck wurde unvollständig übertragen.' }
			if (@($received | Where-Object Name -eq $fileName).Count) { throw "Datei doppelt übertragen: '$fileName'" }
			if ($session -and [IO.Path]::GetExtension($fileName) -ieq '.sav' -and ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant() -ne $session.SaveHash) { throw 'Der Datei-Fingerabdruck passt nicht zur vorbereiteten Sitzung.' }
			if ($length -lt 0 -or $length -gt $SaveMaxBytes) { throw "Ungültige Größe: $length" }
			$part = Join-Path $saveDir ($fileName + '.part')
			$parts += $part
			$sha = [System.Security.Cryptography.SHA256]::Create()
			$out = [System.IO.File]::Create($part)
			try {
				$left = $length
				while ($left -gt 0) {
					$want = [int][Math]::Min([int64]$buffer.Length, $left)
					$n = $stream.Read($buffer, 0, $want)
					if ($n -le 0) { throw 'Die Verbindung ist abgebrochen.' }
					$out.Write($buffer, 0, $n)
					[void]$sha.TransformBlock($buffer, 0, $n, $null, 0)
					$left -= $n
					$done += $n
					if (& $tick "Empfange '$name' ..." $done $total) { throw 'Abgebrochen.' }
				}
				[void]$sha.TransformFinalBlock($buffer, 0, 0)
				if (-not (Test-SameBytes $sha.Hash $hash)) { throw "Die Datei '$fileName' kam beschädigt an. Bitte noch einmal übertragen." }
			} finally { $out.Dispose(); $sha.Dispose() }
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
		$parts = @()
		$text = "Spielstand '$name' gespeichert ($([Math]::Round($done / 1MB, 1)) MB)."
		$writer.Write([byte]1); $writer.Write($text); $writer.Flush()
		if ($session) { return [pscustomobject]@{ Text = $text; Session = $session; SavePath = (Join-Path $saveDir ($name + '.sav')) } }
		return $text
	} catch {
		if ($writer) { try { $writer.Write([byte]0); $writer.Write($_.Exception.Message); $writer.Flush() } catch {} }
		throw
	} finally {
		foreach ($p in $parts) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
		$client.Close()
	}
}

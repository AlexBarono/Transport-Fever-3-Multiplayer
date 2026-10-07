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

$SaveMagic = 'TF3MPSAVE1'
$SaveChunk = 65536
# Größter Spielstand, den der Mitspieler annimmt (die größten bisher: rund 80 MB).
$SaveMaxBytes = 1GB

# Ordner der Spielstände: <Steam>\userdata\<Konto>\3493540\local\save; bei mehreren Konten der mit
# dem zuletzt geänderten Spielstand.
function Get-SaveFolder($steam) {
	$best = $null
	$bestTime = [DateTime]::MinValue
	$userdata = Join-Path $steam 'userdata'
	if (-not (Test-Path $userdata)) { return $null }
	foreach ($account in Get-ChildItem $userdata -Directory) {
		$dir = Join-Path $account.FullName '3493540\local\save'
		if (-not (Test-Path $dir)) { continue }
		$newest = Get-ChildItem $dir -Filter '*.sav' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
		$time = if ($newest) { $newest.LastWriteTime } else { [DateTime]::MinValue.AddSeconds(1) }
		if (-not $best -or $time -gt $bestTime) { $best = $dir; $bestTime = $time }
	}
	return $best
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
# wenn abgebrochen werden soll. Gibt den Text der Antwort des Mitspielers zurück.
function Send-Savegame($savPath, [int]$port, $tick, [int]$waitSeconds = 600) {
	$files = Get-SaveFiles $savPath
	$name = [System.IO.Path]::GetFileNameWithoutExtension($savPath)
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
		$writer.Write($SaveMagic)
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
		$reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
		& $tick "Warte auf die Bestätigung des Mitspielers ..." $done $total | Out-Null
		$ok = $reader.ReadByte()
		$text = $reader.ReadString()
		if ($ok -ne 1) { throw "Der Mitspieler hat den Spielstand nicht gespeichert: $text" }
		return $text
	} finally {
		if ($client) { $client.Close() }
		$listener.Stop()
	}
}

# Mitspieler: holt den Spielstand vom Gastgeber und legt ihn in $saveDir ab.
# $confirm (Text) gibt $true zurück, wenn ein anderer Spielstand mit demselben Namen ersetzt werden darf.
function Receive-Savegame($hostIp, [int]$port, $saveDir, $tick, $confirm) {
	$client = New-Object System.Net.Sockets.TcpClient
	$parts = @()
	$stream = $null
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
		if ($reader.ReadString() -ne $SaveMagic) { throw 'Die Gegenstelle ist kein Launcher dieses Mods.' }
		$name = $reader.ReadString()
		$count = $reader.ReadInt32()
		if ($count -lt 1 -or $count -gt 2) { throw "Ungültige Anzahl Dateien: $count" }
		$total = $reader.ReadInt64()
		$received = @()
		$buffer = New-Object byte[] $SaveChunk
		$done = [int64]0
		for ($i = 0; $i -lt $count; $i++) {
			$fileName = $reader.ReadString()
			$length = $reader.ReadInt64()
			$hash = $reader.ReadBytes(32)
			if (-not (Test-SaveFileName $fileName $name)) { throw "Ungültiger Dateiname vom Gastgeber: '$fileName'" }
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
		# Gibt es schon einen anderen Spielstand mit diesem Namen?
		$replace = @()
		foreach ($r in $received) {
			$target = Join-Path $saveDir $r.Name
			if ((Test-Path -LiteralPath $target) -and -not (Test-SameBytes (Get-FileSha256 $target) $r.Hash)) { $replace += $r.Name }
		}
		if ($replace.Count -gt 0 -and -not (& $confirm "Es gibt schon einen anderen Spielstand '$name'. Ersetzen? (Der alte bleibt als .bak erhalten.)")) {
			$writer.Write([byte]0); $writer.Write('Der Mitspieler wollte seinen Spielstand mit diesem Namen behalten.'); $writer.Flush()
			throw "Nicht gespeichert: es gibt schon einen anderen Spielstand '$name'."
		}
		foreach ($r in $received) {
			$target = Join-Path $saveDir $r.Name
			if ($replace -contains $r.Name) { Move-Item -LiteralPath $target -Destination ($target + '.bak') -Force }
			Move-Item -LiteralPath $r.Part -Destination $target -Force
		}
		$parts = @()
		$text = "Spielstand '$name' gespeichert ($([Math]::Round($done / 1MB, 1)) MB)."
		$writer.Write([byte]1); $writer.Write($text); $writer.Flush()
		return $text
	} finally {
		foreach ($p in $parts) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
		$client.Close()
	}
}

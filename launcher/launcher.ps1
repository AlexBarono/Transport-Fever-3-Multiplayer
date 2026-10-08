param([switch]$LibraryOnly, [switch]$Preview, [string]$PreviewPath = "", [ValidateSet("host","join","test")][string]$PreviewRole = "host", [string]$ReplayLog = "")
# Einfache Oberfläche zum Einrichten des TF3-Multiplayer-Tests.
# Wird über Start.bat im Hauptordner gestartet (Doppelklick).
# Installiert die Proxy-DLL (launcher\bin\alut.dll) und den Mod mods\mp_probe,
# schreibt alut_proxy.ini mit Rolle, Port und Partner-IP und kann alles wieder entfernen.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$AppId = '3493540'
$Root = Split-Path -Parent $PSScriptRoot
$ProxyDll = Join-Path $PSScriptRoot 'bin\alut.dll'
$ModSource = Join-Path $Root 'mods\mp_probe'
$ModName = 'mp_probe'
# Gleiche-Stelle-Test: Aufnahme aus stdout.txt lesen und an die DLL schicken.
. (Join-Path $Root 'tools\same-spot.ps1')
# Spielstand vom Gastgeber zum Mitspieler übertragen.
. (Join-Path $Root 'tools\save-transfer.ps1')
. (Join-Path $Root 'tools\session.ps1')
# Neu abgleichen mit einem Klick.
. (Join-Path $Root 'tools\resync.ps1')

function Get-SteamRoot {
	foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam') {
		try {
			$p = Get-ItemProperty $key -ErrorAction Stop
			$path = if ($p.SteamPath) { $p.SteamPath } else { $p.InstallPath }
			if ($path -and (Test-Path $path)) { return (Resolve-Path $path).Path }
		} catch {}
	}
	return 'C:\Program Files (x86)\Steam'
}

function Find-GameDir($steam) {
	$libraries = @($steam)
	$vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
	if (Test-Path $vdf) {
		foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
			$libraries += $m.Groups[1].Value -replace '\\\\', '\'
		}
	}
	foreach ($lib in $libraries | Select-Object -Unique) {
		$dir = Join-Path $lib 'steamapps\common\Transport Fever 3'
		if (Test-Path (Join-Path $dir 'alut.dll')) { return $dir }
	}
	return ''
}

# Ordner, in denen TF3 lokale Mods sucht: <Steam>\userdata\<Konto>\3493540\local\staging_area
function Get-ModTargets($steam) {
	$targets = @()
	$userdata = Join-Path $steam 'userdata'
	if (Test-Path $userdata) {
		foreach ($account in Get-ChildItem $userdata -Directory) {
			$local = Join-Path $account.FullName "$AppId\local"
			if (Test-Path $local) { $targets += (Join-Path $local "staging_area\$ModName") }
		}
	}
	return $targets
}

function Get-LocalIPs {
	try {
		return (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
			Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'vEthernet|Loopback|WSL' } |
			ForEach-Object { $_.IPAddress }) -join ', '
	} catch { return '(unbekannt)' }
}

function Test-GameRunning { return [bool](Get-Process -Name 'TransportFever3' -ErrorAction SilentlyContinue) }

function Read-Ini($path) {
	$cfg = @{ mode = 'host'; port = '47800'; host = ''; test = '' }
	if (Test-Path $path) {
		foreach ($line in Get-Content $path) {
			if ($line -match '^\s*(mode|port|host|test)\s*=\s*(.*?)\s*$') { $cfg[$matches[1]] = $matches[2] }
		}
	}
	return $cfg
}

function Install-All($gameDir, $mode, $port, $partner, $steam, $test = '', $session = $null) {
	if (Test-GameRunning) { throw 'Transport Fever 3 läuft noch. Bitte zuerst das Spiel beenden.' }
	if ($mode -in 'host','client' -and -not $test -and -not $session) {
		throw 'Bitte zuerst den gemeinsamen Spielstand teilen oder vom Gastgeber holen. Damit wird die Sitzung geprüft.'
	}
	$sessionLines = if ($session) { @(Get-SessionIniLines -Session $session) } else { @() }
	if (-not (Test-Path (Join-Path $gameDir 'alut.dll'))) { throw "Im Spielordner fehlt alut.dll:`n$gameDir" }
	if (-not (Test-Path $ProxyDll)) { throw "Die mitgelieferte DLL fehlt:`n$ProxyDll" }

	$dll = Join-Path $gameDir 'alut.dll'
	$orig = Join-Path $gameDir 'alut_orig.dll'
	if (-not (Test-Path $orig)) {
		# Beim ersten Mal muss alut.dll das signierte Original sein, sonst nicht umbenennen.
		$sig = Get-AuthenticodeSignature $dll
		if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Urban Games') {
			throw "alut.dll im Spielordner ist nicht das Original von Urban Games.`nBitte in Steam 'Dateien auf Fehler überprüfen' ausführen und erneut versuchen."
		}
		Move-Item $dll $orig
	}
	Copy-Item $ProxyDll $dll -Force
	Unblock-File $dll -ErrorAction SilentlyContinue

	$ini = @('[net]', "mode=$mode", "port=$port")
	if ($mode -eq 'client') { $ini += "host=$partner" }
	# Ausdrücklich gewählte lokale Tests benötigen keine gemeinsame Sitzung.
	if ($test) { $ini += "test=$test" }
	if ($session) { $ini += $sessionLines }
	Set-Content -Path (Join-Path $gameDir 'alut_proxy.ini') -Value $ini -Encoding ASCII

	$targets = Get-ModTargets $steam
	if ($targets.Count -eq 0) {
		throw "Kein TF3-Ordner unter $steam\userdata gefunden.`nBitte TF3 einmal starten und wieder beenden, dann erneut installieren."
	}
	foreach ($t in $targets) {
		if (Test-Path $t) { Remove-Item $t -Recurse -Force }
		New-Item -ItemType Directory -Force (Split-Path $t) | Out-Null
		Copy-Item $ModSource $t -Recurse
	}
	return $targets.Count
}

function Uninstall-All($gameDir, $steam) {
	if (Test-GameRunning) { throw 'Transport Fever 3 läuft noch. Bitte zuerst das Spiel beenden.' }
	$dll = Join-Path $gameDir 'alut.dll'
	$orig = Join-Path $gameDir 'alut_orig.dll'
	if (Test-Path $orig) { Move-Item $orig $dll -Force }
	foreach ($f in 'alut_proxy.ini','alut_session.json') {
		$p = Join-Path $gameDir $f
		if (Test-Path $p) { Remove-Item $p -Force }
	}
	foreach ($t in Get-ModTargets $steam) {
		if (Test-Path $t) { Remove-Item $t -Recurse -Force }
	}
}

# Zeigt die Netzwerk-Zeilen des letzten Spielstarts aus alut_proxy.log.
function Get-ConnectionStatus($gameDir) {
	$status = Get-SessionStatus $gameDir
	$log = Join-Path $gameDir 'alut_proxy.log'
	$tail = if (Test-Path $log) { (Get-Content $log -Tail 100 | Where-Object { $_ -match 'net:|backpressure|backlog|game result' } | Select-Object -Last 10) -join "`r`n" } else { 'Noch kein Protokoll vorhanden.' }
	return "$($status.Text)`r`n`r`n$tail"
}

function Test-FakeHostRunning([int]$port) {
	$probe = New-Object System.Net.Sockets.UdpClient(0)
	try {
		$probe.Client.ReceiveTimeout = 200
		$nonce = [Guid]::NewGuid().ToString('N')
		$target = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $port)
		$bytes = [System.Text.Encoding]::ASCII.GetBytes("TF3MP/1 PROBE $nonce")
		[void]$probe.Send($bytes, $bytes.Length, $target)
		$from = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
		$answer = [System.Text.Encoding]::ASCII.GetString($probe.Receive([ref]$from))
		return $from.Address.Equals($target.Address) -and $from.Port -eq $port -and $answer -eq "TF3MP/1 READY $nonce proto=2"
	} catch { return $false } finally { $probe.Close() }
}
function Start-FakeHost([int]$port) {
	if (Test-FakeHostRunning $port) { return }
	$script = Join-Path $Root 'tools\fake-partner.ps1'
	if (-not (Test-Path $script)) { throw "Das Werkzeug fehlt: $script" }
	$log = Join-Path $env:TEMP "tf3mp-fake-$port.log"
	$process = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Port $port -Minutes 120 -LogFile `"$log`""
	for ($attempt = 0; $attempt -lt 15; $attempt++) {
		if (Test-FakeHostRunning $port) { return }
		if ($process.HasExited) { break }
		Start-Sleep -Milliseconds 100
	}
	throw "Der simulierte Gastgeber antwortet nicht auf Port $port. Der Port kann belegt sein. Protokoll: $log"
}
function Parse-JoinAddress([string]$text, [string]$defaultPort) {
	$text = $text.Trim()
	if ($text -match '^(?:tf3mp://)?([0-9.]+)(?::([0-9]+))?/?$') {
		$address = $matches[1]; $port = if ($matches[2]) { $matches[2] } else { $defaultPort }
		$parsed = $null
		if ([System.Net.IPAddress]::TryParse($address, [ref]$parsed) -and
			$parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
			$parsed.ToString() -eq $address -and $address -ne '0.0.0.0' -and
			$port -match '^\d{1,5}$' -and [int]$port -ge 1024 -and [int]$port -le 65535) {
			return @{ Address = $address; Port = [int]$port }
		}
	}
	throw 'Bitte die VPN-IPv4 des Gastgebers eingeben, zum Beispiel 100.80.12.4:47800.'
}
function Get-WorldDifferenceText([string]$fields) {
	$labels = @{ hcon='Bauwerke'; hedge='Straßen/Gleise'; hline='Linien'; hveh='Fahrzeuge'; hpos='Fahrzeugpositionen'; hcargo='Fracht'; htown='Städte'; loan='Kredite'; money='Geld'; date='Datum'; con='Bauwerke'; st='Haltestellen'; lines='Linien'; veh='Fahrzeuge' }
	$parts = @()
	foreach ($field in ($fields -split ',')) { $field = $field.Trim(); if ($field) { $parts += $(if ($labels.ContainsKey($field)) { $labels[$field] } else { $field }) } }
	return ($parts -join ', ')
}
function Get-SessionStatus($gameDir) {
	$path = Join-Path $gameDir 'alut_proxy.status'
	if (-not (Test-GameRunning)) { return @{ Text='Bereit zum Einrichten'; Color='idle' } }
	if (-not (Test-Path $path) -or (Get-Item $path).LastWriteTime -lt (Get-Date).AddSeconds(-8)) { return @{ Text='Spiel gestartet - warte auf Multiplayer'; Color='idle' } }
	$values=@{}
	foreach ($line in Get-Content $path) { if ($line -match '^(\w+)=(.*)$') { $values[$matches[1]]=$matches[2] } }
	if ($values.blocked -eq '1' -or $values.error) { return @{ Text="Abgleich erforderlich: $($values.error)"; Color='error' } }
	if ($values.world -eq 'diff' -or $values.world_peer -eq 'diff') {
		return @{ Text="Weltabweichung erkannt ($(Get-WorldDifferenceText $values.world_fields)). Bitte auf beiden PCs 'Neu abgleichen' klicken."; Color='error' }
	}
	$pending=[int]$values.outbox + [int]$values.inbox
	$disk = if ([int64]$values.backlog -gt 0) { " + weitere auf Datenträger" } else { "" }
	if ($values.connected -eq '1') {
		$world = if ($values.world -eq 'same') { '  |  Weltprüfung stimmt überein' } elseif ($values.world -eq 'checking') { '  |  Weltprüfung läuft' } else { '' }
		return @{ Text="Verbunden  |  $pending Aktion(en) warten$disk$world"; Color='ok' }
	}
	if ($values.mode -eq 'loopback') { return @{ Text="Allein-Test  |  $pending Aktion(en) warten$disk"; Color='ok' } }
	if ($values.protocol -eq '3' -and $values.ready -eq '0') {
		return @{ Text='Sitzung geprüft - den vereinbarten Spielstand pausiert laden'; Color='idle' }
	}
	return @{ Text="Warte auf Partner  |  $pending Aktion(en) vorgemerkt$disk"; Color='idle' }
}

# Die letzten Abgleich-Zeilen des Mods aus stdout.txt (Pause, Geschwindigkeit, Prüfpunkte, Warnungen).
function Get-SyncStatus($steam) {
	try { $lines = Read-SameSpotLines (Find-SameSpotLog $steam) } catch { return '' }
	$sync = @($lines | Where-Object { $_ -match '\[mp_probe\]\s*(sync |gui script|journal test)' } | Select-Object -Last 8)
	if ($sync.Count -eq 0) { return '' }
	$text = ($sync | ForEach-Object { $_ -replace '^.*\[mp_probe\]\s*', '' }) -join "`r`n"
	return "`r`n`r`nAbgleich (letzte Zeilen aus dem Spiel):`r`n$text"
}

function Read-ReplayRecording([string]$path) {
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Die gespeicherte Aufnahme fehlt: $path" }
	try {
		$resolved = (Resolve-Path -LiteralPath $path).Path
		$recording = Get-SameSpotRecording (Read-SameSpotLines $resolved)
	} catch { throw "Die gespeicherte Aufnahme konnte nicht gelesen werden: $path`r`n$($_.Exception.Message)" }
	$recording.Source = $resolved
	return $recording
}

# Bei einer importierten Aufnahme ist deren letztes Laden historisch. Nur das aktuelle
# Spielprotokoll kann bestätigen, welcher Spielstand jetzt tatsächlich geöffnet ist.
function Get-ReplayRecordingForGame($recording, $liveLines, [datetime]$gameStartedAt = [datetime]::MinValue) {
	$current = ''; $loadedAt = [datetime]::MinValue
	foreach ($line in $liveLines) {
		if ($line -match 'Loading game from file (.+?)\s*$') {
			$current = $matches[1]; $loadedAt = [datetime]::MinValue
			if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})Z') {
				$loadedAt = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture,
					[Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
			}
		}
	}
	if (-not $current -or $loadedAt.AddSeconds(1) -lt $gameStartedAt.ToUniversalTime()) {
		throw "Im aktuellen Spiel wurde noch kein Spielstand geladen. Bitte '$($recording.Save)' laden, warten bis die Karte sichtbar ist und dann erneut nachbauen."
	}
	if ($current -ne $recording.Save) {
		throw "Geladen ist '$current', die Aufnahme gehört zu '$($recording.Save)'. Bitte ohne Speichern den ursprünglichen Spielstand '$($recording.Save)' laden."
	}
	return @{ Save=$recording.Save; Current=$current; Lines=@($recording.Lines); Source=$recording.Source }
}

function Get-LauncherManifest($gameDir, $steam, $tick = $null) {
	$saveDir = Get-SaveFolder $steam
	if (-not $saveDir) { throw 'Kein Spielstandordner gefunden. Bitte zuerst im Spiel einen Spielstand speichern.' }
	return Get-SessionManifest -GameDir $gameDir -ModSource $ModSource -ProxyDll $ProxyDll -Steam $steam -SaveDir $saveDir -Tick $tick
}

function Assert-LauncherSavePath([string]$path, [string]$saveDir) {
	if (-not $saveDir -or -not (Test-Path -LiteralPath $saveDir -PathType Container)) { throw 'Der Spielstandordner des aktuellen Steam-Kontos fehlt.' }
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Der vorbereitete Spielstand fehlt: $path" }
	$file = Get-Item -LiteralPath $path
	$folder = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $saveDir).Path).TrimEnd('\','/')
	if ([IO.Path]::GetDirectoryName($file.FullName).TrimEnd('\','/') -ine $folder -or $file.Extension -ine '.sav' -or
		(Test-SessionLink $file)) {
		throw "Bitte einen Spielstand direkt aus dem Spielstandordner des aktuellen Steam-Kontos wählen: $folder. Eine gleichnamige Datei aus einem anderen Ordner reicht nicht."
	}
	return $file.FullName
}

function Get-LaunchSession($gameDir, $steam, [switch]$Installed) {
	if ($script:forceNewSession) { throw 'Bitte den gemeinsamen Spielstand erneut teilen oder vom Gastgeber holen, um den Neuabgleich abzuschließen.' }
	$path = Join-Path $gameDir 'alut_session.json'
	$prepared = Read-PreparedSession -Path $path
	if (-not $prepared) { throw 'Noch keine gemeinsame Sitzung vorbereitet. Bitte zuerst den Spielstand teilen oder vom Gastgeber holen.' }
	Assert-LauncherSavePath $prepared.SavePath (Get-SaveFolder $steam) | Out-Null
	$manifest = Get-LauncherManifest $gameDir $steam
	$session = Assert-PreparedSession -Prepared $prepared -Manifest $manifest
	if ($Installed) {
		$targets = @(Get-ModTargets $steam | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
		if ($targets.Count -eq 0) { throw 'Der Multiplayer-Mod ist noch nicht installiert. Bitte über den großen Startknopf starten.' }
		foreach ($target in $targets) {
			$installedManifest = Get-SessionManifest -GameDir $gameDir -ModSource $target -ProxyDll (Join-Path $gameDir 'alut.dll') -Steam $steam -SaveDir (Get-SaveFolder $steam)
			Assert-SessionCompatibility -Session $session -Manifest $installedManifest | Out-Null
		}
		$expected = @(Get-SessionIniLines -Session $session)
		$current = @(Get-Content -LiteralPath (Join-Path $gameDir 'alut_proxy.ini'))
		foreach ($line in $expected) {
			if ($current -cnotcontains $line) { throw 'Die installierte Sitzung ist veraltet. Bitte über den großen Startknopf erneut installieren.' }
		}
	}
	return $session
}

function Get-RecoveryInstructions([string]$role) {
	if ($role -eq 'host') {
		return "Neu abgleichen (Gastgeber):`r`n" +
			"1. Der Launcher nimmt den Spielstand, den das Spiel bei der Abweichung selbst gespeichert hat ('$ResyncSaveName'), oder bittet dich, jetzt zu speichern.`r`n" +
			"2. TF3 wird beendet und der Stand an deinen Mitspieler geschickt. Er klickt ebenfalls auf 'Neu abgleichen'.`r`n" +
			"3. TF3 startet neu. Beide laden denselben Spielstand pausiert und setzen gemeinsam fort."
	}
	return "Neu abgleichen (Mitspieler):`r`n" +
		"1. TF3 wird beendet. Der Launcher wartet, bis der Gastgeber ebenfalls auf 'Neu abgleichen' klickt, und holt seinen Spielstand.`r`n" +
		"2. TF3 startet neu. Lade den genannten Spielstand pausiert und setzt gemeinsam fort."
}

$script:replayRecording = if ($ReplayLog) { Read-ReplayRecording $ReplayLog } else { $null }
if ($LibraryOnly) { return }
# ---------- Oberfläche ----------
. (Join-Path $PSScriptRoot 'view.ps1')

function Update-Fields {
	$ipBox.Enabled = $clientRadio.Checked
	$portBox.Enabled = -not $loopRadio.Checked
	$replay.Enabled = $spotRadio.Checked
	$recover.Enabled = $hostRadio.Checked -or $clientRadio.Checked
	$hostPage.Visible = $hostRadio.Checked
	$joinPage.Visible = $clientRadio.Checked
	$testPage.Visible = $loopRadio.Checked -or $spotRadio.Checked -or $fakeRadio.Checked
	$primary.Text = if ($hostRadio.Checked) { 'Als Gastgeber starten' } elseif ($clientRadio.Checked) { 'Beitreten und Spiel starten' } else { 'Test starten' }
	$transfer.Text = if ($clientRadio.Checked) { 'Spielstand vom Gastgeber holen' } else { 'Spielstand bereitstellen' }
	$transfer.Enabled = $hostRadio.Checked -or $clientRadio.Checked
	foreach ($pair in @(@($navHost,$hostRadio.Checked),@($navJoin,$clientRadio.Checked),@($navTest,($loopRadio.Checked -or $spotRadio.Checked -or $fakeRadio.Checked)))) {
		$pair[0].BackColor = if ($pair[1]) { $Accent } else { $Sidebar }
		$pair[0].ForeColor = if ($pair[1]) { $Sidebar } else { $TextColor }
	}
}
$hostRadio.Add_CheckedChanged({ Update-Fields })
$clientRadio.Add_CheckedChanged({ Update-Fields })
$loopRadio.Add_CheckedChanged({ Update-Fields })
$spotRadio.Add_CheckedChanged({ Update-Fields })
$fakeRadio.Add_CheckedChanged({ Update-Fields })

# Vorhandene Einstellungen übernehmen
$cfg = Read-Ini (Join-Path $gameBox.Text 'alut_proxy.ini')
if ($cfg.test -eq 'fakehost') { $fakeRadio.Checked = $true }
elseif ($cfg.mode -eq 'client') { $clientRadio.Checked = $true }
elseif ($cfg.mode -eq 'loopback') { $loopRadio.Checked = $true }
elseif ($cfg.test -eq 'samespot') { $spotRadio.Checked = $true }
else { $hostRadio.Checked = $true }
if ($Preview) {
	if ($PreviewRole -eq 'host') { $hostRadio.Checked=$true }
	elseif ($PreviewRole -eq 'join') { $clientRadio.Checked=$true }
	else { $fakeRadio.Checked=$true }
}
$ipBox.Text = $cfg.host
if ($script:replayRecording) {
	$spotRadio.Checked=$true
	$spotRadio.Text='Gleiche Stelle / gespeicherte Aufnahme erneut nachbauen'
	foreach ($label in $testPage.Controls) {
		if ($label.Text -eq 'Der simulierte Gastgeber startet automatisch im Hintergrund.') {
			$label.Text="Gesicherte Aufnahme: $($script:replayRecording.Lines.Count) Aktionen. Lade den ursprünglichen Spielstand '$($script:replayRecording.Save)'."
		}
	}
}
$portBox.Text = $cfg.port
Update-Fields
$out.Text = if ($gameBox.Text) { "Spiel gefunden: $($gameBox.Text)" } else { 'Spielordner nicht gefunden - bitte über "Suchen..." auswählen.' }
if ($script:replayRecording) {
	$out.AppendText("`r`nGespeicherte Aufnahme: $($script:replayRecording.Lines.Count) Aktionen aus '$($script:replayRecording.Save)'.`r`nTest starten, diesen ursprünglichen Spielstand laden und 'Am selben Ort nachbauen' klicken. Ohne neue Bauaufnahme.")
}

function Show-Error($msg) { [System.Windows.Forms.MessageBox]::Show($msg, 'Fehler', 'OK', 'Error') | Out-Null }

$install.Add_Click({
	$script:installOK = $false
	try {
		$mode = if ($clientRadio.Checked -or $fakeRadio.Checked) { 'client' } elseif ($loopRadio.Checked) { 'loopback' } else { 'host' }
		# Gleiche Stelle: die DLL hört als Gastgeber ohne Partner, das Nachbau-Skript spielt den Partner.
		# Simulierter Gastgeber: das Spiel ist Mitspieler, tools\fake-partner.ps1 spielt auf 127.0.0.1 den Gastgeber.
		$test = if ($spotRadio.Checked) { 'samespot' } elseif ($fakeRadio.Checked) { 'fakehost' } else { '' }
		if ($fakeRadio.Checked) { $ipBox.Text = '127.0.0.1' }
		$port = $portBox.Text.Trim()
		if ($port -notmatch '^\d+$' -or [int]$port -lt 1024 -or [int]$port -gt 65535) { throw 'Der Port muss eine Zahl zwischen 1024 und 65535 sein (Standard 47800).' }
		$ip = $ipBox.Text.Trim()
		if ($mode -eq 'client') { $endpoint = Parse-JoinAddress $ip $port; $ip = $endpoint.Address; $port = $endpoint.Port; $ipBox.Text=$ip; $portBox.Text="$port" }
		$parsed = $null
		if ($mode -eq 'client' -and -not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) { throw 'Bitte die IP-Adresse des Gastgebers eingeben, z. B. 192.168.1.10.' }
		$session = $null
		if ($mode -in 'host','client' -and -not $test) { $session = Get-LaunchSession $gameBox.Text.Trim() $steam }
		$n = Install-All $gameBox.Text.Trim() $mode $port $ip $steam $test $session
		if ($test -eq 'fakehost') { Start-FakeHost $port }
		$role = if ($test -eq 'fakehost') { "Mitspieler eines simulierten Gastgebers auf diesem PC (Port $port)" }
			elseif ($test) { "Gleiche Stelle testen (Port $port)" }
			elseif ($mode -eq 'client') { "Mitspieler, verbindet sich mit $($ip):$port" }
			elseif ($mode -eq 'loopback') { 'Allein testen, eigene Bauten kommen 100 m daneben zurück' }
			else { "Gastgeber, wartet auf Port $port" }
		$next = if ($test -eq 'fakehost') {
			"Der simulierte Gastgeber läuft im Hintergrund; sein UDP-Port wurde geprüft.`r`n" +
			"1. 'Spiel starten', einen Spielstand laden, Tempo 1x lassen.`r`n" +
			"2. Etwa 5 Minuten zuschauen: nach gut 1 Minute pausiert das Spiel von selbst, 20 Sekunden später läuft es weiter,`r`n" +
			"   kurz danach eine Weile doppelt so schnell.`r`n" +
			"3. Dann bauen: Gleise, zwei Bahnhöfe, Bahndepot, Signal, Linie, Zug. Danach einen Bahnhof`r`n" +
			"   verlängern und die Linie umbenennen.`r`n" +
			"4. OHNE Speichern ins Hauptmenü und denselben Spielstand neu laden. Nach etwa 20 Sekunden baut der`r`n" +
			"   simulierte Gastgeber alles von selbst am selben Ort nach.`r`n" +
			"5. Ohne Speichern beenden."
		} elseif ($test -eq 'samespot' -and $script:replayRecording) {
			"1. Im Spiel den ursprünglichen Spielstand '$($script:replayRecording.Save)' laden und warten, bis die Karte sichtbar ist.`r`n" +
			"2. Direkt hier 'Am selben Ort nachbauen' klicken: die $($script:replayRecording.Lines.Count) gespeicherten Aktionen werden wiederholt.`r`n" +
			"3. Ergebnis prüfen und ohne Speichern beenden. Du brauchst vorher nichts neu zu bauen."
		} elseif ($test) {
			"1. 'Spiel starten' und einen Spielstand laden.`r`n2. Bauen (z. B. Straße und Depot).`r`n" +
			"3. OHNE Speichern ins Hauptmenü und denselben Spielstand neu laden (Spiel nicht beenden).`r`n" +
			"4. Hier 'Am selben Ort nachbauen' klicken."
		} elseif ($session) {
			"Sitzung geprüft. Beide laden jetzt '$($session.SaveName)' pausiert und setzen gemeinsam fort.`r`n" +
			"Die Verbindung wartet, bis beide den vereinbarten Spielstand geladen haben."
		} else { "Jetzt 'Spiel starten', einen Spielstand laden und danach 'Details prüfen'." }
		$script:installOK = $true
		$out.Text = "Installiert.`r`nRolle: $role`r`nMod kopiert in $n Steam-Konto/Konten.`r`n`r`n$next"
	} catch { Show-Error $_.Exception.Message }
})

$startGame.Add_Click({
	# Simulierter Gastgeber: falls sein Fenster inzwischen zu ist, wieder starten.
	try {
		$cfg = Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
		if ($cfg.test -eq 'fakehost') { Start-FakeHost $cfg.port }
		elseif ($cfg.mode -in 'host','client' -and -not $cfg.test) {
			$session = Get-LaunchSession $gameBox.Text.Trim() $steam -Installed
			$out.Text="Sitzung geprüft. Im Spiel '$($session.SaveName)' pausiert laden."
		}
	} catch { Show-Error $_.Exception.Message; return }
	try { Start-Process "steam://rungameid/$AppId" } catch { Show-Error 'Steam konnte nicht gestartet werden.' }
})

$check.Add_Click({
	try { $out.Text = (Get-ConnectionStatus $gameBox.Text.Trim()) + (Get-SyncStatus $steam) } catch { Show-Error $_.Exception.Message }
})

$script:transferBusy = $false
$script:transferCancel = $false
$script:transferOK = $false
$script:forceNewSession = $false
$script:transferHint = ''

function Enter-TransferBusy($others) {
	$script:transferBusy = $true; $script:transferCancel = $false
	$transfer.Text = 'Abbrechen'
	foreach ($b in $others) { $b.Enabled = $false }
}

# Gastgeber beim Neuabgleich, TF3 läuft: der neueste seit dem Spielstart gespeicherte Stand (meist der,
# den der Mod bei der Abweichung gespeichert hat), oder einer, den der Gastgeber jetzt speichert.
# $null heißt abgebrochen.
function Select-ResyncSave([string]$saveDir, $tick) {
	$since = Get-GameStartTime
	if (-not $since) { $since = [DateTime]::UtcNow }
	$file = Find-ResyncSave $saveDir $since
	if ($file) {
		$file = Wait-SaveWritten $file $tick
		$answer = [System.Windows.Forms.MessageBox]::Show(
			"Spielstand für den Neuabgleich: '$($file.BaseName)', gespeichert um $($file.LastWriteTime.ToString('HH:mm:ss')) Uhr.`r`n`r`n" +
			"Ja: diesen Stand nehmen. TF3 wird dafür beendet, bei Bedarf auch sein Prozess.`r`n" +
			"Nein: Ich speichere jetzt im Spiel einen neueren Stand.`r`n" +
			"Abbrechen: nichts tun.", 'Neu abgleichen', 'YesNoCancel', 'Question')
		if ($answer -eq 'Cancel') { return $null }
		if ($answer -eq 'Yes') { return $file.FullName }
		$since = [DateTime]::UtcNow
	}
	return (Wait-NewSave $saveDir $since $tick).FullName
}

# Spielstand teilen (Gastgeber) oder holen (Mitspieler). -Resync ist der Knopf 'Neu abgleichen': Er
# beendet TF3 selbst, nimmt beim Gastgeber den gerade gespeicherten Stand ohne Dateiauswahl und lässt
# den Mitspieler warten, bis der Gastgeber so weit ist.
function Invoke-Transfer([switch]$Resync) {
	# Ein zweiter Klick während der Übertragung bricht sie ab.
	if ($script:transferBusy) { $script:transferCancel = $true; return }
	$others = @($install, $startGame, $check, $remove, $replay, $recover, $primary, $navHost, $navJoin, $navTest, $gameBox, $browse, $ipBox, $portBox, $roleBox)
	# Bricht der Spieler den Neuabgleich vor dem Beenden von TF3 ab, bleibt die bisherige Sitzung gültig.
	$previousForce = $script:forceNewSession
	try {
		$script:transferOK = $false
		$script:forceNewSession = $true
		$script:transferHint = ''
		if ((Test-GameRunning) -and -not $Resync) { throw 'Bitte TF3 auf beiden PCs vollständig beenden, bevor ihr eine gemeinsame Sitzung vorbereitet.' }
		$port = $portBox.Text.Trim()
		if ($port -notmatch '^\d+$' -or [int]$port -lt 1024 -or [int]$port -gt 65535) { throw 'Der Port muss eine Zahl zwischen 1024 und 65535 sein (Standard 47800).' }
		$saveDir = Get-SaveFolder $steam
		if (-not $saveDir) { throw "Kein Spielstand-Ordner unter $steam\userdata gefunden.`nBitte TF3 einmal starten und einen Spielstand speichern." }
		$tick = {
			param($text, $done, $total)
			$mb = if ($total -gt 0) { " ($([Math]::Round($done / 1MB, 1)) von $([Math]::Round($total / 1MB, 1)) MB)" } else { '' }
			if ($done -gt 0 -and $total -gt 0 -and $text -match '^(Schicke|Empfange) ') {
				if (-not $script:transferMeter -or $done -lt $script:transferMeter.StartBytes) { $script:transferMeter = @{ Clock = [Diagnostics.Stopwatch]::StartNew(); StartBytes = $done } }
				$seconds = $script:transferMeter.Clock.Elapsed.TotalSeconds
				if ($seconds -ge 0.2 -and $done -gt $script:transferMeter.StartBytes) {
					$rate = ($done - $script:transferMeter.StartBytes) / $seconds
					$left = [int][Math]::Ceiling(($total - $done) / $rate)
					$mb += "  |  $([Math]::Round($rate / 1MB, 1)) MB/s  |  etwa $left Sekunden verbleibend"
				}
			} else { $script:transferMeter = $null }
			$out.Text = "$text$mb$($script:transferHint)`r`n`r`nAbbrechen: noch einmal auf den Knopf klicken."
			[System.Windows.Forms.Application]::DoEvents()
			return $script:transferCancel
		}
		if ($Resync) { $out.Text = Get-RecoveryInstructions $(if ($hostRadio.Checked) { 'host' } else { 'client' }) }
		if ($hostRadio.Checked) {
			if ($Resync -and (Test-GameRunning)) {
				Enter-TransferBusy $others
				$offeredSave = Select-ResyncSave $saveDir $tick
				if (-not $offeredSave) { $script:forceNewSession = $previousForce; $out.Text = 'Neuabgleich abgebrochen. Nichts wurde geändert.'; return }
				Stop-GameForResync $tick | Out-Null
				# Hat das Spiel beim Beenden noch einmal gespeichert, erst danach weiter.
				Wait-SaveWritten (Get-Item -LiteralPath $offeredSave) $tick -quietSeconds 0.2 | Out-Null
			} else {
				$dialog = New-Object System.Windows.Forms.OpenFileDialog
				$dialog.InitialDirectory = $saveDir
				$dialog.Filter = 'Spielstände (*.sav)|*.sav'
				$dialog.Title = 'Welchen Spielstand soll der Mitspieler bekommen?'
				if ($Resync) {
					$newest = Find-ResyncSave $saveDir ([datetime]::MinValue)
					if ($newest) { $dialog.FileName = $newest.Name }
				}
				if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
				$offeredSave = $dialog.FileName
				Enter-TransferBusy $others
			}
			$offeredSave = Assert-LauncherSavePath $offeredSave $saveDir
			if ($Resync) { $script:transferHint = "`r`nDein Mitspieler klickt jetzt ebenfalls auf 'Neu abgleichen'." }
			$out.Text='Prüfe Spielversion und Moddateien ...'
			[System.Windows.Forms.Application]::DoEvents()
			$manifest = Get-LauncherManifest $gameBox.Text.Trim() $steam $tick
			$session = New-MultiplayerSession -Manifest $manifest -SavePath $offeredSave
			$result = Send-Savegame $offeredSave ([int]$port) $tick -Session $session
			Save-PreparedSession -Path (Join-Path $gameBox.Text.Trim() 'alut_session.json') -Session $result.Session -SavePath $result.SavePath | Out-Null
			$script:transferOK = $true; $script:forceNewSession = $false
			$out.Text = "Fertig: $($result.Text)`r`n`r`nSpielversion, Moddateien und Spielstand stimmen überein. " +
				"Beide starten jetzt über den großen Startknopf und laden '$($result.Session.SaveName)' pausiert. Das anschließende Laden der Welt übernimmt TF3."
		}
		elseif ($clientRadio.Checked) {
			$endpoint = Parse-JoinAddress $ipBox.Text $port
			$ip = $endpoint.Address; $port=$endpoint.Port
			$parsed = $null
			if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) { throw 'Bitte die IP-Adresse des Gastgebers eingeben, z. B. 192.168.1.10.' }
			if ($Resync -and (Test-GameRunning)) {
				$question = "TF3 wird beendet und der Spielstand des Gastgebers geholt. Dein jetziger Stand wird nicht gespeichert. Reagiert TF3 nicht auf Schließen, wird sein Prozess beendet.`r`n`r`nWeiter?"
				if ([System.Windows.Forms.MessageBox]::Show($question, 'Neu abgleichen', 'YesNo', 'Question') -ne 'Yes') { $script:forceNewSession = $previousForce; return }
				Enter-TransferBusy $others
				Stop-GameForResync $tick | Out-Null
			} else { Enter-TransferBusy $others }
			# Beim Neuabgleich ersetzt der Stand des Gastgebers einen gleichnamigen ohne Rückfrage (der alte bleibt als .bak).
			$confirm = if ($Resync) { { param($question) $true } } else { { param($question) [System.Windows.Forms.MessageBox]::Show($question, 'Spielstand ersetzen?', 'YesNo', 'Question') -eq 'Yes' } }
			$out.Text='Prüfe Spielversion und Moddateien ...'
			[System.Windows.Forms.Application]::DoEvents()
			$manifest = Get-LauncherManifest $gameBox.Text.Trim() $steam $tick
			$wait = if ($Resync) { 600 } else { 0 }
			$result = Receive-Savegame $ip ([int]$port) $saveDir $tick $confirm -LocalManifest $manifest -WaitSeconds $wait
			Save-PreparedSession -Path (Join-Path $gameBox.Text.Trim() 'alut_session.json') -Session $result.Session -SavePath $result.SavePath | Out-Null
			$script:transferOK = $true; $script:forceNewSession = $false
			$out.Text = "Fertig: $($result.Text)`r`n`r`nSpielversion, Moddateien und Spielstand stimmen überein. " +
				"Jetzt über den großen Startknopf starten und '$($result.Session.SaveName)' pausiert laden. Das anschließende Laden der Welt übernimmt TF3."
		}
		else { throw "Bitte oben 'Gastgeber' oder 'Mitspieler' wählen. Der Gastgeber schickt, der Mitspieler holt." }
	} catch { Show-Error $_.Exception.Message }
	finally {
		$script:transferBusy = $false
		$script:transferHint = ''
		Update-Fields
		foreach ($b in $others) { $b.Enabled = $true }
		Update-Fields
	}
}
$transfer.Add_Click({ Invoke-Transfer })

$replay.Add_Click({
	try {
		$cfg = Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
		if ($cfg.test -ne 'samespot' -or $cfg.mode -ne 'host') {
			throw "Bitte zuerst 'Gleiche Stelle testen' wählen, 'Installieren / Speichern' klicken und das Spiel neu starten."
		}
		Assert-SameSpotGameRunning
		$log = Find-SameSpotLog $steam
		$liveLines = Read-SameSpotLines $log
		if ($script:replayRecording) {
			$game = Get-Process -Name 'TransportFever3' -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1
			$rec = Get-ReplayRecordingForGame $script:replayRecording $liveLines $game.StartTime
		} else { $rec = Get-SameSpotRecording $liveLines }
		$question = "Aufgenommen im Spielstand '$($rec.Save)': $($rec.Lines.Count) Bau-Zeile(n).`r`nJetzt geladen: '$($rec.Current)'."
		if ($rec.Save -ne $rec.Current) { $question += "`r`n`r`nAchtung: das ist ein anderer Spielstand als bei der Aufnahme." }
		$question += "`r`n`r`nAn derselben Stelle nachbauen?"
		if ([System.Windows.Forms.MessageBox]::Show($question, 'Am selben Ort nachbauen', 'YesNo', 'Question') -ne 'Yes') { return }
		$out.Text = "Schicke $($rec.Lines.Count) Zeile(n) an das Spiel ..."
		$form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
		$sent = Send-SameSpotRecording $rec ([int]$cfg.port) 2 {
			param($text)
			$out.AppendText("`r`n$text")
			[System.Windows.Forms.Application]::DoEvents()
		}
		$out.AppendText("`r`n`r`nFertig: $sent Zeile(n) übergeben. Im Spiel nachsehen, ob alles an derselben Stelle steht und das Depot angeschlossen ist.")
	} catch { Show-Error $_.Exception.Message }
	finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
})

$remove.Add_Click({
	$answer = [System.Windows.Forms.MessageBox]::Show('Original-Datei wiederherstellen und Mod entfernen?', 'Entfernen', 'YesNo', 'Question')
	if ($answer -ne 'Yes') { return }
	try {
		Uninstall-All $gameBox.Text.Trim() $steam
		$out.Text = 'Entfernt. Das Spiel ist wieder im Originalzustand.'
	} catch { Show-Error $_.Exception.Message }
})

$primary.Add_Click({
	if ($hostRadio.Checked -or $clientRadio.Checked) {
		$prepared = $false
		if (-not $script:forceNewSession) {
			try { Get-LaunchSession $gameBox.Text.Trim() $steam | Out-Null; $prepared = $true } catch {}
		}
		if (-not $prepared) { $transfer.PerformClick(); if (-not $script:transferOK) { return } }
	}
	$install.PerformClick()
	if ($script:installOK) { $startGame.PerformClick() }
})
# Neu abgleichen mit einem Klick: TF3 beenden, Spielstand teilen oder holen, einrichten und neu starten.
$recover.Add_Click({
	if ($script:transferBusy) { return }
	Invoke-Transfer -Resync
	if (-not $script:transferOK) { return }
	$install.PerformClick()
	if (-not $script:installOK) { return }
	$startGame.PerformClick()
	$out.AppendText("`r`n`r`nNeuabgleich: TF3 startet neu. Wenn beide den Spielstand pausiert geladen haben, setzt ihr gemeinsam fort.")
})
$navHost.Add_Click({ Refresh-HostAddresses; $hostRadio.Checked=$true; Update-Fields })
$navJoin.Add_Click({ if ($fakeRadio.Checked -and $ipBox.Text -eq '127.0.0.1') { $ipBox.Text='' }; $clientRadio.Checked=$true; Update-Fields })
$navTest.Add_Click({ $fakeRadio.Checked=$true; Update-Fields })
$copyAddress.Add_Click({
	if ($hostAddress.SelectedItem) {
		try {
			$endpoint = Parse-JoinAddress "$($hostAddress.SelectedItem.Address):$($portBox.Text.Trim())" '47800'
			[System.Windows.Forms.Clipboard]::SetText("$($endpoint.Address):$($endpoint.Port)")
		} catch { Show-Error $_.Exception.Message; return }
		$out.Text='Beitrittsadresse kopiert. Teile sie mit deinem Mitspieler im gemeinsamen VPN.'
	}
})
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval=2000
$timer.Add_Tick({
	try {
		$status = Get-SessionStatus $gameBox.Text.Trim()
		$statusLabel.Text=$status.Text
		$statusLabel.ForeColor = if ($status.Color -eq 'error') { [System.Drawing.ColorTranslator]::FromHtml('#FF8990') } elseif ($status.Color -eq 'ok') { $Accent } else { $Muted }
	} catch { $statusLabel.Text='Verbindungsstatus wird aktualisiert ...' }
})
$form.Add_Shown({ $timer.Start() })
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
if ($Preview) {
	if (-not $PreviewPath) { $PreviewPath = Join-Path $env:TEMP 'tf3mp-launcher-preview.png' }
	$form.Show(); [System.Windows.Forms.Application]::DoEvents()
	$bitmap=New-Object System.Drawing.Bitmap($form.Width,$form.Height)
	$form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
	$bitmap.Save($PreviewPath); $bitmap.Dispose(); $form.Close()
	Write-Output $PreviewPath
} else { [void]$form.ShowDialog() }

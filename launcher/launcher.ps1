param([switch]$LibraryOnly, [switch]$Preview, [string]$PreviewPath = "", [ValidateSet("host","join","test","internet")][string]$PreviewRole = "host", [string]$ReplayLog = "")
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
. (Join-Path $Root 'tools\lobby.ps1')
. (Join-Path $Root 'tools\session.ps1')
# Neu abgleichen mit einem Klick.
. (Join-Path $Root 'tools\resync.ps1')
. (Join-Path $Root 'tools\game-start.ps1')
. (Join-Path $Root 'tools\fake-report.ps1')
. (Join-Path $Root 'tools\action-issues.ps1')
. (Join-Path $Root 'tools\internet.ps1')
. (Join-Path $Root 'tools\internet-view.ps1')
$script:actionIssues = New-ActionIssueReader
$script:actionLogPath = ''
$script:actionLogChecked = [datetime]::MinValue

function Update-LauncherActionIssues($steam, $gameDir) {
	if (([datetime]::UtcNow - $script:actionLogChecked).TotalSeconds -ge 10) {
		$script:actionLogChecked = [datetime]::UtcNow
		try { $script:actionLogPath = Find-SameSpotLog $steam } catch {}
	}
	$values = Read-ProxyStatusValues (Join-Path $gameDir 'alut_proxy.status')
	Update-ActionIssues $script:actionIssues $script:actionLogPath ([string]$values.pid)
}

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
	$cfg = @{ mode = 'host'; port = '47800'; host = ''; test = ''; transport = '' }
	if (Test-Path $path) {
		foreach ($line in Get-Content $path) {
			if ($line -match '^\s*(mode|port|host|test|transport)\s*=\s*(.*?)\s*$') { $cfg[$matches[1]] = $matches[2] }
		}
	}
	return $cfg
}

function Install-All($gameDir, $mode, $port, $partner, $steam, $test = '', $session = $null, $transport = '') {
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
	if ($transport -eq 'internet') { $ini += 'transport=internet' }
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
	Remove-GameAutoload $gameDir
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
	$values=Read-ProxyStatusValues (Join-Path $gameDir 'alut_proxy.status')
	$diagnostic="Rolle=$($values.mode), Quelle geladen=$($values.loaded), Mod bereit=$($values.initialized), Partner bereit=$($values.peer_ready)`r`nUDP-Begrüßungen: gesendet=$($values.hello_sent), empfangen=$($values.hello_received), letzte Antwort vor $($values.peer_hello_age_ms) ms"
	$cfg=Read-Ini (Join-Path $gameDir 'alut_proxy.ini')
	if($cfg.mode -eq 'client' -and -not $cfg.test -and $cfg.transport -ne 'internet' -and (Test-GameRunning)) { $diagnostic+="`r`n"+(Test-GameUdpEndpoint $cfg.host ([int]$cfg.port)) }
	$log = Join-Path $gameDir 'alut_proxy.log'
	$tail = if (Test-Path $log) { (Get-Content $log -Tail 100 | Where-Object { $_ -match 'net:|backpressure|backlog|game result' } | Select-Object -Last 10) -join "`r`n" } else { 'Noch kein Protokoll vorhanden.' }
	return "$($status.Text)`r`n`r`n$diagnostic`r`n`r`n$tail"
}

function Test-GameUdpEndpoint([string]$Address,[int]$Port) {
	$udp=New-Object Net.Sockets.UdpClient(0)
	try {
		$udp.Client.ReceiveTimeout=700; $udp.Connect($Address,$Port)
		$nonce=[Guid]::NewGuid().ToString('N'); $bytes=[Text.Encoding]::ASCII.GetBytes("TF3MP/1 PING $nonce")
		[void]$udp.Send($bytes,$bytes.Length)
		$from=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)
		$reply=[Text.Encoding]::ASCII.GetString($udp.Receive([ref]$from))
		if($reply -match ('^TF3MP/1 HEALTH '+$nonce+' mode=(host|client) loaded=([01]) ready=([01]) proto=([23])$')) {
			return "UDP-Test: Gastgeber-Spiel erreicht, Rolle=$($matches[1]), geladen=$($matches[2]), bereit=$($matches[3])."
		}
		return 'UDP-Test: unerwartete Antwort; Paketversion und Gastgeberadresse prüfen.'
	} catch { return 'UDP-Test: keine Antwort. Auf Gastgeber-PC Rolle, TF3-UDP-Firewall und VPN-Adresse prüfen. Beide benötigen v50 oder neuer für diesen Test.' }
	finally { $udp.Close() }
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
	$labels = @{ clock='gemeinsamer Zeitplan'; hcon='Bauwerke'; hedge='Straßen/Gleise'; hline='Linien'; hveh='Fahrzeuge'; hpos='Fahrzeugpositionen'; hcargo='Fracht'; htown='Städte'; loan='Kredite'; money='Geld'; date='Datum'; con='Bauwerke'; st='Haltestellen'; lines='Linien'; veh='Fahrzeuge' }
	$parts = @()
	foreach ($field in ($fields -split ',')) { $field = $field.Trim(); if ($field) { $parts += $(if ($labels.ContainsKey($field)) { $labels[$field] } else { $field }) } }
	return ($parts -join ', ')
}
function Get-ReplayQueueText($values) {
	# Older bridges report a combined count that also includes world/error reports.
	$parsed=@{}
	foreach($field in @('outbox_actions','inbox_actions','outbox_diagnostics','inbox_diagnostics')) {
		$number=0
		if(-not [int]::TryParse([string]$values[$field],[ref]$number) -or $number -lt 0 -or $number -gt 128) {
			return "$([int]$values.outbox + [int]$values.inbox) Einträge warten"
		}
		$parsed[$field]=$number
	}
	$actions=$parsed.outbox_actions+$parsed.inbox_actions
	$diagnostics=$parsed.outbox_diagnostics+$parsed.inbox_diagnostics
	$text="$actions Spielaktion(en) warten"
	if($diagnostics) { $text+="  |  $diagnostics Diagnosebericht(e) warten" }
	return $text
}
function Get-ReplayWaitText($values) {
	if($values.order_phase -notin @('active','ack','finish','done') -or -not $values.order_token) { return '' }
	$progress=[string]$values.order_progress_age_ms
	if($progress -notmatch '^\d{1,10}$') { $progress=[string]$values.order_age_ms }
	if($progress -notmatch '^\d{1,10}$' -or [int64]$progress -lt 30000) { return '' }
	$local=($values.mode -eq 'host' -and $values.order_side -eq 'C') -or ($values.mode -eq 'client' -and $values.order_side -eq 'H')
	$place=if($local){'auf diesem PC'}else{'beim Mitspieler'}
	$prefix=if($local){''}else{'peer_'}
	$phase=if($values[$prefix+'work_token'] -eq $values.order_token){[string]$values[$prefix+'work_phase']}else{''}
	$detail=switch($phase) {
		'handoff' { 'Übergabe an TF3'; break }
		'waiting' { 'Abschluss der Aktion'; break }
		'callbacks' { 'TF3-Rückmeldung'; break }
		'followup' { 'Fortsetzung der Aktion'; break }
		'weld' { 'Anschlussprüfung'; break }
		default { 'Ausführungsbestätigung' }
	}
	# A missing payload/order acknowledgement is a network wait, not an engine callback.
	switch([string]$values.order_stage) {
		'waiting_order_ack' { $detail='Bestätigung der Aktionsreihenfolge'; $place='beim Mitspieler' }
		'waiting_release_ack' { $detail='Abschlussbestätigung'; $place='beim Mitspieler' }
		'waiting_release' { $detail='Freigabe'; $place='durch den Gastgeber' }
		{ $_ -in @('sending_payload','sending_fragments','waiting_peer_receipt') } { $detail='Empfangsbestätigung'; $place='beim Mitspieler' }
		{ $_ -in @('receiving_payload','waiting_payload') } { $detail='Aktionsdaten'; $place='vom Mitspieler' }
		'delivering_to_game' { $detail='Übergabe an TF3'; $place='auf diesem PC' }
	}
	return "Warte seit $([Math]::Floor([int64]$progress/1000)) s auf $detail $place (Kennung $($values.order_token))"
}
function Get-SessionStatus($gameDir) {
	$path = Join-Path $gameDir 'alut_proxy.status'
	if (-not (Test-GameRunning)) { return @{ Text='Bereit zum Einrichten'; Color='idle' } }
	if (-not (Test-Path $path) -or (Get-Item $path).LastWriteTime -lt (Get-Date).AddSeconds(-8)) { return @{ Text='Spiel gestartet - warte auf Multiplayer'; Color='idle' } }
	$values = Read-ProxyStatusValues $path
	if ($values.resync -eq 'armed') {
		# Außerhalb eines Neuabgleichs heißt das: TF3 hat ihn nicht geladen (der Launcher fragt neu).
		if ($script:liveMemory -and $script:liveMemory.Failures -gt 0) { return @{ Text="TF3 hat den gemeinsamen Spielstand nicht geladen. Bei Bedarf 'Neu abgleichen' anklicken."; Color='error' } }
		return @{ Text='Neuabgleich: TF3 lädt den gemeinsamen Spielstand ...'; Color='idle' }
	}
	if ($values.blocked -eq '1' -or $values.error) { return @{ Text="Abgleich erforderlich: $($values.error)"; Color='error' } }
	$clockStopped = $values.world -eq 'diff' -and @([string]$values.world_fields -split '[,\s]+') -contains 'clock'
	if ($clockStopped) { return @{ Text="Aktionszeitplan blockiert. Bei Bedarf 'Neu abgleichen' anklicken."; Color='error' } }
	if ($values.connected -ne '1' -and $values.epoch -match '^\d+$' -and $script:peerEpoch -gt [int]$values.epoch + 1) {
		return @{ Text="Der Mitspieler ist mehrere Neuabgleiche weiter. Bitte den Gastgeber bitten, 'Neu abgleichen' zu starten."; Color='error' }
	}
	$drift = ''
	if ($values.world -eq 'diff' -and $values.world_fields) { $drift = "  |  Abweichung ($(Get-WorldDifferenceText $values.world_fields)), Spiel läuft weiter. Neuabgleich bei Bedarf." }
	elseif ($values.world_peer -eq 'diff') { $drift = '  |  der Mitspieler sieht eine Abweichung' }
	if ($values.epoch -match '^[1-9]' -and $values.connected -ne '1' -and $values.mode -in 'host','client') {
		return @{ Text='Neu geladen - warte, bis der Mitspieler auch neu geladen hat ...'; Color='idle' }
	}
	$pending=Get-ReplayQueueText $values
	$disk = if ([int64]$values.backlog -gt 0) { " + weitere auf Datenträger" } else { "" }
	if ($values.connected -eq '1') {
		$world = if ($drift) { $drift } elseif ($values.world -eq 'same') { '  |  Weltprüfung stimmt überein' } elseif ($values.world -eq 'checking') { '  |  Weltprüfung läuft' } else { '' }
		$waiting=Get-ReplayWaitText $values
		if($waiting) { return @{ Text="$waiting  |  $pending$disk"; Color='warning' } }
		return @{ Text="Verbunden  |  $pending$disk$world"; Color='ok' }
	}
	if ($values.mode -eq 'loopback') { return @{ Text="Allein-Test  |  $pending$disk"; Color='ok' } }
	if ($values.protocol -eq '3' -and $values.ready -eq '0') {
		if($values.loaded -eq '1') { return @{ Text='Spielstand geladen, aber Mod noch nicht bereit. Details stehen im Protokoll; TF3MP-Mod muss aktiv sein.'; Color='idle' } }
		return @{ Text='Sitzung geprüft - den vereinbarten Spielstand pausiert laden'; Color='idle' }
	}
	if($values.protocol -eq '3' -and $values.compatible -eq '1' -and $values.peer_ready -eq '0') { return @{ Text='Partner erreicht; sein Spielstand / Mod ist noch nicht bereit.'; Color='idle' } }
	if($values.protocol -eq '3' -and $values.hello_received -eq '0') { return @{ Text='Spiel bereit, keine UDP-Antwort vom Partner. Gastgeberrolle, Adresse und TF3-Firewall auf beiden PCs prüfen.'; Color='error' } }
	return @{ Text="Warte auf Partner  |  $pending$disk"; Color='idle' }
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
    if($role -eq 'host'){
        return "Neu abgleichen (Gastgeber): TF3 speichert einen frischen Stand automatisch. Der Launcher schickt eine geprüfte Kopie und beide offenen Spiele laden sie automatisch. Nur der Gastgeber startet den Vorgang."
    }
    return "Neu abgleichen (Mitspieler): Der Launcher wartet, bis der Gastgeber den Neuabgleich startet, holt den neuen Spielstand und lädt ihn im offenen Spiel automatisch. Kein eigener Knopf nötig."
}

$script:replayRecording = if ($ReplayLog) { Read-ReplayRecording $ReplayLog } else { $null }
if ($LibraryOnly) { return }

# v34: kein schwarzes Konsolenfenster neben dem Launcher (Start.bat startet PowerShell schon versteckt;
# das hier versteckt es auch bei einem Start von Hand). Fehler beim Start zeigt ein Fenster statt der Konsole.
if (-not $Preview) {
	try {
		Add-Type -Namespace TF3MP -Name ConsoleWindow -MemberDefinition '[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);'
		$console = [TF3MP.ConsoleWindow]::GetConsoleWindow()
		if ($console -ne [IntPtr]::Zero) { [void][TF3MP.ConsoleWindow]::ShowWindow($console, 0) }
	} catch {}
}
trap {
	if ($Preview) { break }
	[System.Windows.Forms.MessageBox]::Show("Der Launcher ist auf einen Fehler gestoßen:`r`n`r`n$($_.Exception.Message)", 'TF3 Multiplayer', 'OK', 'Error') | Out-Null
	exit 1
}
# ---------- Oberfläche ----------
. (Join-Path $PSScriptRoot 'view.ps1')
. (Join-Path $PSScriptRoot 'lobby-ui.ps1')

function Update-Fields {
    $testMode=$loopRadio.Checked -or $spotRadio.Checked -or $fakeRadio.Checked
    $locked=$script:transferBusy -or $script:liveBusy -or $script:lobbyPreparing -or $script:lobbyPhase -in 'starting','started'
    $ipBox.Enabled=$clientRadio.Checked -and -not $locked
    $portBox.Enabled=-not $loopRadio.Checked -and -not $script:internetTunnel -and -not $locked
    $gameBox.Enabled=-not $locked; $browse.Enabled=-not $locked
    $hostPage.Visible=$hostRadio.Checked; $joinPage.Visible=$clientRadio.Checked; $testPage.Visible=$testMode
    $hostConnected=$script:transferBusy -or ($script:presence -and $script:presence.Connected) -or ($script:lobby -and $script:lobby.Connected)
    $primary.Visible=$testMode -or ($hostRadio.Checked -and $hostConnected)
    $saveChoice.Visible=$hostRadio.Checked -and $hostConnected
    $saveChoice.Enabled=-not $locked
    $primary.Text=if($hostRadio.Checked){'Spielstand bereitstellen'}else{'Test starten'}
    $primary.Enabled=-not $locked -and ($testMode -or ($script:presence -and $script:presence.Connected -and $saveChoice.SelectedItem))
    # Use the already scaled row width when switching roles after WinForms DPI scaling.
    $primary.Width=if($hostRadio.Checked){[int][Math]::Round($joinStatus.Width*336/694)}else{$joinStatus.Width}
    $flowTitle.Text=if($testMode){'LOKAL TESTEN  /  ERGEBNIS PRÜFEN'}else{'02  SPIELSTAND  /  GEMEINSAMER START'}
    $remove.Enabled=-not $locked -and -not (Test-GameRunning)
    $startBoth.Visible=$hostRadio.Checked -and $hostConnected
    $startBoth.Enabled=Test-LobbyCanStart
    $startBoth.Text=if($startBoth.Enabled){'Spiel für beide starten'}elseif($script:lobbyPhase -eq 'started'){'Beide Spiele gestartet'}elseif($script:lobbyPhase -eq 'starting'){'Warte auf Startbestätigung ...'}else{'Spiel starten'}
    $startBoth.BackColor=if($startBoth.Enabled){$Accent}else{$Card}
    $startBoth.ForeColor=if($startBoth.Enabled){$Background}else{$Muted}
    $joinStatus.Visible=$clientRadio.Checked -or ($hostRadio.Checked -and -not $hostConnected)
    $joinStatus.Text=switch($script:lobbyPhase){
        'ready' {'Warte auf das Starten des Gastgebers'}
        'started' {if($script:lobbyLoadSeen){'Gemeinsamer Spielstand geladen'}elseif($script:lobbyError){'Laden prüfen – siehe Protokoll'}else{'TF3 lädt den gemeinsamen Spielstand.'}}
        'error' {'Verbindung oder Spielstand prüfen'}
        default {if($hostRadio.Checked){'Warte auf Verbindung zum Mitspieler'}elseif($script:lobbyJob -and $script:lobbyJob.Progress.Snapshot()[0] -like 'Verbunden.*'){'Warte auf Spielstand vom Gastgeber'}else{'Warte auf Verbindung zum Gastgeber'}}
    }
    if(-not $script:transferBusy -and -not $script:liveBusy -and -not $script:lobbyJob){
        $workflowHint.Text=if($testMode){'Test wählen und starten. Die Auswertung findest du anschließend unter Details prüfen.'}elseif($script:lobbyError){'Verbindung oder Vorbereitung fehlgeschlagen. Die Ursache steht im Protokoll.'}elseif($script:lobbyPhase -eq 'started'){'Der gemeinsame Spielstand wird automatisch geladen. Der Launcher bleibt offen.'}elseif($clientRadio.Checked -and $script:lobbyPhase -eq 'ready'){'Alles vorbereitet. Dein Gastgeber startet beide Spiele.'}elseif($clientRadio.Checked){'Adresse oder Einladung einfügen. Alles Weitere läuft automatisch.'}elseif($script:lobbyPhase -eq 'ready' -and -not $script:lobbyPeerReady){'Übertragen. Warte, bis der Mitspieler seine Einrichtung bestätigt.'}elseif($script:lobbyPeerReady){'Beide PCs sind bereit. Gemeinsam starten.'}elseif($hostConnected){'Spielstand oben wählen. Ein laufendes TF3 wird für die neue Sitzung beendet.'}else{'Erst verbinden. Danach den Spielstand teilen und gemeinsam starten.'}
    }
    $transfer.Visible=$script:transferBusy -or $script:liveBusy
    $transfer.Text='Abbrechen'; $transfer.Enabled=$true
    $check.Visible=$testMode; $check.Enabled=-not $locked
    $install.Visible=$testMode; $install.Enabled=-not $locked
    $replay.Visible=$testMode; $replay.Enabled=$spotRadio.Checked -and -not $locked
    $recover.Visible=$hostRadio.Checked
    $recover.Enabled=$hostRadio.Checked -and -not $script:transferBusy -and -not $script:liveBusy -and -not $script:lobbyPreparing -and (Test-GameRunning)
    $internetMode=$connectionMode.SelectedIndex -eq 0
    $internetSetup.Visible=$internetMode; $ipv4Setup.Visible=$internetMode
    $internetSetup.Enabled=$hostRadio.Checked -and -not $locked
    $ipv4Setup.Enabled=$internetSetup.Enabled
    $connectionMode.Enabled=-not $locked
    if($script:internetTunnel -and $script:internetRole -eq 'host'){$internetPortBox.Text="$($script:internetTunnel.Port)"}
    $internetPortBox.Visible=$internetMode; $internetPortBox.Enabled=-not $locked -and -not $script:internetTunnel
    $connectionPortLabel.Visible=$internetMode
    $portBox.Visible=$testMode; $testPortLabel.Visible=$testMode
    $clearAddress.Enabled=$clientRadio.Checked -and -not $locked
    if(-not $testMode){$gameBox.Width=[int][Math]::Round($settings.Width*510/734)}
    $connectionStatus.Text=if($hostConnected){'Mitspieler verbunden. Spielstand bereitstellen.'}elseif($script:internetRole -eq 'host'){'Internetzugang offen. Einladung teilen; warte auf Mitspieler.'}elseif(-not $internetMode){"VPN / LAN: TCP + UDP $($portBox.Text). Adresse teilen; warte auf Mitspieler."}else{'IPv6 wählen oder öffentliche IPv4 eingeben. Verbindung öffnen.'}
    if($clientRadio.Checked){$joinConnection.Text=if($script:lobbyPhase -in 'ready','started','starting'){'Verbunden. Spielstand vorbereitet.'}elseif($script:lobbyJob -and $script:lobbyJob.Progress.Snapshot()[0] -like 'Verbunden.*'){'Verbunden. Warte auf den Spielstand.'}else{'Adresse einfügen. Die Verbindung startet automatisch.'}}
    $internetCheck.Enabled=-not $locked -and -not $script:lobbyJob
    $hostAddress.Enabled=-not $locked
    $refreshAddress.Enabled=$hostAddress.Enabled
    $copyAddress.Enabled=-not $locked -and (-not $internetMode -or [bool]$script:internetInvite)
    $copyAddress.Text=if($internetMode){'Einladung kopieren'}else{'Adresse kopieren'}
    foreach($pair in @(@($navHost,$hostRadio.Checked),@($navJoin,$clientRadio.Checked),@($navTest,$testMode))){
        $pair[0].Enabled=-not $locked
        $pair[0].BackColor=if($pair[1]){$Accent}else{$Sidebar}
        $pair[0].ForeColor=if($pair[1]){$Sidebar}else{$TextColor}
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
	if ($PreviewRole -in 'host','internet') { $hostRadio.Checked=$true }
	elseif ($PreviewRole -eq 'join') { $clientRadio.Checked=$true }
	else { $fakeRadio.Checked=$true }
}
$ipBox.Text = $cfg.host
if($cfg.transport -eq 'internet') {
	$script:internetNeedsSetup=$true
	if($cfg.mode -eq 'client') { $ipBox.Text='' }
}
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
if($cfg.transport -ne 'internet'){$connectionMode.SelectedIndex=1}
Refresh-HostAddresses
Update-Fields
$out.Text = if ($gameBox.Text) { "Spiel gefunden: $($gameBox.Text)" } else { 'Spielordner nicht gefunden - bitte über "Suchen..." auswählen.' }
if($script:internetNeedsSetup) { $out.AppendText("`r`nLetzte Sitzung: Internet ohne VPN. Gastgeber: Internetzugang neu einrichten und die neue Einladung teilen. Mitspieler: neue Einladung einfügen.") }
if ($script:replayRecording) {
	$out.AppendText("`r`nGespeicherte Aufnahme: $($script:replayRecording.Lines.Count) Aktionen aus '$($script:replayRecording.Save)'.`r`nTest starten, diesen ursprünglichen Spielstand laden und 'Am selben Ort nachbauen' klicken. Ohne neue Bauaufnahme.")
}

# v36: Protokoll des Launchers neben alut_proxy.log im Spielordner (Lauf 38: ohne Protokoll war nicht zu
# sehen, ob der Launcher den Neuabgleich überhaupt versucht hat).
function Write-LauncherLog([string]$text) {
	if ($out -and -not $out.IsDisposed) {
		if ($out.TextLength -gt 80000) { $out.Text=$out.Text.Substring($out.TextLength-60000) }
		$out.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] $text`r`n"); $out.SelectionStart=$out.TextLength; $out.ScrollToCaret()
	}
	try {
		$dir = $gameBox.Text.Trim()
		if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return }
		$path = Join-Path $dir 'alut_launcher.log'
		if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 2MB) { Move-Item -LiteralPath $path "$path.old" -Force }
		Add-Content -LiteralPath $path -Value ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, ($text -replace "`r?`n", ' | ')) -Encoding UTF8
	} catch {}
}
function Show-Error($msg) {
	Write-LauncherLog "Fehler: $msg"
	[System.Windows.Forms.MessageBox]::Show($msg, 'Fehler', 'OK', 'Error') | Out-Null
}
# Größe und Dauer einer Übertragung fürs Protokoll.
function Get-TransferRateText([string]$path, $clock) {
	try {
		$bytes = (Get-Item -LiteralPath $path).Length; $seconds = [Math]::Max(0.001, $clock.Elapsed.TotalSeconds)
		$rate = '{0:N1} MB in {1:N1} s ({2:N1} MB/s)' -f ($bytes / 1MB), $seconds, ($bytes / 1MB / $seconds)
		# v37: die Übertragung misst die reinen Daten selbst (tools\save-transfer.ps1), ohne Warten.
		$stats = $script:LastSaveTransfer
		if ($stats -and [double]$stats.Seconds -gt 0 -and [int64]$stats.Bytes -gt 0) {
			$rate += '; Daten {0:N1} MB in {1:N1} s = {2:N1} MB/s über {3} Verbindung(en)' -f ([int64]$stats.Bytes / 1MB), [double]$stats.Seconds, ([int64]$stats.Bytes / 1MB / [double]$stats.Seconds), $stats.Streams
			$rate += '; Verfahren {0}; SHA-Prüfung {1:N2} s; Messprotokoll: {2}' -f $stats.Method, $stats.VerifySeconds, $stats.LogPath
		}
		return $rate
	} catch { return '' }
}

function Install-LauncherSettings {
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
		if ($mode -eq 'client') { $endpoint = Resolve-LauncherEndpoint $ip $port; $ip = $endpoint.Address; $port = $endpoint.Port; if(-not $endpoint.Internet) { $ipBox.Text=$ip }; $portBox.Text="$port" }
		Assert-LauncherInternetMode $mode ([int]$port) $test
		$parsed = $null
		if ($mode -eq 'client' -and -not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) { throw 'Bitte die IP-Adresse des Gastgebers eingeben, z. B. 192.168.1.10.' }
		$session = $null
		if ($mode -in 'host','client' -and -not $test) { $session = Get-LaunchSession $gameBox.Text.Trim() $steam }
		$transport = if($script:internetTunnel -and -not $test) { 'internet' } else { '' }
		$n = Install-All $gameBox.Text.Trim() $mode $port $ip $steam $test $session $transport
		if ($test -eq 'fakehost') { Start-FakeHost $port }
		$role = if ($test -eq 'fakehost') { "Mitspieler eines simulierten Gastgebers auf diesem PC (Port $port)" }
			elseif ($test) { "Gleiche Stelle testen (Port $port)" }
			elseif ($mode -eq 'client') { "Mitspieler, verbindet sich mit $($ip):$port" }
			elseif ($mode -eq 'loopback') { 'Allein testen, eigene Bauten kommen 100 m daneben zurück' }
			else { "Gastgeber, wartet auf Port $port" }
		$next = if ($test -eq 'fakehost') {
			"Der simulierte Gastgeber läuft im Hintergrund; sein UDP-Port wurde geprüft.`r`n" +
			"1. 'Test starten', einen Spielstand laden, Tempo 1x lassen.`r`n" +
			"2. Etwa 5 Minuten zuschauen: nach gut 1 Minute pausiert das Spiel von selbst, 20 Sekunden später läuft es weiter,`r`n" +
			"   kurz danach eine Weile doppelt so schnell.`r`n" +
			"3. Dann bauen: Gleise, zwei Bahnhöfe, Bahndepot, Signal, Linie, Zug. Danach einen Bahnhof`r`n" +
			"   verlängern und die Linie umbenennen.`r`n" +
			"4. OHNE Speichern ins Hauptmenü und denselben Spielstand neu laden. Nach etwa 20 Sekunden baut der`r`n" +
			"   simulierte Gastgeber alles von selbst am selben Ort nach.`r`n" +
			"5. 'Details pruefen' zeigt bestaetigte und offene Testteile. Danach ohne Speichern beenden."
		} elseif ($test -eq 'samespot' -and $script:replayRecording) {
			"1. Im Spiel den ursprünglichen Spielstand '$($script:replayRecording.Save)' laden und warten, bis die Karte sichtbar ist.`r`n" +
			"2. Direkt hier 'Am selben Ort nachbauen' klicken: die $($script:replayRecording.Lines.Count) gespeicherten Aktionen werden wiederholt.`r`n" +
			"3. Ergebnis prüfen und ohne Speichern beenden. Du brauchst vorher nichts neu zu bauen."
		} elseif ($test) {
			"1. 'Test starten' und einen Spielstand laden.`r`n2. Bauen (z. B. Straße und Depot).`r`n" +
			"3. OHNE Speichern ins Hauptmenü und denselben Spielstand neu laden (Spiel nicht beenden).`r`n" +
			"4. Hier 'Am selben Ort nachbauen' klicken."
		} elseif ($session) {
			"Sitzung geprüft. Beide laden jetzt '$($session.SaveName)' pausiert und setzen gemeinsam fort.`r`n" +
			"Die Verbindung wartet, bis beide den vereinbarten Spielstand geladen haben."
		} else { "Jetzt 'Test starten', einen Spielstand laden und danach 'Details prüfen'." }
		$script:installOK = $true
		Write-LauncherLog "Multiplayer eingerichtet: $role. Mod in $n Steam-Konto/Konten."
		if ($test -or $mode -eq 'loopback') { Write-LauncherLog $next }
	} catch { throw }
}
$install.Add_Click({ try { Install-LauncherSettings } catch { Show-Error $_.Exception.Message } })

function Start-LauncherGame {
	# Simulierter Gastgeber: falls sein Fenster inzwischen zu ist, wieder starten.
	try {
		$cfg = Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
		if ($cfg.transport -eq 'internet') {
			if ($cfg.mode -eq 'client') { [void](Resolve-LauncherEndpoint $ipBox.Text $cfg.port) }
			if (-not $script:internetTunnel) { throw 'Internetzugang zuerst neu einrichten und die neue Einladung mit dem Mitspieler teilen.' }
			Assert-LauncherInternetMode $cfg.mode ([int]$cfg.port) $cfg.test
		}
		if ($cfg.test -eq 'fakehost') { Start-FakeHost $cfg.port }
		elseif ($cfg.mode -in 'host','client' -and -not $cfg.test) {
			$session = Get-LaunchSession $gameBox.Text.Trim() $steam -Installed
			Stop-LauncherGameForStart
			Request-GameAutoload $gameBox.Text.Trim() $session.SaveName
			Initialize-GameFirewall
			Write-LauncherLog "Sitzung geprüft. TF3 lädt '$($session.SaveName)' automatisch."
		}
	} catch { throw }
	try { Start-Process "steam://rungameid/$AppId" } catch {
        $request=Join-Path $gameBox.Text.Trim() 'alut_proxy.launch'
        if(Test-Path -LiteralPath $request){Remove-Item -LiteralPath $request -Force}
        throw 'Steam konnte nicht gestartet werden.'
    }
}
function Initialize-GameFirewall {
    $cfg=Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
    if($cfg.mode -in 'host','client' -and -not $cfg.test){
        $result=Enable-InternetFirewall ([int]$cfg.port) (Join-Path $gameBox.Text.Trim() 'TransportFever3.exe') $cfg.mode
        Write-LauncherLog "Spiel-Firewall geprüft: UDP / $($cfg.mode) / Port $($cfg.port), $result"
    }
}

$check.Add_Click({
	try {
		if ($fakeRadio.Checked) {
			$hostLog = Join-Path $env:TEMP "tf3mp-fake-$($portBox.Text.Trim()).log"
			$hostLines = Read-SameSpotLines $hostLog
			$gameLines = @()
			try { $gameLines = Read-SameSpotLines (Find-SameSpotLog $steam) } catch {}
			$report = Get-FakeHostReport $hostLines $gameLines
			$reportPath = "$hostLog.report.txt"
			Set-Content -LiteralPath $reportPath -Value $report.Text -Encoding UTF8
			$out.Text = $report.Text + "`r`n`r`nGespeichert: $reportPath"
		} else {
			Update-LauncherActionIssues $steam $gameBox.Text.Trim()
			$out.Text = (Get-LauncherInternetSummary) + (Get-ActionIssueDetails $script:actionIssues) + (Get-ConnectionStatus $gameBox.Text.Trim()) + (Get-SyncStatus $steam)
		}
	} catch { Show-Error $_.Exception.Message }
})

$script:transferBusy = $false
$script:transferCancel = $false
$script:transferOK = $false
$script:forceNewSession = $false
$script:transferHint = ''

function Enter-TransferBusy($others) {
	$script:transferBusy = $true; $script:transferCancel = $false
	$transfer.Text = 'Abbrechen'; $transfer.Visible=$true
	foreach ($b in $others) { $b.Enabled = $false }
}

# The host prepares the save; the joining launcher receives in its background worker.
function Invoke-Transfer {
    if($script:transferBusy){$script:transferCancel=$true; return}
    if(-not $hostRadio.Checked){return}
    $others=@($install,$startBoth,$check,$remove,$replay,$recover,$primary,$navHost,$navJoin,$navTest,$gameBox,$browse,$ipBox,$portBox,$roleBox,$internetSetup,$internetCheck)
    $connection=$null
    try {
        if(-not $script:presence -or -not $script:presence.Connected){throw 'Zuerst mit dem Mitspieler verbinden.'}
        $port=$portBox.Text.Trim()
        if($port -notmatch '^\d+$' -or [int]$port -lt 1024 -or [int]$port -gt 65535){throw 'Der Port muss zwischen 1024 und 65535 liegen.'}
        Assert-LauncherInternetMode 'host' ([int]$port) ''
        $saveDir=Get-SaveFolder $steam
        if(-not $saveDir){throw 'Kein Spielstandordner gefunden. Bitte zuerst einen Spielstand in TF3 speichern.'}
        if(-not $saveChoice.SelectedItem){throw 'Bitte einen Spielstand in der Liste auswählen.'}
        $savePath=Assert-LauncherSavePath $saveChoice.SelectedItem.Path $saveDir
        $script:presence.BeginTransfer(); $script:presence.Dispose(); $script:presence=$null
        Close-LauncherLobby
        Enter-TransferBusy $others; Update-Fields
        $script:forceNewSession=$true; $script:transferOK=$false
        Write-LauncherLog "Bereite '$(Split-Path -Leaf $savePath)' vor und warte auf den Mitspieler."
        $tick={param($text,$done,$total) Set-LauncherProgress $text $done $total; Update-InternetDiagnostics; [Windows.Forms.Application]::DoEvents(); return $script:transferCancel}
        if($script:internetTunnel){Write-LauncherLog (Get-LauncherInternetSummary)}
        if(-not $script:internetTunnel){[void](Enable-InternetFirewall ([int]$port))}
        Stop-LauncherGameForStart $tick
        $manifest=Get-LauncherManifest $gameBox.Text.Trim() $steam $tick
        $session=New-MultiplayerSession -Manifest $manifest -SavePath $savePath
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $result=Send-Savegame $savePath ([int]$port) $tick -Session $session -KeepConnection ([ref]$connection)
        Save-PreparedSession (Join-Path $gameBox.Text.Trim() 'alut_session.json') $result.Session $result.SavePath | Out-Null
        $script:forceNewSession=$false
        Install-LauncherSettings; Install-GameAutoload $gameBox.Text.Trim(); Initialize-GameFirewall
        Set-LobbyConnection $connection $result.Session $true; $connection=$null
        $script:lobbyKey="$($clientRadio.Checked)|$($hostRadio.Checked)|$($ipBox.Text.Trim())|$($portBox.Text.Trim())|$($gameBox.Text.Trim())"
        $script:transferOK=$true
        Write-LauncherLog "Spielstand übertragen: $(Get-TransferRateText $savePath $clock). Warte auf die Bereitschaft des Mitspielers."
    } catch {
        $script:lobbyPhase='error'; $script:lobbyError=$_.Exception.Message
        if($_.Exception.Message -eq 'Abgebrochen.'){Write-LauncherLog 'Spielstandübertragung abgebrochen.'}else{Show-Error $_.Exception.Message}
    } finally {
        if($connection){$connection.Close()}
        $script:transferBusy=$false
        foreach($control in $others){$control.Enabled=$true}
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
		Close-LauncherLobby
		Uninstall-All $gameBox.Text.Trim() $steam
		$script:lobbyPhase='error'; $script:lobbyError='Mod entfernt. Für eine neue Sitzung Rolle auswählen und den Stand erneut bereitstellen.'
		Write-LauncherLog 'Entfernt. Das Spiel ist wieder im Originalzustand.'
		Update-Fields
	} catch { Show-Error $_.Exception.Message }
})

$primary.Add_Click({
    if($hostRadio.Checked){Invoke-Transfer; return}
    if($clientRadio.Checked){return}
    try {Install-LauncherSettings; Start-LauncherGame} catch {Show-Error $_.Exception.Message}
})
$startBoth.Add_Click({Start-BothGames})
$saveChoice.Add_SelectedIndexChanged({Update-Fields})
$recover.Add_Click({
    if(-not $hostRadio.Checked -or $script:transferBusy -or $script:liveBusy){return}
    $values=Read-ProxyStatusValues (Join-Path $gameBox.Text.Trim() 'alut_proxy.status')
    $config=Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
    if(-not (Test-ManualLiveResyncAvailable $values $config (Test-GameRunning))){
        Write-LauncherLog 'Neuabgleich noch nicht möglich. Beide PCs müssen TF3 mit der gemeinsamen Karte geöffnet haben.'; return
    }
    try {
        if($script:lobby -and $script:lobby.Connected){$script:lobby.Send('RESYNC',[Guid]::NewGuid().ToString('N'))}
        Invoke-LiveResync $values @{Kind='manual'; Detail='Gastgeber'}
    } catch {Show-Error $_.Exception.Message}
})
$navHost.Add_Click({ Close-LauncherLobby; if($script:internetRole -eq 'client'){Stop-LauncherInternet}; Refresh-HostAddresses; $hostRadio.Checked=$true; Update-Fields })
$navJoin.Add_Click({ Close-LauncherLobby; if($script:internetRole -eq 'host'){Stop-LauncherInternet}; if ($fakeRadio.Checked -and $ipBox.Text -eq '127.0.0.1') { $ipBox.Text='' }; $clientRadio.Checked=$true; Update-Fields })
$navTest.Add_Click({ Close-LauncherLobby; Stop-LauncherInternet; $fakeRadio.Checked=$true; Update-Fields })
$hostAddress.Add_SelectedIndexChanged({ if(-not $script:refreshingAddresses -and -not $script:lobbyPreparing -and -not $script:transferBusy -and -not $script:liveBusy){Close-LauncherLobby; if($script:internetRole -eq 'host'){Stop-LauncherInternet}; Update-Fields} })
$internetSetup.Add_Click({ Start-LauncherInternetHost $false })
$ipv4Setup.Add_Click({ Start-LauncherInternetHost $true })
$clearAddress.Add_Click({ Clear-LauncherJoinAddress })
$connectionMode.Add_SelectedIndexChanged({ Close-LauncherLobby; Stop-LauncherInternet; $script:internetNeedsSetup=$connectionMode.SelectedIndex -eq 0; Refresh-HostAddresses; Update-Fields })
$internetCheck.Add_Click({ try { Test-LauncherInternetInvitation } catch { Write-LauncherLog $_.Exception.Message } })
$copyAddress.Add_Click({
	if ($script:internetRole -eq 'host' -and $script:internetInvite) {
		[System.Windows.Forms.Clipboard]::SetText($script:internetInvite)
		Write-LauncherLog 'Interneteinladung kopiert. Der Mitspieler fügt sie unter Beitreten ein und prüft sie von seinem PC.'
		return
	}
	if ($hostAddress.SelectedItem) {
		try {
			$endpoint = Parse-JoinAddress "$($hostAddress.SelectedItem.Address):$($portBox.Text.Trim())" '47800'
			[System.Windows.Forms.Clipboard]::SetText("$($endpoint.Address):$($endpoint.Port)")
			$script:internetNeedsSetup=$false
		} catch { Show-Error $_.Exception.Message; return }
		Write-LauncherLog 'Beitrittsadresse kopiert. Teile sie mit deinem Mitspieler im gemeinsamen VPN.'
	}
})
# v40: explicit local/peer request. The host sends a separate copy of a fresh save;
# both load it in the open game. World differences never start this operation.
$script:liveMemory = New-LiveResyncMemory
$script:liveBusy = $false

function Invoke-LiveResync($values, $reason) {
	$script:liveBusy = $true
	$gameDir = $gameBox.Text.Trim()
	$others = @($install, $startBoth, $check, $remove, $replay, $recover, $primary, $navHost, $navJoin, $navTest, $gameBox, $browse, $ipBox, $portBox, $roleBox)
	$why = switch ($reason.Kind) {
		'manual' { 'von dir per Knopf gestartet' }
		'diff' { "Abweichung im Aufbau ($(Get-WorldDifferenceText $reason.Detail))" }
		'clock' { 'der gemeinsame Zeitplan ist stehen geblieben' }
		'error' { "Fehler: $($reason.Detail)" }
		default { 'der Launcher deines Mitspielers hat ihn angefragt' }
	}
	$success = $false
	Register-LiveResync $script:liveMemory ([DateTime]::UtcNow)
	Write-LauncherLog "Angeforderter Neuabgleich im laufenden Spiel: Rolle $($values.mode), Grund $why, epoch $($values.epoch)"
	$script:transferHint = "`r`n`r`nManuell angeforderter Neuabgleich, Grund: $why.`r`nTF3 bleibt offen und lädt gleich den gemeinsamen Spielstand."
	$statusLabel.Text = 'Neuabgleich im laufenden Spiel ...'; $statusLabel.ForeColor = $Muted
	$tick = {
		param($text, $done, $total)
		$mb = if ($total -gt 0) { " ($([Math]::Round($done / 1MB, 1)) von $([Math]::Round($total / 1MB, 1)) MB)" } else { '' }
		Set-LauncherProgress $text $done $total
		[System.Windows.Forms.Application]::DoEvents()
		return $script:transferCancel
	}
	Enter-TransferBusy $others
	$transfer.Enabled = $true
	try {
		$cfg = Read-Ini (Join-Path $gameDir 'alut_proxy.ini')
		$port = [int]$cfg.port
		$saveDir = Get-SaveFolder $steam
		if (-not $saveDir) { throw 'Kein Spielstandordner gefunden.' }
		$statusPath = Join-Path $gameDir 'alut_proxy.status'
		$epochBefore = if ($values.epoch -match '^\d+$') { [int]$values.epoch } else { 0 }
		if ($values.mode -eq 'host') {
			# v37: immer ein frischer Stand. Die Bitte sagt auch dem Mitspieler Bescheid (resync_peer).
			$since = [DateTime]::UtcNow.AddSeconds(-1)
			Write-ProxyRequest $gameDir 'alut_proxy.save' 'save' | Out-Null
			$file = Wait-NewSave $saveDir $since $tick -timeoutSeconds 90 -waitText 'Das Spiel speichert den gemeinsamen Stand ...'
			$file = Wait-SaveWritten $file $tick
			# v37 (Lauf 39): eine eigene Kopie schicken. TF3 darf das Original währenddessen wieder speichern.
			$copy = Copy-SaveSnapshot $file $saveDir
			$savePath = Assert-LauncherSavePath $copy.FullName $saveDir
			# Lädt der Mitspieler ihn und dieses Spiel nicht, holt es ihn damit nach (Get-EpochCatchUp).
			$script:liveMemory.LastSave = $savePath
			$manifest = Get-LauncherManifest $gameDir $steam $tick
			$session = New-MultiplayerSession -Manifest $manifest -SavePath $savePath
			Write-LauncherLog "Neuabgleich: schicke $(Split-Path -Leaf $savePath) (Kopie von $($file.Name), gespeichert $($file.LastWriteTime.ToString('HH:mm:ss')))"
			$clock = [Diagnostics.Stopwatch]::StartNew()
			$script:LastSaveTransfer = $null
			$result = Send-Savegame $savePath $port $tick 150 -Session $session
			Write-LauncherLog "Neuabgleich: geschickt, $(Get-TransferRateText $savePath $clock)"
		} else {
			# Dem Gastgeber Bescheid sagen (resync_peer), außer er hat selbst gefragt.
			if ($reason.Kind -ne 'peer') { Write-ProxyRequest $gameDir 'alut_proxy.save' 'save' | Out-Null }
			if (-not $cfg.host) { throw 'In alut_proxy.ini fehlt die Adresse des Gastgebers.' }
			$manifest = Get-LauncherManifest $gameDir $steam $tick
			Write-LauncherLog "Neuabgleich: hole den Spielstand von $($cfg.host):$port"
			$clock = [Diagnostics.Stopwatch]::StartNew()
			$script:LastSaveTransfer = $null
			$result = Receive-Savegame $cfg.host $port $saveDir $tick { param($question) $true } -LocalManifest $manifest -WaitSeconds 150
			$script:liveMemory.LastSave = [string]$result.SavePath
			Write-LauncherLog "Neuabgleich: geholt, $(Get-TransferRateText $result.SavePath $clock) (inklusive Warten)"
		}
		Save-PreparedSession -Path (Join-Path $gameDir 'alut_session.json') -Session $result.Session -SavePath $result.SavePath | Out-Null
		$name = Get-LiveReloadName $result.SavePath
		$reloadPath = Write-ProxyRequest $gameDir 'alut_proxy.reload' "name=$name"
		Write-LauncherLog "Neuabgleich: TF3 soll '$name' laden"
		Wait-LiveReload $statusPath $epochBefore $tick 120 $reloadPath | Out-Null
		Write-LauncherLog "Neuabgleich: '$name' geladen"
		$success = $true
		Write-LauncherLog "Neuabgleich abgeschlossen: '$name' geladen. Sobald beide Karten bereit sind, gemeinsam die Pause aufheben."
	} catch {
		$problem = $_.Exception.Message
		Write-LauncherLog "Neuabgleich fehlgeschlagen: $problem"
		if ($problem -eq 'Abgebrochen.') {
			# Selbst abgebrochen: nicht gleich wieder anfangen.
			$success = $true
			Write-LauncherLog 'Neuabgleich abgebrochen. Nur der Gastgeber kann einen weiteren Versuch starten.'
		} else {
			Write-LauncherLog 'Kein automatischer weiterer Versuch. Bei Bedarf startet der Gastgeber Neu abgleichen erneut.'
		}
	} finally {
		Complete-LiveResync $script:liveMemory $success ([DateTime]::UtcNow)
		try {
			$latest=Read-ProxyStatusValues (Join-Path $gameDir 'alut_proxy.status')
			$script:liveMemory.PeerReq=[string]$latest.resync_peer
			if($latest.pid){$script:liveMemory.Pid=$latest.pid}
		} catch {}
		# Ältere Kopien weg, auch nach einem Fehlschlag; die zuletzt ausgetauschte bleibt.
		try {
			$old = Remove-OldSyncSaves (Get-SaveFolder $steam) $LiveResyncKeepSaves $script:liveMemory.LastSave
			if ($old) { Write-LauncherLog "Neuabgleich: $old ältere TF3MP-Sync-Spielstände gelöscht" }
		} catch {}
		$script:transferBusy = $false
		$script:transferHint = ''
		foreach ($b in $others) { $b.Enabled = $true }
		Update-Fields
		$script:liveBusy = $false
	}
}

# v37: Hat der Mitspieler den zuletzt ausgetauschten Stand geladen und dieses Spiel nicht (der
# Neuabgleich klappte nur auf einem PC), lädt dieses Spiel ihn nach; sonst verbinden sich die beiden
# DLLs nie wieder (verschiedene Runden).
function Invoke-EpochCatchUp($values, [string]$savePath, [int]$peerEpoch) {
	$script:liveBusy = $true
	$gameDir = $gameBox.Text.Trim()
	$others = @($install, $startBoth, $check, $remove, $replay, $recover, $primary, $navHost, $navJoin, $navTest, $gameBox, $browse, $ipBox, $portBox, $roleBox)
	$name = ''
	Write-LauncherLog "Neuabgleich nachholen: Mitspieler in Runde $peerEpoch, dieses Spiel in $($values.epoch); lade $(Split-Path -Leaf $savePath)"
	$script:transferHint = "`r`n`r`nDer Mitspieler hat den gemeinsamen Spielstand schon geladen, dieses Spiel noch nicht. Es lädt ihn jetzt nach."
	$tick = {
		param($text, $done, $total)
		Set-LauncherProgress $text $done $total
		[System.Windows.Forms.Application]::DoEvents()
		return $script:transferCancel
	}
	Enter-TransferBusy $others
	$transfer.Enabled = $true
	try {
		$name = Get-LiveReloadName $savePath
		$epochBefore = [int]$values.epoch
		$reloadPath = Write-ProxyRequest $gameDir 'alut_proxy.reload' "name=$name"
		Wait-LiveReload (Join-Path $gameDir 'alut_proxy.status') $epochBefore $tick 120 $reloadPath | Out-Null
		Write-LauncherLog "Neuabgleich nachgeholt: '$name' geladen"
		$out.Text = "Neuabgleich nachgeholt: '$name' ist geladen. Sobald beide verbunden sind, gemeinsam weiterspielen (Pause aufheben)."
	} catch {
		Write-LauncherLog "Neuabgleich nachholen fehlgeschlagen: $($_.Exception.Message)"
		$out.Text = "Der Mitspieler hat den gemeinsamen Spielstand geladen, dieses Spiel konnte ihn nicht nachladen: $($_.Exception.Message)`r`n`r`n" +
			"Bitte den Gastgeber bitten, 'Neu abgleichen' zu starten (TF3 startet dabei neu)."
	} finally {
		$script:transferBusy = $false
		$script:transferHint = ''
		foreach ($b in $others) { $b.Enabled = $true }
		Update-Fields
		$script:liveBusy = $false
	}
}

$script:peerEpoch = -1
$script:peerEpochRead = [datetime]::MinValue
Register-LobbyInputEvents
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval=500
$script:lastStatusUpdate=[datetime]::MinValue
$script:lastVisibleStatus=''
$script:shownActionIssues=@{}
$timer.Add_Tick({
	Update-InternetDiagnostics
	if($script:liveBusy -or $script:transferBusy -or $script:lobbyPreparing){return}
	try {Update-LauncherLobby} catch {Write-LauncherLog "Sitzungssteuerung: $($_.Exception.Message)"}
	if(([DateTime]::UtcNow-$script:lastStatusUpdate).TotalSeconds -lt 2){return}
	$script:lastStatusUpdate=[DateTime]::UtcNow
	try {
		if (-not $Preview -and -not $script:transferBusy -and (Test-GameRunning)) {
			Update-LauncherActionIssues $steam $gameBox.Text.Trim()
		}
		$issueLabel.Text = if ($script:actionIssues.Count) { "$($script:actionIssues.Count) Aktion(en) fehlgeschlagen – Ursachen stehen unten im Protokoll." } else { '' }
        foreach($issue in @($script:actionIssues.Issues)){
            $key="$($script:actionIssues.Pid)/$($issue.Place)/$($issue.Token)"
            if(-not $script:shownActionIssues.ContainsKey($key)){
                $script:shownActionIssues[$key]=$true
                $place=if($issue.Place -eq 'peer'){'beim Mitspieler'}else{'auf diesem PC'}
                Write-LauncherLog "Fehlgeschlagene Aktion $place | $($issue.Label): $(Get-ActionReasonText $issue.Reason) Kennung: $($issue.Token)"
            }
        }
        $status = Get-SessionStatus $gameBox.Text.Trim()
        if(-not (Test-GameRunning)){
            $status.Text=if($script:lobbyError){$script:lobbyError}elseif($clientRadio.Checked){$joinStatus.Text}elseif(Test-LobbyCanStart){'Mitspieler bereit. Ihr könnt gemeinsam starten.'}elseif($script:lobbyPhase -eq 'ready'){'Spielstand übertragen. Warte auf die Bereitschaft des Mitspielers.'}elseif($script:presence -and $script:presence.Connected){'Mitspieler verbunden. Jetzt Spielstand bereitstellen.'}else{'Verbindung herstellen und Einladung oder VPN-Adresse teilen.'}
        }
        $statusKey=$status.Text -replace '\d+ (Spielaktion\(en\)|Aktion\(en\)|Einträge|Diagnosebericht\(e\)) warten','$1 warten' -replace 'seit \d+ s','seit längerem'
        if($statusKey -ne $script:lastVisibleStatus){
            $script:lastVisibleStatus=$statusKey
            Write-LauncherLog $status.Text
            if(Test-GameRunning){
                $diagnostic=Read-ProxyStatusValues (Join-Path $gameBox.Text.Trim() 'alut_proxy.status')
                if($diagnostic.mode) { Write-LauncherLog "Spielkanal: Rolle=$($diagnostic.mode), Quelle geladen=$($diagnostic.loaded), Mod bereit=$($diagnostic.initialized), Partner bereit=$($diagnostic.peer_ready); UDP-Antworten=$($diagnostic.hello_received)." }
                if($status.Color -eq 'warning') { Write-LauncherLog "Aktionswartezeit: Stufe=$($diagnostic.order_stage), Kennung=$($diagnostic.order_token), ohne Fortschritt=$($diagnostic.order_progress_age_ms) ms; TF3 hier=$($diagnostic.work_phase)/$($diagnostic.work_token), gegenüber=$($diagnostic.peer_work_phase)/$($diagnostic.peer_work_token). Weltabweichungen lösen keinen automatischen Neuabgleich aus." }
                if($status.Color -in @('error','warning') -or $status.Text -match 'Abweichung|Warte auf Partner'){
                    $sync=Get-SyncStatus $steam; if($sync -and $sync -ne $script:lastSyncDiagnostic){$script:lastSyncDiagnostic=$sync; Write-LauncherLog $sync}
                }
            }
        }
        $statusLabel.Text=$status.Text
		$statusLabel.ForeColor = if ($status.Color -eq 'error') { [System.Drawing.ColorTranslator]::FromHtml('#FF8990') } elseif ($status.Color -eq 'warning') { [System.Drawing.ColorTranslator]::FromHtml('#F1C879') } elseif ($status.Color -eq 'ok') { $Accent } else { $Muted }
	} catch { $statusLabel.Text='Verbindungsstatus wird aktualisiert ...' }
	if ($Preview -or $script:transferBusy -or -not (Test-GameRunning)) { return }
	try {
		$values = Read-ProxyStatusValues (Join-Path $gameBox.Text.Trim() 'alut_proxy.status')
		$liveConfig = Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
		if (-not (Test-AutomaticResyncEnabled $values $liveConfig)) { return }
		$reason = Get-LauncherResyncReason $values
		# Ohne Verbindung: in welcher Runde ist der Mitspieler (höchstens alle 10 Sekunden lesen)?
		if ($values.connected -eq '1' -or $values.mode -notin 'host', 'client') { $script:peerEpoch = -1 }
		elseif (([DateTime]::UtcNow - $script:peerEpochRead).TotalSeconds -ge 10) {
			$script:peerEpochRead = [DateTime]::UtcNow
			$script:peerEpoch = Get-PeerEpoch (Join-Path $gameBox.Text.Trim() 'alut_proxy.log') ([string]$values.pid)
		}
		$catchUp = if ($reason) { $null } else { Get-EpochCatchUp $values $script:liveMemory $script:peerEpoch }
		if ($reason) { Invoke-LiveResync $values $reason }
		elseif ($catchUp) { Invoke-EpochCatchUp $values $catchUp $script:peerEpoch }
		elseif ($values.world -eq 'diff' -or $values.world_peer -eq 'diff' -or $values.error) {
			$note = "Abweichung ohne Neuabgleich: world=$($values.world)/$($values.world_peer) Felder=$($values.world_fields) error=$($values.error) ready=$($values.ready) resync=$($values.resync) bisher $($script:liveMemory.Count)"
			if ($script:liveNote -ne $note) { $script:liveNote = $note; Write-LauncherLog $note }
		}
	} catch { $script:liveBusy = $false; Write-LauncherLog "Zeitgeber: $($_.Exception.Message)" }
})
$form.Add_Shown({ if($Preview){return}; Write-LauncherLog "Launcher gestartet ($(Split-Path -Leaf $Root))"; $timer.Start() })
# v34: das normale X schließt den Launcher immer, auch während einer Übertragung. Laufende Schritte
# werden abgebrochen; danach endet der (versteckte) PowerShell-Prozess sicher.
$form.Add_FormClosing({ $script:transferCancel = $true; Close-LauncherLobby; if(-not $Preview){Write-LauncherLog 'Launcher geschlossen'}; Stop-LauncherInternet })
$form.Add_FormClosed({
	$timer.Stop(); $timer.Dispose()
	if (-not $Preview) { [Environment]::Exit(0) }
})
if ($Preview) {
	if (-not $PreviewPath) { $PreviewPath = Join-Path $env:TEMP 'tf3mp-launcher-preview.png' }

	$form.Show(); [System.Windows.Forms.Application]::DoEvents()
	$bitmap=New-Object System.Drawing.Bitmap($form.Width,$form.Height)
	$form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
	$bitmap.Save($PreviewPath); $bitmap.Dispose(); $form.Close()
	Write-Output $PreviewPath
} else { [void]$form.ShowDialog() }

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

function Install-All($gameDir, $mode, $port, $partner, $steam, $test = '') {
	if (Test-GameRunning) { throw 'Transport Fever 3 läuft noch. Bitte zuerst das Spiel beenden.' }
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
	# Nur für den Launcher; die DLL liest den Schlüssel nicht.
	if ($test) { $ini += "test=$test" }
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
	foreach ($f in 'alut_proxy.ini') {
		$p = Join-Path $gameDir $f
		if (Test-Path $p) { Remove-Item $p -Force }
	}
	foreach ($t in Get-ModTargets $steam) {
		if (Test-Path $t) { Remove-Item $t -Recurse -Force }
	}
}

# Zeigt die Netzwerk-Zeilen des letzten Spielstarts aus alut_proxy.log.
function Get-ConnectionStatus($gameDir) {
	$log = Join-Path $gameDir 'alut_proxy.log'
	if (-not (Test-Path $log)) { return 'Noch kein Protokoll. Bitte erst installieren und das Spiel einmal starten.' }
	$lines = @(Get-Content $log -Tail 3000)
	$start = 0
	for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match 'alut proxy v\S+ loaded') { $start = $i; break } }
	$net = @($lines[$start..($lines.Count - 1)] | Where-Object { $_ -match ' net: | loaded| unloaded|bridge: the mod has line' })
	$text = ($net | Select-Object -Last 12) -join "`r`n"
	if ($net -match 'net: loopback') {
		$head = if ($net -match 'bridge: the mod has line') { 'ALLEIN-TEST: eine Straße ist durch die ganze Kette gelaufen.' } else { 'Allein-Test aktiv. Baue im Spiel eine Straße, dann erneut prüfen.' }
	}
	elseif ($net -match 'net: connected to') {
		$head = 'VERBUNDEN - die beiden Spiele haben sich gefunden.'
		if ($net -match 'delivered to the peer|received from the peer') { $head += "`r`nStraßen wurden übertragen (siehe die 'line'-Zeilen unten)." }
	}
	elseif ($net -match 'net: off') { $head = 'Netzwerk ist aus (keine Einstellungen gespeichert).' }
	else { $head = 'Noch keine Verbindung zum Partner.' }
	return "$head`r`n`r`n$text"
}

function Test-FakeHostRunning {
	try { return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*fake-partner.ps1*' }).Count -gt 0 } catch { return $false }
}

# Startet tools\fake-partner.ps1 in einem eigenen, verkleinerten Fenster (läuft 2 Stunden), falls es noch nicht läuft.
function Start-FakeHost($port) {
	if (Test-FakeHostRunning) { return }
	$script = Join-Path $Root 'tools\fake-partner.ps1'
	if (-not (Test-Path $script)) { throw "Das Werkzeug fehlt:`n$script" }
	Start-Process powershell -WindowStyle Minimized -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script, '-Port', $port, '-Minutes', '120'
}

# Die letzten Abgleich-Zeilen des Mods aus stdout.txt (Pause, Geschwindigkeit, Prüfpunkte, Warnungen).
function Get-SyncStatus($steam) {
	try { $lines = Read-SameSpotLines (Find-SameSpotLog $steam) } catch { return '' }
	$sync = @($lines | Where-Object { $_ -match '\[mp_probe\]\s*(sync |gui script|journal test)' } | Select-Object -Last 8)
	if ($sync.Count -eq 0) { return '' }
	$text = ($sync | ForEach-Object { $_ -replace '^.*\[mp_probe\]\s*', '' }) -join "`r`n"
	return "`r`n`r`nAbgleich (letzte Zeilen aus dem Spiel):`r`n$text"
}

# ---------- Oberfläche ----------
$steam = Get-SteamRoot
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Transport Fever 3 Multiplayer (Test)'
$form.Size = New-Object System.Drawing.Size(560, 675)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

function Add-Label($text, $x, $y, $w = 500, $h = 20) {
	$l = New-Object System.Windows.Forms.Label
	$l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, $h)
	$form.Controls.Add($l); return $l
}

Add-Label 'Spielordner:' 15 15 | Out-Null
$gameBox = New-Object System.Windows.Forms.TextBox
$gameBox.Location = New-Object System.Drawing.Point(15, 35); $gameBox.Size = New-Object System.Drawing.Size(420, 23)
$gameBox.Text = Find-GameDir $steam
$form.Controls.Add($gameBox)
$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Suchen...'; $browse.Location = New-Object System.Drawing.Point(445, 34); $browse.Size = New-Object System.Drawing.Size(85, 25)
$browse.Add_Click({
	$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
	$dlg.Description = 'Ordner "Transport Fever 3" auswählen (enthält alut.dll)'
	if ($dlg.ShowDialog() -eq 'OK') { $gameBox.Text = $dlg.SelectedPath }
})
$form.Controls.Add($browse)

$roleBox = New-Object System.Windows.Forms.GroupBox
$roleBox.Text = 'Wer bist du?'; $roleBox.Location = New-Object System.Drawing.Point(15, 70); $roleBox.Size = New-Object System.Drawing.Size(515, 148)
$hostRadio = New-Object System.Windows.Forms.RadioButton
$hostRadio.Text = 'Gastgeber (der andere verbindet sich mit mir)'; $hostRadio.Location = New-Object System.Drawing.Point(12, 20); $hostRadio.Size = New-Object System.Drawing.Size(490, 22)
$clientRadio = New-Object System.Windows.Forms.RadioButton
$clientRadio.Text = 'Mitspieler (ich verbinde mich mit dem Gastgeber)'; $clientRadio.Location = New-Object System.Drawing.Point(12, 45); $clientRadio.Size = New-Object System.Drawing.Size(490, 22)
$loopRadio = New-Object System.Windows.Forms.RadioButton
$loopRadio.Text = 'Allein testen (eigene Bauten werden 100 m daneben nachgebaut)'; $loopRadio.Location = New-Object System.Drawing.Point(12, 70); $loopRadio.Size = New-Object System.Drawing.Size(490, 22)
$spotRadio = New-Object System.Windows.Forms.RadioButton
$spotRadio.Text = 'Gleiche Stelle testen (bauen, Spielstand neu laden, am selben Ort nachbauen)'; $spotRadio.Location = New-Object System.Drawing.Point(12, 95); $spotRadio.Size = New-Object System.Drawing.Size(490, 22)
$fakeRadio = New-Object System.Windows.Forms.RadioButton
$fakeRadio.Text = 'Test mit simuliertem Gastgeber (Pause, Tempo, Geld; ein PC)'; $fakeRadio.Location = New-Object System.Drawing.Point(12, 120); $fakeRadio.Size = New-Object System.Drawing.Size(490, 22)
$roleBox.Controls.AddRange(@($hostRadio, $clientRadio, $loopRadio, $spotRadio, $fakeRadio))
$form.Controls.Add($roleBox)

Add-Label 'IP-Adresse des Gastgebers:' 15 231 200 | Out-Null
$ipBox = New-Object System.Windows.Forms.TextBox
$ipBox.Location = New-Object System.Drawing.Point(215, 228); $ipBox.Size = New-Object System.Drawing.Size(150, 23)
$form.Controls.Add($ipBox)
Add-Label 'Port:' 380 231 40 | Out-Null
$portBox = New-Object System.Windows.Forms.TextBox
$portBox.Location = New-Object System.Drawing.Point(420, 228); $portBox.Size = New-Object System.Drawing.Size(110, 23)
$form.Controls.Add($portBox)

$myIp = Add-Label ("Deine IP-Adresse(n) im Heimnetz: " + (Get-LocalIPs)) 15 261 515 20
$hint = Add-Label ("Gastgeber: diese IP dem Mitspieler schicken. Windows fragt beim ersten Spielstart evtl. nach einer Firewall-Freigabe - erlauben.`r`n" +
	"Übers Internet geht das nur mit Portfreigabe (UDP) am Router oder einem gemeinsamen VPN wie Tailscale oder ZeroTier.") 15 281 515 64
$hint.ForeColor = [System.Drawing.Color]::DimGray

$install = New-Object System.Windows.Forms.Button
$install.Text = 'Installieren / Speichern'; $install.Location = New-Object System.Drawing.Point(15, 351); $install.Size = New-Object System.Drawing.Size(165, 32)
$startGame = New-Object System.Windows.Forms.Button
$startGame.Text = 'Spiel starten'; $startGame.Location = New-Object System.Drawing.Point(190, 351); $startGame.Size = New-Object System.Drawing.Size(110, 32)
$check = New-Object System.Windows.Forms.Button
$check.Text = 'Verbindung prüfen'; $check.Location = New-Object System.Drawing.Point(310, 351); $check.Size = New-Object System.Drawing.Size(125, 32)
$remove = New-Object System.Windows.Forms.Button
$remove.Text = 'Entfernen'; $remove.Location = New-Object System.Drawing.Point(445, 351); $remove.Size = New-Object System.Drawing.Size(85, 32)
$form.Controls.AddRange(@($install, $startGame, $check, $remove))
$replay = New-Object System.Windows.Forms.Button
$replay.Text = 'Am selben Ort nachbauen'; $replay.Location = New-Object System.Drawing.Point(15, 393); $replay.Size = New-Object System.Drawing.Size(185, 32)
$form.Controls.Add($replay)
$replayHint = Add-Label 'Nur für "Gleiche Stelle testen": nach dem Neuladen des Spielstands klicken.' 210 393 320 34
$replayHint.ForeColor = [System.Drawing.Color]::DimGray

$out = New-Object System.Windows.Forms.TextBox
$out.Multiline = $true; $out.ReadOnly = $true; $out.ScrollBars = 'Vertical'
$out.Location = New-Object System.Drawing.Point(15, 437); $out.Size = New-Object System.Drawing.Size(515, 185)
$out.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$form.Controls.Add($out)

function Update-Fields {
	$ipBox.Enabled = $clientRadio.Checked
	$portBox.Enabled = -not $loopRadio.Checked
	$replay.Enabled = $spotRadio.Checked
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
$ipBox.Text = $cfg.host
$portBox.Text = $cfg.port
Update-Fields
$out.Text = if ($gameBox.Text) { "Spiel gefunden: $($gameBox.Text)" } else { 'Spielordner nicht gefunden - bitte über "Suchen..." auswählen.' }

function Show-Error($msg) { [System.Windows.Forms.MessageBox]::Show($msg, 'Fehler', 'OK', 'Error') | Out-Null }

$install.Add_Click({
	try {
		$mode = if ($clientRadio.Checked -or $fakeRadio.Checked) { 'client' } elseif ($loopRadio.Checked) { 'loopback' } else { 'host' }
		# Gleiche Stelle: die DLL hört als Gastgeber ohne Partner, das Nachbau-Skript spielt den Partner.
		# Simulierter Gastgeber: das Spiel ist Mitspieler, tools\fake-partner.ps1 spielt auf 127.0.0.1 den Gastgeber.
		$test = if ($spotRadio.Checked) { 'samespot' } elseif ($fakeRadio.Checked) { 'fakehost' } else { '' }
		if ($fakeRadio.Checked) { $ipBox.Text = '127.0.0.1' }
		$port = $portBox.Text.Trim()
		if ($port -notmatch '^\d+$' -or [int]$port -lt 1024 -or [int]$port -gt 65535) { throw 'Der Port muss eine Zahl zwischen 1024 und 65535 sein (Standard 47800).' }
		$ip = $ipBox.Text.Trim()
		$parsed = $null
		if ($mode -eq 'client' -and -not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) { throw 'Bitte die IP-Adresse des Gastgebers eingeben, z. B. 192.168.1.10.' }
		$n = Install-All $gameBox.Text.Trim() $mode $port $ip $steam $test
		if ($test -eq 'fakehost') { Start-FakeHost $port }
		$role = if ($test -eq 'fakehost') { "Mitspieler eines simulierten Gastgebers auf diesem PC (Port $port)" }
			elseif ($test) { "Gleiche Stelle testen (Port $port)" }
			elseif ($mode -eq 'client') { "Mitspieler, verbindet sich mit $($ip):$port" }
			elseif ($mode -eq 'loopback') { 'Allein testen, eigene Bauten kommen 100 m daneben zurück' }
			else { "Gastgeber, wartet auf Port $port" }
		$next = if ($test -eq 'fakehost') {
			"Der simulierte Gastgeber läuft in einem kleinen PowerShell-Fenster (offen lassen).`r`n" +
			"1. 'Spiel starten', einen Spielstand laden, Tempo 1x lassen.`r`n" +
			"2. Etwa 8 Minuten laufen lassen. Nach gut 1 Minute pausiert das Spiel von selbst, 20 Sekunden später läuft es weiter,`r`n" +
			"   kurz danach eine Weile doppelt so schnell.`r`n" +
			"3. Ohne Speichern beenden."
		} elseif ($test) {
			"1. 'Spiel starten' und einen Spielstand laden.`r`n2. Bauen (z. B. Straße und Depot).`r`n" +
			"3. OHNE Speichern ins Hauptmenü und denselben Spielstand neu laden (Spiel nicht beenden).`r`n" +
			"4. Hier 'Am selben Ort nachbauen' klicken."
		} else { "Jetzt 'Spiel starten', einen Spielstand laden und danach 'Verbindung prüfen'." }
		$out.Text = "Installiert.`r`nRolle: $role`r`nMod kopiert in $n Steam-Konto/Konten.`r`n`r`n$next"
	} catch { Show-Error $_.Exception.Message }
})

$startGame.Add_Click({
	# Simulierter Gastgeber: falls sein Fenster inzwischen zu ist, wieder starten.
	try {
		$cfg = Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
		if ($cfg.test -eq 'fakehost') { Start-FakeHost $cfg.port }
	} catch { Show-Error $_.Exception.Message; return }
	try { Start-Process "steam://rungameid/$AppId" } catch { Show-Error 'Steam konnte nicht gestartet werden.' }
})

$check.Add_Click({
	try { $out.Text = (Get-ConnectionStatus $gameBox.Text.Trim()) + (Get-SyncStatus $steam) } catch { Show-Error $_.Exception.Message }
})

$replay.Add_Click({
	try {
		$cfg = Read-Ini (Join-Path $gameBox.Text.Trim() 'alut_proxy.ini')
		if ($cfg.test -ne 'samespot' -or $cfg.mode -ne 'host') {
			throw "Bitte zuerst 'Gleiche Stelle testen' wählen, 'Installieren / Speichern' klicken und das Spiel neu starten."
		}
		Assert-SameSpotGameRunning
		$log = Find-SameSpotLog $steam
		$rec = Get-SameSpotRecording (Read-SameSpotLines $log)
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

[void]$form.ShowDialog()

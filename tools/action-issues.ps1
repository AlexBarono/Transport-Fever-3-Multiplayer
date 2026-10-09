# Incremental, bounded log reader. Do not reread a large stdout.txt on every UI tick.
function New-ActionIssueReader {
	return @{ Path=''; Pid=''; Position=[int64]0; Decoder=[Text.Encoding]::UTF8.GetDecoder(); Pending=''; Discard=$false;
		Issues=(New-Object Collections.ArrayList); Seen=@{}; Count=0 }
}

function ConvertFrom-ActionHex([string]$text) {
	if (-not $text -or $text.Length -gt 640 -or $text.Length % 2 -or $text -notmatch '^[0-9a-fA-F]+$') { throw 'Invalid diagnostic text' }
	$bytes=New-Object byte[] ($text.Length / 2)
	for($i=0;$i -lt $bytes.Length;$i++) { $bytes[$i]=[Convert]::ToByte($text.Substring($i*2,2),16) }
	return ([Text.Encoding]::UTF8.GetString($bytes) -replace '[\x00-\x1f\x7f]',' ').Trim()
}

function Add-ActionIssueLine($reader, [string]$line) {
	if ($line -notmatch '\[mp_probe\]' -and $line -match 'Loading game from file ') {
		$reader.Issues.Clear(); $reader.Seen.Clear(); $reader.Count=0; return
	}
	if($line -notmatch '\[mp_probe\]\s*action issue (local|peer) I1 ([\w.\-]{1,64}) (partial|none) ([0-9a-fA-F]{2,640}) ([0-9a-fA-F]{2,480})\s*$') { return }
	$place=$matches[1]; $token=$matches[2]; $partial=$matches[3]; $label=$matches[4]; $reason=$matches[5]
	$key="$place/$token"
	if($reader.Seen.ContainsKey($key)) { return }
	try { $label=ConvertFrom-ActionHex $label; $reason=ConvertFrom-ActionHex $reason } catch { return }
	$time='Zeit unbekannt'
	if($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})Z') {
		try { $time=[datetime]::ParseExact($matches[1],'yyyy-MM-dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,
			[Globalization.DateTimeStyles]::AssumeUniversal).ToLocalTime().ToString('HH:mm:ss') } catch {}
	}
	# Keep both PCs' details, but one shared action is not two failed actions.
	$other=if($place -eq 'local'){'peer'}else{'local'}
	if(-not $reader.Seen.ContainsKey("$other/$token")) { $reader.Count++ }
	$reader.Seen[$key]=$true
	[void]$reader.Issues.Add(@{ Token=$token; Place=$place; Partial=($partial -eq 'partial'); Label=$label; Reason=$reason; Time=$time })
	while($reader.Issues.Count -gt 30) {
		$old=$reader.Issues[0]; $reader.Seen.Remove("$($old.Place)/$($old.Token)"); $reader.Issues.RemoveAt(0)
	}
}

function Update-ActionIssues($reader, [string]$path, [string]$gamePid='') {
	if(-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
	$share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
	$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
	try {
		if($reader.Path -ne $path -or $reader.Pid -ne $gamePid -or $stream.Length -lt $reader.Position) {
			$fresh=New-ActionIssueReader; $reader.Clear(); foreach($key in $fresh.Keys) { $reader[$key]=$fresh[$key] }
			$reader.Path=$path; $reader.Pid=$gamePid
		}
		[void]$stream.Seek($reader.Position,[IO.SeekOrigin]::Begin)
		$bytes=New-Object byte[] 262144
		$read=$stream.Read($bytes,0,$bytes.Length); $reader.Position+=$read
		if(-not $read) { return }
		$chars=New-Object char[] ($read+2)
		$length=$reader.Decoder.GetChars($bytes,0,$read,$chars,0,$false)
		$text=$reader.Pending + [string]::new($chars,0,$length)
		$parts=$text -split "`n"; $reader.Pending=''
		for($i=0;$i -lt $parts.Count-1;$i++) {
			if(-not $reader.Discard -and $parts[$i].Length -le 4096) { Add-ActionIssueLine $reader $parts[$i].TrimEnd("`r") }
			$reader.Discard=$false
		}
		$last=$parts[-1]
		if($reader.Discard -or $last.Length -gt 4096) { $reader.Discard=$true }
		else { $reader.Pending=$last }
	} finally { $stream.Dispose() }
}

function Get-ActionReasonText([string]$reason) {
	$explanation = switch -Regex ($reason) {
		'subvention.*terms/rewards differ' { 'Die Subvention fehlt oder hat auf diesem PC andere Bedingungen oder Belohnungen. Es wurde keine zusätzliche Auszahlung gebucht.'; break }
		'subvention.*not found|subvention.*unreadable|subvention.*missing' { 'Die Subvention fehlt, ist abgelaufen oder konnte auf diesem PC nicht gelesen werden.'; break }
		'subvention.*ambiguous|subvention.*collision' { 'Die Subvention konnte nicht eindeutig zugeordnet werden. Es wurde keine zusätzliche Auszahlung gebucht.'; break }
		'subvention.*already decided|subvention.*already accepted|subvention.*instead of declined' { 'Über diese Subvention wurde bereits anders entschieden. Es wurde keine weitere Auszahlung ausgelöst.'; break }
		'subvention.*not applied' { 'TF3 hat die Annahme oder Ablehnung der Subvention nicht bestätigt. Konto und Auftragsliste prüfen.'; break }
		'invalid company name' { 'Der Unternehmensname ist leer, zu lang oder enthält nicht erlaubte Steuerzeichen.'; break }
		'economy scheduling failed' { 'Die Änderung konnte nicht in den gemeinsamen Zeitplan aufgenommen werden. Verbindung prüfen und erneut versuchen.'; break }
		'loan limit' { 'Auf diesem PC ist die Höchstzahl an Krediten erreicht.'; break }
		'loan to repay.*not found|loan to repay.*ambiguous' { 'Der zurückzuzahlende Kredit fehlt auf diesem PC oder ist nicht eindeutig zugeordnet.'; break }
		'no path' { 'TF3 findet keinen befahrbaren Weg zur Linie. Depotanschluss, Gleisrichtung und Haltestellen prüfen.'; break }
		'missing electrification' { 'Auf dem Fahrweg fehlt die benötigte Elektrifizierung.'; break }
		'missing rail|missing road|missing tram|incompatible rail|incompatible tram' { 'Der Fahrweg passt nicht zum Fahrzeugtyp.'; break }
		'construction-owned' { 'Eine zum Gebäude gehörende Zufahrt konnte nicht sicher geändert werden.'; break }
		'node configurations|existing node|node.*not found|node.*resolved' { 'Ein benötigter Gleis-/Straßenanschluss wurde nicht gefunden.'; break }
		'bridge|tunnel|resource' { 'Eine benötigte Bauressource fehlt oder ist nicht zuordenbar.'; break }
		'vehicle.*not found|vehicle.*missing' { 'Das zugehörige Fahrzeug fehlt auf diesem PC.'; break }
		'line.*not found|station.*not found|station.*resolve' { 'Die zugehörige Linie oder Haltestelle fehlt.'; break }
		'rejected|not possible|critical' { 'TF3 hat die Ausführung abgelehnt.'; break }
		default { 'Die Aktion konnte nicht vollständig übernommen werden.' }
	}
	return "$explanation Technischer Grund: $reason"
}

function Get-ActionIssueDetails($reader) {
	if(-not $reader.Count) { return '' }
	$lines=@("$($reader.Count) fehlgeschlagene Aktion(en) seit dem Laden. Die Sitzung läuft weiter.",
		"Bauten, Konto, Subventionen und Unternehmensname prüfen. 'Neu abgleichen' übernimmt bei Bedarf den Gastgeberstand; keine automatische Wiederholung.")
	foreach($issue in @($reader.Issues | Select-Object -Last 10)) {
		$place=if($issue.Place -eq 'peer'){'beim Mitspieler'}else{'auf diesem PC'}
		$effect=if($issue.Partial){'Möglicherweise teilweise ausgeführt; Karte, Konto und Unternehmensfenster prüfen.'}else{'Vor dem Senden eines Spielbefehls abgelehnt; keine Ausführung bestätigt.'}
		$lines+="`r`n$($issue.Time) $place | $($issue.Label)`r`n$(Get-ActionReasonText $issue.Reason)`r`n$effect Kennung: $($issue.Token)"
	}
	return ($lines -join "`r`n") + "`r`n`r`n"
}

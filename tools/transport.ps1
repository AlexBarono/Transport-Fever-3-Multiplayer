# Protocol v2 helpers shared by the local test partners. Build/action payloads are ASCII encoded.
function New-MpReceiver { return @{ Parts = @{}; Done = @{} } }
function Read-MpDataPacket($state, [string]$packet) {
	if ($packet -match '^TF3MP/1 CHECK (\S+)$') {
		$token = $matches[1]
		$reply = if ($state.Done.ContainsKey($token)) { "DONE $token $($state.Done[$token])" } else { "RESET $token" }
		return @{ Reply = "TF3MP/1 $reply" }
	}
	if ($packet -match '^TF3MP/1 FRAG (\S+) (\d+) (\d+) (.+)$') {
		$token = $matches[1]; $index = [int]$matches[2]; $count = [int]$matches[3]; $text = $matches[4]
		if ($count -lt 1 -or $count -gt 342 -or $index -ge $count -or $text.Length -gt 768 -or ($index -lt $count - 1 -and $text.Length -ne 768)) { return }
		if ($state.Done.ContainsKey($token)) { return @{ Reply = "TF3MP/1 DONE $token $($state.Done[$token])" } }
		if (-not $state.Parts.ContainsKey($token)) {
			if ($index -ne 0) { return @{ Reply = "TF3MP/1 RESET $token" } }
			# Only one message is in flight per peer. Bound incomplete assemblies.
			$state.Parts.Clear()
			$state.Parts[$token] = @{ Next = 0; Count = $count; Text = New-Object System.Text.StringBuilder }
		}
		$part = $state.Parts[$token]
		if ($part.Count -ne $count -or $index -gt $part.Next) { return }
		if ($index -eq $part.Next) { [void]$part.Text.Append($text); $part.Next++ }
		if ($part.Text.Length -gt 262144) { $state.Parts.Remove($token); return }
		if ($part.Next -eq $count) {
			# Here the test partner's work is to retain the complete recording, not run TF3 commands.
			$state.Done[$token] = 'OK'; $state.Parts.Remove($token)
			return @{ Reply = "TF3MP/1 DONE $token OK"; Token = $token; Text = $part.Text.ToString() }
		}
		return @{ Reply = "TF3MP/1 PART $token $index" }
	}
	if ($packet -match '^TF3MP/1 LINE (\S+) (.+)$') {
		$token = $matches[1]; $text = $matches[2]
		if ($text.Length -gt 262144) { return }
		if ($state.Done.ContainsKey($token)) { return @{ Reply = "TF3MP/1 DONE $token $($state.Done[$token])" } }
		$state.Done[$token] = 'OK'
		return @{ Reply = "TF3MP/1 DONE $token OK"; Token = $token; Text = $text }
	}
}

function New-MpSend($token, [string]$text) {
	if ($text.Length -gt 262144 -or $text.Length -eq 0) { throw 'Die Aktion ist leer oder groesser als 256 KiB.' }
	return @{ Token = $token; Text = $text; Part = 0; Count = [int][Math]::Ceiling($text.Length / 768.0); Received = $false; Done = $false }
}
function Get-MpSendPacket($send) {
	if ($send.Received -or $send.Part -ge $send.Count) { return "TF3MP/1 CHECK $($send.Token)" }
	$offset = $send.Part * 768; $length = [Math]::Min(768, $send.Text.Length - $offset)
	return "TF3MP/1 FRAG $($send.Token) $($send.Part) $($send.Count) $($send.Text.Substring($offset, $length))"
}
function Confirm-MpSend($send, [string]$packet) {
	if ($packet -notmatch '^TF3MP/1 (PART|GOT|DONE|RESET) (\S+)(?: (\S+))?$' -or $matches[2] -ne $send.Token) { return }
	switch ($matches[1]) {
		'PART' { if ([int]$matches[3] -eq $send.Part) { $send.Part++ } }
		'GOT' { $send.Received = $true }
		'RESET' { $send.Part = 0; $send.Received = $false }
		'DONE' {
			if ($matches[3] -eq 'FAIL') { throw "Das Spiel hat Aktion $($send.Token) abgelehnt. Abgleich der Spielstaende erforderlich; Folgeaktionen angehalten." }
			if ($matches[3] -eq 'OK') { $send.Done = $true }
		}
	}
}

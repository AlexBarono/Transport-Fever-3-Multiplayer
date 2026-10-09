# Test auf einem PC: spielt den Gastgeber für ein Spiel, das als Mitspieler auf 127.0.0.1 eingestellt ist
# (alut_proxy.ini: mode=client, host=127.0.0.1, port=47800). So lässt sich der Abgleich von Pause,
# Geschwindigkeit, Spielzeit, Geld und Zählern prüfen, ohne dass ein zweiter PC mitspielt.
#
# Ablauf (Sekunden ab dem ersten Lebenszeichen des Spiels, also wenn der Spielstand geladen ist):
#     0  der Gastgeber folgt dem Spiel (gleiche Geschwindigkeit, gleiche Spielzeit)
#    60  der Gastgeber pausiert             -> das Spiel muss pausieren
#    80  der Gastgeber läuft wieder mit 1x  -> das Spiel muss weiterlaufen
#   100  der Gastgeber ist 90 s Spielzeit voraus -> das Spiel muss mit 2x aufholen
#   danach: der Gastgeber hat 5000 mehr Geld, bis das Spiel sie nachgebucht hat (das Spiel meldet
#           seine Buchungen als adj= im Prüfpunkt) -> das Spiel bucht 5000 nach;
#           ab dem vierten Prüfpunkt ein Fahrzeug mehr -> das Spiel meldet eine Abweichung
# Bau-Zeilen des Spiels werden bestätigt (GOT) und aufgehoben. Lädt das Spiel den Spielstand neu
# (seine Spielzeit springt zurück), schickt der Gastgeber sie, sobald das Spiel wieder 20 s läuft,
# eine nach der anderen zurück: das Spiel baut sie an derselben Stelle nach (wie "Gleiche Stelle
# testen", nur ohne Knopf).
#
# Aufruf: powershell -ExecutionPolicy Bypass -File tools\fake-partner.ps1 [-Port 47800] [-Minutes 12] [-LogFile <pfad>]
param(
	[int]$Port = 47800,
	[double]$Minutes = 12,
	[string]$LogFile = '',
	[ValidateRange(1, 3600)][int]$ReplayTimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'transport.ps1')
$receiver = New-MpReceiver
if (-not $LogFile) { $LogFile = Join-Path $PSScriptRoot 'fake-partner.log' }
# Preserve an interrupted run rather than silently overwriting its evidence.
if (Test-Path -LiteralPath $LogFile) {
	Copy-Item -LiteralPath $LogFile -Destination ("$LogFile." + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff') + '.previous')
}
Set-Content -Path $LogFile -Value @() -Encoding UTF8

$script:start = [DateTime]::UtcNow
function Now { return ([DateTime]::UtcNow - $script:start).TotalSeconds }
function Log($text) {
	$line = ('{0,7:N1} {1}' -f (Now), $text)
	# A report viewer may briefly hold the log open. Diagnostics must not kill the peer.
	for ($writeTry = 0; $writeTry -lt 20; $writeTry++) {
		try {
			$share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
			$stream = New-Object IO.FileStream($LogFile, [IO.FileMode]::Append, [IO.FileAccess]::Write, $share)
			try {
				$bytes = [Text.Encoding]::UTF8.GetBytes($line + "`r`n")
				$stream.Write($bytes, 0, $bytes.Length)
			} finally { $stream.Dispose() }
			break
		} catch [IO.IOException] {
			if ($writeTry -eq 19) { Write-Warning "Test log temporarily unavailable: $line" }
			else { Start-Sleep -Milliseconds 25 }
		}
	}
	Write-Host $line
}

function Parse-State($text) {
	$t = @{}
	foreach ($pair in ($text -split ' ')) {
		$i = $pair.IndexOf('=')
		if ($i -gt 0) {
			$v = $pair.Substring($i + 1)
			$n = 0.0
			if ([double]::TryParse($v, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { $t[$pair.Substring(0, $i)] = $n }
			else { $t[$pair.Substring(0, $i)] = $v }
		}
	}
	return $t
}

function Format-State($t) {
	$parts = foreach ($k in ($t.Keys | Sort-Object)) {
		$v = $t[$k]
		if ($v -is [double] -or $v -is [int] -or $v -is [int64]) { $v = ([int64][Math]::Round([double]$v)).ToString([System.Globalization.CultureInfo]::InvariantCulture) }
		"$k=$v"
	}
	return ($parts -join ' ')
}

# Nur auf 127.0.0.1, damit Windows nicht nach einer Firewall-Freigabe fragt.
$udp = New-Object System.Net.Sockets.UdpClient((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $Port)))
$udp.Client.ReceiveTimeout = 200
# Ohne das meldet Windows ein ICMP "Port nicht erreichbar" beim nächsten Empfang als Fehler.
try { [void]$udp.Client.IOControl(-1744830452, [byte[]](0, 0, 0, 0), $null) } catch {}
Log "fake host listening on UDP port $Port for $Minutes minutes"

$peer = $null
$client = $null        # last gui state of the game
$clientAt = 0          # when it changed (hb)
$hostReg = $null       # speed register of the fake host
$hb = 0
$lastSend = -10
$lastHello = -10
$t0 = $null            # first gui state of the game
$hostSim = $null       # checkpoint answered last
$firstCk = $null
$catchup = $null       # @{ start; gt } while the fake host is ahead
$phase = 'follow'
$deadline = $Minutes * 60
$lines = 0
$lastLineToken = $null
$sessionLines = New-Object System.Collections.ArrayList   # build lines since the last load
$replay = New-Object System.Collections.ArrayList         # lines to send back after a reload
$replayAfterGt = $null
$replayToken = $null                                      # line in flight
$replaySend = $null
$replaySentAt = -10
$replayTries = 0
$replayCount = 0
$replayDone = 0
$replayRound = 0
$replayFailure = $null
$replayProgressAt = 0

function Client-Gt {
	if (-not $client) { return 0 }
	$run = [double]$client['run']
	return [double]$client['gt'] + ((Now) - $clientAt) * 1000 * $run
}

function Set-HostSpeed($speed, $why) {
	$script:hostReg.ver = [Math]::Max($script:hostReg.ver, [double]$script:client['ver']) + 1
	$script:hostReg.speed = $speed
	$script:hostReg.by = 'host'
	Log "HOST sets speed $speed (version $($script:hostReg.ver)): $why"
}

function Send-Text($text) {
	if (-not $script:peer) { return }
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
	[void]$script:udp.Send($bytes, $bytes.Length, $script:peer)
}

while ((Now) -lt $deadline -and -not $replayFailure) {
	$packet = $null
	try {
		$from = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
		$packet = [System.Text.Encoding]::UTF8.GetString($udp.Receive([ref]$from))
	} catch {
		# Zeitüberschreitung beim Empfang: weiter.
	}
	if ($packet -match '^TF3MP/1 PROBE ([A-Za-z0-9-]+)$') {
		$ready = [System.Text.Encoding]::ASCII.GetBytes("TF3MP/1 READY $($matches[1]) proto=2")
		[void]$udp.Send($ready, $ready.Length, $from)
		continue
	}
	if ($packet) {
		if (-not $peer) { Log "game connected from $from" }
		$peer = $from
		$data = Read-MpDataPacket $receiver $packet
		if ($data) {
			Send-Text $data.Reply
			if ($data.Text) {
				$lines++; [void]$sessionLines.Add($data.Text)
				Log "recorded build $($data.Token) ($($data.Text.Length) bytes)"
			}
		}
		elseif ($replaySend -and $packet -match '^TF3MP/1 (PART|GOT|DONE|RESET) ') {
			$before = $replaySend.Part
			try { Confirm-MpSend $replaySend $packet } catch {
				if (-not $replayFailure) {
					$replayFailure = $_.Exception.Message
					Log "REPLAY FAILED at line $($replayDone + 1) of $replayCount ($replayToken): $replayFailure"
					Log 'Following actions remain stopped. Restart the game and the test from the original save after fixing the rejected action.'
				}
			}
			if ($replaySend.Part -ne $before) { $replaySentAt = -10; $replayProgressAt = Now }
			if ($replaySend.Done) {
				$replayDone++; Log "game APPLIED line $replayDone of $replayCount"
				$replayToken = $null; $replaySend = $null; $replay.RemoveAt(0)
			}
		}
		elseif ($packet.StartsWith('TF3MP/1 STATE gui ')) {
			$s = Parse-State $packet.Substring(18)
			# The savegame was loaded again: its game time went back.
			if ($client -and [double]$s['gt'] -lt [double]$client['gt'] - 30000) {
				Log "the game loaded a savegame again (game time $([int64]$client['gt']) -> $([int64]$s['gt']))"
				$hostSim = $null; $firstCk = $null
				if ($sessionLines.Count -gt 0) {
					foreach ($l in $sessionLines) { [void]$replay.Add($l) }
					$replayRound++
					$replayCount = $replay.Count; $replayDone = 0; $replayToken = $null; $replaySend = $null
					$replayAfterGt = [double]$s['gt'] + 20000
					Log "$($sessionLines.Count) build line(s) of the session before go back to the game once it ran 20 s"
					$sessionLines.Clear()
				}
			}
			if (-not $client -or $s['hb'] -ne $client['hb']) { $clientAt = Now }
			if (-not $client -or $s['speed'] -ne $client['speed'] -or $s['ver'] -ne $client['ver'] -or $s['run'] -ne $client['run']) {
				Log "game speed state: $($packet.Substring(18))"
			}
			$client = $s
			if (-not $t0) {
				$t0 = Now
				$hostReg = @{ speed = [double]$client['speed']; ver = [double]$client['ver']; by = 'host' }
				Log "game is running (src=$($client['src'])); scenario starts"
			}
		}
		elseif ($packet.StartsWith('TF3MP/1 STATE sim ')) {
			$s = Parse-State $packet.Substring(18)
			$ck = [int]$s['ck']
			if (-not $hostSim -or $hostSim['ck'] -ne $ck) {
				$answer = @{}
				foreach ($k in $s.Keys) { $answer[$k] = $s[$k] }
				$notes = @()
				if ($t0 -and -not $firstCk -and (Now) - $t0 -ge 20) { $firstCk = $ck }
				# Like a real host the fake one keeps its 5000 more; only what the game booked (adj) evens it out.
				if ($firstCk -and $ck -ge $firstCk + 1) {
					$adj = 0.0
					if ($s.ContainsKey('adj')) { $adj = [double]$s['adj'] }
					$answer['money'] = [double]$s['money'] + 5000 - $adj
					if (5000 - $adj -ne 0) { $notes += "money $(5000 - $adj) higher" }
				}
				if ($firstCk -and ($ck -eq $firstCk + 4 -or $ck -eq $firstCk + 5)) {
					$answer['veh'] = [double]$s['veh'] + 1
					$notes += 'one vehicle more'
				}
				$note = if ($notes.Count -gt 0) { $notes -join ', ' } else { 'same values' }
				$hostSim = $answer
				Log "checkpoint $ck of the game: money=$($s['money']) adj=$($s['adj']) veh=$($s['veh']) date=$($s['date']); host answers with $note"
			}
		}
	}

	$now = Now
	if ($client -and $hostReg) {
		# Changes of the game's player win when they are newer.
		if ([double]$client['ver'] -gt $hostReg.ver) {
			$hostReg.ver = [double]$client['ver']; $hostReg.speed = [double]$client['speed']; $hostReg.by = "$($client['by'])"
			Log "the game changed the speed: $($hostReg.speed) (version $($hostReg.ver))"
		}
		$since = $now - $t0
		if ($phase -eq 'follow' -and $since -ge 60) { $phase = 'paused'; Set-HostSpeed 0 'pause test' }
		elseif ($phase -eq 'paused' -and $since -ge 80) { $phase = 'resumed'; Set-HostSpeed 1 'pause test over' }
		elseif ($phase -eq 'resumed' -and $since -ge 100) {
			$phase = 'ahead'
			$catchup = @{ start = $now; gt = (Client-Gt) + 90000 }
			Log "HOST is now 90 s of game time ahead (game time $([int64]$catchup.gt))"
		}
		elseif ($phase -eq 'ahead') {
			$hostGt = $catchup.gt + ($now - $catchup.start) * 1000 * $hostReg.speed
			# The mod stops catching up below 5 s (sync.CATCHUP_STOP_MS); both estimates lag by up to a heartbeat.
			if ((Client-Gt) -ge $hostGt - 8000) { $phase = 'done'; Log "the game caught up after $([int]($now - $catchup.start)) s" }
			elseif ($now - $catchup.start -gt 200) { $phase = 'done'; Log "the game did NOT catch up within 200 s" }
		}
	}
	# Replay after a reload: one line at a time, again every second until the game confirms it.
	if (-not $replayFailure -and $peer -and $replay.Count -gt 0 -and $client -and [double]$client['gt'] -ge $replayAfterGt) {
		if (-not $replayToken) {
			$replayToken = "fh$PID-$replayRound.$($replayDone + 1)"
			$replaySend = New-MpSend $replayToken $replay[0]
			$replaySentAt = -10
			$replayTries = 0
			$replayProgressAt = $now
		}
		if ($now - $replayProgressAt -ge $ReplayTimeoutSeconds) {
			$replayFailure = "No replay progress for $ReplayTimeoutSeconds seconds"
			Log "REPLAY TIMEOUT at line $($replayDone + 1) of $replayCount ($replayToken): $replayFailure"
			break
		}
		if ($now - $replaySentAt -ge 1) {
			$replaySentAt = $now
			$replayTries++
			Send-Text (Get-MpSendPacket $replaySend)
			if ($replayTries -eq 1) { Log "sending line $($replayDone + 1) of $replayCount back ($replayToken)" }
			elseif ($replayTries % 30 -eq 0) { Log "line $($replayDone + 1) not confirmed after $replayTries tries" }
		}
	}
	if ($peer -and $now - $lastHello -ge 2) {
		$lastHello = $now
		Send-Text "TF3MP/1 HELLO host pid=$PID seq=$hb proto=2 session=fh$PID"
	}
	if ($peer -and $hostReg -and $now - $lastSend -ge 1) {
		$lastSend = $now
		$hb++
		$run = $hostReg.speed
		$gt = Client-Gt
		if ($phase -eq 'ahead') { $gt = $catchup.gt + ($now - $catchup.start) * 1000 * $hostReg.speed }
		$state = @{ speed = $hostReg.speed; ver = $hostReg.ver; by = $hostReg.by; run = $run; tg = $run; src = 'gui'; hb = $hb; gt = $gt }
		Send-Text ("TF3MP/1 STATE gui " + (Format-State $state))
		if ($hostSim) { Send-Text ("TF3MP/1 STATE sim " + (Format-State $hostSim)) }
	}
}
$udp.Close()
Log "fake host stopped ($lines build line(s) received, $replayDone sent back, last phase '$phase')"
if ($replayFailure) { Log "replay stopped: $replayFailure" }

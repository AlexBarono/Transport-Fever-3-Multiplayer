# Gleiche-Stelle-Test: baut die Bauten einer früheren Spielsitzung an genau derselben Stelle nach,
# so wie es der Mitspieler mit demselben Spielstand bekäme (gleiches Gelände, keine 100 m daneben).
#
# Ablauf:
#   1. Im Launcher "Gleiche Stelle testen" wählen, installieren, Spiel starten, Spielstand laden.
#   2. Bauen (z. B. Straße und Depot). Danach OHNE Speichern ins Hauptmenü und denselben Spielstand
#      neu laden. Das Spiel dabei nicht beenden, sonst ist die Aufnahme in stdout.txt weg.
#   3. Dieses Skript starten (oder im Launcher "Am selben Ort nachbauen"). Es nimmt alle
#      "net send"-Zeilen der vorigen Sitzung aus stdout.txt und schickt sie per UDP an die DLL
#      (Gastgeber-Modus, 127.0.0.1). Der Mod baut sie wie Zeilen vom Partner an Ort und Stelle.
#
# Aufruf ohne Launcher:
#   powershell -ExecutionPolicy Bypass -File tools\same-spot.ps1 [-Log <stdout.txt>] [-Port 47800] [-List]
# Mit -List werden die Zeilen nur angezeigt, nicht geschickt.
param(
	[string]$Log = '',
	[int]$Port = 47800,
	[double]$Pause = 2,
	[switch]$List
)

$SameSpotAppId = '3493540'
. (Join-Path $PSScriptRoot 'transport.ps1')

function Get-SameSpotSteamRoot {
	foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam') {
		try {
			$p = Get-ItemProperty $key -ErrorAction Stop
			$path = if ($p.SteamPath) { $p.SteamPath } else { $p.InstallPath }
			if ($path -and (Test-Path $path)) { return (Resolve-Path $path).Path }
		} catch {}
	}
	return 'C:\Program Files (x86)\Steam'
}

# Das zuletzt geschriebene stdout.txt aller Steam-Konten.
function Find-SameSpotLog($steam) {
	if (-not $steam) { $steam = Get-SameSpotSteamRoot }
	$userdata = Join-Path $steam 'userdata'
	$found = @()
	if (Test-Path $userdata) {
		foreach ($account in Get-ChildItem $userdata -Directory) {
			$f = Join-Path $account.FullName "$SameSpotAppId\local\crash_dump\stdout.txt"
			if (Test-Path $f) { $found += Get-Item $f }
		}
	}
	if ($found.Count -eq 0) { throw "stdout.txt von Transport Fever 3 nicht gefunden (unter $userdata)." }
	return ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# Liest die Datei, auch während das Spiel noch hineinschreibt.
function Read-SameSpotLines($path) {
	$share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
	$stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
	try {
		$reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
		$text = $reader.ReadToEnd()
	} finally { $stream.Dispose() }
	return $text -split "`r?`n"
}

# Teilt das Protokoll an jedem "Loading game from file <Name>" in Sitzungen und gibt die Bauzeilen
# der letzten Sitzung vor der aktuellen zurück, die welche hat.
# Ergebnis: @{ Save = Name der aufgenommenen Sitzung; Current = Name der aktuellen; Lines = @(...) }
function Get-SameSpotRecording($lines) {
	$sessions = @()
	$current = $null
	$uploads = @{}
	foreach ($line in $lines) {
		if ($line -match 'Loading game from file (.+?)\s*$') {
			$current = @{ Save = $matches[1]; Lines = New-Object System.Collections.ArrayList }
			$sessions += $current
			$uploads.Clear()
		} elseif ($current -and $line -match '\[mp_probe\]\s*net upload (\S+) (\d+) (\d+) (.+)$') {
			$id=$matches[1]; $index=[int]$matches[2]; $count=[int]$matches[3]; $text=$matches[4]
			if ($index -eq 0) { $uploads[$id] = New-Object System.Text.StringBuilder }
			if ($uploads.ContainsKey($id)) {
				[void]$uploads[$id].Append($text)
				if ($index -eq $count - 1) { [void]$current.Lines.Add($uploads[$id].ToString()); $uploads.Remove($id) }
			}
		} elseif ($current -and $line -match '\[mp_probe\]net send (.+?)\s*$') {
			[void]$current.Lines.Add($matches[1])
		}
	}
	if ($sessions.Count -lt 2) {
		throw 'Es ist nur ein geladener Spielstand im Protokoll. Bitte nach dem Bauen OHNE Speichern ins Hauptmenü und denselben Spielstand neu laden (Spiel dabei nicht beenden), dann noch einmal.'
	}
	for ($i = $sessions.Count - 2; $i -ge 0; $i--) {
		if ($sessions[$i].Lines.Count -gt 0) {
			return @{ Save = $sessions[$i].Save; Current = $sessions[-1].Save; Lines = @($sessions[$i].Lines) }
		}
	}
	throw 'In den früheren Sitzungen wurde nichts gebaut, das sich nachbauen lässt (keine "net send"-Zeilen).'
}

# Unter Windows muss das Spiel laufen, sonst wartet das Senden vergeblich.
function Assert-SameSpotGameRunning {
	if ($IsWindows -ne $false -and -not (Get-Process -Name 'TransportFever3' -ErrorAction SilentlyContinue)) {
		throw 'Transport Fever 3 läuft nicht. Bitte das Spiel offen lassen und den Spielstand neu laden, dann noch einmal.'
	}
}

# Schickt die Zeilen nacheinander an die DLL und wartet jeweils auf ihre Bestätigung (GOT).
# $progress bekommt einen Text pro Schritt.
function Send-SameSpotRecording($recording, $port, $pause, [scriptblock]$progress) {
	if (-not $progress) { $progress = { param($t) Write-Host $t } }
	$udp = New-Object System.Net.Sockets.UdpClient(0)
	$udp.Client.ReceiveTimeout = 1000
	$target = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $port)
	$stamp = [int64]([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds
	$total = $recording.Lines.Count
	$done = 0
	try {
		for ($i = 0; $i -lt $total; $i++) {
			$token = "gs$stamp.$($i + 1)"
			$send = New-MpSend $token $recording.Lines[$i]
			$bytes = $null
			$kind = $recording.Lines[$i].Substring(0, [Math]::Min(2, $recording.Lines[$i].Length))
			$ok = $false
			$silent = 0
			$deadline = [DateTime]::UtcNow.AddSeconds(120)
			while (-not $ok -and [DateTime]::UtcNow -lt $deadline) {
				$bytes = [System.Text.Encoding]::ASCII.GetBytes((Get-MpSendPacket $send))
				[void]$udp.Send($bytes, $bytes.Length, $target)
				$until = [DateTime]::UtcNow.AddSeconds(1)
				while (-not $ok -and [DateTime]::UtcNow -lt $until) {
					try {
						$from = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
						$answer = [System.Text.Encoding]::UTF8.GetString($udp.Receive([ref]$from))
						if ($from.Address.Equals($target.Address) -and $from.Port -eq $target.Port) {
							$before = $send.Part
							Confirm-MpSend $send $answer
							$ok = $send.Done
							if ($before -ne $send.Part) { break }
						}
					} catch {
						# Zeitüberschreitung: noch einmal schicken. 10054: niemand hört auf dem Port
						# (Windows meldet das beim nächsten Empfang).
						if ($_.Exception.Message -like "Das Spiel hat Aktion*") { throw }
						$e = $_.Exception
						while ($e.InnerException) { $e = $e.InnerException }
						if ($e -is [System.Net.Sockets.SocketException] -and
							"$($e.SocketErrorCode)" -in 'ConnectionReset', 'ConnectionRefused') { $silent++ }
						break
					}
				}
				if (-not $ok -and $silent -ge 5) {
					throw "Das Spiel antwortet nicht auf Port $port. Läuft es, und ist im Launcher 'Gleiche Stelle testen' installiert?"
				}
			}
			if (-not $ok) { throw "Zeile $($i + 1) von $total ($kind) wurde nach 2 Minuten nicht angenommen. Läuft das Spiel (nicht pausiert)?" }
			$done++
			& $progress "Zeile $($i + 1) von $total ($kind, $($send.Text.Length) Bytes) im Spiel ausgefuehrt."
			Start-Sleep -Milliseconds ([int]($pause * 1000))
		}
	} finally { $udp.Close() }
	return $done
}

# Direkt gestartet (nicht aus dem Launcher eingebunden):
if ($MyInvocation.InvocationName -ne '.') {
	try {
		if (-not $Log) { $Log = Find-SameSpotLog }
		Write-Host "Protokoll: $Log"
		$rec = Get-SameSpotRecording (Read-SameSpotLines $Log)
		Write-Host "Aufgenommen im Spielstand '$($rec.Save)': $($rec.Lines.Count) Zeile(n). Jetzt geladen: '$($rec.Current)'."
		if ($rec.Save -ne $rec.Current) { Write-Host 'Achtung: das ist ein anderer Spielstand als bei der Aufnahme.' }
		if ($List) {
			$n = 0
			foreach ($l in $rec.Lines) { $n++; Write-Host ("{0,3}: {1}" -f $n, ($l.Substring(0, [Math]::Min(160, $l.Length)))) }
			exit 0
		}
		Assert-SameSpotGameRunning
		$sent = Send-SameSpotRecording $rec $Port $Pause $null
		Write-Host "Fertig: $sent Zeile(n) an das Spiel übergeben. Im Spiel nachsehen, ob alles an derselben Stelle steht."
	} catch {
		Write-Host "Fehler: $($_.Exception.Message)"
		exit 1
	}
}

# Launcher-only integration. Internet sockets run in C# workers; WinForms stays responsive.
$script:internetTunnel = $null
$script:internetRole = ''
$script:internetInvite = ''
$script:internetLocalPort = 0
$script:internetMapping = $null
$script:internetLastStats = ''
$script:internetNeedsSetup = $false

function Write-InternetLog([string]$Event, $Data = @{}) {
    try {
        $folder = Join-Path $env:LOCALAPPDATA 'TF3MP\Logs'
        [IO.Directory]::CreateDirectory($folder) | Out-Null
        if (-not $script:internetLogPath) { $script:internetLogPath = Join-Path $folder ('internet-{0}-{1}.jsonl' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$PID) }
        if ((Test-Path -LiteralPath $script:internetLogPath) -and (Get-Item -LiteralPath $script:internetLogPath).Length -gt 2MB) { Move-Item -LiteralPath $script:internetLogPath -Destination ($script:internetLogPath+'.old') -Force }
        $record = @{ utc=[DateTime]::UtcNow.ToString('o'); event=$Event; data=$Data }
        # Do not pass invitations, keys, certificates or endpoint addresses here.
        Add-Content -LiteralPath $script:internetLogPath -Value ($record | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
    } catch {}
}

function Stop-LauncherInternet {
    if ($script:internetTunnel) { $script:internetTunnel.Dispose(); $script:internetTunnel=$null }
    if ($script:internetMapping) {
        $mapping=$script:internetMapping; $script:internetMapping=$null
        try { Invoke-InternetUpnp Remove $mapping.Port $mapping.Client $mapping.Owner { [Windows.Forms.Application]::DoEvents() } | Out-Null }
        catch { Write-InternetLog 'router_cleanup_failed' @{ type=$_.Exception.GetType().Name } }
    }
    $script:internetRole=''; $script:internetInvite=''; $script:internetLocalPort=0
}

function Resolve-LauncherEndpoint([string]$Text, [string]$DefaultPort) {
    if ($Text.Trim().StartsWith('tf3mp-internet://',[StringComparison]::Ordinal)) {
        $invite=Read-InternetInvitation $Text
        $localPort=47800
        if ($script:internetTunnel -and ($script:internetRole -ne 'client' -or $script:internetInvite -ne $Text.Trim())) {
            if (Test-GameRunning) { throw 'TF3 vor dem Wechsel der Internetverbindung beenden.' }
            Stop-LauncherInternet
        }
        if (-not $script:internetTunnel) {
            Initialize-InternetTransport
            $script:internetTunnel=[TF3MP.Internet.Tunnel]::StartClient($invite.Address,$invite.Port,$invite.Fingerprint,$invite.Key,$localPort)
            $script:internetRole='client'; $script:internetInvite=$Text.Trim(); $script:internetLocalPort=$localPort
            Write-InternetLog 'client_started' @{ family=([Net.IPAddress]::Parse($invite.Address).AddressFamily.ToString()); local_port=$localPort; public_port=$invite.Port }
        }
        return @{ Address='127.0.0.1'; Port=$localPort; Internet=$true }
    }
    if ($script:internetTunnel -and $script:internetRole -eq 'client') { throw 'Internetverbindung aktiv. Zum Wechsel auf VPN/LAN den Launcher neu öffnen.' }
    $endpoint=Parse-JoinAddress $Text $DefaultPort
    if($script:internetNeedsSetup -and $endpoint.Address -eq '127.0.0.1') { throw 'Nach einem Internetlauf die neue Einladung des Gastgebers einfügen. Die alte lokale Tunneladresse genügt nicht.' }
    $script:internetNeedsSetup=$false
    return $endpoint
}

function Assert-LauncherInternetMode([string]$Role, [int]$Port, [string]$Test) {
    if(-not $Test -and $Role -eq 'host' -and $script:internetNeedsSetup -and -not $script:internetTunnel) {
        throw 'Die letzte Sitzung nutzte Internet. Zuerst Internet ohne VPN neu einrichten und die neue Einladung teilen. Für VPN/LAN stattdessen die passende Adresse auswählen und Adresse kopieren klicken.'
    }
    if ($script:internetTunnel -and ($Test -or $Role -ne $script:internetRole -or $Port -ne $script:internetLocalPort)) {
        throw 'Internetzugang ist für eine andere Rolle oder einen anderen Spielport aktiv. Erst im Internetdialog beenden oder den Launcher neu öffnen.'
    }
}

function Get-LauncherInternetSummary {
    if(-not $script:internetTunnel) { return '' }
    $t=$script:internetTunnel
    return "Internet / TLS: $($script:internetRole), Spielkanal=$($t.GameChannelConnected), $($t.UdpPackets) Pakete, $([Math]::Round($t.TcpBytes/1MB,1)) MB, $($t.Reconnects) Wiederverbindungen, $($t.Rejected) abgewiesen.`r`nLetzte Transportmeldung: $($t.LastError)`r`nProtokoll: $script:internetLogPath`r`n`r`n"
}

function Test-LauncherInternetInvitation {
    $invite=Read-InternetInvitation $ipBox.Text
    Initialize-InternetTransport
    $task=[TF3MP.Internet.Tunnel]::ProbeAsync($invite.Address,$invite.Port,$invite.Fingerprint,$invite.Key)
    $out.Text='Prüfe Internetverbindung und Einladung beim Gastgeber ...'
    while (-not $task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
    if ($task.IsFaulted) {
        Write-InternetLog 'probe_failed' @{ type=$task.Exception.GetBaseException().GetType().Name }
        throw ('Internetverbindung fehlgeschlagen: ' + $task.Exception.GetBaseException().Message + "`r`nGastgeber: Internetzugang im Launcher offen lassen, Windows-TCP-Regel zulassen und Routerfreigabe prüfen. IPv6 braucht auf beiden PCs Internet-IPv6. Bei IPv4 kann CGNAT eine Freigabe verhindern.")
    }
    Write-InternetLog 'probe_ok'
    $out.Text="Internetverbindung zum Gastgeber bestätigt. Einladung und TLS-Zertifikat stimmen.`r`nJetzt den gemeinsamen Spielstand holen. Eine Prüfung auf demselben PC beweist keine Erreichbarkeit von außen."
}

function Show-InternetHostSetup([string]$PreviewPath = '') {
    if (-not $PreviewPath -and (Test-GameRunning)) { throw 'TF3 vor dem Einrichten einer neuen Internetverbindung beenden.' }
    if ($script:transferBusy) { return }
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text='Ohne VPN / Internetzugang'; $dialog.ClientSize=New-Object Drawing.Size(780,505)
    $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
    $dialog.BackColor=$Background; $dialog.ForeColor=$TextColor; $dialog.Font=$form.Font
    New-Label $dialog 'Dein PC ist der Gastgeber' 22 16 735 34 18 | Out-Null
    New-Label $dialog "IPv6 verbindet euch direkt. Bei IPv4 fragt der Launcher eine UPnP-Freigabe am Router an.`r`nBeides braucht eine passende Windows-Firewallregel. Der Launcher bleibt beim Spielen offen." 22 60 735 50 10 $Muted | Out-Null
    $addresses=New-Object Windows.Forms.ComboBox
    $addresses.Location=New-Object Drawing.Point(22,120); $addresses.Size=New-Object Drawing.Size(735,30)
    $addresses.DropDownStyle='DropDown'; $addresses.DisplayMember='Display'
    foreach($address in @(Get-InternetIPv6Addresses)) { [void]$addresses.Items.Add($address) }
    if($addresses.Items.Count -gt 0) { $addresses.SelectedIndex=0 }
    $dialog.Controls.Add($addresses)
    New-Label $dialog 'INTERNETPORT (TCP)' 22 166 220 22 9 $Muted | Out-Null
    $publicPort=New-Box $dialog 245 160 100
    $publicPort.Text=if($script:internetTunnel -and $script:internetRole -eq 'host') { "$($script:internetTunnel.Port)" } else { '47801' }
    $ipv6=New-Button $dialog 'Direkt starten' 22 206 200 38 $true
    $ipv4=New-Button $dialog 'IPv4 / Routerfreigabe' 234 206 240 38
    $firewall=New-Button $dialog 'Windows-Firewall zulassen' 486 206 271 38
    $message=New-Label $dialog 'Oben öffentliche IPv6 wählen oder öffentliche IPv4 bei manueller Routerfreigabe eingeben. IPv4 hinter CGNAT braucht weiterhin VPN oder einen Relaydienst.' 22 260 735 68 10 $Muted
    $invitation=New-Box $dialog 22 340 735; $invitation.ReadOnly=$true; $invitation.Font=New-Object Drawing.Font('Consolas',9)
    $copy=New-Button $dialog 'Einladung kopieren' 22 386 230 38 $true
    $stop=New-Button $dialog 'Internetzugang beenden' 264 386 250 38
    New-Label $dialog "Einladung nur mit deinem Mitspieler teilen. Sie gilt, solange dieser Launcher geöffnet ist.`r`nBeim Mitspieler: Beitreten > Einladung einfügen > Verbindung prüfen. Erst das prüft den Internetweg." 22 440 735 50 10 $Muted | Out-Null
    if($script:internetRole -eq 'host') { $invitation.Text=$script:internetInvite; $message.Text='Internetzugang läuft. Der Mitspieler prüft die Einladung von seinem PC.' }
    $start={
        param([bool]$UseIPv4)
        $buttons=@($ipv6,$ipv4,$firewall,$copy,$stop); foreach($button in $buttons) { $button.Enabled=$false }; $dialog.ControlBox=$false
        try {
            if($publicPort.Text -notmatch '^\d{1,5}$' -or [int]$publicPort.Text -lt 1024 -or [int]$publicPort.Text -gt 65535) { throw 'Internetport muss zwischen 1024 und 65535 liegen.' }
            $localPort=[int]$portBox.Text; $port=[int]$publicPort.Text
            if($localPort -lt 1024 -or $localPort -gt 65535 -or $localPort -eq $port) { throw 'Internetport und Spielport müssen verschieden sein.' }
            Stop-LauncherInternet
            Initialize-InternetTransport
            $script:internetTunnel=[TF3MP.Internet.Tunnel]::StartHost($port,$localPort)
            $script:internetRole='host'; $script:internetLocalPort=$localPort
            if($UseIPv4) {
                $message.Text='Frage TCP-Freigabe am Router an ...'; [Windows.Forms.Application]::DoEvents()
                $lan=Get-InternetLanIPv4; $owner='TF3MP TLS '+[Guid]::NewGuid().ToString('N')
                # Record ownership before mutation, so even a timed-out attempt can be cleaned up.
                $script:internetMapping=[pscustomobject]@{ Port=$port; Client=$lan; Owner=$owner }
                $mapping=Invoke-InternetUpnp Add $port $lan $owner { [Windows.Forms.Application]::DoEvents() }
                $address=$mapping.Address
                if (-not (Test-PublicInternetAddress ([Net.IPAddress]::Parse($address)))) { throw 'Der Router hat keine öffentliche IPv4-Adresse (z. B. CGNAT/DS-Lite). IPv6 oder VPN verwenden.' }
            } else {
                $address=if($addresses.SelectedItem) { $addresses.SelectedItem.Address } else { $addresses.Text.Trim() }
                $parsed=[Net.IPAddress]::Parse($address)
                if(-not (Test-PublicInternetAddress $parsed)) { throw 'Öffentliche IPv6 auswählen oder öffentliche IPv4 des Routers eingeben.' }
                if($parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6 -and -not $script:internetTunnel.SupportsIPv6) { throw 'IPv6 ist auf diesem PC nicht verfügbar. IPv4 oder VPN verwenden.' }
            }
            $script:internetInvite=New-InternetInvitation $address $port $script:internetTunnel.Fingerprint $script:internetTunnel.Key
            $invitation.Text=$script:internetInvite
            $message.Text="Internetzugang gestartet (TLS TCP $port). Jetzt Windows-Firewall zulassen und die Einladung teilen. Bei IPv6 kann zusätzlich die Router-Firewall eine TCP-Freigabe für diesen PC brauchen."
            $out.Text="Internet ohne VPN vorbereitet. Launcher offen lassen. Der Mitspieler prüft zuerst die Einladung von seinem PC.`r`nDanach den Spielstand wie gewohnt bereitstellen."
            Write-InternetLog 'host_started' @{ method=$(if($UseIPv4){'upnp_ipv4'}else{'direct'}); public_port=$port; local_port=$localPort }
        } catch { Stop-LauncherInternet; $invitation.Text=''; $message.Text=$_.Exception.Message; Write-InternetLog 'setup_failed' @{ type=$_.Exception.GetType().Name } }
        finally { foreach($button in $buttons) { $button.Enabled=$true }; $dialog.ControlBox=$true }
    }
    $ipv6.Add_Click({ & $start $false }); $ipv4.Add_Click({ & $start $true })
    $firewall.Add_Click({ try { if(-not $script:internetTunnel -or $script:internetRole -ne 'host') { throw 'Zuerst IPv6 oder IPv4 starten.' }; Enable-InternetFirewall $script:internetTunnel.Port; $message.Text='Windows-Regel für den verschlüsselten TCP-Port eingerichtet. Der Mitspieler prüft jetzt die Einladung.' } catch { $message.Text=$_.Exception.Message } })
    $copy.Add_Click({ if($invitation.Text) { [Windows.Forms.Clipboard]::SetText($invitation.Text); $message.Text='Einladung kopiert. Beim Mitspieler unter Beitreten einfügen und Verbindung prüfen.' } })
    $stop.Add_Click({ Stop-LauncherInternet; $script:internetNeedsSetup=$false; $invitation.Text=''; $message.Text='Internetzugang beendet. Eine neue Internetsitzung braucht eine neue Einladung. Eventuelle Fehler beim Entfernen der eigenen Routerfreigabe stehen im Internetprotokoll.' })
    if($PreviewPath) {
        $dialog.Show(); [Windows.Forms.Application]::DoEvents()
        $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
        $dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height)))
        $bitmap.Save($PreviewPath); $bitmap.Dispose(); $dialog.Close()
    } else { [void]$dialog.ShowDialog($form) }
    $dialog.Dispose()
}

function Update-InternetDiagnostics {
    if (-not $script:internetTunnel) { return }
    $t=$script:internetTunnel
    $values=@{ tcp_bytes=$t.TcpBytes; udp_packets=$t.UdpPackets; accepted=$t.Accepted; rejected=$t.Rejected; reconnects=$t.Reconnects; game_channel=$t.GameChannelConnected }
    $snapshot=($values | ConvertTo-Json -Compress)
    if($snapshot -ne $script:internetLastStats) { $script:internetLastStats=$snapshot; Write-InternetLog 'transport' $values }
}

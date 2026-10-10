# Internet setup is explicit. Merely opening the launcher changes no firewall/router rules.
function Initialize-InternetTransport {
    if (-not ('TF3MP.Internet.Tunnel' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'internet-tunnel.cs') }
}

function Test-PublicInternetAddress([Net.IPAddress]$Address) {
    $b = $Address.GetAddressBytes()
    if ($b.Length -eq 16) {
        # Native global unicast only; no link-local, ULA, multicast or Teredo.
        return (($b[0] -band 0xe0) -eq 0x20 -and -not ($b[0] -eq 0x20 -and $b[1] -eq 1 -and $b[2] -eq 0 -and $b[3] -eq 0))
    }
    return -not ($b[0] -eq 0 -or $b[0] -eq 10 -or $b[0] -eq 127 -or $b[0] -ge 224 -or
        ($b[0] -eq 169 -and $b[1] -eq 254) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
        ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127))
}

function Get-InternetIPv6Addresses {
    try {
        @(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop | Where-Object {
            $_.AddressState -eq 'Preferred' -and $_.InterfaceAlias -notmatch 'Teredo|VPN|Radmin|Tailscale|ZeroTier|Hamachi|TAP|TUN|Loopback' -and
            (Test-PublicInternetAddress ([Net.IPAddress]::Parse($_.IPAddress)))
        } | Sort-Object SkipAsSource, InterfaceMetric | ForEach-Object {
            [pscustomobject]@{ Address=$_.IPAddress; Display="$($_.IPAddress) / $($_.InterfaceAlias)" }
        })
    } catch { @() }
}

function Get-InternetLanIPv4 {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
        Where-Object { $_.NextHop -ne '0.0.0.0' -and $_.InterfaceAlias -notmatch 'VPN|Radmin|Tailscale|ZeroTier|Hamachi|TAP|TUN' } |
        Sort-Object RouteMetric | Select-Object -First 1
    if (-not $route) { throw 'Kein direkter IPv4-Internetanschluss gefunden.' }
    $address = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    if (-not $address) { throw 'Keine IPv4-Adresse am Internetadapter gefunden.' }
    return $address.IPAddress
}

function New-InternetInvitation([string]$Address, [int]$Port, [string]$Fingerprint, [string]$Key) {
    $ip = [Net.IPAddress]::Parse($Address)
    $endpoint = if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { "[$ip]" } else { "$ip" }
    $value = "tf3mp-internet://$($endpoint):$Port/$Fingerprint/$Key"
    [void](Read-InternetInvitation $value)
    return $value
}

function Read-InternetInvitation([string]$Text) {
    $Text = $Text.Trim()
    if ($Text.Length -gt 256 -or $Text -cnotmatch '^tf3mp-internet://(\[[0-9a-fA-F:]+\]|[0-9.]+):([0-9]{1,5})/([0-9a-f]{64})/([0-9a-f]{64})$') {
        throw 'Ungültige Interneteinladung. Bitte die vollständige Einladung des Gastgebers einfügen.'
    }
    $addressText = $matches[1]; $port = [int]$matches[2]; $pin = $matches[3]; $key = $matches[4]
    $address = $null
    if ($port -lt 1024 -or $port -gt 65535 -or -not [Net.IPAddress]::TryParse($addressText.Trim('[',']'), [ref]$address)) { throw 'Ungültige Internetadresse oder Portnummer.' }
    if ($address.Equals([Net.IPAddress]::Any) -or $address.Equals([Net.IPAddress]::IPv6Any) -or $address.IsIPv6Multicast -or $address.IsIPv6LinkLocal -or
        ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and ($address.ToString() -ne $addressText -or $address.GetAddressBytes()[0] -ge 224))) { throw 'Diese Internetadresse kann nicht verwendet werden.' }
    return [pscustomobject]@{ Address=$address.ToString(); Port=$port; Fingerprint=$pin; Key=$key }
}

function Invoke-InternetUpnp([ValidateSet('Add','Remove','Query')][string]$Mode, [int]$Port, [string]$ClientAddress, [string]$Owner, [scriptblock]$Tick = {}) {
    # COM discovery can wait on broken routers. Bound it in a disposable process;
    # no ThreadPool starvation and no frozen WinForms message loop.
    $job = Start-Job -ArgumentList $Mode,$Port,$ClientAddress,$Owner -ScriptBlock {
        param($mode,$port,$client,$owner)
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $mappings = $nat.StaticPortMappingCollection
        if ($null -eq $mappings) { throw 'Der Router bietet keine UPnP-Portfreigabe an.' }
        $existing = $null; try { $existing = $mappings.Item($port,'TCP') } catch {}
        if ($mode -eq 'Query') { return [pscustomobject]@{ Available=$true; Occupied=($null -ne $existing) } }
        if ($mode -eq 'Remove') {
            if ($existing -and $existing.Description -eq $owner -and $existing.InternalClient -eq $client -and $existing.InternalPort -eq $port) { $mappings.Remove($port,'TCP') }
            return
        }
        if ($existing) { throw "TCP-Port $port ist im Router bereits vergeben. Bitte einen anderen Internetport wählen." }
        $mapping = $mappings.Add($port,'TCP',$port,$client,$true,$owner)
        [pscustomobject]@{ Address=$mapping.ExternalIPAddress; Port=$port; Client=$client; Owner=$owner }
    }
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(18)
        while ($job.State -in 'NotStarted','Running') {
            if ([DateTime]::UtcNow -ge $deadline) { throw 'Der Router antwortet nicht rechtzeitig auf UPnP. IPv6 oder eine manuelle TCP-Freigabe verwenden.' }
            & $Tick | Out-Null
            Start-Sleep -Milliseconds 100
        }
        try { $result = Receive-Job $job -ErrorAction Stop }
        catch {
            if ($Mode -eq 'Add') { throw "Die automatische TCP-Freigabe ist fehlgeschlagen. IPv6 verwenden oder im Router TCP $Port für diesen PC freigeben. Manche Router verlangen 'selbstständige Portfreigaben zulassen'; auch der Windows-UPnP-Dienst kann die Anfrage verhindern. ($($_.Exception.Message))" }
            throw
        }
        if ($job.State -eq 'Failed') { throw $job.ChildJobs[0].JobStateInfo.Reason }
        return $result
    } finally { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
}

function Get-InternetFirewallArguments([int]$Port, [string]$Program) {
    if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Ungültiger Internetport.' }
    if (-not [IO.Path]::IsPathRooted($Program) -or -not (Test-Path -LiteralPath $Program -PathType Leaf)) { throw 'Launcher-Prozess nicht gefunden.' }
    # One inbound TCP rule for the TLS listener, never an unrestricted UDP rule.
    return @{ Name="TF3MP-Internet-TLS-$Port"; DisplayName="TF3 Multiplayer Internet (TLS TCP $Port)"; Direction='Inbound'; Action='Allow'; Protocol='TCP'; LocalPort=$Port; Program=$Program; Profile='Any'; EdgeTraversalPolicy='Block' }
}

function Enable-InternetFirewall([int]$Port) {
    $program = (Get-Process -Id $PID).Path
    [void](Get-InternetFirewallArguments $Port $program)
    $helper = Join-Path $PSScriptRoot 'internet-firewall.ps1'
    # Administrator UAC is Windows' approval for this one explicitly clicked rule.
    $proc = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$helper`"",'-Port',"$Port",'-Program',"`"$program`"")
    while (-not $proc.WaitForExit(100)) { [Windows.Forms.Application]::DoEvents() }
    if ($proc.ExitCode -ne 0) { throw 'Windows hat die Firewallregel nicht eingerichtet. Administratorfreigabe oder vorhandene Regeln prüfen.' }
}

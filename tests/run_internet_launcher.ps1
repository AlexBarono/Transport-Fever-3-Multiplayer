$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\launcher\launcher.ps1') -LibraryOnly
$passed=0
function Check($ok,$message){if(-not $ok){throw $message}; $script:passed++}
function Get-NetIPAddress {
    @(
        [pscustomobject]@{IPAddress='2001:db8::2'; AddressState='Preferred'; InterfaceAlias='Ethernet'; SuffixOrigin='Random'; SkipAsSource=$false; InterfaceMetric=1},
        [pscustomobject]@{IPAddress='2001:db8::1'; AddressState='Preferred'; InterfaceAlias='Ethernet'; SuffixOrigin='Link'; SkipAsSource=$false; InterfaceMetric=2},
        [pscustomobject]@{IPAddress='2001:db8::3'; AddressState='Preferred'; InterfaceAlias='Radmin VPN'; SuffixOrigin='Link'; SkipAsSource=$false; InterfaceMetric=0}
    )
}
$addresses=@(Get-InternetIPv6Addresses)
Check ($addresses.Count -eq 2) 'VPN address offered for direct Internet'
Check ($addresses[0].Address -eq '2001:db8::1' -and $addresses[0].Display -like '*dauerhaft*') 'Temporary privacy address selected before stable router target'
Check ($addresses[1].Display -like '*temporär*') 'Temporary IPv6 not identified'
$script:internetTunnel=[pscustomobject]@{Running=$true;Port=47801}
$script:internetRole='host'; $script:internetLocalPort=47800; $script:internetInvite='fixture invitation'
Check (Test-ReuseInternetHost 47801 47800) 'Reopening the same host rotates the invitation'
Check (-not (Test-ReuseInternetHost 47805 47800)) 'Changed public port incorrectly reused'
Check (-not (Test-ReuseInternetHost 47801 47900)) 'Changed local port incorrectly reused'
$script:internetRole='client'
Check (-not (Test-ReuseInternetHost 47801 47800)) 'Client listener reused as a host'
$script:internetRole='host'; $script:internetTunnel.Running=$false
Check (-not (Test-ReuseInternetHost 47801 47800)) 'Stopped listener reused'
Write-Output "$passed Internet launcher checks passed. No firewall/router mutations."

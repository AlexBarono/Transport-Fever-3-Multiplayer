param([switch]$CheckLocalAddresses,[switch]$CheckRouter)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\internet.ps1')
$passed=0
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
function Test-RoutingFixture {
    function Get-NetIPAddress($IPAddress,$AddressFamily,$InterfaceIndex){
        @(
            [pscustomobject]@{IPAddress='2001:db8::1';AddressFamily='IPv6';InterfaceIndex=7;SuffixOrigin='Link';AddressState=$script:fixtureState},
            [pscustomobject]@{IPAddress='2001:db8::2';AddressFamily='IPv6';InterfaceIndex=7;SuffixOrigin='Random';AddressState='Preferred'},
            [pscustomobject]@{IPAddress='192.168.7.2';AddressFamily='IPv4';InterfaceIndex=7;AddressState='Preferred'},
            [pscustomobject]@{IPAddress='192.168.9.2';AddressFamily='IPv4';InterfaceIndex=9;AddressState='Preferred'}
        )|Where-Object{(-not $IPAddress -or $_.IPAddress -eq $IPAddress) -and (-not $AddressFamily -or $_.AddressFamily -eq $AddressFamily) -and (-not $InterfaceIndex -or $_.InterfaceIndex -eq $InterfaceIndex)}
    }
    function Get-NetRoute($InterfaceIndex,$DestinationPrefix){
        if($DestinationPrefix -eq '::/0'){
            return [pscustomobject]@{InterfaceIndex=7;NextHop='fe80::1';RouteMetric=256;InterfaceAlias='Ethernet'}
        }
        @(
            [pscustomobject]@{InterfaceIndex=9;NextHop='192.168.9.1';RouteMetric=1;InterfaceAlias='Wi-Fi'},
            [pscustomobject]@{InterfaceIndex=7;NextHop='192.168.7.1';RouteMetric=50;InterfaceAlias='Ethernet'}
        )|Where-Object{-not $InterfaceIndex -or $_.InterfaceIndex -eq $InterfaceIndex}
    }
    $script:fixtureState='Preferred'
    Check ((Get-InternetLanIPv4) -eq '192.168.9.2') 'Fixture does not reproduce a different IPv4 default adapter'
    foreach($address in @('2001:db8::1','2001:db8::2')){
        $context=Get-InternetIPv6RouterContext $address
        Check ($context.Lan -eq '192.168.7.2' -and $context.Gateway -eq '192.168.7.1' -and $context.InterfaceIndex -eq 7) 'IPv6 router discovery used another adapter'
        Check ($context.Kind -eq $(if($address.EndsWith('1')){'permanent'}else{'temporary'})) 'Selected IPv6 kind incorrect'
        Check ($context.GatewayIPv6 -eq 'fe80::1%7') 'IPv6 router address lacks the selected adapter scope'
    }
    $script:fixtureState='Deprecated';$failed=$false
    try{Get-InternetIPv6RouterContext '2001:db8::1'|Out-Null}catch{$failed=$true}
    Check $failed 'Deprecated permanent address accepted'
    $failed=$false
    try{Get-InternetIPv6RouterContext '2001:db8::99'|Out-Null}catch{$failed=$true}
    Check $failed 'Missing address silently uses another interface'
    function Get-NetRoute { @() }
    $failed=$false
    try{Get-InternetIPv6RouterContext '2001:db8::2'|Out-Null}catch{$failed=$true}
    Check $failed 'Missing adapter router was ignored'
}
Test-RoutingFixture
if($CheckLocalAddresses -or $CheckRouter){
    Initialize-InternetTransport
    $addresses=@(Get-InternetIPv6Addresses)
    Check ($addresses.Count -gt 0) 'No preferred public IPv6 available for local probes'
    $tunnel=[TF3MP.Internet.Tunnel]::StartHost(0,47800)
    try{
        foreach($address in $addresses){
            $context=Get-InternetIPv6RouterContext $address.Address
            $lease=$null
            try{
                if($CheckRouter){
                    $control=[TF3MP.Internet.RouterLease]::Discover($context.Lan,$context.Gateway)
                    $lease=[TF3MP.Internet.RouterLease]::OpenSelected($control,$context.Gateway,$context.GatewayIPv6,$address.Address,$tunnel.Port,5)
                    Check ($lease.Active -or $lease.FirewallDisabled) ('Router did not confirm '+$context.Kind+' IPv6')
                    Write-Output ("Router IPv6: {0}, confirmed, firewall disabled={1}, control over IPv6={2}." -f $context.Kind,$lease.FirewallDisabled,$lease.ControlViaIPv6)
                    if(-not $lease.FirewallDisabled){
                        Start-Sleep -Milliseconds 2600
                        Check ($lease.Renewals -ge 1 -and -not $lease.LastError) ('Router renewal failed for '+$context.Kind)
                        Write-Output ("Renewals: {0}, via AddPinhole={1}." -f $lease.Renewals,$lease.RenewalViaAdd)
                    }
                }
                [TF3MP.Internet.Tunnel]::Probe($address.Address,$tunnel.Port,$tunnel.Fingerprint,$tunnel.Key)
                Check $true ('Local TLS failed for '+$context.Kind)
                Write-Output ("Local IPv6 TLS: {0}, interface {1}, successful." -f $context.Kind,$context.InterfaceIndex)
            }finally{
                if($lease){
                    $lease.Dispose();Check (-not $lease.LastError) 'Test router pinhole cleanup failed'
                    Write-Output ("Router cleanup confirmed; expires in {0} seconds (0=deleted)." -f $lease.CloseExpiresInSeconds)
                }
            }
        }
    }finally{$tunnel.Dispose()}
}
Write-Output "$passed IPv6 checks passed. No Windows firewall changes. Router test leases, if requested, were closed. Local probes do not establish external reachability."

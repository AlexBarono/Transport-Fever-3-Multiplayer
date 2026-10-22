param([switch]$CheckRouter)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\internet.ps1')
Initialize-InternetTransport
Add-Type -Path (Join-Path $PSScriptRoot 'router_fixture.cs') -ReferencedAssemblies 'System.dll','System.Core.dll','System.Xml.dll'
$passed=0
function Check($value,$why) { if(-not $value) { throw $why }; $script:passed++ }
foreach($url in @('http://192.168.1.2:49000/control','https://127.0.0.1/control','http://user@127.0.0.1/control','http://example.com/control')) {
    $failed=$false; try { [void][TF3MP.Internet.RouterLease]::ValidateUrl($url,'127.0.0.1') } catch { $failed=$true }; Check $failed 'Untrusted router URL accepted'
}
$router=[RouterFixture]::new(); $lease=$null
try {
    $lease=[TF3MP.Internet.RouterLease]::Open($router.Url,'127.0.0.1','2001:db8::5',47801,2)
    Check ($lease.Active -and $router.Adds -eq 1) 'Pinhole not created'
    [xml]$fields='<root>'+$router.AddedFields+'</root>'
    Check ($fields.root.InternalPort -eq '47801' -and $fields.root.Protocol -eq '6' -and $fields.root.InternalClient -eq '2001:db8::5' -and $fields.root.RemotePort -eq '0' -and $fields.root.LeaseTime -eq '2') 'Pinhole scope differs'
    Start-Sleep -Milliseconds 2400
    Check ($router.Updates -ge 2 -and $lease.Active -and $lease.Renewals -ge 2) 'Lease did not renew'
    $router.FailRenew=$true; Start-Sleep -Milliseconds 3000
    Check (-not $lease.Active -and $lease.LastError -eq '704') 'Expired pinhole was still reported as active'
    $lease.Dispose(); $lease.Dispose()
    Check ($router.Deletes -eq 1 -and $router.DeletedId -eq '42') 'Cleanup deleted another id or ran twice'
    $router.Deny=$true
    $failed=$false; try { [void][TF3MP.Internet.RouterLease]::Open($router.Url,'127.0.0.1','2001:db8::5',47801,2) } catch { $failed=$_.Exception.GetBaseException().Code -eq '703' }
    Check ($failed -and $router.Adds -eq 1) 'Router permission denial was ignored'
} finally { if($lease) { $lease.Dispose() }; $router.Dispose() }
$router=[RouterFixture]::new($true);$router.RequireSameSource=$true;$router.DenyUpdateDelete=$true;$lease=$null
try{
    $legacy=[Uri]('http://127.0.0.1:'+$router.Url.Port+'/control')
    $lease=[TF3MP.Internet.RouterLease]::OpenSelected($legacy,'127.0.0.1','::1','::1',47811,2)
    Check ($lease.ControlViaIPv6 -and $router.LastSource -eq '::1') 'Router control did not use the selected IPv6 as source'
    Start-Sleep -Milliseconds 1300
    Check ($lease.RenewalViaAdd -and $lease.Renewals -ge 1 -and -not $lease.LastError) 'IPv6 606 renewal did not extend the identical pinhole'
    Check ($router.Adds -ge 2 -and $router.LastLeaseTime -eq 2) 'Renewal changed the pinhole lease or scope'
    $lease.Dispose()
    Check (-not $lease.LastError -and $lease.CloseExpiresInSeconds -eq 1 -and $router.LastLeaseTime -eq 1) 'Denied IPv6/IPv4 deletion did not shorten its own pinhole'
}finally{if($lease){$lease.Dispose()};$router.Dispose()}
foreach($entry in @(@('http://[::1]:49000/control','::1'),@('http://[fe80::1%7]:49000/control','fe80::1%7'))){
    $validated=[TF3MP.Internet.RouterLease]::ValidateUrl($entry[0],$entry[1])
    Check (([Net.IPAddress]::Parse($validated.DnsSafeHost)).Equals([Net.IPAddress]::Parse($entry[1]))) 'IPv6 gateway scope not retained'
}
$failed=$false
try{[void][TF3MP.Internet.RouterLease]::ValidateUrl('http://[fe80::1%8]:49000/control','fe80::1%7')}catch{$failed=$true}
Check $failed 'Control URL accepted another IPv6 adapter scope'
$program=(Get-Process -Id $PID).Path
$hostArgs=Get-GameFirewallArguments 47800 $program host
$clientArgs=Get-GameFirewallArguments 47800 $program client
Check ($hostArgs.Protocol -eq 'UDP' -and $hostArgs.LocalPort -eq 47800 -and $hostArgs.Program -eq $program) 'Host UDP rule scope'
Check ($clientArgs.Protocol -eq 'UDP' -and $clientArgs.LocalPort -eq 'Any' -and $clientArgs.Program -eq $program) 'Client ephemeral UDP rule scope'
if($CheckRouter) {
    $lan=Get-InternetLanIPv4
    $index=(Get-NetIPAddress -IPAddress $lan -AddressFamily IPv4).InterfaceIndex
    $gateway=(Get-NetRoute -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    $address=(Get-InternetIPv6Addresses | Select-Object -First 1).Address
    $tunnel=[TF3MP.Internet.Tunnel]::StartHost(47811,47810); $actual=$null
    try {
        $control=[TF3MP.Internet.RouterLease]::Discover($lan,$gateway)
        $actual=[TF3MP.Internet.RouterLease]::Open($control,$gateway,$address,47811,60)
        Check ($actual.Active -and -not $actual.FirewallDisabled) 'Real router did not confirm test pinhole'
    } finally { if($actual) { $actual.Dispose(); Check (-not $actual.LastError) 'Real router cleanup failed' }; $tunnel.Dispose() }
}
"$passed router/firewall checks passed"

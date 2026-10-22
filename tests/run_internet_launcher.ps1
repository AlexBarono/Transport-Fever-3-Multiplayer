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
Check ($addresses[0].Address -eq '2001:db8::2' -and $addresses[0].Display -like '*temporär*') 'Temporary IPv6 is not the default address'
Check ($addresses[1].Display -like '*dauerhaft*') 'Permanent IPv6 fallback not retained'
function Test-SavedEndpoint {
    $script:endpointFixture=Join-Path $env:TEMP ('tf3mp-endpoint-'+[guid]::NewGuid().ToString('N')+'\endpoint.json')
    function Get-InternetHostStatePath {return $script:endpointFixture}
    function Write-InternetLog {}
    try{
        Check (-not (Get-SavedInternetHostEndpoint)) 'Missing endpoint returned a profile'
        Save-InternetHostEndpoint $addresses[1].Address 47901
        $saved=Get-SavedInternetHostEndpoint
        Check ($saved.Address -eq $addresses[1].Address -and $saved.Port -eq 47901) 'Endpoint did not persist'
        $script:connectionMode=[pscustomobject]@{SelectedIndex=0}
        $script:hostAddress=[pscustomobject]@{Items=$addresses;SelectedItem=$addresses[0]}
        $script:internetPortBox=[pscustomobject]@{Text='47801'}
        $script:connectionStatus=[pscustomobject]@{Text=''}
        Restore-LauncherInternetHostEndpoint
        Check ($hostAddress.SelectedItem.Address -eq $addresses[1].Address -and $internetPortBox.Text -eq '47901') 'Saved permanent IPv6/port not restored over temporary default'
        Save-InternetHostEndpoint '2001:db8::99' 47902
        $hostAddress.SelectedItem=$addresses[0];$internetPortBox.Text='47801'
        Restore-LauncherInternetHostEndpoint
        Check ($hostAddress.SelectedItem.Address -eq $addresses[0].Address -and $internetPortBox.Text -eq '47801') 'Disappeared address replaced the valid temporary default'
        Check ($connectionStatus.Text -like '*nicht mehr verfügbar*') 'Address rotation has no visible explanation'
        Save-InternetHostEndpoint $addresses[1].Address 47901
        $connectionMode.SelectedIndex=1
        Restore-LauncherInternetHostEndpoint
        Check ($hostAddress.SelectedItem.Address -eq $addresses[0].Address) 'Internet profile overrides VPN mode'
        foreach($bad in @('{bad','{"Version":2,"Address":"2001:db8::1","Port":47801}','{"Version":1,"Address":"2001:db8::1","Port":1}')){
            Set-Content -LiteralPath $script:endpointFixture -Value $bad -Encoding UTF8
            Check (-not (Get-SavedInternetHostEndpoint)) 'Invalid endpoint profile accepted'
        }
    }finally{
        $folder=[IO.Path]::GetFullPath((Split-Path -Parent $script:endpointFixture))
        if($folder.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
            Remove-Item -LiteralPath $folder -Recurse -Force
        }
    }
}
Test-SavedEndpoint
$script:internetTunnel=[pscustomobject]@{Running=$true;Port=47801}
$script:internetRole='host'; $script:internetLocalPort=47800; $script:internetInvite='fixture invitation'
Check (Test-ReuseInternetHost 47801 47800) 'Reopening the same host rotates the invitation'
Check (-not (Test-ReuseInternetHost 47805 47800)) 'Changed public port incorrectly reused'
Check (-not (Test-ReuseInternetHost 47801 47900)) 'Changed local port incorrectly reused'
$script:internetRole='client'
Check (-not (Test-ReuseInternetHost 47801 47800)) 'Client listener reused as a host'
$script:internetRole='host'; $script:internetTunnel.Running=$false
Check (-not (Test-ReuseInternetHost 47801 47800)) 'Stopped listener reused'
function Test-GameRunning { return $script:autoGameRunning }
function Reset-AutoFixture {
    $script:Preview=$false; $script:launcherClosing=$false; $script:autoGameRunning=$false; $script:autoFail=$false
    $script:autoStarts=0; $script:internetTunnel=$null; $script:internetRole=''
    $script:internetAutoKey=''; $script:internetAutoAttempt=''
    $script:transferBusy=$false; $script:liveBusy=$false; $script:lobbyPreparing=$false
    $script:lobbyPhase='idle'; $script:lobby=$null; $script:presence=$null; $script:lobbyJob=$null
    $script:hostRadio=[pscustomobject]@{Checked=$true}
    $script:connectionMode=[pscustomobject]@{SelectedIndex=0}
    $script:hostAddress=[pscustomobject]@{SelectedItem=$addresses[0];Text=$addresses[0].Address}
    $script:internetPortBox=[pscustomobject]@{Text='47801'}
    $script:portBox=[pscustomobject]@{Text='47800'}
}
function Start-LauncherInternetHost {
    $script:autoStarts++; $script:lobbyPreparing=$true
    try {
        # Real setup clears the automatic bookkeeping when stopping an old tunnel.
        $script:internetAutoKey=''; $script:internetAutoAttempt=''
        Update-AutomaticInternetHost
        if(-not $script:autoFail){
            $script:internetTunnel=[pscustomobject]@{Running=$true;Port=[int]$internetPortBox.Text}
            $script:internetRole='host'
        }
    } finally {$script:lobbyPreparing=$false}
}
function Advance-AutoStart {
    Update-AutomaticInternetHost
    $script:internetAutoChanged=[DateTime]::UtcNow.AddSeconds(-2)
    Update-AutomaticInternetHost
}
Reset-AutoFixture
Update-AutomaticInternetHost
Check ($script:autoStarts -eq 0) 'Automatic host ignores address/port debounce'
$script:internetAutoChanged=[DateTime]::UtcNow.AddSeconds(-2)
Update-AutomaticInternetHost
Check ($script:autoStarts -eq 1 -and $script:internetRole -eq 'host') 'Selected Internet host did not open automatically'
1..5 | ForEach-Object {Update-AutomaticInternetHost}
Check ($script:autoStarts -eq 1) 'Timer recreated an active Internet connection'
Reset-AutoFixture; $script:autoFail=$true; Advance-AutoStart
1..5 | ForEach-Object {Update-AutomaticInternetHost}
Check ($script:autoStarts -eq 1) 'Failed setup repeatedly prompts or retries from the timer'
Update-AutomaticInternetHost -Retry
Check ($script:autoStarts -eq 2) 'Explicit retry does not retry failed setup'
$internetPortBox.Text='47802'; Advance-AutoStart
Check ($script:autoStarts -eq 3) 'Changed public port did not allow a new attempt'
$hostAddress.SelectedItem=$addresses[1]; Advance-AutoStart
Check ($script:autoStarts -eq 4) 'Changed IPv6 address did not allow a new attempt'
foreach($blocked in @('preview','closing','join','vpn','game','transfer','preparing','started','presence','lobby','job','noaddress')){
    Reset-AutoFixture
    switch($blocked){
        preview {$script:Preview=$true}
        closing {$script:launcherClosing=$true}
        join {$hostRadio.Checked=$false}
        vpn {$connectionMode.SelectedIndex=1}
        game {$script:autoGameRunning=$true}
        transfer {$script:transferBusy=$true}
        preparing {$script:lobbyPreparing=$true}
        started {$script:lobbyPhase='started'}
        presence {$script:presence=[pscustomobject]@{Connected=$false}}
        lobby {$script:lobby=[pscustomobject]@{Connected=$true}}
        job {$script:lobbyJob=[pscustomobject]@{Waiting=$true}}
        noaddress {$hostAddress.SelectedItem=$null; $hostAddress.Text=''}
    }
    Advance-AutoStart
    Check ($script:autoStarts -eq 0) "Automatic Internet setup ran during $blocked"
}
Reset-AutoFixture; $script:autoFail=$true; Advance-AutoStart
Stop-LauncherInternet
Advance-AutoStart
Check ($script:autoStarts -eq 2) 'Reentering Internet mode cannot start after a previous failed session'
Write-Output "$passed Internet launcher checks passed. No firewall/router mutations."

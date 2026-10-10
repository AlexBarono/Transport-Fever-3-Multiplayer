param([int]$HostPort,[string]$ReadyFile,[string]$StopFile)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\internet.ps1')
Initialize-InternetTransport
$reservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$HostPort); $reservation.Start()
$hostTunnel=$null; $clientTunnel=$null
try {
    $hostTunnel=[TF3MP.Internet.Tunnel]::StartHost(0,$HostPort)
    $pick=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $pick.Start(); $port=$pick.LocalEndpoint.Port; $pick.Stop()
    $clientTunnel=[TF3MP.Internet.Tunnel]::StartClient('::1',$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$port)
    $reservation.Stop()
    [IO.File]::WriteAllText($ReadyFile,"$port")
    while(-not (Test-Path -LiteralPath $StopFile)) { Start-Sleep -Milliseconds 100 }
} finally { $reservation.Stop(); if($clientTunnel){$clientTunnel.Dispose()}; if($hostTunnel){$hostTunnel.Dispose()} }

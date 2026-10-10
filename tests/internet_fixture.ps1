param([int]$HostPort,[string]$ReadyFile,[string]$StopFile)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\internet.ps1')
Initialize-InternetTransport
$reservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$HostPort); $reservation.Start()
$hostTunnel=$null; $clientTunnel=$null
try {
    $hostTunnel=[TF3MP.Internet.Tunnel]::StartHost(0,$HostPort)
    # The tunnel binds TCP and UDP on the same port. A free ephemeral TCP
    # port can be reserved/occupied for UDP on Windows (WSAEACCES 10013).
    $port=0
    for($attempt=0;$attempt -lt 20 -and $port -eq 0;$attempt++){
        $pick=$null; $pickUdp=$null
        try {
            $pickUdp=New-Object Net.Sockets.UdpClient([Net.Sockets.AddressFamily]::InterNetwork)
            $pickUdp.Client.ExclusiveAddressUse=$true
            $pickUdp.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,0)))
            $candidate=([Net.IPEndPoint]$pickUdp.Client.LocalEndPoint).Port
            $pick=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$candidate); $pick.Start()
            $port=$candidate
        } catch [Net.Sockets.SocketException] {
            if($attempt -eq 19){throw}
        } finally {if($pick){$pick.Stop()}; if($pickUdp){$pickUdp.Close()}}
    }
    $clientTunnel=[TF3MP.Internet.Tunnel]::StartClient('::1',$hostTunnel.Port,$hostTunnel.Fingerprint,$hostTunnel.Key,$port)
    $reservation.Stop()
    [IO.File]::WriteAllText($ReadyFile,"$port")
    while(-not (Test-Path -LiteralPath $StopFile)) { Start-Sleep -Milliseconds 100 }
} finally { $reservation.Stop(); if($clientTunnel){$clientTunnel.Dispose()}; if($hostTunnel){$hostTunnel.Dispose()} }

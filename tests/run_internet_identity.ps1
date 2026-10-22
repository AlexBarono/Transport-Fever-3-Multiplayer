param([string]$WorkerDirectory='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\internet.ps1')
Initialize-InternetTransport
function Invitation-Hash($tunnel){
    $text=New-InternetInvitation '::1' $tunnel.Port $tunnel.Fingerprint $tunnel.Key
    return [TF3MP.Internet.Tunnel]::Hash([Text.Encoding]::UTF8.GetBytes($text))
}
if($WorkerDirectory){
    $expected=Get-Content -LiteralPath (Join-Path $WorkerDirectory 'expected.json') -Raw | ConvertFrom-Json
    $tunnel=[TF3MP.Internet.Tunnel]::StartHost($expected.Port,47800,(Join-Path $WorkerDirectory 'identity.dat'))
    try {
        if(-not $tunnel.IdentityReused -or (Invitation-Hash $tunnel) -ne $expected.Hash){throw 'Invitation changed in a new process'}
        [TF3MP.Internet.Tunnel]::Probe('::1',$tunnel.Port,$tunnel.Fingerprint,$tunnel.Key)
        [IO.File]::WriteAllText((Join-Path $WorkerDirectory 'worker-ok.txt'),'ok')
    }finally{$tunnel.Dispose()}
    exit
}
$passed=0
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
$testDirectory=Join-Path $env:TEMP ('tf3mp-identity-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testDirectory)
$identity=Join-Path $testDirectory 'identity.dat'
$tunnel=$null; $worker=$null
try {
    $tunnel=[TF3MP.Internet.Tunnel]::StartHost(0,47800,$identity)
    Check (-not $tunnel.IdentityReused -and (Test-Path -LiteralPath $identity)) 'First host identity not stored'
    $port=$tunnel.Port; $pin=$tunnel.Fingerprint; $key=$tunnel.Key; $hash=Invitation-Hash $tunnel
    $stored=[IO.File]::ReadAllBytes($identity)
    Check (-not [Text.Encoding]::UTF8.GetString($stored).Contains($key)) 'Host key stored as plaintext'
    $clear=[Security.Cryptography.ProtectedData]::Unprotect($stored,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try{
        $reader=[IO.BinaryReader]::new([IO.MemoryStream]::new($clear))
        Check ($reader.ReadInt32() -eq 1 -and $reader.ReadString() -eq $key) 'Current user cannot decrypt the protected identity'
    }finally{if($reader){$reader.Dispose()};[Array]::Clear($clear,0,$clear.Length)}
    [TF3MP.Internet.Tunnel]::Probe('::1',$port,$pin,$key);$passed++
    $tunnel.Dispose();$tunnel=$null
    $tunnel=[TF3MP.Internet.Tunnel]::StartHost($port,47800,$identity)
    Check ($tunnel.IdentityReused -and $tunnel.Fingerprint -eq $pin -and $tunnel.Key -eq $key) 'Identity changed after restart'
    Check ((Invitation-Hash $tunnel) -eq $hash) 'Full invitation changed after restart'
    [TF3MP.Internet.Tunnel]::Probe('::1',$port,$pin,$key);$passed++
    Check ([TF3MP.Internet.Tunnel]::Hash([IO.File]::ReadAllBytes($identity)) -eq [TF3MP.Internet.Tunnel]::Hash($stored)) 'Reading identity rewrote it'
    $tunnel.Dispose();$tunnel=$null
    @{Port=$port;Hash=$hash}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $testDirectory 'expected.json') -Encoding UTF8
    $worker=Start-Process (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-WorkerDirectory',('"'+$testDirectory+'"'))
    Check ($worker.WaitForExit(20000) -and $worker.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $testDirectory 'worker-ok.txt'))) 'New-process restart/TLS probe failed'
    # Never silently rotate a damaged identity and invalidate every shared link.
    [IO.File]::WriteAllBytes($identity,[byte[]](1..64))
    $failed=$false
    try{$tunnel=[TF3MP.Internet.Tunnel]::StartHost(0,47800,$identity)}catch{$failed=$true}
    Check $failed 'Corrupted identity silently replaced'
    Check ([TF3MP.Internet.Tunnel]::Hash([IO.File]::ReadAllBytes($identity)) -eq [TF3MP.Internet.Tunnel]::Hash([byte[]](1..64))) 'Corrupted identity was overwritten'
    Check (@(Get-ChildItem -LiteralPath $testDirectory -Filter '*.new-*').Count -eq 0) 'Identity temporary files left behind'
    Write-Output "$passed persistent invitation checks passed, including a separate process and real IPv6 TLS. No firewall/router changes."
}finally{
    if($tunnel){$tunnel.Dispose()}
    if($worker -and -not $worker.HasExited){$worker.Kill();$worker.WaitForExit()}
    $resolved=[IO.Path]::GetFullPath($testDirectory)
    if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

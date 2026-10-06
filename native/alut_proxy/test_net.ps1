# Local test of the UDP peer link without the game: loads build\alut.dll in two
# separate PowerShell processes (host and client on 127.0.0.1) for a few
# seconds and prints both logs.
param([int]$Seconds = 12, [int]$Port = 47800)
$ErrorActionPreference = 'Stop'

$dll = Join-Path $PSScriptRoot 'build\alut.dll'
$work = Join-Path $PSScriptRoot 'build\nettest'
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

$loader = @'
param($Path, $Seconds)
Add-Type -Name K -Namespace T -MemberDefinition '[DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryW(string p);'
if ([T.K]::LoadLibraryW($Path) -eq [IntPtr]::Zero) { throw "LoadLibrary failed" }
Start-Sleep -Seconds $Seconds
# Exit without FreeLibrary, like the game does at shutdown.
'@

$procs = foreach ($role in 'host', 'client') {
	$dir = Join-Path $work $role
	New-Item -ItemType Directory -Force $dir | Out-Null
	Copy-Item $dll $dir
	Set-Content -Encoding ASCII (Join-Path $dir 'alut_proxy.ini') "[net]`r`nmode=$role`r`nport=$Port`r`nhost=127.0.0.1"
	Set-Content -Encoding ASCII (Join-Path $dir 'load.ps1') $loader
	Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dir 'load.ps1'), (Join-Path $dir 'alut.dll'), $Seconds
}
$procs | Wait-Process
foreach ($role in 'host', 'client') {
	"--- $role"
	Get-Content (Join-Path $work "$role\alut_proxy.log")
}

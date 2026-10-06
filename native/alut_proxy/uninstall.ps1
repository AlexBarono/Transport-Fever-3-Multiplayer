# Removes the proxy and restores the original alut.dll.
# Alternative: Steam > Transport Fever 3 > Properties > Installed Files > Verify integrity.
param(
	[string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3'
)
$ErrorActionPreference = 'Stop'

if (Get-Process -Name 'TransportFever3' -ErrorAction SilentlyContinue) {
	throw 'Transport Fever 3 is running. Close it first.'
}
$dll = Join-Path $GameDir 'alut.dll'
$orig = Join-Path $GameDir 'alut_orig.dll'
if (-not (Test-Path $orig)) { throw "No alut_orig.dll found, nothing to restore." }

Move-Item $orig $dll -Force
Write-Output "Restored original alut.dll"

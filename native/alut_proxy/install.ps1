# Installs build\alut.dll as proxy into the TF3 folder.
# The original alut.dll is kept as alut_orig.dll (the proxy forwards to it).
param(
	[string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3'
)
$ErrorActionPreference = 'Stop'

if (Get-Process -Name 'TransportFever3' -ErrorAction SilentlyContinue) {
	throw 'Transport Fever 3 is running. Close it first.'
}
$proxy = Join-Path $PSScriptRoot 'build\alut.dll'
if (-not (Test-Path $proxy)) { throw "Proxy not built: $proxy (run build.bat)" }

$dll = Join-Path $GameDir 'alut.dll'
$orig = Join-Path $GameDir 'alut_orig.dll'

if (-not (Test-Path $orig)) {
	# First install: the current alut.dll must be the signed original.
	$sig = Get-AuthenticodeSignature $dll
	if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Urban Games') {
		throw "alut.dll in the game folder is not the signed original, refusing to rename it."
	}
	Move-Item $dll $orig
}
Copy-Item $proxy $dll -Force
Write-Output "Installed proxy: $dll -> forwards to $orig"

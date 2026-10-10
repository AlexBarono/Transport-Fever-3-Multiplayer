# Builds the portable Windows package without installing, publishing or touching game files.
# Run from any directory: powershell -NoProfile -File tools/package.ps1 [-Force]
[CmdletBinding()]
param(
	[string]$OutputPath = '',
	[switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packagePrefix = $packageRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar

function Assert-PackageNotLinked($Item) {
	# OneDrive marks ordinary pinned files as ReparsePoint too. Actual filesystem links
	# have a LinkType or Target; cloud placeholders retain their normal project path.
	$linkType = $Item.PSObject.Properties['LinkType']
	$linkTarget = $Item.PSObject.Properties['Target']
	if (($linkType -and $linkType.Value) -or ($linkTarget -and $linkTarget.Value)) { throw "Linked source is not packaged: $($Item.FullName)" }
}

function Get-PackageSource([string]$RelativePath) {
	$path = [IO.Path]::GetFullPath((Join-Path $packageRoot $RelativePath))
	if (-not $path.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Source escapes the project: $RelativePath" }
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required package file missing: $RelativePath" }
	$item = Get-Item -LiteralPath $path -Force
	Assert-PackageNotLinked $item
	$parent = $item.Directory
	while ($parent -and $parent.FullName.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
		Assert-PackageNotLinked (Get-Item -LiteralPath $parent.FullName -Force)
		$parent = $parent.Parent
	}
	return $path
}

function Get-PackageHash([string]$Path) {
	return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$mainPath = Get-PackageSource 'mods/mp_probe/content/mp_probe/main.script.lua'
$mainText = [IO.File]::ReadAllText($mainPath)
$probeMatch = [regex]::Match($mainText, '(?m)^\s*main\.PROBE_VERSION\s*=\s*(\d+)\b')
if (-not $probeMatch.Success) { throw 'The probe version could not be read.' }
$probeVersion = $probeMatch.Groups[1].Value
$bridgeText = [IO.File]::ReadAllText((Get-PackageSource 'native/alut_proxy/proxy.h'))
$bridgeMatch = [regex]::Match($bridgeText, '(?m)^\s*#define\s+PROXY_VERSION\s+"(\d+)"')
if (-not $bridgeMatch.Success) { throw 'The bridge version could not be read.' }
$bridgeVersion = $bridgeMatch.Groups[1].Value

$bundledProxy = Get-PackageSource 'launcher/bin/alut.dll'
$builtProxy = Get-PackageSource 'native/alut_proxy/build/alut.dll'
$proxyHash = Get-PackageHash $bundledProxy
if ($proxyHash -cne (Get-PackageHash $builtProxy)) { throw 'The launcher DLL differs from the native build. Build and copy the current DLL before packaging.' }
$metadata = [IO.File]::ReadAllText((Get-PackageSource 'mods/mp_probe/_metadata/modinfo.json')) | ConvertFrom-Json
$descriptionVersion = 'Probe v' + [regex]::Escape($probeVersion) + '\s*/\s*bridge v' + [regex]::Escape($bridgeVersion) + '\b'
if ([string]$metadata.description -notmatch $descriptionVersion) { throw 'Mod metadata and source versions do not match.' }
$view = [IO.File]::ReadAllText((Get-PackageSource 'launcher/view.ps1'))
if ($view -notmatch ('Probe v' + [regex]::Escape($probeVersion) + '\s*/\s*Bridge v' + [regex]::Escape($bridgeVersion) + '\b')) { throw 'The launcher version label does not match the source.' }
$readme = [IO.File]::ReadAllText((Get-PackageSource 'README.md'))
if ($readme -notmatch ('Aktueller Stand:\s+\*\*Probe v' + [regex]::Escape($probeVersion) + '\s*/\s*DLL v' + [regex]::Escape($bridgeVersion) + '\*\*')) { throw 'README current-version label does not match the source.' }

$manifest = [IO.File]::ReadAllText((Get-PackageSource 'mods/mp_probe/_content.json')) | ConvertFrom-Json
foreach ($file in $manifest.files) {
	if ([IO.Path]::IsPathRooted($file) -or $file -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid mod manifest path: $file" }
	Get-PackageSource ('mods/mp_probe/content/' + $file) | Out-Null
}

# Explicit allowlist: only the launcher, mod, PowerShell helpers, user docs and saved test capture.
$sources = @{}
function Add-PackageFile([string]$Path) {
	$full = [IO.Path]::GetFullPath($Path)
	if (-not $full.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Source escapes the project: $full" }
	$relative = $full.Substring($packagePrefix.Length).Replace('\', '/')
	$sources[$relative] = Get-PackageSource $relative
}
foreach ($file in 'Start.bat', 'Test-letzte-Aufnahme.bat', 'README.md', 'launcher/bin/alut.dll', 'logs/run29-stdout.txt') {
	Add-PackageFile (Get-PackageSource $file)
}
foreach ($pattern in @(
	@{ Directory = 'launcher'; Filter = '*.ps1' },
	@{ Directory = 'tools'; Filter = '*.ps1' },
	@{ Directory = 'tools'; Filter = '*.cs' },
	@{ Directory = 'tools'; Filter = 'game-autoload.lua' },
	@{ Directory = 'docs'; Filter = '*.md' }
)) {
	foreach ($file in Get-ChildItem -LiteralPath (Join-Path $packageRoot $pattern.Directory) -File -Filter $pattern.Filter -Force) {
		Add-PackageFile $file.FullName
	}
}
$modRoot = Join-Path $packageRoot 'mods/mp_probe'
Assert-PackageNotLinked (Get-Item -LiteralPath $modRoot -Force)
foreach ($item in Get-ChildItem -LiteralPath $modRoot -Recurse -Force) {
	Assert-PackageNotLinked $item
	if (-not $item.PSIsContainer) { Add-PackageFile $item.FullName }
}
$names = [string[]]@($sources.Keys)
[Array]::Sort($names, [StringComparer]::Ordinal)

if (-not $OutputPath) { $OutputPath = Join-Path $packageRoot "release/TF3-Multiplayer-v$probeVersion-Windows.zip" }
$target = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($target) -ine '.zip') { throw 'The output must be a .zip file.' }
if (Test-Path -LiteralPath $target) {
	if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'The output path is not a file.' }
	Assert-PackageNotLinked (Get-Item -LiteralPath $target -Force)
	if (-not $Force) { throw "The package already exists. Use -Force to replace it: $target" }
}
# Prevent an output file inside any packaged source tree from becoming its own future input.
foreach ($sourceTree in 'mods/mp_probe', 'launcher', 'tools', 'docs', 'logs') {
	$sourcePrefix = [IO.Path]::GetFullPath((Join-Path $packageRoot $sourceTree)).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
	if ($target.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'The output must be outside packaged source folders.' }
}
$targetDirectory = [IO.Path]::GetDirectoryName($target)
[IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
$temporary = $target + '.building-' + [Guid]::NewGuid().ToString('N')
$expected = @{}
try {
	$stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
	try {
		$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
		try {
			foreach ($name in $names) {
				$expected[$name] = Get-PackageHash $sources[$name]
				$entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
				$entry.LastWriteTime = [DateTimeOffset]'2020-01-01T00:00:00+00:00'
				$input = [IO.File]::Open($sources[$name], [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
				try {
					$output = $entry.Open()
					try { $input.CopyTo($output) } finally { $output.Dispose() }
				} finally { $input.Dispose() }
			}
		} finally { $archive.Dispose() }
	} finally { $stream.Dispose() }

	# Open the finished archive and verify its exact path set and every extracted byte stream.
	$stream = [IO.File]::OpenRead($temporary)
	try {
		$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
		try {
			if ($archive.Entries.Count -ne $names.Count) { throw 'Archive entry count differs from the allowlist.' }
			$seen = @{}
			foreach ($entry in $archive.Entries) {
				$name = $entry.FullName
				if (-not $expected.ContainsKey($name) -or $seen.ContainsKey($name) -or $name.Contains('\') -or $name.StartsWith('/')) { throw "Unexpected or duplicate archive entry: $name" }
				$seen[$name] = $true
				$sha = [Security.Cryptography.SHA256]::Create()
				$input = $entry.Open()
				try { $actual = ([BitConverter]::ToString($sha.ComputeHash($input))).Replace('-', '').ToLowerInvariant() }
				finally { $input.Dispose(); $sha.Dispose() }
				if ($actual -cne $expected[$name]) { throw "Archive content verification failed: $name" }
			}
		} finally { $archive.Dispose() }
	} finally { $stream.Dispose() }

	if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $temporary -Destination $target -Force }
	else { [IO.File]::Move($temporary, $target) }
	[pscustomobject]@{
		Path = $target
		ProbeVersion = $probeVersion
		BridgeVersion = $bridgeVersion
		FileCount = $names.Count
		Bytes = (Get-Item -LiteralPath $target).Length
		SHA256 = Get-PackageHash $target
		ProxySHA256 = $proxyHash
	}
} finally {
	# Only the uniquely named temporary file created by this invocation can be removed here.
	if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
}

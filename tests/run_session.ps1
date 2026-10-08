# Deterministische Sitzungsprüfung ohne Spielinstallation oder Netzwerk.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\session.ps1')
$passed = 0; $failed = 0
function Test($name, $fn) { try { & $fn; $script:passed++ } catch { $script:failed++; Write-Host "FAIL ${name}: $($_.Exception.Message)" } }
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Rejection($fn, $pattern) { $message = ''; try { & $fn | Out-Null } catch { $message = $_.Exception.Message }; Assert ($message -like $pattern) "expected $pattern, got $message" }
$base = Join-Path ([IO.Path]::GetTempPath()) ('tf3mp-session-test-' + [Guid]::NewGuid().ToString('N'))
$oldPublic = $env:PUBLIC; $oldLocalAppData = $env:LOCALAPPDATA
try {
	$env:PUBLIC = Join-Path $base 'public'; $env:LOCALAPPDATA = Join-Path $base 'appdata'
	foreach ($name in 'one', 'two') {
		$dir = Join-Path $base $name
		New-Item -ItemType Directory -Force (Join-Path $dir 'game'), (Join-Path $dir 'probe\content'), (Join-Path $dir 'local\save'), (Join-Path $dir 'local\staging_area\track_pack') | Out-Null
		[IO.File]::WriteAllText((Join-Path $dir 'game\TransportFever3.exe'), 'game build')
		[IO.File]::WriteAllText((Join-Path $dir 'proxy.dll'), 'network package')
		[IO.File]::WriteAllText((Join-Path $dir 'probe\content\main.lua'), 'return true')
		[IO.File]::WriteAllText((Join-Path $dir 'probe\mod.json'), '{"revision":1}')
		[IO.File]::WriteAllText((Join-Path $dir 'local\staging_area\track_pack\mod.json'), '{"track":1}')
		[IO.File]::WriteAllText((Join-Path $dir 'local\save\Bär am See.sav'), 'shared world')
	}
	function Manifest($name = 'one') {
		$dir = Join-Path $base $name
		return Get-SessionManifest -GameDir (Join-Path $dir 'game') -ModSource (Join-Path $dir 'probe') -ProxyDll (Join-Path $dir 'proxy.dll') -SaveDir (Join-Path $dir 'local\save')
	}
	$manifest = Manifest
	$save = Join-Path $base 'one\local\save\Bär am See.sav'
	$session = New-MultiplayerSession -Manifest $manifest -SavePath $save
	Test 'cloud reparse placeholders are allowed while filesystem links are rejected' {
		Assert (-not (Test-SessionLink ([pscustomobject]@{ Attributes = [IO.FileAttributes]::ReparsePoint; LinkType = ''; Target = @() }))) 'OneDrive placeholder is not a link'
		Assert (-not (Test-SessionLink ([pscustomobject]@{ Attributes = [IO.FileAttributes]::Normal; LinkType = $null; Target = $null }))) 'ordinary file'
		foreach ($type in 'Junction', 'SymbolicLink') {
			Assert (Test-SessionLink ([pscustomobject]@{ Attributes = [IO.FileAttributes]::ReparsePoint; LinkType = $type; Target = 'C:\elsewhere' })) "$type rejected"
		}
		Assert (Test-SessionLink ([pscustomobject]@{ LinkType = ''; Target = @('', 'C:\elsewhere') })) 'nonempty target alone rejects'
	}
	Test 'manifest ignores absolute paths and file timestamps' {
		(Get-Item (Join-Path $base 'two\probe\mod.json')).LastWriteTime = [DateTime]::Now.AddDays(-5)
		$other = Manifest 'two'
		foreach ($field in 'GameHash', 'PackageHash', 'ModsHash') { Assert ($manifest.$field -ceq $other.$field) $field }
		Assert ($manifest.ModCount -eq 1) 'one external mod'
	}
	Test 'all own package files and proxy bytes affect its hash' {
		$path = Join-Path $base 'two\probe\content\main.lua'; [IO.File]::AppendAllText($path, '\nchanged')
		Assert ((Manifest 'two').PackageHash -ne $manifest.PackageHash) 'Lua source must matter'
		[IO.File]::WriteAllText($path, 'return true')
		$path = Join-Path $base 'two\proxy.dll'; [IO.File]::AppendAllText($path, 'changed')
		Assert ((Manifest 'two').PackageHash -ne $manifest.PackageHash) 'DLL must matter'
		[IO.File]::WriteAllText($path, 'network package')
	}
	Test 'own mod and generated texture cache are excluded from external mods' {
		$dir = Join-Path $base 'two\local'
		New-Item -ItemType Directory -Force (Join-Path $dir 'staging_area\mp_probe'), (Join-Path $dir 'mods\texture_cache') | Out-Null
		[IO.File]::WriteAllText((Join-Path $dir 'staging_area\mp_probe\run.lua'), 'another own version')
		[IO.File]::WriteAllText((Join-Path $dir 'mods\texture_cache\generated.bin'), 'cache')
		Assert ((Manifest 'two').ModsHash -eq $manifest.ModsHash) 'not third-party content'
	}
	Test 'inactive external mods are compared with useful mismatch details' {
		$path = Join-Path $base 'two\local\staging_area\track_pack\mod.json'
		[IO.File]::WriteAllText($path, '{"track":2}')
		$other = Manifest 'two'
		Rejection { Assert-SessionCompatibility -Session $session -Manifest $other } '*anderer Inhalt: staging/track_pack*'
		[IO.File]::WriteAllText($path, '{"track":1}')
	}
	Test 'a game build mismatch is rejected' {
		$path = Join-Path $base 'two\game\TransportFever3.exe'; [IO.File]::WriteAllText($path, 'different build')
		Rejection { Assert-SessionCompatibility $session (Manifest 'two') } '*TF3-Spielversion*'
		[IO.File]::WriteAllText($path, 'game build')
	}
	Test 'configured mod.io storage fingerprints actual mods and ignores cache' {
		New-Item -ItemType Directory -Force (Join-Path $env:LOCALAPPDATA 'mod.io'), (Join-Path $base 'custom-modio\10640\mods\123'), (Join-Path $base 'custom-modio\10640\cache') | Out-Null
		@{ RootLocalStoragePath = (Join-Path $base 'custom-modio') } | ConvertTo-Json | Set-Content (Join-Path $env:LOCALAPPDATA 'mod.io\globalsettings.json')
		[IO.File]::WriteAllText((Join-Path $base 'custom-modio\10640\mods\123\mod.json'), 'installed mod')
		[IO.File]::WriteAllText((Join-Path $base 'custom-modio\10640\cache\random.json'), 'cache')
		$m = Manifest
		Assert ($m.ModCount -eq 2 -and ($m.Mods.Key -contains 'modio/123')) 'mod.io installed content included'
		Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'mod.io\globalsettings.json') -Force
	}
	Test 'fresh offers have distinct cryptographic IDs and UTF8 names in INI' {
		$another = New-MultiplayerSession $manifest $save
		Assert ($another.SessionId -ne $session.SessionId) 'fresh ID'
		$lines = Get-SessionIniLines $session
		$nameLine = $lines | Where-Object { $_ -like 'name=*' }
		$expected = ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes('Bär am See'))).Replace('-', '').ToLowerInvariant()
		Assert ($nameLine -ceq "name=$expected") 'basename UTF8 hex'
		Assert (($lines | Where-Object { $_ -like 'mods=*' }) -eq "mods=$($manifest.ModsHash)") 'native mod key'
	}
	Test 'prepared record verifies the save and installed package again' {
		$path = Join-Path $base 'prepared.json'
		Save-PreparedSession -Path $path -Session $session -SavePath $save | Out-Null
		$record = Read-PreparedSession $path
		Assert ((Assert-PreparedSession $record $manifest).SessionId -eq $session.SessionId) 'read and validate'
		$changedManifest = Manifest 'two'; $changedManifest.PackageHash = ('f' * 64)
		Rejection { Assert-PreparedSession $record $changedManifest } '*Multiplayer-Paket*'
		[IO.File]::AppendAllText($save, 'changed after transfer')
		Rejection { Assert-PreparedSession $record $manifest } '*Spielstand wurde verändert*'
		Rejection { Save-PreparedSession (Join-Path $base 'invalid.json') $session $save } '*während der Vorbereitung verändert*'
		Assert (-not (Test-Path (Join-Path $base 'invalid.json'))) 'failed preparation does not persist'
		[IO.File]::WriteAllText($save, 'shared world')
	}
	Test 'malformed sessions and missing preparation fail with clear instructions' {
		Rejection { Read-PreparedSession (Join-Path $base 'missing.json') } '*zuerst den Spielstand übertragen*'
		$invalid = $session | ConvertTo-Json -Depth 6 | ConvertFrom-Json; $invalid.SaveName = '..\outside'
		Rejection { Assert-SessionMetadata $invalid } '*Ungültiger Spielstandname*'
		$invalid = $session | ConvertTo-Json -Depth 6 | ConvertFrom-Json; $invalid.SessionId = 'not-an-id'
		Rejection { Assert-SessionMetadata $invalid } '*Ungültige Sitzung*'
	}
} finally {
	$env:PUBLIC = $oldPublic; $env:LOCALAPPDATA = $oldLocalAppData
	if (Test-Path -LiteralPath $base) {
		$resolved = [IO.Path]::GetFullPath($base)
		if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped temporary workspace.' }
		Remove-Item -LiteralPath $resolved -Recurse -Force
	}
}
Write-Host "$passed session tests passed, $failed failed"
if ($failed) { exit 1 }

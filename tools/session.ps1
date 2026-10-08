# Gemeinsamer Startstand für zwei PCs. Fingerabdrücke enthalten relative Namen und Dateiinhalt,
# keine Laufwerksbuchstaben, Benutzerkonten oder Änderungszeiten. Es werden keine Mods verändert.

function Get-SessionFileHash([string]$Path) {
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Die Datei fehlt: $Path" }
	return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SessionTextHash([string]$Text) {
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
	finally { $sha.Dispose() }
}

# OneDrive-Dateien können ReparsePoint tragen, ohne eine Verknüpfung zu sein. Nur tatsächliche
# Dateisystem-Verknüpfungen (LinkType/Target) dürfen den geprüften Ordner nicht verlassen.
function Test-SessionLink($Item) {
	if (-not [string]::IsNullOrWhiteSpace([string]$Item.LinkType)) { return $true }
	foreach ($target in @($Item.Target)) { if (-not [string]::IsNullOrWhiteSpace([string]$target)) { return $true } }
	return $false
}

function Get-SessionTreeHash([string]$Path, $Tick = $null) {
	if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Der Mod-Ordner fehlt: $Path" }
	if (Test-SessionLink (Get-Item -LiteralPath $Path -Force)) { throw "Verknüpfter Mod-Ordner kann nicht zuverlässig verglichen werden: $Path" }
	$prefix = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
	$linked = Get-ChildItem -LiteralPath $Path -Recurse -Directory -Force | Where-Object { Test-SessionLink $_ } | Select-Object -First 1
	if ($linked) { throw "Verknüpfter Mod-Ordner kann nicht zuverlässig verglichen werden: $($linked.FullName)" }
	$entries = @{}
	foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File -Force) {
		if (Test-SessionLink $file) { throw "Verknüpfte Mod-Datei kann nicht zuverlässig verglichen werden: $($file.FullName)" }
		$key = $file.FullName.Substring($prefix.Length).Replace('\', '/').ToLowerInvariant()
		$entries[$key] = "$key`:$($file.Length):$(Get-SessionFileHash $file.FullName)`n"
		if ($Tick -and (& $Tick "Prüfe Mod-Dateien ..." 0 0)) { throw 'Abgebrochen.' }
	}
	$keys = [string[]]@($entries.Keys)
	[Array]::Sort($keys, [StringComparer]::Ordinal)
	return Get-SessionTextHash (($keys | ForEach-Object { $entries[$_] }) -join '')
}

# Alle installierten zusätzlichen Mods werden verglichen, auch momentan inaktive. Die mit TF3
# ausgelieferten urbangames_* und der eigene mp_probe gehören bereits zu Spiel/Paket, Cache nicht.
function Get-SessionModRoots([string]$GameDir, [string]$Steam, [string]$SaveDir, [string[]]$AdditionalModRoots = @()) {
	$roots = @()
	if ($SaveDir) {
		$local = Split-Path -Parent $SaveDir
		$roots += @{ Label = 'staging'; Path = (Join-Path $local 'staging_area') }
		$roots += @{ Label = 'local'; Path = (Join-Path $local 'mods') }
	}
	$roots += @{ Label = 'game'; Path = (Join-Path $GameDir 'mods') }
	$roots += @{ Label = 'release'; Path = (Join-Path $GameDir 'mods\release') }
	if ($Steam) { $roots += @{ Label = 'workshop'; Path = (Join-Path $Steam 'steamapps\workshop\content\3493540') } }
	# TF3 mod.io game ID 10640; the SDK's globalsettings.json may override its storage root.
	$modioStorage = if ($env:PUBLIC) { Join-Path $env:PUBLIC 'mod.io' } else { '' }
	if ($env:LOCALAPPDATA) {
		$settingsPath = Join-Path $env:LOCALAPPDATA 'mod.io\globalsettings.json'
		if (Test-Path -LiteralPath $settingsPath) {
			try {
				$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
				if ($settings.RootLocalStoragePath) { $modioStorage = [string]$settings.RootLocalStoragePath }
			} catch { throw "Die mod.io-Speichereinstellung konnte nicht gelesen werden: $settingsPath" }
		}
	}
	if ($modioStorage) { $roots += @{ Label = 'modio'; Path = (Join-Path $modioStorage '10640\mods') } }
	$i = 0
	foreach ($path in $AdditionalModRoots) { $roots += @{ Label = "extra$($i++)"; Path = $path } }
	return $roots
}

function Get-SessionManifest([string]$GameDir, [string]$ModSource, [string]$ProxyDll, [string]$Steam = '', [string]$SaveDir = '', $Tick = $null, [string[]]$AdditionalModRoots = @()) {
	$gameHash = Get-SessionFileHash (Join-Path $GameDir 'TransportFever3.exe')
	$packageHash = Get-SessionTextHash ("mod:$(Get-SessionTreeHash $ModSource $Tick)`nproxy:$(Get-SessionFileHash $ProxyDll)`n")
	$mods = @()
	foreach ($root in Get-SessionModRoots $GameDir $Steam $SaveDir $AdditionalModRoots) {
		if (-not (Test-Path -LiteralPath $root.Path -PathType Container)) { continue }
		foreach ($item in Get-ChildItem -LiteralPath $root.Path -Force) {
			if ($item.Name -eq 'release' -or $item.Name -eq 'texture_cache' -or $item.Name -match '^mp_probe(?:_\d+)?$' -or $item.Name -match '^urbangames_') { continue }
			if (Test-SessionLink $item) { throw "Verknüpfter Mod-Ordner kann nicht zuverlässig verglichen werden: $($item.FullName)" }
			$key = "$($root.Label)/$($item.Name.ToLowerInvariant())"
			$hash = if ($item.PSIsContainer) { Get-SessionTreeHash $item.FullName $Tick } else { Get-SessionFileHash $item.FullName }
			$mods += [pscustomobject]@{ Key = $key; Hash = $hash }
		}
	}
	$lines = @{}
	foreach ($mod in $mods) { if ($lines.ContainsKey($mod.Key)) { throw "Mod doppelt erfasst: $($mod.Key)" }; $lines[$mod.Key] = "$($mod.Key):$($mod.Hash)`n" }
	$keys = [string[]]@($lines.Keys); [Array]::Sort($keys, [StringComparer]::Ordinal)
	return [pscustomobject]@{ Protocol = 3; GameHash = $gameHash; PackageHash = $packageHash; ModsHash = (Get-SessionTextHash (($keys | ForEach-Object { $lines[$_] }) -join '')); ModCount = $mods.Count; Mods = @($keys | ForEach-Object { $key = $_; $mods | Where-Object Key -eq $key }) }
}

function Assert-SessionMetadata($Session) {
	if (-not $Session -or $Session.Protocol -ne 3 -or $Session.SessionId -notmatch '^[a-fA-F0-9]{32}$') { throw 'Ungültige Sitzung. Bitte den Spielstand erneut übertragen.' }
	foreach ($field in 'GameHash', 'PackageHash', 'ModsHash', 'SaveHash') {
		if ([string]$Session.$field -notmatch '^[a-fA-F0-9]{64}$') { throw "Ungültiger Sitzungs-Fingerabdruck: $field" }
	}
	$name = [string]$Session.SaveName
	if (-not $name -or $name.Length -gt 200 -or $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $name -eq '.' -or $name -eq '..') { throw 'Ungültiger Spielstandname in der Sitzung.' }
	if (@($Session.Mods).Count -gt 10000) { throw 'Zu viele Mod-Einträge in der Sitzung.' }
}

function New-MultiplayerSession($Manifest, [string]$SavePath) {
	if ([IO.Path]::GetExtension($SavePath) -ine '.sav') { throw 'Bitte eine .sav-Spielstanddatei auswählen.' }
	$session = [pscustomobject]@{ Protocol = 3; SessionId = [Guid]::NewGuid().ToString('N'); GameHash = $Manifest.GameHash; PackageHash = $Manifest.PackageHash; ModsHash = $Manifest.ModsHash; SaveHash = (Get-SessionFileHash $SavePath); SaveName = [IO.Path]::GetFileNameWithoutExtension($SavePath); CreatedUtc = [DateTime]::UtcNow.ToString('o'); Mods = @($Manifest.Mods) }
	Assert-SessionMetadata $session
	return $session
}

function Assert-SessionCompatibility($Session, $Manifest) {
	Assert-SessionMetadata $Session
	if (-not $Manifest -or $Manifest.Protocol -ne 3) { throw 'Die lokale Kompatibilitätsprüfung fehlt.' }
	$errors = @()
	if ($Session.GameHash -ne $Manifest.GameHash) { $errors += 'Die TF3-Spielversion unterscheidet sich. Beide PCs müssen denselben Steam-Stand verwenden.' }
	if ($Session.PackageHash -ne $Manifest.PackageHash) { $errors += 'Das Multiplayer-Paket unterscheidet sich. Auf beiden PCs dieselbe Projektversion verwenden.' }
	if ($Session.ModsHash -ne $Manifest.ModsHash) {
		$remoteMods = @{}; $localMods = @{}
		foreach ($m in $Session.Mods) { $remoteMods[[string]$m.Key] = [string]$m.Hash }
		foreach ($m in $Manifest.Mods) { $localMods[[string]$m.Key] = [string]$m.Hash }
		$detail = @()
		foreach ($key in $remoteMods.Keys) { if (-not $localMods.ContainsKey($key)) { $detail += "fehlt: $key" } elseif ($remoteMods[$key] -ne $localMods[$key]) { $detail += "anderer Inhalt: $key" } }
		foreach ($key in $localMods.Keys) { if (-not $remoteMods.ContainsKey($key)) { $detail += "zusätzlich: $key" } }
		$errors += ('Die installierten zusätzlichen Mods unterscheiden sich (auch inaktive werden geprüft).' + $(if ($detail.Count) { ' ' + (($detail | Select-Object -First 8) -join '; ') } else { '' }))
	}
	if ($errors.Count) { throw ($errors -join "`r`n") }
}

function Save-PreparedSession([string]$Path, $Session, [string]$SavePath) {
	Assert-SessionMetadata $Session
	if ([IO.Path]::GetFileNameWithoutExtension($SavePath) -cne $Session.SaveName -or (Get-SessionFileHash $SavePath) -ne $Session.SaveHash) { throw 'Der Spielstand wurde während der Vorbereitung verändert. Bitte erneut übertragen.' }
	$record = [pscustomobject]@{ Version = 1; Session = $Session; SavePath = [IO.Path]::GetFullPath($SavePath); PreparedUtc = [DateTime]::UtcNow.ToString('o') }
	$parent = Split-Path -Parent $Path
	if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
	$temp = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
	try { [IO.File]::WriteAllText($temp, ($record | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath $temp -Destination $Path -Force }
	finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
	return $record
}

function Read-PreparedSession([string]$Path) {
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Noch keine gemeinsame Sitzung vorbereitet. Bitte zuerst den Spielstand übertragen.' }
	try { $record = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw 'Die gespeicherte Sitzung ist beschädigt. Bitte den Spielstand erneut übertragen.' }
	if ($record.Version -ne 1 -or -not $record.SavePath) { throw 'Die gespeicherte Sitzung ist unvollständig. Bitte den Spielstand erneut übertragen.' }
	Assert-SessionMetadata $record.Session
	return $record
}

function Assert-PreparedSession($Prepared, $Manifest) {
	if (-not $Prepared -or -not $Prepared.SavePath) { throw 'Noch keine gemeinsame Sitzung vorbereitet. Bitte zuerst den Spielstand übertragen.' }
	Assert-SessionCompatibility $Prepared.Session $Manifest
	if ([IO.Path]::GetFileNameWithoutExtension([string]$Prepared.SavePath) -cne $Prepared.Session.SaveName -or (Get-SessionFileHash $Prepared.SavePath) -ne $Prepared.Session.SaveHash) { throw 'Der vorbereitete Spielstand wurde verändert. Bitte erneut übertragen und auf beiden PCs diesen Stand laden.' }
	return $Prepared.Session
}

function Get-SessionIniLines($Session) {
	Assert-SessionMetadata $Session
	$name = ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes([string]$Session.SaveName))).Replace('-', '').ToLowerInvariant()
	return @('[session]', "id=$($Session.SessionId.ToLowerInvariant())", "game=$($Session.GameHash.ToLowerInvariant())", "package=$($Session.PackageHash.ToLowerInvariant())", "mods=$($Session.ModsHash.ToLowerInvariant())", "save=$($Session.SaveHash.ToLowerInvariant())", "name=$name")
}

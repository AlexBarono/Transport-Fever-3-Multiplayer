# Portable launcher updates. The release manifest is a public GitHub asset;
# clients need neither Git, an API token nor a GitHub account.
$script:LauncherUpdateRepository='AlexBarono/Transport-Fever-3-Multiplayer'

function Get-LauncherPackageVersion([string]$Root) {
    $path=Join-Path $Root 'mods\mp_probe\content\mp_probe\main.script.lua'
    $match=[regex]::Match([IO.File]::ReadAllText($path),'(?m)^\s*main\.PROBE_VERSION\s*=\s*(\d+)\b')
    if(-not $match.Success){throw 'Die Paketversion konnte nicht gelesen werden.'}
    return [int]$match.Groups[1].Value
}

function Test-UpdateLink($Item) {
    return ($Item.PSObject.Properties['LinkType'] -and $Item.LinkType) -or
        ($Item.PSObject.Properties['Target'] -and @($Item.Target | Where-Object {$_}).Count -gt 0)
}

function Assert-LauncherUpdateRoot([string]$Root) {
    $full=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    if($full.Length -lt 5 -or -not (Test-Path -LiteralPath (Join-Path $full 'Start.bat') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $full 'launcher\launcher.ps1') -PathType Leaf)){
        throw 'Kein gültiger Launcher-Paketordner.'
    }
    if(Test-Path -LiteralPath (Join-Path $full '.git')){throw 'Updates bitte im Windows-Paket installieren; dieser Ordner ist ein Entwicklercheckout.'}
    $parent=Get-Item -LiteralPath $full -Force
    while($parent){
        if(Test-UpdateLink $parent){throw 'Ein verknüpfter Paketordner kann nicht automatisch aktualisiert werden.'}
        $parent=$parent.Parent
    }
    [void](Get-LauncherPackageVersion $full)
    return $full
}

function Read-LauncherUpdateManifest($Manifest,[int]$CurrentVersion) {
    $version=0; $size=0L
    if($Manifest.schema -ne 1 -or -not [int]::TryParse([string]$Manifest.version,[ref]$version) -or $version -lt 1 -or
        -not [long]::TryParse([string]$Manifest.bytes,[ref]$size) -or $size -lt 1 -or $size -gt 64MB -or
        [string]$Manifest.sha256 -cnotmatch '^[0-9a-f]{64}$'){
        throw 'Die Updateinformation ist unvollständig oder ungültig.'
    }
    $name="TF3-Multiplayer-v$version-Windows.zip"
    return [pscustomobject]@{Version=$version;Available=($version -gt $CurrentVersion);Bytes=$size;Sha256=[string]$Manifest.sha256;
        Name=$name;Url="https://github.com/$script:LauncherUpdateRepository/releases/download/v$version/$name"}
}

function Open-LauncherUpdateResponse([string]$Url) {
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request=[Net.HttpWebRequest]::Create($Url)
    $request.UserAgent='TF3MP-Launcher-Updater/1';$request.Timeout=15000;$request.ReadWriteTimeout=15000
    $request.MaximumAutomaticRedirections=5
    try{$response=$request.GetResponse()}
    catch [Net.WebException]{
        if($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404){
            $_.Exception.Response.Dispose()
            throw 'Noch kein öffentliches Update vorhanden. Das GitHub-Repository muss öffentlich sein und ein Release mit update.json enthalten. Alternativ Update aus ZIP wählen.'
        }
        if($_.Exception.Response){$_.Exception.Response.Dispose()}
        throw 'GitHub ist gerade nicht erreichbar. Später erneut versuchen oder Update aus ZIP wählen.'
    }
    $uri=$response.ResponseUri
    if($uri.Scheme -ne 'https' -or $uri.DnsSafeHost -notin @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com')){
        $response.Dispose();throw 'Das Update wurde auf eine unerwartete Downloadadresse umgeleitet.'
    }
    return $response
}

function Get-LauncherUpdate([int]$CurrentVersion) {
    $response=Open-LauncherUpdateResponse "https://github.com/$script:LauncherUpdateRepository/releases/latest/download/update.json"
    try{
        $stream=$response.GetResponseStream();$buffer=New-Object byte[] 16385;$count=0
        while($count -lt $buffer.Length){$read=$stream.Read($buffer,$count,$buffer.Length-$count);if(-not $read){break};$count+=$read}
        if($count -gt 16384){throw 'Die Updateinformation ist zu groß.'}
        $manifest=[Text.Encoding]::UTF8.GetString($buffer,0,$count).TrimStart([char]0xfeff) | ConvertFrom-Json
        return Read-LauncherUpdateManifest $manifest $CurrentVersion
    }finally{$response.Dispose()}
}

function Save-LauncherUpdate($Update,[string]$Destination) {
    $response=Open-LauncherUpdateResponse $Update.Url
    try{
        if($response.ContentLength -gt 64MB -or ($response.ContentLength -ge 0 -and $response.ContentLength -ne $Update.Bytes)){
            throw 'Die Downloadgröße stimmt nicht mit der Updateinformation überein.'
        }
        $input=$response.GetResponseStream();$output=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew)
        try{
            $buffer=New-Object byte[] 65536;$total=0L
            while(($count=$input.Read($buffer,0,$buffer.Length)) -gt 0){
                $total+=$count;if($total -gt $Update.Bytes -or $total -gt 64MB){throw 'Das Update ist größer als angekündigt.'}
                $output.Write($buffer,0,$count)
            }
        }finally{$output.Dispose()}
        if($total -ne $Update.Bytes -or (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Update.Sha256){
            throw 'Die Prüfsumme des Updates stimmt nicht. Das bisherige Paket bleibt erhalten.'
        }
    }finally{$response.Dispose()}
}

function Read-UpdateZipText($Archive,[string]$Name,[long]$Limit=2MB) {
    $entry=$Archive.GetEntry($Name)
    if(-not $entry -or $entry.Length -gt $Limit){throw "Im Update fehlt eine gültige Datei: $Name"}
    $reader=[IO.StreamReader]::new($entry.Open(),[Text.Encoding]::UTF8,$true)
    try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
}

function Get-LauncherUpdateArchive([string]$ZipPath,[int]$CurrentVersion,[int]$ExpectedVersion=0) {
    Add-Type -AssemblyName System.IO.Compression
    $info=Get-Item -LiteralPath $ZipPath -Force
    if($info.Length -gt 64MB -or (Test-UpdateLink $info)){throw 'Die Update-ZIP ist zu groß oder verknüpft.'}
    $file=[IO.File]::OpenRead($info.FullName)
    try{
        $archive=[IO.Compression.ZipArchive]::new($file,[IO.Compression.ZipArchiveMode]::Read,$true)
        try{
            if($archive.Entries.Count -lt 8 -or $archive.Entries.Count -gt 2000){throw 'Das Update enthält eine ungültige Anzahl Dateien.'}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$total=0L
            foreach($entry in $archive.Entries){
                $name=$entry.FullName
                if(-not $seen.Add($name) -or $name -match '[\\:]|(^|/)\.\.?(/|$)' -or
                    $name -notmatch '^(Start\.bat|Test-letzte-Aufnahme\.bat|README\.md|package-manifest\.json|launcher/[^/]+\.ps1|launcher/bin/alut\.dll|tools/[^/]+\.(ps1|cs|lua)|mods/mp_probe/.+|docs/[^/]+\.md|logs/README\.md|tests/fixtures/run29-replay\.log)$'){
                    throw "Ungültiger oder doppelter Pfad im Update: $name"
                }
                foreach($part in $name.Split('/')){
                    if(-not $part -or $part.TrimEnd('.',' ') -cne $part -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
                        $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)'){throw 'Ungültiger Windows-Dateiname im Update.'}
                }
                if((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000){throw 'Verknüpfungen sind im Update nicht erlaubt.'}
                $total+=$entry.Length
                if($entry.Length -gt 64MB -or $total -gt 256MB){throw 'Das entpackte Update ist zu groß.'}
            }
            $main=Read-UpdateZipText $archive 'mods/mp_probe/content/mp_probe/main.script.lua'
            $match=[regex]::Match($main,'(?m)^\s*main\.PROBE_VERSION\s*=\s*(\d+)\b')
            if(-not $match.Success){throw 'Im Update fehlt die Paketversion.'}
            $version=[int]$match.Groups[1].Value
            if($version -le $CurrentVersion){throw "Das Paket v$version ist nicht neuer als die installierte Version v$CurrentVersion."}
            if($ExpectedVersion -and $version -ne $ExpectedVersion){throw 'Die Version im Update stimmt nicht mit der Ankündigung überein.'}
            $metadata=(Read-UpdateZipText $archive 'mods/mp_probe/_metadata/modinfo.json') | ConvertFrom-Json
            $view=Read-UpdateZipText $archive 'launcher/view.ps1'
            $metaVersion=[regex]::Match([string]$metadata.description,("Probe v"+$version+'\s*/\s*bridge v(\d+)\b'))
            $viewVersion=[regex]::Match($view,("Probe v"+$version+'\s*/\s*Bridge v(\d+)\b'))
            if(-not $metaVersion.Success -or -not $viewVersion.Success -or $metaVersion.Groups[1].Value -ne $viewVersion.Groups[1].Value){
                throw 'Die Versionsangaben im Update widersprechen sich.'
            }
            foreach($required in @('Start.bat','README.md','launcher/launcher.ps1','launcher/bin/alut.dll','tools/update.ps1','tools/apply-update.ps1')){
                if(-not $seen.Contains($required)){throw "Im Update fehlt $required"}
            }
            $content=(Read-UpdateZipText $archive 'mods/mp_probe/_content.json') | ConvertFrom-Json
            if($content.files -isnot [Array] -or -not $content.files.Count){throw 'Im Update fehlt die Mod-Dateiliste.'}
            foreach($name in $content.files){
                if([string]$name -match '[\\:]|(^|/)\.\.?(/|$)' -or -not $seen.Contains('mods/mp_probe/content/'+$name)){
                    throw 'Die Mod-Dateiliste des Updates ist unvollständig.'
                }
            }
            $inventory=(Read-UpdateZipText $archive 'package-manifest.json') | ConvertFrom-Json
            if($inventory.schema -ne 1 -or $inventory.version -ne $version -or $inventory.bridge -ne [int]$metaVersion.Groups[1].Value -or
                $inventory.files -isnot [Array] -or $inventory.files.Count -ne $seen.Count-1){throw 'Die Paket-Dateiliste ist unvollständig.'}
            $verified=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($record in $inventory.files){
                $name=[string]$record.path
                if($name -eq 'package-manifest.json' -or -not $seen.Contains($name) -or -not $verified.Add($name) -or [string]$record.sha256 -cnotmatch '^[0-9a-f]{64}$'){
                    throw 'Ungültiger Eintrag in der Paket-Dateiliste.'
                }
                $input=$archive.GetEntry($name).Open();$sha=[Security.Cryptography.SHA256]::Create()
                try{$hash=([BitConverter]::ToString($sha.ComputeHash($input))).Replace('-','').ToLowerInvariant()}finally{$input.Dispose();$sha.Dispose()}
                if($hash -cne $record.sha256){throw "Die Paketdatei ist beschädigt oder verändert: $name"}
            }
            return [pscustomobject]@{Version=$version;Files=$seen.Count;Bytes=$total;Sha256=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()}
        }finally{$archive.Dispose()}
    }finally{$file.Dispose()}
}

function Expand-LauncherUpdate([string]$ZipPath,[string]$Destination) {
    # Only called after validation, into a new, exclusively created directory.
    $prefix=[IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\'
    $file=[IO.File]::OpenRead($ZipPath)
    try{
        $archive=[IO.Compression.ZipArchive]::new($file,[IO.Compression.ZipArchiveMode]::Read,$true)
        try{foreach($entry in $archive.Entries){
            $target=[IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if(-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Updatepfad verlässt den Zielordner.'}
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
            $input=$entry.Open();$output=[IO.File]::Open($target,[IO.FileMode]::CreateNew)
            try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
        }}finally{$archive.Dispose()}
    }finally{$file.Dispose()}
}

function Prepare-LauncherUpdate([string]$Root,$Update=$null,[string]$ZipPath='',[string]$WorkDirectory='') {
    $target=Assert-LauncherUpdateRoot $Root
    $current=Get-LauncherPackageVersion $target
    $job=if($WorkDirectory){[IO.Path]::GetFullPath($WorkDirectory)}else{Join-Path (Split-Path -Parent $target) ('.tf3mp-update-'+[guid]::NewGuid().ToString('N'))}
    if((Split-Path -Parent $job) -cne (Split-Path -Parent $target) -or (Split-Path -Leaf $job) -notmatch '^\.tf3mp-update-[0-9a-f]{32}$' -or (Test-Path -LiteralPath $job)){
        throw 'Ungültiger oder bereits vorhandener Update-Arbeitsordner.'
    }
    [void][IO.Directory]::CreateDirectory($job)
    try{
        $zip=Join-Path $job 'package.zip'
        if($ZipPath){Copy-Item -LiteralPath $ZipPath -Destination $zip}
        elseif($Update -and $Update.Available){Save-LauncherUpdate $Update $zip}
        else{throw 'Kein neueres Update ausgewählt.'}
        $expected=if($Update){[int]$Update.Version}else{0}
        $package=Get-LauncherUpdateArchive $zip $current $expected
        $stage=Join-Path $job 'package';[void][IO.Directory]::CreateDirectory($stage)
        Expand-LauncherUpdate $zip $stage
        Copy-Item -LiteralPath (Join-Path $target 'tools\update.ps1') -Destination (Join-Path $job 'update.ps1')
        Copy-Item -LiteralPath (Join-Path $target 'tools\apply-update.ps1') -Destination (Join-Path $job 'apply-update.ps1')
        @{Schema=1;Root=$target;Version=$package.Version;PreviousVersion=$current;Sha256=$package.Sha256} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $job 'plan.json') -Encoding UTF8
        return [pscustomobject]@{Directory=$job;Version=$package.Version}
    }catch{
        Remove-LauncherUpdateWork $target $job
        throw
    }
}

function Remove-LauncherUpdateWork([string]$Root,[string]$Directory) {
    $target=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $job=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    if((Split-Path -Parent $job) -cne (Split-Path -Parent $target) -or (Split-Path -Leaf $job) -notmatch '^\.tf3mp-update-[0-9a-f]{32}$'){
        throw 'Der Update-Arbeitsordner liegt außerhalb des vorgesehenen Bereichs.'
    }
    if(Test-Path -LiteralPath $job){
        if(Test-UpdateLink (Get-Item -LiteralPath $job -Force)){throw 'Verknüpften Updateordner nicht entfernen.'}
        $linked=Get-ChildItem -LiteralPath $job -Recurse -Force | Where-Object {Test-UpdateLink $_} | Select-Object -First 1
        if($linked){throw 'Verknüpften Inhalt im Updateordner nicht entfernen.'}
        Remove-Item -LiteralPath $job -Recurse -Force
    }
}

function Get-LauncherUpdateBlockReason([bool]$GameRunning,[bool]$Busy,[bool]$Connected) {
    if($GameRunning){return 'TF3 vor dem Aktualisieren beenden.'}
    if($Busy){return 'Den laufenden Vorgang vor dem Aktualisieren abschließen.'}
    if($Connected){return 'Vor dem Aktualisieren die gemeinsame Sitzung beenden und beide Launcher aktualisieren.'}
    return ''
}

# Shared start: bounded process shutdown, reversible menu bootstrap and a one-shot DLL request.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Stop-LauncherGameForStart($Tick = $null) {
    if(-not (Test-GameRunning)){return}
    if(-not $Tick){$Tick={param($text,$done,$total) Write-LauncherLog $text; [Windows.Forms.Application]::DoEvents(); return $false}}
    # Stop-GameForResync also has a $tick parameter; capture a different name so
    # PowerShell's dynamic scope cannot turn this callback into a recursive call.
    $startProgressCallback=$Tick
    $progress={param($text,$done,$total) & $startProgressCallback ($text -replace 'für den bestätigten Neuabgleich','für den gemeinsamen Start') $done $total}.GetNewClosure()
    [void](Stop-GameForResync $progress)
}

function Get-GameAutoloadFailure([string]$GameDir, [datetime]$Since) {
    $path=Join-Path $GameDir 'alut_proxy.log'
    if(-not (Test-Path -LiteralPath $path)){return ''}
    foreach($line in @(Get-Content -LiteralPath $path -Tail 80 -ErrorAction SilentlyContinue)){
        if($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[\d+\] launcher: autoload failed: (.+)$'){
            $stamp=[datetime]::ParseExact($matches[1],'yyyy-MM-dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
            if($stamp -ge $Since.ToLocalTime().AddSeconds(-1)){return $matches[2]}
        }
    }
    return ''
}

function Install-GameAutoload([string]$GameDir) {
    $base=Join-Path $GameDir 'base'
    $manifest=Join-Path $base '_content.json'
    $backup=$manifest+'.tf3mp-original'; $record=$manifest+'.tf3mp.json'
    $entryName='gui/menu/main_menu.tl'
    $loose=Join-Path $base ('content/'+$entryName)
    $helper=Join-Path $base 'content/gui/menu/tf3mp_autoload.lua'
    if(-not (Test-Path -LiteralPath $manifest)){throw 'Die TF3-Ressourcenliste fehlt. Automatisches Laden ist mit dieser Installation nicht möglich.'}
    $current=Get-SessionFileHash $manifest
    if(Test-Path -LiteralPath $record){
        $saved=Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
        if($current -eq $saved.Patched -and (Get-SessionFileHash $backup) -eq $saved.Original -and (Get-SessionFileHash $loose) -eq $saved.Bootstrap -and (Get-SessionFileHash $helper) -eq $saved.Helper){
            # Upgrade our verified helper as well; an existing v53 bootstrap
            # otherwise keeps its old load API even with a newer launcher.
            $helperSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'game-autoload.lua'))
            if([IO.File]::ReadAllText($helper) -cne $helperSource){
                [IO.File]::WriteAllText($helper,$helperSource,(New-Object Text.UTF8Encoding($false)))
                $saved.Helper=Get-SessionFileHash $helper
                $saved | ConvertTo-Json | Set-Content -LiteralPath $record -Encoding ASCII
            }
            return
        }
        throw 'Die TF3-Menüeinrichtung wurde verändert. Mod entfernen oder die Spieldateien in Steam prüfen.'
    }
    if((Test-Path -LiteralPath $loose) -or (Test-Path -LiteralPath $helper)){throw 'Eine andere Erweiterung verändert bereits das TF3-Hauptmenü. Die Datei wird nicht überschrieben.'}
    $data=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $gui=@($data.archives | Where-Object {$_.fileName -eq 'gui.zip'})
    if($gui.Count -ne 1 -or @($gui[0].entries | Where-Object {$_.fileName -eq $entryName}).Count -ne 1){throw 'TF3-Hauptmenü wurde in dieser Version nicht eindeutig gefunden.'}
    $archive=Join-Path $base 'content/gui.zip'
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entry=$zip.GetEntry($entryName); if(-not $entry){throw 'TF3-Hauptmenü fehlt im Archiv.'}
        $reader=New-Object IO.StreamReader($entry.Open()); try {$source=$reader.ReadToEnd()}finally{$reader.Dispose()}
    } finally {$zip.Dispose()}
    $anchor='local commonMenuParams : CommonMenuParams = {'
    if(([regex]::Matches($source,[regex]::Escape($anchor))).Count -ne 1){throw 'Diese TF3-Menüversion kann nicht sicher für den automatischen Start eingerichtet werden.'}
    $bootstrap=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'game-autoload.lua'))
    $injection=@'
-- TF3MP_AUTOLOAD_V53
    local tf3mp_autoload = ug_require "::/gui/menu/tf3mp_autoload.lua" as any
    tf3mp_autoload(react, app, api, log, setPage)

'@
    $patched=$source.Replace($anchor,$injection+"`n`t"+$anchor)
    # TF3 indexes zip entries by byte offset. Keep every archive untouched and replace only
    # this entry in its resource index with a loose file, just like native loose resources.
    $gui[0].entries=@($gui[0].entries | Where-Object {$_.fileName -ne $entryName})
    $data.files=@($data.files)+@($entryName,'gui/menu/tf3mp_autoload.lua')
    $json=$data | ConvertTo-Json -Depth 12 -Compress
    Copy-Item -LiteralPath $manifest -Destination $backup -Force
    $temp=$manifest+'.tf3mp-new'
    try {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $loose))
        [IO.File]::WriteAllText($loose,$patched,(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($helper,$bootstrap,(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
        @{Original=$current;Patched=(Get-SessionFileHash $temp);Bootstrap=(Get-SessionFileHash $loose);Helper=(Get-SessionFileHash $helper)} | ConvertTo-Json | Set-Content -LiteralPath $record -Encoding ASCII
        Move-Item -LiteralPath $temp -Destination $manifest -Force
    } finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}

function Remove-GameAutoload([string]$GameDir) {
    $manifest=Join-Path $GameDir 'base/_content.json'; $backup=$manifest+'.tf3mp-original'; $record=$manifest+'.tf3mp.json'
    $loose=Join-Path $GameDir 'base/content/gui/menu/main_menu.tl'
    $helper=Join-Path $GameDir 'base/content/gui/menu/tf3mp_autoload.lua'
    if(Test-Path -LiteralPath $record){
        $saved=Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
        $current=Get-SessionFileHash $manifest
        if($current -eq $saved.Patched){
            if((Get-SessionFileHash $backup) -ne $saved.Original){throw 'Die Sicherung der TF3-Ressourcenliste stimmt nicht. Original bleibt zur Prüfung erhalten.'}
            Copy-Item -LiteralPath $backup -Destination $manifest -Force
        }
        # A Steam update may have replaced the index. Preserve that newer index.
        if(Test-Path -LiteralPath $loose){
            if((Get-SessionFileHash $loose) -ne $saved.Bootstrap){throw 'Die Menüergänzung wurde anderweitig geändert; sie bleibt zur Prüfung erhalten.'}
            Remove-Item -LiteralPath $loose -Force
        }
        if(Test-Path -LiteralPath $helper){
            if((Get-SessionFileHash $helper) -ne $saved.Helper){throw 'Die Ladeergänzung wurde anderweitig geändert; sie bleibt zur Prüfung erhalten.'}
            Remove-Item -LiteralPath $helper -Force
        }
        Remove-Item -LiteralPath $backup,$record -Force
    }
    $request=Join-Path $GameDir 'alut_proxy.launch'
    if(Test-Path -LiteralPath $request){Remove-Item -LiteralPath $request -Force}
}

function Request-GameAutoload([string]$GameDir, [string]$SaveName) {
    $name=$SaveName
    if(-not $name -or $SaveName -match '[\\/\r\n]' -or $name.Length -gt 180){throw 'Ungültiger Name für den gemeinsamen Spielstart.'}
    Install-GameAutoload $GameDir
    $hex=([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($name))).Replace('-','').ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $GameDir 'alut_proxy.launch') -Value @('[launch]',"save_hex=$hex") -Encoding ASCII
}

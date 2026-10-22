$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\update.ps1')
Add-Type -AssemblyName System.IO.Compression
$script:passed=0
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
function Reject($action,$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Check $failed $message}
function Hash-Bytes([byte[]]$bytes){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function New-FixtureZip([string]$Path,[int]$Version=67,[string]$Extra='',[string]$Drop='',[switch]$Damage,[switch]$BadBridge,[switch]$Symlink){
    $files=[ordered]@{
        'Start.bat'='@echo off'
        'README.md'="Fixture v$Version"
        'launcher/launcher.ps1'='[IO.File]::WriteAllText((Join-Path $PSScriptRoot ''restart-proof.txt''),''ok'')'
        'launcher/view.ps1'="Probe v$Version / Bridge v16"
        'launcher/bin/alut.dll'='MZ fixture'
        'tools/update.ps1'='# fixture'
        'tools/apply-update.ps1'='# fixture'
        'mods/mp_probe/content/mp_probe/main.script.lua'="main.PROBE_VERSION = $Version"
        'mods/mp_probe/_metadata/modinfo.json'=(@{description="Probe v$Version / bridge v16"}|ConvertTo-Json -Compress)
        'mods/mp_probe/_content.json'='{"files":["mp_probe/main.script.lua"]}'
    }
    if($BadBridge){$files['launcher/view.ps1']="Probe v$Version / Bridge v17"}
    $records=@(foreach($name in $files.Keys){@{path=$name;sha256=(Hash-Bytes ([Text.Encoding]::UTF8.GetBytes($files[$name])))}})
    $files['package-manifest.json']=@{schema=1;version=$Version;bridge=16;files=$records}|ConvertTo-Json -Compress -Depth 5
    if($Damage){$files['README.md']='damaged after checksums were calculated'}
    if($Extra){$files[$Extra]='unwanted'}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew)
    try{
        $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        try{foreach($name in $files.Keys){
            if($name -eq $Drop){continue}
            $entry=$zip.CreateEntry($name)
            if($Symlink -and $name -eq 'README.md'){$entry.ExternalAttributes=-1610612736}
            $bytes=[Text.Encoding]::UTF8.GetBytes($files[$name]);$output=$entry.Open()
            try{$output.Write($bytes,0,$bytes.Length)}finally{$output.Dispose()}
        }}finally{$zip.Dispose()}
    }finally{$stream.Dispose()}
}

function Test-DownloadFixture([string]$Directory,[string]$Zip){
    function Open-LauncherUpdateResponse {
        $response=[pscustomobject]@{ContentLength=$script:downloadBytes.Length}
        $response|Add-Member ScriptMethod GetResponseStream {return [IO.MemoryStream]::new($script:downloadBytes,$false)}
        $response|Add-Member ScriptMethod Dispose {}
        return $response
    }
    $script:downloadBytes=[IO.File]::ReadAllBytes($Zip)
    $info=[pscustomobject]@{Url='fixture';Bytes=$script:downloadBytes.Length;Sha256=(Hash-Bytes $script:downloadBytes)}
    $destination=Join-Path $Directory 'download.zip'
    Save-LauncherUpdate $info $destination
    Check ((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -eq $info.Sha256) 'Complete download changed'
    $info.Sha256='a'*64
    Reject {Save-LauncherUpdate $info (Join-Path $Directory 'bad-download.zip')} 'Wrong outer download checksum accepted'
    $info.Bytes++
    Reject {Save-LauncherUpdate $info (Join-Path $Directory 'short-download.zip')} 'Truncated download accepted'
    $script:downloadBytes=[Text.Encoding]::UTF8.GetPreamble()+[Text.Encoding]::UTF8.GetBytes('{"schema":1,"version":67,"bytes":1024,"sha256":"'+('a'*64)+'"}')
    Check ((Get-LauncherUpdate 66).Version -eq 67) 'UTF8 BOM release manifest rejected'
    $script:downloadBytes=New-Object byte[] 16385
    Reject {Get-LauncherUpdate 66} 'Oversized release manifest accepted'
}

$testRoot=Join-Path $env:TEMP ('tf3mp-update-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$oldLocal=$env:LOCALAPPDATA;$process=$null;$oldLauncher=$null
try{
    $manifest=@{schema=1;version=67;bytes=1024;sha256=('a'*64)}
    $update=Read-LauncherUpdateManifest $manifest 66
    Check ($update.Available -and $update.Version -eq 67 -and $update.Url -eq 'https://github.com/AlexBarono/Transport-Fever-3-Multiplayer/releases/download/v67/TF3-Multiplayer-v67-Windows.zip') 'Wrong release selected'
    Check (-not (Read-LauncherUpdateManifest $manifest 67).Available) 'Same version offered again'
    Check (-not (Read-LauncherUpdateManifest $manifest 68).Available) 'Downgrade offered online'
    foreach($change in @(@('schema',2),@('version','oops'),@('version',0),@('bytes',0),@('bytes',67108865),@('sha256','bad'))){
        $bad=$manifest.Clone();$bad[$change[0]]=$change[1]
        Reject {Read-LauncherUpdateManifest $bad 66} ('Invalid release accepted: '+$change[0])
    }
    Check (-not (Get-LauncherUpdateBlockReason $false $false $false)) 'Idle update blocked'
    Check ([bool](Get-LauncherUpdateBlockReason $true $false $false)) 'Running TF3 can be updated'
    Check ([bool](Get-LauncherUpdateBlockReason $false $true $false)) 'Busy session can be updated'
    Check ([bool](Get-LauncherUpdateBlockReason $false $false $true)) 'Connected session can be updated'

    $zip=Join-Path $testRoot 'good.zip';New-FixtureZip $zip
    $package=Get-LauncherUpdateArchive $zip 66 67
    Test-DownloadFixture $testRoot $zip
    Check ($package.Version -eq 67 -and $package.Files -eq 11) 'Valid package rejected'
    Reject {Get-LauncherUpdateArchive $zip 67} 'Same package version accepted'
    Reject {Get-LauncherUpdateArchive $zip 66 68} 'Wrong announced version accepted'
    foreach($name in @('../outside.ps1','mods/mp_probe/../../outside.ps1','mods/mp_probe/content/evil:stream.lua','mods/mp_probe/content/NUL.lua','mods/mp_probe/content/end.','launcher\launcher.ps1','unexpected.ps1')){
        $bad=Join-Path $testRoot ([guid]::NewGuid().ToString('N')+'.zip');New-FixtureZip $bad -Extra $name
        Reject {Get-LauncherUpdateArchive $bad 66} ('Unsafe ZIP path accepted: '+$name)
    }
    foreach($mode in @('missing','damage','bridge','symlink')){
        $bad=Join-Path $testRoot ($mode+'.zip')
        switch($mode){
            missing {New-FixtureZip $bad -Drop 'tools/update.ps1'}
            damage {New-FixtureZip $bad -Damage}
            bridge {New-FixtureZip $bad -BadBridge}
            symlink {New-FixtureZip $bad -Symlink}
        }
        Reject {Get-LauncherUpdateArchive $bad 66} ('Broken ZIP accepted: '+$mode)
    }

    $portable=Join-Path $testRoot 'Portable launcher with spaces'
    [void][IO.Directory]::CreateDirectory($portable)
    Expand-LauncherUpdate $zip $portable
    # Fixture v66 is the old package; v67 is the offered update.
    Set-Content -LiteralPath (Join-Path $portable 'mods/mp_probe/content/mp_probe/main.script.lua') -Value 'main.PROBE_VERSION = 66' -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\tools\update.ps1') -Destination (Join-Path $portable 'tools\update.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\tools\apply-update.ps1') -Destination (Join-Path $portable 'tools\apply-update.ps1') -Force
    # The real game may be open while this isolated fixture runs. Only its
    # copied library receives the process mock; production helpers keep the guard.
    $processMock=@'

function Get-Process {
    param($Name,$Id)
    if($Name -eq 'TransportFever3'){
        if($env:TF3MP_UPDATE_FIXTURE_GAME -eq '1'){return [pscustomobject]@{Name=$Name}}
        return
    }
    Microsoft.PowerShell.Management\Get-Process @PSBoundParameters
}
function Move-Item {
    param($LiteralPath,$Destination)
    $script:fixtureMoves++
    if($env:TF3MP_UPDATE_FIXTURE_MOVE_FAIL -eq '1' -and $script:fixtureMoves -eq 2){throw 'Scripted second rename failure'}
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -ErrorAction Stop
}
'@
    Add-Content -LiteralPath (Join-Path $portable 'tools\update.ps1') -Value $processMock -Encoding UTF8
    [IO.File]::WriteAllText((Join-Path $portable 'personal-note.txt'),'retain in backup')
    Check ((Assert-LauncherUpdateRoot $portable) -eq [IO.Path]::GetFullPath($portable).TrimEnd('\','/')) 'Valid portable root rejected'
    [void][IO.Directory]::CreateDirectory((Join-Path $portable '.git'))
    Reject {Assert-LauncherUpdateRoot $portable} 'Git checkout can be replaced'
    [IO.Directory]::Delete((Join-Path $portable '.git'))
    Reject {Remove-LauncherUpdateWork $portable $testRoot} 'Cleanup accepted an unrelated directory'

    $prepared=Prepare-LauncherUpdate $portable $null $zip
    Check ($prepared.Version -eq 67 -and (Test-Path -LiteralPath (Join-Path $prepared.Directory 'plan.json'))) 'Package not prepared'
    Check ((Get-LauncherPackageVersion $portable) -eq 66) 'Preparation changed the running package'
    # The helper must ignore modifications to previously extracted staging files.
    [IO.File]::WriteAllText((Join-Path $prepared.Directory 'package\README.md'),'tampered stage')
    $env:LOCALAPPDATA=Join-Path $testRoot 'profile'
    $identity=Join-Path $env:LOCALAPPDATA 'TF3MP\Internet\host-identity.dat'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $identity));[IO.File]::WriteAllText($identity,'unchanged identity')
    $helper=Join-Path $prepared.Directory 'apply-update.ps1'
    $env:TF3MP_UPDATE_FIXTURE_GAME='1'
    $process=Start-Process (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -PassThru -WorkingDirectory $testRoot -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$helper+'"'),'-Directory',('"'+$prepared.Directory+'"'),'-NoRestart')
    Check ($process.WaitForExit(20000) -and $process.ExitCode -eq 1) 'Helper ignored a game started after preparation'
    Check ((Get-LauncherPackageVersion $portable) -eq 66) 'Rejected update changed the old package'
    $env:TF3MP_UPDATE_FIXTURE_GAME=''
    $env:TF3MP_UPDATE_FIXTURE_MOVE_FAIL='1'
    $process=Start-Process (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -PassThru -WorkingDirectory $testRoot -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$helper+'"'),'-Directory',('"'+$prepared.Directory+'"'),'-NoRestart')
    Check ($process.WaitForExit(20000) -and $process.ExitCode -eq 1) 'Second rename failure was not reported'
    Check ((Get-LauncherPackageVersion $portable) -eq 66 -and (Test-Path -LiteralPath (Join-Path $portable 'personal-note.txt'))) 'Failed replacement did not restore the old folder'
    $env:TF3MP_UPDATE_FIXTURE_MOVE_FAIL=''
    $waitScript=Join-Path $testRoot 'old-launcher.ps1';Set-Content -LiteralPath $waitScript -Value 'Start-Sleep -Seconds 30'
    $oldLauncher=Start-Process (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -PassThru -WorkingDirectory $testRoot -ArgumentList @('-NoProfile','-File',('"'+$waitScript+'"'))
    Remove-Item -LiteralPath (Join-Path $prepared.Directory 'ready.txt') -Force
    $process=Start-Process (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -PassThru -WorkingDirectory $testRoot -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$helper+'"'),'-Directory',('"'+$prepared.Directory+'"'),'-ParentId',[string]$oldLauncher.Id)
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while(-not (Test-Path -LiteralPath (Join-Path $prepared.Directory 'ready.txt')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 50}
    Check ((Test-Path -LiteralPath (Join-Path $prepared.Directory 'ready.txt')) -and -not $process.HasExited) 'Helper did not acknowledge its parent handoff'
    Check ((Get-LauncherPackageVersion $portable) -eq 66) 'Package replaced before the old launcher exited'
    $oldLauncher.Kill();$oldLauncher.WaitForExit()
    Check ($process.WaitForExit(20000) -and $process.ExitCode -eq 0) ('Update helper failed: '+$(if(Test-Path -LiteralPath (Join-Path $prepared.Directory 'error.txt')){Get-Content -LiteralPath (Join-Path $prepared.Directory 'error.txt') -Raw}))
    Check ((Get-LauncherPackageVersion $portable) -eq 67) 'New version not installed'
    Check ([IO.File]::ReadAllText((Join-Path $portable 'README.md')) -eq 'Fixture v67') 'Altered staging file installed'
    $backups=@(Get-ChildItem -LiteralPath $testRoot -Directory -Filter 'Portable launcher with spaces.previous-*')
    Check ($backups.Count -eq 1 -and (Get-LauncherPackageVersion $backups[0].FullName) -eq 66) 'Old version not preserved'
    Check ([IO.File]::ReadAllText((Join-Path $backups[0].FullName 'personal-note.txt')) -eq 'retain in backup') 'Extra user file lost'
    Check ([IO.File]::ReadAllText($identity) -eq 'unchanged identity') 'Invitation identity changed'
    Check (-not (Test-Path -LiteralPath $prepared.Directory)) 'Completed work directory not cleaned'
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while(-not (Test-Path -LiteralPath (Join-Path $portable 'launcher\restart-proof.txt')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 50}
    Check (Test-Path -LiteralPath (Join-Path $portable 'launcher\restart-proof.txt')) 'New launcher process not restarted from its installed path'

    Write-Output "$passed updater checks passed, including a separate helper process, package replacement, backup and preserved invitation. No GitHub writes or game changes."
}finally{
    $env:LOCALAPPDATA=$oldLocal
    $env:TF3MP_UPDATE_FIXTURE_GAME=''
    $env:TF3MP_UPDATE_FIXTURE_MOVE_FAIL=''
    if($process -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
    if($oldLauncher -and -not $oldLauncher.HasExited){$oldLauncher.Kill();$oldLauncher.WaitForExit()}
    $full=[IO.Path]::GetFullPath($testRoot)
    if($full.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

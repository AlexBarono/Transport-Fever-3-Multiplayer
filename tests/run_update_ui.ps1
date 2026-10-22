$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\update.ps1')
. (Join-Path $PSScriptRoot '..\tools\update-view.ps1')
$script:passed=0
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
function Update-Fields {}
function Write-LauncherLog($message){$script:notices+=$message}
function Test-GameRunning {return $script:fixtureGame}
function Start-LauncherUpdateApply {$script:applyCalls++}
function Wait-Update {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($script:updateJob){
        if($clock.Elapsed.TotalSeconds -gt 15){throw 'Update job timed out'}
        Update-LauncherUpdateJob;Start-Sleep -Milliseconds 50
    }
}
$directory=Join-Path $env:TEMP ('tf3mp-update-ui-'+[guid]::NewGuid().ToString('N'))
$Root=Join-Path $directory 'portable';$Preview=$false
$script:fixtureGame=$false;$script:notices=@();$script:applyCalls=0
$script:launcherClosing=$false;$script:transferBusy=$false;$script:liveBusy=$false;$script:lobbyPreparing=$false
$script:lobbyPhase='idle';$script:lobbyJob=$null;$script:presence=$null;$script:lobby=$null;$script:internetTunnel=$null
$updateStatus=[pscustomobject]@{Text=''}
[void][IO.Directory]::CreateDirectory((Join-Path $Root 'tools'))
[void][IO.Directory]::CreateDirectory((Join-Path $Root 'launcher'))
[void][IO.Directory]::CreateDirectory((Join-Path $Root 'mods/mp_probe/content/mp_probe'))
try{
    Set-Content -LiteralPath (Join-Path $Root 'Start.bat') -Value '@echo off'
    Set-Content -LiteralPath (Join-Path $Root 'launcher/launcher.ps1') -Value '# fixture'
    Set-Content -LiteralPath (Join-Path $Root 'mods/mp_probe/content/mp_probe/main.script.lua') -Value 'main.PROBE_VERSION = 66'
    $library=Join-Path $Root 'tools/update.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\tools\update.ps1') -Destination $library
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\tools\apply-update.ps1') -Destination (Join-Path $Root 'tools/apply-update.ps1')
    $fixture=@'

function Get-LauncherUpdate([int]$CurrentVersion){
    if($env:TF3MP_UI_FIXTURE_FAIL -eq '1'){throw 'Scripted offline response'}
    Read-LauncherUpdateManifest @{schema=1;version=67;bytes=1024;sha256=('a'*64)} $CurrentVersion
}
function Prepare-LauncherUpdate([string]$Root,$Update,[string]$ZipPath,[string]$WorkDirectory){
    [void][IO.Directory]::CreateDirectory($WorkDirectory)
    [pscustomobject]@{Version=67;Directory=$WorkDirectory}
}
'@
    Add-Content -LiteralPath $library -Value $fixture -Encoding UTF8
    Start-LauncherUpdateCheck
    Check ($script:updateBusy -and [bool]$script:updateJob) 'Update check blocks or failed to start a background job'
    Wait-Update
    Check (-not $script:updateBusy -and $script:updateInfo.Available -and $updateStatus.Text -like '*67*') 'Release information not displayed'
    Start-LauncherUpdateCheck;Wait-Update
    Check ($script:updatePrepared.Version -eq 67 -and $script:applyCalls -eq 1) 'Online installation requires an extra installation click'
    Check ((Get-LauncherPackageVersion $Root) -eq 66) 'UI fixture unexpectedly installed a package'
    $work=$script:updateWork;Stop-LauncherUpdateJob
    Check (-not (Test-Path -LiteralPath $work)) 'Closing launcher leaves a prepared job behind'
    $script:updatePrepared=$null;$script:updateWork=''

    $script:fixtureGame=$true
    Start-LauncherUpdatePreparation 'fixture.zip'
    Check (-not $script:updateJob -and $updateStatus.Text -like '*TF3*') 'UI permits installation while game runs'
    $script:fixtureGame=$false;$script:presence=[pscustomobject]@{Connected=$true}
    Start-LauncherUpdatePreparation 'fixture.zip'
    Check (-not $script:updateJob -and $updateStatus.Text -like '*Sitzung*') 'UI permits installation during a connected session'
    $script:presence=$null;$script:updateInfo=$null
    $env:TF3MP_UI_FIXTURE_FAIL='1'
    Start-LauncherUpdateCheck;Wait-Update
    Check (-not $script:updateBusy -and $script:notices -like '*Scripted offline response*') 'Network failure leaves the UI locked or unexplained'
    $env:TF3MP_UI_FIXTURE_FAIL=''
    $Preview=$true;Start-LauncherUpdateCheck
    Check (-not $script:updateJob) 'Preview starts an update request'
    Write-Output "$passed updater UI checks passed (real background jobs; release/download results and restart mocked)."
}finally{
    Stop-LauncherUpdateJob;$env:TF3MP_UI_FIXTURE_FAIL=''
    $full=[IO.Path]::GetFullPath($directory)
    if($full.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

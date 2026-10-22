$script:updateJob=$null
$script:updateBusy=$false
$script:updateInfo=$null
$script:updatePrepared=$null
$script:updateWork=''
$script:updateApplying=$false

function Get-LauncherCurrentUpdateBlock {
    $busy=$script:transferBusy -or $script:liveBusy -or $script:lobbyPreparing -or $script:lobbyPhase -in 'starting','started' -or [bool]$script:lobbyJob
    $connected=($script:presence -and $script:presence.Connected) -or ($script:lobby -and $script:lobby.Connected) -or
        ($script:internetTunnel -and $script:internetTunnel.GameChannelConnected)
    return Get-LauncherUpdateBlockReason (Test-GameRunning) $busy $connected
}

function Start-LauncherUpdateCheck {
    if($Preview -or $script:updateBusy -or $script:launcherClosing){return}
    if($script:updatePrepared){Start-LauncherUpdateApply;return}
    if($script:updateInfo -and $script:updateInfo.Available){Start-LauncherUpdatePreparation;return}
    $script:updateBusy=$true;$script:updateOperation='check'
    $updateStatus.Text='Suche nach einer neuen Version ...'
    try{
        $library=Join-Path $Root 'tools\update.ps1';$version=Get-LauncherPackageVersion $Root
        $script:updateJob=Start-Job -ArgumentList $library,$version -ScriptBlock {
            param($library,$version);$ErrorActionPreference='Stop';. $library;Get-LauncherUpdate $version
        }
    }catch{$script:updateBusy=$false;Write-LauncherLog $_.Exception.Message;$updateStatus.Text='Updateprüfung konnte nicht starten.'}
    Update-Fields
}

function Start-LauncherUpdatePreparation([string]$ZipPath='') {
    if($Preview -or $script:updateBusy -or $script:launcherClosing){return}
    $blocked=Get-LauncherCurrentUpdateBlock
    if($blocked){Write-LauncherLog $blocked;$updateStatus.Text=$blocked;return}
    try{$target=Assert-LauncherUpdateRoot $Root}catch{Write-LauncherLog $_.Exception.Message;return}
    $script:updateWork=Join-Path (Split-Path -Parent $target) ('.tf3mp-update-'+[guid]::NewGuid().ToString('N'))
    $script:updateBusy=$true;$script:updateOperation='prepare'
    $script:updateAfterPrepare=-not [bool]$ZipPath
    $updateStatus.Text=if($ZipPath){'Prüfe Update-ZIP ...'}else{'Lade und prüfe das Update ...'}
    $library=Join-Path $Root 'tools\update.ps1'
    $online=if($ZipPath){$null}else{$script:updateInfo}
    try{
        $script:updateJob=Start-Job -ArgumentList $library,$Root,$online,$ZipPath,$script:updateWork -ScriptBlock {
            param($library,$root,$online,$zip,$work);$ErrorActionPreference='Stop';. $library;Prepare-LauncherUpdate $root $online $zip $work
        }
    }catch{$script:updateBusy=$false;Write-LauncherLog $_.Exception.Message;$updateStatus.Text='Updatevorbereitung konnte nicht starten.'}
    Update-Fields
}

function Update-LauncherUpdateJob {
    if(-not $script:updateJob -or $script:updateJob.State -in 'Running','NotStarted'){return}
    $job=$script:updateJob;$script:updateJob=$null;$apply=$false
    try{
        $result=Receive-Job -Job $job -ErrorAction Stop
        if($job.State -ne 'Completed' -or -not $result){throw 'Der Updatevorgang wurde nicht abgeschlossen.'}
        if($script:updateOperation -eq 'check'){
            $script:updateInfo=$result
            $updateStatus.Text=if($result.Available){"Version $($result.Version) ist verfügbar. Zum Installieren klicken."}else{"Version $(Get-LauncherPackageVersion $Root) ist aktuell."}
            if($result.Available){Write-LauncherLog "Update v$($result.Version) ist verfügbar. Beide PCs benötigen dasselbe Paket."}
        }else{
            $script:updatePrepared=$result
            $apply=$script:updateAfterPrepare
            $updateStatus.Text="Version $($result.Version) ist geprüft. Mit einem Klick installieren und neu starten."
            Write-LauncherLog "Update v$($result.Version) ist vorbereitet. Zum Installieren links auf 'Update installieren' klicken. Der vorherige Paketordner wird gesichert."
        }
    }catch{
        $updateStatus.Text='Update fehlgeschlagen. Details stehen im Protokoll.'
        Write-LauncherLog ('Update: '+$_.Exception.Message)
        if($script:updateWork -and -not $script:updatePrepared){
            try{Remove-LauncherUpdateWork $Root $script:updateWork}catch{}
            $script:updateWork=''
        }
    }finally{
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $script:updateBusy=$false;Update-Fields
    }
    if($apply){Start-LauncherUpdateApply}
}

function Start-LauncherUpdateApply {
    if(-not $script:updatePrepared -or $Preview -or $script:updateApplying){return}
    $blocked=Get-LauncherCurrentUpdateBlock
    if($blocked){Write-LauncherLog $blocked;$updateStatus.Text=$blocked;return}
    $script:updateBusy=$true;$script:updateApplying=$true;Update-Fields
    try{
        $directory=$script:updatePrepared.Directory
        $helper=Join-Path $directory 'apply-update.ps1'
        $ready=Join-Path $directory 'ready.txt'
        if(Test-Path -LiteralPath $ready){Remove-Item -LiteralPath $ready -Force}
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$helper+'"'),'-Directory',('"'+$directory+'"'),'-ParentId',[string]$PID)
        $process=Start-Process (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -WorkingDirectory $directory -ArgumentList $arguments -PassThru
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while(-not (Test-Path -LiteralPath $ready) -and -not $process.HasExited -and $clock.Elapsed.TotalSeconds -lt 8){
            [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 50
        }
        if(-not (Test-Path -LiteralPath $ready)){
            if(-not $process.HasExited){$process.Kill();$process.WaitForExit()}
            throw 'Der Updatehelfer konnte nicht starten. Das bestehende Paket bleibt erhalten.'
        }
        Write-LauncherLog "Installiere v$($script:updatePrepared.Version). Der Launcher startet gleich neu."
        $form.Close()
    }catch{
        $script:updateApplying=$false;$script:updateBusy=$false
        $updateStatus.Text='Update konnte nicht starten. Details stehen im Protokoll.'
        Write-LauncherLog $_.Exception.Message;Update-Fields
    }
}

function Stop-LauncherUpdateJob {
    if($script:updateJob){
        Stop-Job -Job $script:updateJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:updateJob -Force -ErrorAction SilentlyContinue
        $script:updateJob=$null
    }
    if($script:updateWork -and -not $script:updateApplying){try{Remove-LauncherUpdateWork $Root $script:updateWork}catch{}}
}

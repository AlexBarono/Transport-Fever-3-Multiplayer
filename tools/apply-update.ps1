param([Parameter(Mandatory=$true)][string]$Directory,[int]$ParentId=0,[switch]$NoRestart)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'update.ps1')
$root='';$backup='';$moved=$false;$installed=$false
try{
    $job=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    if($job -cne [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')){throw 'Der Updatehelfer muss aus seinem Arbeitsordner gestartet werden.'}
    $plan=Get-Content -LiteralPath (Join-Path $job 'plan.json') -Raw | ConvertFrom-Json
    $root=Assert-LauncherUpdateRoot $plan.Root
    if($plan.Schema -ne 1 -or (Split-Path -Parent $job) -cne (Split-Path -Parent $root) -or
        (Split-Path -Leaf $job) -notmatch '^\.tf3mp-update-[0-9a-f]{32}$'){throw 'Ungültiger Updateauftrag.'}
    [IO.File]::WriteAllText((Join-Path $job 'ready.txt'),'ready')
    if($ParentId -gt 0){
        $parent=Get-Process -Id $ParentId -ErrorAction SilentlyContinue
        if($parent -and -not $parent.WaitForExit(120000)){throw 'Der alte Launcher wurde nicht rechtzeitig geschlossen.'}
    }
    if(Get-Process -Name 'TransportFever3' -ErrorAction SilentlyContinue){throw 'TF3 läuft; das Update wurde nicht installiert.'}
    if((Get-LauncherPackageVersion $root) -ne $plan.PreviousVersion){throw 'Der Paketordner wurde inzwischen geändert.'}
    $zip=Join-Path $job 'package.zip';$stage=Join-Path $job 'package'
    if((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $plan.Sha256){throw 'Das vorbereitete Update wurde verändert.'}
    [void](Get-LauncherUpdateArchive $zip $plan.PreviousVersion $plan.Version)
    # Re-extract the verified ZIP, so modified staging files cannot be executed.
    # The stage is inside this validated, exclusively created job directory.
    $stageFull=[IO.Path]::GetFullPath($stage)
    if(-not $stageFull.StartsWith($job+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-UpdateLink (Get-Item -LiteralPath $stage -Force))){throw 'Ungültiger Update-Zielordner.'}
    $linked=Get-ChildItem -LiteralPath $stage -Recurse -Force | Where-Object {Test-UpdateLink $_} | Select-Object -First 1
    if($linked){throw 'Verknüpfter Inhalt im vorbereiteten Update.'}
    Remove-Item -LiteralPath $stageFull -Recurse -Force
    [void][IO.Directory]::CreateDirectory($stageFull)
    Expand-LauncherUpdate $zip $stageFull
    $backup=$root+'.previous-v'+$plan.PreviousVersion+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    # Both moves stay within the same, checked parent directory and volume.
    if((Split-Path -Parent $backup) -cne (Split-Path -Parent $root) -or (Test-Path -LiteralPath $backup)){throw 'Ungültiger Sicherungsordner.'}
    Move-Item -LiteralPath $root -Destination $backup -ErrorAction Stop;$moved=$true
    Move-Item -LiteralPath $stageFull -Destination $root -ErrorAction Stop;$installed=$true
    $result=@{Version=$plan.Version;Backup=$backup;Utc=[DateTime]::UtcNow.ToString('o')}
    $state=Join-Path $env:LOCALAPPDATA 'TF3MP\Updates'
    [void][IO.Directory]::CreateDirectory($state)
    $result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $state 'last-update.json') -Encoding UTF8
    [IO.File]::WriteAllText((Join-Path $job 'completed.txt'),'ok')
    if(-not $NoRestart){
        $executable=Join-Path $PSHOME 'powershell.exe'
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',('"'+(Join-Path $root 'launcher\launcher.ps1')+'"'))
        Start-Process $executable -WindowStyle Hidden -WorkingDirectory $root -ArgumentList $arguments
    }
    Set-Location -LiteralPath $env:TEMP
    [Environment]::CurrentDirectory=$env:TEMP
    try{Remove-LauncherUpdateWork $root $job}catch{[IO.File]::WriteAllText((Join-Path $job 'cleanup.txt'),$_.Exception.Message)}
}catch{
    $problem=$_.Exception.Message
    if($moved -and -not $installed -and -not (Test-Path -LiteralPath $root)){
        try{[IO.Directory]::Move($backup,$root)}catch{$problem+=' Die Sicherung liegt unter '+$backup}
    }
    if(Test-Path -LiteralPath $Directory){[IO.File]::WriteAllText((Join-Path $Directory 'error.txt'),$problem)}
    if(-not $NoRestart){
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show(('Update fehlgeschlagen: '+$problem+"`r`nDer vorherige Paketstand ist weiterhin vorhanden."),'TF3 Multiplayer','OK','Error')
    }
    Write-Error $problem
    exit 1
}

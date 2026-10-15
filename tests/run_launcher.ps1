$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\launcher\launcher.ps1') -LibraryOnly
$passed=0
$translated=Get-WorldDifferenceText 'hcon,hpos,hcargo,htown,loan,future'
if($translated -ne 'Bauwerke, Fahrzeugpositionen, Fracht, Städte, Kredite, future'){throw 'World fields are not explained correctly'}
$passed++
foreach($entry in @(@('100.80.12.4',47800),@('100.80.12.4:47900',47900),@('tf3mp://100.80.12.4:47801',47801))) {
    $value=Parse-JoinAddress $entry[0] '47800'
    if($value.Address -ne '100.80.12.4' -or $value.Port -ne $entry[1]){throw 'Endpoint parse failed'}
    $passed++
}
foreach($entry in @('::1','vpn.example.com','127.1','0.0.0.0','10.0.0.1:99999','10.0.0.1:1','10.0.0.1:abc','garbage')) {
    $rejected=$false
    try{Parse-JoinAddress $entry '47800' | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw "Invalid address accepted: $entry"}
    $passed++
}
$script:internetNeedsSetup=$true
$rejected=$false; try { Assert-LauncherInternetMode 'host' 47800 '' } catch { $rejected=$true }
if(-not $rejected) { throw 'A restarted Internet host silently reverted to raw UDP' }; $passed++
$rejected=$false; try { Resolve-LauncherEndpoint '127.0.0.1' '47800' | Out-Null } catch { $rejected=$true }
if(-not $rejected) { throw 'A restarted Internet client reused a dead local tunnel' }; $passed++
$value=Resolve-LauncherEndpoint '100.80.12.4:47800' '47800'
if($script:internetNeedsSetup -or $value.Address -ne '100.80.12.4') { throw 'Explicit VPN switch failed' }; $passed++
foreach($script in @('launcher\launcher.ps1','launcher\view.ps1','launcher\lobby-ui.ps1','tools\lobby.ps1','tools\session.ps1','tools\resync.ps1','tools\save-transfer.ps1','tools\transport.ps1','tools\fake-partner.ps1','tools\same-spot.ps1','tools\internet.ps1','tools\internet-view.ps1','tools\internet-firewall.ps1')) {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $script),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors | Out-String)}
    $passed++
}
$receiver=New-MpReceiver
$manifest=Get-Content (Join-Path $Root 'mods\mp_probe\_content.json') -Raw | ConvertFrom-Json
$actual=@(Get-ChildItem (Join-Path $Root 'mods\mp_probe\content\mp_probe') -File | ForEach-Object { "mp_probe/$($_.Name)" } | Sort-Object)
if(Compare-Object @($manifest.files | Sort-Object) $actual){throw 'Mod content manifest does not match its source files'}
$passed++
$payload='B5 '+('x'*100000)
$send=New-MpSend 'test.1' $payload
$saved=$null
while(-not $send.Done) {
    $packet=Get-MpSendPacket $send
    if($packet.Length -gt 850){throw 'UDP fragment too long'}
    $data=Read-MpDataPacket $receiver $packet
    if($data.Text){$saved=$data.Text}
    Confirm-MpSend $send $data.Reply
}
if($saved -ne $payload){throw 'Fragment round trip failed'}
$passed++
$duplicate=Read-MpDataPacket $receiver 'TF3MP/1 FRAG test.1 0 1 abc'
if($duplicate.Text -or $duplicate.Reply -ne 'TF3MP/1 DONE test.1 OK'){throw 'Duplicate replay'}
$passed++
$send=New-MpSend 'test.2' 'B5 failure'
$rejected=$false
try{Confirm-MpSend $send 'TF3MP/1 DONE test.2 FAIL'}catch{$rejected=$true}
if(-not $rejected){throw 'Game failure was ignored'}
$passed++
$record=Get-SameSpotRecording @('Loading game from file a.sav','[mp_probe]net upload 1 0 2 B5 abc','[mp_probe]net upload 1 1 2 def','Loading game from file a.sav')
if($record.Lines.Count -ne 1 -or $record.Lines[0] -ne 'B5 abcdef'){throw 'Large replay recording failed'}
$passed++
$missing=Join-Path $env:TEMP ('tf3mp-missing-'+[Guid]::NewGuid().ToString('N')+'.txt')
$rejected=$false
try{Read-ReplayRecording $missing | Out-Null}catch{$rejected=$_.Exception.Message -like 'Die gespeicherte Aufnahme fehlt:*'}
if(-not $rejected){throw 'Missing imported recording was not clearly rejected'}
$passed++
$testLog=Join-Path $env:TEMP ('tf3mp-replay-'+[Guid]::NewGuid().ToString('N')+'.txt')
try {
    [IO.File]::WriteAllLines($testLog,@('Loading game from file original','[mp_probe]net send B5 demo'))
    $rejected=$false
    try{Read-ReplayRecording $testLog | Out-Null}catch{$rejected=$_.Exception.Message -like 'Die gespeicherte Aufnahme konnte nicht gelesen werden:*'}
    if(-not $rejected){throw 'An incomplete imported recording was accepted'}
    $passed++
    [IO.File]::AppendAllText($testLog,"Loading game from file original`r`n")
    $import=Read-ReplayRecording $testLog
    if($import.Save -ne 'original' -or $import.Lines.Count -ne 1 -or $import.Lines[0] -ne 'B5 demo' -or $import.Source -ne $testLog){throw 'Imported recording lost its source or actions'}
    $passed++
    $import.Current='historical-other-save'
    $started=[datetime]::Parse('2026-10-08T12:00:00Z').ToUniversalTime()
    $live=@('[2026-10-08 12:00:03Z - MESSAGE] Loading game from file original')
    $current=Get-ReplayRecordingForGame $import $live $started
    if($current.Current -ne 'original' -or $current.Lines[0] -ne 'B5 demo'){throw 'Matching current live save was rejected'}
    $passed++
    foreach($badLive in @(
        @{ Lines=@('[2026-10-08 12:00:03Z - MESSAGE] Loading game from file other'); Why='wrong live save' },
        @{ Lines=@('game starting'); Why='no live save loaded' },
        @{ Lines=@('[2026-10-08 11:59:55Z - MESSAGE] Loading game from file original'); Why='stale previous game log' },
        @{ Lines=@('Loading game from file original'); Why='unknown log session' },
        @{ Lines=@($live[0],'[2026-10-08 12:00:05Z - MESSAGE] Loading game from file other'); Why='latest live save differs' }
    )) {
        $rejected=$false
        try{Get-ReplayRecordingForGame $import $badLive.Lines $started | Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw "Imported replay accepted $($badLive.Why)"}
        $passed++
    }
    if($import.Current -ne 'historical-other-save'){throw 'Live validation modified the saved recording'}
    $passed++
} finally { Remove-Item -LiteralPath $testLog -Force -ErrorAction SilentlyContinue }
$actualReplay=Read-ReplayRecording (Join-Path $Root 'tests\fixtures\run29-replay.log')
if($actualReplay.Save -ne 'Det' -or $actualReplay.Lines.Count -ne 21){throw 'The saved run29 replay no longer contains the 21 original actions'}
$passed++
$originalGameRunning=(Get-Item Function:\Test-GameRunning).ScriptBlock
function Test-GameRunning { return $false }
try {
    foreach($mode in 'host','client') {
        $rejected=$false
        try{Install-All 'unused-missing-directory' $mode 47800 '127.0.0.1' '' | Out-Null}catch{$rejected=$_.Exception.Message -like 'Bitte zuerst den gemeinsamen Spielstand*'}
        if(-not $rejected){throw "Real $mode installation accepted missing prepared session"}
        $passed++
    }
    foreach($entry in @(@('host','samespot'),@('client','fakehost'),@('loopback',''))) {
        $rejected=$false
        try{Install-All 'unused-missing-directory' $entry[0] 47800 '127.0.0.1' '' $entry[1] | Out-Null}catch{$rejected=$_.Exception.Message -like 'Im Spielordner fehlt alut.dll:*'}
        if(-not $rejected){throw 'An explicit local test unexpectedly required a shared session'}
        $passed++
    }
} finally { Set-Item Function:\Test-GameRunning $originalGameRunning }
$integrationRoot=Join-Path $env:TEMP ('tf3mp-launcher-session-'+[Guid]::NewGuid().ToString('N'))
$originalSource=$ModSource; $originalDll=$ProxyDll; $originalPublic=$env:PUBLIC; $originalLocalAppData=$env:LOCALAPPDATA
try {
    $game=Join-Path $integrationRoot 'game'; $fixtureSteam=Join-Path $integrationRoot 'steam'
    $save=Join-Path $fixtureSteam 'userdata\test\3493540\local\save'
    $installed=Join-Path $fixtureSteam 'userdata\test\3493540\local\staging_area\mp_probe'
    $ModSource=Join-Path $integrationRoot 'source'; $ProxyDll=Join-Path $integrationRoot 'proxy.dll'
    $env:PUBLIC=Join-Path $integrationRoot 'public'; $env:LOCALAPPDATA=Join-Path $integrationRoot 'appdata'
    foreach($dir in @($game,$save,$installed,$ModSource)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
    [IO.File]::WriteAllText((Join-Path $game 'TransportFever3.exe'),'fixture game')
    [IO.File]::WriteAllText($ProxyDll,'fixture proxy')
    Copy-Item -LiteralPath $ProxyDll -Destination (Join-Path $game 'alut.dll')
    [IO.File]::WriteAllText((Join-Path $ModSource 'mod.lua'),'fixture mod')
    Copy-Item -LiteralPath (Join-Path $ModSource 'mod.lua') -Destination $installed
    $savePath=Join-Path $save 'Original.sav'; [IO.File]::WriteAllText($savePath,'fixture save')
    $manifest=Get-LauncherManifest $game $fixtureSteam
    $session=New-MultiplayerSession -Manifest $manifest -SavePath $savePath
    Save-PreparedSession -Path (Join-Path $game 'alut_session.json') -Session $session -SavePath $savePath | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'alut_proxy.ini') -Encoding ASCII -Value (@('[net]','mode=host','port=47800')+@(Get-SessionIniLines $session))
    $current=Get-LaunchSession $game $fixtureSteam -Installed
    if($current.SessionId -ne $session.SessionId){throw 'Matching prepared and installed session did not validate'}
    $passed++
    if((Assert-LauncherSavePath $savePath $save) -ne $savePath){throw 'The actual Steam save was rejected'}
    $passed++
    $backupPath=Join-Path $integrationRoot 'Original.sav'; [IO.File]::WriteAllText($backupPath,'a different same-name save')
    $rejected=$false
    try{Assert-LauncherSavePath $backupPath $save | Out-Null}catch{$rejected=$_.Exception.Message -like '*gleichnamige Datei*'}
    if(-not $rejected){throw 'Offering an external same-name save bypassed source binding'}
    $passed++
    $outside=New-MultiplayerSession -Manifest $manifest -SavePath $backupPath
    Save-PreparedSession -Path (Join-Path $game 'alut_session.json') -Session $outside -SavePath $backupPath | Out-Null
    $rejected=$false
    try{Get-LaunchSession $game $fixtureSteam | Out-Null}catch{$rejected=$_.Exception.Message -like '*gleichnamige Datei*'}
    if(-not $rejected){throw 'Launching with an external prepared save bypassed source binding'}
    $passed++
    Save-PreparedSession -Path (Join-Path $game 'alut_session.json') -Session $session -SavePath $savePath | Out-Null
    [IO.File]::AppendAllText((Join-Path $installed 'mod.lua'),' tampered')
    $rejected=$false
    try{Get-LaunchSession $game $fixtureSteam -Installed | Out-Null}catch{$rejected=$_.Exception.Message -like '*Multiplayer-Paket unterscheidet sich*'}
    if(-not $rejected){throw 'Changed installed mod bypassed launch check'}
    $passed++
    Copy-Item -LiteralPath (Join-Path $ModSource 'mod.lua') -Destination $installed -Force
    Set-Content -LiteralPath (Join-Path $game 'alut_proxy.ini') -Encoding ASCII -Value @('[net]','mode=host','port=47800')
    $rejected=$false
    try{Get-LaunchSession $game $fixtureSteam -Installed | Out-Null}catch{$rejected=$_.Exception.Message -like 'Die installierte Sitzung ist veraltet*'}
    if(-not $rejected){throw 'Old installed INI bypassed launch check'}
    $passed++
    $script:forceNewSession=$true
    $rejected=$false
    try{Get-LaunchSession $game $fixtureSteam | Out-Null}catch{$rejected=$_.Exception.Message -like '*Neuabgleich abzuschließen*'}
    if(-not $rejected){throw 'A pending recovery reused the previous session'}
    $passed++
    if((Get-RecoveryInstructions host) -notlike '*frischen Stand automatisch*beide offenen Spiele*' -or (Get-RecoveryInstructions client) -notlike '*wartet, bis der Gastgeber*'){throw 'Recovery omitted role-specific save instructions'}
    $passed++
} finally {
    $ModSource=$originalSource; $ProxyDll=$originalDll; $env:PUBLIC=$originalPublic; $env:LOCALAPPDATA=$originalLocalAppData; $script:forceNewSession=$false
    $resolvedIntegration=[IO.Path]::GetFullPath($integrationRoot)
    $resolvedTemp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolvedIntegration.StartsWith($resolvedTemp,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped TEMP'}
    if(Test-Path -LiteralPath $resolvedIntegration){Remove-Item -LiteralPath $resolvedIntegration -Recurse -Force}
}
$statusRoot=Join-Path $env:TEMP ('tf3mp-ready-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($statusRoot) | Out-Null
$originalGameRunning=(Get-Item Function:\Test-GameRunning).ScriptBlock
function Test-GameRunning { return $true }
try {
    foreach($case in @(
        @{ Extra='ready=0'; Detail='loaded=1'; Expected='*Mod noch nicht bereit*' },
        @{ Extra='ready=1'; Detail="compatible=1`r`npeer_ready=0"; Expected='*Partner erreicht*' },
        @{ Extra='ready=1'; Detail="compatible=0`r`nhello_received=0"; Expected='*keine UDP-Antwort*' }
    )) {
        [IO.File]::WriteAllText((Join-Path $statusRoot 'alut_proxy.status'),"protocol=3`r`nmode=client`r`nconnected=0`r`noutbox=0`r`ninbox=0`r`n$($case.Extra)`r`n$($case.Detail)")
        if((Get-SessionStatus $statusRoot).Text -notlike $case.Expected) { throw 'Readiness failure was not distinguished' }; $passed++
    }
    $queue=@{outbox='53';inbox='0';outbox_actions='21';inbox_actions='0';outbox_diagnostics='32';inbox_diagnostics='0'}
    if((Get-ReplayQueueText $queue) -ne '21 Spielaktion(en) warten  |  32 Diagnosebericht(e) warten'){throw 'World reports were counted as game actions'}; $passed++
    $legacy=@{outbox='53';inbox='0'}
    if((Get-ReplayQueueText $legacy) -ne '53 Einträge warten'){throw 'Legacy combined count claimed a game action count'}; $passed++
    $bad=$queue.Clone(); $bad.outbox_actions='-1'
    if((Get-ReplayQueueText $bad) -ne '53 Einträge warten'){throw 'Malformed queue counts were trusted'}; $passed++
    $waiting=@{mode='client';order_side='C';order_phase='active';order_token='62420-180487375.89';order_age_ms='600000';order_progress_age_ms='30000';peer_work_token='62420-180487375.89';peer_work_phase='callbacks'}
    if((Get-ReplayWaitText $waiting) -notlike '*TF3-Rückmeldung beim Mitspieler*62420-180487375.89*'){throw 'Remote callback wait not identified'}; $passed++
    $waiting.order_progress_age_ms='1000'
    if(Get-ReplayWaitText $waiting){throw 'A long but progressing action was marked stuck'}; $passed++
    $waiting.order_progress_age_ms='60000'; $waiting.peer_work_token='previous.1'
    if((Get-ReplayWaitText $waiting) -notlike '*Ausführungsbestätigung beim Mitspieler*'){throw 'Stale remote work diagnosis reused'}; $passed++
    $waiting.order_side='H'; $waiting.work_token=$waiting.order_token; $waiting.work_phase='weld'
    if((Get-ReplayWaitText $waiting) -notlike '*Anschlussprüfung auf diesem PC*'){throw 'Local replay side was misidentified'}; $passed++
    $waiting.order_phase='idle'
    if(Get-ReplayWaitText $waiting){throw 'Completed order stayed marked as stalled'}; $passed++
    $waiting.order_phase='active'; $waiting.order_stage='waiting_payload'
    if((Get-ReplayWaitText $waiting) -notlike '*Aktionsdaten vom Mitspieler*'){throw 'Missing payload was reported as an engine callback wait'}; $passed++
    $waiting.order_phase='finish'; $waiting.order_stage='waiting_release_ack'
    if((Get-ReplayWaitText $waiting) -notlike '*Abschlussbestätigung beim Mitspieler*'){throw 'Order release acknowledgement was reported as an engine callback wait'}; $passed++
    $statusValues=$queue.Clone()
    foreach($pair in @{protocol='3';mode='client';connected='1';ready='1';peer_ready='1';world='diff';world_fields='hpos,htown';order_phase='active';order_side='C';order_token='incoming.89';order_progress_age_ms='40000'}.GetEnumerator()){$statusValues[$pair.Key]=$pair.Value}
    [IO.File]::WriteAllLines((Join-Path $statusRoot 'alut_proxy.status'),[string[]]@($statusValues.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }))
    $status=Get-SessionStatus $statusRoot
    if($status.Color -ne 'warning' -or $status.Text -notlike '*Ausführungsbestätigung*21 Spielaktion*32 Diagnosebericht*' -or $status.Text -like '*Abgleich erforderlich*'){throw 'Stalled replay diagnosis was hidden behind world drift'}; $passed++
} finally {
    Set-Item Function:\Test-GameRunning $originalGameRunning
    Remove-Item -LiteralPath (Join-Path $statusRoot 'alut_proxy.status') -Force
    Remove-Item -LiteralPath $statusRoot -Force
}
Write-Host "$passed launcher/protocol tests passed, 0 failed"

# Only temporary resource fixtures. Never installs into or stops the real game.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'launcher/launcher.ps1') -LibraryOnly
$passed=0
function Check($ok,$message){if(-not $ok){throw $message}; $script:passed++}
$fixture=Join-Path $env:TEMP ('tf3mp-autoload-'+[Guid]::NewGuid().ToString('N'))
$base=Join-Path $fixture 'base'; $content=Join-Path $base 'content'
[void][IO.Directory]::CreateDirectory($content)
$archive=Join-Path $content 'gui.zip'; $manifest=Join-Path $base '_content.json'
$zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try{
    $entry=$zip.CreateEntry('gui/menu/main_menu.tl'); $writer=New-Object IO.StreamWriter($entry.Open())
    $writer.Write('local commonMenuParams : CommonMenuParams = {}'); $writer.Dispose()
    $entry=$zip.CreateEntry('unchanged.bin'); $stream=$entry.Open(); $stream.WriteByte(42); $stream.Dispose()
}finally{$zip.Dispose()}
$index='{"archives":[{"fileName":"gui.zip","entries":[{"fileName":"gui/menu/main_menu.tl","headerOffset":123,"fileSize":44},{"fileName":"unchanged.bin","headerOffset":987,"fileSize":1}]}],"files":["original.lua"]}'
[IO.File]::WriteAllText($manifest,$index)
$original=Get-SessionFileHash $manifest; $zipHash=Get-SessionFileHash $archive
try{
    Request-GameAutoload $fixture 'Meine Welt.2 ä'
    Check ((Get-SessionFileHash $archive) -eq $zipHash) 'Game archive changed: native header offsets would be invalid'
    $patched=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    Check ($patched.archives[0].entries.Count -eq 1 -and $patched.archives[0].entries[0].headerOffset -eq 987) 'Unrelated resource offset changed'
    Check ($patched.files -contains 'gui/menu/main_menu.tl' -and $patched.files -contains 'original.lua') 'Loose menu resource not indexed'
    $loose=Join-Path $content 'gui/menu/main_menu.tl'
    Check ([IO.File]::ReadAllText($loose).Contains('TF3MP_AUTOLOAD_V53')) 'Menu bootstrap missing'
    $hex=([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes('Meine Welt.2 ä'))).Replace('-','').ToLowerInvariant()
    Check ([IO.File]::ReadAllText((Join-Path $fixture 'alut_proxy.launch')).Contains("save_hex=$hex")) 'Unicode/dotted save name changed'
    $patchedHash=Get-SessionFileHash $manifest
    Request-GameAutoload $fixture 'Andere Welt'
    Check ((Get-SessionFileHash $manifest) -eq $patchedHash -and (Get-SessionFileHash ($manifest+'.tf3mp-original')) -eq $original) 'Repeated start replaced the original backup'
    Remove-GameAutoload $fixture
    Check ((Get-SessionFileHash $manifest) -eq $original -and -not (Test-Path -LiteralPath $loose)) 'Uninstall did not restore exact original index'
    Check (-not (Test-Path -LiteralPath (Join-Path $fixture 'alut_proxy.launch'))) 'Uninstall leaves an armed launch request'
    Request-GameAutoload $fixture 'Welt'
    [IO.File]::WriteAllText($manifest,$index+' ')
    $updated=Get-SessionFileHash $manifest
    Remove-GameAutoload $fixture
    Check ((Get-SessionFileHash $manifest) -eq $updated) 'Uninstall replaced an updated game index with an old backup'
    [IO.File]::WriteAllText($loose,'another menu mod')
    $rejected=$false;try{Install-GameAutoload $fixture}catch{$rejected=$true}
    Check ($rejected -and [IO.File]::ReadAllText($loose) -eq 'another menu mod') 'Existing menu extension was overwritten'
    foreach($bad in @('../Welt',"World`n",'',('x'*181))){$rejected=$false;try{Request-GameAutoload $fixture $bad}catch{$rejected=$true};Check $rejected 'Invalid launch name accepted'}
    [IO.File]::WriteAllText((Join-Path $fixture 'alut_proxy.log'),"2000-01-01 10:00:00 [42] launcher: autoload failed: stale`r`n$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) [43] launcher: autoload failed: save metadata unavailable")
    Check ((Get-GameAutoloadFailure $fixture ([DateTime]::UtcNow)) -eq 'save metadata unavailable') 'Current automatic-load error is not reported'
    Check ((Get-GameAutoloadFailure $fixture ([DateTime]::UtcNow.AddMinutes(2))) -eq '') 'Old load error is shown in a later launch'
    # Shutdown dispatch uses the tested close/force adapter, only when the game is running.
    $script:fakeRunning=$false; $script:stops=0
    function Test-GameRunning{return $script:fakeRunning}
    function Stop-GameForResync($tick){[void](& $tick 'Beende TF3 für den bestätigten Neuabgleich ...' 0 0); $script:stops++; $script:fakeRunning=$false; return $true}
    Stop-LauncherGameForStart {return $false}; Check ($script:stops -eq 0) 'Stopped an absent game'
    $script:fakeRunning=$true; $script:shutdownMessage=''
    Stop-LauncherGameForStart {param($text,$done,$total) $script:shutdownMessage=$text; return $false}; Stop-LauncherGameForStart {return $false}
    Check ($script:stops -eq 1) 'Running game was not stopped exactly once'
    Check ($script:shutdownMessage -like '*für den gemeinsamen Start*') 'Shutdown progress callback was shadowed or not adapted'
    Write-Output "$passed automatic-start fixture checks passed; real game untouched."
}finally{
    $resolved=[IO.Path]::GetFullPath($fixture); $temp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped TEMP'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

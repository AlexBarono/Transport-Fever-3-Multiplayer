$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\launcher\launcher.ps1') -LibraryOnly
$passed=0
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
function Reject($action,$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Check $failed $message}
$directory=Join-Path $env:TEMP ('tf3mp-friends-'+[guid]::NewGuid().ToString('N'))
$originalLocal=$env:LOCALAPPDATA;$env:LOCALAPPDATA=$directory
try{
    Check (@(Get-LauncherFriends).Count -eq 0) 'Missing address book is not empty'
    $invite=New-InternetInvitation '2001:db8::1' 47801 ('a'*64) ('b'*64)
    $alex=Save-LauncherFriend '  Alex  ' $invite
    Check ($alex.Name -eq 'Alex' -and $alex.Address -eq $invite) 'Name/invitation not saved'
    $friends=@(Get-LauncherFriends)
    Check ($friends.Count -eq 1 -and $friends[0].Id -eq $alex.Id) 'Saved friend cannot be read back'
    $stored=[IO.File]::ReadAllBytes((Get-LauncherFriendsPath))
    Check (-not [Text.Encoding]::UTF8.GetString($stored).Contains($invite) -and -not [Text.Encoding]::UTF8.GetString($stored).Contains('b'*64)) 'Invitation stored in plaintext'
    $updated=Save-LauncherFriend 'alex' (New-InternetInvitation '2001:db8::2' 47801 ('a'*64) ('c'*64))
    Check ($updated.Id -eq $alex.Id -and @(Get-LauncherFriends).Count -eq 1) 'Same name creates a duplicate'
    $bea=Save-LauncherFriend 'Bea' '100.80.12.4'
    Check ($bea.Address -eq '100.80.12.4:47800') 'VPN default port not normalized'
    $renamed=Save-LauncherFriend 'Alex zuhause' $invite $alex.Id
    Check ($renamed.Id -eq $alex.Id -and $renamed.Name -eq 'Alex zuhause') 'Friend rename changes identity'
    Reject {Save-LauncherFriend 'Bea' $invite $alex.Id} 'Duplicate contact name accepted'
    foreach($bad in @('',"Bad`nName",('x'*65))){Reject {Save-LauncherFriend $bad $invite} 'Invalid name accepted'}
    foreach($bad in @('https://example.com','127.0.0.1:47800','garbage',('x'*257))){Reject {Save-LauncherFriend 'Bad' $bad} 'Invalid invitation accepted'}
    Reject {Save-LauncherFriend 'Missing' $invite ([guid]::NewGuid().ToString())} 'Unknown edited friend silently created'
    Remove-LauncherFriend $bea.Id
    Check (@(Get-LauncherFriends).Count -eq 1) 'Friend not removed'
    Remove-LauncherFriend $bea.Id
    Check (@(Get-LauncherFriends).Count -eq 1) 'Repeated removal changed another entry'
    Remove-LauncherFriend $alex.Id
    Check (@(Get-LauncherFriends).Count -eq 0) 'Empty list not persisted'
    [IO.File]::WriteAllBytes((Get-LauncherFriendsPath),[byte[]](1..64))
    Reject {Get-LauncherFriends} 'Corrupted friend file accepted'
    Reject {Save-LauncherFriend 'New' $invite} 'Corrupted list silently overwritten'
    Check ([IO.File]::ReadAllBytes((Get-LauncherFriendsPath)).Length -eq 64) 'Corrupted list replaced'
    $waiting=Get-LauncherCopyState $true $false $true $false $true
    Check ($waiting.Busy -and -not $waiting.Enabled -and $waiting.Text -like '*vorbereitet*') 'Connection wait looks like an unavailable copy action'
    $failed=Get-LauncherCopyState $true $false $false $true $true
    Check (-not $failed.Busy -and -not $failed.Enabled -and $failed.Reason -like '*fehlgeschlagen*') 'Connection error still animates as loading'
    $ready=Get-LauncherCopyState $true $true $false $false $true
    Check ($ready.Enabled -and -not $ready.Busy -and $ready.Text -eq 'Einladung kopieren') 'Ready invitation not copyable'
    $none=Get-LauncherCopyState $true $false $false $false $false
    Check (-not $none.Busy -and $none.Reason -like '*Adresse*') 'Missing address reported as a connection in progress'
    Write-Output "$passed friends and connection-state checks passed. Current-user DPAPI; no network traffic."
}finally{
    $env:LOCALAPPDATA=$originalLocal
    $full=[IO.Path]::GetFullPath($directory)
    if($full.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

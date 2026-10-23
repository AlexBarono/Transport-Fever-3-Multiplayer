# Local address book. Invitations contain shared credentials and stay encrypted
# for the current Windows user, outside the replaceable launcher package.
function Get-LauncherFriendsPath {return Join-Path $env:LOCALAPPDATA 'TF3MP\Friends\friends.dat'}

function ConvertTo-LauncherFriendAddress([string]$Address) {
    $text=$Address.Trim()
    if($text.Length -gt 256){throw 'Die Einladung ist zu lang.'}
    if($text.StartsWith('tf3mp-internet://',[StringComparison]::Ordinal)){
        $invite=Read-InternetInvitation $text
        return New-InternetInvitation $invite.Address $invite.Port $invite.Fingerprint $invite.Key
    }
    $endpoint=Parse-JoinAddress $text '47800'
    if($endpoint.Address -eq '127.0.0.1'){throw 'Eine lokale Tunneladresse ist keine speicherbare Einladung. Die vollständige Einladung des Gastgebers verwenden.'}
    return "$($endpoint.Address):$($endpoint.Port)"
}

function Get-LauncherFriends {
    $path=Get-LauncherFriendsPath
    if(-not (Test-Path -LiteralPath $path)){return @()}
    Add-Type -AssemblyName System.Security
    $clear=$null
    try{
        if((Get-Item -LiteralPath $path).Length -gt 256KB){throw 'Freundesliste zu groß'}
        $clear=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $data=[Text.Encoding]::UTF8.GetString($clear)|ConvertFrom-Json
        if($data.Schema -ne 1 -or $data.Friends -isnot [Array] -or $data.Friends.Count -gt 100){throw 'Ungültiges Format'}
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $result=@(foreach($friend in $data.Friends){
            $id=[guid]::Empty
            if(-not [guid]::TryParse([string]$friend.Id,[ref]$id) -or -not $ids.Add($id.ToString()) -or
                [string]::IsNullOrWhiteSpace($friend.Name) -or $friend.Name.Length -gt 64 -or $friend.Name -match '[\x00-\x1f\x7f]' -or -not $names.Add($friend.Name)){
                throw 'Ungültiger Freundeseintrag'
            }
            [pscustomobject]@{Id=$id.ToString();Name=[string]$friend.Name;Address=(ConvertTo-LauncherFriendAddress $friend.Address)}
        })
        return @($result|Sort-Object Name)
    }catch{throw 'Die gespeicherte Freundesliste kann nicht gelesen werden. Sie wurde nicht ersetzt.'}
    finally{if($clear){[Array]::Clear($clear,0,$clear.Length)}}
}

function Write-LauncherFriends([object[]]$Friends) {
    Add-Type -AssemblyName System.Security
    $path=Get-LauncherFriendsPath
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    $temporary=$path+'.new-'+[guid]::NewGuid().ToString('N')
    $clear=[Text.Encoding]::UTF8.GetBytes((@{Schema=1;Friends=@($Friends)}|ConvertTo-Json -Compress -Depth 4))
    try{
        $encrypted=[Security.Cryptography.ProtectedData]::Protect($clear,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($temporary,$encrypted)
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }finally{[Array]::Clear($clear,0,$clear.Length);if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}

function Save-LauncherFriend([string]$Name,[string]$Address,[string]$Id='') {
    $name=($Name.Trim() -replace ' +',' ')
    if(-not $name -or $name.Length -gt 64 -or $name -match '[\x00-\x1f\x7f]'){throw 'Einen Namen mit 1 bis 64 Zeichen eingeben.'}
    $endpoint=ConvertTo-LauncherFriendAddress $Address
    $friends=@(Get-LauncherFriends)
    $existing=@(if($Id){$friends|Where-Object Id -eq $Id}else{$friends|Where-Object Name -eq $name})
    if($Id -and -not $existing.Count){throw 'Dieser Freund wurde inzwischen entfernt. Neu speichern.'}
    $existingId=if($existing.Count){$existing[0].Id}else{''}
    if(@($friends|Where-Object {$_.Name -eq $name -and $_.Id -ne $existingId}).Count){throw 'Dieser Name ist bereits vergeben.'}
    $entry=[pscustomobject]@{Id=$(if($existing.Count){$existing[0].Id}else{[guid]::NewGuid().ToString()});Name=$name;Address=$endpoint}
    $updated=@($friends|Where-Object Id -ne $entry.Id)+@($entry)
    if($updated.Count -gt 100){throw 'Es können höchstens 100 Freunde gespeichert werden.'}
    Write-LauncherFriends $updated
    return $entry
}

function Remove-LauncherFriend([string]$Id) {
    $friends=@(Get-LauncherFriends)
    $updated=@($friends|Where-Object Id -ne $Id)
    if($friends.Count -ne $updated.Count){Write-LauncherFriends $updated}
}

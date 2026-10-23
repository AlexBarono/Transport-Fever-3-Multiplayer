$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'launcher\launcher.ps1') -LibraryOnly
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'launcher\launcher.ps1'),[ref]$null,[ref]$null)
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-Fields'},$true)
Invoke-Expression $fn.Extent.Text
$passed=0;$script:notices=@();$script:closeCalls=0;$script:stopCalls=0;$script:fixtureGame=$false
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
function Test-GameRunning {return $script:fixtureGame}
function Test-LobbyCanStart {return $false}
function Write-LauncherLog($message){$script:notices+=$message}
function Close-LauncherLobby {$script:closeCalls++;$script:presence=$null;$script:lobby=$null}
function Stop-LauncherInternet {$script:stopCalls++;$script:internetTunnel=$null;$script:internetRole='';$script:internetInvite=''}
function Get-InternetIPv6Addresses {return [pscustomobject]@{Address='2001:db8::1';Display='2001:db8::1 / Testnetz'}}
function Get-SteamRoot {return $directory}
function Find-GameDir {return $directory}
function Get-SaveFolder {return $null}
function Click-FriendRow([int]$Index,[bool]$Edit=$false){
    $row=$friendList.GetItemRectangle($Index)
    $x=if($Edit){$friendList.ClientSize.Width-20}else{70}
    $event=New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Left,1,$x,($row.Top+10),0)
    $method=[Windows.Forms.Control].GetMethod('OnMouseClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$method.Invoke($friendList,@($event.PSObject.BaseObject))
}
$directory=Join-Path $env:TEMP ('tf3mp-friends-ui-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$originalLocal=$env:LOCALAPPDATA;$env:LOCALAPPDATA=$directory;$Preview=$true
try{
    . (Join-Path $root 'launcher\view.ps1')
    Register-LauncherPageEvents
    $hostRadio.Checked=$true;Update-Fields;$form.Show();[Windows.Forms.Application]::DoEvents()
    $navGuide.PerformClick()
    Check ($guidePage.Visible -and $guideText.Text -like '*FREUNDE SPEICHERN*') 'Guide navigation failed'
    Check ($script:closeCalls -eq 0 -and $script:stopCalls -eq 0) 'Reading guide interrupts session'
    $navHost.PerformClick()
    Check ($sessionPage.Visible -and $script:closeCalls -eq 0) 'Returning from guide disconnects host'
    $navFriends.PerformClick();Refresh-LauncherFriends
    Check ($friendsPage.Visible -and $friendEmpty.Visible) 'Empty friends page missing'
    $invite=New-InternetInvitation '2001:db8::2' 47801 ('a'*64) ('b'*64)
    $friendName.Text='Alex';$friendAddress.Text=$invite;$friendSave.PerformClick()
    Check ($friendList.Items.Count -eq 1 -and $friendQuick.Items.Count -eq 2 -and -not $friendEmpty.Visible) 'Saving does not refresh list and join selector'
    $id=$friendList.Items[0].Id
    $friendNew.PerformClick();$friendName.Text='Bea';$friendAddress.Text='100.80.12.4';$friendSave.PerformClick()
    Check ($friendList.Items.Count -eq 2) 'Second friend not saved'
    Click-FriendRow 0 $true
    Check ($friendsPage.Visible -and $friendName.Text -eq 'Alex' -and $script:friendsEditingId -eq $id) 'Ellipsis cannot edit without joining'
    $friendName.Text='Alex zuhause';$friendSave.PerformClick()
    Check ($friendList.Items[0].Name -eq 'Alex zuhause' -and $friendList.Items[0].Id -eq $id) 'Editing creates a duplicate or loses identity'
    Click-FriendRow 0
    Check ($sessionPage.Visible -and $clientRadio.Checked -and $ipBox.Text -eq $invite -and $connectionMode.SelectedIndex -eq 0) 'Name click does not fill the Internet invitation in Join'
    Check ($script:closeCalls -eq 1 -and $script:lobbyKey -eq '' -and $script:lobbyChanged -gt [DateTime]::UtcNow.AddSeconds(-5)) 'Joining does not rearm automatic connection'
    $navGuide.PerformClick();$navJoin.PerformClick()
    Check ($sessionPage.Visible -and $script:closeCalls -eq 1 -and $ipBox.Text -eq $invite) 'Returning from guide disconnects joining player'
    Check (-not ($script:notices -join "`n").Contains($invite) -and -not ($script:notices -join "`n").Contains('b'*64)) 'Friend invitation leaked into log'
    $friendAdd.PerformClick()
    Check ($friendsPage.Visible -and $friendAddress.Text -eq $invite -and -not $script:friendsEditingId) 'Save from Join loses pasted invitation'
    $navFriends.PerformClick();$friendQuick.SelectedIndex=2
    $committed=[Windows.Forms.ComboBox].GetMethod('OnSelectionChangeCommitted',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$committed.Invoke($friendQuick,@([EventArgs]::Empty))
    Check ($clientRadio.Checked -and $ipBox.Text -eq '100.80.12.4:47800' -and $connectionMode.SelectedIndex -eq 1) 'Quick selector cannot switch to VPN friend'
    $calls=$script:closeCalls;$script:updateBusy=$true;Join-LauncherFriend $friendList.Items[0];$script:updateBusy=$false
    Check ($script:closeCalls -eq $calls -and $ipBox.Text -eq '100.80.12.4:47800') 'Joining interrupts active update'
    $script:fixtureGame=$true;Join-LauncherFriend $friendList.Items[0];$script:fixtureGame=$false
    Check ($script:closeCalls -eq $calls) 'Joining interrupts running game'
    $navFriends.PerformClick();Click-FriendRow 1 $true;$friendRemove.PerformClick()
    Check ($friendList.Items.Count -eq 1 -and $friendQuick.Items.Count -eq 2 -and @(Get-LauncherFriends).Count -eq 1) 'Removal not persisted or selectors stale'
    Refresh-LauncherFriends
    Check ($friendList.Items[0].Name -eq 'Alex zuhause') 'Saved friend does not survive reload'
    $key=[Windows.Forms.Control].GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
    $keyEvent=New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::F11)
    [void]$key.Invoke($form,@($keyEvent.PSObject.BaseObject))
    Check ($form.WindowState -eq 'Maximized') 'F11 does not maximize'
    [void]$key.Invoke($form,@($keyEvent.PSObject.BaseObject))
    Check ($form.WindowState -eq 'Normal') 'F11 does not restore'
    Write-Output "$passed friends UI checks passed (real controls/events, isolated profile, network/game operations mocked)."
}finally{
    if($form){$form.Dispose()};$env:LOCALAPPDATA=$originalLocal
    $full=[IO.Path]::GetFullPath($directory)
    if($full.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

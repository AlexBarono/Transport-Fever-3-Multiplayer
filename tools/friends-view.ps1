$script:friendsEditingId='';$script:friendsLoadError=$false

function Get-LauncherCopyState([bool]$Internet,[bool]$Invite,[bool]$Locked,[bool]$Failed,[bool]$Address) {
    if(-not $Internet){return @{Text='Adresse kopieren';Busy=$false;Enabled=($Address -and -not $Locked);Reason='Die ausgewählte VPN-/LAN-Adresse teilen.'}}
    if($Invite){return @{Text='Einladung kopieren';Busy=$false;Enabled=(-not $Locked);Reason='Die vollständige Einladung mit dem Mitspieler teilen.'}}
    if($Failed){return @{Text='Einladung noch nicht bereit';Busy=$false;Enabled=$false;Reason='Verbindung fehlgeschlagen. Ursache im Protokoll prüfen und Erneut verbinden wählen.'}}
    if(-not $Address){return @{Text='Keine Einladung verfügbar';Busy=$false;Enabled=$false;Reason='Keine öffentliche Adresse verfügbar. Netzwerk prüfen und Neu laden wählen.'}}
    return @{Text='Verbindung wird vorbereitet …';Busy=$true;Enabled=$false;Reason='Der Launcher richtet die Verbindung ein. Danach lässt sich die Einladung kopieren.'}
}

function Set-LauncherPage([ValidateSet('session','friends','guide')][string]$Page) {
    $script:launcherPage=$Page
    Update-Fields
}

function Update-LauncherPageVisibility {
    if(-not $sessionPage){return}
    $sessionPage.Visible=$script:launcherPage -eq 'session'
    $friendsPage.Visible=$script:launcherPage -eq 'friends'
    $guidePage.Visible=$script:launcherPage -eq 'guide'
    $form.AcceptButton=if($friendsPage.Visible){$friendSave}elseif($sessionPage.Visible){$primary}else{$null}
    foreach($pair in @(@($navHost,($hostRadio.Checked -and $sessionPage.Visible)),@($navJoin,($clientRadio.Checked -and $sessionPage.Visible)),
        @($navTest,(($loopRadio.Checked -or $spotRadio.Checked -or $fakeRadio.Checked) -and $sessionPage.Visible)),
        @($navFriends,$friendsPage.Visible),@($navGuide,$guidePage.Visible))){
        $pair[0].BackColor=if($pair[1]){[Drawing.ColorTranslator]::FromHtml('#234052')}else{$Sidebar}
        $pair[0].ForeColor=if($pair[1]){$Accent}else{$TextColor}
    }
    Resize-LauncherPages
}

function Refresh-LauncherFriends {
    try{
        $friends=@(Get-LauncherFriends);$script:friendsLoadError=$false
        $friendList.Items.Clear();$friendQuick.Items.Clear()
        [void]$friendQuick.Items.Add([pscustomobject]@{Id='';Name='Freund auswählen …';Address=''})
        foreach($friend in $friends){[void]$friendList.Items.Add($friend);[void]$friendQuick.Items.Add($friend)}
        $friendQuick.SelectedIndex=0;$friendEmpty.Visible=$friends.Count -eq 0
        $friendListTitle.Text="GESPEICHERTE FREUNDE  /  $($friends.Count)"
    }catch{
        $script:friendsLoadError=$true;$friendStatus.Text=$_.Exception.Message
        Write-LauncherLog $_.Exception.Message
    }
}

function Join-LauncherFriend($Friend) {
    if(-not $Friend -or -not $Friend.Id){return}
    if($script:updateBusy -or $script:transferBusy -or $script:liveBusy -or $script:lobbyPreparing -or $script:lobbyPhase -in 'starting','started'){
        Write-LauncherLog 'Den laufenden Vorgang vor dem Wechsel zu einem Freund abschließen.';return
    }
    if(Test-GameRunning){Write-LauncherLog 'TF3 vor dem Wechsel zu einem Freund beenden.';return}
    $address=ConvertTo-LauncherFriendAddress $Friend.Address
    Close-LauncherLobby
    if($script:internetTunnel -and ($script:internetRole -ne 'client' -or $script:internetInvite -ne $address)){Stop-LauncherInternet}
    $clientRadio.Checked=$true
    $connectionMode.SelectedIndex=if($address.StartsWith('tf3mp-internet://',[StringComparison]::Ordinal)){0}else{1}
    $ipBox.Text=$address;$script:lobbyKey='';$script:lobbyChanged=[DateTime]::UtcNow
    Set-LauncherPage 'session'
    Write-LauncherLog "Einladung von $($Friend.Name) übernommen. Die Verbindung startet automatisch."
}

function Edit-LauncherFriend {
    if($friendList.SelectedItem){
        $item=$friendList.SelectedItem;$script:friendsEditingId=$item.Id
        $friendName.Text=$item.Name;$friendAddress.Text=$item.Address;$friendSave.Text='Änderungen speichern'
        $friendsPage.ScrollControlIntoView($friendEditor);[void]$friendName.Focus()
    }
}

function Register-LauncherPageEvents {
    $navHost.Add_Click({
        if(-not $hostRadio.Checked){Close-LauncherLobby;if($script:internetRole -eq 'client'){Stop-LauncherInternet};Refresh-HostAddresses;$hostRadio.Checked=$true}
        Set-LauncherPage 'session'
    })
    $navJoin.Add_Click({
        if(-not $clientRadio.Checked){
            Close-LauncherLobby;if($script:internetRole -eq 'host'){Stop-LauncherInternet}
            if($fakeRadio.Checked -and $ipBox.Text -eq '127.0.0.1'){$ipBox.Text=''};$clientRadio.Checked=$true
        }
        Set-LauncherPage 'session'
    })
    $navTest.Add_Click({
        if(-not ($loopRadio.Checked -or $spotRadio.Checked -or $fakeRadio.Checked)){Close-LauncherLobby;Stop-LauncherInternet;$fakeRadio.Checked=$true}
        Set-LauncherPage 'session'
    })
    $navFriends.Add_Click({Set-LauncherPage 'friends'})
    $navGuide.Add_Click({Set-LauncherPage 'guide'})
    $friendAdd.Add_Click({
        $script:friendsEditingId='';$friendSave.Text='Freund speichern';$friendName.Clear();$friendAddress.Text=$ipBox.Text
        Set-LauncherPage 'friends';[void]$friendName.Focus()
    })
    $friendQuick.Add_SelectionChangeCommitted({try{Join-LauncherFriend $friendQuick.SelectedItem}catch{Write-LauncherLog $_.Exception.Message}})
    $friendList.Add_MouseClick({param($sender,$event)
        $index=$sender.IndexFromPoint($event.Location)
        if($event.Button -eq 'Left' -and $index -ge 0){
            $sender.SelectedIndex=$index
            if($event.X -ge $sender.ClientSize.Width-$sender.EditAreaWidth){Edit-LauncherFriend}
            else{try{Join-LauncherFriend $sender.SelectedItem}catch{Write-LauncherLog $_.Exception.Message}}
        }
    })
    $friendList.Add_KeyDown({param($sender,$event)if($event.KeyCode -eq 'Enter'){
        try{Join-LauncherFriend $sender.SelectedItem}catch{Write-LauncherLog $_.Exception.Message};$event.Handled=$true;$event.SuppressKeyPress=$true
    }})
    $friendSave.Add_Click({
        try{
            $friend=Save-LauncherFriend $friendName.Text $friendAddress.Text $script:friendsEditingId
            $script:friendsEditingId=$friend.Id;$friendSave.Text='Änderungen speichern'
            Refresh-LauncherFriends;$friendStatus.Text="$($friend.Name) ist gespeichert. Zum Beitreten den Namen anklicken."
            Update-Fields
        }catch{$friendStatus.Text=$_.Exception.Message}
    })
    $friendNew.Add_Click({$script:friendsEditingId='';$friendSave.Text='Freund speichern';$friendName.Clear();$friendAddress.Clear();[void]$friendName.Focus()})
    $friendEdit.Add_Click({Edit-LauncherFriend})
    $friendRemove.Add_Click({
        if($friendList.SelectedItem){
            try{Remove-LauncherFriend $friendList.SelectedItem.Id;$script:friendsEditingId='';$friendSave.Text='Freund speichern';$friendName.Clear();$friendAddress.Clear();Refresh-LauncherFriends;$friendStatus.Text='Der Eintrag wurde aus deiner Liste entfernt.'}catch{$friendStatus.Text=$_.Exception.Message}
        }
    })
    if(-not $Preview){Refresh-LauncherFriends}
}

# Fluent 2 inspired Windows view. Rendering never starts network setup.
$steam=Get-SteamRoot
if(-not ('TF3MP.UI.ActionButton' -as [type])){Add-Type -Path (Join-Path $Root 'tools\launcher-controls.cs') -ReferencedAssemblies System.dll,System.Drawing.dll,System.Windows.Forms.dll}
$Background=[Drawing.ColorTranslator]::FromHtml('#10161F');$Sidebar=[Drawing.ColorTranslator]::FromHtml('#151D28')
$Card=[Drawing.ColorTranslator]::FromHtml('#1D2836');$TextColor=[Drawing.ColorTranslator]::FromHtml('#F2F5FA')
$Muted=[Drawing.ColorTranslator]::FromHtml('#AFBDCF');$Accent=[Drawing.ColorTranslator]::FromHtml('#60CDFF')
$script:launcherPage='session';$script:layoutBusy=$false
$form=New-Object Windows.Forms.Form
$form.Text='Transport Fever 3 | Multiplayer'
$area=Get-LauncherWorkingArea
$form.ClientSize=New-Object Drawing.Size([Math]::Min(1160,$area.Width-60),[Math]::Min(1000,$area.Height-80))
$form.MinimumSize=New-Object Drawing.Size(980,700)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='Sizable';$form.MaximizeBox=$true
$form.BackColor=$Background;$form.ForeColor=$TextColor;$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96);$form.AutoScaleMode='Dpi';$form.KeyPreview=$true
$form.Add_KeyDown({param($sender,$event)if($event.KeyCode -eq 'F11'){
    $sender.WindowState=if($sender.WindowState -eq 'Maximized'){'Normal'}else{'Maximized'}
    $event.Handled=$true;$event.SuppressKeyPress=$true
}})
function New-Label($parent,$text,$x,$y,$w,$h,$size=10,$color=$TextColor){
    $c=New-Object Windows.Forms.Label;$c.UseMnemonic=$false;$c.Text=$text;$c.SetBounds($x,$y,$w,$h)
    $c.Font=New-Object Drawing.Font('Segoe UI',$size);$c.ForeColor=$color;$c.BackColor=$parent.BackColor
    if($w -ge $parent.Width*0.6){$c.Anchor='Top, Left, Right'}
    $parent.Controls.Add($c);return $c
}
function New-Button($parent,$text,$x,$y,$w,$h,$isPrimary=$false){
    $c=New-Object TF3MP.UI.ActionButton;$c.Text=$text;$c.SetBounds($x,$y,$w,$h);$c.Cursor=[Windows.Forms.Cursors]::Hand
    $c.BackColor=if($isPrimary){$Accent}else{$Card};$c.ForeColor=if($isPrimary){$Background}else{$TextColor}
    $parent.Controls.Add($c);return $c
}
function New-Box($parent,$x,$y,$w){
    $c=New-Object Windows.Forms.TextBox;$c.SetBounds($x,$y,$w,30);$c.BackColor=$Background;$c.ForeColor=$TextColor
    $c.BorderStyle='FixedSingle';$c.Font=New-Object Drawing.Font('Segoe UI',11);$parent.Controls.Add($c);return $c
}
function New-Panel($parent,$x,$y,$w,$h,$color=$Card){$c=New-Object Windows.Forms.Panel;$c.SetBounds($x,$y,$w,$h);$c.BackColor=$color;$parent.Controls.Add($c);return $c}
function Stretch-Row($control){$control.Anchor='Top, Left, Right'}

# Docking keeps navigation separate from the resizable, scrollable workspace.
$workspace=New-Panel $form 232 0 ($form.ClientSize.Width-232) $form.ClientSize.Height $Background
$workspace.Dock='Fill';$workspace.Padding=New-Object Windows.Forms.Padding(24)
$side=New-Panel $form 0 0 232 $form.ClientSize.Height $Sidebar;$side.Dock='Left'
$sideFooter=New-Panel $side 0 0 232 44 $Sidebar;$sideFooter.Dock='Bottom'
New-Label $sideFooter 'Probe v68  /  Bridge v16' 24 12 184 22 9 $Muted|Out-Null
$sideBody=New-Panel $side 0 0 232 650 $Sidebar;$sideBody.Dock='Fill';$sideBody.AutoScroll=$true
$sideBody.AutoScrollMinSize=New-Object Drawing.Size(210,636)
$sideBody.BringToFront()
New-Label $sideBody 'TF3' 24 24 184 40 24 $TextColor|Out-Null
New-Label $sideBody 'MULTIPLAYER' 26 70 182 24 10 $Accent|Out-Null
$navHost=New-Button $sideBody 'Gastgeber' 16 128 192 44
$navJoin=New-Button $sideBody 'Beitreten' 16 180 192 44
$navFriends=New-Button $sideBody 'Freunde' 16 232 192 44
$navGuide=New-Button $sideBody 'Anleitung' 16 284 192 44
$navTest=New-Button $sideBody 'Testlabor' 16 336 192 44
New-Label $sideBody 'VERSIONEN' 24 408 184 20 9 $Muted|Out-Null
$updateCheck=New-Button $sideBody 'Auf Updates prüfen' 16 436 192 44
$updateZip=New-Button $sideBody 'Update aus ZIP' 16 488 192 36
$updateStatus=New-Label $sideBody 'Aktualisieren, ohne Dateien von Hand auszutauschen.' 24 540 176 86 9 $Muted

$sessionPage=New-Panel $workspace 0 0 880 980 $Background;$sessionPage.Dock='Fill';$sessionPage.AutoScroll=$true
$sessionBody=New-Panel $sessionPage 0 0 880 1004 $Background
$bodyWidth=$sessionBody.Width
New-Label $sessionBody 'Gemeinsam spielen.' 0 0 680 44 25|Out-Null
New-Label $sessionBody 'Verbinden, Spielstand teilen und zusammen loslegen.' 2 50 680 28 11 $Muted|Out-Null
$statusLabel=New-Label $sessionBody 'Bereit zum Einrichten' 2 86 ($bodyWidth-4) 30 10 $Accent;Stretch-Row $statusLabel
$hostPage=New-Panel $sessionBody 0 128 $bodyWidth 264;Stretch-Row $hostPage
New-Label $hostPage 'Verbindung herstellen' 24 18 480 32 17|Out-Null
New-Label $hostPage 'VERBINDUNGSART' 24 61 210 20 9 $Muted|Out-Null
$connectionPortLabel=New-Label $hostPage 'INTERNETPORT (TCP)' 258 61 180 20 9 $Muted
$connectionMode=New-Object Windows.Forms.ComboBox;$connectionMode.SetBounds(24,84,210,30);$connectionMode.DropDownStyle='DropDownList'
[void]$connectionMode.Items.Add('Internet ohne VPN');[void]$connectionMode.Items.Add('VPN / LAN');$connectionMode.SelectedIndex=0
$connectionMode.BackColor=$Background;$connectionMode.ForeColor=$TextColor;$hostPage.Controls.Add($connectionMode)
$connectionMode.FlatStyle='Flat'
$internetPortBox=New-Box $hostPage 258 84 110;$internetPortBox.Text='47801'
$hostAddress=New-Object Windows.Forms.ComboBox;$hostAddress.SetBounds(24,132,($bodyWidth-172),30);Stretch-Row $hostAddress
$hostAddress.DropDownStyle='DropDown';$hostAddress.DisplayMember='Display';$hostAddress.BackColor=$Background;$hostAddress.ForeColor=$TextColor;$hostPage.Controls.Add($hostAddress)
$hostAddress.FlatStyle='Flat'
function Refresh-HostAddresses {
    $script:refreshingAddresses=$true
    try{
        $selected=if($hostAddress.SelectedItem){$hostAddress.SelectedItem.Address}else{$hostAddress.Text};$hostAddress.Items.Clear()
        if($connectionMode.SelectedIndex -eq 0){$addresses=@(Get-InternetIPv6Addresses)}else{
            $addresses=@()
            try{$addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object{
                $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.AddressState -eq 'Preferred'
            }|Sort-Object @{Expression={if($_.InterfaceAlias -match 'Tailscale|ZeroTier|Hamachi|Radmin|WireGuard|TAP|TUN|VPN'){0}else{1}}},InterfaceAlias|ForEach-Object{
                [pscustomobject]@{Address=$_.IPAddress;Display="$($_.IPAddress) / $($_.InterfaceAlias)"}
            })}catch{}
        }
        foreach($address in $addresses){[void]$hostAddress.Items.Add($address)}
        if($hostAddress.Items.Count){$hostAddress.SelectedIndex=0}
        for($i=0;$i -lt $hostAddress.Items.Count;$i++){if($hostAddress.Items[$i].Address -eq $selected){$hostAddress.SelectedIndex=$i}}
    }finally{$script:refreshingAddresses=$false}
}
Refresh-HostAddresses
$refreshAddress=New-Button $hostPage 'Neu laden' ($bodyWidth-132) 130 108 34;$refreshAddress.Anchor='Top, Right'
$internetSetup=New-Button $hostPage 'Erneut verbinden' 24 180 192 40
$copyAddress=New-Button $hostPage 'Einladung kopieren' 228 180 ($bodyWidth-252) 40 $true;Stretch-Row $copyAddress
$connectionStatus=New-Label $hostPage 'Internetverbindung wird vorbereitet …' 24 230 ($bodyWidth-48) 30 9 $Muted;Stretch-Row $connectionStatus

$joinPage=New-Panel $sessionBody 0 128 $bodyWidth 264;Stretch-Row $joinPage
New-Label $joinPage 'Beim Gastgeber beitreten' 24 18 600 32 17|Out-Null
New-Label $joinPage 'Gespeicherter Freund' 24 60 220 22 9 $Muted|Out-Null
$friendQuick=New-Object Windows.Forms.ComboBox;$friendQuick.SetBounds(24,84,($bodyWidth-240),30);$friendQuick.DropDownStyle='DropDownList'
$friendQuick.DisplayMember='Name';$friendQuick.BackColor=$Background;$friendQuick.ForeColor=$TextColor;Stretch-Row $friendQuick;$joinPage.Controls.Add($friendQuick)
$friendQuick.FlatStyle='Flat'
$friendAdd=New-Button $joinPage 'Freund speichern' ($bodyWidth-204) 82 180 34;$friendAdd.Anchor='Top, Right'
$ipBox=New-Box $joinPage 24 132 ($bodyWidth-172);Stretch-Row $ipBox;$ipBox.AccessibleName='Einladung oder Adresse des Gastgebers'
$clearAddress=New-Button $joinPage 'Löschen' ($bodyWidth-132) 130 108 34;$clearAddress.Anchor='Top, Right'
$internetCheck=New-Button $joinPage 'Verbindung prüfen' 24 180 192 40
$joinConnection=New-Label $joinPage 'Einladung einfügen oder oben einen Freund auswählen.' 232 184 ($bodyWidth-256) 54 10 $Muted;Stretch-Row $joinConnection

$testPage=New-Panel $sessionBody 0 128 $bodyWidth 264;Stretch-Row $testPage
New-Label $testPage 'Testlabor / ein PC' 24 18 600 32 17|Out-Null
$roleBox=New-Object Windows.Forms.GroupBox;$roleBox.SetBounds(24,64,($bodyWidth-48),138);Stretch-Row $roleBox;$roleBox.ForeColor=$TextColor;$testPage.Controls.Add($roleBox)
$hostRadio=New-Object Windows.Forms.RadioButton;$hostRadio.Visible=$false
$clientRadio=New-Object Windows.Forms.RadioButton;$clientRadio.Visible=$false
$loopRadio=New-Object Windows.Forms.RadioButton;$loopRadio.Text='Allein testen / Bauten 100 m daneben nachbauen'
$spotRadio=New-Object Windows.Forms.RadioButton;$spotRadio.Text='Gleiche Stelle / nach Neuladen am selben Ort nachbauen'
$fakeRadio=New-Object Windows.Forms.RadioButton;$fakeRadio.Text='Simulierter Gastgeber / Pause, Tempo, Geld und Nachbau'
$y=20;foreach($radio in @($loopRadio,$spotRadio,$fakeRadio)){$radio.SetBounds(14,$y,($bodyWidth-80),30);Stretch-Row $radio;$y+=36}
$roleBox.Controls.AddRange(@($hostRadio,$clientRadio,$loopRadio,$spotRadio,$fakeRadio))
New-Label $testPage 'Der simulierte Gastgeber startet automatisch im Hintergrund.' 24 220 ($bodyWidth-48) 24 10 $Muted|Out-Null

$workflow=New-Panel $sessionBody 0 408 $bodyWidth 174;Stretch-Row $workflow
$flowTitle=New-Label $workflow 'SPIELSTAND UND GEMEINSAMER START' 24 16 560 22 9 $Accent
$saveChoice=New-Object Windows.Forms.ComboBox;$saveChoice.SetBounds(24,48,($bodyWidth-48),30);Stretch-Row $saveChoice
$saveChoice.DropDownStyle='DropDownList';$saveChoice.DisplayMember='Display';$saveChoice.BackColor=$Background;$saveChoice.ForeColor=$TextColor;$workflow.Controls.Add($saveChoice)
$saveChoice.FlatStyle='Flat'
function Refresh-SaveChoices {
    $selected=if($saveChoice.SelectedItem){$saveChoice.SelectedItem.Path}else{''};$saveChoice.Items.Clear();$folder=Get-SaveFolder $steam
    if($folder){foreach($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.sav' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)){
        [void]$saveChoice.Items.Add([pscustomobject]@{Path=$file.FullName;Display=("{0}   /   {1}" -f $file.BaseName,$file.LastWriteTime.ToString('dd.MM. HH:mm'))})
    }}
    if($saveChoice.Items.Count){$saveChoice.SelectedIndex=0}
    for($i=0;$i -lt $saveChoice.Items.Count;$i++){if($saveChoice.Items[$i].Path -eq $selected){$saveChoice.SelectedIndex=$i}}
}
$primary=New-Button $workflow 'Spielstand bereitstellen' 24 92 360 44 $true
$startBoth=New-Button $workflow 'Spiel starten' 396 92 ($bodyWidth-420) 44;Stretch-Row $startBoth
$joinStatus=New-Label $workflow 'Warte auf Verbindung' 24 48 ($bodyWidth-48) 38 15 $TextColor;Stretch-Row $joinStatus
$workflowHint=New-Label $workflow 'Nach der Übertragung startet der Gastgeber beide Spiele.' 24 144 ($bodyWidth-48) 24 9 $Muted;Stretch-Row $workflowHint
$progressBar=New-Object TF3MP.UI.ProgressMeter;$progressBar.SetBounds(0,170,$bodyWidth,4);$progressBar.Style='Continuous';Stretch-Row $progressBar;$workflow.Controls.Add($progressBar)
$transfer=New-Button $workflow 'Abbrechen' ($bodyWidth-134) 10 110 30;$transfer.Anchor='Top, Right';$transfer.Visible=$false

$settings=New-Panel $sessionBody 0 598 $bodyWidth 94;Stretch-Row $settings
New-Label $settings 'SPIELORDNER' 24 14 450 20 9 $Muted|Out-Null
$gameBox=New-Box $settings 24 44 ($bodyWidth-314);Stretch-Row $gameBox;$gameBox.Font=New-Object Drawing.Font('Segoe UI',9);$gameBox.Text=Find-GameDir $steam
$browse=New-Button $settings 'Suchen …' ($bodyWidth-278) 42 110 34;$browse.Anchor='Top, Right'
$browse.Add_Click({$dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Transport Fever 3 auswählen (enthält alut.dll)';try{if($dialog.ShowDialog() -eq 'OK'){$gameBox.Text=$dialog.SelectedPath}}finally{$dialog.Dispose()}})
$testPortLabel=New-Label $settings 'TESTPORT' ($bodyWidth-138) 14 114 20 9 $Muted;$testPortLabel.Anchor='Top, Right'
$portBox=New-Box $settings ($bodyWidth-138) 44 114;$portBox.Anchor='Top, Right'
$install=New-Button $sessionBody 'Einstellungen speichern' 0 708 206 36
$replay=New-Button $sessionBody 'Aufnahme nachbauen' 218 708 200 36
$recover=New-Button $sessionBody 'Neu abgleichen' 0 708 206 36
$check=New-Button $sessionBody 'Details prüfen' ($bodyWidth-300) 708 144 36;$check.Anchor='Top, Right'
$remove=New-Button $sessionBody 'Mod entfernen' ($bodyWidth-144) 708 144 36;$remove.Anchor='Top, Right'
$issueLabel=New-Label $sessionBody '' 0 758 $bodyWidth 24 9 ([Drawing.ColorTranslator]::FromHtml('#FFCA80'));Stretch-Row $issueLabel
New-Label $sessionBody 'Sitzung & Protokoll' 0 792 620 28 13|Out-Null
$out=New-Object Windows.Forms.TextBox;$out.SetBounds(0,832,$bodyWidth,148);$out.Anchor='Top, Bottom, Left, Right'
$out.Multiline=$true;$out.ReadOnly=$true;$out.ScrollBars='Vertical';$out.BorderStyle='FixedSingle'
$out.BackColor=$Card;$out.ForeColor=$Muted;$out.Font=New-Object Drawing.Font('Consolas',9);$sessionBody.Controls.Add($out)

$friendsPage=New-Panel $workspace 0 0 880 850 $Background;$friendsPage.Dock='Fill';$friendsPage.AutoScroll=$true;$friendsPage.Visible=$false
$friendsBody=New-Panel $friendsPage 0 0 880 860 $Background
New-Label $friendsBody 'Deine Freunde' 0 0 680 44 25|Out-Null
New-Label $friendsBody 'Einmal speichern. Beim nächsten Mal den Namen anklicken.' 2 54 680 28 11 $Muted|Out-Null
$friendEditor=New-Panel $friendsBody 0 112 880 236;Stretch-Row $friendEditor
New-Label $friendEditor 'Freund hinzufügen oder Einladung aktualisieren' 24 18 700 28 16|Out-Null
New-Label $friendEditor 'NAME' 24 60 260 20 9 $Muted|Out-Null
$friendName=New-Box $friendEditor 24 84 260;$friendName.MaxLength=64
New-Label $friendEditor 'EINLADUNG ODER VPN-ADRESSE' 304 60 500 20 9 $Muted|Out-Null
$friendAddress=New-Box $friendEditor 304 84 552;Stretch-Row $friendAddress;$friendAddress.MaxLength=256
$friendSave=New-Button $friendEditor 'Freund speichern' 24 142 200 42 $true
$friendNew=New-Button $friendEditor 'Neuer Eintrag' 236 142 164 42
$friendStatus=New-Label $friendEditor 'Die Liste wird auf diesem Windows-Konto geschützt gespeichert.' 24 196 832 26 9 $Muted;Stretch-Row $friendStatus
$friendListTitle=New-Label $friendsBody 'GESPEICHERTE FREUNDE' 0 376 600 24 9 $Accent
$friendList=New-Object TF3MP.UI.FriendList;$friendList.SetBounds(0,416,880,320);$friendList.Anchor='Top, Bottom, Left, Right'
$friendList.Font=New-Object Drawing.Font('Segoe UI',13);$friendList.IntegralHeight=$false
$friendList.DisplayMember='Name';$friendList.BackColor=$Card;$friendList.ForeColor=$TextColor;$friendList.BorderStyle='FixedSingle';$friendsBody.Controls.Add($friendList)
$friendEmpty=New-Label $friendsBody 'Noch keine Freunde gespeichert. Namen und Einladung oben eintragen.' 24 440 800 80 12 $Muted;Stretch-Row $friendEmpty
$friendEdit=New-Button $friendsBody 'Auswahl bearbeiten' 0 756 206 40;$friendEdit.Anchor='Bottom, Left'
$friendRemove=New-Button $friendsBody 'Aus Liste entfernen' 218 756 206 40;$friendRemove.Anchor='Bottom, Left'
$friendHint=New-Label $friendsBody 'Name anklicken: beitreten. Über … rechts am Namen den Eintrag bearbeiten.' 0 816 840 34 10 $Muted;$friendHint.Anchor='Bottom, Left, Right'

$guidePage=New-Panel $workspace 0 0 880 850 $Background;$guidePage.Dock='Fill';$guidePage.Visible=$false
New-Label $guidePage 'So spielt ihr zusammen' 0 0 $guidePage.ClientSize.Width 44 25|Out-Null
New-Label $guidePage 'Die wichtigsten Schritte – direkt im Launcher.' 2 54 ($guidePage.ClientSize.Width-2) 28 11 $Muted|Out-Null
$guideText=New-Object Windows.Forms.TextBox;$guideText.Multiline=$true;$guideText.ScrollBars='Vertical'
$guideText.SetBounds(0,112,$guidePage.ClientSize.Width,([Math]::Max(120,$guidePage.ClientSize.Height-150)));$guideText.Anchor='Top, Bottom, Left, Right'
$guideText.ReadOnly=$true;$guideText.BorderStyle='None';$guideText.BackColor=$Background;$guideText.ForeColor=$TextColor
$guideText.Font=New-Object Drawing.Font('Segoe UI',12);$guidePage.Controls.Add($guideText)
$guideText.Text=@'
GASTGEBER

1. Links Gastgeber wählen. Internet ohne VPN öffnet die Verbindung automatisch.
2. Sobald die Einladung bereit ist, Einladung kopieren anklicken und dem Mitspieler geben.
3. Auf den Mitspieler warten. Danach einen Spielstand auswählen und bereitstellen.
4. Wenn beide bereit sind, Spiel für beide starten anklicken. Beide Launcher bleiben geöffnet.

BEITRETEN

1. Links Beitreten wählen und die vollständige Einladung des Gastgebers einfügen.
2. Die Verbindung und der Empfang des Spielstands laufen automatisch.
3. Auf den gemeinsamen Start durch den Gastgeber warten.

FREUNDE SPEICHERN

1. Unter Beitreten die Einladung einfügen und Freund speichern wählen.
2. Einen Namen eingeben und speichern. Alternativ unter Freunde Namen und Einladung eintragen.
3. Später den Namen in Freunde anklicken oder unter Beitreten auswählen. Die gespeicherte Einladung wird automatisch übernommen.
4. Über … rechts am Namen lässt sich der Eintrag bearbeiten, zum Beispiel bei einer neuen Internetadresse des Gastgebers.

FENSTER UND ANZEIGE

Das Fenster lässt sich frei vergrößern und maximieren. F11 wechselt zwischen maximiert und normal. In kleineren Fenstern kann der Inhalt gescrollt werden.

Verbindung wird vorbereitet … bedeutet, dass der Launcher noch arbeitet. Erst nach erfolgreicher Einrichtung erscheint Einladung kopieren. Konkrete Fehler stehen unter Sitzung & Protokoll.

AKTUALISIEREN

Spiel und gemeinsame Sitzung beenden. Links Auf Updates prüfen und anschließend Update installieren wählen. Der Launcher startet danach neu. Update aus ZIP ist zusätzlich verfügbar. Beide PCs benötigen dieselbe Paketversion.

WENN ETWAS NICHT KLAPPT

• Beide PCs verwenden dieselbe Version und denselben geteilten Spielstand.
• Für Internet ohne VPN brauchen beide Anschlüsse IPv6. Routerfehler stehen im Protokoll.
• Alternativ VPN / LAN verwenden und die VPN-Adresse des Gastgebers teilen.
• Der Gastgeber kann mit Neu abgleichen seinen aktuellen Stand auf beiden PCs neu laden.
• Eine gespeicherte Einladung bleibt bei gleicher Adresse und gleichem Port gültig. Bei einer geänderten Internetadresse muss der Freundeseintrag aktualisiert werden.
'@
$guideText.Lines=$guideText.Text -split '\r?\n'
function Update-LauncherActionRows {
    if(-not $primary){return}
    $scale=[Math]::Max([double]1,[double]($hostPage.Top/128.0));$gap=[int](12*$scale)
    $primary.Width=if($hostRadio.Checked){[int][Math]::Floor(($joinStatus.Width-$gap)/2)}else{$joinStatus.Width}
    $startBoth.Left=$primary.Right+$gap;$startBoth.Width=[Math]::Max(100,$joinStatus.Right-$startBoth.Left)
    $test=$loopRadio.Checked -or $spotRadio.Checked -or $fakeRadio.Checked
    $browse.Left=if($test){$portBox.Left-$gap-$browse.Width}else{$settings.Width-[int](24*$scale)-$browse.Width}
    $gameBox.Width=[Math]::Max(100,$browse.Left-$gameBox.Left-$gap)
}
function Resize-LauncherPages {
    if($script:layoutBusy -or $form.IsDisposed){return};$script:layoutBusy=$true
    $scale=[Math]::Max([double]1,[double]($hostPage.Top/128.0))
    try{foreach($pair in @(@($sessionPage,$sessionBody,1004),@($friendsPage,$friendsBody,860))){
        $pair[1].Width=[Math]::Max([int](680*$scale),$pair[0].ClientSize.Width)
        $pair[1].Height=[Math]::Max([int]($pair[2]*$scale),$pair[0].ClientSize.Height)
    };Update-LauncherActionRows}finally{$script:layoutBusy=$false}
}
$form.Add_Resize({Resize-LauncherPages});$workspace.Add_Resize({Resize-LauncherPages})
$sessionPage.Add_Resize({Resize-LauncherPages});$friendsPage.Add_Resize({Resize-LauncherPages})
$form.AcceptButton=$primary
$tooltips=New-Object Windows.Forms.ToolTip;$tooltips.ShowAlways=$true
$tooltips.SetToolTip($copyAddress,'Die Einladung ist verfügbar, sobald die Verbindung vorbereitet wurde.')
$tooltips.SetToolTip($updateCheck,'Sucht nach einer neueren Version auf GitHub.')
$tooltips.SetToolTip($friendList,'Namen anklicken oder Enter drücken: beitreten. … rechts am Namen: bearbeiten.')
$tooltips.SetToolTip($recover,'Übernimmt den Gastgeberstand auf beiden PCs. Der Mitspieler muss nichts anklicken.')
Resize-LauncherPages

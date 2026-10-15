# Shared view for launcher.ps1. No installation or network mutations during rendering.
$steam = Get-SteamRoot
$Background=[System.Drawing.ColorTranslator]::FromHtml('#111923')
$Sidebar=[System.Drawing.ColorTranslator]::FromHtml('#182330')
$Card=[System.Drawing.ColorTranslator]::FromHtml('#202E3D')
$TextColor=[System.Drawing.ColorTranslator]::FromHtml('#EDF3F8')
$Muted=[System.Drawing.ColorTranslator]::FromHtml('#A5B6C7')
$Accent=[System.Drawing.ColorTranslator]::FromHtml('#75E0C0')
$form=New-Object System.Windows.Forms.Form
$form.Text='Transport Fever 3 | Multiplayer'
$form.ClientSize=New-Object System.Drawing.Size(1024,900)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedSingle'; $form.MaximizeBox=$false
$form.BackColor=$Background; $form.ForeColor=$TextColor
$form.Font=New-Object System.Drawing.Font('Segoe UI',10)
$form.AutoScaleMode='Dpi'

function New-Label($parent,$text,$x,$y,$w,$h,$size=10,$color=$TextColor) {
    $control=New-Object System.Windows.Forms.Label
    $control.UseMnemonic=$false; $control.Text=$text; $control.Location=New-Object System.Drawing.Point($x,$y)
    $control.Size=New-Object System.Drawing.Size($w,$h)
    $control.Font=New-Object System.Drawing.Font('Segoe UI',$size)
    $control.ForeColor=$color; $parent.Controls.Add($control); return $control
}
function New-Button($parent,$text,$x,$y,$w,$h,$isPrimary=$false) {
    $control=New-Object System.Windows.Forms.Button
    $control.Text=$text; $control.Location=New-Object System.Drawing.Point($x,$y)
    $control.Size=New-Object System.Drawing.Size($w,$h); $control.FlatStyle='Flat'
    $control.FlatAppearance.BorderSize=0; $control.Cursor=[System.Windows.Forms.Cursors]::Hand
    $control.BackColor=if($isPrimary){$Accent}else{$Card}
    $control.ForeColor=if($isPrimary){$Background}else{$TextColor}
    $control.Add_Paint({param($sender,$event)
        if(-not $sender.Enabled){
            $brush=New-Object Drawing.SolidBrush($sender.BackColor)
            $event.Graphics.FillRectangle($brush,$sender.ClientRectangle); $brush.Dispose()
            [Windows.Forms.TextRenderer]::DrawText($event.Graphics,$sender.Text,$sender.Font,$sender.ClientRectangle,$Muted,([Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))
        }
    })
    $parent.Controls.Add($control); return $control
}
function New-Box($parent,$x,$y,$w) {
    $control=New-Object System.Windows.Forms.TextBox
    $control.Location=New-Object System.Drawing.Point($x,$y); $control.Size=New-Object System.Drawing.Size($w,30)
    $control.BackColor=$Background; $control.ForeColor=$TextColor; $control.BorderStyle='FixedSingle'
    $control.Font=New-Object System.Drawing.Font('Segoe UI',12)
    $parent.Controls.Add($control); return $control
}
function New-Panel($parent,$x,$y,$w,$h,$color=$Card) {
    $control=New-Object System.Windows.Forms.Panel
    $control.Location=New-Object System.Drawing.Point($x,$y); $control.Size=New-Object System.Drawing.Size($w,$h)
    $control.BackColor=$color; $parent.Controls.Add($control); return $control
}

$side=New-Panel $form 0 0 218 900 $Sidebar
New-Label $side 'TF3 / MULTIPLAYER' 24 30 190 30 12 $Accent | Out-Null
New-Label $side "Gemeinsam bauen.`r`nGemeinsam verbinden." 24 77 177 60 12 | Out-Null
$navHost=New-Button $side 'Gastgeber' 16 176 186 46
$navJoin=New-Button $side 'Beitreten' 16 232 186 46
$navTest=New-Button $side 'Testlabor' 16 288 186 46
New-Label $side "VPN ODER INTERNET" 24 650 180 24 9 $Accent | Out-Null
New-Label $side "Ohne VPN: Internetzugang`r`neinrichten und Einladung`r`nbeim Mitspieler einfügen." 24 684 176 75 10 $Muted | Out-Null
New-Label $side 'Probe v62  /  Bridge v16' 24 856 185 22 9 $Muted | Out-Null
New-Label $form 'Gemeinsam auf derselben Karte.' 250 28 734 44 23 | Out-Null
New-Label $form 'Ein gemeinsamer Spielstand. Ein Start für beide. Platz für eure Ideen.' 252 77 734 28 11 $Muted | Out-Null
$statusLabel=New-Label $form 'Bereit zum Einrichten' 252 110 734 40 9 $Accent

$hostPage=New-Panel $form 250 155 734 220
New-Label $hostPage '01  Verbindung herstellen' 22 12 680 32 17 | Out-Null
$connectionMode=New-Object Windows.Forms.ComboBox
$connectionMode.Location=New-Object Drawing.Point(22,53); $connectionMode.Size=New-Object Drawing.Size(200,28)
$connectionMode.DropDownStyle='DropDownList'; [void]$connectionMode.Items.Add('Internet ohne VPN'); [void]$connectionMode.Items.Add('VPN / LAN')
$connectionMode.SelectedIndex=0; $hostPage.Controls.Add($connectionMode)
$connectionPortLabel=New-Label $hostPage 'Internetport (TCP)' 240 56 145 22 9 $Muted
$internetPortBox=New-Box $hostPage 388 51 90; $internetPortBox.Text='47801'
$hostAddress=New-Object Windows.Forms.ComboBox
$hostAddress.Location=New-Object Drawing.Point(22,91); $hostAddress.Size=New-Object Drawing.Size(576,30)
$hostAddress.DropDownStyle='DropDown'; $hostAddress.DisplayMember='Display'
$hostAddress.BackColor=$Background; $hostAddress.ForeColor=$TextColor; $hostAddress.Font=New-Object Drawing.Font('Segoe UI',10)
$hostPage.Controls.Add($hostAddress)
function Refresh-HostAddresses {
    $script:refreshingAddresses=$true
    try {
    $selected=if($hostAddress.SelectedItem){$hostAddress.SelectedItem.Address}else{$hostAddress.Text}
    $hostAddress.Items.Clear()
    if($connectionMode.SelectedIndex -eq 0){$addresses=@(Get-InternetIPv6Addresses)}else{
        $addresses=@()
        try {$addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.AddressState -eq 'Preferred'
        } | Sort-Object @{Expression={if($_.InterfaceAlias -match 'Tailscale|ZeroTier|Hamachi|Radmin|WireGuard|TAP|TUN|VPN'){0}else{1}}},InterfaceAlias | ForEach-Object {
            [pscustomobject]@{Address=$_.IPAddress;Display="$($_.IPAddress) / $($_.InterfaceAlias)"}
        })}catch{}
    }
    foreach($address in $addresses){[void]$hostAddress.Items.Add($address)}
    if($hostAddress.Items.Count){$hostAddress.SelectedIndex=0}
    for($i=0;$i -lt $hostAddress.Items.Count;$i++){if($hostAddress.Items[$i].Address -eq $selected){$hostAddress.SelectedIndex=$i}}
    }finally{$script:refreshingAddresses=$false}
}
Refresh-HostAddresses
$refreshAddress=New-Button $hostPage 'Neu laden' 610 90 102 30
$internetSetup=New-Button $hostPage 'Verbindung öffnen' 22 132 220 36 $true
$ipv4Setup=New-Button $hostPage 'IPv4 automatisch' 252 132 200 36
$copyAddress=New-Button $hostPage 'Einladung kopieren' 462 132 250 36
$connectionStatus=New-Label $hostPage 'Verbindung öffnen und Einladung teilen.' 22 178 690 32 10 $Muted

$joinPage=New-Panel $form 250 155 734 220
New-Label $joinPage '01  Beim Gastgeber verbinden' 22 12 690 32 17 | Out-Null
New-Label $joinPage 'Einladung, IPv6- oder IPv4-Adresse des Gastgebers' 22 57 680 24 10 $Muted | Out-Null
$ipBox=New-Box $joinPage 22 91 576
$clearAddress=New-Button $joinPage 'Löschen' 610 90 102 30
$internetCheck=New-Button $joinPage 'Verbindung prüfen' 22 132 220 36
$joinConnection=New-Label $joinPage 'Adresse einfügen. Die Verbindung startet automatisch.' 252 133 460 55 10 $Muted

$testPage=New-Panel $form 250 155 734 220
New-Label $testPage 'Testlabor / ein PC' 22 15 690 34 18 | Out-Null
$roleBox=New-Object System.Windows.Forms.GroupBox
$roleBox.Location=New-Object System.Drawing.Point(18,52); $roleBox.Size=New-Object System.Drawing.Size(696,123)
$roleBox.ForeColor=$TextColor; $testPage.Controls.Add($roleBox)
$hostRadio=New-Object System.Windows.Forms.RadioButton; $hostRadio.Visible=$false
$clientRadio=New-Object System.Windows.Forms.RadioButton; $clientRadio.Visible=$false
$loopRadio=New-Object System.Windows.Forms.RadioButton
$loopRadio.Text='Allein testen / Bauten 100 m daneben nachbauen'
$spotRadio=New-Object System.Windows.Forms.RadioButton
$spotRadio.Text='Gleiche Stelle / nach Neuladen am selben Ort nachbauen'
$fakeRadio=New-Object System.Windows.Forms.RadioButton
$fakeRadio.Text='Simulierter Gastgeber / Pause, Tempo, Geld und Nachbau'
$y=18
foreach($radio in @($loopRadio,$spotRadio,$fakeRadio)) {
    $radio.Location=New-Object System.Drawing.Point(12,$y); $radio.Size=New-Object System.Drawing.Size(675,28); $y+=32
}
$roleBox.Controls.AddRange(@($hostRadio,$clientRadio,$loopRadio,$spotRadio,$fakeRadio))
New-Label $testPage 'Der simulierte Gastgeber startet automatisch im Hintergrund.' 22 185 690 24 10 $Muted | Out-Null

$workflow=New-Panel $form 250 390 734 155
$flowTitle=New-Label $workflow '02  SPIELSTAND  /  GEMEINSAMER START' 20 8 565 20 9 $Accent
$saveChoice=New-Object Windows.Forms.ComboBox
$saveChoice.Location=New-Object Drawing.Point(20,34); $saveChoice.Size=New-Object Drawing.Size(694,30)
$saveChoice.DropDownStyle='DropDownList'; $saveChoice.DisplayMember='Display'
$saveChoice.BackColor=$Background; $saveChoice.ForeColor=$TextColor; $workflow.Controls.Add($saveChoice)
function Refresh-SaveChoices {
    $selected=if($saveChoice.SelectedItem){$saveChoice.SelectedItem.Path}else{''}
    $saveChoice.Items.Clear()
    $folder=Get-SaveFolder $steam
    if($folder){foreach($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.sav' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)){
        [void]$saveChoice.Items.Add([pscustomobject]@{Path=$file.FullName;Display=("{0}   /   {1}" -f $file.BaseName,$file.LastWriteTime.ToString('dd.MM. HH:mm'))})
    }}
    if($saveChoice.Items.Count){$saveChoice.SelectedIndex=0}
    for($i=0;$i -lt $saveChoice.Items.Count;$i++){if($saveChoice.Items[$i].Path -eq $selected){$saveChoice.SelectedIndex=$i}}
}
$primary=New-Button $workflow 'Spielstand bereitstellen' 20 75 336 44 $true
$primary.Font=New-Object System.Drawing.Font('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
$startBoth=New-Button $workflow 'Spiel starten' 370 75 344 44
$startBoth.Font=$primary.Font
$startBoth.Add_Paint({param($sender,$event)
    $brush=New-Object Drawing.SolidBrush($sender.BackColor)
    $event.Graphics.FillRectangle($brush,$sender.ClientRectangle); $brush.Dispose()
    $color=if($sender.Enabled){$Background}else{$Muted}
    [Windows.Forms.TextRenderer]::DrawText($event.Graphics,$sender.Text,$sender.Font,$sender.ClientRectangle,$color,([Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))
})
$joinStatus=New-Label $workflow 'Warte auf Spielstand vom Gastgeber' 20 34 694 45 16 $TextColor
$workflowHint=New-Label $workflow 'Nach der Übertragung startet der Gastgeber beide Spiele.' 20 125 694 25 9 $Muted
$joinStatus.BackColor=$Card; $workflowHint.BackColor=$Card
$progressBar=New-Object Windows.Forms.ProgressBar
$progressBar.Location=New-Object Drawing.Point(0,151); $progressBar.Size=New-Object Drawing.Size(734,2)
$progressBar.Style='Continuous'; $workflow.Controls.Add($progressBar)
$transfer=New-Button $workflow 'Abbrechen' 604 3 110 25
$transfer.Font=New-Object System.Drawing.Font('Segoe UI',9); $transfer.Visible=$false
$check=New-Button $form 'Details prüfen' 686 664 152 32
$issueLabel=New-Label $form '' 252 702 732 22 9 ([System.Drawing.ColorTranslator]::FromHtml('#FFCA80'))

$settings=New-Panel $form 250 552 734 98
New-Label $settings 'SPIELORDNER' 18 12 500 21 9 $Muted | Out-Null
$gameBox=New-Box $settings 18 43 510
$gameBox.Font=New-Object System.Drawing.Font('Segoe UI',9)
$gameBox.Text=Find-GameDir $steam
$browse=New-Button $settings 'Suchen ...' 540 40 92 32
$browse.Add_Click({
    $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description='Transport Fever 3 auswählen (enthält alut.dll)'
    if($dialog.ShowDialog() -eq 'OK'){$gameBox.Text=$dialog.SelectedPath}
    $dialog.Dispose()
})
$testPortLabel=New-Label $settings 'TESTPORT' 649 12 70 21 9 $Muted
$portBox=New-Box $settings 649 43 68
$portBox.Font=New-Object System.Drawing.Font('Segoe UI',10)
$install=New-Button $form 'Nur Einstellungen speichern' 250 664 205 32
$install.Font=New-Object System.Drawing.Font('Segoe UI',9)
$replay=New-Button $form 'Am selben Ort nachbauen' 468 664 205 32
$replay.Font=New-Object System.Drawing.Font('Segoe UI',9)
$recover=New-Button $form 'Neu abgleichen' 250 664 205 32
$recover.Font=New-Object System.Drawing.Font('Segoe UI',9)
$remove=New-Button $form 'Mod entfernen' 852 664 132 32
$remove.ForeColor=$Muted
New-Label $form 'Sitzung & Protokoll' 252 729 734 26 12 $TextColor | Out-Null
$out=New-Object System.Windows.Forms.TextBox
$out.Location=New-Object System.Drawing.Point(250,765); $out.Size=New-Object System.Drawing.Size(734,111)
$out.Multiline=$true; $out.ReadOnly=$true; $out.ScrollBars='Vertical'; $out.BorderStyle='None'
$out.BackColor=$Background; $out.ForeColor=$Muted; $out.Font=New-Object System.Drawing.Font('Consolas',9)
$form.Controls.Add($out)
$form.AcceptButton=$primary
$tooltips=New-Object Windows.Forms.ToolTip
$tooltips.SetToolTip($install,'Kopiert Mod und Bridge und speichert Rolle, Port und Sitzung. Öffnet das Spiel nicht. Im normalen Ablauf geschieht das automatisch.')
$tooltips.SetToolTip($replay,'Testlabor: spielt eine Bauaufnahme nach dem Neuladen am ursprünglichen Ort erneut ab. Nur im Test Gleiche Stelle verwenden.')
$tooltips.SetToolTip($recover,'Übernimmt den Gastgeberstand auf beiden PCs. Der Mitspieler muss nichts anklicken.')
New-Label $side '01  VERBINDEN' 24 402 185 24 9 $Accent | Out-Null
New-Label $side '02  SPIELSTAND TEILEN' 24 442 190 24 9 $Muted | Out-Null
New-Label $side '03  GEMEINSAM STARTEN' 24 482 185 24 9 $Muted | Out-Null


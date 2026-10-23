# Hit testing includes resize, real maximization, DPI scaling and scroll containers.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'launcher\launcher.ps1') -LibraryOnly
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'launcher\launcher.ps1'),[ref]$null,[ref]$null)
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-Fields'},$true)
Invoke-Expression $fn.Extent.Text
function Test-GameRunning {return $false}
function Test-LobbyCanStart {return $false}
$passed=0
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
function Check-Exposed($control){
    Check $control.Visible "Hidden control: $($control.Text)"
    $ancestor=$control.Parent
    while($ancestor){if($ancestor -is [Windows.Forms.ScrollableControl] -and $ancestor.AutoScroll){$ancestor.ScrollControlIntoView($control)};$ancestor=$ancestor.Parent}
    [Windows.Forms.Application]::DoEvents()
    # A field wider than a tiny viewport must remain reachable by scrolling;
    # hit-test the portion actually exposed instead of its offscreen midpoint.
    $visible=$control.RectangleToScreen($control.ClientRectangle);$ancestor=$control.Parent
    while($ancestor){$visible=[Drawing.Rectangle]::Intersect($visible,$ancestor.RectangleToScreen($ancestor.ClientRectangle));$ancestor=$ancestor.Parent}
    Check ($visible.Width -gt 0 -and $visible.Height -gt 0) "Control cannot be reached by scrolling: $($control.Text), $scale/$window/$role"
    $child=$control;$screen=New-Object Drawing.Point(($visible.X+[int]($visible.Width/2)),($visible.Y+[int]($visible.Height/2)))
    while($child.Parent){
        $parent=$child.Parent
        if(-not ($parent -is [Windows.Forms.ScrollableControl] -and $parent.AutoScroll)){
            Check ($parent.ClientRectangle.Contains($child.Bounds)) "Clipped control: $($control.Text), child=$($child.Bounds), parent=$($parent.ClientRectangle)"
        }
        $point=$parent.PointToClient($screen)
        Check ($parent.ClientRectangle.Contains($point)) "Control cannot be scrolled into view: $($control.Text), $scale/$window/$role, parent=$($parent.GetType().Name), point=$point, bounds=$($parent.ClientRectangle), child=$($child.Bounds), scroll=$($sessionPage.AutoScrollPosition)"
        $hit=$parent.GetChildAtPoint($point,[Windows.Forms.GetChildAtPointSkip]::Invisible)
        Check ([object]::ReferenceEquals($hit,$child)) "Covered control: $($control.Text), hit=$($hit.Text)"
        $child=$parent
    }
}
foreach($scale in @(1.0,1.5,2.0)){
    . (Join-Path $root 'launcher\view.ps1')
    try{
        $script:presence=[pscustomobject]@{Connected=$true};$hostRadio.Checked=$true;Update-Fields
        $form.Show();[Windows.Forms.Application]::DoEvents();$form.AutoScaleMode='None';$form.Scale((New-Object Drawing.SizeF($scale,$scale)))
        foreach($window in @('normal','compact','narrow','maximized')){
            if($window -eq 'compact'){$form.WindowState='Normal';$form.ClientSize=New-Object Drawing.Size([int](980*$scale),[int](720*$scale))}
            if($window -eq 'narrow'){$form.WindowState='Normal';$form.ClientSize=New-Object Drawing.Size(980,720)}
            if($window -eq 'maximized'){$form.WindowState='Maximized'}
            Resize-LauncherPages;[Windows.Forms.Application]::DoEvents()
            Check ($form.MaximizeBox -and $form.FormBorderStyle -eq 'Sizable') 'Launcher cannot be resized/maximized'
            foreach($role in @('host','join','test')){
                $hostRadio.Checked=$false;$clientRadio.Checked=$false;$loopRadio.Checked=$false
                switch($role){host{$hostRadio.Checked=$true};join{$clientRadio.Checked=$true};test{$loopRadio.Checked=$true}}
                Set-LauncherPage 'session';Update-Fields;$form.PerformLayout();[Windows.Forms.Application]::DoEvents()
                if($role -eq 'host'){
                    foreach($control in @($primary,$startBoth,$saveChoice,$hostAddress,$internetPortBox,$copyAddress,$internetSetup)){Check-Exposed $control}
                    Check (-not $primary.Bounds.IntersectsWith($startBoth.Bounds)) 'Host action buttons overlap'
                    Check (-not $copyAddress.Bounds.IntersectsWith($internetSetup.Bounds)) 'Connection buttons overlap'
                }elseif($role -eq 'join'){
                    foreach($control in @($friendQuick,$friendAdd,$ipBox,$clearAddress,$internetCheck,$joinStatus)){Check-Exposed $control}
                }else{Check-Exposed $primary;Check ($primary.Width -eq $joinStatus.Width) 'Test action does not fill its row'}
                foreach($control in @($gameBox,$browse,$workflowHint,$updateCheck,$updateZip,$updateStatus,$navFriends,$navGuide)){Check-Exposed $control}
                Check (-not $gameBox.Bounds.IntersectsWith($browse.Bounds)) 'Game folder input overlaps browse button'
                if($portBox.Visible){Check (-not $browse.Bounds.IntersectsWith($portBox.Bounds)) 'Browse button overlaps test port'}
            }
            Set-LauncherPage 'guide';Check-Exposed $guideText
            Check (-not $sessionPage.Visible -and $guidePage.Visible) 'Guide tab reveals session controls'
            Set-LauncherPage 'friends'
            foreach($control in @($friendName,$friendAddress,$friendSave,$friendNew,$friendList,$friendEdit,$friendRemove)){Check-Exposed $control}
            Check (-not $friendList.Bounds.IntersectsWith($friendEdit.Bounds)) 'Friend list overlaps its actions'
        }
    }finally{$form.Dispose()}
}
Write-Output "$passed launcher layout checks passed (four window sizes, real maximization, 100/150/200 percent)."

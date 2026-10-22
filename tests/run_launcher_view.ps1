# Real WinForms hit testing: DrawToBitmap alone does not detect sibling occlusion.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'launcher\launcher.ps1') -LibraryOnly
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'launcher\launcher.ps1'),[ref]$null,[ref]$null)
$fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-Fields'},$true)
Invoke-Expression $fn.Extent.Text
function Test-GameRunning { return $false }
function Test-LobbyCanStart { return $false }
$passed=0
function Check($ok,$message){if(-not $ok){throw $message}; $script:passed++}
function Check-Exposed($control) {
    Check $control.Visible "Hidden control: $($control.Text)"
    $child=$control
    while($child.Parent){
        $parent=$child.Parent
        Check ($parent.ClientRectangle.Contains($child.Bounds)) "Clipped control: $($control.GetType().Name) $($control.Text), bounds=$($child.Bounds), parent=$($parent.ClientRectangle)"
        $point=New-Object Drawing.Point(($child.Left+[int]($child.Width/2)),($child.Top+[int]($child.Height/2)))
        $hit=$parent.GetChildAtPoint($point,[Windows.Forms.GetChildAtPointSkip]::Invisible)
        Check ([object]::ReferenceEquals($hit,$child)) "Covered control: $($control.Text)"
        $child=$parent
    }
}
foreach($scale in @(1.0,1.5,2.0)){
    . (Join-Path $root 'launcher\view.ps1')
    try {
        $script:presence=[pscustomobject]@{Connected=$true}; $hostRadio.Checked=$true; Update-Fields
        $form.Show(); [Windows.Forms.Application]::DoEvents()
        $form.Scale((New-Object Drawing.SizeF($scale,$scale)))
        foreach($role in @('host','join','test','host')){
            $hostRadio.Checked=$false; $clientRadio.Checked=$false; $loopRadio.Checked=$false
            switch($role){host {$hostRadio.Checked=$true}; join {$clientRadio.Checked=$true}; test {$loopRadio.Checked=$true}}
            Update-Fields; $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()
            if($role -eq 'host'){
                Check-Exposed $primary; Check-Exposed $startBoth; Check-Exposed $saveChoice; Check-Exposed $hostAddress; Check-Exposed $internetPortBox
                Check-Exposed $copyAddress; Check-Exposed $internetSetup
                Check (-not @($hostPage.Controls | Where-Object {$_.Text -eq 'IPv4 automatisch'}).Count) 'IPv4 setup button still shown'
                Check (-not $copyAddress.Bounds.IntersectsWith($internetSetup.Bounds)) 'Internet buttons overlap'
                Check (-not $portBox.Visible) 'Internal port shown in normal host mode'
                Check (-not $primary.Bounds.IntersectsWith($startBoth.Bounds)) 'Host buttons overlap'
            }elseif($role -eq 'join'){Check-Exposed $joinStatus; Check-Exposed $clearAddress; Check (-not $portBox.Visible) 'Internal port shown when joining'}else{
                Check-Exposed $primary
                Check ($primary.Width -eq $joinStatus.Width) 'Test button does not fill the scaled workflow row'
            }
            Check-Exposed $workflowHint
            Check-Exposed $updateCheck;Check-Exposed $updateZip;Check-Exposed $updateStatus
        }
        $script:presence=$null; $hostRadio.Checked=$true; Update-Fields
        Check (-not $primary.Visible -and -not $startBoth.Visible) 'Host can share before a peer connects'
        Check-Exposed $joinStatus
        $script:transferBusy=$true; Update-Fields
        Check-Exposed $transfer; Check-Exposed $progressBar
        $script:transferBusy=$false
    } finally {$form.Dispose()}
}
Write-Output "$passed launcher layout checks passed (100%, 150%, 200%)."

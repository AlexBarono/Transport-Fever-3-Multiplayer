$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\tools\action-issues.ps1')
$passed=0
function Hex([string]$s){return ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($s))).Replace('-','').ToLowerInvariant()}
$one="[2026-10-09 12:56:59Z] [mp_probe]action issue local I1 peer.528 partial $(Hex 'Bahnhof Süd bei 5245.3, -7390.3') $(Hex 'game command rejected')"
$two="[mp_probe]action issue peer I1 scheduled_client.7 none $(Hex 'Gleis bei 50, 60') $(Hex 'existing node not found')"
$r=New-ActionIssueReader
Add-ActionIssueLine $r $one; Add-ActionIssueLine $r $one; Add-ActionIssueLine $r $two
if($r.Count -ne 2 -or $r.Issues.Count -ne 2){throw 'Duplicate or peer issue mishandled'}; $passed++
$details=Get-ActionIssueDetails $r
foreach($part in @('Bahnhof Süd','5245.3','TF3 hat die Ausführung abgelehnt','Möglicherweise teilweise','beim Mitspieler','anschluss wurde nicht gefunden','Kennung: peer.528')){
 if(-not $details.Contains($part)){throw "Missing readable detail: $part"}; $passed++
}
foreach($bad in @($one.Replace('partial','invalid'),$one+' injected', '[mp_probe]action issue local I1 p.1 none zz aa')){Add-ActionIssueLine $r $bad}
if($r.Count -ne 2){throw 'Malformed issue accepted'}; $passed++
Add-ActionIssueLine $r $one.Replace('issue local','issue peer')
if($r.Count -ne 2 -or $r.Issues.Count -ne 3){throw 'Same failure on both PCs counted twice or details lost'}; $passed++
if(-not (Get-ActionReasonText 'line assignment rejected: no path at 12.0, -30.0').Contains('keinen befahrbaren Weg')){throw 'Path diagnosis not explained'}; $passed++
if(-not (Get-ActionReasonText 'line assignment rejected: missing electrification').Contains('Elektrifizierung')){throw 'Electrification diagnosis not explained'}; $passed++
foreach($case in @(
 @('subvention offer not found or terms/rewards differ; no payout booked','Bedingungen oder Belohnungen'),
 @('subvention offer ambiguous','eindeutig'),
 @('subvention decision rejected or not applied by original game script','nicht bestätigt'),
 @('economy scheduling failed: held command queue full','Zeitplan'),
 @('loan limit reached in destination game','Höchstzahl'))){
 if(-not (Get-ActionReasonText $case[0]).Contains($case[1])){throw "Missing economy diagnosis: $($case[0])"}; $passed++
}
$finance="[mp_probe]action issue local I1 scheduled_host.77 none $(Hex 'Subvention annehmen: Waren nach Süd (Auszahlung 500000)') $(Hex 'subvention offer not found or terms/rewards differ; no payout booked')"
$company="[mp_probe]action issue peer I1 scheduled_client.78 partial $(Hex 'Unternehmen umbenennen: Süd AG') $(Hex 'game command rejected')"
Add-ActionIssueLine $r $finance; Add-ActionIssueLine $r $company
$details=Get-ActionIssueDetails $r
foreach($part in @('Auszahlung 500000','Unternehmen umbenennen: Süd AG','Konto, Subventionen','Bedingungen oder Belohnungen')){
 if(-not $details.Contains($part)){throw "Missing economy detail: $part"}; $passed++
}
Add-ActionIssueLine $r 'Loading game from file common.sav'
if($r.Count -ne 0 -or $r.Issues.Count){throw 'Old session issues retained after reload'}; $passed++
$path=Join-Path $env:TEMP ('tf3mp-issues-'+[guid]::NewGuid().ToString('N')+'.log')
try{
 [IO.File]::WriteAllText($path,('x'*300000)+"`n"+$one+"`n"+[string]::Empty,[Text.Encoding]::UTF8)
 $r=New-ActionIssueReader; Update-ActionIssues $r $path '123'
 if($r.Position -gt 262144 -or $r.Count){throw 'Read budget exceeded'}; $passed++
 Update-ActionIssues $r $path '123'
 if($r.Count -ne 1){throw 'Issue after long line not read'}; $passed++
 [IO.File]::AppendAllText($path,$two.Substring(0,30),[Text.Encoding]::UTF8); Update-ActionIssues $r $path '123'
 if($r.Count -ne 1){throw 'Incomplete issue interpreted'}; $passed++
 [IO.File]::AppendAllText($path,$two.Substring(30)+"`n",[Text.Encoding]::UTF8); Update-ActionIssues $r $path '123'
 if($r.Count -ne 2){throw 'Split issue lost'}; $passed++
 Update-ActionIssues $r $path '123'; if($r.Count -ne 2){throw 'Repeated read duplicated issues'}; $passed++
 [IO.File]::WriteAllText($path,"Loading game from file fresh.sav`n",[Text.Encoding]::UTF8); Update-ActionIssues $r $path '124'
 if($r.Count){throw 'Restart/truncation retained issues'}; $passed++
 for($i=1;$i -le 45;$i++){Add-ActionIssueLine $r $one.Replace('peer.528',"peer.$i")}
 if($r.Count -ne 45 -or $r.Issues.Count -ne 30 -or $r.Seen.Count -ne 30){throw 'History not bounded'}; $passed++
}finally{Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
Write-Output "$passed action issue tests passed"

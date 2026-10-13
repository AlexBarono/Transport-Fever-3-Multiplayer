# Fixed-source selection and launcher lifecycle, no sockets, router or game mutations.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\launcher\launcher.ps1') -LibraryOnly
$passed=0
function Check($ok,[string]$message) { if(-not $ok){throw $message}; $script:passed++ }
$messages=New-Object 'Collections.Generic.List[string]'
function Write-LauncherLog([string]$text) { $messages.Add($text) }
function New-TestTunnel {
    $t=[pscustomobject]@{ DiagnosticDirectory=''; DiagnosticBytesReceived=0L; DiagnosticBytesSent=0L; DiagnosticConnected=$false; DiagnosticLastError=''; EnableCount=0; SourceCalls=0; Kinds=@(); Paths=@(); Disposed=$false }
    $t | Add-Member ScriptMethod EnableDiagnosticReceiver { param($path) $this.EnableCount++; $this.DiagnosticDirectory=$path }
    $t | Add-Member ScriptMethod SetDiagnosticSources { param($kinds,$paths) $this.SourceCalls++; $this.Kinds=[string[]]$kinds; $this.Paths=[string[]]$paths }
    $t | Add-Member ScriptMethod Dispose { $this.Disposed=$true }
    return $t
}
function Force-Poll { if($script:internetProtocolState){$script:internetProtocolState.CheckedAt=[datetime]::MinValue} }
$fixture=Join-Path $env:TEMP ('tf3mp-protocol-launcher-'+[guid]::NewGuid().ToString('N'))
$originalLocal=$env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA=$fixture
    $game=Join-Path $fixture 'game'; $steamFixture=Join-Path $fixture 'steam'; $logs=Join-Path $fixture 'TF3MP\Logs'
    [void][IO.Directory]::CreateDirectory($game); [void][IO.Directory]::CreateDirectory($logs)
    $script:internetTunnel=$null; $script:internetRole=''
    Update-InternetProtocolSharing $game $steamFixture
    Check ($null -eq $script:internetProtocolState -and $messages.Count -eq 0) 'VPN/no Internet must do nothing'
    $script:internetTunnel=New-TestTunnel; $script:internetRole='client'
    Update-InternetProtocolSharing $game $steamFixture
    $t=$script:internetTunnel
    Check ($t.SourceCalls -eq 1 -and $t.EnableCount -eq 0 -and $t.Kinds.Count -eq 3) 'Client configures exactly the initially known sources'
    Check (($t.Kinds -join ',') -eq 'bridge,launcher,status' -and $t.Paths[0] -eq (Join-Path $game 'alut_proxy.log')) 'Only fixed diagnostic game paths are supplied'
    Update-InternetProtocolSharing $game $steamFixture
    Check ($t.SourceCalls -eq 1 -and $messages.Count -eq 1) 'Repeated timer does not reconfigure or spam logs'
    $stdout=Join-Path $steamFixture 'userdata\test\3493540\local\crash_dump\stdout.txt'
    [void][IO.Directory]::CreateDirectory((Split-Path $stdout -Parent)); [IO.File]::WriteAllText($stdout,"late game log`n")
    Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    Check ($t.Kinds -contains 'stdout' -and $t.Paths -contains $stdout) 'A missing game log is discovered after TF3 starts'
    $script:internetLogPath=Join-Path $logs "internet-20261013-220000-$PID.jsonl"
    [IO.File]::WriteAllText($script:internetLogPath,"{}`n")
    $transfer=Join-Path $logs "save-transfer-20261013-220001-$PID-live.jsonl"
    [IO.File]::WriteAllText($transfer,"{}`n")
    $foreign=Join-Path $logs 'save-transfer-20261013-220002-999999-foreign.jsonl'
    [IO.File]::WriteAllText($foreign,"{}`n")
    Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    Check ($t.Kinds.Count -eq 6 -and $t.Paths -contains $transfer -and $t.Paths -notcontains $foreign) 'Live receive-runspace trace found by current launcher PID only'
    Check ($t.Paths -notmatch 'alut_proxy.ini|alut_session.json|\.sav$') 'Settings, invitations and saves are never sources'
    $calls=$t.SourceCalls; Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    Check ($t.SourceCalls -eq $calls -and $messages.Count -eq 1) 'Unchanged sources do not repeat configuration notices'
    $next=Join-Path $logs "save-transfer-20261013-220003-$PID-next.jsonl"
    [IO.File]::WriteAllText($next,"{}`n"); (Get-Item -LiteralPath $next).LastWriteTimeUtc=[datetime]::UtcNow.AddSeconds(3)
    Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    Check ($t.Paths -contains $next -and $t.Paths -notcontains $transfer) 'New transfer attempts refresh the source path'
    $old=Join-Path $logs "save-transfer-20261010-220004-$PID-old.jsonl"
    [IO.File]::WriteAllText($old,"{}`n"); (Get-Item -LiteralPath $old).LastWriteTimeUtc=[datetime]::UtcNow.AddDays(-2)
    $selected=Get-InternetProtocolSources $game $steamFixture ([datetime]::UtcNow.AddDays(-1)) $logs
    Check ($selected.transfer -ne $old) 'Reused historical PID log is excluded'
    $t.DiagnosticBytesSent=2048; $t.DiagnosticConnected=$true
    Check ((Get-InternetProtocolSummary) -like '*verbunden*2 KiB*') 'Client summary exposes actual diagnostic progress'
    Stop-LauncherInternet
    Check ($t.Disposed -and $null -eq $script:internetProtocolState -and -not $script:internetRole) 'Stopping Internet clears diagnostic lifecycle'
    $script:internetTunnel=New-TestTunnel; $script:internetRole='host'
    Update-InternetProtocolSharing $game $steamFixture; $t=$script:internetTunnel
    Check ($t.EnableCount -eq 1 -and $t.SourceCalls -eq 0 -and $t.DiagnosticDirectory -eq (Join-Path $logs 'Mitspieler')) 'Host receives under its own diagnostic folder and uploads nothing'
    Check ((Get-InternetProtocolSummary) -like '*Warte auf Diagnosedaten*') 'Receiver root alone is not a successful peer upload'
    $before=$messages.Count; $t.DiagnosticBytesReceived=37; $t.DiagnosticDirectory=Join-Path $logs 'Mitspieler\session-test'
    Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    Check ($messages.Count -eq $before+1 -and $messages[-1] -like '*session-test*' -and $t.EnableCount -eq 1) 'Host logs received session path once, without per-chunk spam'
    $t.DiagnosticLastError='IOException'; Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    $afterError=$messages.Count; Force-Poll; Update-InternetProtocolSharing $game $steamFixture
    Check ($messages.Count -eq $afterError -and $messages[-1] -like '*Spielkanal läuft unabhängig*') 'Diagnostic errors remain isolated and are logged only on change'
    $replacement=New-TestTunnel; $script:internetTunnel=$replacement
    Update-InternetProtocolSharing $game $steamFixture
    Check ($replacement.EnableCount -eq 1) 'A new invitation/tunnel starts a separate diagnostic receiver lifecycle'
    Stop-LauncherInternet
    Check ((Get-InternetProtocolSummary) -eq '') 'VPN mode has no diagnostic transport summary'
    $parseErrors=$null; [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\tools\internet-diagnostics.ps1'),[ref]$null,[ref]$parseErrors)
    Check (-not $parseErrors) 'New PowerShell helper parses'
} finally {
    $script:internetTunnel=$null; $script:internetRole=''; Reset-InternetProtocolSharing; $env:LOCALAPPDATA=$originalLocal
    $resolved=[IO.Path]::GetFullPath($fixture); $temporaryRoot=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($temporaryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup escaped TEMP'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
Write-Output "$passed Internet protocol launcher checks passed. No sockets or game changes."

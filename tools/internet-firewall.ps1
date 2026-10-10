param([ValidateRange(1024,65535)][int]$Port, [Parameter(Mandatory=$true)][string]$Program, [ValidateSet('','host','client')][string]$GameMode='', [Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internet.ps1')
try {
    $ruleArguments = if($GameMode) { Get-GameFirewallArguments $Port $Program $GameMode } else { Get-InternetFirewallArguments $Port $Program }
    $existing = Get-NetFirewallRule -Name $ruleArguments.Name -ErrorAction SilentlyContinue
    if ($existing) { $existing | Remove-NetFirewallRule }
    New-NetFirewallRule @ruleArguments | Out-Null
    if(-not (Test-LauncherFirewallRule $ruleArguments)) { throw 'Die Regel wird durch Windows-Richtlinien nicht angewendet.' }
    @{ok=$true} | ConvertTo-Json -Compress | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    exit 0
} catch { @{ok=$false; error=$_.Exception.Message} | ConvertTo-Json -Compress | Set-Content -LiteralPath $ResultPath -Encoding UTF8; exit 1 }

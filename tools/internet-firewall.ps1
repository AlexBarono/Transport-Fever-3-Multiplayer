param([ValidateRange(1024,65535)][int]$Port, [Parameter(Mandatory=$true)][string]$Program)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internet.ps1')
try {
    $ruleArguments = Get-InternetFirewallArguments $Port $Program
    $existing = Get-NetFirewallRule -Name $ruleArguments.Name -ErrorAction SilentlyContinue
    if ($existing) { $existing | Remove-NetFirewallRule }
    New-NetFirewallRule @ruleArguments | Out-Null
    exit 0
} catch { exit 1 }

# Controlled local comparison; no game processes, game folders or external peers.
[CmdletBinding()]
param([int]$Megabytes = 64, [int]$ReceiptDelayMs = 60, [string]$ReportPath = '')
$ErrorActionPreference = 'Stop'
if ($Megabytes -lt 16 -or $Megabytes -gt 512 -or $ReceiptDelayMs -lt 0 -or $ReceiptDelayMs -gt 500) { throw 'Invalid benchmark settings.' }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/save-transfer.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'save-transfer-relay.cs')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('tf3mp-transfer-benchmark-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary) | Out-Null
$script:SaveTransferLogDirectory = Join-Path $temporary 'metrics'
$results = @()
try {
	$path = Join-Path $temporary 'source.sav'
	$file = [IO.File]::Create($path)
	try { $block = New-Object byte[] 1MB; for ($i=0;$i -lt $Megabytes;$i++) { $file.Write($block,0,$block.Length) } } finally { $file.Dispose() }
	$source = New-Object TF3MP.TransferFile
	$source.Path=$path; $source.Name='source.sav'; $source.Length=(Get-Item -LiteralPath $path).Length; $source.Hash=Get-FileSha256 $path
	foreach ($continuous in $false,$true) {
		$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $listener.Start()
		$relay=$null; $send=$null; $receive=$null
		try {
			$relay=New-Object TF3MPReceiptRelay($listener.LocalEndpoint.Port,4,$ReceiptDelayMs)
			$destination=New-Object TF3MP.TransferFile
			$destination.Path=Join-Path $temporary 'destination.part'; $destination.Name=$source.Name; $destination.Length=$source.Length; $destination.Hash=$source.Hash
			$token=[Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N')
			$clock=[Diagnostics.Stopwatch]::StartNew()
			$send=[TF3MP.TransferJob]::Send($listener,[Net.IPAddress]::Loopback,$token,[TF3MP.TransferFile[]]@($source),4,$continuous)
			$receive=[TF3MP.TransferJob]::Receive('127.0.0.1',$relay.Port,$token,[TF3MP.TransferFile[]]@($destination),4,$continuous)
			Wait-SaveJob $send { $false } 'Schicke ...' $source.Length | Out-Null
			Wait-SaveJob $receive { $false } 'Empfange ...' $source.Length | Out-Null
			if (-not (Test-SameBytes $source.Hash (Get-FileSha256 $destination.Path))) { throw 'Hash mismatch.' }
			$results += [pscustomobject]@{ method=$send.Method; bytes=$send.Bytes; streams=$send.Streams; receipt_delay_ms=$ReceiptDelayMs; data_s=[Math]::Round($send.Seconds,3); mib_per_s=[Math]::Round($send.Bytes/1MB/$send.Seconds,2); total_s=[Math]::Round($clock.Elapsed.TotalSeconds,3); verified=$true }
		} finally { if ($send) { $send.Cancel() }; if ($receive) { $receive.Cancel() }; if ($relay) { $relay.Dispose() }; $listener.Stop() }
	}
	$json = $results | ConvertTo-Json
	if ($ReportPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),$json,(New-Object Text.UTF8Encoding($false))) }
	Write-Output $json
} finally {
	$resolved=[IO.Path]::GetFullPath($temporary)
	if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup escaped TEMP.' }
	Remove-Item -LiteralPath $resolved -Recurse -Force
}

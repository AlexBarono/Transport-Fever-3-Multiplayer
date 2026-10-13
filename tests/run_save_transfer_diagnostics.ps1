# Isolated diagnostic regressions: no sockets, launcher or game process are opened.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\save-transfer.ps1')
$passed = 0; $failed = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Test([string]$Name, $Body) {
	try { & $Body; $script:passed++ } catch { $script:failed++; Write-Host "FAIL ${Name}: $($_.Exception.Message)" }
}
$diagRoot = Join-Path ([IO.Path]::GetTempPath()) ('tf3mp-transfer-diagnostics-' + [Guid]::NewGuid().ToString('N'))
$script:SaveTransferLogDirectory = $diagRoot
function Rows { return @(Get-Content -LiteralPath $script:SaveTransferTrace.Path | ForEach-Object { $_ | ConvertFrom-Json }) }
try {
	Test 'nested socket failures retain system codes without disclosing exception messages' {
		$secret = 'INVITATION_SECRET password=PASSWORD_SECRET [2001:db8::7] 192.0.2.8 C:\PRIVATE_SAVE.sav https://user:secret@example.test/ ' + ('a' * 64)
		$socket = New-Object Net.Sockets.SocketException(10054)
		$failure = New-Object IO.IOException($secret, $socket)
		Start-SaveTransferTrace 'client'; Write-SaveTransferTrace 'attempt' @{ number = 2 }; Write-SaveTransferTrace 'connected'
		Write-SaveTransferTrace 'receive_failed' (Get-SaveTransferErrorFields $failure)
		$row = (Rows)[-1]
		Assert ($row.error_chain.Count -eq 2 -and $row.error_chain[1].socket_error -eq 'ConnectionReset' -and $row.error_chain[1].socket_code -eq 10054) 'actual inner socket reset is retained'
		Assert ($row.failure_phase -eq 'header' -and $row.attempt -eq 2 -and $row.connection_attempt -eq 1) 'phase and retry budget are explicit'
		$raw = Get-Content -LiteralPath $script:SaveTransferTrace.Path -Raw
		Assert ($raw -notmatch 'INVITATION_SECRET|PASSWORD_SECRET|2001:db8|192\.0\.2|PRIVATE_SAVE|example\.test|[a-f0-9]{64}') 'no raw secret, address, path or token is logged'
	}
	Test 'error chains and output are bounded for deeply nested peer-controlled messages' {
		$failure = New-Object Exception(('secret ' * 20000))
		for ($i = 0; $i -lt 20; $i++) { $failure = New-Object Exception(('secret ' * 20000), $failure) }
		$details = Get-SaveTransferErrorFields $failure
		Assert ($details.error_chain.Count -eq 8 -and $details.error_chain_truncated) 'nested chains stop at eight identities'
		Assert (($details | ConvertTo-Json -Depth 5 -Compress).Length -lt 2000) 'log size does not grow with exception message size'
	}
	Test 'host readiness and refused connections remain distinct without changing retry semantics' {
		$waiting = New-NoHostError 'SECRET readiness text' 'host_not_ready'
		$refused = New-NoHostError 'SECRET endpoint text' 'connect_failed' (New-Object Net.Sockets.SocketException(10061))
		Assert ((Get-SaveTransferErrorFields $waiting).error_reason -eq 'host_not_ready') 'WAIT is distinguished from a broken connection'
		$details = Get-SaveTransferErrorFields $refused
		Assert ($details.error_reason -eq 'connect_failed' -and $details.error_chain[-1].socket_error -eq 'ConnectionRefused') 'discarded connection cause survives only in diagnostics'
		Assert ((Test-NoHostError $refused) -and -not (Get-TransferNetworkError $refused) -and $null -eq $refused.InnerException) 'no-host wait/retry behavior is preserved'
	}
	Test 'a cancelled worker cannot replace the original failed phase or socket cause' {
		Start-SaveTransferTrace 'client'; Write-SaveTransferTrace 'attempt' @{ number = 1 }
		$work = [pscustomobject]@{}; $work | Add-Member ScriptMethod Wait { param($Milliseconds) return $true }
		$job = [pscustomobject]@{ Kind = 'receive'; Phase = 'data'; Method = 'continuous'; Streams = 4; Bytes = [int64]28106008; LaneBytes = @(7471689,6322152,6947518,7364649); Work = $work; Error = (New-Object IO.IOException('SECRET', (New-Object Net.Sockets.SocketException(10054)))); Result = $null; FileReadMs = 0; FileWriteMs = 106.3; NetworkReadMs = 69374.2; NetworkWriteMs = 0; AckWaitMs = 0; VerifySeconds = 0; Seconds = 17.137; SendBufferBytes = 8388608; ReceiveBufferBytes = 8388608 }
		$job | Add-Member ScriptMethod Cancel { $this.Error = New-Object OperationCanceledException('secondary cancellation'); $this.Phase = 'failed' }
		try { Wait-SaveJob $job { $false } 'receive' 100000000 | Out-Null } catch {}
		$row = @((Rows) | Where-Object event -eq 'job_failed')[-1]
		Assert ($row.phase -eq 'failed' -and $row.failure_phase -eq 'data' -and $row.bytes -eq 28106008) 'last observed data phase and exact completed byte count survive worker cancellation'
		Assert ($row.error_chain[-1].socket_error -eq 'ConnectionReset') 'original socket cause survives cancellation'
		Assert ($row.lane_bytes.Count -eq 4 -and ($row.lane_bytes | Measure-Object -Sum).Sum -eq 28106008 -and $row.failure_lane_known -eq $false) 'all four offsets are preserved without inventing a failing lane'
	}
	Test 'waiting attempts get unique connection numbers and do not reuse previous byte offsets' {
		Start-SaveTransferTrace 'client'; Write-SaveTransferTrace 'attempt' @{ number = 1 }
		Set-SaveTransferTraceProgress 'receive' 123456
		Write-SaveTransferTrace 'receive_failed' (Get-SaveTransferErrorFields (New-Object IO.EndOfStreamException))
		Write-SaveTransferTrace 'attempt' @{ number = 1 }; Write-SaveTransferTrace 'connected'
		Write-SaveTransferTrace 'receive_failed' (Get-SaveTransferErrorFields (New-NoHostError 'SECRET' 'host_not_ready'))
		$rows = @((Rows) | Where-Object event -eq 'receive_failed')
		Assert ($rows[0].bytes -eq 123456 -and $rows[0].failure_phase -eq 'data') 'first attempt keeps its own offset'
		Assert ($rows[1].attempt -eq 1 -and $rows[1].connection_attempt -eq 2 -and $null -eq $rows[1].bytes -and $rows[1].failure_phase -eq 'header') 'readiness polling does not masquerade as a retry or retain stale progress'
	}
	Test 'legacy completed chunks retain their final byte offset for a subsequent failure' {
		$memory = New-Object IO.MemoryStream
		try {
			Start-SaveTransferTrace 'host'; Write-SaveTransferTrace 'attempt' @{ number = 1 }
			Write-SaveData $memory (New-Object byte[] 37) 0 37 (New-SaveProgress) { $false } 'send' 100 137
			Write-SaveTransferTrace 'send_failed' (Get-SaveTransferErrorFields (New-Object IO.EndOfStreamException))
			$row = (Rows)[-1]
			Assert ($row.bytes -eq 137 -and $row.lane_bytes[0] -eq 137 -and $row.failure_phase -eq 'data') 'sender offset includes the last completed chunk'
			$memory.Position = 0
			Start-SaveTransferTrace 'client'; Write-SaveTransferTrace 'attempt' @{ number = 1 }
			$read = Read-SaveData $memory (New-Object byte[] 37) 37 (New-SaveProgress) { $false } 'receive' 200 237
			Set-SaveTransferTracePhase 'verify'
			Write-SaveTransferTrace 'receive_failed' (Get-SaveTransferErrorFields (New-Object IO.InvalidDataException))
			$row = (Rows)[-1]
			Assert ($read -eq 37 -and $row.bytes -eq 237 -and $row.lane_bytes[0] -eq 237 -and $row.failure_phase -eq 'verify') 'receiver offset and later verification phase remain distinct'
		} finally { $memory.Dispose() }
	}
	Test 'diagnostic write errors cannot replace a transfer error' {
		$previous = $script:SaveTransferTrace.Path
		try { $script:SaveTransferTrace.Path = $diagRoot; Write-SaveTransferTrace 'receive_failed' (Get-SaveTransferErrorFields (New-Object IO.EndOfStreamException)) }
		finally { $script:SaveTransferTrace.Path = $previous }
	}
} finally {
	$script:SaveTransferTrace = $null
	$resolvedDiagRoot = [IO.Path]::GetFullPath($diagRoot)
	$resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
	if (-not $resolvedDiagRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) { throw 'Diagnostic cleanup escaped TEMP.' }
	if (Test-Path -LiteralPath $resolvedDiagRoot) { Remove-Item -LiteralPath $resolvedDiagRoot -Recurse -Force }
}
Write-Host "$passed save transfer diagnostic tests passed, $failed failed"
if ($failed) { exit 1 }

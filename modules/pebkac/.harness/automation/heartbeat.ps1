# PEBKAC Harness Heartbeat for Windows PowerShell
# Auto-generated during unboxing (F17 fix: Windows support)
# Run every 5 minutes via Windows Task Scheduler

param(
    [string]$HarnessDir = "$HOME\.harness"
)

$ErrorActionPreference = "SilentlyContinue"

# Check vault accessibility
$vaultConfig = Join-Path $HarnessDir "vault\config.yaml"
if (Test-Path $vaultConfig) {
    Write-Host "[heartbeat] Vault config: OK"
} else {
    Write-Host "[heartbeat] Vault config: MISSING"
}

# Check checkpoint age
$latest = Join-Path $HarnessDir "checkpoints\latest.json"
if (Test-Path $latest) {
    $mtime = (Get-Item $latest).LastWriteTimeUtc
    $age = [int](New-TimeSpan -Start $mtime -End (Get-Date)).TotalSeconds
    if ($age -gt 3600) {
        Write-Host "[heartbeat] Checkpoint: STALE (${age}s old)"
    } else {
        Write-Host "[heartbeat] Checkpoint: OK (${age}s old)"
    }
} else {
    Write-Host "[heartbeat] Checkpoint: NONE"
}

# Update heartbeat timestamp
$heartbeatFile = Join-Path $HarnessDir "state\last-heartbeat.txt"
(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") | Out-File -FilePath $heartbeatFile -Encoding utf8

Write-Host "[heartbeat] $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') complete"

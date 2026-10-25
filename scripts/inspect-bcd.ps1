# Elevated inspection: what does the BCD/firmware menu look like now, and is the file on S:?
$ErrorActionPreference = 'Continue'
$log = 'E:\AI\gpu-unlock-win\logs\inspect-bcd.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    Write-Output '=== S: files ==='
    Get-ChildItem -LiteralPath 'S:\' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object FullName, Length | Format-Table -AutoSize | Out-String | Write-Output
    Write-Output '=== bcdedit /enum firmware ==='
    & bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String | Write-Output
    Write-Output '=== descriptions in all entries ==='
    $all = & bcdedit /enum all 2>&1 | Out-String
    ($all -split "`r?`n") | Where-Object { $_ -match '^(identifier|description|path|device)\s' } | Write-Output
    Write-Output '=== any GPU entry ==='
    ($all -split "`r?`n") | Select-String -Pattern 'GPU|WindowsGPUUnlock|OBSERVE' | Write-Output
    Write-Output '=== registration state files ==='
    Get-ChildItem -LiteralPath 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK\research\headless' -Filter '*registration*' -ErrorAction SilentlyContinue |
        Select-Object Name, Length | Format-Table -AutoSize | Out-String | Write-Output
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

# Elevated: copy the observation capture off the ESP into the workspace for analysis.
$ErrorActionPreference = 'Continue'
$log  = 'E:\AI\gpu-unlock-win\logs\collect-capture.log'
$dest = 'E:\AI\gpu-unlock-win\captures'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
New-Item -ItemType Directory -Force -Path $dest       | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    Write-Output '=== S:\ tree ==='
    Get-ChildItem -LiteralPath 'S:\' -Recurse -Force -ErrorAction SilentlyContinue |
        Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String | Write-Output
    $src = 'S:\RTX3090-UNLOCK'
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output '=== copied to workspace ==='
        Get-ChildItem -LiteralPath $dest -Recurse -File |
            Select-Object FullName, Length | Format-Table -AutoSize | Out-String | Write-Output
    } else {
        Write-Output 'capture directory not present on S:'
    }
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

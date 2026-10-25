# Elevated: remove the orphan observation entry created before the locale fix, then register.
# Only entries whose description is exactly the observation name are removed.
$ErrorActionPreference = 'Continue'
$repo = 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK'
$log  = 'E:\AI\gpu-unlock-win\logs\register-observe.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    $name = 'GPU Headless Observe - NO UNLOCK'
    Write-Output '=== existing entries before cleanup ==='
    $all = & bcdedit /enum all 2>&1 | Out-String
    $blocks = $all -split "(?m)^-{5,}\s*$"
    foreach ($b in $blocks) {
        if ($b -match [regex]::Escape($name)) {
            $id = ([regex]::Match($b, '(?mi)^(?:identifier|标识符)\s+(\{[0-9a-f-]{36}\})')).Groups[1].Value
            $isFwChild = $b -match '(?m)^(?:device|设备)\s+partition='
            Write-Output "found orphan: id=$id loaderEntry=$isFwChild"
            if ($id) {
                & bcdedit /delete $id /f 2>&1 | Out-String | Write-Output
                Write-Output "delete exit: $LASTEXITCODE"
            }
        }
    }

    Write-Output '=== staging dir ==='
    $targetDir = 'S:\EFI\WindowsGPUUnlock'
    if (-not (Test-Path -LiteralPath $targetDir)) { [void][IO.Directory]::CreateDirectory($targetDir) }

    Write-Output '=== register ==='
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'research\headless\register-observe.ps1') -Register 2>&1 | Out-String | Write-Output
    Write-Output "register-observe exit: $LASTEXITCODE"

    Write-Output '=== firmware order after ==='
    & bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String | Write-Output
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

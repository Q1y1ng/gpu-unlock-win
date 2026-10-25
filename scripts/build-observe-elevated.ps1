# Elevated wrapper: build the observation (diagnostic-only) EFI.
$ErrorActionPreference = 'Continue'
$repo = 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK'
$log  = 'E:\AI\gpu-unlock-win\logs\build-observe.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'research\headless\build-observe.ps1') `
        -UnlockDriveLetter S `
        -WindowsEspGuid '2e82c91f-e37b-41c4-8205-0330180354b4' `
        -Clang 'C:\Users\s3431\AppData\Local\Programs\Swift\Toolchains\6.3.2+Asserts\usr\bin\clang.exe' `
        -LldLink 'C:\Users\s3431\AppData\Local\Programs\Swift\Toolchains\6.3.2+Asserts\usr\bin\lld-link.exe' `
        -Python 'E:\AI\gpu-unlock-bench\.venv\Scripts\python.exe' `
        -HardwareProfile 'lenovo-82rf-3060' 2>&1 | Out-String | Write-Output
    Write-Output "build-observe exit: $LASTEXITCODE"
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

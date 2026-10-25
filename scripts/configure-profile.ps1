# Elevated wrapper: run upstream Configure.ps1 for this machine and log everything.
$ErrorActionPreference = 'Continue'
$repo = 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK'
$log  = 'E:\AI\gpu-unlock-win\logs\configure.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'internal-boot\Configure.ps1') `
        -UnlockDriveLetter S `
        -WindowsEspGuid '2e82c91f-e37b-41c4-8205-0330180354b4' `
        -HardwareProfile 'lenovo-82rf-3060' 2>&1 | Out-String | Write-Output
    Write-Output "Configure.ps1 exit: $LASTEXITCODE"
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

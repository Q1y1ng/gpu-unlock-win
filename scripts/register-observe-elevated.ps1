# Elevated wrapper: stage OBSERVE.EFI onto S: and append a manual F12/F8 entry.
# Preserves the existing firmware boot order; no BootNext, no reboot, no BIOS change.
$ErrorActionPreference = 'Continue'
$repo = 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK'
$log  = 'E:\AI\gpu-unlock-win\logs\register-observe.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    # The upstream staging step uses [IO.File]::Copy and assumes the directory exists.
    $targetDir = 'S:\EFI\WindowsGPUUnlock'
    if (-not (Test-Path -LiteralPath $targetDir)) { [void][IO.Directory]::CreateDirectory($targetDir) }
    Write-Output "staging dir ready: $targetDir"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'research\headless\register-observe.ps1') -Register 2>&1 | Out-String | Write-Output
    Write-Output "register-observe exit: $LASTEXITCODE"
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

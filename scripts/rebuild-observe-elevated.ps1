# Elevated: create the capture directory the diagnostic expects, then rebuild OBSERVE.EFI.
$ErrorActionPreference = 'Continue'
$repo = 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK'
$log  = 'E:\AI\gpu-unlock-win\logs\build-observe.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    # The diagnostic writes \RTX3090-UNLOCK\DIAG00.TXT and does not create the directory.
    $capDir = 'S:\RTX3090-UNLOCK'
    if (-not (Test-Path -LiteralPath $capDir)) { [void][IO.Directory]::CreateDirectory($capDir) }
    Write-Output "capture dir exists: $(Test-Path -LiteralPath $capDir)"
    # Prove the directory is writable by the FAT32 ESP before trusting it.
    $probe = Join-Path $capDir 'WRITE-TEST.TXT'
    [IO.File]::WriteAllText($probe, 'write test')
    Write-Output "write test ok: $([IO.File]::Exists($probe))"
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'research\headless\build-observe.ps1') `
        -UnlockDriveLetter S `
        -WindowsEspGuid '2e82c91f-e37b-41c4-8205-0330180354b4' `
        -Clang 'C:\Users\s3431\AppData\Local\Programs\Swift\Toolchains\6.3.2+Asserts\usr\bin\clang.exe' `
        -LldLink 'C:\Users\s3431\AppData\Local\Programs\Swift\Toolchains\6.3.2+Asserts\usr\bin\lld-link.exe' `
        -Python 'E:\AI\gpu-unlock-bench\.venv\Scripts\python.exe' `
        -HardwareProfile 'lenovo-82rf-3060' 2>&1 | Out-String | Write-Output
    Write-Output "build-observe exit: $LASTEXITCODE"

    $new = Get-ChildItem -LiteralPath (Join-Path $repo 'research\headless\build') -Filter 'OBSERVE.EFI' -ErrorAction SilentlyContinue
    if ($new) { Write-Output ("new OBSERVE.EFI sha256=" + (Get-FileHash -LiteralPath $new.FullName).Hash) }
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

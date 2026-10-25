# Elevated: archive the previous observation image, rebuild, replace the boot entry, re-register.
# ASCII-only: Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI.
$ErrorActionPreference = 'Continue'
$repo = 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK'
$log  = 'E:\AI\gpu-unlock-win\logs\reregister-observe.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null

$name      = 'GPU Headless Observe - NO UNLOCK'
$observeEf = 'S:\EFI\WindowsGPUUnlock\OBSERVE.EFI'

function Get-ObserveEntries {
    param([string]$All)
    $hits = @()
    foreach ($block in ($All -split "(?m)^-{5,}\s*$")) {
        $desc = ([regex]::Match($block, '(?mi)^description\s+(.+?)\s*$')).Groups[1].Value
        if ($desc -cne $name) { continue }
        $id = ''
        foreach ($line in ($block -split "`r?`n")) {
            if ($line -match '^\s*displayorder\b') { continue }
            $m = [regex]::Match($line, '^\s*\S+\s+(\{[0-9a-fA-F-]{36}\})\s*$')
            if ($m.Success) { $id = $m.Groups[1].Value; break }
        }
        $hits += [pscustomobject]@{ Id = $id; Path = ([regex]::Match($block, '(?mi)^path\s+(.+?)\s*$')).Groups[1].Value }
    }
    return $hits
}

try {
    Write-Output '=== archive previous observation image ==='
    $buildDir = Join-Path $repo 'research\headless\build'
    $oldEfi   = Join-Path $buildDir 'OBSERVE.EFI'
    if (Test-Path -LiteralPath $oldEfi) {
        $archive = Join-Path $buildDir 'archive'
        [void][IO.Directory]::CreateDirectory($archive)
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Move-Item -LiteralPath $oldEfi -Destination (Join-Path $archive "OBSERVE-$stamp.EFI") -Force
        Write-Output "archived old OBSERVE.EFI ($stamp)"
    }

    Write-Output '=== rebuild observation EFI ==='
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'research\headless\build-observe.ps1') `
        -UnlockDriveLetter S `
        -WindowsEspGuid '2e82c91f-e37b-41c4-8205-0330180354b4' `
        -Clang 'C:\Users\s3431\AppData\Local\Programs\Swift\Toolchains\6.3.2+Asserts\usr\bin\clang.exe' `
        -LldLink 'C:\Users\s3431\AppData\Local\Programs\Swift\Toolchains\6.3.2+Asserts\usr\bin\lld-link.exe' `
        -Python 'E:\AI\gpu-unlock-bench\.venv\Scripts\python.exe' `
        -HardwareProfile 'lenovo-82rf-3060' 2>&1 | Out-String | Write-Output
    if ($LASTEXITCODE -ne 0) { throw 'rebuild failed' }
    $newHash = (Get-FileHash -LiteralPath $observeEf -ErrorAction SilentlyContinue).Hash
    Write-Output "built OBSERVE.EFI on the workspace"

    Write-Output '=== remove previous registration ==='
    $all = & bcdedit /enum all 2>&1 | Out-String
    $hits = @(Get-ObserveEntries -All $all)
    Write-Output "existing observation entries: $($hits.Count)"
    foreach ($h in $hits) {
        Write-Output ("deleting " + $h.Id + " path=" + $h.Path)
        & bcdedit /delete $h.Id /f 2>&1 | Out-String | Write-Output
        Write-Output "delete exit: $LASTEXITCODE"
    }
    $state = Join-Path $repo 'research\headless\registration.local.json'
    if (Test-Path -LiteralPath $state) { Remove-Item -LiteralPath $state -Force; Write-Output 'removed stale registration state' }

    Write-Output '=== replace staged EFI and register ==='
    if (-not (Test-Path -LiteralPath 'S:\EFI\WindowsGPUUnlock')) { [void][IO.Directory]::CreateDirectory('S:\EFI\WindowsGPUUnlock') }
    $staged = Join-Path $repo 'research\headless\build\OBSERVE.EFI'
    if (Test-Path -LiteralPath $observeEf) { Remove-Item -LiteralPath $observeEf -Force }
    [IO.File]::Copy($staged, $observeEf, $false)
    Write-Output ("staged hash: " + (Get-FileHash -LiteralPath $observeEf).Hash)

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'research\headless\register-observe.ps1') -Register 2>&1 | Out-String | Write-Output
    Write-Output "register exit: $LASTEXITCODE"

    Write-Output '=== firmware order ==='
    & bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String | Write-Output
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

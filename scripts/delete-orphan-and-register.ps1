# Elevated: remove the one orphan observation entry (resolved and asserted first), then register.
# ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI.
$ErrorActionPreference = 'Continue'
$repo = 'E:\AI\gpu-unlock-win\Windows-GPU-UNLOCK'
$log  = 'E:\AI\gpu-unlock-win\logs\register-observe.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null

$name = 'GPU Headless Observe - NO UNLOCK'
$bootPath = '\EFI\Microsoft\Boot\bootmgfw.efi'

function Get-ObserveEntry {
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
        $hits += [pscustomobject]@{
            Id   = $id
            Path = ([regex]::Match($block, '(?mi)^path\s+(.+?)\s*$')).Groups[1].Value
        }
    }
    return $hits
}

try {
    $fw = & bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String
    $all = & bcdedit /enum all 2>&1 | Out-String
    $hits = @(Get-ObserveEntry -All $all)
    Write-Output "observation entries found: $($hits.Count)"
    $hits | Format-List | Out-String | Write-Output

    if ($hits.Count -eq 1) {
        $id = $hits[0].Id
        if (-not $id) { throw 'could not resolve the identifier of the orphan entry' }
        if ($fw -match [regex]::Escape($id)) { throw "entry $id is already in the firmware order; aborting cleanup" }
        if ($hits[0].Path -ne $bootPath) { throw "orphan path is '$($hits[0].Path)', expected '$bootPath'; aborting" }
        Write-Output "deleting exactly $id"
        & bcdedit /delete $id /f 2>&1 | Out-String | Write-Output
        Write-Output "delete exit: $LASTEXITCODE"
        $all2 = & bcdedit /enum all 2>&1 | Out-String
        if ($all2 -match [regex]::Escape($id)) { throw "entry $id still present after delete" }
        if (@(Get-ObserveEntry -All $all2).Count -ne 0) { throw 'observation entries remain after cleanup' }
        Write-Output 'cleanup verified: 0 observation entries remain'
    }
    elseif ($hits.Count -gt 1) { throw 'more than one observation entry exists; manual review required' }
    else { Write-Output 'no orphan entry present; nothing to clean' }

    if (-not (Test-Path -LiteralPath 'S:\EFI\WindowsGPUUnlock')) { [void][IO.Directory]::CreateDirectory('S:\EFI\WindowsGPUUnlock') }

    Write-Output '=== register ==='
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'research\headless\register-observe.ps1') -Register 2>&1 | Out-String | Write-Output
    Write-Output "register-observe exit: $LASTEXITCODE"

    Write-Output '=== firmware displayorder after ==='
    & bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String | Write-Output
    Write-Output '=== observation entry after ==='
    (& bcdedit /enum all 2>&1 | Out-String) -split "(?m)^-{5,}\s*$" | Where-Object { $_ -match [regex]::Escape($name) } | Out-String | Write-Output
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

# Elevated, READ-ONLY: locate the observation loader entry by exact description.
# ASCII-only on purpose: PowerShell 5.1 reads BOM-less .ps1 as ANSI, so no non-ASCII literals.
$ErrorActionPreference = 'Continue'
$log = 'E:\AI\gpu-unlock-win\logs\find-observe-entry.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
    $name = 'GPU Headless Observe - NO UNLOCK'
    $all = & bcdedit /enum all 2>&1 | Out-String
    $fw  = & bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String
    $hits = @()
    foreach ($block in ($all -split "(?m)^-{5,}\s*$")) {
        $desc = ([regex]::Match($block, '(?mi)^description\s+(.+?)\s*$')).Groups[1].Value
        if ($desc -ceq $name) {
            $id = ''
            foreach ($line in ($block -split "`r?`n")) {
                if ($line -match '^\s*displayorder\b') { continue }
                $m = [regex]::Match($line, '^\s*\S+\s+(\{[0-9a-fA-F-]{36}\})\s*$')
                if ($m.Success) { $id = $m.Groups[1].Value; break }
            }
            $dev  = ([regex]::Match($block, '(?mi)^device\s+(.+?)\s*$')).Groups[1].Value
            $path = ([regex]::Match($block, '(?mi)^path\s+(.+?)\s*$')).Groups[1].Value
            $hits += [pscustomobject]@{
                Id             = $id
                Device         = $dev
                Path           = $path
                InFirmwareOrder = [bool]($fw -match [regex]::Escape($id))
            }
        }
    }
    Write-Output "MATCH_COUNT=$($hits.Count)"
    $hits | Format-List | Out-String | Write-Output
    Write-Output '=== firmware displayorder ==='
    $fw | Out-String | Write-Output
}
catch { Write-Output "ERROR: $($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }

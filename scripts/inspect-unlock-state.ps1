# READ-ONLY inspection of the unlock deployment. Writes nothing to any ESP or BCD.
# ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI.
$ErrorActionPreference = 'Continue'
$log = 'E:\AI\gpu-unlock-win\logs\inspect-unlock.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null

$expectedSha = '403D78938AD859A1A90E0E9222380C60F71EAE2EC1CBF432DEED7641A94EC617'
$entryId     = '{b05c3bb8-d07b-11f1-b16c-30894a35f1b9}'

function Ids([string]$Text) {
    $out = @()
    foreach ($block in ($Text -split "(?m)^-{5,}\s*$")) {
        foreach ($line in ($block -split "`r?`n")) {
            if ($line -match '^\s*displayorder\b') { continue }
            $m = [regex]::Match($line, '^\s*\S+\s+(\{[0-9a-fA-F-]{36}\})\s*$')
            if ($m.Success) { $out += $m.Groups[1].Value; break }
        }
    }
    return $out
}

try {
    Write-Output '=== S: volume ==='
    $p = Get-Partition -DriveLetter S -ErrorAction SilentlyContinue
    if ($p) {
        $v = $p | Get-Volume
        Write-Output ("S: disk={0} part={1} guid={2} size={3} fs={4} free={5} sys={6}" -f $p.DiskNumber,$p.PartitionNumber,$p.Guid,$p.Size,$v.FileSystem,$v.SizeRemaining,$p.IsSystem)
    } else { Write-Output 'S: not present' }

    Write-Output ''
    Write-Output '=== S:\EFI\WindowsGPUUnlock ==='
    Get-ChildItem -LiteralPath 'S:\EFI\WindowsGPUUnlock' -Force -ErrorAction SilentlyContinue |
        Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String | Write-Output

    $staged = 'S:\EFI\WindowsGPUUnlock\UNLOCK-3060-MANUAL.EFI'
    if (Test-Path -LiteralPath $staged) {
        $h = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash
        Write-Output ("staged EFI sha256 = " + $h)
        Write-Output ("matches expected    = " + ($h -eq $expectedSha))
        $bytes = [IO.File]::ReadAllBytes($staged)
        Write-Output ("staged EFI bytes    = " + $bytes.Length)
        Write-Output ("first 2 bytes       = " + ([Text.Encoding]::ASCII.GetString($bytes,0,2)))
        $peOff = [BitConverter]::ToInt32($bytes,0x3c)
        Write-Output ("e_lfanew            = 0x" + $peOff.ToString('x'))
        Write-Output ("PE sig              = " + [Text.Encoding]::ASCII.GetString($bytes,$peOff,4))
    } else { Write-Output 'STAGED EFI MISSING' }

    Write-Output ''
    Write-Output '=== S:\RTX3090-UNLOCK (does RUN00 exist => app got past the media gate) ==='
    Get-ChildItem -LiteralPath 'S:\RTX3090-UNLOCK' -Force -ErrorAction SilentlyContinue |
        Select-Object Name,Length,LastWriteTime,Attributes | Format-Table -AutoSize | Out-String | Write-Output
    $run = Get-ChildItem -LiteralPath 'S:\RTX3090-UNLOCK' -Directory -Force -ErrorAction SilentlyContinue
    if (-not $run) { Write-Output 'no RUN directory: the app never created one' }
    foreach ($d in $run) {
        $rep = Join-Path $d.FullName 'REPORT.TXT'
        Write-Output ("RUN dir: " + $d.Name)
        if (Test-Path -LiteralPath $rep) {
            Write-Output ("  REPORT.TXT bytes = " + (Get-Item -LiteralPath $rep).Length)
            Write-Output '  --- first 40 lines ---'
            Get-Content -LiteralPath $rep -TotalCount 40 | ForEach-Object { '  | ' + $_ }
        } else { Write-Output '  no REPORT.TXT inside' }
    }

    Write-Output ''
    Write-Output '=== BCD: our entry ==='
    & bcdedit /enum $entryId 2>&1 | Out-String | Write-Output
    Write-Output ('enum exit = ' + $LASTEXITCODE)

    Write-Output '=== BCD: observation entry for comparison ==='
    & bcdedit /enum '{b05c3bb6-d07b-11f1-b16c-30894a35f1b9}' 2>&1 | Out-String | Write-Output

    Write-Output '=== firmware order ==='
    & bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String | Write-Output

    Write-Output '=== all firmware entries with their description/path ==='
    $all = & bcdedit /enum all 2>&1 | Out-String
    foreach ($block in ($all -split "(?m)^-{5,}\s*$")) {
        $desc = ([regex]::Match($block,'(?mi)^description\s+(.+?)\s*$')).Groups[1].Value
        $path = ([regex]::Match($block,'(?mi)^path\s+(.+?)\s*$')).Groups[1].Value
        $dev  = ([regex]::Match($block,'(?mi)^device\s+(.+?)\s*$')).Groups[1].Value
        if ($desc -match 'GPU|Unlock|Observe') {
            Write-Output ("desc=[" + $desc + "] device=[" + $dev + "] path=[" + $path + "]")
        }
    }
}
catch { Write-Output ('ERROR: ' + $_.Exception.Message) }
finally { Stop-Transcript | Out-Null }

# READ-ONLY copy of the unlock run reports off the ESP. Writes only under E:\AI\gpu-unlock-win.
# ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI.
$ErrorActionPreference = 'Continue'
$log = 'E:\AI\gpu-unlock-win\logs\collect-reports.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null

$dest = 'E:\AI\gpu-unlock-win\captures\runs'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

try {
    $root = 'S:\RTX3090-UNLOCK'
    $dirs = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue
    foreach ($d in $dirs) {
        if ($d.Name -eq 'ASSETS') { continue }
        $rep = Join-Path $d.FullName 'REPORT.TXT'
        if (-not (Test-Path -LiteralPath $rep)) {
            Write-Output ('no report in ' + $d.Name)
            continue
        }
        $target = Join-Path $dest ($d.Name + '.txt')
        [IO.File]::Copy($rep, $target, $true)
        $h = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        Write-Output ('copied ' + $d.Name + ' -> ' + $target + ' bytes=' + (Get-Item $target).Length)
        Write-Output ('  sha256=' + $h)
    }

    Write-Output ''
    Write-Output '=== staged EFI ==='
    Get-ChildItem -LiteralPath 'S:\EFI\WindowsGPUUnlock' -Force -ErrorAction SilentlyContinue |
        Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String | Write-Output
    $efi = 'S:\EFI\WindowsGPUUnlock\UNLOCK-3060-MANUAL.EFI'
    if (Test-Path -LiteralPath $efi) {
        Write-Output ('staged sha256=' + (Get-FileHash -LiteralPath $efi -Algorithm SHA256).Hash)
        Write-Output ('staged bytes=' + (Get-Item -LiteralPath $efi).Length)
    }
}
catch { Write-Output ('ERROR: ' + $_.Exception.Message) }
finally { Stop-Transcript | Out-Null }

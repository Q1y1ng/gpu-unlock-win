# Elevated helper: create the dedicated 1 GiB EFI System Partition on disk 0.
#
# Design notes (why not diskpart):
#   diskpart /s continues after errors; a failed "create partition efi" would leave
#   volume E: selected and the following "format" would reformat the whole volume.
#   The storage cmdlets below throw immediately, and every destructive step is
#   preceded by an explicit state assertion and followed by a verification.
#
# Scope: disk 0 (CT1000P3SSD8, internal NVMe) only. Shrinks E: by 1 GiB and adds a
#        1 GiB FAT32 partition of type EFI System. Windows system disk is untouched.
# Rollback: Remove-Partition on the new partition, then Resize-Partition E back.

$ErrorActionPreference = 'Stop'
$root = 'E:\AI\gpu-unlock-win'
$log  = Join-Path $root 'logs\create-esp.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null

function Show([string]$t) { Write-Output ''; Write-Output "=== $t ===" }
$EspType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

try {
    Show 'privilege'
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Output "administrator=$admin"
    if (-not $admin) { throw 'Must run elevated' }

    Show 'pre-flight assertions (nothing is changed yet)'
    $disk = Get-Disk -Number 0
    Write-Output ("disk0: {0} {1} bus={2} size={3:N0} GB" -f $disk.Number, $disk.FriendlyName, $disk.BusType, ($disk.Size/1GB))
    if ($disk.FriendlyName -notlike 'CT1000P3SSD8*') { throw "disk 0 is not the expected CT1000P3SSD8: $($disk.FriendlyName)" }
    if ($disk.PartitionStyle -ne 'GPT') { throw 'disk 0 is not GPT' }

    $e = Get-Partition -DriveLetter E
    if ($e.DiskNumber -ne 0) { throw "E: is not on disk 0 (it is on disk $($e.DiskNumber))" }
    $ev = Get-Volume -DriveLetter E
    Write-Output ("E: part={0} fs={1} size={2:N1} GB free={3:N1} GB type={4}" -f $e.PartitionNumber, $ev.FileSystem, ($e.Size/1GB), ($ev.SizeRemaining/1GB), $e.GptType)
    if ($ev.FileSystem -ne 'NTFS') { throw 'E: is not NTFS' }
    if (($ev.SizeRemaining/1GB) -lt 4) { throw 'E: has less than 4 GiB free; refusing to shrink' }
    if (Get-Partition -DriveLetter S -ErrorAction SilentlyContinue) { throw 'S: already in use' }
    if (Get-Partition -DiskNumber 0 | Where-Object { $_.GptType -eq $EspType }) { throw 'disk 0 already has an ESP' }

    Show 'step 1/4 shrink E: by 1 GiB'
    $newSize = $e.Size - 1GB
    Resize-Partition -DriveLetter E -Size $newSize
    $e2 = Get-Partition -DriveLetter E
    $ev2 = Get-Volume -DriveLetter E
    Write-Output ("E: now size={0:N1} GB free={1:N1} GB fs={2}" -f ($e2.Size/1GB), ($ev2.SizeRemaining/1GB), $ev2.FileSystem)
    if ($e2.Size -ne $newSize) { throw 'E: size after shrink does not match the request' }

    Show 'step 2/4 create the ESP-type partition (not formatted yet)'
    $free = (Get-Disk -Number 0).Size - (((Get-Partition -DiskNumber 0 | Measure-Object -Property Size -Sum).Sum))
    Write-Output ("disk0 unallocated: {0:N2} GB" -f ($free/1GB))
    if ($free -lt 1GB) { throw 'not enough unallocated space on disk 0' }
    $part = New-Partition -DiskNumber 0 -Size 1GB -GptType $EspType
    Write-Output ("created partition {0} size={1:N0} MB type={2}" -f $part.PartitionNumber, ($part.Size/1MB), $part.GptType)
    if ($part.GptType -ne $EspType) { throw 'new partition is not of EFI System type' }
    if ($part.Size -lt 1000MB) { throw 'new partition is smaller than expected' }

    Show 'step 3/4 assign letter S:'
    Set-Partition -DiskNumber 0 -PartitionNumber $part.PartitionNumber -NewDriveLetter S
    $s = Get-Partition -DiskNumber 0 -PartitionNumber $part.PartitionNumber
    Write-Output ("S: -> partition {0}, size={1:N0} MB, type={2}" -f $s.PartitionNumber, ($s.Size/1MB), $s.GptType)
    if ($s.DriveLetter -ne 'S') { throw 'drive letter S was not assigned' }
    # Hard stop: format only the partition we just created, addressed by number.
    if ($s.PartitionNumber -eq $e2.PartitionNumber) { throw 'refusing to format: new partition shares the E: partition number' }
    if ($s.Size -gt 1100MB) { throw 'refusing to format: partition larger than expected, not ours' }

    Show 'step 4/4 format S: as FAT32'
    Format-Volume -Partition $s -FileSystem FAT32 -NewFileSystemLabel 'GPUUNLOCK' -Confirm:$false -Force | Out-Null
    $sv = Get-Volume -DriveLetter S
    Write-Output ("S: fs={0} label={1} size={2:N0} MB" -f $sv.FileSystem, $sv.FileSystemLabel, ($sv.Size/1MB))
    if ($sv.FileSystem -ne 'FAT32') { throw 'S: is not FAT32' }

    Show 'final layout'
    Get-Partition -DiskNumber 0 | Select-Object PartitionNumber, DriveLetter, GptType, IsSystem, Size | Format-Table -AutoSize | Out-String | Write-Output
    Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining | Format-Table -AutoSize | Out-String | Write-Output
    Show 'windows ESP (untouched, for Configure.ps1)'
    Get-Partition -DiskNumber 1 -PartitionNumber 1 | Select-Object Guid, IsSystem, Size | Format-List | Out-String | Write-Output
    Write-Output 'RESULT: OK'
}
catch {
    Write-Output "RESULT: FAILED - $($_.Exception.Message)"
}
finally {
    Stop-Transcript | Out-Null
}

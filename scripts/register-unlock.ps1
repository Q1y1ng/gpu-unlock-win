# Stage the manual unlock EFI plus its firmware assets onto the dedicated S: ESP and
# append one manual firmware boot entry. Preserves existing order; no BootNext, no
# reboot, no BIOS change. ASCII-only: Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI.
param(
    [switch]$Register,
    [switch]$Rollback
)
$ErrorActionPreference = 'Stop'

$projectRoot = 'E:\AI\gpu-unlock-win'
$repo        = Join-Path $projectRoot 'Windows-GPU-UNLOCK'
$logDir      = Join-Path $projectRoot 'logs'
$stateFile   = Join-Path $projectRoot 'registration-unlock.local.json'
$drive       = 'S'
$bootPath    = '\EFI\WindowsGPUUnlock\UNLOCK-3060-MANUAL.EFI'
$entryName   = 'GPU Unlock 3060 Laptop - EXPERIMENTAL (press U)'

$efiSource = Join-Path $repo 'internal-boot\unlock\build\experimental\entryLatchedSs1Preserve\RTX3060-LAPTOP-EXPERIMENTAL-entryLatchedSs1Preserve.EFI'
$efiSha    = '403D78938AD859A1A90E0E9222380C60F71EAE2EC1CBF432DEED7641A94EC617'

$assetSource = Join-Path $repo 'assets'
$assets = @(
    @{ Name = 'booter_load_ga102.bin';      Bytes = 61256;     Sha = '056cbc064a888f80717726c54d7f64fcd68044d123870c95a74f37f4975dcaa4' },
    @{ Name = 'v67-ga102-610.43.03.bin';    Bytes = 64000;     Sha = '2a0aa1f86d0b6afff5214d641d87d46dc98ef06ed908ff05d0ddbad5ffb7e197' },
    @{ Name = 'gsp_ga10x.bin';              Bytes = 84277400;  Sha = '572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a' },
    @{ Name = 'gsp_boot_ga102.bin';         Bytes = 24576;     Sha = '3df651acb174fd5f5561a1996965b192f50c5d763168446ed0d4ead19d895768' },
    @{ Name = 'gsp_boot_desc_ga102.bin';    Bytes = 84;        Sha = 'cc5a3fc1f4c47f2fe107b1b68f0176d8a448e6dec84b575e5560ccef5262bf15' }
)

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Start-Transcript -Path (Join-Path $logDir 'register-unlock.log') -Force | Out-Null

function Bcd([string[]]$Arguments) {
    $lines = @(& bcdedit @Arguments)
    if ($LASTEXITCODE -ne 0) { throw ('bcdedit failed: ' + ($Arguments -join ' ')) }
    return ($lines -join "`r`n")
}

# Locale-independent identifier extraction: Chinese bcdedit prints the label instead
# of the English word "identifier", so match "<label> {guid}" and skip displayorder.
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

function Order([string]$Text) {
    $m = [regex]::Match($Text, '(?ms)^displayorder\s+(.*?)(?=\r?\n\S|\z)')
    if (!$m.Success) { throw 'No firmware displayorder' }
    return @([regex]::Matches($m.Groups[1].Value, '\{(?:bootmgr|[0-9a-f-]{36})\}') | ForEach-Object { $_.Value })
}

function AssertTarget {
    $partition = Get-Partition -DriveLetter $drive
    $disk      = Get-Disk -Number $partition.DiskNumber
    $volume    = $partition | Get-Volume
    $config    = Get-Content -LiteralPath (Join-Path $repo 'internal-boot\local-config.json') -Raw | ConvertFrom-Json
    if ($partition.Guid -ne $config.UnlockPartitionGuid) { throw ('Unexpected partition GUID on ' + $drive + ':') }
    if ($partition.IsSystem) { throw 'Refusing: S: is the Windows system partition' }
    if ($volume.FileSystem -ne 'FAT32') { throw ('Refusing: ' + $drive + ': is not FAT32') }
    if ($disk.Model -notmatch 'CT1000P3SSD8') { throw ('Refusing: unexpected disk model ' + $disk.Model) }
    Write-Output ('target confirmed: ' + $drive + ': guid=' + $partition.Guid + ' size=' + $partition.Size + ' fs=' + $volume.FileSystem)
}

function StageFile([string]$Source, [string]$Dest, [string]$Sha, [long]$Bytes) {
    if (Test-Path -LiteralPath $Dest) {
        $existing = (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash
        if ($existing -ne $Sha) { throw ('Refusing to overwrite a different file: ' + $Dest) }
        Write-Output ('already staged: ' + $Dest)
        return
    }
    [IO.File]::Copy($Source, $Dest, $false)
    $info = Get-Item -LiteralPath $Dest
    if ($info.Length -ne $Bytes) { throw ('Size mismatch after copy: ' + $Dest) }
    $actual = (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash
    if ($actual -ne $Sha) { throw ('Hash mismatch after copy: ' + $Dest) }
    Write-Output ('staged: ' + $Dest + ' ' + $info.Length + ' bytes')
}

try {
    AssertTarget

    Write-Output '=== stage files ==='
    $efiTarget = Join-Path ($drive + ':\') ($bootPath.TrimStart('\'))
    $efiDir = Split-Path -Parent $efiTarget
    if (!(Test-Path -LiteralPath $efiDir)) { [void][IO.Directory]::CreateDirectory($efiDir) }
    if ((Get-FileHash -LiteralPath $efiSource -Algorithm SHA256).Hash -ne $efiSha) { throw 'Local unlock EFI does not match the reviewed hash' }
    StageFile $efiSource $efiTarget $efiSha 65536

    $assetDir = Join-Path ($drive + ':\') 'RTX3090-UNLOCK\ASSETS'
    if (!(Test-Path -LiteralPath $assetDir)) { [void][IO.Directory]::CreateDirectory($assetDir) }
    foreach ($asset in $assets) {
        StageFile (Join-Path $assetSource $asset.Name) (Join-Path $assetDir $asset.Name) $asset.Sha $asset.Bytes
    }
    $runDir = Join-Path ($drive + ':\') 'RTX3090-UNLOCK'
    Write-Output ('asset root: ' + $assetDir)

    if (!$Register) { Write-Output 'Staging only; no boot entry changes.'; return }

    Write-Output '=== register ==='
    if (Test-Path -LiteralPath $stateFile) { throw ('Registration state already exists: ' + $stateFile) }
    $fwBefore   = Bcd @('/enum', '{fwbootmgr}')
    if ($fwBefore -match '(?mi)^bootsequence\s+') { throw 'Pending BootNext present; refusing to register' }
    $orderBefore = Order $fwBefore
    $allBefore   = Ids (Bcd @('/enum', 'all'))

    $backup = Join-Path $env:ProgramData ('WindowsGPUUnlock\UnlockBackups\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
    [void][IO.Directory]::CreateDirectory($backup)
    [void](Bcd @('/export', (Join-Path $backup 'BCD-export')))
    [IO.File]::WriteAllText((Join-Path $backup 'firmware-before.txt'), $fwBefore)

    $state = [ordered]@{
        EntryId = $null; Name = $entryName; Path = $bootPath; Drive = $drive
        EfiSha256 = $efiSha; BackupRoot = $backup; OrderBefore = $orderBefore
        RegisteredUtc = $null; HardwareTested = $false
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding utf8

    $entryId = $null
    try {
        # bcdedit /copy prints the new identifier, but the wording is localised; resolve
        # it by diffing identifiers before and after instead of parsing the output.
        [void](Bcd @('/copy', '{bootmgr}', '/d', $entryName))
        $created = @(Ids (Bcd @('/enum', 'all')) | Where-Object { $allBefore -notcontains $_ })
        if ($created.Count -ne 1) { throw ('Expected exactly one new entry, saw ' + $created.Count) }
        $entryId = $created[0]
        $state.EntryId = $entryId
        $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding utf8
        Write-Output ('created entry ' + $entryId)

        [void](Bcd @('/set', $entryId, 'device', ('partition=' + $drive + ':')))
        [void](Bcd @('/set', $entryId, 'path', $bootPath))
        [void](Bcd @('/set', '{fwbootmgr}', 'displayorder', $entryId, '/addlast'))
        Write-Output 'entry configured and appended to the firmware order'
    }
    catch {
        Write-Output ('ERROR during registration: ' + $_.Exception.Message)
        if ($entryId -and (@(Ids (Bcd @('/enum', 'all'))) -contains $entryId)) {
            Write-Output ('rollback: deleting ' + $entryId)
            & bcdedit /delete $entryId /f | Out-Null
        }
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
        throw
    }

    Write-Output '=== verify ==='
    $fwAfter    = Bcd @('/enum', '{fwbootmgr}')
    $orderAfter = Order $fwAfter
    $expected   = @($orderBefore) + @($entryId)
    if (($orderAfter -join ',') -ne ($expected -join ',')) { throw 'Firmware order is not the original order plus the new entry' }
    if ($fwAfter -match '(?mi)^bootsequence\s+') { throw 'A BootNext appeared during registration' }
    $entry = Bcd @('/enum', $entryId)
    if ($entry -notmatch ('(?mi)^path\s+' + [regex]::Escape($bootPath) + '\s*$')) { throw 'Entry path mismatch' }
    if ($entry -notmatch ('(?m)^description\s+' + [regex]::Escape($entryName) + '\s*$')) { throw 'Entry description mismatch' }
    if ($entry -notmatch ('(?mi)^device\s+partition=' + [regex]::Escape($drive) + ':\s*$')) { throw 'Entry device mismatch' }
    foreach ($old in $orderBefore) {
        if ($old -eq '{bootmgr}') { continue }
        if ((Bcd @('/enum', $old)) -notmatch '\S') { throw ('Existing entry missing: ' + $old) }
    }
    if ((Get-FileHash -LiteralPath $efiTarget -Algorithm SHA256).Hash -ne $efiSha) { throw 'Staged EFI changed after registration' }

    $state.RegisteredUtc = [DateTime]::UtcNow.ToString('o')
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding utf8
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'registration.json') -Encoding utf8
    [IO.File]::WriteAllText((Join-Path $backup 'firmware-after.txt'), (Bcd @('/enum', 'firmware')))
    Write-Output ('registered ' + $entryName + ' -> ' + $entryId + ' at the end of the firmware order')
    Write-Output ('backup: ' + $backup)
}
catch {
    Write-Output ('ERROR: ' + $_.Exception.Message)
}
finally {
    Stop-Transcript | Out-Null
}

if ($Rollback) {
    if (!(Test-Path -LiteralPath $stateFile)) { Write-Output 'no registration state to roll back'; return }
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    Write-Output ('rolling back entry ' + $state.EntryId)
    $order = Order (Bcd @('/enum', '{fwbootmgr}'))
    $kept = @($order | Where-Object { $_ -ne $state.EntryId })
    [void](Bcd (@('/set', '{fwbootmgr}', 'displayorder') + $kept))
    [void](Bcd @('/delete', $state.EntryId, '/f'))
    Remove-Item -LiteralPath $stateFile -Force
    Write-Output 'rollback complete'
}

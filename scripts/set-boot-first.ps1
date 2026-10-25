# Move the unlock firmware entry to the FRONT of the firmware boot order (or restore
# it to the end). Never sets BootNext; never deletes any entry. ASCII-only on purpose.
param(
    [switch]$First,
    [switch]$Restore
)
$ErrorActionPreference = 'Stop'
$log = 'E:\AI\gpu-unlock-win\logs\boot-order.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null

$entryName = 'GPU Unlock 3060 Laptop - EXPERIMENTAL (press U)'
$stateFile = 'E:\AI\gpu-unlock-win\boot-order.local.json'

function Bcd([string[]]$Arguments) {
    $lines = @(& bcdedit @Arguments)
    if ($LASTEXITCODE -ne 0) { throw ('bcdedit failed: ' + ($Arguments -join ' ')) }
    return ($lines -join "`r`n")
}

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

try {
    $all = Bcd @('/enum', 'all')
    $ids = Ids $all
    $matches = @()
    foreach ($block in ($all -split "(?m)^-{5,}\s*$")) {
        $desc = ([regex]::Match($block, '(?mi)^description\s+(.+?)\s*$')).Groups[1].Value
        if ($desc -cne $entryName) { continue }
        foreach ($line in ($block -split "`r?`n")) {
            if ($line -match '^\s*displayorder\b') { continue }
            $m = [regex]::Match($line, '^\s*\S+\s+(\{[0-9a-fA-F-]{36}\})\s*$')
            if ($m.Success) { $matches += $m.Groups[1].Value; break }
        }
    }
    Write-Output ('unlock entries found: ' + $matches.Count + ' -> ' + ($matches -join ','))
    if ($matches.Count -ne 1) { throw 'Expected exactly one unlock entry; refusing to change order' }
    $id = $matches[0]

    $fw = Bcd @('/enum', '{fwbootmgr}')
    if ($fw -match '(?mi)^bootsequence\s+') { throw 'Pending BootNext present; refusing' }
    $order = Order $fw
    Write-Output ('order before: ' + ($order -join ','))

    if ($Restore) {
        if (!(Test-Path -LiteralPath $stateFile)) { throw 'No saved order to restore' }
        $saved = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).OrderBefore
        Write-Output ('restoring: ' + ($saved -join ','))
        [void](Bcd (@('/set', '{fwbootmgr}', 'displayorder') + @($saved)))
    }
    elseif ($First) {
        if (Test-Path -LiteralPath $stateFile) { Write-Output 'state file already exists; keeping the original' }
        else {
            [ordered]@{ EntryId = $id; OrderBefore = $order; SavedUtc = [DateTime]::UtcNow.ToString('o') } |
                ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stateFile -Encoding utf8
        }
        $new = @($id) + @($order | Where-Object { $_ -ne $id })
        Write-Output ('setting: ' + ($new -join ','))
        [void](Bcd (@('/set', '{fwbootmgr}', 'displayorder') + $new))
    }
    else { throw 'Pass -First or -Restore' }

    $after = Order (Bcd @('/enum', '{fwbootmgr}'))
    Write-Output ('order after:  ' + ($after -join ','))
    $fw2 = Bcd @('/enum', '{fwbootmgr}')
    if ($fw2 -match '(?mi)^bootsequence\s+') { throw 'A BootNext appeared' }
    if ($First -and $after[0] -ne $id) { throw 'Unlock entry is not first' }
    if (@($after | Select-Object -Unique).Count -ne $after.Count) { throw 'Duplicate identifiers in order' }
    Write-Output 'boot order verified; no BootNext set; every entry preserved'
}
catch { Write-Output ('ERROR: ' + $_.Exception.Message) }
finally { Stop-Transcript | Out-Null }

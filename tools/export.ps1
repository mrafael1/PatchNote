# Windows export check (M7 gate): export the release build, boot the exported game
# headless, and require the game banner, the full mutation list (big patches marked)
# and a clean log.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\export.ps1
# Output: builds\windows\PatchNotes.exe (+ PatchNotes.console.exe)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root '.check'
$outDir = Join-Path $root 'builds\windows'
New-Item -ItemType Directory -Force $logDir, $outDir | Out-Null
$errorPattern = 'SCRIPT ERROR|Parse Error|^\s*ERROR:|Could not find type|Failed to load script'
$failures = @()

Write-Host '[1/2] export'
$exportLog = Join-Path $logDir 'export.log'
cmd /c "godot --headless --path `"$root`" --export-release `"Windows Desktop`" `"$outDir\PatchNotes.exe`" > `"$exportLog`" 2>&1"
if ($LASTEXITCODE -ne 0) { $failures += "export: exit code $LASTEXITCODE" }
if (Select-String -Path $exportLog -Pattern $errorPattern) { $failures += 'export: error lines in log' }
$exe = Join-Path $outDir 'PatchNotes.console.exe'
if (-not (Test-Path $exe)) { $failures += 'export: console executable missing' }

if ($failures.Count -eq 0) {
    Write-Host '[2/2] boot exported game'
    $bootLog = Join-Path $logDir 'export_boot.log'
    # --autostart goes straight from the start screen into a run.
    cmd /c "`"$exe`" --headless --quit-after 180 -- --autostart > `"$bootLog`" 2>&1"
    $text = Get-Content $bootLog -Raw
    if ($LASTEXITCODE -ne 0) { $failures += "boot: exit code $LASTEXITCODE" }
    if (Select-String -Path $bootLog -Pattern $errorPattern) { $failures += 'boot: error lines in log' }
    if ($text -notmatch '\[boot\] Patch Notes .*start screen') { $failures += 'boot: start screen banner missing' }
    if ($text -notmatch '\[boot\] Patch Notes .*Godot') { $failures += 'boot: game banner missing' }
    $expected = (Get-ChildItem (Join-Path $root 'mutations') -Directory).Count
    if ($text -match '\[mutations\] (\d+): (.*)') {
        Write-Host "    mutations: $($Matches[1]) ($($Matches[2].Trim()))"
        if ([int]$Matches[1] -ne $expected) { $failures += "boot: $($Matches[1]) mutations listed, $expected folders" }
        # Big patches (PLAN v3 M12) are marked "(BIG)"; every resource with is_big = true must be.
        $listed = ([regex]::Matches($Matches[2], '\(BIG\)')).Count
        $bigs = @(Get-ChildItem (Join-Path $root 'mutations') -Recurse -Filter '*.tres' |
            Where-Object { Select-String -Path $_.FullName -Pattern '^is_big = true' -Quiet }).Count
        Write-Host "    big patches marked: $listed of $bigs"
        if ($bigs -eq 0 -or $listed -ne $bigs) { $failures += "boot: $listed big patches marked, $bigs resources with is_big" }
        # Mediums are marked "(MED)" and boss-only patches "(BOSS)" (PLAN v4 1.1), counted the same way.
        foreach ($tier in @(@('MED', 'is_medium'), @('BOSS', 'boss_only'))) {
            $marked = ([regex]::Matches($Matches[2], "\($($tier[0])\)")).Count
            $flagged = @(Get-ChildItem (Join-Path $root 'mutations') -Recurse -Filter '*.tres' |
                Where-Object { Select-String -Path $_.FullName -Pattern "^$($tier[1]) = true" -Quiet }).Count
            Write-Host "    $($tier[0]) patches marked: $marked of $flagged"
            if ($marked -ne $flagged) { $failures += "boot: $marked $($tier[0]) patches marked, $flagged resources with $($tier[1])" }
        }
    } else { $failures += 'boot: mutation list missing' }
    $size = (Get-Item (Join-Path $outDir 'PatchNotes.exe')).Length / 1MB
    Write-Host ("    PatchNotes.exe {0:N1} MB" -f $size)
}

if ($failures.Count -gt 0) {
    Write-Host 'EXPORT FAILED' -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host 'EXPORT PASSED' -ForegroundColor Green
exit 0

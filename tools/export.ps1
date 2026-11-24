# Windows export check (playtest builds; G13): export the release build, boot the
# exported game headless, and require the game banner, the campaign data (its session
# and reaction counts and last session read from the data, PLAN v9 4), the full
# mutation list (big patches marked) and a clean log; then boot S5, S4 (teleport), S7 and
# S8 on each path (M47) too.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\export.ps1
# Output: builds\windows\PatchNotes.exe (+ PatchNotes.console.exe, PLAYTEST.md: the G13.1 sheet)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root '.check'
$outDir = Join-Path $root 'builds\windows'
New-Item -ItemType Directory -Force $logDir, $outDir | Out-Null
$errorPattern = 'SCRIPT ERROR|Parse Error|^\s*ERROR:|Could not find type|Failed to load script'
$failures = @()

# PLAN v9 4 (M43): the campaign's size and last session, read as check.ps1 reads them.
$campaignText = Get-Content (Join-Path $root 'campaign\campaign.tres') -Raw
$sessionRids = @{}
foreach ($m in [regex]::Matches($campaignText, '\[ext_resource type="Resource" path="res://campaign/sessions/(\w+)\.tres" id="([^"]+)"\]')) {
    $sessionRids[$m.Groups[2].Value] = $m.Groups[1].Value
}
$sessionsList = [regex]::Match($campaignText, '(?m)^sessions = Array\[ExtResource\("[^"]+"\)\]\(\[(.*)\]\)').Groups[1].Value
$sessionIds = @([regex]::Matches($sessionsList, 'ExtResource\("([^"]+)"\)') | ForEach-Object { $sessionRids[$_.Groups[1].Value] } | Where-Object { $_ })
$sessionCount = $sessionIds.Count
$lastSession = if ($sessionCount -gt 0) { $sessionIds[-1] } else { '' }
$reactionCount = @(Get-ChildItem (Join-Path $root 'campaign\reactions') -Filter '*.tres').Count

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
    # The boot lines name the save's version and the run's genre (PLAN v5 M30); the smoke
    # boot never touches the real save.
    if ($text -notmatch '\[boot\] Patch Notes .*start screen, game v\d+\.\d+\.\d+, inert save') { $failures += 'boot: start screen line without version, or the real save' }
    # In the campaign the game line names the session between the genre and the playable list.
    if ($text -match '\[boot\] Patch Notes .*, game (v\d+\.\d+\.\d+), genre (\w+)(?:, session (\w+))? \(playable: ([^)]*)\)') {
        Write-Host "    boot: game $($Matches[1]), genre $($Matches[2]), session $($Matches[3]), playable: $($Matches[4])"
    } else { $failures += 'boot: game line without version and genres' }
    # PLAN v8 M42: --autostart starts a new campaign at S0, with Stage 1's data loaded.
    if ($text -notmatch ', session s1_00_nothing \(playable') { $failures += 'boot: the export did not start the campaign at S0' }
    # M42: Godot 4.7's text-to-binary resource conversion empties every PackedStringArray
    # (lines, cues, intros) in the export; project.godot keeps text resources as text.
    # A regression shows here as "reaction <id>: no lines" errors.
    if ($text -match '\[campaign\] (\d+ sessions: .*)') { Write-Host "    campaign: $($Matches[1].Trim()) (data: $sessionCount sessions, last $lastSession, $reactionCount reactions)" }
    if ($sessionCount -eq 0 -or $text -notmatch "\[campaign\] $sessionCount sessions: .*$lastSession; $reactionCount reactions") { $failures += 'boot: the campaign data did not load' }
    # Both lines end with the save's fork answers (PLAN v6 M36); the inert smoke boot has none.
    if (([regex]::Matches($text, '\[boot\] Patch Notes .*, answers -')).Count -lt 2) { $failures += 'boot: lines without the save''s answers' }
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
    # A second boot straight into S5 (a load check: the rule book's edits and the event
    # without source; 300 frames never reach the 40 s event).
    $bootLog5 = Join-Path $logDir 'export_boot_s5.log'
    cmd /c "`"$exe`" --headless --quit-after 300 -- --autostart --session=s1_05_wrong > `"$bootLog5`" 2>&1"
    $text5 = Get-Content $bootLog5 -Raw
    if ($LASTEXITCODE -ne 0) { $failures += "boot S5: exit code $LASTEXITCODE" }
    if (Select-String -Path $bootLog5 -Pattern $errorPattern) { $failures += 'boot S5: error lines in log' }
    if ($text5 -notmatch ', session s1_05_wrong ') { $failures += 'boot S5: the export did not jump to S5' }
    else { Write-Host '    boot S5: session s1_05_wrong, clean log' }
    # M42.1: a third boot into S4 with a non-classic dash (--dash= answers fork_dash in the
    # boot's own save; --autostart keeps it off the real save). M42.2: --dash-aim= too.
    $bootLog4 = Join-Path $logDir 'export_boot_s4.log'
    cmd /c "`"$exe`" --headless --quit-after 300 -- --autostart --session=s1_04_level --dash=teleport --dash-aim=aim > `"$bootLog4`" 2>&1"
    $text4 = Get-Content $bootLog4 -Raw
    if ($LASTEXITCODE -ne 0) { $failures += "boot S4: exit code $LASTEXITCODE" }
    if (Select-String -Path $bootLog4 -Pattern $errorPattern) { $failures += 'boot S4: error lines in log' }
    if ($text4 -notmatch ', session s1_04_level ') { $failures += 'boot S4: the export did not jump to S4' }
    elseif ($text4 -notmatch 'answers .*fork_dash=dash_teleport.* fork_dash_aim=dashdir_aim') { $failures += 'boot S4: --dash=teleport --dash-aim=aim did not answer both forks' }
    else { Write-Host '    boot S4: session s1_04_level, dash teleport + aim, clean log' }
    # M47 (G14a): S7 (the three tastes) and S8 on each path (--answer= answers fork_path in
    # the boot's own save; --autostart keeps it off the real save).
    $bootLog7 = Join-Path $logDir 'export_boot_s7.log'
    cmd /c "`"$exe`" --headless --quit-after 300 -- --autostart --session=s2_01_tryout > `"$bootLog7`" 2>&1"
    $text7 = Get-Content $bootLog7 -Raw
    if ($LASTEXITCODE -ne 0) { $failures += "boot S7: exit code $LASTEXITCODE" }
    if (Select-String -Path $bootLog7 -Pattern $errorPattern) { $failures += 'boot S7: error lines in log' }
    if ($text7 -notmatch ', session s2_01_tryout ') { $failures += 'boot S7: the export did not jump to S7' }
    else { Write-Host '    boot S7: session s2_01_tryout, clean log' }
    foreach ($p in @('arsenal', 'auto', 'survival')) {
        $bootLog8 = Join-Path $logDir "export_boot_s8_$p.log"
        cmd /c "`"$exe`" --headless --quit-after 300 -- --autostart --session=s2_02_day_one --answer=fork_path=path_$p > `"$bootLog8`" 2>&1"
        $text8 = Get-Content $bootLog8 -Raw
        if ($LASTEXITCODE -ne 0) { $failures += "boot S8 ${p}: exit code $LASTEXITCODE" }
        if (Select-String -Path $bootLog8 -Pattern $errorPattern) { $failures += "boot S8 ${p}: error lines in log" }
        if ($text8 -notmatch ', session s2_02_day_one ') { $failures += "boot S8 ${p}: the export did not jump to S8" }
        elseif ($text8 -notmatch "answers .*fork_path=path_$p") { $failures += "boot S8 ${p}: --answer did not answer fork_path" }
        else { Write-Host "    boot S8: session s2_02_day_one, path $p, clean log" }
    }
    Copy-Item (Join-Path $root 'PLAYTEST.md') $outDir -Force
    # M47 (0.4): the Stage 2 lines file goes next to the sheet (the owner edits tone there).
    Copy-Item (Join-Path $root 'campaign\lines_stage2.md') $outDir -Force
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

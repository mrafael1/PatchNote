# Project check: import, boot the game headless, run the GUT tests, scan the logs.
# Passes only if exit codes are 0 AND the expected banner/summary lines are present
# AND no error lines appear. Headless Godot can exit 0 on a broken script, so the
# log scan is the real gate.
#
# Usage (from anywhere):  powershell -ExecutionPolicy Bypass -File tools\check.ps1 [-BotRuns]
# -BotRuns adds the M6 gate: five full-length seeded bot runs (about two minutes), plus
# one run of the parked turn-based genre through the big-slot seam (PLAN v5 M25), plus
# four runs chained through a scratch save (PLAN v5 M27, M29).
# Every step must leave the real save folder exactly as it was (PLAN v5 1.5, 6).

param([switch]$BotRuns)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root '.check'
New-Item -ItemType Directory -Force $logDir | Out-Null

$errorPattern = 'SCRIPT ERROR|Parse Error|^\s*ERROR:|Could not find type|Failed to load script'
$failures = @()

# The real save (SaveGame.DEFAULT_PATH) lives here. Nothing the check runs may create,
# change or remove a file in it: tests, boots and bots are inert or use scratch paths.
$saveDir = Join-Path $env:APPDATA 'Godot\app_userdata\Patch Notes\save'
function Get-SaveSnapshot {
    if (-not (Test-Path $saveDir)) { return '(no save folder)' }
    $files = Get-ChildItem -Path $saveDir -File | Sort-Object Name |
        ForEach-Object { '{0}|{1}|{2}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc.Ticks }
    if (-not $files) { return '(empty save folder)' }
    return ($files -join "`n")
}
$saveBefore = Get-SaveSnapshot

function Invoke-Godot([string]$name, [string]$godotArgs) {
    $log = Join-Path $logDir "$name.log"
    # cmd handles the redirection so stderr is captured as plain text.
    cmd /c "godot --headless --path `"$root`" $godotArgs > `"$log`" 2>&1"
    return @{ Code = $LASTEXITCODE; Log = $log; Text = (Get-Content $log -Raw) }
}

function Test-Errors([string]$name, $run) {
    $hits = Select-String -Path $run.Log -Pattern $errorPattern
    if ($hits) {
        $script:failures += "${name}: error lines in log"
        $hits | Select-Object -First 15 | ForEach-Object { Write-Host "    $($_.Line)" }
    }
    if ($run.Code -ne 0) { $script:failures += "${name}: exit code $($run.Code)" }
}

$version = (cmd /c "godot --version 2>&1" | Select-Object -Last 1)
Write-Host "Godot $version"
if ($version -notmatch '^4\.7') { $failures += "Godot 4.7.x required, found $version" }

Write-Host '[1/4] import'
$import = Invoke-Godot 'import' '--import'
if ($import.Code -ne 0) { $failures += "import: exit code $($import.Code)" }

Write-Host '[2/4] boot (start screen)'
$boot = Invoke-Godot 'boot' '--quit-after 120 -- --inert-save'
Test-Errors 'boot' $boot
if ($boot.Text -notmatch '\[boot\] Patch Notes .*start screen') { $failures += 'boot: start screen banner missing' }

Write-Host '[3/4] boot (game scene)'
$game = Invoke-Godot 'boot_game' 'res://main.tscn --quit-after 120'
Test-Errors 'boot_game' $game
if ($game.Text -notmatch '\[boot\] Patch Notes .*Godot') { $failures += 'boot_game: game banner missing' }
# PLAN v8: the game scene straight into a campaign session (inert save, nothing written).
$session = Invoke-Godot 'boot_session' 'res://main.tscn --quit-after 120 -- --session=s1_03_enemies'
Test-Errors 'boot_session' $session
if ($session.Text -notmatch '\[boot\] Patch Notes .*session s1_03_enemies') { $failures += 'boot_session: no campaign session banner' }
if ($session.Text -notmatch '\[campaign\] \d+ sessions') { $failures += 'boot_session: the campaign did not load' }

Write-Host '[4/4] tests'
$testWatch = [System.Diagnostics.Stopwatch]::StartNew()
$tests = Invoke-Godot 'tests' '--fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -ginclude_subdirs -gexit'
$testWatch.Stop()
# PLAN v4 11: the suite's budget is 8 min; over it is a known issue.
Write-Host ("    suite duration: {0:N1} s wall" -f $testWatch.Elapsed.TotalSeconds)
Test-Errors 'tests' $tests
if ($tests.Text -notmatch 'All tests passed') { $failures += 'tests: "All tests passed" summary missing' }
$summary = Select-String -Path $tests.Log -Pattern '^\s*(Scripts|Tests|Passing|Failing|Asserts)\s' | ForEach-Object { $_.Line.Trim() }
if ($summary) { Write-Host ("    " + ($summary -join ' | ')) }

if ($BotRuns) {
    Write-Host '[+] bot runs'
    $bots = Invoke-Godot 'bot_runs' '--fixed-fps 60 -s tools/bot_runs.gd -- 1 2 3 4i 5i'
    Test-Errors 'bot_runs' $bots
    Select-String -Path $bots.Log -Pattern '^\[botrun\]' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($bots.Text -notmatch '\[botrun\] summary: \d+ runs, 0 failures') { $failures += 'bot_runs: summary missing or failures' }
    # The parked turn-based genre still plays a full run through the big-slot seam
    # (PLAN v5 1.3, M25 gate), until Phase 5 ports it into the genre interface.
    $parked = Invoke-Godot 'bot_runs_parked' '--fixed-fps 60 -s tools/bot_runs.gd -- --big=turn_mode 9i'
    Test-Errors 'bot_runs_parked' $parked
    Select-String -Path $parked.Log -Pattern '^\[botrun\]' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($parked.Text -notmatch '\[botrun\] summary: 1 runs, 0 failures') { $failures += 'bot_runs_parked: summary missing or failures' }
    # Four mortal runs chained through a fresh scratch save (PLAN v5 M27): the file counts them.
    $chain = Invoke-Godot 'bot_runs_save' '--fixed-fps 60 -s tools/bot_runs.gd -- --save=user://save_check/save.json --keep-save --fresh 1 2 3 4'
    Test-Errors 'bot_runs_save' $chain
    Select-String -Path $chain.Log -Pattern '^\[botrun\] (save|session|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($chain.Text -notmatch '\[botrun\] summary: 4 runs, 0 failures') { $failures += 'bot_runs_save: summary missing or failures' }
    if ($chain.Text -notmatch '\[botrun\] save: user://save_check/save.json runs=4 ') { $failures += 'bot_runs_save: the save does not count 4 runs' }
    # Between runs the report opens the dev session (PLAN v5 M29, 4.8): the first two
    # ship the basics after two smoke tests, the third is the look mockup (v0.1.0).
    if ($chain.Text -notmatch '\[botrun\] session=1 after_run=1 kind=basic .*ai_ship=basic_movement .*version=v0\.0\.0->v0\.0\.1') { $failures += 'bot_runs_save: session 1 did not ship movement' }
    if ($chain.Text -notmatch '\[botrun\] session=2 after_run=2 kind=basic .*ai_ship=basic_world .*version=v0\.0\.1->v0\.0\.2') { $failures += 'bot_runs_save: session 2 did not ship enemies and the level' }
    if ($chain.Text -notmatch '\[botrun\] session=3 after_run=3 kind=fork fork=look_1 .*shelved=\["look_1_\w+", "look_1_\w+"\] .*version=v0\.0\.2->v0\.1\.0') { $failures += 'bot_runs_save: no look mockup session shipping v0.1.0' }
    if ($chain.Text -notmatch '\[botrun\] save: user://save_check/save.json runs=4 wins=\d+ version=v0\.1\.0 ') { $failures += 'bot_runs_save: the save is not at v0.1.0' }
    # PLAN v8 4: the campaign so far, invincible on a fresh scratch save, then mortal in memory.
    $camp = Invoke-Godot 'bot_campaign' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --save=user://save_check_campaign/save.json --keep-save --fresh 1i'
    Test-Errors 'bot_campaign' $camp
    Select-String -Path $camp.Log -Pattern '^\[botrun\] (session|save|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($camp.Text -notmatch '\[botrun\] summary: campaign, 0 failures') { $failures += 'bot_campaign: summary missing or failures' }
    if ($camp.Text -notmatch '\[botrun\] session=s1_01_nothing attempt=1 \(invincible\) outcome=stopped .*version=v0\.0\.0->v0\.1\.0') { $failures += 'bot_campaign: S1 did not stop and ship v0.1.0' }
    if ($camp.Text -notmatch '"index":3') { $failures += 'bot_campaign: the save did not reach the end of the campaign' }
    $campMortal = Invoke-Godot 'bot_campaign_mortal' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign 2'
    Test-Errors 'bot_campaign_mortal' $campMortal
    Select-String -Path $campMortal.Log -Pattern '^\[botrun\] (session|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($campMortal.Text -notmatch '\[botrun\] summary: campaign, 0 failures') { $failures += 'bot_campaign_mortal: summary missing or failures' }
}

if ((Get-SaveSnapshot) -ne $saveBefore) { $failures += 'the real save folder changed during the check (is the game running? a playtest writes it too)' }

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'CHECK FAILED' -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" }
    Write-Host "Logs: $logDir"
    exit 1
}
Write-Host 'CHECK PASSED' -ForegroundColor Green
exit 0

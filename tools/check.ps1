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

# PLAN v9 4 (M43): the campaign's end is read from data, by id: the session order from
# campaign.tres (the ExtResource ids after the `](` of its sessions line, kept only when
# they name a campaign/sessions/<id>.tres), and the reaction count from its folder.
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
Write-Host "campaign: $sessionCount sessions, last $lastSession; $reactionCount reactions"
# M43.2: a session with a `cooking` list is not played by the flow (the cooking screen
# shows it); the chain plays the sessions before the first one.
$cookingIds = @($sessionIds | Where-Object { (Get-Content (Join-Path $root "campaign\sessions\$($_).tres") -Raw) -match '(?m)^cooking = PackedStringArray\(' })
$firstCooking = if ($cookingIds.Count -gt 0) { $cookingIds[0] } else { '' }
$playable = @(if ($firstCooking -ne '') { $sessionIds[0..([array]::IndexOf($sessionIds, $firstCooking) - 1)] } else { $sessionIds })
$playableCount = $playable.Count
$lastPlayable = if ($playableCount -gt 0) { $playable[-1] } else { '' }
Write-Host "campaign: $playableCount playable, cooking: $($cookingIds -join ', ')"
if ($sessionCount -eq 0) { $failures += 'campaign.tres: no sessions read' }

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
$session = Invoke-Godot 'boot_session' 'res://main.tscn --quit-after 120 -- --session=s1_03_shooting'
Test-Errors 'boot_session' $session
if ($session.Text -notmatch '\[boot\] Patch Notes .*session s1_03_shooting') { $failures += 'boot_session: no campaign session banner' }
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
    # PLAN v8 4: the campaign (S0 to the last session), invincible on a fresh scratch save,
    # then mortal in memory.
    $camp = Invoke-Godot 'bot_campaign' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --save=user://save_check_campaign/save.json --keep-save --fresh 1i'
    Test-Errors 'bot_campaign' $camp
    Select-String -Path $camp.Log -Pattern '^\[botrun\] (session|save|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($camp.Text -notmatch '\[botrun\] summary: campaign, 0 failures') { $failures += 'bot_campaign: summary missing or failures' }
    if ($camp.Text -notmatch '\[botrun\] session=s1_00_nothing attempt=1 \(invincible\) outcome=stopped .*version=v0\.0\.0->v0\.1\.0') { $failures += 'bot_campaign: S0 did not stop and ship v0.1.0' }
    # PLAN v9 1.14 (M43): the save points at the next session by id. M43.2: the chain ends
    # with the last playable session done and the save pointing at the cooking one (S7).
    $nextId = if ($firstCooking -ne '') { $firstCooking } else { '' }
    if ($camp.Text -notmatch ('"next":"' + $nextId + '"') -or $camp.Text -notmatch ('"done":\[[^\]]*"' + $lastPlayable + '"\]')) { $failures += 'bot_campaign: the save did not reach the end of the playable campaign' }
    # PLAN v8 M39: from S3 on the AI reacts live.
    if ($camp.Text -notmatch '\[botrun\] session=s1_04_level .*reactions=[1-9]') { $failures += 'bot_campaign: no live reactions in S4' }
    # PLAN v8 M40: S4 bends its walls at 12 s; the rule book lands it.
    if ($camp.Text -notmatch '\[botrun\] session=s1_04_level .*edits=1') { $failures += 'bot_campaign: S4 rule edit did not land' }
    # PLAN v8 M41: S5 plays wrong_variable; three gravity flips land through the rule book (the speed is the event's own).
    if ($camp.Text -notmatch '\[botrun\] session=s1_05_wrong attempt=1 \(invincible\) outcome=won .*edits=3 events=wrong_variable') { $failures += 'bot_campaign: S5 did not play wrong_variable' }
    # PLAN v8 M42: S5 now offers Next; S6 ends Stage 1 at v0.7.0. M43: S6 offers Next too.
    # M43.2 (G13b): S6 is 40 kills and slow-mo lands with the flip (a quiet cue): the gift,
    # the big enemies, inverted, slow-mo = 4 edits. Then the cooking screen, not S7.
    if ($camp.Text -notmatch '\[botrun\] session=s1_05_wrong attempt=1 \(invincible\) outcome=won .*choice=next_session') { $failures += 'bot_campaign: S5 is no longer the last session' }
    if ($camp.Text -notmatch '\[botrun\] session=s1_06_playground attempt=1 \(invincible\) outcome=won .*choice=next_session .*edits=4 .*landed=edit_gift_explode,edit_big_enemies,edit_inverted,edit_slowmo .*version=v0\.6\.0->v0\.7\.0') { $failures += 'bot_campaign: S6 did not end Stage 1 with its 4 edits' }
    # M43.2: after S6, the cooking screen (Stage 2's card, the AI building S7, then To be continued).
    if ($camp.Text -notmatch ('(?m)\[botrun\] cooking: session=' + $firstCooking + ' stage=2 lines=[1-9] building=v0\.8\.0 then=to_be_continued card=2\r?$')) { $failures += "bot_campaign: no cooking screen for $firstCooking after Stage 1" }
    if ($camp.Text -match '\[botrun\] session=s2_01_tryout ') { $failures += 'bot_campaign: the S7 stub was played (it is cooking)' }
    if ($camp.Text -notmatch "\[botrun\] chain: sessions=$playableCount ") { $failures += 'bot_campaign: no chain total' }
    Select-String -Path $camp.Log -Pattern '^\[botrun\] chain:' | ForEach-Object { Write-Host "    $($_.Line)" }
    # PLAN v8 M38: S3's debrief asks fork_mascot; the pick gives the AI its body.
    # M42.1: then fork_dash. The chains pick by seed: this invincible chain (1i) has
    # pick_seed 5 at S3 -> mascot index 2 (blob), dash index floor(5/3) mod 3 = 1 (grapple);
    # the mortal chain (2) has pick_seed 6 -> mascot 0, dash 2 (teleport). So the S4-S6
    # checks below run under the two new dashes, on purpose. M42.2: then fork_dash_aim,
    # index floor(pick_seed / 9) mod 2 = 0 for both (aim): grapple+aim and teleport+aim.
    # The forced S4 runs below play move (unanswered), plus one classic+aim.
    if ($camp.Text -notmatch '\[botrun\] session=s1_03_shooting .*pick=mascot_\w+,dash_(classic|grapple|teleport),dashdir_(aim|move)') { $failures += 'bot_campaign: S3 did not ask fork_mascot, fork_dash then fork_dash_aim' }
    if ($camp.Text -notmatch '"mascot":"(cursor|window|blob)"') { $failures += 'bot_campaign: the save has no mascot' }
    if ($camp.Text -notmatch '"dash_(classic|grapple|teleport)"') { $failures += 'bot_campaign: the save shipped no dash' }
    if ($camp.Text -notmatch '"dashdir_(aim|move)"') { $failures += 'bot_campaign: the save shipped no dash direction' }
    $campMortal = Invoke-Godot 'bot_campaign_mortal' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign 2'
    Test-Errors 'bot_campaign_mortal' $campMortal
    Select-String -Path $campMortal.Log -Pattern '^\[botrun\] (session|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($campMortal.Text -notmatch '\[botrun\] summary: campaign, 0 failures') { $failures += 'bot_campaign_mortal: summary missing or failures' }
    # PLAN v9 1.14 (M43): an M42.2 save at the end of Stage 1 (a fixture, read-only: the
    # snapshot never writes or moves it). M43.2: it lands on the cooking screen (S7 is
    # cooking), plays nothing and replays nothing; so does a save that played the old stub.
    foreach ($fixture in @('save_m42_2_stage1_end', 'save_m43_owner_shape')) {
        $door = Invoke-Godot "campaign_door_$fixture" "--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --save=res://tests/gut/$fixture.json 1i"
        Test-Errors "campaign_door_$fixture" $door
        Select-String -Path $door.Log -Pattern '^\[botrun\] (session|cooking|chain|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
        $doorFirst = Select-String -Path $door.Log -Pattern '^\[botrun\] (session=|cooking:)' | Select-Object -First 1
        if (-not $doorFirst -or $doorFirst.Line -notmatch ('^\[botrun\] cooking: session=' + $firstCooking + ' stage=2 .*then=to_be_continued card=2$')) { $failures += "campaign_door ($fixture): the save did not land on the cooking screen" }
        if ($door.Text -match '\[botrun\] session=') { $failures += "campaign_door ($fixture): a session was played" }
        if ($door.Text -notmatch '\[botrun\] chain: sessions=0 attempts=0 ') { $failures += "campaign_door ($fixture): no empty chain" }
        if ($door.Text -notmatch '\[botrun\] summary: campaign, 0 failures') { $failures += "campaign_door ($fixture): summary missing or failures" }
    }
    # M42.1: S4 with each new dash forced: it wins (invincible) and the dash is used.
    foreach ($style in @('grapple', 'teleport')) {
        $dashRun = Invoke-Godot "bot_dash_$style" "--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --only=s1_04_level --dash=$style 3i"
        Test-Errors "bot_dash_$style" $dashRun
        Select-String -Path $dashRun.Log -Pattern '^\[botrun\] (session|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
        if ($dashRun.Text -notmatch "outcome=win .*dash=$style uses=[1-9]") { $failures += "bot_dash_${style}: not won, or the $style was never used" }
        if ($dashRun.Text -notmatch '\[botrun\] summary: .*, 0 failures') { $failures += "bot_dash_${style}: summary missing or failures" }
    }
    # M42.2: S4 with the classic dash going where the bot aims.
    $aimRun = Invoke-Godot 'bot_dash_classic_aim' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --only=s1_04_level --dash=classic --dash-aim=aim 3i'
    Test-Errors 'bot_dash_classic_aim' $aimRun
    Select-String -Path $aimRun.Log -Pattern '^\[botrun\] (session|summary)' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($aimRun.Text -notmatch 'outcome=win .*dash=classic uses=[1-9].* aim=aim') { $failures += 'bot_dash_classic_aim: not won, the dash never used, or not aimed' }
    if ($aimRun.Text -notmatch '\[botrun\] summary: .*, 0 failures') { $failures += 'bot_dash_classic_aim: summary missing or failures' }
    # PLAN v8 M40: each rule edit forced into S4 lands through the rule book.
    $edits = Invoke-Godot 'bot_edits' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --only=s1_04_level --lift=30 --edits=edit_bouncy_walls,edit_big_enemies,edit_tiny_enemies,edit_inverted,edit_slowmo,edit_gift_explode 3i'
    Test-Errors 'bot_edits' $edits
    Select-String -Path $edits.Log -Pattern '^\[botrun\] edits:' | ForEach-Object { Write-Host "    $($_.Line)" }
    if (([regex]::Matches($edits.Text, '\[botrun\] summary: s1_04_level x1, .* 0 failures')).Count -ne 6) { $failures += 'bot_edits: a forced edit run failed' }
    if (([regex]::Matches($edits.Text, 'edit=edit_\w+ landed=edit_\w+@13\.5')).Count -ne 6) { $failures += 'bot_edits: a forced edit did not land at 13.5 s' }
    # PLAN v8 M41: wrong_variable plays every step in S5 (invincible seed) and the session is still won.
    # M43.3 (owner): a 20-kill goal, the event at 20 s, 2.5 s longer per direction (19 s).
    $ev = Invoke-Godot 'bot_event' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --only=s1_05_wrong 3i'
    Test-Errors 'bot_event' $ev
    Select-String -Path $ev.Log -Pattern '^\[botrun\] events:' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($ev.Text -notmatch 'outcome=win t=61\.8 enemy=\w+ event=wrong_variable@20\.0-39\.0 steps=6/6') { $failures += 'bot_event: wrong_variable did not play fully' }
    if ($ev.Text -notmatch '\[botrun\] summary: s1_05_wrong x1, .* 0 failures') { $failures += 'bot_event: run failed' }
    # M43.2 (G13b): S6's slow-mo lands with the flip (a quiet cue at the same kill count:
    # 1-3 ticks after it, within the printed 0.1 s), replacing M42's "hp 2" cue.
    $flip = Invoke-Godot 'bot_s6_flip' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --only=s1_06_playground 3i'
    Test-Errors 'bot_s6_flip' $flip
    Select-String -Path $flip.Log -Pattern '^\[botrun\] session=s1_06_playground' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($flip.Text -notmatch 'landed=edit_gift_explode@[\d.]+,edit_big_enemies@[\d.]+,edit_inverted@(\d+\.\d),edit_slowmo@(\d+\.\d)' -or ([double]$Matches[2] - [double]$Matches[1]) -lt 0 -or ([double]$Matches[2] - [double]$Matches[1]) -gt 0.11) { $failures += 'bot_s6_flip: slow-mo did not land with the flip' }
    if ($flip.Text -notmatch '\[botrun\] summary: s1_06_playground x1, .* 0 failures') { $failures += 'bot_s6_flip: run failed' }
    # M44: the S7 stub (dev jump only) hands the shotgun at 12 s through the give cue.
    $s7 = Invoke-Godot 'bot_s7_stub' '--fixed-fps 60 -s tools/bot_runs.gd -- --campaign --only=s2_01_tryout 3i'
    Test-Errors 'bot_s7_stub' $s7
    Select-String -Path $s7.Log -Pattern '^\[botrun\] session=s2_01_tryout' | ForEach-Object { Write-Host "    $($_.Line)" }
    if ($s7.Text -notmatch '(?m)outcome=win .* weapons=pistol:1,shotgun:1\r?$') { $failures += 'bot_s7_stub: not won, or the give cue did not hand the shotgun' }
    if ($s7.Text -notmatch '\[botrun\] summary: s2_01_tryout x1, .* 0 failures') { $failures += 'bot_s7_stub: run failed' }
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

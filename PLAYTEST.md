# Patch Notes: playtest sheet (G13.2, Stage 1 with your G13 feedback)

One page. The player reads **Before** and **Controls** only. The observer keeps the rest until the end.

## G13b changes (M43.2, from your S3-S7 notes of 2026-11-24)
- **S3:** 10 kills (was 15).
- **S4:** unchanged.
- **S5:** 25 kills (was 90 s; 2.5 min at most, "Time's up" after that). The gravity mix-up comes at ~20 s, right after the AI's version line, and each direction lasts 2.5 s longer (~17.5 s in all, the counter and the spawns paused). The session cannot end in the middle of it: reach 25 during the mix-up and the counter waits at 25/25 until gravity is fixed.
- **S6:** 40 kills (was 60). Explosive shots at ~11 s, big enemies at ~14 kills, then at ~27 kills the AI says your controls flip and that it will slow time down: the flip and slow-mo land together (10 s), and arrows around you show where each key goes now for the first few seconds (with reduce flashing on they stay still and only fade).
- **S7:** no longer playable. After S6 the Stage 2 card shows the AI cooking the next version (a few progress lines, a bar that never quite fills), then "To be continued"; a key goes back to the title. The real three-game tryout comes in a later build.
- **Your save** goes straight to that screen: nothing replays. It already reads v0.8.0 from the old S7 stub; the real S7 keeps that number. A new chain now ends Stage 1 at v0.7.0 and shows "Building v0.8.0".
- The cooking lines ("Trying three kinds of shooter...", "Compiling... mostly.", "One of them is on fire.", "Not ready yet. Soon.") are my draft: tone edits welcome.

## Before
- In `%APPDATA%\Godot\app_userdata\Patch Notes\`, back up, then move aside `save\save.json` (e.g. rename it to `save.before-g13.json`) and `playtest\runs.jsonl`. Without this the first-launch question is skipped and the logs mix.
- A New game is needed: the dash pick and where it goes are asked at S3's end. An old save stays on the classic dash, going where you move, for good.
- Run `PatchNotes.exe`. The screen reads "New campaign". Answer the flashing question the way you like.
- Play Stage 1 **in one sitting** until "To be continued" (about 6 min). After a death, Retry or Move on as you like.
- No F-keys (F1–F9 work in this build). The observer is silent: no help, no explaining, no reacting.
- **No spoilers** beforehand: not the mascot pick, not the gravity "mistake", not that the early sessions are broken on purpose.

## Controls
| | Keyboard and mouse | Pad |
|---|---|---|
| Move | WASD (ZQSD on AZERTY), arrows | Left stick |
| Aim and shoot | Mouse, left click | Right stick, right trigger |
| Dash / hook / teleport (the one you pick, once the game has it) | Shift or right click | Left trigger |
| Jump (only when the game lets you) | Space | A |
| Hold the AI's speech bubble | Hold Tab | – |
| Debrief: next line | Space, Enter or click | Lines move on by themselves |
| Pick a card | Click, or 1 / 2 / 3 | A on the card |
| Next / Retry | 1 or Enter | A on the button |
| Move on | 2 | A on the button |
| Pause | Esc | Start |

## What should happen (observer only)
- **S0:** nothing works, 5 s.
- **S1:** movement, 5 s.
- **S2:** things appear, no damage until ~11 s, then the overrun. A death is expected (Next, not Retry).
- **S3:** shots pass through until ~9.5 s, 10 kills, then the mascot pick, then the dash pick (classic / grappling hook / teleport), then where it goes (where you aim / where you move).
- **S4:** the AI's body, walls and the dash you picked (its line says how and where it goes), 30 s; bouncy walls ~13.5–23.5 s; then the enemy pick.
- **S5:** the picked enemy arrives at ~6 s; the version stamp appears at ~15 s (the AI says so); 25 kills (2.5 min at most). At 20 s the "speed" warning becomes gravity left / up / down (6.5 / 5.5 / 5.5 s, clock and spawns paused; the session cannot end during it), then +1 HP as an apology. A bomber you shoot blinks and explodes too (bigger blast); the AI says so the first time.
- **S6:** explosive shots at ~11 s, big enemies at 14 kills, inverted controls and slow-mo together at 27 kills (one warning for both, arrows around the player for ~3.5 s); a bomber you shoot blinks and explodes too (bigger blast); 40 kills (or 4 min), then Next session: the Stage 2 card with the AI cooking, "To be continued" and the title screen.

## Observer: write down during the session
- Per session: attempts, deaths, Retry or Move on, wall-clock time including the debrief.
- Laughs, sighs, "is it broken?", wanting to quit.
- Whether they read the AI's lines or skip them, and whether the bubble hides anything.
- Each rule-change warning: did they notice the marker before it landed, and was it fair? (Q4)
- Gravity: confusion or laughter, "a bug?" (Q3)
- Time on each pick, and which one.
- Did the dash pick feel like the AI asking, or like a menu?
- S0–S2: does the wordless start read as a story, or as broken? (Q5)
- The version stamp appearing in S5: noticed?
- Real bugs (not the AI's doing), with the time.

## After: ask in this order (short free answers, no rating grids)
1. Fun and quick? Too long, too short? Something new every session? (Q1)
2. The AI: charming or annoying? Too chatty or too quiet? Which body did you pick, and why? (Q2)
3. The gravity moment: a funny accident, or a bug? (Q3)
4. The rule changes: did they feel like the AI running the game? Did the warning make them fair? (Q4)
5. Nothing → words → a face: did it feel like a small story? (Q5)
6. Do you want to know what Stage 2 brings? (Q6)
7. **Owner only: new since G13.**
   - **a.** The dash pick comes at the end of S3, after the face, and the AI then says how to use it at S4's start. Right moment, or should it be asked live in S4, when the AI adds it?
   - **b.** Which dash did you take, and does it feel good? (You now choose: where you aim or where you move. Which did you take? Would you switch?)
   - **b2.** (Hook only) Did the hook miss too often?
   - **b3.** (Teleport with "where you aim") It goes a fixed 4 tiles along your aim, not to the cursor. Did you expect a blink to the cursor?
   - **c.** A shot bomber blinks for a moment, then blows up. It hurts you if you're within about 2 tiles, and its victims count as your kills. Too strong, too weak? Is the blink long enough to get away?
   - **d.** Your G13 questions still open, updated to this build: answer any you care about.
     - Explosive shots for all of S6, or ~20 s?
     - The gravity gag counts as seen when it starts (dying mid-event never shows its end). Keep, or when it finishes?
     - S5 difficulty: fair for you?
     - My own lines and titles (S5 "The wrong slider", S6 "Playground", the version line, S4's hit_none line): edit any.
     - Length (M43.2): about 4 min of action (bot chain 242 s, was 290 s), about 6 min in all, then the cooking screen. Right, or should S6 grow?
     - Move on after the first death? The mascot top-right? The names Cursor / Window / Blob?
     - The S0 glyphs as ASCII? The version stamp without "build N"?
     - Fun without the AI (`PatchNotes.exe -- --autostart --mute-ai`)?
     - S6 now: 40 kills, big enemies at 14 kills, then at 27 kills the flip and slow-mo together (one warning, arrows around you for ~3.5 s). Keep, or move any of them?
     - S6 now ends on the cooking screen (Stage 2's card, the AI building v0.8.0, then "To be continued"). Enough, or too long / too short?

## Files to send back (before Part B)
From `%APPDATA%\Godot\app_userdata\Patch Notes\`:
- `playtest\runs.jsonl`: one `"type":"campaign"` line per session attempt (outcome, attempt, Retry / Move on, play and wall time, reactions, rule changes, events, the picks, the flashing setting);
- `save\save.json`.

They contain no personal data. **Send them before Part B**: a replayed session writes to `runs.jsonl` too.

For the analyst: keep `"build":"M42.2"`, `"type":"campaign"` and the first process's `session_id`. First-try deaths = `attempt==1 && outcome=="died"` per session. `real_duration` is the attempt's wall time from the session's start to the end of play (pauses and the intro included, **the debrief not included**: the record is taken when play ends). Each line's `timestamp` is written when the debrief's button is pressed, so the total time with debriefs = last `timestamp` − first `timestamp` + the first line's `real_duration`. `forks` lists every pick of an attempt (3 at S3: face, dash, direction); `dash` is the style and `dash_aim` is `aim` or `move`.

## Part B (optional, owner)
A second New game with a different mascot and enemy (back up the first `save.json` first), or replay one session in memory:
`PatchNotes.exe -- --autostart --session=s1_05_wrong` (or `--session=s1_06_playground`).
To try another dash: `PatchNotes.exe -- --autostart --session=s1_04_level --dash=grapple --dash-aim=aim` (or `teleport`, `classic`; `--dash-aim=move`; also works with S5 and S6). Without `--dash-aim=` the dash goes where you move.
- On a pad with "where you aim", move the right stick once before dashing: until then the dash (like the gun) aims at the mouse cursor's spot.
- Use `--autostart` in every Part B command: it starts the session at once and never touches the save. Without it, pressing Continue or New game makes the real save live and the replay moves it.
- The jumped session answers the enemy pick with its first option, and the version stamp reads "v0.0.1" ("v0.0.2" in S5/S6 jumps with `--dash=`; `--dash-aim=` adds one more patch). That is expected. Without `--autostart`, `--dash=` and `--dash-aim=` would ship into the real save.

# Patch Notes: playtest sheet (G13, Stage 1)

One page. The player reads **Before** and **Controls** only. The observer keeps the rest until the end.

## Before
- In `%APPDATA%\Godot\app_userdata\Patch Notes\`, back up, then move aside `save\save.json` (e.g. rename it to `save.before-g13.json`) and `playtest\runs.jsonl`. Without this the first-launch question is skipped and the logs mix.
- Run `PatchNotes.exe`. The screen reads "New campaign". Answer the flashing question the way you like.
- Play Stage 1 **in one sitting** until "To be continued" (about 7 min). After a death, Retry or Move on as you like.
- No F-keys (F1–F9 work in this build). The observer is silent: no help, no explaining, no reacting.
- **No spoilers** beforehand: not the mascot pick, not the gravity "mistake", not that the early sessions are broken on purpose.

## Controls
| | Keyboard and mouse | Pad |
|---|---|---|
| Move | WASD (ZQSD on AZERTY), arrows | Left stick |
| Aim and shoot | Mouse, left click | Right stick, right trigger |
| Dash (once the game has it) | Shift or right click | Left trigger |
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
- **S3:** shots pass through until ~9.5 s, 15 kills, then the mascot pick.
- **S4:** the AI's body, walls and dash, 30 s; bouncy walls ~13.5–23.5 s; then the enemy pick.
- **S5:** the picked enemy arrives at ~6 s; the version stamp appears at ~15 s (the AI says so); 90 s. At 40 s the "speed" warning becomes gravity left / up / down (~10 s, clock and spawns paused), then +1 HP as an apology.
- **S6:** explosive shots at ~11 s, big enemies at 20 kills, inverted controls at 40 kills, slow-mo once when HP drops to 2 (it waits while another change is being announced or running); 60 kills (or 4 min), then "To be continued" and the title screen.

## Observer: write down during the session
- Per session: attempts, deaths, Retry or Move on, wall-clock time including the debrief.
- Laughs, sighs, "is it broken?", wanting to quit.
- Whether they read the AI's lines or skip them, and whether the bubble hides anything.
- Each rule-change warning: did they notice the marker before it landed, and was it fair? (Q4)
- Gravity: confusion or laughter, "a bug?" (Q3)
- Time on each pick, and which one.
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
7. **Owner only: defaults I took. Keep or change each.**
   - **a.** Explosive shots last the whole of S6. Keep, or ~20 s?
   - **b.** The gravity gag counts as "seen" when it starts: dying mid-event and retrying never shows its end. Keep, or count it when it finishes?
   - **c.** S5 difficulty. Bot first-try deaths (16 seeds; targets in brackets): S4 0/16 (≤ 3), S5 2/16 (≤ 4; it was 10/16), S6 2/16 (≤ 6; above S5 over 112 seeds: 23% vs 21%). S5 got there with five changes: spawns pause while gravity is broken, 1.5 s of grace after each flip, spawn rate ×0.8, +1 HP at the clear, and the picked enemy arriving at 6 s instead of on top of the event. Was it fair for you?
   - **d.** My own lines and titles: S5's title "The wrong slider" and intro, the "proud" clear line, the tiny / done lines, S5's version line ("See the number up there? That's my version."), S6's title "Playground", intro, notes ("A small game, start to finish") and debrief, S4's new hit_none line ("Not a scratch. The walls helped, right?"). Edit any.
   - **e.** Length. The M42 target was 9–11 min of play. Stage 1 plays about 4.9 min of action (not met: your cuts made S0/S1 5 s, S2 45 s, S4 30 s), about 7 min with deaths and reading. Right for a first stage, or should S6 grow?
   - **f.** Move on after the first death? The mascot top-right? The names Cursor / Window / Blob?
   - **g.** The S0 glyphs as ASCII ("_", "...")? The version stamp without "build N"?
   - **h.** S6 has no ending screen, only the "To be continued" button and the title line. Enough?
   - **i.** Optional: replay with `PatchNotes.exe -- --autostart --mute-ai` (`--autostart` keeps your save and logs untouched). Is it fun without the AI?
   - **j.** My departures from the plan for S6: the goal is 60 kills, not 40, and big enemies / inverted come at 20 / 40 kills, not at 60 s / 110 s, so both land for every player. Slow-mo waits while another change is announced or running. Keep?

## Files to send back (before Part B)
From `%APPDATA%\Godot\app_userdata\Patch Notes\`:
- `playtest\runs.jsonl`: one `"type":"campaign"` line per session attempt (outcome, attempt, Retry / Move on, play and wall time, reactions, rule changes, events, the picks, the flashing setting);
- `save\save.json`.

They contain no personal data. **Send them before Part B**: a replayed session writes to `runs.jsonl` too.

For the analyst: keep `"build":"M42"`, `"type":"campaign"` and the first process's `session_id`. First-try deaths = `attempt==1 && outcome=="died"` per session. `real_duration` is the attempt's wall time from the session's start to the end of play (pauses and the intro included, **the debrief not included**: the record is taken when play ends). Each line's `timestamp` is written when the debrief's button is pressed, so the total time with debriefs = last `timestamp` − first `timestamp` + the first line's `real_duration`.

## Part B (optional, owner)
A second New game with a different mascot and enemy (back up the first `save.json` first), or replay one session in memory:
`PatchNotes.exe -- --autostart --session=s1_05_wrong` (or `--session=s1_06_playground`).
- Use `--autostart`: it starts the session at once and never touches the save. Without it, pressing Continue or New game makes the real save live and the replay moves it.
- The jumped session answers the enemy pick with its first option, and the version stamp reads "v0.0.1". That is expected.

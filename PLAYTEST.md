# Patch Notes: playtest sheet (G12)

One page. The player reads **Before** and **Controls** only. The observer keeps **After** until the session is over.

## Before
- Run `PatchNotes.exe`. If the start screen shows anything other than `v0.0.0 · 0 runs`, press **Reset save** twice, then confirm it reads `v0.0.0 · 0 runs`.
- Play **about 10 runs** on that save (about 45–60 minutes; a break between two sittings is fine, the save keeps). Don't skip anything and don't read the patch notes ahead of time. Play the way you would at home.
- Between runs the AI holds a dev session. Some sessions ask you a question; the others are the AI's own work. Answer the way you like: there is no right answer.
- No debug keys (F1–F9). The observer doesn't help, explain anything or react. Only write down what you see.

## Controls
| | Keyboard and mouse | Pad |
|---|---|---|
| Move | WASD (ZQSD on AZERTY), arrows | Left stick |
| Aim / shoot | Mouse / left click | Right stick / right trigger |
| Dash | Shift or right click | Left trigger |
| Pick a card | Click, or 1 / 2 / 3 | A |
| The Rework card | Click, or 4 | A |
| Pause | Esc | Start |

## What should happen (observer only)
- Runs 1–2: two broken smoke-test builds, 20 s each. Run 3 on: the full 3-minute run.
- Session 3: the look question (three stills). Session 4: which enemy joins. Session 5: the AI builds an in-run patch on its own; from here a **Rework** card can show next to the options.
- Session 6 (after 6 runs): **the Stages question**: Gauntlet, Shifting or Breakout. From the next run on, a run has 3 stages and lasts up to ~6 minutes.
- Later sessions: one AI-built patch each, with Rework on offer.

## Observer: write down during the session
- At each run's start: the version (top right) and, from the Stages question on, the stage reached. At each run's end: how long it lasted.
- Every time the player laughs, sighs, says "is it broken?", or wants to quit.
- On each question: how long they took, whether they looked at the stills, and what they picked.
- **Rework:** the first session it shows, whether the player notices it, opens it, uses it, or backs out. What they swapped, and what they said.
- In staged runs: the stage clears, the exit gate in Breakout (did they find it?), the walls moving in Shifting (did they notice?).
- Anything that looked like a real bug (not the AI's doing). Note the time.

## After: ask in this order, then hand over the files
1. The questions you answered (the look, the enemy, the stages): did your answer change the game you then played? Would the other answers have made a different game? *(divergence)*
2. Did you see the Rework card? What did you think it did? If you used it: did it feel like freedom, or like a chore? If not: why not? *(Rework)*
3. The options you were shown: any that felt new or surprising? Any that felt like filler? *(creative options)*
4. The 6-minute run with stages against the 3-minute one before it: better, worse, or just longer? Which stage was best? *(the staged run)*
5. Between questions the AI built patches on its own and told you. Did you notice them in your runs? Did you miss choosing them? *(the AI's own patches)*
6. When you stopped: did you want one more version? Rate it 1–5, and say why. *(the hook)*

## Part B (optional, the owner): a second save
To compare two answers directly: note the first save's answers (the boot line ends with them, e.g. `answers fork_enemy=enemy_tank look_1=look_1_clean stages=stages_breakout`), then back up `save\save.json` and press **Reset save** twice. Play a second save to its Stages question (6 runs, ~25 minutes), picking differently each time, and play 2 staged runs. Then answer question 1 again.

**Files to send back** (from `%APPDATA%\Godot\app_userdata\Patch Notes\`): `playtest\runs.jsonl` (every run and dev session) and `save\save.json` (and the backed-up first save, if you played part B). They contain no personal data.

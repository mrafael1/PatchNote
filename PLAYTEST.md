# Patch Notes: playtest sheet (G11)

One page. The player reads **Before** and **Controls** only. The observer keeps **After** until the session is over.

## Before
- Run `PatchNotes.exe`. If the start screen shows anything other than `v0.0.0 · 0 runs`, press **Reset save** twice, then confirm it reads `v0.0.0 · 0 runs`.
- Play **at least 6 runs in one sitting** (about 20 minutes). Don't skip anything and don't read the patch notes ahead of time. Play the way you would at home.
- No debug keys (F1–F9). The observer doesn't help, explain anything or react. Only write down what you see.

## Controls
| | Keyboard and mouse | Pad |
|---|---|---|
| Move | WASD (ZQSD on AZERTY), arrows | Left stick |
| Aim / shoot | Mouse / left click | Right stick / right trigger |
| Dash | Shift or right click | Left trigger |
| Pick a card | Click, or 1 / 2 / 3 | A |
| Pause | Esc | Start |

## Observer: write down during the session
- At each run's start: the version (top right). At each run's end: how long it lasted.
- Every time the player laughs, sighs, says "is it broken?", or wants to quit.
- On each dev-session screen: how long they took to pick, and whether they read the cards.
- Anything that looked like a real bug (not the AI's doing). Note the time.

## After: ask in this order, then hand over the files
1. In the first two runs, what did you think was going on? Was it a joke, or a broken game? *(the broken first builds)*
2. Once it fully played, was a 3-minute run fun? What was the best moment? The worst? *(v0.0)*
3. When a run ended and the AI showed you what it could build next, did that feel like a reward, or a chore? *(the dev session)*
4. The three looks you chose between: did they play the way their pictures promised? Could you tell them apart? *(the look takes)*
5. When you stopped: did you want one more version? Rate it 1–5, and say why. *(the hook)*
6. Anything you wanted the AI to build next?

**Files to send back** (from `%APPDATA%\Godot\app_userdata\Patch Notes\`): `playtest\runs.jsonl` (every run and dev session) and `save\save.json`. They contain no personal data.

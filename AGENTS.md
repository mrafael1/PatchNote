# AGENTS.md: Patch Notes

Godot 4.7.x, GDScript, Windows (PowerShell + Git Bash). Tests use GUT (`addons/gut`, tests in `tests/gut/`).
`godot` is on PATH; `godot --version` must start with `4.7`.

For code conventions (names, APIs, patterns, commands), follow the existing code over this file or any doc, and list each mismatch you found in your final report. For what to build, PLAN.md wins (section 7).

## 1. Commands

| Purpose | Command |
|---|---|
| Import (fresh checkout, worktree, or any new `.gd`) | `godot --headless --path . --import` |
| Full check (definition of done) | `powershell -ExecutionPolicy Bypass -File tools\check.ps1`, which must print `CHECK PASSED` (several minutes) |
| Full check plus bots and hashes | `powershell -ExecutionPolicy Bypass -File tools\check.ps1 -BotRuns` (about 15 min) |
| One GUT file | `godot --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gtest=res://tests/gut/<file>.gd -gexit` |
| All GUT | `godot --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests/gut -ginclude_subdirs -gexit` |
| Run hash compare | `godot --headless --path . --fixed-fps 60 -s tools/run_hash.gd -- --compare=<ref.jsonl> 1 2 3 4` |
| Bot runs (pacing) | `godot --headless --path . --fixed-fps 60 -s tools/bot_runs.gd -- [opts] 1 2 3 4i 5i` (`Ni` = invincible) |
| Visual check (real window, no `--headless`) | `godot --path . -s tools/screenshot.gd -- <out.png>`; also `tools/campaign_shots.gd`, `mascot_capture.gd`, `mockup_capture.gd` (usage in each file's header) |
| Preview exe (not for the owner) | `godot --headless --path . --export-release "Windows Desktop" builds/<name>/PatchNotes.exe` |
| Ship a playtest build | `powershell -ExecutionPolicy Bypass -File tools\export.ps1` (always overwrites `builds\windows\`, see 5) |
| Regenerate the Stage 2 lines file | `godot --headless --path . -s tools/lines_file.gd` (a GUT test compares it) |

### Gotchas
- Always pass `--fixed-fps 60` to tests, bots and hashes. Without it, results do not replay.
- Headless Godot can exit 0 on a broken script, so the log scan is the real gate. Any `SCRIPT ERROR`, `Parse Error`, `ERROR:`, `Could not find type` or `Failed to load script` line is a failure. check.ps1 scans for these; scan yourself when you run godot by hand.
- Script arguments go after `--` (for example `-- --inert-save`). Before `--`, Godot swallows them.
- A timeout is not a failure. Re-run the command in the background; never cut a gate to fit a timeout.
- Windowed checks never go into check.ps1. Run them separately, open every PNG, describe what you saw in the report, and compare with the previous milestone's shots. Required for looks, skins, UI, menus and hosting changes.

## 2. What to run for which change

| Change | Minimum gate |
|---|---|
| Docs, PLAN, comments only | nothing, unless the file is a source for generated or loaded data (next rows) |
| Stage 2 line sources | `lines_file.gd` regen, then the GUT files that read lines, then `check.ps1` |
| `campaign/*.tres` or other `.tres` data | as gameplay below: a `.tres` edit can move hashes |
| One script, no play effect (UI text, a helper) | the affected GUT file(s), then `check.ps1` |
| Any new `.gd` | `--import`, commit its new `.gd.uid`, then `check.ps1` |
| Presentation (looks, skins, UI, hosting, menus) | `check.ps1 -BotRuns` plus the hash gates (3): no hash may move |
| Gameplay, RNG, sessions, weapons, mutations | `check.ps1 -BotRuns` plus the hash gates. A ref moves only on purpose (3) |
| Save or telemetry fields | the above, plus an old save/log still loads |
| Anything shipped to the owner | all of the above, plus `export.ps1` |

New tests must fail without the change. Say which tests prove what.

## 3. Determinism and hash gates

Seeded runs replay exactly. The refs and gate scripts live in `.check/`, which is gitignored and exists only in the main checkout.

- `CHECK PASSED` does not prove the hashes: `-BotRuns` skips its hash steps when `.check/ref_*` is missing. In a worktree or fresh clone, first copy the `ref_*` folders, the `runhash_*.jsonl` files and the latest gate script from the main checkout's `.check/`. If you cannot, report "hash gates not run".
- Latest gate script: `ls -t .check/*/gates.sh | head -1`. Copy it to `.check/<new>/gates.sh`, change `O=`, and change its `cd` line to `cd "$(git rev-parse --show-toplevel)"` (it hard-codes the main checkout, so a worktree would test main's tree). Run it with `bash`, then `grep -H "summary" .check/<new>/*.log`.
- Pass: `g0_sheet_iou.log` says `exit 0`; every other summary says 0 failures. `g0` needs `.check/pixel_art/render_sheet.gd` from the main checkout.
- Run exactly the matrix in that script: `--look=pixel`, `--skins=off`, `--shell` and `--viewport=` appear only where it uses them. `--shell` is campaign-only (`run_hash.gd` quits 1 on the v6 loop).
- Menu and handoff runs (`--menu=`, `--handoff=`) compare against an `--out=$O/<x>_base.jsonl` recorded on the same tree, not against a ref. S8 Survival offers no pick, so its third menu uses tick `1800` instead of `pick`. Copy this pattern for new menu gates.
- A ref changes only when a milestone deliberately changes that session's play. Record it in a new `.check/ref_<milestone>/` folder and state it in the milestone's "As built" Numbers. Otherwise the gate is "no ref changed".
- Only one `check.ps1 -BotRuns` or gate script at a time across all worktrees. They share one `user://` folder (`%APPDATA%\Godot\app_userdata\Patch Notes`) and fixed scratch paths (`user://save_check*/`, `user://m*_check/`, `user://playtest/run_hash.jsonl`), so parallel runs fail at random. A failure seen while another check ran is not a real failure: re-run alone before touching any test or ref.

## 4. Hard invariants

Lint-backed rules (the lint file says exactly what it checks; do not "fix" its exempt files):
- RNG only from the `RunState` streams `director_rng`, `gameplay_rng`, `loot_rng`, `pick_rng` (drops: `loot_rng`; offers and shuffles: `pick_rng`). A new `gameplay_rng` draw shifts every hash. No bare `randf`/`randi`/`randomize()`/`.pick_random()`/`.shuffle()`/`get_instance_id()` ordering. Lint: `test_playtest_build.gd` (skips `addons`, `tests`, `builds`, `tools`, dot-folders and five named presentation/core files; calls on a stream pass).
- Only `core/run_state.gd` writes `Engine.time_scale`. Lint: `test_big_slot.gd`.
- Mutation ids appear only inside `mutations/<id>/`. Lint and exemptions: `test_mutations.gd`.
- Looks stay out of gameplay: `systems/skins/` and `palette.gd` read no RNG, Tuning, WorldRules or `RunState.rules`; gameplay never reads Palette or Skins. Every hard-coded `Color` goes through Palette (white tints `Color(1, 1, 1, a)`, `Color.WHITE`, `Color.MAGENTA` allowed). No image files in game folders: art is drawn in GDScript or shaders (six legacy stills in `devsession/stills/` exempt). Lint: `test_pixel_skin.gd`.

Rules nothing enforces:
- In anything hashed, sort ids as Strings, never as StringNames (StringNames sort by interning order; this once moved a digest).
- Systems read `RunState.rules`; nothing branches on a "mode"; caps live in Tuning. Weapon ranks live on `Weapon`, never in RunState or the save.
- Save and telemetry schemas (`SaveGame.SCHEMA`, `Telemetry.SCHEMA`, `Telemetry.CAMPAIGN_SCHEMA`) only gain fields, because readers ignore unknown keys. Never rename or remove a key.
- Every `.gd` has a committed `.gd.uid`; a missing one breaks other machines. In `.tscn`/`.tres` text edits keep every `uid://` and `ext_resource` id as is (no renumbering); re-run `--import` if a uid or `class_name` changed.
- Line endings: the index is LF everywhere and `.gitattributes` sets the working-tree ending. Never convert a file's endings (it makes the whole diff noisy). Prefer exact-string edits over whole-file rewrites. Check with `git ls-files --eol <file>`.
- GDScript is Godot 4 only: `@export`, `@onready`, `await`, `instantiate()`, `signal.connect(callable)`, typed vars and `Array[T]`. If unsure an API exists in 4.7, check the class reference; do not guess.
- Every tween and flash respects the `reduce_flashing` setting.

## 5. Safety: the owner's data and builds

- Never read or write the real `user://save/save.json` or `user://playtest/runs.jsonl`.
  - Plain `godot --path .` and the editor's Run boot the start screen on the real save. Pass `-- --inert-save` or `-- --autostart`. `res://main.tscn` booted directly is inert.
  - `-- --save=` / `-- --log=` are `bot_runs.gd` options only (the game and `run_hash.gd` ignore them). bot_runs `--save=` is read-only unless `--keep-save` is given.
  - Tests that build a StartScreen clear `save_live`, and every test redirects `Telemetry.log_path`. An unredirected test once wrote the owner's save.
- check.ps1 fails if the real save folder changed during the run. That means the owner is playing: stop and report it. Never restore or edit the save without the owner's OK. Backups under `.check/` are read-only snapshots; to experiment, copy one into `user://<scratch>/` and load the copy.
- `builds\windows\` holds the owner's playtest exe and `export.ps1` always overwrites it. Run `export.ps1` only when shipping a playtest build; previews use the preview command (1).
- Parallel builds run in sibling worktrees (`../IA-roguelike-<name>`). Never read, write or run godot in a worktree that belongs to another session. A new worktree: `git worktree add ../IA-roguelike-<name> -b build/<name>` (branch names must never match a tag), then `--import`, then copy `.check/` refs (3).
- Never edit `addons/`, `.godot/` or `builds/` by hand.
- The repo is public. Keep personal details (names, emails, local paths, links) out of commits, docs and web queries.

## 6. Boundaries

- Always: run the gate from section 2 before you report done. End with this report:
  1. What changed (files).
  2. Gates and results: GUT n/n, hash summaries (or "hash gates not run" and why), bot time, `CHECK PASSED`.
  3. Captures looked at and what they showed.
  4. Doc/code mismatches found.
  5. Open questions and the defaults you took.
- Ask first (a builder agent: stop and put the question in the report; an interactive session: ask the owner): a new plan revision or large design, changing a hash ref, any push outside a milestone, touching the owner's save or `builds\windows\`.
- Never: delete an archived `PLAN.vN.md` / `ROADMAP.vN.md`, or retune difficulty from bot numbers alone. Bots measure pacing, not fun: invincible bots give pacing only, mortal bots compare time-to-death only. Check hit kinds before blaming a genre, and label bot numbers as bot numbers.

## 7. Docs and decisions

- Authority, highest first: the owner's latest message > PLAN.md section 0 subsections that say they win over older text > the rest of PLAN.md > `PLAN.v8.md` 6.x As-built (for how things work today, per PLAN.md 0.0) > other `PLAN.v*.md` / `ROADMAP.v*.md` archives (read-only).
- Design rules: PLAN.md section "Read this first". Determinism: "Contracts". Save/telemetry: "Save and version" and "Telemetry". Open defaults: "Still open".
- A default you took without the owner goes into PLAN.md "Still open" with a one-line question for the next report. Unanswered means the default stands. Do not re-ask settled decisions.
- `ROADMAP.md` is the long-range model; `PLAYTEST.md` is what the owner checks at each playtest gate (G-numbers).
- `campaign/lines_stage2.md` is generated: edit the source lines, then regenerate.
- Before a long pause, save resumable state (map, WIP diff, results) in `.check/handoff/`. Workflow run ids do not survive a new session.

## 8. Milestone routine

Steps 1-3 are the builder's. Steps 4-5 are the orchestrator's: a worktree builder commits only to its own branch and never pushes or tags.

1. Build. A small or feedback patch (`Mxx.y`) gets one build agent plus the gates plus a look at the captures. The multi-reviewer pass is for big milestones only. Give a rough time estimate up front.
2. Gate (section 2) and look at the windowed captures.
3. Docs: `const BUILD := "<Mxx>"` in `main.gd`, a row in PLAN.md "Milestones", a new `As built (<Mxx>)` subsection under "Milestones" with Deviations / Numbers / Review, and a PLAYTEST.md entry when the owner will see the change.
4. Commit:
   ```
   <Mxx>: <short title>

   - <what changed>
   - Review: <findings and fixes>
   - Hashes unchanged (<refs>); <n>/<n> GUT; check.ps1 -BotRuns and export.ps1 passed

   Co-Authored-By: <agent attribution line>
   ```
5. Tag in lowercase (`<mxx>`), then push only this milestone's tag: `git push origin main refs/tags/<mxx>`. Never `--tags`: local tags from unmerged worktree branches would go public.

## 9. Design rules that shape code

Full list: PLAN.md "Read this first". The ones code reviews catch most:
- Nothing exists by default; the in-game AI adds each piece live. A feature that is on without a session adding it is a bug.
- Irreversible changes are explicit: a flag, a UI lock, and tests that exclude them.
- Inspirations are used for mechanics only, never their names or art.

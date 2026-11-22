# Build Plan v6 — Divergence: forks, the shelf, rework, and the shooter's stages

**For:** the builder agent
**Goal of this build:** two saves should end up as **slightly or moderately different games**, and nobody should get stuck with an answer they regret. Today every change ships eventually, so every save converges on the same game (G11, 2026-11-22). From v6, every dev session asks **one question with 2–3 answers**. The answer you pick ships, and the others go to **the shelf**. A **Rework** card lets you swap a past answer for one on the shelf. Then the shooter grows its first maturity step, **Stages**, as one of those questions.
**Engine:** Godot **4.7.x stable**, GDScript, 2D, unchanged.
**Roadmap:** `ROADMAP.md` Phase 5, first half (5a). The second genre and the stage-end switch are Phase 5b, the next plan (v7).
**Supersedes:** `PLAN.v5.md` (Phase 4, done: M25–M30.2, G11 played). **Every v2–v5 contract stays in force** unless this document changes it.

Milestones continue from **M31**.

---

## 0. Read this first

| | v5 (now) | v6 |
|---|---|---|
| A dev session | 3 different changes; the 2 not picked stay available | **one question (a fork)** with 2–3 answers; the ones not picked go to the shelf |
| End of the content | every change ships; every save is the same game | each save answers each fork once; the answers diverge |
| Changing your mind | impossible | a **Rework** card swaps a past answer for a shelved one |
| The look mockup | 3 takes, the 2 not picked are lost | a fork like any other: they go to the shelf and can be reworked back |
| The AI's own ship | ships a change you did not pick | **answers a fork itself** with its agenda pick, and says you can rework it |
| Content | 6 changes, all shooter | 6 forks, 3 answers each where we can: 6 new pieces (section 3) |
| The shooter's run | ~3 min, one arena | still ~3 min until the **Stages** fork ships; then ~3 stages and ~6 min |

**Owner decisions behind this plan (2026-11-22):**
- **G11:** "gameplay is basic for now => but it's not necessary a bad point"; "mockup integration is a first nice step"; "upgrades can be even more creative in the future"; the next-patch gauge (fixed in M30.2).
- **Divergence:** "current dev session implement all features until there is no more. If we want each player to build smally / mediumly different final games without being frustrated and not be able to change a previous answer".
- **The mechanism:** the owner was shown A (exclusive picks plus rework), B (limited slots) and C (version rollback) and answered **"A"**.
- **After M34 (2026-11-22):** "dev session should never be about new patch in future run (ai will talk about implementing new patch but user never chose which one he want between 3 for example)"; "mockup and choices are only for big features, new mechanics impacting run from start".
  - Asked which questions are big, the owner chose **Look, Enemy and Stages**.
  - Asked how the AI adds in-run patches, the owner chose **one per session, by taste**.
  - See 1.7.

**Principles that hold:**
- Power stays inside the run (ROADMAP 1.8 rule 5): forks change *how* you play, never your stats.
- Fun before meta.
- The shell never names a genre or a change.
- A patch touches only its own folder.
- The reversibility invariant inside a run is unchanged.

**Amended:**
- ROADMAP 1.8 rule 3 "Never locked out" now reads: **a shelved answer is never lost; Rework reaches it.**
- ROADMAP 1.5's "3 different changes" shape becomes "3 answers to one question". The 3-mockup-takes shape is one kind of fork.

### Out of scope (v7 and later)
- The second genre (turn-based or platformer, ROADMAP open decision 9), the stage-end genre switch, and build translation.
- Bosses, mediums, look tiers 2+.
- In-run rollbacks and live AI patches (still parked, ROADMAP 1.7).
- Refusing a session outright: a "Surprise me" card is still open (section 9).

---

## 1. Contracts

### 1.1 Forks
- **`Fork`** (`devsession/fork.gd`, `devsession/forks/*.tres`):
  - `id`
  - `question` (the AI's line, e.g. "Who joins the fight?")
  - `options: Array[Change]` (2 or 3)
  - `requires_forks: Array[StringName]`: those forks must be *answered*, whatever the answer
  - `due_after_run`
  - `genre` (`&""` = shared)
  - `play_runs`: a hidden play threshold, the genre's runs in the save (ROADMAP 1.3, "picks and play")
  - `bump` (patch or minor)
  - `tags` (taste)
  - `mockup: bool`: its options are shown as stills
- **A `Change` belongs to at most one fork** (`Change.fork`, set by `ForkDB` at load). The basics (`kind = &"basic"`) belong to none, and the AI ships them as today (v5 4.8).
- **A mockup fork's options are changes with one take each.** The v5 `look_1` change with 3 takes becomes the fork `look_1` with 3 changes: `look_1_punchy`, `look_1_clean`, `look_1_arcade`. Each change unlocks its own `LookPreset`. `MockupTake` stays as the card data (`image`, `line`), held by the change. This removes the "a mockup is one change with 3 takes" special case.
- **Answered** means that one option of the fork is shipped. **Shelved** means the options of an answered fork that are not shipped. Both are derived from `SaveGame.shipped()`. **No save schema change for the state**: the shelf is `fork.options - shipped`.
- **Dependencies sit on forks, not on answers.** v5's `patch_horde_mode` "requires `enemy_tank`" becomes the pressure fork requiring the enemy fork. **This is what makes Rework safe:** swapping an answer never unanswers a fork, so nothing shipped later can lose its prerequisite.
- **`ForkDB`** (inside `ChangeDB`, same autoload) sorts and validates in `problems()`:
  - ids are unique;
  - every option exists and is in one fork only;
  - 2–3 options per fork;
  - no fork requires itself;
  - a mockup fork's options each have an image;
  - `requires_forks` exist and form no cycle;
  - an option's `unlocks` are valid (as today).

### 1.2 Which session
In order:
1. **BASIC** (v5 4.8, unchanged) while a basic is missing.
2. **FORK:** pick one ready fork.
   - Ready means: not answered, `requires_forks` answered, `due_after_run <= runs`, genre at least Playable, and the genre's runs `>= play_runs`.
   - **Due first:** any ready fork with `due_after_run > 0` comes up the first time it is ready (as `look_1` does today, at session 3 after the basics).
   - Otherwise the fork is drawn by taste: weight × `Taste.weight_mult_raw(fork.tags)`, seeded from the run seed and the session number, as today.
   - **The cards are the fork's options.** On a non-mockup fork, one option is marked **"AI's wish"**: the one least liked by tag (ROADMAP 1.8 rule 4).
   - Picking ships it, bumps the version by the fork's `bump`, and shelves the others. Taste: the pick is nudged up and the shelved options slightly down (`Taste.on_session_pick`, unchanged).
3. **REWORK card:** in a FORK session, a 4th card of its own style ("Rework…") appears when at least `Tuning.rework_after_forks = 2` forks are answered and the shelf is not empty.
   - Choosing it costs the session: no new fork is answered this time.
   - It opens the rework list (1.3).
4. **REWORK-only:** no fork is ready but the shelf is not empty. The opening line is "Nothing new on my list. Want to change something?", then the rework list plus **"Keep it as it is"** (no bump; the session is logged).
5. **NONE:** no fork ready and the shelf empty (v5's line, no bump).

- **The AI answers a fork itself** every `Tuning.ai_own_ship_every = 4` sessions (counted in the save). After the player's pick, it answers a second ready fork with that fork's agenda option. The notes say: "I answered *Who joins the fight?* myself: Lancer. Rework it if you disagree."
  - This replaces v5 4.4 (shipping a change you did not pick), which would undercut divergence.
  - It never answers a mockup fork, and never during a REWORK-only session.
- **AI_LAST** (v5) is gone: with forks there is no "one change left".

### 1.3 Rework
- **The rework list** shows one row per answered fork that has a shelf: the fork's question, "now: Tank", then a button per shelved option ("→ Bomber", "→ Lancer"). A mockup fork shows each shelved still.
- **Swap:** unship the current answer, ship the shelved one, and bump a **patch** step (a rework never takes a minor step, even on a minor fork; the version only goes up). Then come the patch notes: "Version 0.2.4 · Reworked *Who joins the fight?*: Tank → Bomber", and the unlock lines for what changed ("No more Tanks. New enemy: Bomber").
  - The old answer goes to the shelf. Reworking back later is allowed.
  - `SaveGame.unship(id)` is new: it removes the id from `shipped` and keeps the session history.
  - A look fork's swap also calls `SaveGame.set_look`.
- **Everything derived follows the next run:** the pool, the enemies, the look, the Stages flavour. Nothing changes mid-run. F9's debug session and Shift+F9 stay.
- **Taste:** +nudge for the new answer, −nudge for the old one. A rework is a strong signal.
- **Limits:** none beyond costing the session. "Not frustrated" (G11) means that changing your mind must never be blocked.

### 1.4 Telemetry (schema 3)
- A session record adds `fork`, `options`, `pick`, `shelved`, `rework: {fork, from, to}` or null, `ai_fork: {fork, pick}` or null, and `kept: bool` (REWORK-only "Keep it as it is").
- Run records add `forks: {fork_id: answer}`, which is what makes saves comparable.
- The save itself stays schema 1: a v5 save loads unchanged. An old save with two options of one fork shipped counts the fork as answered with an empty shelf, and nothing is unshipped (tested).

### 1.5 As built (M31)
- **`Fork.options` are change ids** (`Array[StringName]`), not embedded changes; `Fork.changes()`, `answer()`, `is_answered()` and `shelf()` derive everything from the save. Forks and changes share one id namespace (`ChangeDB` rejects a clash).
- **`Change.take: MockupTake`** replaces v5's `takes` array. A look option is `look_1_<take>` with its preset on the take; `Change.short_name()` is the take's title ("Punchy"). `ChangeDB.problems()` requires a look change to have a take with a preset.
- **M31's forks:** `look_1` (Punchy · Clean · Arcade), `fork_enemy` (Tank · Bomber) and `fork_hands` (Auto-aim · Motion time · Horde, until M33). The v5 requires (bomber → tank, horde → tank) are gone.
- **The AI answers a fork only when at least `Tuning.ai_fork_min_ready = 2` ready non-mockup forks are left after the pick**, so it never takes the player's last question. In a first bot chain it answered `fork_enemy` right after the player's `fork_hands`, so the player only ever answered 2 of 3 forks. With M31's 3 forks it never fires; it does once M33 brings 5.
- **The question is spoken in the opening line** (`DevSession.opening` ends with `Fork.question`). A separate title over the cards is left for M32, which reworks the screen anyway.
- **Session kinds:** `basic`, `fork`, `none` (`DevSession.shape`); v5's `mockup`, `changes` and `ai_last` are gone. The bot's line reads `kind=`.
- **Old saves:** `SaveGame.RENAMED` maps `look_1` to `look_1_<the save's take>` (punchy if none) on load; everything else loads as is.
- **Fixed on the way:**
  - the patch notes no longer list a basic's unlocks as enemies ("New enemy: Enemies" since M29b);
  - the 20 s bot test pins the look and the save (`test_combat.gd`); the count is 7 alone and in the suite;
  - the stills are not byte-stable (unseeded particles, PLAN.v5 4.9 corrected).

### 1.6 As built (M32)
- **`DevSession.REWORK`** is a session kind: no fork is ready and `rework_rows()` is not empty. `NONE` now needs an empty shelf too, so with M31's 3 forks every session after the last answer is REWORK-only.
- **`DevSession.rework(fork, to)`** unships the answer (`SaveGame.unship`), ships `to` with a patch step, sets the look for a take, calls `Taste.on_rework` (the new answer +PICK, the old one 2 × PASS), and logs the session (`rework: "fork:from->to"` in the save, `{fork, from, to}` in telemetry). `keep()` logs `kept: true` with no bump. No pick and no AI fork answer happen in a rework session.
- **The question moved from the opening line to a title** over the cards (and over the list).
- **The Rework card** is last, 240 px wide, outlined in blue, on key 4 (`choose_4` is new). The list rebuilds from the save each time it opens. Mockup rows show the shelved still as the button's icon. "Back" returns to the cards with a fresh input delay.
- **Patch notes for a rework:** "• Reworked "*question*": Tank → Bomber", then "No more Tanks" / "Out of the pool: …" for the old answer, the unlock lines of the new one, then "Back on the shelf: Tank."
- **Run records add `pool`** (ids), so a rework's next run can be checked exactly. The schema stays 3.
- **F2:** one "rework <fork> <option>" button per shelved option (`Main.debug_rework`). It logs a session of its own, like Shift+F9.
- **Fixed on the way:** three mockup cards were 1368 px wide on the 1280 px screen from M29 to M32, so the third card was clipped. Cards now shrink to fit (`DevSessionScreen.card_width`), and their stills shrink with them.

### 1.7 As built (M34.2): big choices only
- **Questions (forks)** are only for big features that change a run from its start: `look_1`, `fork_enemy`, and `stages` (M35). `fork_hands`, `fork_pressure` and `fork_odd` are gone.
- **The AI builds the in-run patches itself.** IMPLEMENT is a new session shape, between FORK and REWORK in 1.2's order.
  - It applies when no question is ready and an in-run patch (a change in no fork) is left to build.
  - The AI draws one by taste (weight × `Taste.weight_mult_raw(tags)`, seeded as the fork draw), ships it with a patch step and says so: "No question this time. I built something for your runs: "Orbit"."
  - The notes list it with "Built by the AI. It shows up among your patch offers."
  - When Rework is on offer (2 answers and a shelf), the screen shows "Play" and the Rework card. A rework then comes on top of the AI's patch (two patch steps); otherwise the flow goes straight to the notes, as a BASIC.
  - Without that, a save would wait ~9 sessions before it could change its mind.
- **The AI never answers a question itself** (`Tuning.ai_own_ship_every = 0`; the code stays).
- **A fresh save's sessions:** 2 basics, the look, the enemy (and Stages once it is ready), then 9 IMPLEMENT sessions, then REWORK-only.
- **Saves are unchanged:** shipped answers to the old patch questions stay shipped, and the AI builds the rest.
- **Divergence** now comes from the 2 questions (3 × 3) and Stages, plus the order the patches arrive in. A finished save has every patch.
- **Numbers (bot):** 16 fresh 14-run invincible chains with rework chance 0.2. Each played 2 basic, 2 fork and 9 IMPLEMENT sessions; 0 failures, and every save ends with all 13 changes it can have. 25 IMPLEMENT sessions reworked as well (11 chains), with 0 mismatches in the next run. 8 distinct final answer sets of the 9 possible.
  - Found on the way: the bot rolled its rework chance every frame while the screen's input delay ignored "open Rework" but not "Play", so it never reworked there. It now waits for `DevSessionScreen.input_ready()`.

---

## 2. The dev session screens
- **Fork session:** the question as a title over the cards (`Fork.question`); the cards are as today (mockup stills or change cards). The AI's wish badge stays, and the Rework card sits at the right with its own outline. Keys 1/2/3 pick and 4 opens Rework.
- **Rework list:** a scrolling column of rows (1.3) plus "Back" (returns to the fork session) or "Keep it as it is" (REWORK-only). The input delay is as today.
- **Patch notes:** for a pick, as today, plus a shelf line ("On the shelf: Bomber, Lancer"). For a rework, "Reworked …: A → B" and the unlock changes. Then the AI's own fork answer, if any.
- **Start screen:** the save line adds the answered forks ("v0.2.4 · 9 runs · 5/6 forks").
- **F1 overlay:** `forks=look_1:clean,fork_enemy:tank,...`; F2 lists the shelf.

---

## 3. Content: the shooter's forks

The bar for every option, from "upgrades can be even more creative" (G11) and ROADMAP 1.4:
- it changes how a run *plays*, visible within 10 s;
- no stat options ("+20% damage" is never a fork answer);
- the three answers to one question pull in different directions, so the choice says something about the player.

| Fork | Question | Options | Bump | Requires | Notes |
|---|---|---|---|---|---|
| `look_1` | "How should it feel?" | Punchy · Clean · Arcade (exist) | minor | — | mockup; due after the basics, as today |
| `fork_enemy` | "Who joins the fight?" | **Tank** (exists) · **Bomber** (exists) · **Lancer** (new) | patch | — | |
| ~~`fork_hands`~~ | (removed in M34.2) | Auto-aim · Motion time · Orbit | — | — | built by the AI, one per session (1.7) |
| ~~`fork_pressure`~~ | (removed in M34.2) | Horde · Hunter · Elite | — | — | built by the AI (1.7) |
| ~~`fork_odd`~~ | (removed in M34.2) | Echo · Magnet · Well | — | — | built by the AI (1.7); the "Experimental:" voice stays |
| `stages` | "The shooter needs a real run. Which one?" | Gauntlet · Shifting · Breakout | minor (maturity step) | `look_1` and `fork_enemy` answered (M34.2) | mockup; `play_runs = 6`; section 4 |

**New pieces** (one folder each; takes for `topdown` only; parity rule as v5 M30: mortal time-to-death within ±15% with the piece unlocked vs not, 16 seeds):
- **Lancer** (enemy): stops, telegraphs a line for 0.7 s, then charges along it through other enemies (they take its hit too, as enemy-faction damage, like the bomber). Hp 3. It reuses `enemy_walker.gd` with a `lancer` archetype (v4 M20's design).
- **Orbit** (small, unlocked by `fork_hands`): 2 shards circle you at 1.5 tiles and hit what they touch (1 damage, 0.4 s per-enemy cooldown). Your gun is unchanged.
- **Hunter** (small, `fork_pressure`): from 60 s, one slow stalker follows you for the rest of the run. It can't be killed; 8 hits stun it for 4 s. It is not a reward kill, and its contact costs 1 HP as usual.
- **Elite** (small, `fork_pressure`): each spawn wave has one marked enemy with a shield that drops after 3 hits; killing it clears the 3 nearest enemies' shots.
- **Echo** (small, `fork_odd`): each of your shots fires again 0.6 s later from where you stood when you fired it.
- **Magnet** (small, `fork_odd`): enemy shots that pass within 1 tile of another enemy curve into it and hit it.
- **Well** (small, `fork_odd`): a killed enemy leaves a 1 s pull field that drags nearby enemies (not you) toward its centre.

The 4 starter smalls stay outside forks (always in the pool), and so do the basics.

**Divergence in numbers:** 6 forks (Stages included) with 3 answers each give 3⁶ = 729 possible saves. Two players share every answer by chance about once in 729 (uniform picks). Taste skews this, which is the point.

### 3.1 As built (M33)
- **Five forks of three:**
  - `look_1`;
  - `fork_enemy`: Tank · Bomber · Lancer;
  - `fork_hands`: Auto-aim · Motion time · Orbit;
  - `fork_pressure`: Horde · Hunter · Elite (requires `fork_enemy`);
  - `fork_odd`: Echo · Magnet · Well (requires `fork_hands`).
- **Interpretations where section 3 left room:**
  - **Lancer:** a `lancer` archetype of `enemy_walker.gd`.
    - It telegraphs a visible line (a `Line2D`) and charges by `Mover.dash`. The charge stops at a wall.
    - It hits everyone within reach once per charge, with damage kind `charge`.
    - It spawns from 35 s with chance 0.1.
  - **Elite:** the spawner sends single enemies, not waves, so "each wave has one" became **every 8th spawned enemy**.
    - "Clears the 3 nearest enemies' shots" became **removes every enemy shot within 5 tiles** of the dead elite. Projectiles do not know who fired them.
    - The shield is a new generic `Health.shield_hits` (whole hits absorbed, `shield_hit` signal). The elite's mark component owns it and takes it back on a revert.
  - **Hunter:** it is not an enemy (its own group): no kill, no spawn cap, not an auto-aim target, explosions pass it by.
    - It cannot be hurt: a shield that never runs out. Every 8th shield hit stuns it for 4 s.
    - A watcher component on the player sends it at 60 s of run time from the spawner's off-screen point, and takes it away on a revert.
    - A first version used a watcher node added to the world with `call_deferred`. It leaked when the world went first, and could send two hunters.
    - Like the walkers, it wanders when stuck behind a wall.
    - Its parity was measured before the wander rule.
  - **Well:** a drag on the position (`move_and_collide`), not a velocity push.
    - An enemy's own steering (accel 3200 px/s², friction 3600) cancels any push below that, so a push would not show.
  - **Magnet:** the shot's damage, counted as the player's (the patch's kill, `source_patch` magnet).
    - Enemies within 1.5 tiles of the muzzle are ignored, so a shot never curves back into its shooter.
  - **Echo:** a physics-time timer that pauses with the tree. An echo is the patch's shot: it does not echo and does not pulse motion time.
- **Old saves:**
  - A v5 save that answered with Horde keeps it shipped and so answers `fork_pressure`; `fork_hands` is asked again.
  - A v5 save with Tank and Bomber now has the Lancer on its shelf (1.4 said "empty shelf" before M33's third option).
- **The smoke matrix samples** (M33): every single patch, every pair, the full stack, and 40 seeded larger subsets, about 132 per slot.
  - The full matrix was 8191 subsets per slot with 13 smalls, and the suite never finished.
  - Under motion time it no longer compares the time scale after a rebuild: B1's factor is smoothed over past ticks. The old matrix passed only because its seeds caught the bot at full speed.
- **Numbers:** see the M33 row.

---

## 4. The shooter's Stages step
ROADMAP 1.3's ladder: Playable → **Stages**. The `stages` fork ships the step (`SaveGame` genre step → `stages`, a minor bump). Its three takes are **presets of one stage build** (ROADMAP 1.5's scope rule).
- **Stage plumbing** (v4 M16's kept parts, ROADMAP section 5):
  - `StageDef` (arena data, duration, goal, spawn preset);
  - the run loop's stage sub-states (play → stage clear → next stage → the last stage's release candidate);
  - the genre reports "stage ended" to the shell;
  - the build carries across stages (the stack is kept: same run);
  - a cross-stage determinism test (same seed, same 3-stage run hash).
- **Arenas as data** (v4 M15, re-scoped): `levels/arenas/*.tres` (blocks, spawn points, start), validated per genre. Today's arena becomes `arena_0`; there are 2 new arenas.
- **The takes:**
  - **Gauntlet:** 3 arenas in a row, ~110 s each; the stack carries; 1 prompt per stage.
  - **Shifting:** one arena whose middle blocks move between stages (3 layouts); same pacing.
  - **Breakout:** survive ~90 s, then an exit gate opens on the far side and you must reach it under fire; 3 stages.
- **Pacing:** 3 small prompts per run as today, one per stage. The release candidate wave is the last stage's end. Target ~6 min (median 330–390 s, invincible bot, a save with the Stages step shipped).
- **Stills:** `mockup_capture.gd` gains a stage scene (a stage-clear moment per take).
- **Reworking `stages`** swaps the flavour. It never returns to the single arena: a maturity step does not go back.

### 4.1 As built (M34)
- **Arenas are data:** `ArenaDef` (`levels/arena_def.gd`) in `levels/arenas/`:
  - `arena_0` "Ledges" is the M14 arena, with its blocks in the same order;
  - `arena_1` "Pillars": 18 pillars, two walls shielding the middle;
  - `arena_2` "Lanes": long walls cut it into three lanes.
  - Every arena is 66 × 22 tiles inside the border (the parked turn grid and the camera rely on it). `Arena.new(def)`; with no def, `arena_0`.
  - `problems(genre)` checks a layout for each genre it lists. For top-down: blocks inside the border, the start and markers 0.5 tile clear of blocks, at least 8 markers, and every marker walkable from the start. arena_0's gravity check stays in `test_gravity.gd`.
- **Stages:** `StageDef` (arena, duration, goal, prompts, spawn rate and cap) and `StageSet` (`levels/stages/<id>.tres`, the stages in order).
  - `StageSet.for_run()` gives `single()` unless an override is set: one stage on `arena_0`, with `Tuning.prompts_per_run` prompts and no minimum time. That is the v0.0 run.
  - `gauntlet` (debug only until M35): arena_0, 1 and 2, 100 s each, one prompt each. Spawns are ×1, ×1.15 and ×1.3 in rate and ×1, ×1.1 and ×1.2 in cap.
  - `goal` has one value, `survive`. Breakout's exit gate is M35's.
- **The run loop:** play → (the stage's prompts are done and its duration has passed) → `stage_clear` for `Tuning.stage_clear_time` = 2.5 s → the next stage's play. The last stage's end is the release candidate.
  - At the clear: the spawner stops, enemies deal no damage for the clear plus 1.5 s, the AI says "Stage 1 of 3 passes. Loading the next level." and the run log gets `stage_clear` and `stage_start`.
  - The Director gets a per-stage limit (`prompt_limit`, `begin_stage`). A stage's first prompt uses the first-prompt gap. On a one-stage run nothing is set.
- **The genre at a stage change:**
  - It clears the world (enemies, shots, patch leftovers). It sweeps a second time once the spawns queued that tick have entered the tree.
  - It swaps the arena, puts the player at the new start and resets the camera bounds.
  - It points the spawner and the turn clock at the new arena; the turn clock's tile cache is reset.
  - It forwards `stage_ended(index)`, which the shell relays as `EventBus.stage_ended`.
  - The player, its components and the stack carry over. Two groups: `keeps_across_stages` stays where it is (the turn overlay); `follows_across_stages` is moved to one of the new arena's markers (the Hunter).
- **Telemetry:** the run record adds `stages: {set, total, reached, starts}`. The HUD shows "Stage 2/3" on runs with more than one stage.
- **Tools:** `bot_runs.gd --stages=<id>` (the run line shows `stage=reached/total`) and `run_hash.gd --stages=<id>`. One-stage hashes leave the stage index out, so the M33 recordings still compare.

### 4.2 As built (M34.1): owner feedback after M34 (2026-11-22)
- **"Screen flickering on bullet explosion is a bit too much":**
  - The explosion's white screen flash (Punchy and Arcade looks) went from 25% to 12%.
  - At most one flash per 0.5 s (`ScreenFx.FLASH_COOLDOWN`). Exploding shots used to flash several times a second.
  - The shake is unchanged.
- **"Killing enemies should fill the gauge quicker, or at least bring the next patch sooner":**
  - Before, a prompt needed a kill count *and* a time gap (40 s, then 48 s). Kills reached their count long before the time, so the gauge only followed the clock.
  - Now there is one meter. Time fills it in `prompt_max_gap` = 80 s (55 s for the first meter of a run or stage, when few enemies have spawned). Each counted kill is worth `prompt_kill_seconds` = 1 s more, and the gauge flashes bright on every kill.
  - A prompt never opens sooner than 20 s after the last one. "Next patch incoming" shows from 85% of the meter.
  - `first_prompt_kills` and `prompt_kills_step` are gone.
  - **Numbers (bot, 16 seeds, `--fresh` with the basics unless noted):**
    - prompts open at 37/83/129 s (the old schedule was 40/88/136 s);
    - invincible runs last 174.2 s, and 174.1 s with everything unlocked (target 170–200);
    - mortal runs last 104.5 s, against 108.9 s with the old schedule, re-measured on this code.
    - A 65 s first meter gave 88 s mortal: the first prompt (and its 1 HP heal) came too late.
  - The M33/M34 run hashes no longer apply: the prompts open at other times.

---

## 5. Bot and debug
- **Bot (`tools/bot_runs.gd`):**
  - it picks a random fork answer from the run's seed (as today);
  - in a FORK session with the Rework card, it reworks with `--rework-chance` (default 0.2): a random row, a random shelved option;
  - in a REWORK-only session it reworks or keeps, 50/50;
  - `--ship=` accepts fork options as today.
- **New line:** `[botrun] session=N kind=fork|rework|basic|none fork=<id> cards=[…] pick=<id> shelved=[…] rework=<fork:from->to|-> ai_fork=<fork:pick|-> version=a->b`.
- **Save line:** adds `forks={…}`.
- **Debug:**
  - F9 opens a session as today. Shift+F9 answers the next ready fork with its first option.
  - The F2 console gets `rework <fork> <option>`.
- **Housekeeping:**
  - Fix the flaky 20 s bot-kill test in `test_combat.gd` (it failed in M29 and M30.1): find the real-time dependency, or assert a kill count that cannot flake.
  - `check.ps1` reports the real-save guard as "the real save changed: is the game running?".

---

## 6. Tests (additions)
- **Forks:**
  - `ForkDB.problems()` is empty for the shipped data and catches each bad case.
  - Every non-basic change except the starters is in exactly one fork.
  - A fork session's cards are exactly its options.
  - A pick shelves the rest.
  - Ready respects `requires_forks`, `due_after_run` and `play_runs`.
  - Same seed and same save give the same fork and the same cards.
- **Rework:**
  - A swap unships A and ships B, and bumps one patch step.
  - The pool, enemies and look of the next run match B exactly.
  - Reworking back restores the first state, apart from the version and the session log.
  - A rework never unanswers a fork.
  - "Keep it as it is" does not bump.
  - The rework card is hidden below `rework_after_forks` and when the shelf is empty.
- **AI fork answer:** it fires on the cadence, uses the agenda option, never touches a mockup fork, and its notes line names the fork.
- **Old saves:** a v5 save with tank and bomber both shipped loads with `fork_enemy` answered, an empty shelf, and nothing unshipped. A v5 save with `look_1` shipped maps to `look_1_<its take>`.
- **Stages:**
  - Stage sub-states are in order.
  - The stack carries across stages.
  - The 3-stage run hash matches across two runs.
  - Each take's preset differs; reworking keeps the step.
  - The parked turn-based run still passes its own gates.
- **New pieces:** one test file per piece (telegraph then charge, orbit contact cooldown, hunter stun, elite shield, echo delay, magnet curve, well pull), plus the parity sweep numbers in the milestone report.

---

## 7. Milestones

| # | Milestone | Builder gate | Owner gate |
|---|---|---|---|
| M31 | Forks | 1.1, 1.2 (without Rework), 1.4: `Fork`, `ForkDB`, the 6 v5 changes regrouped into 3 forks: `look_1` (split into 3 changes), `fork_enemy` (Tank · Bomber) and, until M33, `fork_hands` (Auto-aim · Motion time · Horde); fork sessions, shelving, the AI answering a fork, telemetry schema 3, bot, old-save mapping, the flaky test fix. **Numbers:** 16 fresh 10-run bot chains: the final answer sets differ (at least 8 distinct of 16 with 3 × 2 × 3 = 18 combinations); every option is the final answer in at least one chain; same seeds → identical save. **As built:** 11 distinct final sets of 16 (chains seeded k·100+1…+10, invincible); final answers Tank 10 · Bomber 6 · Auto-aim 8 · Horde 5 · Motion time 3 · Punchy 7 · Arcade 6 · Clean 3; chain 1 replayed byte-identical; the AI answered no fork (3 forks, 1.5) | — |
| M32 | Rework | 1.3, section 2: Rework card and list, REWORK-only sessions, "Keep it as it is", `SaveGame.unship`, look swaps, notes lines, taste nudges, bot `--rework-chance`, F2 `rework`. **Numbers:** in the 16-chain sweep with `--rework-chance=0.2`, at least half the chains rework at least once, and every rework's next run shows the swapped pool, enemies or look (checked from telemetry). **As built (bot, same seeds as M31):** 16/16 chains rework at least once; 35 reworks (5 from the Rework card in fork sessions, 30 in REWORK-only sessions) and 29 keeps; 0 mismatches in the next run; 13 distinct final answer sets; chain 1 replayed byte-identical. 59 of 144 sessions were REWORK-only: with 3 forks the questions run out by session 6, until M33 | — |
| M33 | Creative content | Section 3: Lancer, Orbit, Hunter, Elite, Echo, Magnet, Well; Horde moves from `fork_hands` to `fork_pressure`; the forks `fork_pressure` and `fork_odd`; an old save that answered `fork_hands` with Horde keeps it shipped and answers `fork_pressure` (tested); tests, card art lines. **Numbers:** parity for each new piece (±15%); invincible pacing with everything shipped still 170–200 s; the divergence sweep re-run on 5 forks: at least 12 distinct final sets of 16. **As built (all bot numbers, mortal seeds 1–16 against a fresh v0.0.2 baseline, median 108.9 s):**
  - **"Unlocked vs not" turned out to measure the offer pool, not the piece.** Orbit, Magnet and Well were picked in 1 run of 16 each, yet all three read −29.4% with identical runs: any 5th patch in the pool shifts the Director's draws.
  - **Parity is therefore measured with the patch applied from the run start** (`bot_runs.gd --apply=<id>`, new): Orbit −7.8%, Magnet +2.6%, Well −5.3%, Elite +3.9%, Echo +12.0% (after halving the echo's damage; full damage was +15.3%), Hunter −15.8% (after 6 hits to stun instead of 8; 8 gave −17.4%). The Lancer, unlocked: +3.1%.
  - **The Hunter is left just outside ±15%.** Horde, its fork mate, applied from the start reads −70.3%, so the start-applied measure is harsh on pressure pieces.
  - **The bot now dodges and shoots a `threat` group** (the Hunter is in it, and is not an enemy). Before that the bot walked into it.
  - **Pacing:** invincible, everything unlocked: 181 s (16 of 16 runs).
  - **Divergence:** 16 chains as M31/M32 (rework chance 0.2): **16 distinct final sets of 16**. Every option is a final answer in 3 to 8 chains. 15 chains answered all 5 forks. The AI answered a fork 16 times; it did not fire in M31–M32. 35 reworks, 0 mismatches in the next run. Chain 1 replayed byte-identical. | **G12a (short, optional):** the owner plays one save to v0.2.x. Do the new options feel creative? Is a fork question clear? |
| M34 | Stage plumbing + arenas as data | Section 4's plumbing and arenas (no take yet): `StageDef`, sub-states, stage clear, carry, cross-stage hash test, `arena_0` + 2 arenas. A debug `--stages=gauntlet` bot flag runs a 3-stage run. **Numbers:** the same-seed 3-stage hash matches; the one-arena v0.0 run is unchanged (its M28 hash gate passes). **As built (bot, invincible, inert save):**
  - **One-arena run unchanged:** `run_hash.gd` seeds 1–4, recorded at m33 before any change and compared after M34: same run over 182 s, 4 of 4.
  - **3-stage hash:** `--stages=gauntlet`, seeds 1–4 played twice: same run over 351 s, 4 of 4. Each run reached stage 3/3 and won.
  - **In the suite:** `test_stages.gd` replays a compressed 3-stage bot run with prompts twice in one process, and the per-10-frame hashes match. | — |
| M35 | The Stages step | The `stages` fork, its 3 takes, stills, the genre step write, pacing, rework of the flavour. **Numbers:** invincible median 330–390 s with Stages shipped (each take); mortal time-to-death reported per take; v0.0 runs unchanged before the fork | — |
| M36 | Playtest build | Export, the playtest sheet updated (forks, Rework, stages), boot line with forks. | **G12 — owner playtest.** A fresh save, about 10 runs: do two answers to one question feel like different games? Is Rework found, and does it feel like freedom rather than a chore? Are the new options creative enough? Is the 6-min staged run better than the 3-min one? |

`tools/check.ps1` is green before every commit; each milestone gets a tag and a report, as before.

**Why this order:** forks and rework are what the owner asked for and they touch only the dev session, so they come first and are playable in a week of builds. Content comes before stages, so that divergence has something to diverge over. The stage plumbing comes before the Stages fork, which needs it, and v7's genre switch needs stage ends too.

**Cut order if needed (first to last):** Elite → Well → the AI answering a fork (cadence 0) → `fork_odd` (one 3-option fork fewer) → the Breakout take (Stages keeps 2 takes plus a third preset of Gauntlet). **Never cut:** forks, the shelf, Rework, REWORK-only with "Keep it as it is", the old-save mapping, stage plumbing, G12.

---

## 8. What v6 must answer
1. Do two saves feel like different games after ~10 runs?
2. Is changing your mind easy enough that a fork never feels like a trap?
3. Do the new options feel creative ("think outside the box"), not like stats?
4. Is a staged shooter run better than the 3-min arena, and which flavour do players pick?
5. Is the stage plumbing ready for v7's genre switch at a stage end?

## 9. Still open (each with a proposed default)
- **A session is one fork.** Alternative: 3 cards from 3 different forks, where picking one answers its fork and shelves its siblings unseen. Rejected for now: you would not see what you shelve.
- **Rework costs the whole session.** Alternatives: Rework is free (an extra action on any session), or limited (one per N sessions).
- **`rework_after_forks = 2`.** Alternative: from the first answered fork.
- **The AI answers a fork every 4 sessions with its agenda option.** Alternative: off (`ai_own_ship_every = 0`), or it only *proposes* ("I want Lancer. OK?").
- **Dependencies on forks, not answers** (1.1). Alternative: per-answer requires plus rework locks. Rejected: locks are exactly the frustration G11 named.
- **A maturity step cannot be reworked away**, only its flavour.
- **The starter smalls stay outside forks.** Alternative: a "starter kit" fork at v0.0.2.
- **No "Surprise me" / refuse** yet (ROADMAP 1.8 rule 3 is now served by the shelf).
- **v6 is Phase 5a only.** The second genre (ROADMAP open decision 9) and the switch are v7. Alternative: start turn-based as a Mockup genre fork in v6 (a 7th fork) to get its mockup early.
- **The new pieces' designs** (section 3) are this plan's proposals. The owner can swap any of them for their own ideas before M33.
- **Play threshold for Stages: 6 shooter runs.** Values come from G12 (ROADMAP open decision 7).

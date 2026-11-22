# Build Plan v5 — Foundations: versions, the dev session, v0.0

**For:** the builder agent
**Goal of this build:** the game's own version becomes the progression. A new save starts at **v0.0**: one short shooter run (~3 min). After every run, a **dev session** shows the playtest report, offers ~3 proposals, ships the one the player picks and shows the patch notes of the new version. The shooter becomes the first **genre** behind a thin shell.
**Engine:** Godot **4.7.x stable**, unchanged, GDScript, 2D simulation.
**Roadmap:** `ROADMAP.md` (v2) Phase 4. This plan is that phase.
**Supersedes:** `PLAN.v4.md` (on hold after M14). **Every v2 and v3 contract, and v4 sections 1.1–1.3 (the AI layer, kept parked), stay in force** unless this document changes them. v4 sections 1.4–9 are not built; ROADMAP section 5 says which pieces come back later.

Milestones continue from **M25**: M15–M24 were v4's planned numbers and ROADMAP section 5 still refers to them.

---

## 0. Read this first

| | M14 run | v5 run (v0.0) |
|---|---|---|
| Length | ~10 min game time | ~3 min (2.1) |
| Genres | shooter + 2 big patches (B1, B2) swapped in at BIG prompts | the shooter, picked at run start (the only Playable genre) |
| Small prompts | 4 | 3 |
| BIG prompts | 2 | none (removed from play) |
| Rollbacks | 1 charge, on an AI stage patch | none (parked) |
| Between runs | report → "New build" | report → dev session → patch notes → next run |
| Version | `build_number` in the run ("v1.0 shipped") | the saved game version, v0.0.0 → v0.1.x; the in-run build stays as flavour |
| On disk | telemetry | telemetry + `save.json` (version, genres, shipped changes, look, taste, sessions) |
| Content at start | everything | 4 smalls, 2 enemy types, look tier 0; the rest ships through dev sessions |

**Principles that hold:** a patch is rules + components + listeners and touches only its folder. Every patch is removable in classes A and B. The reversibility invariant (v2 2.5, v3 1.2, v4 1.2) is unchanged and its tests stay. **New:** a patch's behaviour lives in a **take** per genre (1.2); the shell never branches on genre (1.1).

### Roadmap open decisions taken as defaults for v5
The owner said "let's start the new roadmap" (2026-11-21). These ROADMAP section 6 defaults are built as proposed and stay flagged (section 9):
- **(1) Bump rule:** a dev-session pick is a patch step; a look tier or a maturity step is a minor step.
- **(5) The AI ships a change of its own** now and then: `Tuning.ai_own_ship_every = 4` sessions (cut first if short of time, section 7).
- **(11) Report ratings** stay, as a taste input beside the pick.
- **(12) Nothing carries between runs inside the build:** each run starts with an empty stack, as today.
- **(13) A real playtest closes Phase 4:** G11 (section 7).

### What v5 amends
| Rule | Was | v5 |
|---|---|---|
| v3 1.2, v3 4 | big slot, BIG prompts, `swap_big` from play | no BIG prompt and no player path to the slot; it stays an internal seam (1.3) until Phase 5 |
| v3 section 2 | B1 `motion_time` is a big patch; its logic sits in `RunState` | a small patch; its logic moves into its take (1.4) |
| v4 1.1 | `gravity_on`, `gravity_reversed` are mediums | **parked** (1.3); they come back as the platformer's base rules and medium in Phase 6 |
| v4 1.3, 9.1 | rollbacks on AI patches, 1 charge, the M14 scaffold | parked: the scaffold is deleted, charges are 0, the history's rollback buttons are gone |
| v2 2.4 | a mutation script holds its behaviour | the behaviour lives in `mutations/<id>/<genre>.gd`; the `.tres` holds the card (1.2) |
| v2 8 | one run → report → "New build" | report → dev session → patch notes → next run (4) |
| v2 0, v4 1.7 | no saves (v4's `Progress` never built) | `SaveGame` (1.5) with v4 1.7's mechanics and a new schema |
| v3 taste | session only (`Taste.carried`) | saved on disk when the save is live |
| v2 3 | one arena owned by `main.gd` | the shooter genre owns its arena, spawner, camera and run pacing (1.1) |

### Out of scope (do not build)
- A second genre, the stage-end switch, stages (Phase 5). The turn-based code stays as it is, parked.
- Platformer, mediums, bosses, look tiers 2+ (Phase 6). Card crawler and 1.0 (Phase 7).
- The 1.0 rule, maturity steps past Playable, play thresholds (no genre steps up in v5; the save records play time so Phase 5 can read it).
- Live AI patches and rollbacks in any form (parked, ROADMAP 1.7).
- Playable mockup tastes (stills only, 4.3). Generated images: every mockup still is captured from the game (`tools/mockup_capture.gd`) and committed.
- **`WorldRules` stays one bag** and requires/conflicts stay on the card (ROADMAP 3's split into a shared part plus per-genre rule bags comes with the second genre, Phase 5). **Mediums get their `genre` field** when mediums come back (Phase 6); v4 1.1's medium tier stays only for the parked AI layer.
- Saving settings; RTS; final art and audio.

---

## 1. Contracts

### 1.1 The shell and the genre interface
- **`GenreDef`** (`core/genre_def.gd`, resource): `id`, `title`, `blurb`, `pace_unit` (`&"seconds"`, later `&"turns"`, `&"rooms"`), `genre_script: Script` (a `Genre` subclass), `playable`. One per genre in `genres/<id>/genre.tres`. **`GenreDB`** autoload lists them like `MutationDB` (sorted by id, `list_directory`, `problems()`); it loads before `RunState` and `MutationDB`, which read it, and `MutationDB` checks that no patch id is a genre id.
- **`Genre`** (`core/genre.gd`, `Node`): the base a genre extends.
  - `func build(shell: Main) -> void`: adds the genre's own nodes (arena, spawner, camera, overlays) under itself and places the player.
  - `func begin_run() -> void`: starts its run.
  - Prompt pacing stays the Director's rule (kills and gaps in game seconds) in v5: it suits the only genre, and moving it would break M26's same-run gate. Phase 5 hands prompt points to the genres (turn-based paces in turns). The Director builds offers and applies patches.
  - It tells the shell exactly two things: `signal stage_ended(index: int)` and `signal run_ended(outcome: StringName)` (ROADMAP 1.3). The shell never asks a genre how it runs.
- **`TopdownGenre`** (`genres/topdown/topdown_genre.gd`): today's arena, spawner, `TurnClock`, `TurnOverlay`, `TimeTint`, camera, and the run pacing of `RunLoop` (play → release candidate → over). It fires `run_ended`; it has no stages yet, so it never fires `stage_ended`.
- **Genre ids never collide with content ids:** the first genre is `topdown` (title "Top-down shooter"), because `shooter` is already an enemy archetype.
- **The shell (`main.gd`)** keeps only what all genres share: `RunState` reset, the player-facing UI (prompt panel, HUD frame, history, report, dev session, patch notes), `Transition`, `Sound`, `Feedback`, the Director, telemetry. `Main` keeps **read-only forwarding properties** (`arena`, `spawner`, `camera`, `turn_clock`, `run_loop`, `player`) to the active genre, so tests and tools keep working unchanged.
- **`RunState.genre: StringName`** is set by `reset(seed, genre)` (default: the first Playable genre in `GenreDB`, `&"topdown"`). It is separate from the patch layers. Nothing in v5 changes it during a run.
- **Rule: the shell never branches on a genre id.** A grep test (like v2's folder isolation) fails if a genre id appears in `main.gd`, `ui/`, `director/`, `devsession/` or `core/` outside `GenreDB`.

### 1.2 Takes: one patch, one behaviour per genre
- **`PatchTake`** (`core/patch_take.gd`, `RefCounted`): the same hooks a mutation has today: `apply_rules(rules)`, `on_entity_spawned(entity)`, `enable()`, `disable()`, `_listen(sig, method)`, `state()`. It gets `patch: Mutation` (its card) when built. `state()` is the card's per-run state, so it resets when the patch does (and on a genre switch, Phase 5).
- **The card stays the `.tres`** (`mutations/<id>/<id>.tres`, plain `Mutation`, no script of its own): id, title, lines, tags, requires, conflicts, weight, `starter`.
- **Takes are files:** `mutations/<id>/<genre>.gd` extends `PatchTake`. Tunable numbers are `@export var`s on the take. `MutationDB` loads every take at boot and builds one instance per (patch, genre).
- **`Mutation`'s hooks forward** to `take_for(RunState.genre)`. A patch with no take for the active genre does nothing (and can never be offered there, below). The forwarding is the only change to `RunState`'s apply/revert/strip paths, so the invariant tests hold as they are.
- **Legacy scripts:** a mutation whose `.tres` still points at its own script (the parked `turn_mode`, `gravity_on`, `gravity_reversed`) keeps working: its overrides win over the forwarding. `MutationDB.problems()` allows that only with `parked = true`.
- **Offer rule:** `get_offer` only offers a patch that has a take for `RunState.genre` and is in the pool (1.6). `MutationDB.problems()` rejects an unparked patch with no take for some Playable genre (the v5 content rule: ROADMAP 1.4).
- **Folder isolation** (the v2 grep test) still holds: a mutation id appears only in its own folder, plus `devsession/changes/*.tres` `unlocks` fields (1.6).
- **Bot `--set=<id>.<var>=<value>`** sets the var on that patch's take for the active genre.

### 1.3 Parking
- `Mutation.parked := false`. A parked patch is never offered, never in the pool, never shipped. `summary_line` marks it `(PARKED)`. v5 parks `turn_mode`, `gravity_on`, `gravity_reversed`.
- **The big slot** (`RunState.big`, `swap_big`, `swap_drops`, `ai_swap_drops`) stays as an **internal seam**: only tests, the F2 console and the bot's `--big=` flag reach it, so turn-based and its ~1,400 test lines keep running until Phase 5 ports turn-based into the genre interface and deletes the slot. No BIG prompt, no big offer, no "Keep" card, no "This one stays" text in play.
- **Deleted:** `Tuning.big_prompt_after`, `big_offer_size`, `Director.open_big_prompt`, `get_big_offer`, `_on_big_choice`, `big_index`, `big_prompts_per_run`, `big_prompt_due`, the M14 scaffold (`ai_scaffold_at_prompt`, `scaffold_due`, `scaffold_patch`, `add_scaffold`).
- **The AI layer** (`RunState.ai`, `add_ai`, `remove_ai`, `expire_ai`) and its invariant tests stay. Nothing in play adds to it. `rollback_charges_start = 0`; `Director.can_revert` stays for tests. The history hides the AI section and its buttons when the layer is empty, and the HUD drops "Rollbacks: N".

### 1.4 B1 becomes a small patch
- `motion_time`: `is_big = false`, `genre_label` cleared, take `mutations/motion_time/topdown.gd`. Conflicts with nothing in the v5 pool.
- **Its logic leaves `RunState`:** `_motion`, `_pulse_left`, `_step_motion`, `motion_target`, `_on_projectile_fired` and `_on_player_dashed` move into the take (its `state()`). `RunState` stays the **only writer of `Engine.time_scale`** through a new seam: `RunState.set_time_factor(owner: StringName, f: float)`. The scale is `rules.time_scale × Π factors`, floored at `MIN_TIME_SCALE`. `_strip(m)` and `reset()` clear that patch's factor, so a reverted B1 leaves time at 1 the same tick.
- The take steps on real time as today (`delta / Engine.time_scale`), in a `physics_frame` listener connected through `_listen`. `rules.time_follows_motion` and `idle_time_scale` stay as rules (a test reads them).
- `RunState.motion_factor()` stays as a read-only helper (the product of factors) for the HUD and `TimeTint`.

### 1.5 The save: `SaveGame`
`core/save_game.gd`, `class_name SaveGame`, static state like `Telemetry`. **v4 1.7's mechanics, unchanged:** `save_path` (default `user://save/save.json`), **inert by default** (`persist = false`, `unlock_all = true`; only the start screen and `bot_runs.gd --save=` turn them on), atomic write (`.tmp` then rename), missing file → new-save state, missing key → that key's default, corrupt → `save.bad.json` + `push_warning` + new-save state, higher schema → read-only, never overwritten, "Reset" disabled, unknown ids dropped on load.

**Schema 1:**
```json
{"schema": 1,
 "version": [0, 1, 2],
 "runs": 4, "wins": 1,
 "genres": {"topdown": {"step": "playable", "runs": 4, "play_time": 702.5}},
 "shipped": ["look_1", "patch_auto_attack", "enemy_tank"],
 "look": {"tier": 1, "take": "punchy"},
 "taste": {"by_id": {}, "by_tag": {}},
 "sessions": [{"after_run": 1, "version": "0.1.0", "shape": "mockup", "cards": ["look_1:punchy", "look_1:clean", "look_1:arcade"], "pick": "look_1:punchy", "agenda": "", "ai_ship": ""}],
 "pending_session": false}
```
- **Inert means "everything shipped":** with `unlock_all`, the pool is every unparked patch, every enemy spawns, and the look is tier 1 take `punchy` (today's feel). So GUT, `main.tscn` booted directly and the export's `--autostart` play as today. Tests of v0.0 gating turn `unlock_all` off.
- **Play time is time spent playing** (the owner: genres grow from "time spent playing them"): `RunState.real_time()` of the run, unscaled, so B1's slow motion and hit stop do not shrink it.
- **When it writes:** at run end (runs, wins, genre runs and play time, taste) with `pending_session = true`, then again when the dev session ships (shipped, version, look, sessions, `pending_session = false`). If the game closes between the two, the next start screen opens the pending dev session first ("The last build is still on my desk.").
- **Taste:** `Taste.to_dict()` and a new `Taste.from_dict()`. When the save is live it replaces `Taste.carried`; inert games keep the session carry as today.
- **Start screen:** "v0.1.2 · 4 runs" under the title, "Reset save" (two clicks, disabled on a higher-schema file), and Start (it opens the genre picker only when more than one genre is listed; in v5 it starts the shooter). Opening the screen only reads the save (a snapshot: no write, no rename); Start and Reset make it live (v4 1.7: "when it starts a game"). `--autostart`, `--inert-save` (check.ps1's boot) and tools that clear `StartScreen.save_live` leave the save alone.
- **Isolation gate:** `check.ps1` snapshots the real save folder (names, sizes, mtimes) before its first step and fails if anything changed by the end; `-BotRuns` adds a 2-run chain through a scratch save.

### 1.6 Versions, changes and the pool
- **`GameVersion`** (`core/game_version.gd`): `major.minor.patch` from the save. `bump(kind)`: `&"patch"` → patch + 1; `&"minor"` → minor + 1, patch 0. `label()` → `"v0.1.2"`. A new save is `v0.0.0`.
- **In-run label:** "v0.1.2 · build 5" (`build_number` stays as flavour). The report title no longer says "v1.0 shipped"; it says "Playtest of v0.1.2".
- **`Change`** (`devsession/change.gd`, resource), one `.tres` per change in `devsession/changes/`: `id`, `title`, `pitch` (the AI's line), `kind` (`&"patch"`, `&"enemy"`, `&"look"`), `genre` (`&""` = shared), `bump` (`&"patch"`/`&"minor"`), `requires: Array[StringName]` (change ids), `unlocks: Array[StringName]` (mutation ids or enemy archetypes), `tags` (taste), `weight`, `due_after_run := 0` (offered first once `runs >= due_after_run`), and for a mockup: `takes: Array[MockupTake]`.
- **`MockupTake`** (resource): `id`, `title`, `line`, `image: Texture2D`, `preset: Resource` (for a look, a `LookPreset`, 1.7).
- **`ChangeDB`** autoload (after `MutationDB`; its data layer, `Change` and `MockupTake`, lands with M27 because `Unlocks` and the save's unknown-id rule read it; content comes with M29): lists, sorts, validates (`problems()`: ids unique, `requires` exist, `unlocks` name an existing unparked mutation or a spawner archetype, a mockup has exactly 3 takes with an image each, no cycle in `requires`).
- **What is unlocked** (`Unlocks`, static, reads `SaveGame`): `pool()` = `starter` mutations + those a shipped change unlocks (minus parked); `enemies()` = `Tuning.starter_enemies` + shipped; `look()` = the save's tier and take (tier 0 when nothing shipped). With `unlock_all`: everything, look tier 1 `punchy`.
- **The Director** draws offers from `Unlocks.pool()` (1.2's take filter on top). The spawner's `pick_type()` skips archetypes not in `Unlocks.enemies()` and renormalises; a locked type's chance goes to chasers.

### 1.7 The look
- **`Look`** (`systems/look.gd`, static) holds the active `LookPreset` (`systems/looks/*.tres`): `shake_scale`, `particle_scale`, `hit_stop` (real seconds), `muzzle_flash`, `kill_pop_scale`, `trail`, `screen_flash`, `palette: Gradient` or 4 colours. Presentation only: no gameplay value reads it.
- `Feedback`, `CameraRig.shake`, the projectile and the player's shooter read `Look.preset`. Hit stop goes through `RunState.set_time_factor(&"hit_stop", 0.0)` for `hit_stop` real seconds (the one time-scale writer stays `RunState`).
- **Tier 0 (`look_0.tres`)** is the v0.0 look: readability only (2.2), `shake_scale = 0`, `particle_scale = 0.3`, no hit stop, no flash, no trail.
- **Tier 1** has 3 takes (`look_1_punchy`, `look_1_clean`, `look_1_arcade`), each a preset of the same code (ROADMAP 1.5 scope rule). `punchy` is M14's feel plus hit stop. **The 3 takes share tier 0's palette:** tier 1 is juice (ROADMAP 1.6); palettes and shaders are tier 2 (Phase 6). The 3 are tuned to look clearly different in a still through juice alone (shake blur, particle density, flashes, trails, kill pops); hit stop, which a still cannot show, is named in the take's line.

---

## 2. The v0.0 run

### 2.1 Pacing (starting targets, game time)
- The shooter's run: **3 small prompts**, then a **45 s release-candidate wave**, then the report. Target **~3 min** (170–200 s median, invincible bot).
- `Tuning`: `first_prompt_min_gap = 35`, `prompt_min_gap = 40`, `prompt_max_gap = 55`, `first_prompt_kills = 10`, `prompt_kills_step = 6`, `prompts_per_run = 3`, `rc_duration = 45`, `spawn_ramp_time = 120`. Retuned from bot sweeps at M28. **M28:** the kill gates are met long before the gaps (the bot kills ~2/s), so the run is the sum of the gaps: 35 + 40 + 40 + 45 = 160 s. The gaps are now `first_prompt_min_gap = 40`, `prompt_min_gap = 48` and `prompt_max_gap = 60`, which gives 181 s. The kill numbers stay as listed.
- **The prompt is announced visually** (ROADMAP 1.4, part of the core gimmick): once the kill gate is met, a HUD banner pulses "Next patch incoming" until the prompt opens (the remaining time gap, at most `prompt_min_gap`). It shows the existing gates, adds no rule, and never sits waiting on kills.
- Picking still heals 1 HP. HP 5, as today.

### 2.2 Readability (in every look, tier 0 included)
Fun before meta (ROADMAP 1.8 rule 1). Bots cannot judge it; G11 does.
- **Telegraphs:** an enemy shooter flashes and grows for `Tuning.shooter_windup = 0.35` s before each shot (the shot is fired at the end of the windup, so the interval is unchanged); a chaser or tank within `Tuning.contact_warn_range = 1.5` tiles of the player shows a red rim that brightens as it closes in, so contact hits are read before they land (hops need gravity, which is parked). The bomber's 0.6 s windup (3) is the third telegraph. Under the parked B2 the grid telegraphs stay as they are.
- **Hit confirmation:** the enemy flashes white (exists) and its body shows its HP lost (a short white bar under it, only once damaged, gone at full HP).
- **Kill confirmation:** a short ring pop at the kill position and the `kill` sound in every look (`kill_pop_scale` sizes it); in tier 0 it is the only kill effect besides a small puff.
- **Player hit:** a red screen-edge vignette for 0.3 s and the invulnerability blink (exists); no shake in tier 0.
- **Camera lookahead:** the camera leads toward the aim direction by `Tuning.camera_lookahead = 0.12` of the view, smoothed (`camera_lookahead_lerp = 4.0`). The arena bounds still clamp it.
- **As built (M28):**
  - **Shooter windup:** the cooldown is `shooter_fire_interval - shooter_windup` and the windup runs after it, so shots stay 1.8 s apart. A started telegraph always ends in its shot, aimed where the player is at that moment.
  - **Rim:** the rim range is measured past the walker's contact reach, not from its centre (1.5 tiles from the centre would sit almost inside the 40 px reach). It rises from faint to full at contact.
  - **Readability drawing:** the HP bar, telegraph and rim are drawn by `RectVisual`, so a sprite swap must keep them. The kill pop skips the effect cap.
  - **Hit stop:** the full `hit_stop` applies on a player hit. A kill gets 0.35 of it. A stop already running is not extended. There is none on the turn grid or once the player is dead (the report is never slowed). It is timed in unscaled seconds. TimeTint and Sound's pitch read `RunState.felt_time_scale()`, which leaves hit stop out, so a stop never looks or sounds like B1.
  - **Spawner:** its hidden margin grows by the largest possible camera lead (`1 + 2 * camera_lookahead` of the half view), so a lead never reveals a fresh spawn. Spawning stays independent of camera state.
  - **punchy:** for now this is the M14 feel plus hit stop (0.08 s, kill pop 1.3). The muzzle flash, trail and screen flash code paths exist, but no take turns them on until M30 tunes the three takes.
  - **HUD:** it runs while paused, so the banner hides as the prompt opens.

### 2.3 Start content (a new save)
- **Smalls in the pool (`starter = true`):** `bouncing_projectiles`, `explode_on_hit`, `enemies_split`, `jump_button`. **Shipped later:** `auto_attack`, `horde_mode`, `motion_time`. That is 7 smalls in all (ROADMAP Phase 4 content).
- **Enemies:** chaser and shooter (`Tuning.starter_enemies`). Shipped later: tank, and the new **bomber** (3).
- **Look:** tier 0.
- With 4 starter smalls and 3 prompts, prompt 3 shows 2 cards. Accepted (flagged, 9).

---

## 3. Content: the first chain of changes

| Change id | Kind | Shape | Unlocks | Bump | Notes |
|---|---|---|---|---|---|
| `look_1` | look | mockup (3 takes) | look tier 1 | minor | `due_after_run = 1`: the first dev session is this mockup, so the core gimmick shows at once |
| `patch_auto_attack` | patch | change | `auto_attack` | patch | |
| `patch_horde_mode` | patch | change | `horde_mode` | patch | requires `enemy_tank` (horde needs variety to read) |
| `patch_motion_time` | patch | change | `motion_time` | patch | the AI's "experimental" pitch |
| `enemy_tank` | enemy | change | `tank` | patch | |
| `enemy_bomber` | enemy | change | `bomber` | patch | requires `enemy_tank` |

- **Bomber** (`entities/enemy_bomber.tscn`, reuses `enemy_walker.gd` with archetype `bomber`): walks toward the player, stops at 2 tiles, telegraphs 0.6 s (grows, flashes), explodes (`Explosion.blast`, radius 1.6 tiles, 1 damage, hurts enemies too), dies. HP 2. Spawn chance `spawn_bomber_chance = 0.12` after 40 s. Takes of the existing smalls apply as for any walker (split halves explode too: `enemies_split` already copies the archetype). The parked B2 gets no bomber role (bombers are filtered from the spawner when `rules.turn_based`).
- After the 6 changes ship (v0.1.5), a dev session has nothing to propose: it says "I'm working on something bigger." and goes straight to the next run without a bump. Phase 5 adds content.

---

## 4. The dev session

### 4.1 Flow
1. **Report** (the existing screen, both outcomes). Its main button becomes **"Dev session"** when the save is live (inert: "New build", as today). Ratings stay optional (taste).
2. **Dev session screen** (`ui/dev_session.gd`): the AI's opening line (references the run: outcome, a patch picked, the hit kind that hurt most), then the cards, then the pick.
3. **Patch notes screen** (`ui/patch_notes.gd`): "Version 0.1.0", the change's title and pitch as a bullet, the unlocked content listed ("New patch in the pool: Auto-aim"), an AI-own ship if any (4.4), and "Play v0.1.0".
4. The next run starts (same scene reload path as "New build").

### 4.2 Which cards
- **Available:** not shipped, every `requires` shipped, its genre (if any) is at least Playable.
- **Shape:** if an available change has `due_after_run <= runs` and takes, the session is a **mockup session** on that change (its 3 takes as cards). Otherwise a **3-changes session**: up to `Tuning.session_cards = 3` cards, taste-weighted by tags (`Taste.weight_mult` over the change's tags), with **one agenda card** (the least-liked by tag, voiced as the AI's own wish) whenever at least `Tuning.agenda_min_available = 2` cards are shown (ROADMAP 1.8 rule 4: push-back is a tuning value, never zero over a run of sessions). Seeded from `run_seed` so a same-seed chain gives the same cards.
- **Fewer than 2 available:** no single forced card. The AI ships the last change itself, named in the patch notes as its own ("Last one on my list. I shipped it."), with its bump; the player goes straight to the patch notes.
- **Pick:** ships the change (or the take), bumps the version, logs the session, feeds taste (`Taste.on_offer` with the change's tags; picking a look take nudges a `look:<take>` id). Unpicked mockup takes are kept in the session log; **they do not come back in v5**, and where they return (ROADMAP 1.5) is open (9).
- **Refusing is not an option in v5:** the player must pick one. A refused proposal "comes back later" (rule 3) holds for changes, because the unpicked ones stay available.

### 4.3 Mockup cards
- Each take card shows its still (`MockupTake.image`, 480×270, letterboxed), its title and one line. Hovering or focusing a card enlarges the still.
- **Stills are captured from the game:** `tools/mockup_capture.gd -- <change_id>` runs a seeded, scripted 4-second scene (the player strafes and fires at a fixed group of chasers, one dies, one hits the player) under each take's preset and saves `devsession/mockups/<change>_<take>.png`. Committed. Rerun when a preset changes.

### 4.4 The AI ships its own change (default for open decision 5)
Every `Tuning.ai_own_ship_every = 4` sessions (counted in the save), after the player's pick, the AI also ships one available non-mockup change of its own choice (least liked by tag, the agenda rule), named in the patch notes: "I also shipped something you didn't ask for: Tank." It bumps once more. 0 turns it off. The cadence, the target and the extra bump are this plan's own choices (ROADMAP open decision 5 is still "to confirm"), listed in 9.

### 4.5 Telemetry (schema 2)
Today's records are `schema: 1` (v4's schema 2 was never built). v5's run records become `schema: 2` and add `genre`, `game_version` (the saved version, "v0.1.2"), `look` {tier, take}, `pool_size`, `enemies`. `version` keeps its meaning (the in-run build label, "v0.5"). A new line type `session` {version_before, version_after, shape, cards, pick, agenda, ai_ship, run_index}. Every schema 1 key is kept. The big-slot keys (`final_big`, `big_offers`, `big_swaps`) and the genre-split keys (`genre_seconds`, `genre_hits`, `genre_hits_by_kind`) stay keyed by big patch id until Phase 5 moves turn-based out of the slot (ROADMAP 3: "genre keys change from big patch id to genre"); `[botrun]` adds `genre=`.

### 4.6 Bot
- The bot answers the dev session with a seeded random card and presses "Play".
- `--save=<path> --keep-save` chains runs through a save file (inert, read-only snapshot otherwise, as v4 1.7). `--fresh` starts from a new save (v0.0) instead of `unlock_all`.
- `[botrun]` adds `version=`, `look=`, `pool=`, `enemies=`.

---

### 4.7 As built (M29)
- **Logic in `DevSession`** (`devsession/dev_session.gd`): `plan(run_seed, context)` picks the shape and deals the cards; `pick(i)` / `finish()` ship, feed taste, log and write. `ui/dev_session.gd`, `ui/patch_notes.gd` and `ui/dev_session_flow.gd` only show it, so the game scene (after the report, F9) and the start screen (a pending session) share one flow.
- **The deal:** due changes first, then the agenda card (least liked by tag, taken from the whole pool before the taste-weighted picks, so it is really what the player likes least), then taste-weighted picks; the agenda card is shown last. A mockup is only ever shown as its takes, never as a plain card. The generator is seeded from the run seed, the session number and the run count.
- **"Fewer than 2 available"** can happen before the end of the chain: `enemy_tank` gates `patch_horde_mode` and `enemy_bomber`, so a chain that leaves the tank for last reaches a session where only the tank is ready. The AI ships it (its bump, no card) and the notes say "Only one change was ready, so I shipped it myself. More are coming."; "Last one on my list. I shipped it." is kept for the real last change. On that path the AI's own ship at session 4 does not happen (it follows a player's pick), and all 6 are out by session 6 instead of 5. Bot seeds 1–7 take that path; 11–17 and 21–27 take the planned one (gate numbers in the M29 report).
- **Nothing left:** the session screen shows "I'm working on something bigger." and "Play"; the session is still logged (shape `none`, no bump) and `pending_session` is cleared.
- **Taste:** change cards move their tags; take cards move only their `look:<take>` id (all three share the change's tags).
- **Pending session:** opening the start screen still only reads the save. It shows "The last build is still on my desk." and Start becomes "Dev session"; pressing it makes the save live and opens the session, whose "Play" starts the game.
- **The bomber** (3) is built in M29, ahead of M30: `enemy_bomber` must unlock a real archetype (`ChangeDB.problems()`). It has no contact damage and no rim. It lights its fuse at **1.3 tiles**, not 2, with a clear line: section 3's 2 tiles sits outside its own 1.6-tile blast (plus the 12 px body margin), so a player who stood still was never hit. 0.6 s is still plenty of time to step out. Its blast hurts the player and enemies, but it is enemy damage: neither its own death nor its victims count as the player's kills or pace the prompts, and they do not show in the report's damage by source. M30 keeps its sweep and parity numbers.
- **Look takes:** `look_1_clean` and `look_1_arcade` are placeholder presets (numbers only, no flash/trail/muzzle) and the 3 stills are gradient placeholders; M30 tunes the takes and captures the stills.

### 4.8 The broken first builds (M29b, owner idea 2026-11-22)
The owner: "first couple runs could be really quick and miss basic control (zqsd/wasd not working, then no ennemies / plateform)". Asked whether to add it as a step before M30, the owner said yes. The exact basics and their order are this plan's default (9), not the owner's.
- **The basics** (`Unlocks.BASICS`): `movement`, `enemies`, `level`. A new save has none; inert games have all. `Unlocks.has_basic()` / `missing_basics()`.
- **v0.0.0:** the player cannot move or dash (aim and shoot still work), nothing spawns, and the arena is its border only (`Arena.strip_layout()`). **v0.0.1:** movement works; still no enemies and no level. **v0.0.2:** today's v0.0 run (2.1–2.3).
- **A build missing a basic plays a smoke test:** no prompts (the Director is off), `Tuning.smoke_test_duration = 20` s of game time, then "SMOKE TEST OF v0.0.0 - BUILD SURVIVED". A HUD countdown runs, and the AI names what is missing at the start and on the report. The run record adds `smoke_test` and `missing_basics`.
- **Two basic changes** (`kind = &"basic"`): `basic_movement` ("Movement") and `basic_world` ("Enemies and a level", requires `basic_movement`). Each is a patch step. While a basic is unshipped, **only basics are available**. The session shape is `basic`: the AI ships the next one itself, with no card, and the flow goes straight to the patch notes (like `ai_last`).
- **Chain:** v0.0.0 → (smoke) → v0.0.1 → (smoke) → v0.0.2 → look mockup v0.1.0 → the 6 changes of section 3 → v0.1.5. The first two sessions count toward the AI's own-ship cadence (every 4th session).
- **Bot:** `--ship=<id>,<id>` ships changes into the save before the first run. `--fresh --ship=basic_movement,basic_world` plays the v0.0.2 run, for pacing sweeps.

### 4.9 As built (M30)
- **The 3 takes** (`systems/looks/look_1_*.tres`) share tier 0's palette:

  | take | shake | particles | hit stop | kill pop | muzzle flash | trail | screen flash |
  |---|---|---|---|---|---|---|---|
  | punchy | 1.0 | 1.0 | 0.08 | 1.3 | yes | no | yes |
  | clean | 0.25 | 0.5 | 0.03 | 0.9 | no | thin (`trail_scale` 0.6) | no |
  | arcade | 1.6 | 2.0 | 0.1 | 1.9 | yes | long (1.8) | yes |

  `LookPreset.trail_scale` is new (the trail's length and width), so clean's and arcade's tracers read differently in a still. Punchy is still the inert default, so tests and an inert boot now show its muzzle and screen flashes.
- **`tools/mockup_capture.gd`** needs a real window. It plays the same seeded fight (seed 7, `explode_on_hit`, invincible bot, HUD hidden) once per take and keeps the busiest frame in an 8 s window. "Busiest" means effects near the player, with kill pops weighted 3; frames where the player blinks are skipped. Each still is cropped 2× around the player at 480×270 and saved to `devsession/stills/look_1_<take>.png`, which `look_1.tres` uses in place of the gradient placeholders. Same code, same stills.
- **Tank retune:** `spawn_tank_chance` goes from 0.15 to **0.08**. With every change shipped, the mortal median was 79.9 s (−27% from M28's 108.9 s). Split by enemy: tank only gave −25%, bomber only −10%, and hit kinds didn't change (no explosion hits; the bot takes the same projectile hits, just sooner). Tanks soak fire, kills per run fall from 76 to 52, and shooters live longer. Tank HP 8 barely helped (−26%); spawn chance did (0.08: +1%). Tank HP stays at 12.
- **Boot lines:** the game prints `[boot] Patch Notes M30, game v0.1.2, genre topdown (playable: topdown), Godot 4.7.0`, and the start screen prints `..., start screen, game v0.0.0, real save|inert save`. `tools/export.ps1` requires both, checks that the smoke boot is on the inert save, and copies `PLAYTEST.md` next to the exe.
- **`PLAYTEST.md`**, the G11 sheet: how to reset the save, the controls (keys bind by physical position, so ZQSD works on AZERTY), what the observer notes, the 6 questions asked after the session (none of them spoil the broken builds), and which files to send back.

## 5. Debug
- F2 console lists parked patches under "PARKED" (apply through the old paths, as today).
- New: **F9** opens the dev session at once (inert: on a temporary in-memory save); **Shift+F9** ships the next available change without the screen. F1 shows version, look, pool size and enemies.

---

## 6. Tests (additions)
- **Shell:** the genre-id grep (1.1); `Main`'s forwarders return the genre's nodes; `run_ended` from the genre reaches the report; a test genre fixture (a `Genre` with no arena that ends the run after 2 s) runs through the shell to the report, proving run start and run end need nothing shooter-specific.
- **Takes:** forwarding calls the active genre's take; a patch with no take for the genre is never offered and its hooks are no-ops; `--set=<id>.<var>` reaches the take; `state()` is per patch and cleared on revert; a legacy script without `parked` is rejected by `problems()`. The invariant suite (≥250 sequences) passes unchanged with takes.
- **Same run as M14:** an invincible bot run on seeds 1–4 with `unlock_all` and the M14 pacing (`--set` the old values) gives the same per-second hash of player position and enemy set before and after the genre port (M26 gate).
- **B1 as a small:** applying `motion_time` slows time when idle; reverting it puts `Engine.time_scale` back to `rules.time_scale` in the same tick; the hit-stop factor and B1 multiply; `RunState` has no motion fields left (grep).
- **Parking:** no parked patch in any offer over 200 seeded prompts; no BIG prompt opens in a full bot run; the history shows no rollback button with an empty AI layer.
- **Save:** v4 11's save list, adapted: round-trip, missing, missing key, corrupt (`.bad` + warning, no `ERROR:`), higher schema (read-only, reset disabled), unknown ids dropped, inert by default, the real save file's existence and mtime unchanged by the suite, `pending_session` reopens the dev session.
- **Version:** bump rules; label; a new save is v0.0.0; the report title.
- **Unlocks:** a new save's pool is the 4 starters; the spawner never spawns a locked archetype over 2,000 picks and renormalises; `unlock_all` gives everything.
- **Dev session:** first session is the `look_1` mockup; a session showing ≥ 2 cards has exactly 1 agenda card; a chained fresh sweep shows at least one agenda card; with 1 change left the AI ships it and no card is shown; `requires` respected; same seed + same save → same cards; picking ships, bumps, logs, writes taste; nothing available → no bump, straight to the next run; the AI's own ship every 4th session; `ChangeDB.problems()` empty.
- **Look:** tier 0 has no shake and no hit stop; each tier 1 take differs from the others in at least 3 juice fields and has tier 0's palette; nothing outside presentation reads `Look` (grep for `Look.` outside `systems/`, `ui/`, `entities/`' visuals).
- **Readability:** the shooter's shot comes `shooter_windup` after its telegraph starts and its interval is unchanged; a chaser's rim is off beyond `contact_warn_range` and on inside it; the kill pop fires on every kill in every look; the camera lookahead stays inside bounds.
- **Bomber:** telegraph then blast; hurts enemies and the player; never spawned under `turn_based`; `enemies_split` halves of a bomber are bombers.
- **Updated:** `test_big_prompts` (BIG prompts gone: keep the slot tests that go through `swap_big` directly, delete the prompt-flow ones), `test_director` (no scaffold, charges 0), `test_motion_time` (small patch, factor seam), `test_smoke_matrix` (pinned counts recomputed: 7 smalls, parked excluded), `test_playtest_build` (boot line with version, genres and PARKED), `test_run_loop` (3 prompts, 45 s wave).

---

## 7. Milestones

| # | Milestone | Builder gate | Owner gate |
|---|---|---|---|
| M25 | Park the v4 run | 1.3 and 1.4: BIG prompts and big offers deleted, scaffold deleted, charges 0, history AI section hidden when empty, HUD without rollbacks; `parked` flag on `turn_mode`, `gravity_on`, `gravity_reversed`; `motion_time` a small with its logic in the patch and `RunState.set_time_factor`; smoke matrix re-pinned; check.ps1's rollback gate replaced by a parked-genre gate (`--big=turn_mode` 1 invincible run reaches its report); bot drops the rollback policy. **Numbers:** invincible 16-seed sweep, every run reaches its report, 0 BIG prompts, 0 rollbacks | — |
| M26 | Genre interface + takes | 1.1 and 1.2: `GenreDef`, `GenreDB`, `Genre`, `TopdownGenre` owning arena, spawner, camera, turn clock, overlays and run pacing; `Main` thin with forwarders; `RunState.genre`; `PatchTake`, forwarding, takes for the 7 smalls (`mutations/<id>/topdown.gd`); legacy scripts only when parked; genre-id grep; test genre fixture. **Numbers:** the same-run hash test passes on seeds 1–4; suite duration within +15% of M25 | — |
| M27 | Save + version | 1.5 and 1.6 (`GameVersion`, `Unlocks`, schema 1, taste on disk, genre play time, start screen line and reset, `pending_session`); all save tests. **Numbers:** 5 chained invincible bot runs with `--save --keep-save --fresh` write `runs: 5` and play time within 2% of the sum of the runs' real seconds; a second chain with the same seeds gives the identical file | — |
| M28 | v0.0 + readability | 2.1–2.3: short run pacing, start content gating, prompt announcement, telegraphs, hit and kill confirmation, player-hit vignette, camera lookahead; `Look` with tier 0 and tier 1 `punchy` (the M14 feel) only. **Numbers:** invincible 16-seed sweep with `--fresh`: median run 170–200 s game time; mortal 16-seed sweep: median time-to-death reported (no target, it is the v0.0 baseline) | — |
| M29 | Dev session | Section 4 except the tier 1 takes' tuning: `Change`, `MockupTake`, `ChangeDB`, the 6 changes (look takes may use placeholder stills), dev session and patch notes screens, both shapes, agenda card, report button, bump, taste writes, AI's own ship, F9, telemetry schema 2, bot answers. **Numbers:** a 7-run fresh chained bot sweep with `ai_own_ship_every = 4`: session 1 ships `look_1` (v0.1.0), sessions 2–4 one pick each plus the AI's ship at 4, session 5 the last change as the AI's own (1 left), so all 6 are out by session 5 at v0.1.5; session 6 ships nothing and does not bump; at least one agenda card over the chain; same seeds → identical save | — |
| M29b | The broken first builds | 4.8: the basics, smoke-test runs, `basic_movement` and `basic_world`, the `basic` session shape, the bot's `--ship=`, check.ps1's save chain to 4 runs. **Numbers:** a 9-run fresh chained bot sweep: runs 1–2 are 20 s smoke tests and ship the basics (v0.0.1, v0.0.2), session 3 is the look mockup (v0.1.0), all 8 changes are out by v0.1.5, the last session ships nothing; same seeds → identical save | — |
| M30 | Look tier 1 + bomber + playtest build | 1.7 tier 1 takes tuned apart, `mockup_capture.gd` and the 3 committed stills, the bomber (3), Windows export (boot line with version and genres), a one-page playtest sheet. **Numbers:** M28's sweep medians still hold with all 6 changes shipped (±15%); **parity** ("never stats", ROADMAP 1.8 rule 5): mortal-bot time-to-death with starter enemies only, the 4-starter pool vs the 7-small pool, medians within ±15% (16 seeds each). **As built (4.9), `--fresh --ship=`, seeds 1–16:** invincible, all shipped: 181.1 s (M28: 181.1); mortal, all shipped: 109.7 s (M28: 108.9, +0.7%; was −27% before the tank retune); parity: 4-starter pool 108.9 s vs 7-small pool 102.6 s (−6%) | **G11 — real human playtest.** A fresh save, at least 6 runs in one sitting, so the two broken smoke-test builds (4.8), v0.0.2, the look mockup and 2–3 shipped changes all show. Do the broken first builds read as a joke, or as a broken game? Is v0.0 fun for 3 minutes? Does the dev session feel like a reward? Do the 3 juice takes read as clearly different from their stills? Does the player want "one more version"? |

Check, commit and report rules: as in v2 section 10. `tools/check.ps1` is green before every commit. Each milestone gets a tag (`m25`...) and a milestone report: what was built, check output, proxy numbers (saying which came from bots), decisions and tuning, known issues, what is untested.

**Why this order:** parking first shrinks what the genre port has to carry (no BIG prompts, no scaffold, B1 out of `RunState`). The genre port is a pure refactor with a hash gate, so it goes before anything changes how a run plays. The save comes before the short run because content gating reads it. The dev session needs the save and the gating. The look takes and stills are tuned last, once the screens that show them exist.

**Cut order if needed (first to last):** the AI's own ship (4.4) → the HP bar under damaged enemies → `patch_horde_mode`'s requires → the bomber (the chain keeps 5 changes) → the prompt announcement (a core-gimmick item, ROADMAP 1.4: cut last). **Never cut:** the genre interface and takes, the same-run hash gate, the save's mechanics and test isolation, both dev-session shapes, the look mockup with real stills, the readability telegraphs, the parity check, G11.

---

## 8. What v5 must answer
1. Is v0.0 fun for 3 minutes with no AI layer and 4 patches?
2. Does the dev session feel like a reward, and does the mockup session read as "the game is being made with me"?
3. Does the player want "one more version"?
4. Can the shell start and end a run of a genre it knows nothing about (the test genre)? (Prompt timing is the one shooter assumption left in the shell until Phase 5, 9.)
5. Does a patch's behaviour live only in its take file?

## 9. Still open (each with a proposed default)
After the alignment review (2026-11-21) the owner said "let's go": every default below stands until the owner says otherwise. The first five are ROADMAP section 6 defaults built as proposed.
- **(1) Bump rule:** a pick is a patch step; a look tier or maturity step is a minor step. Alternative: every session is a minor step.
- **(5) The AI ships its own change** every 4 sessions, least liked by tag, with its own bump (4.4). Alternative: `ai_own_ship_every = 0` for v5. ROADMAP still has this "to confirm".
- **(11) Report ratings** stay as a taste input. Alternative: drop them; the dev-session pick is the taste signal.
- **(12) Nothing carries between runs** inside the build. Alternative: the last run's pick starts in the next run's stack.
- **(13) The playtest** is G11, before Phase 4 closes.
- **Prompt timing stays with the Director** (1.1) until Phase 5. ROADMAP 1.3 says a genre tells the shell two things; until prompt points move into the genres, the shell keeps this one shooter assumption. Alternative: a third genre signal now (`prompt_due`), with the same rule moved into TopdownGenre.
- **Unpicked look takes do not return in v5** (4.2). Where they come back (a "look alt" change, Phase 6?) is open; ROADMAP Phase 6 does not list it yet.
- **Stills only for mockups** (4.3). Alternative: `mockup_capture.gd` also saves a short loop, which would show hit stop.
- **Big slot deletion waits for Phase 5** (1.3). ROADMAP Phase 4 says "remove the big slot"; v5 removes it from play and keeps the code as a parked seam so turn-based and its tests survive the port. Alternative: delete it now and park turn-based's tests until Phase 5.
- **The first dev session is the look mockup** (3, `due_after_run = 1`). Alternative: a 3-changes session first, the mockup at session 2 or 3.
- **No refusing a dev session** (4.2). Alternative: a "Surprise me" card that lets the AI pick.
- **Run 1's thin offers:** 4 starter smalls, prompt 3 shows 2 cards (2.3). Alternative: 5 starters (add `auto_attack`), so every v0.0 prompt shows 3.
- **The bot cannot judge fun:** M28's numbers are pacing only; G11 is the only fun gate.
- **After v0.1.5 there is nothing to ship** until Phase 5 (3). Accepted for a foundations phase.
- **Genre picker at run start** only appears with 2+ listed genres (1.5); with one it is skipped.
- **The broken first builds (4.8):** two 20 s smoke tests. v0.0.0 has no movement, no enemies and no level; v0.0.1 adds movement. The AI ships the basics with no choice. The basics and their order are this plan's default. Alternatives: three steps (movement, then enemies, then the level), only one broken build, or a card per basic so the player picks what to fix first.

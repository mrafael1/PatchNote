# Build Plan v4 — Stages and the AI boss ("Patch Notes")

> **On hold after M14 (owner, 2026-11-21).** The direction changed; see `ROADMAP.md` (v2). Its section 5 lists which v4 pieces survive. The next plan is v5 (Roadmap Phase 4).

**For:** the builder agent
**Goal of this build:** turn one continuous run into **3 stages + a boss stage**. Each stage is an arena the AI ships with a hidden patch of its own. Rollbacks become a weapon against the AI's patches. The game gets its first save, so the AI can ship new mutations from run to run.
**Engine:** Godot **4.7.x stable**, unchanged, GDScript, 2D simulation.
**Roadmap:** `ROADMAP.md` Phase 3. This plan is that phase.
**Supersedes:** `PLAN.v3.md` (v3) for scope and milestones. **Every v2 contract (v2 sections 1–4 and 9–12) and every v3 contract (v3 sections 1–6, 3b and 8) stays in force** unless this document changes it explicitly. Read `PLAN.v2.md` and `PLAN.v3.md` first.

---

## 0. Read this first

v3 proved that a permanent genre shift works on the v2 core. v4 gives the run a shape: chapters, a hidden AI patch per chapter, an end boss, and a pool that grows across runs.

| | v3 run (M13) | v4 run |
|---|---|---|
| Arenas | 1 (the Lab) | Lab, then 2 arenas you choose, then the Core (boss) |
| Length | ~10 min game time | ~18 min game time (3 + 5 + 5 + ~5); real time 20–25 min (ROADMAP, B1/B2 run ahead of game time) |
| Small prompts | 4 | 6: 2 per stage, none in the boss stage |
| BIG prompts | 2, after small prompts 1 and 3 | 2, at the end of stages 1 and 2 |
| Gravity | small card, forced at prompt 2 | medium tier: a stage's hidden default patch |
| Rollbacks | 2 free charges, on your own small patches | 1 charge + 1 per stage clear, on **AI patches only** |
| How it ends | survive the 90 s RC wave | destroy the Core in the boss stage, or die |
| Offer pool | all 10 mutations | starter pool (8 small + 2 big), grows by 2 per finished run |
| On disk | telemetry only | telemetry + `progress.json` (pool, arenas) |

Principle 1 holds without change: a stage default patch, a boss patch, and every new patch are `WorldRules` values plus components and listeners. **No patch branches on genre, stage or boss.** (The run flow itself dispatches on `StageDef.kind`, section 1.6; that is flow, not a patch.)

### Owner decisions for v4 (2026-11-20, final)
1. **Stages and BIG prompts both happen at stage ends.** A run is 3 stages + a boss stage. Stage 1 is the base game (no big patch). After each stage clear: a BIG prompt (the genre for the next stage), then a stage choice (2 arenas, leaned by taste). That keeps 2 BIG prompts per run, before stages 2 and 3. Small prompts stay inside stages.
2. **Rollbacks = ROADMAP option D.** Rollbacks target only AI patches: each stage's hidden default patch and the boss's live patches. The player cannot roll back their own small patches. The run starts with 1 charge and earns 1 per stage clear.
3. **Medium tier.** Medium patches (`gravity_on`, `gravity_reversed`, and new ones) are stage default patches. They end with the stage, can be rolled back as AI patches, and no longer appear at small prompts. The player is not told a stage's default patch; they discover it by playing.
4. **Pool growth is taste-led.** The first run's offers come from a starter pool (~8). Each finished run ships 1–2 new mutations leaning toward the tags the player likes, plus one agenda pick so nothing is locked out for good. This needs the first save on disk.
5. Earlier (2026-11-20): Turn-based conflicts with gravity. Section 5 proposes how that resolves with gravity stages (**flagged for the owner**).

**Owner playtest note (2026-11-20):** "gameplay is flat for now, but normal for the game beginning => it match the idea". v4 does not retune base combat for this; variety is meant to come from stages, defaults and the pool. **But v4 moves the first genre later:** in M13 the first BIG prompt came at ~60 s; in v4 it comes at the end of stage 1. To keep the flat stretch close to what the owner accepted, stage 1 is shortened to ~180 s (2.4), still 3× M13's. This is flagged (13) and G7 asks whether stage 1 drags.

**G5** ("does Turn-based feel different from B1?") was not answered explicitly. It is asked **now, at M14, on the existing M13 export** (no new build), because M17 and M20 build B2-specific content. M20's B2 enemy roles depend on the answer. G7 re-checks it.

### What v4 amends
| Rule | Was | v4 |
|---|---|---|
| v2 7, v2 3 HUD | 2 free rollbacks per run, on your own patches | 1 at start + 1 per stage clear, AI patches only (1.3) |
| v2 6, v3 3b.6 | gravity guarantee: forced gravity card at small prompt 2 | removed; `force_gravity_at_prompt` deleted. Gravity comes from stages |
| v2 5 | `gravity_on`, `gravity_reversed` are small patches | medium tier; never in the stack |
| v2 8 | one PLAY → RC → OVER pass; win = survive the RC wave | per-stage deploy wave; win = destroy the Core (2, 6) |
| v3 4 | BIG prompts after small prompts `[1, 3]` | BIG prompts at the end of stages 1 and 2 (4) |
| v2 2.5, v3 1.2 | patches live in `stack` and `big` | a third layer, `RunState.ai` (1.2); the invariant extends |
| v2 3 | one arena, consts in `arena.gd` | arenas as data (1.5) |
| v2 0, v3 0 | no saves | one save, `progress.json`: pool and arenas only (1.7) |
| v2 test "two reverts per run" | stack rollbacks | AI-layer rollbacks with earned charges |

Still true: the big slot is permanent and carries across stages ("This one stays" stays). Taste is not saved (v5). Every patch in every layer is removable in classes A and B.

### Already done before v4 (M13)
Big slot, B1 "Time moves when you move", B2 "Turn-based" with grid enemies and the danger map, 2 BIG prompts, session taste with agenda cards, telemetry with genre hits by kind, Windows export. Content: 8 small (2 of them gravity), 2 big, 1 arena, 3 enemy types.

### Out of scope (do not build)
- Tower defense big patch, JRPG card stage (v5; `StageDef.kind` leaves room for it)
- **Taste on disk** (v5). Pool growth reads the run's in-memory `Taste` at run end, so no taste is written. The save holds exactly what 1.7 lists.
- Self-rollbacks of the player's own patches, in any form
- Endings, AI personality evolution, menu takeovers (v6)
- A branching route map; stage choice is always 2 cards
- Arenas as run starts (ROADMAP 1.2 "as starts"): dropped for v4, flagged (13)
- Meta stats or power across runs (ROADMAP 1.3 rule 5; see the parity rule in 8.3)
- Saving settings; RTS; real generative AI; final art and audio

---

## 1. Contracts

### 1.1 `Mutation` and `MutationDB`: the medium tier and boss-only patches
```gdscript
@export var is_medium := false   ## how you move and see (ROADMAP 1.4): a stage default the boss may also push
@export var boss_only := false   ## a boss hazard: only the boss pushes it, never a stage
@export var starter := false     ## in the first run's offer pool (1.7)
@export var boss_weight := 0.0   ## > 0: the boss may push it live (section 6)
func is_ai_tier() -> bool: return is_medium or boss_only   ## lives in RunState.ai, never in the stack
```
- A patch is exactly one of small, medium, boss-only, big. `MutationDB.problems()` rejects any two of `is_medium`, `boss_only`, `is_big` together, and `boss_only` with `boss_weight == 0`.
- An AI-tier patch may `require` only mediums (`low_gravity` requires `gravity_on`); requiring a small or a big is rejected. It may `conflict` with any patch, big ones included. This is how `gravity_on` keeps `conflicts = [turn_mode]`.
- **A small patch may not `require` an AI-tier patch** (validated). Otherwise a stage end would drop the player's pick. A small may `conflict` with one.
- `starter` and `boss_weight` live on the mutation's own `.tres`, so the starter list names no id outside its folder.
- `MutationDB.summary_line` marks mediums `(MED)` and boss-only patches `(BOSS)` like `(BIG)`. `tools/export.ps1` checks both counts against the `.tres` files.

### 1.2 `RunState`: the AI layer
New state beside `stack` and `big`:
- `ai: Array[Mutation]`: live AI patches, in add order.
- `ai_owner: Dictionary`: id → `&"stage"` or `&"boss"`.

| Function | Does |
|---|---|
| `can_add_ai(m)` | `m.is_ai_tier()`, not present, requires met by `has_patch`, no conflict with `big`, `stack` or `ai` (live state) |
| `can_add_ai_list(ids, with_big, with_stack) -> bool` | **pure**: simulates adding `ids` in order to an empty layer over `with_big` and `with_stack` (each one's requires may be met by an earlier id in the list). Used by offer legality and `StageDB` checks; never reads live `ai` |
| `add_ai(m, owner)` | append → `recompute()` → `m.enable()` → `on_entity_spawned` on live entities → build +1 → log `ai_apply {id, owner}` → emit `EventBus.ai_patch_added(m, owner)` |
| `ai_dependents_of(m)` | AI patches in `ai` that require `m`, transitively. Scans only `ai` |
| `remove_ai(m, reason)` | removes `ai_dependents_of(m)` (latest first) and `m` through `_remove_ai` (erase from `ai` and `ai_owner`, then `_strip`) → one build → log `ai_remove {ids, reason}` → emit `EventBus.ai_patch_removed(m, reason)` for each. `reason` is `&"rollback"`, `&"expired"`, `&"dropped"`, or `&"console"` (F2 only: no charge, no `revert_used`; added at M14) |
| `expire_ai(owner)` | `remove_ai` on every patch of that owner with reason `expired`, as **one** build |

- Rule order: `base → big → ai → stack`. `preview_rules(patches, with_big = big, with_ai = ai)` gains the third argument. **Every** `Transition._run` preview passes the AI layer as it will be after the operation: `request_swap_big` passes `ai` minus what the swap drops; `request_ai_remove` passes `ai` minus `m` and its AI dependents; the deploy (2.2) passes the stage's default list. So an AI gravity change gets the pause, velocity clear and grace.
- `has_patch` scans `ai` too. **`dependents_of` stays stack-only** (it feeds `_remove`, which erases only from `stack`); AI removal always goes through `ai_dependents_of` and `_remove_ai`. `can_apply` (small) refuses `is_ai_tier()` and checks conflicts against `ai`.
- `register_entity`: big, then `ai` in order, then the stack.
- `swap_big` also removes AI patches that conflict with the new big, with their AI dependents (reason `dropped`, no charge). In normal v4 play the layer is empty at a swap (stage ends expire it first) and `get_big_offer` filters bigs that conflict with `ai` (4), so only the F2 console reaches this path. This also holds in M14's interim flow.
- `revert(m)` keeps working for the stack: the invariant tests and the F2 console use it. No player-facing path calls it any more (1.3).
- `reset()` strips the layer. `snapshot()` adds `"ai": [[id, owner], ...]` and `"blocks": [owner ids]` (the arena's extra block owners, 1.5).

**Invariant (extends v3 1.2):** after any legal sequence of apply / revert / swap_big / add_ai / remove_ai / expire_ai / reset, the state equals `reset()` → `swap_big(big)` → `add_ai` each AI patch in order with its owner → apply the stack in order. Same comparisons as v2 and v3 (rules, components per entity, mutation-owned connections), plus `ai` ids and owners and the set of arena block owners (not their rects, which are drawn from `gameplay_rng`). Component-internal state (a Shield's `spent` flag, 8.2) is entity state like HP and is not compared. Replay order differs from live order (an AI patch added after a small one). This is legal because rules use a fixed layer order, and no small can require an AI-tier patch.

### 1.3 Rollbacks (option D) and charges
- Charges live on the Director as today (`reverts_left`, renamed `charges`). Start: `Tuning.rollback_charges_start = 1`. Each stage clear adds `Tuning.rollback_charges_per_stage = 1`. A run therefore earns at most 4. No cap.
- `can_revert(m)` = `charges > 0` and `RunState.ai.has(m)` and the transition is not busy. **Stack patches are never targets.**
- `revert(m)` spends one charge for `m` plus its AI dependents. It goes through `transition.request_ai_remove(m, &"rollback")` and logs `revert_used {id, owner, hp}`.
- **Taste:** a rolled-back **stage** default calls `taste.on_revert` for each removed patch (the player steers away from it, ROADMAP 1.3 rule 3). A rolled-back **boss** patch does not touch taste: it is a tactical move the armor pushes the player into, not a dislike (flagged, 13).
- **`reverted` stays for smalls only.** AI rollbacks never write `Director.reverted` (which means "never offered again this run"). A rolled-back stage default stays off for the rest of its stage and can come back in a later stage or as a boss push. A rolled-back boss patch cannot be pushed again for `boss_relock_time` (section 6).
- `Transition.request_revert` (stack-only) stays for the F2 console. A new `request_ai_remove` checks `RunState.ai.has(m)`.

### 1.4 `WorldRules` additions
| Field | Type | Base | Composition | Reader | Milestone |
|---|---|---|---|---|---|
| `darkness` | bool | false | turned on | a world-light overlay (presentation); radius `Tuning.light_radius` | M16 |
| `friction_mult` | float | 1.0 | multiplied | `Mover` (player and walkers) | M17 |
| `slip_tiles` | int | 0 | added | `TurnClock._step`: a step slides on up to N more free, unheld tiles; the slide is resolved inside step 1 (`P`), before enemies plan | M17 |
| `projectile_pierce` | int | 0 | added | `projectile.gd`, player shots | M18 |
| `shot_count` | int | 1 | added | player `Shooter` (fan of `Tuning.spread_angle`) | M18 |
| `shoot_cooldown_mult` | float | 1.0 | multiplied | player `Shooter` | M18 |
| `dash_distance_mult` | float | 1.0 | multiplied | `Dasher`; `TurnClock._dash` uses `roundi(2 × mult)` tiles | M18 |
| `player_max_hp_add` | int | 0 | added | player `Health` (ratio kept, as for enemies) | M18 |
| `player_damage_mult` | float | 1.0 | multiplied | player projectiles and explosions | M18 |

Each field is one rule plus one reader, per the v2 section 1 exception. The danger tiles of B2 are never hidden by `darkness`: the danger promise wins over the visual.

### 1.5 Arenas as data
- New resource `ArenaLayout` (`levels/arena_layout.gd`): `id`, `cols`, `rows`, `ledges`, `chunks`, `spawn_tiles`, `player_start`, `core_rect` (boss only). These are the same shapes as today's consts, in tile units.
- `Arena.new(layout)` builds from it. `_init` keeps the border, ledge and chunk order, so the Lab is built **block for block identical** to M13 (test). `Arena.COLS/ROWS` go; tests read `arena.layout`. `core_rect` is **not** built into the `Blocks` StaticBody (the Core entity is its own body, 6); it is included in `distance_to_blocks` and `TurnClock`'s blocked tiles.
- **Extra blocks:** `Arena.add_blocks(owner, rects)` / `remove_blocks(owner)` build a second StaticBody per owner (freed in the owner's `_exit_tree` too) and emit `EventBus.arena_blocks_changed(arena)`. That signal only clears `TurnClock._free` and rebuilds the danger map; it never moves the player. `Arena.block_owners()` feeds `snapshot()`.
- Layout rules from v2 section 3 hold per arena: no pockets deeper than the jump, open lanes, 12–16 spawn tiles valid in every gravity state. **Ledge reachability both ways with the tuned jump is checked on every arena, the Core included**, because gravity can be live anywhere (stage variations, boss pushes).
- **Swap seam:** `Main.load_arena(layout)` frees the old Arena and adds a new one, moves the player to `player_start`, and emits `EventBus.arena_changed(arena)`. The spawner, `TurnClock` and the camera (`set_bounds`) listen to it instead of being re-pointed from `Main`.
- **TurnClock on `arena_changed` fully re-enters:** `_turn_left = 0`, `mover.stop()`, clear `_free`, `danger`, `intents` and every held-tile claim, `snap_player()`, `player_tile = tile_center(player_start)`, then rebuild the field and the danger map before the first turn. (Today only `_enter`, on the rule toggle, resets this; a STAGE_WAVE under B2 almost always ends mid-turn, and `_end_turn` would put the player back on the old arena's tile.) The `_free` comment "the arena never changes" is corrected.
- `turn_logic.gd` `RING_LIMIT` becomes `cols + rows` of `TurnClock.arena` (the clock is the neutral owner, so the mutation still names nothing outside its folder).
- **Clearing hostiles:** `RunState.clear_hostiles()` frees the members of `enemy`, `enemy_projectile`, `player_projectile` and explosions, every extra block owner, **and every node still in flight**: `RunState.spawn` keeps its deferred nodes in `_pending_nodes: Array[Node]` (removed on `register_entity`), and `clear_hostiles` frees those and zeroes `_pending`. This is class C: it is logged and never touches patches.

### 1.6 Stages
- New resource `StageDef` (`levels/stage_def.gd`), one `.tres` per arena in `levels/stages/`: `id`, `kind: StringName` (`&"start"` for the Lab, `&"arena"`, `&"boss"` for the Core; v5 adds `&"cards"`), `title` (must not name a patch), `blurb` (the AI's line on the card, which must not name the patch), `tags`, `layout: ArenaLayout`, `variations: Array[StageVariation]`, `starter := false`, `unlock_by_reaching := 0` (1.7).
- `StageVariation`: `id`, `patches: Array[StringName]` (1–2 medium ids, added in order), `weight := 1.0`.
- **`StageDB` autoload** (`core/stage_db.gd`), modelled on `MutationDB`: `ResourceLoader.list_directory`, sorted by id (the listing order is not guaranteed, and exported builds need it). `problems()` checks: every id in `patches` exists and `is_medium` (never boss-only or big); requires are satisfied in order inside the variation; exactly one `boss` and one `start` stage; variation ids are unique per arena; within an arena, variations have distinct first patches. The boot and export lines print the stage count.
- A **stage** at runtime = (arena, variation). Its default patches are added with owner `&"stage"` during the deploy transition and expire at stage clear.
- **Dispatch by kind:** the stage choice filters `kind == &"arena"`. `RunLoop` and the Director's add-ons (the boss script, 6) are enabled by `stage_started` according to `kind`, never by id.
- **Folder isolation:** the grep test (`test_mutations.gd`) now allows a mutation id in exactly one more place: the `patches` field of a `levels/stages/*.tres`. Any other mention still fails.

### 1.7 The save: `Progress`
- `core/progress.gd`, `class_name Progress`, static state like `Telemetry`. `Progress.save_path` (default `user://save/progress.json`) can be pointed elsewhere, like `Telemetry.log_path`.
- **Inert by default:** `Progress.persist = false` and `Progress.unlock_all = true` until something turns them on. Only the start screen (when it starts a game), and `tools/bot_runs.gd --save=`, turn them on and load. A test file therefore cannot forget a setup step: GUT, `res://main.tscn` booted directly (check.ps1, editor F6) and the exported `--autostart` boot all run inert with the full pool and never read or write the real file. The pool tests turn both on with a temp path.
- **Schema (version 1), the only things saved:**
```json
{"version": 1, "runs_finished": 3,
 "pool": ["auto_attack", "homing_shots", ...],
 "arenas": ["foundry"],
 "shipped": [{"run": 1, "seed": 12345, "ids": ["homing_shots", "glass_cannon"], "why": ["taste", "agenda"], "arenas": ["foundry"]}],
 "new": ["homing_shots", "glass_cannon", "foundry"]}
```
- `pool` starts as every `starter = true` mutation. `arenas` lists unlocked non-starter arenas only; starter arenas, the Lab (`start`) and the Core (`boss`) are always available and never stored. `new` holds what the last finished run shipped; it is replaced only by the next finished run's write. An unfinished run writes nothing, so NEW survives it.
- **Missing file:** starter state, nothing written until a finished live run ends. **Missing key** (a partial file): that key's default, the others kept. **Corrupt file** (bad JSON or a wrong type), only when `persist`: renamed to `progress.bad.json`, a `push_warning` (never `push_error`, because `check.ps1` scans for `ERROR:`), then starter state. **Higher version:** used read-only as starter state in memory and never overwritten; "Reset progress" is disabled and the start screen says "progress from a newer build". **Unknown ids** (a mutation or arena removed since): dropped on load.
- **Writes** happen only when a finished run (7) of a live game ends, after shipping. The atomic write goes to a `.tmp` file, then a rename.
- **Reset:** the start screen gets "Reset progress" (two clicks, like the history's rollback arm). It writes the starter state (not on a higher-version file, see above).
- **Bot runs:** by default every bot run loads the same read-only snapshot (`--pool=starter`, the default, or `--pool=all`) and writes nothing, so seeds stay comparable one by one. Only `--save=<path> --keep-save` chains runs through a file; only the M19 gate uses it.

---

## 2. Stage flow

### 2.1 Run structure
| Stage | Arena | Default patches | Genre | Small prompts | Ends with |
|---|---|---|---|---|---|
| 1 | Lab (`start`) | none | none (base game) | 2 | deploy wave → clear → BIG #1 → stage choice |
| 2 | chosen | 1 variation (hidden) | BIG #1 pick | 2 | deploy wave → clear → BIG #2 (with Keep) → stage choice |
| 3 | chosen, not stage 2's arena | 1 variation (hidden) | BIG #2 pick | 2 | deploy wave → clear (no BIG, no choice) |
| Boss | Core (`boss`) | none at start; the boss adds them live | inherited | 0 | Core destroyed (win) or death (lose) |

**End of stage 3 (proposal, flagged):** no BIG prompt and no stage choice. The boss inherits the genre and the stack, so the boss tests the build the player made. The stage-3 clear still grants the charge and the heal.

### 2.2 Phases (`RunLoop`)
`PLAY → STAGE_WAVE → STAGE_CLEAR → BIG_OPEN → STAGE_OPEN → DEPLOY → PLAY ... → BOSS → OVER`.
- **`Director.poll()` runs only in PLAY** (RunLoop sets `director.enabled` false on leaving PLAY and true on entering it), so the Director never opens a small prompt in a later phase.
- **PLAY:** the Director's per-stage small prompts. When `director.stage_prompts_done()`, go to STAGE_WAVE.
- **STAGE_WAVE:** today's RC wave, renamed and shortened. `spawner.phase_rate = stage_wave_rate`, `phase_cap = stage_wave_cap`, for `stage_wave_duration[index]`. The HUD shows the countdown (`rc_time_left` becomes `wave_time_left`).
- **STAGE_CLEAR:** `RunState.clear_hostiles()`, `expire_ai(&"stage")` (one build, no charge, the patch name is revealed in the log), `charges += rollback_charges_per_stage`, heal `stage_clear_heal`, `spawner.phase_rate = phase_cap = 1`, emit `EventBus.stage_cleared(index)`. Then BIG_OPEN if this stage is in `big_prompt_at_stage_end`, else STAGE_OPEN if a choice follows, else DEPLOY (to the Core after stage 3).
- **BIG_OPEN:** opens the BIG prompt (prompt pause). Leaves only when the prompt is answered **and** `transition.finished` has fired for the swap it started (`request_swap_big` stays busy for `transition_long` and awaits a timer; `on_choice` returns before the slot changes). A skipped or Keep answer leaves at once.
- **STAGE_OPEN:** builds the stage offer **at open time**, against the big now in the slot (3), and opens it (prompt pause). Leaves on `stage_chosen`.
- **DEPLOY:** `transition.request_stage(stage_def, variation)`: pause `transition`, terminal band "deploying build to <title>…", a fade, `Main.load_arena` (TurnClock re-enters, 1.5), `spawner.reset_stage(index)`, `add_ai` each default patch (no toast, no line), grace, unpause. Its preview passes the variation's patches as the AI layer, so a gravity default plays the gravity safety. Emits `EventBus.stage_started(index, id)`.
- **BOSS:** section 6. **OVER:** as today. `end()` is reached by death or by `EventBus.boss_defeated`.

### 2.3 What carries across stages
| Carries | Resets at stage start |
|---|---|
| stack, big slot, HP (+1 heal at clear), charges, kills, run log, taste, build number | enemies, projectiles, explosions, in-flight spawns, extra blocks; spawner ramp (`_elapsed`, `_timer`), wave multipliers (`phase_*`), stage multipliers (`stage_*`, set to the new stage's); stage prompt counters; AI layer (`stage` owner); TurnClock turn state |

### 2.4 Pacing (starting targets, game time)
- Stage 1: first small prompt at `stage_first_prompt_gap[0] = 45` s, the second ≥ `stage_prompt_gap[0] = 90` s later, then a `stage_wave_duration[0] = 45` s wave: **~180 s**. Shorter than stages 2 and 3 so the flat base game does not stretch far past what the owner played in M13 (0, 13).
- Stages 2 and 3: first prompt at `stage_first_prompt_gap[1..2] = 90` s, which leaves time to discover the default patch, then `stage_prompt_gap[1..2] = 150` s, then a 60 s wave: **~300 s each**. `stage_prompt_max_gap = [120, 180, 180]` replaces `prompt_max_gap`.
- Boss: ~300 s (section 6; tuned at M22). **Total ≈ 18 min of game time.** Prompts, history and transitions are paused time, as today.
- **Game time vs real time:** the per-stage targets are game time, because that is what the pacing knobs control. Under B1 and B2 real time runs ahead of game time (`RunState.real_time()`). The ROADMAP's 20–25 min is read as **real time** (what the player sits through): M14's report measures M13's real-to-game ratio per genre, and the full-run gate (M24) is set on `real_duration` with game time reported beside it.
- **Pressure by stage:** `stage_spawn_rate = [1.0, 1.15, 1.3, 1.2]`, `stage_spawn_cap = [1.0, 1.1, 1.2, 1.0]`. They go into new spawner fields `stage_rate` and `stage_cap`, set by `reset_stage(index)` and **multiplied** with `phase_rate`/`phase_cap` (the wave's): interval `delta × spawn_rate_mult × phase_rate × stage_rate`, cap `max_enemies × phase_cap × stage_cap`. Never rules.
- Kill thresholds keep `first_prompt_kills = 15` and `prompt_kills_step = 10`, reset per stage.

---

## 3. Stage choice
- `director.get_stage_offer() -> Offer` with `offer.kind = &"stage"` and `offer.stages: Array[StageCard]` (a `StageDef` + its hidden `StageVariation`). `Offer.kind` replaces the `big` flag's role (`big` stays as a getter for v3 call sites). It is built in STAGE_OPEN (2.2).
- **Candidates:** arenas with `kind == &"arena"` that are available (starter, or in `Progress.arenas`, or `unlock_all`), excluding the arena played in stage 2. A variation is legal only if `RunState.can_add_ai_list(variation.patches, RunState.big, RunState.stack)`. An arena with no legal variation is not a candidate.
- **Variation pick, exactly:** candidate arenas in `StageDB` id order; for each, **one weighted draw** from `director_rng` among its legal variations, weight `variation.weight × clamp(1 + LEAN × Σ taste.score(patches), MIN_MULT, MAX_MULT)`. The number of draws therefore depends on the available arenas, so every determinism claim reads **same seed + same save + same choices**.
- **Lean:** arena score = `taste.stage_score(arena id)` + the sum of `taste.score(m)` over the drawn variation's patches. Weight = `clamp(1 + LEAN × score, MIN_MULT, MAX_MULT)`, as for mutations. `Taste` gains `by_stage` (pick `+PICK`, pass `PASS`). Rolling back a stage default lowers that patch and its tags, so a rolled-back ice floor makes icy variations rarer (never removed, 1.3).
- **Size and agenda:** `stage_offer_size = 2`. With 2+ candidates, card 1 is a lean-weighted draw and card 2 is the AI's agenda pick (least liked, `_least_liked`), as in BIG offers. **After an unrated run** (ROADMAP 1.3 rule 4; small offers already take 2 agenda cards) the stage choice still keeps 1 agenda card, because 2 would leave no lean; the extra free rein goes into shipping (7). With 1 candidate, it is mandatory. With 0, the fallback is "Lab (rerun)" with no default patch, logged `stage_fallback`.
- **What a card shows:** the arena title, a thumbnail drawn from the layout's rects, its size, the AI's `blurb`, and "NEW" if **the arena** was unlocked by the last finished run. It **never shows the default patch**, its tags, its variation id, or any per-variation mark.
- **Input:** keys 1–2, mouse, focus. The same panel is used (`PromptPanel` builds stage cards when `offer.kind == &"stage"`). The panel emits `stage_chosen(offer, index)`, which goes to `director.on_stage_choice`.

---

## 4. BIG prompts at stage ends
- `Tuning.big_prompt_at_stage_end = [1, 2]` replaces `big_prompt_after`. `RunLoop` opens the BIG prompt in BIG_OPEN. `big_prompt_due()` is no longer polled from small-prompt counts. The single-genre bot recipe becomes `--big=turn_mode --set=big_prompt_at_stage_end=[]` (the `bot_runs.gd` header is updated).
- Offer rules from v3 section 4 and 3b.6 are unchanged: up to `big_offer_size = 2`, the agenda card, Keep from BIG #2, mandatory with one candidate, skip when empty. The pool is now `Progress`-filtered (section 7).
- Order matters: **the BIG prompt comes before the stage choice**, so the stage choice is filtered by the genre just picked (section 5).
- **`get_big_offer`'s conflict check covers `stack` and `ai`** (`_conflicts_with_live`), permanently. At a v4 stage clear the layer is already empty, but M14's interim flow and any later flow change stay correct.

---

## 5. Conflict rules
**Proposal for Turn-based vs gravity stages (flagged for the owner):** the stage choice never offers a variation whose patches conflict with the slotted big. Gravity variations are filtered out after a Turn-based pick, and B2 under gravity stays unreachable in normal play (v3 3b.6). To keep 2 cards possible under every genre without the arena naming its patch, the content follows the rules below. Alternative if the owner prefers it: allow the gravity stage and drop `gravity_on` when the stage starts. That would make the arena's identity vanish, so this plan rejects it.

- **Content rule (tested, `StageDB` data):** for every big value (none and each big) and an empty stack, in both the starter set and the full set:
  - at least 3 `arena` stages have a legal variation (covers stage 3's "not stage 2's arena");
  - **no arena has exactly one legal variation** (choosing it would tell the player the patch);
  - within an arena, legal variations have distinct first patches.
- **Small vs stage default:** small offers inside a stage go through `can_apply`, which now sees `ai`. A small that conflicts with the live default is not offered during that stage and comes back after it.
- **Stack vs stage choice:** a variation that conflicts with a stacked small is not offered (3). This answers ROADMAP open decision 5 ("can a stage's variation conflict with the player's patches?"): no, it is filtered. Flagged (13).
- **Boss pushes:** only patches passing `can_add_ai` (6). Under B2 the boss never pushes gravity.
- **Console:** F2 ignores legality as today. `swap_big` drops conflicting AI patches (1.2).
- **No proposed small conflicts with a medium.** Fixtures exercise that path (11).

---

## 6. The boss stage
- **Arena:** the Core (`core`, kind `boss`, 50 × 24, symmetric, four pillars), with no default patch. Spawner `stage_spawn_rate[3]`; the enemy mix includes every enemy type built.
- **The Core:** `entities/boss_core.tscn`, a stationary 2 × 2-tile `StaticBody2D` on `layout.core_rect`, on `LAYER_WORLD | LAYER_ENEMY_BODY`, covering exactly its tiles. It registers through `register_entity` with kind `&"boss"` (group `entities` and `boss`, not `enemy`, so it stays out of caps and kill counts). Projectiles ray-cast for bodies in group `entities`, so shots hit it; `LAYER_WORLD` makes walkers and the player collide with it; no layout chunk overlaps it, so which body a ray meets first is defined. Because every patch's `on_entity_spawned` runs on it, a test asserts that no small, medium or big attaches a component to a `boss`-kind entity (patches already filter by group).
- **Health:** `boss_hp = 400` (starting value; a base shot deals 1), `scales_with_enemy_rule = false`, so `horde_mode` does not shrink it.
- **Armor:** `Health` gains a generic `damage_taken_mult := 1.0`, multiplied into the amount inside `take()` (the only place damage is applied). The Core's `BossArmor` component (`components/`) sets it to `boss_armor_per_patch^n` = `0.6^n` on `ai_patch_added`/`ai_patch_removed`, where n = live patches with owner `boss`; it counts owners and names no patch. Three live patches leave 22% damage. **Rolling back a boss patch is both a hazard removed and a damage boost: this is the weapon.**
- **Pushes:** the boss **opens with a push at 0 s** (so n = 1 from the start; with n = 0 focused fire at ~5.5 shots/s would melt the opening), then every `boss_patch_interval = [40, 30, 22]` s by phase. Phases change at Core HP `boss_phase_at = [0.66, 0.33]`. Each push adds one patch with owner `&"boss"`, **named**: the boss announces it (toast, HUD list). Boss patches are visible; only stage defaults are hidden (flagged, 13).
- **Pushes vs charges:** a ~300 s fight is ~10 pushes against at most 4 charges (1 + 3 clears, minus any spent on stage defaults). That is intended: the cap and oldest-expiry keep n ≤ 3 without the player, and a charge is spent when the player wants a damage window. **The charge rules are not changed** (owner decision 2); if G8 says the boss needs more charges, that goes to the owner.
- **Pick:** from patches with `boss_weight > 0` (mediums and boss-only) that pass `can_add_ai` and are not relocked, drawn from `director_rng`. Odd pushes weight by `boss_weight × (1 / taste.weight_mult(m))`, which aims at what the player likes least. Even pushes weight by `boss_weight` alone. (Boss rollbacks do not feed taste, 1.3, so this cannot spiral.)
- **Cap:** `boss_max_live = 3`. A 4th push first expires the oldest (reason `expired`, free).
- **Relock:** a rolled-back patch cannot be pushed again for `boss_relock_time = 45` s.
- **B2:** pushes and expiries land only between turns (TurnClock waiting, `_turn_left == 0`); a push due mid-turn waits for the turn to end. The Core is static on blocked tiles, and player shots hit it by physics during the turn (v3 3b.1). The danger promise is unchanged, because the Core does not attack; `firewall` walls go through `arena_blocks_changed`, which rebuilds the danger map.
- **End:** Core HP 0 emits `EventBus.boss_defeated`, then `end(&"win")`, "v1.0 shipped". Player death: `end(&"lose")`. There is no time limit; the patch cap and the intervals keep the pressure on.
- **Code shape:** `director/boss.gd` (scripted AI, a child of the Director), enabled by `stage_started` when the stage's `kind == &"boss"`. It only calls `RunState.add_ai` and `remove_ai`. The Core entity is plain simulation and knows no patch.

---

## 7. Pool growth
- **Offer pool:** `director._pool()` = `MutationDB.all` filtered by `Progress.has(id)`. Both `get_offer` and `get_big_offer` read it. AI-tier patches are never in it: they come from stage and boss data.
- **Starter (run 1):** 8 small (`auto_attack`, `bouncing_projectiles`, `explode_on_hit`, `enemies_split`, `horde_mode`, `jump_button`, `piercing_shots`, `long_dash`) + 2 big (`motion_time`, `turn_mode`). The two new starters exist from M18, before the save (M19). Starter arenas: `shaft`, `loading_dock`, `archive` (with all their variations); the Lab and the Core are always there.
- **Short offers:** run 1 has 6 small prompts over 8 starter smalls, so prompt k sees at most 9 − k candidates (prompt 6: 3, fewer when a live default withholds one). When candidates < `offer_size`, the prompt shows all of them; the agenda card is kept only when ≥ 2 cards show; 0 candidates skip the prompt (logged `prompt_empty`). Run 1's last prompts therefore have little lean. Flagged to the owner (13); the "~8" starter size is not reopened.
- **A finished run (proposal, flagged):** a live run that reached the report and cleared stage 1. A quick death and restart ships nothing.
- **Shipping, at run end, before the save is written,** exactly 2 mutations per finished run, which fits both readings of owner decision 4:
  1. **Taste pick:** `ship_taste_per_run = 1`. The locked mutation with the highest `taste.score(m)`, a weighted draw with the same `weight_mult`. A never-seen mutation scores through its tags only, which is what "leaning toward tags" means.
  2. **Agenda pick:** `ship_agenda_per_run = 1`. The locked mutation with the lowest score (the `_least_liked` pattern). Ties are broken by RNG.
  - **After an unrated run** (the flag v3 already uses for 2 agenda cards; ROADMAP 1.3 rule 4): 0 taste + 2 agenda.
  - **Taste source:** the run's in-memory taste at run end. Ships happen before the report, so the report's Keep/Cut ratings do not affect them (they still reach `Taste.carried` for the next run's offers, as today). Flagged (13).
- **Arena unlocks (proposal, flagged), by reaching** (ROADMAP 1.2): a locked arena has `unlock_by_reaching = N` and unlocks at the end of the first finished run that reached stage N (`foundry`: 3). Arena unlocks are written in the same save and marked NEW on the arena. There is no taste ship for arenas.
- **RNG:** a local `RandomNumberGenerator` seeded `hash([run_seed, "ship"])`. Candidates are sorted by id first. Same seed + same save + same taste → same ships.
- **Big patches** ship like smalls (the 3rd big starts locked, from M23). When everything is shipped, nothing ships and the report says so.
- **Shown:** the report's "Shipped in the next build: X, Y" line. A "NEW" mark on the first card of each shipped mutation and on a newly unlocked arena's card (never on a variation). The start screen line "Build: N mutations · M arenas".
- **Count:** 8 locked smalls (16 − 8 starter), plus 1 locked big from M23 = 9. At 2 per run the pool completes in 4 finished runs (5 with the 3rd big). One arena unlocks by reaching.

---

## 8. Content (starting targets)

### 8.1 Arenas (6, as data)
Titles never name a patch. Every arena has at least 2 legal variations under every big value, with distinct first patches (5). The signature variation (weight 2.0) is listed first.

| Id | Kind | Title | Size | Shape | Variations (patches) | Legal under B2 | Starter |
|---|---|---|---|---|---|---|---|
| `lab` | start | Lab | 66 × 22 | v3 lattice | none | — | always |
| `shaft` | arena | Shaft | 36 × 34 | tall, ledges every 3 rows, narrow lanes | a `gravity_on` · b `gravity_on`+`gravity_reversed` · c `close_camera` · d `lights_out` | c, d | yes |
| `loading_dock` | arena | Loading Dock | 66 × 20 | open floor, low crates, long sightlines | a `ice_floor` · b `gravity_on` · c `close_camera` · d `lights_out` | a, c, d | yes |
| `archive` | arena | Archive | 56 × 26 | rows of racks as lanes, gaps between | a `lights_out` · b `gravity_on`+`gravity_reversed` · c `close_camera` · d `ice_floor` | a, c, d | yes |
| `foundry` | arena | Foundry | 60 × 24 | big chunks, a lower floor under pits | a `gravity_on`+`low_gravity` · b `ice_floor`+`close_camera` · c `lights_out` · d `close_camera` | b, c, d | no (reach stage 3) |
| `core` | boss | Core | 50 × 24 | symmetric, 4 pillars, Core at centre | none | — | always |

Variations that use `ice_floor` or `low_gravity` ship in M17; M16's data already satisfies the content rule with the other four mediums (B2-legal: c and d everywhere). Under B2: 3 starter arenas with 2–3 legal variations each, plus foundry later. The content rule holds.

### 8.2 Medium tier (6) and boss-only patches (4)
| Id | Effect | Tags | Requires / conflicts | Boss weight | Milestone |
|---|---|---|---|---|---|
| `gravity_on` | as today; becomes medium | physics | conflicts `turn_mode` | 1.0 | M14 |
| `gravity_reversed` | as today; becomes medium | physics | requires `gravity_on` | 0.5 | M14 |
| `close_camera` | `camera_zoom × 1.4` | vision | — | 1.0 | M16 |
| `lights_out` | `darkness` on (light radius 4.5 tiles) | vision | — | 1.0 | M16 |
| `ice_floor` | `friction_mult × 0.15`, `slip_tiles + 1` | physics | — | 1.0 | M17 |
| `low_gravity` | `gravity_strength × 0.45` | physics | requires `gravity_on` | 0 | M17 |

Boss-only (`boss_only = true`, `boss_weight > 0`, never in a stage, M22):
- `spawn_surge`: `spawn_rate_mult × 1.6`, `max_enemies + 10`.
- `shield_wave`: every enemy, live or spawned, gets a `Shield` component while the patch is live (`on_entity_spawned` runs on all of them at apply and on replay, so it cannot be "only enemies spawned while live"). A Shield absorbs one hit, then sets `spent` and stays inert until the patch goes.
- `core_regen`: the Core heals 1 HP per 2 s, through a listener.
- `firewall`: a component on the Core owns 2 wall bars, 1 × 5 tiles, placed from `gameplay_rng` between the player and the Core, only on free, unheld tiles, never on `P` or within 1 tile of the player. It uses `Arena.add_blocks(owner, rects)` / `remove_blocks(owner)` (1.5), removed in `_exit_tree`.

### 8.3 Small patches (6 kept + 10 new = 16)
**Parity rule (ROADMAP 1.3 rule 5):** a shipped small is a sidegrade at parity with the starter set: it carries a cost, or it is a risk card. The starter set mixes buffs and risks (`horde_mode`, `enemies_split`). The M18 report compares mortal-bot time-to-death on the starter pool against the full pool (16 seeds each, forced picks at random); the medians must be within ±15%, or the costs are retuned.

| Id | One mechanic | Cost | Tags | Requires / conflicts |
|---|---|---|---|---|
| `piercing_shots` (starter) | shots pass through 1 enemy (`projectile_pierce + 1`) | — (starter) | weapon | — |
| `long_dash` (starter) | dash ×1.5 (B2: 3 tiles) | — (starter) | movement | — |
| `shotgun_spread` | 3 shots in a fan | cooldown ×1.6 | weapon | — |
| `homing_shots` | player shots steer toward the nearest enemy (component) | shot speed ×0.7 | weapon | conflicts `bouncing_projectiles` |
| `chain_lightning` | a kill arcs 1 damage to the nearest enemy within 3 tiles | cooldown ×1.25 | weapon | — |
| `shrapnel` | explosions throw 3 short shots | needs `explode_on_hit` | weapon | requires `explode_on_hit` |
| `dash_shockwave` | dash end deals 1 damage within 1.5 tiles | dash cooldown ×1.3 | movement | — |
| `vampire_kills` | every 20 kills heal 1 HP (count in `state()`) | max HP −1 | survival | — |
| `glass_cannon` | damage ×2 | max HP −2 | risk | — |
| `elite_enemies` | 1 spawn in 6 is elite: ×3 HP, larger, heals 1 on death | the elites | spawn | — |

New tags `survival`, `risk` and `vision` get names in `Dialogue.TAG_NAMES`.

### 8.4 Third big patch (owner to pick at G7)
- **Candidate A, "Stealth" (`stealth_mode`):** enemies start unaware and patrol; a vision cone component spots the player; a shot alerts its neighbours; unaware enemies take ×3 damage. Skill: picking sightlines. It pairs with `lights_out`.
- **Candidate B, "On the beat" (`beat_mode`):** the world keeps a beat (`beat_interval`, assigned by the big patch). Enemies move and fire only on beats. Player shots within ±0.08 s of a beat deal ×2 and pierce; off-beat shots deal ×0.5. Skill: timing. It is different from B1 (the player does not control time) and from B2 (the beat does not wait).
Both are rules plus components plus listeners. Both need a bot policy and B1/B2-style acceptance numbers, set when the owner picks.

### 8.5 Enemies (3 + 2 = 5, + the Core)
| Type | Real time | Under gravity | B2 role (in `mutations/turn_mode/`) | From stage |
|---|---|---|---|---|
| Bomber | walks in; at 1.5 tiles arms a 0.8 s fuse (ring drawn), blast of 1.6 tiles, 1 damage (`explosion` kind), dies in it; also blows 0.3 s after its death | walks like a chaser | adjacent to `P`: arms (8 tiles marked), blows at the next resolution | 2 |
| Lancer | holds at 4–7 tiles, telegraphs a line for 0.7 s, charges 6 tiles, 1 contact damage, stunned 1 s on a wall | charges laterally only | aims on row or column like the shooter; the next turn it moves up to 6 tiles along the line; hits if `P` is on it (marked) | 3 |

The B2 roles are built as listed if G5 (asked at M14) says Turn-based reads as its own game. If G5 says it is still too close to B1, M20 builds the real-time and gravity behaviours, gives both new enemies only the plain grid walker role in B2, and the B2 roles wait for the owner's direction.

Tuning keys follow `<archetype>_<name>` (`bomber_speed 150`, `bomber_hp 2`, `bomber_fuse 0.8`, `lancer_hp 4`, `lancer_charge_tiles 6`...). The mix by stage: `stage_enemy_mix` (Tuning), an array of weight dictionaries that replaces the shooter and tank chances. Stage 1 equals the v3 chances; `spawn_tank_delay` is kept.

---

## 9. Director, presentation, telemetry, bot

### 9.1 Director
- Per-stage counters reset on `stage_started`: `stage_prompt_index`, `_kills_since_prompt`, `_kills_needed`, `_last_prompt_time`. The run-level `prompt_index` stays (lines, telemetry).
- `prompts_per_stage = [2, 2, 2, 0]` replaces `prompts_per_run`. `stage_prompts_done()` replaces `prompts_done()`.
- `poll()` runs only while RunLoop is in PLAY (2.2).
- Removed: `force_gravity_at_prompt`, `_mode_switch_applied`, the mandatory gravity branch, `big_prompt_after`, `reverts_per_run`.
- **Temporary in M14 only:** `ai_scaffold_at_prompt = 4`. Right after small prompt 4 (the last one, after the last v3 BIG prompt), the AI adds the first `is_medium` mutation with `is_mode_switch` in `MutationDB` order (chosen by data, never by id, so `director/` names no mutation) as owner `&"stage"`, if `can_add_ai`. It stays live through the RC wave, so the one-stage M14 build has a rollback target. Deleted in M16.

### 9.2 Presentation
- **HUD:** "Stage 2/3 · Loading Dock" (boss: "Core 284/400"), "Rollbacks: N [Tab]", the wave countdown, and the live boss patches listed under it.
- **Patch History:** a new top section, **AI PATCHES**. A stage default shows as "Stage patch: undocumented" with a Roll back button until it is rolled back or the stage ends; then it shows its title. Boss patches show by name. The stack is listed without buttons ("yours: cannot be rolled back"). The log gets stage markers ("— Stage 2: Loading Dock —") and `ai_apply`/`ai_remove` rows. Hidden defaults are written "AI patch (undocumented)" until revealed.
- **Lines (`Dialogue`):** `ROLLBACK_HINT` = "Tab opens the build log. Your picks are final. Mine are not, if you have a rollback." Add: stage choice, deploy, stage clear ("Stage 2 shipped with: Ice floor"), boss intro, boss push, boss rollback, boss defeated. Stage openings never name the default patch.
- **Report:** a line per stage (arena, its default patch now named, rolled back at m:ss or not, genre, game and real time), "Rollbacks used N of M earned", the boss result (Core HP left, pushes, rollbacks), and "Shipped in the next build". Stage defaults and boss patches become rateable (Keep / Cut), which feeds `Taste.carried` as today (not the ships, 7).
- **Start screen:** the build line, "Reset progress" (disabled on a higher-version file).
- **Debug:** F2 lists AI-tier patches with add/remove AI. F8 skips to the next stage (wave cut, then clear). Shift+F8 jumps to the boss. F1 shows `ai` with owners.

### 9.3 Telemetry (schema 2)
Add to the run record: `schema: 2`, `stages[]` {index, arena, variation, patches, big, started, cleared, duration, real_duration, kills, hits_by_kind, rolled_back_at}, `stage_offers[]` {cards, agenda, pick, fallback}, `ai_events[]` {time, id, owner, op, reason}, `charges` {start, earned, used}, `boss` {reached, pushes, rolled_back, expired, core_hp_left, duration}, `pool_size`, `arenas_unlocked`, `shipped`, `prompt_empty`. Keep every schema 1 field. `reverts_used` now counts AI rollbacks.

### 9.4 Bot (`tools/bot_runs.gd`, `core/bot_input.gd`)
- Answers stage choices with a random card from the run-seeded RNG.
- **Rollbacks (from M14):** the bot targets `run_state.ai`, never the stack. M14: odd seeds roll back the scaffold patch 30 s after it lands. From M16: odd seeds roll back the stage default 30 s into stages 2 and 3. From M22: every seed rolls back the newest boss patch when charges > 0 and ≥ 2 boss patches are live. This goes through `patch_history.open` and two presses, as today.
- The policy targets the Core in the boss stage when no enemy is within 6 tiles.
- New flags: `--arena=<id>` (M15: start in that arena, no stage flow), `--ai=<id,id>` (M15: add those AI patches with owner `stage` at start), `--stage=<arena>/<variation>` (M16: start at stage 2 there), `--boss` (M22: start at the boss with the stated `--big` and 1 + 3 charges), `--pool=starter|all` (read-only snapshot, default starter), `--save=<path>` and `--keep-save` (chain through a file).
- `[botrun]` adds stages, the variations played, charges earned/used, the boss result, and real and game time per stage.
- **`MAX_FRAMES`** counts real frames. M14 measures M13's real-to-game ratio per genre; `MAX_FRAMES = 60 × 60 × ceil(1.5 × 18 min × worst ratio)`, starting at 45 min, recomputed at M24.
- Bot numbers measure pacing only (memory: invincible bots for length, mortal bots for time-to-death by forced genre). The milestone reports say which numbers came from the bot.

---

## 10. Milestones

| # | Milestone | Builder gate | Owner gate |
|---|---|---|---|
| M14 | AI layer + medium tier + option D | 1.1–1.3: `is_medium`, `boss_only`, DB rules, `RunState.ai` with add/remove/expire, `ai_dependents_of`, `can_add_ai_list`, previews with the AI layer, snapshot; invariant tests ≥250 sequences with AI ops and fixture mediums; gravity pair becomes medium and leaves small offers; forced gravity card removed; `get_big_offer` checks `stack` + `ai`; charges (1 + per clear, stubbed per run), AI-only `can_revert`, history AI section; `ai_scaffold_at_prompt` (data-selected); bot AI rollbacks; F2 AI console; smoke matrix pinned counts set to 63 for every slot; check.ps1 prints the test duration, and the report records M13's suite runtime and M13's real-to-game ratio per genre; ROADMAP 1.4, 1.5 and section 4 updated with the 2026-11-20 decisions, Phase 3 marked current. **Numbers:** 16-seed bot sweep, every run reaches its report; every odd seed without Turn-based logs ≥1 `revert_used` with owner `stage` and 0 stack reverts | **G5 on the existing M13 build** (no new build): does Turn-based feel different from B1? |
| M15 | Arenas as data | 1.5: `ArenaLayout`, Lab identical block for block, 5 more layouts, `load_arena` + `arena_changed` with TurnClock full re-enter, `add_blocks`/`arena_blocks_changed`, `clear_hostiles` with in-flight spawns, `RING_LIMIT` derived, per-layout validity and reachability on **every** arena (Core included), `--arena` and `--ai` bot flags. **Numbers:** the bot plays 60 s in each arena in each genre, plus the Core under `gravity_on` and `gravity_on`+`gravity_reversed`, with 0 errors and 0 spawns inside blocks; screenshots of each arena in the report | — |
| M16 | Stage flow | Sections 2–5 with the mediums `gravity_on`, `gravity_reversed`, `close_camera`, `lights_out` (+ `darkness`): `StageDB`, `StageDef.kind`, 3 stages (temporary: the run is won at stage 3 clear), RunLoop sub-states, deploy, stage clear, `stage_rate`/`stage_cap`, BIG at stage ends, stage choice panel, hidden defaults and reveal, earned charges, carry rules, content rule test, telemetry schema 2, bot stage answers and `--stage`, cross-stage determinism test, hidden-default tree-walk test; scaffold removed. **Numbers:** invincible 16-seed sweep completes 3 stages on every seed; per-stage median game time within ±15% of 2.4 (180 / 300 / 300 s); 0 `stage_fallback` with the starter set under none, B1 and B2; every stage-2 and stage-3 run has a live AI rollback target | — |
| M17 | Stage mediums | `ice_floor`, `low_gravity` (+ `friction_mult`, `slip_tiles`, slide resolved in step 1), their variations (8.1), one behaviour test each, B2 danger-exactness with `ice_floor`, `lights_out` and `close_camera` live and across a deploy. **Numbers:** M16's sweep numbers still hold | — |
| M18 | New smalls | 8.3: 10 new smalls (2 starter) and the M18 rule fields of 1.4; parity rule; smoke matrix rework (11) with pinned counts per slot. **Numbers:** mortal-bot time-to-death, starter pool vs full pool, medians within ±15% (16 seeds each) | — |
| M19 | Save + pool growth | 1.7 and 7: `Progress` (inert by default), starter pool, shipping (1 taste + 1 agenda; 0 + 2 after an unrated run), arena unlock by reaching, NEW marks, start screen line and reset; round-trip, missing, missing-key, corrupt, higher-version (reset disabled), unknown-id, NEW-survives-an-unfinished-run tests; real save file untouched by the suite (test). **Numbers:** 5 chained invincible bot runs (`--save --keep-save`) ship exactly 2 locked mutations in each of runs 1–4 (real pool 10 → 18, all 8 locked smalls), run 5 ships nothing and its report says so, `foundry` unlocks after the first run that reaches stage 3; a second chain with the same seeds gives the identical file | — |
| M20 | Enemies + pacing | 8.5: bomber and lancer (B2 roles per the G5 answer), `stage_enemy_mix`, B2 danger-exactness with bombers and lancers; stage pacing retuned. **Numbers:** invincible 16-seed sweep, per-stage medians within ±15% of 2.4 | — |
| M21 | Playtest build | Windows export (marks BIG, MED and BOSS, stages counted on the boot line), a one-page playtest sheet; a scripted parse of a live telemetry line asserts schema 2 and every 9.3 key | **G7 — real human playtest, before the boss.** At least 3 full runs over 2 sessions, so pool growth shows. Do stages give a run a shape? Does stage 1 still read as the beginning, or does it drag? Is a hidden default found and understood? Is rolling one back satisfying? Is Turn-based different from B1 (G5 again)? Owner picks the 3rd big |
| M22 | Boss | Section 6: the Core body, `damage_taken_mult` and armor, opening push, pushes, phases, cap, relock, the 4 boss-only patches, B2 push timing, `--boss`; `boss_hp` set from measured bot DPS. **Numbers:** invincible 16-seed `--boss` sweep (1 + 3 charges): median boss time 240–360 s, ≥ 4 pushes on every seed, ≥ 1 rollback on every seed; danger-exactness with each boss push under B2 | **G8:** does the boss make rollbacks feel like a weapon? |
| M23 | Third big patch | 8.4, the owner's pick: rules, components, bot policy, acceptance numbers, smoke matrix, B1/B2 genre comparison | **G9:** does it stand apart from B1 and B2? |
| M24 | Run retune + export | Full-run length, boss duration, stage pressure; `MAX_FRAMES` recomputed; export rebuilt. **Numbers:** invincible 16-seed full runs: median real time 20–25 min (ROADMAP), game time 16–20 min, boss 4–6 min | **G10:** v4 playtest build |

Check, commit and report rules: as in v2 section 10. `tools/check.ps1` is green before every commit. Each milestone gets a tag (`m14`...) and a milestone report: what was built, check output, proxy numbers (saying which came from bots), decisions and tuning, known issues, what is untested.

**Why this order:** the AI layer touches the reversibility invariant, so it goes first; G5 is asked there because later milestones build B2 content. The arena swap is the riskiest seam in the scene graph (the TurnClock state, the camera, the spawner, in-flight spawns). Stage flow needs both, and is split from the stage mediums so each has a numeric gate. The new smalls come **before** the save, because shipping needs locked content: with only the 6 kept smalls every one is a starter, and the save's gate would pass vacuously. G7 comes before the boss, as ROADMAP open decision 7 asks.

**Cut order if needed (first to last):** `firewall` → `shield_wave` → arena variations beyond 2 legal per big (the content rule must still hold) → named non-starter smalls, keeping ≥ 6 locked (cut `elite_enemies`, then `dash_shockwave`) → the lancer → NEW marks and the start screen line → `foundry` → the 3rd big (moves to v5) → the bomber. **Never cut:** the AI layer and its invariant tests, option D and earned charges, BIG prompts at stage ends, the stage choice, hidden defaults, the save's versioning and test isolation, the G5 question, the G7 playtest, the boss with `spawn_surge` and `core_regen`, telemetry.

---

## 11. Tests (additions to v2 11 and v3 8)
- **Extended invariant:** random sequences of apply / revert / swap_big / add_ai / remove_ai / expire_ai / reset (≥250, seeded). Fixtures: a medium with rules, a component and a listener; a medium that requires another; a medium that conflicts with fixture big B; a small that conflicts with a medium; a boss-only fixture that adds arena blocks. No ghost: after every op, every id in `ai` is live and every live AI component's patch is in `ai`.
- **DB rules:** small requiring an AI-tier patch rejected; AI-tier requiring a small or a big rejected; two tier flags rejected; mediums and boss-only patches never in `get_offer`.
- **`can_add_ai_list`:** `[gravity_on, low_gravity]` is legal on an empty layer; `[low_gravity]` alone is not; it never reads live `ai`.
- **Option D:** `can_revert` is false for every stack patch; a rollback of `gravity_on` with `low_gravity` live costs one charge and removes both; charges 1 → +1 per clear; `expire_ai` costs nothing and logs `expired`; an AI rollback never writes `Director.reverted`; a boss rollback leaves taste unchanged, a stage rollback lowers it.
- **Big offer:** with an AI `gravity_on` live, `get_big_offer` never offers `turn_mode`; a swap preview built with a live AI gravity change plays the gravity safety.
- **Stage flow:** 3 stages + boss in order; carry rules (stack, big, HP, charges kept; hostiles, spawner ramp, wave and stage multipliers, stage counters reset); BIG prompts at the ends of stages 1 and 2 only; nothing between stage 3 and the boss; the stage offer is built after the BIG swap's `transition.finished` (it sees the new big); `poll()` opens no prompt outside PLAY; deploy plays the gravity safety when a default changes gravity; stage pressure survives the wave (`stage_rate` × `phase_rate`).
- **Arena swap:** spawn then `clear_hostiles` in the same frame leaves 0 hostiles 2 frames later; under B2, a deploy started mid-turn puts the player at the new `player_start` after the next turn, with an empty claim set and a fresh danger map; a free-tile query after a swap reads the new arena; `arena_blocks_changed` never moves the player.
- **Determinism across stages:** a same-process double run (same seed + same save + same choices, invincible bot) through stage 1 → deploy → stage 2 → deploy → stage 3 → the boss. Hash, per second of game time, the player position, the enemy set, the `ai` ids and owners, and the boss pushes, as in v3 3b.8 "same seed, same run".
- **Stage choice:** never the stage-2 arena at stage 3, never an illegal variation (Turn-based → no gravity), the variation pick follows the exact order of 3, same seed + same save + same choices → same cards, agenda card present with 2 candidates (also after an unrated run), the card text never contains a default patch's title or id, NEW only on arena cards, fallback with 0 candidates.
- **Content rule:** per big value, starter set and full set: ≥ 3 arenas with a legal variation, no arena with exactly one legal variation, distinct first patches; `StageDB.problems()` empty; no title or blurb contains a medium's title or id.
- **Hidden default:** a tree walk, every frame of a stage, of all `Label`, `RichTextLabel` and `Button` text plus the transition band and toasts, for each live default's title and id: absent until rollback or stage end; present in the report.
- **Arenas:** the Lab is identical to M13 (block list); each layout's spawn tiles are free and valid in every gravity state; ledges are reachable both ways on every arena; no layout chunk overlaps `core_rect`.
- **Save:** round-trip; missing → starter; missing key → that key's default; corrupt → `.bad` + starter + a warning, no error; higher version is never overwritten and reset is disabled; unknown ids dropped; nothing written when not live or not finished; NEW survives an unfinished run; inert by default (a fresh test reads no file); the test path never equals the default; the default file's existence and mtime are the same before and after the suite.
- **Pool growth:** starter = the `starter` flags; ships exactly 1 + 1, and 0 + 2 after an unrated run; the taste pick follows a tag the run liked; the agenda pick is the least liked; deterministic for the same seed, save and taste; a run that did not clear stage 1 ships nothing; reaching stage 3 unlocks `foundry`; report ratings do not change the ships.
- **Short offers:** a greedy walk of run 1 on the starter pool asserts what each of the 6 prompts shows (count, agenda presence).
- **Boss:** armor at n = 0..3 through `damage_taken_mult`; the opening push at 0 s; cap expires the oldest; relock; no gravity push under B2; under B2 a push lands only between turns and `firewall` never covers `P` or a held tile; no patch attaches a component to the Core; `horde_mode` does not change the Core's max HP; Core death → win and report; a 1-HP death in the boss stage → lose.
- **New smalls, mediums and enemies:** one behaviour test each, plus B2 danger-exactness (the v3 3b.8 test extended) across a deploy, with each B2-legal medium (`ice_floor`, `lights_out`, `close_camera`), with bombers and lancers, and with each boss push (`spawn_surge`, `shield_wave`, `firewall`).
- **Smoke matrix:** M14 sets the pinned counts to 63 for every slot (gravity leaves the small pool). Reworked at M18 (all subsets no longer fit): per big value, every single small and every pair with no AI patch; per big value × each legal variation, 20 seeded random legal subsets of size 3–8; each arena, one bot run with 3 random smalls. Expected counts are computed from the legality filter and asserted against a pinned number per slot. **Budget:** check.ps1 prints the suite duration from M14 on; the M14 report records M13's baseline; over 8 min is reported as a known issue and fixed before the next milestone.
- **Updated:** `test_director` (charges, no self-rollback, the history UI), `test_mutations:76` (small/medium split), `test_big_slot` gravity tests (gravity as AI patch), `test_gravity` and `test_entities` (per layout), `test_run_loop` (stage waves instead of RC), `test_playtest_build` (MED and BOSS marks, the stages boot line), the folder-isolation grep (1.6 allowance).

---

## 12. What v4 must answer
1. Do stages give a run a shape, or do they feel like a loading screen between the same fights?
2. Is a hidden default patch discovered and understood by playing, or is it just confusing?
3. Do rollbacks feel like a weapon against the AI (stage defaults, then the boss)?
4. Does "new in this build" make the next run worth starting?
5. Is Turn-based a different game from B1 (G5, asked at M14 and again at G7)?
6. Does adding an arena, a medium or a boss patch touch only its data or its own folder?
7. Does stage 1 still read as the beginning, or does the flat base game drag?

## 13. Still open (each with a proposed default)
- **Turn-based vs gravity stages:** filter gravity variations after a Turn-based pick (section 5). Owner to confirm.
- **End of stage 3:** no BIG prompt and no stage choice; the boss inherits the genre (2.1). Owner to confirm.
- **Stage 1 default patch:** none, so stage 1 is the pure base game and the starting charge waits for stage 2.
- **Stage 1 length:** ~180 s (2.4) so the flat opening stays near M13's; the first genre still arrives ~3× later than in M13 (60 s). Alternative: keep 270 s like the other stages. Owner to confirm; G7 asks.
- **What counts as a finished run (ships and unlocks):** a run that cleared stage 1. Alternative: any live run of at least 3 min of game time, so a struggling player still sees the pool grow. Owner to confirm.
- **Arena unlocks:** by reaching (`unlock_by_reaching`, foundry at stage 3), no taste ship for arenas, NEW on the arena only. "Arenas as starts" (ROADMAP 1.2) is dropped for v4. Alternative: the AI ships one locked arena per run by taste, with an agenda rule. Owner to confirm.
- **Ships use in-run taste only:** the report's ratings feed the next run's offers, not the ships. Alternative: ship in `save_notes()` (and the close-window path) and show the result on the next start screen.
- **Variation vs the player's patches (ROADMAP open decision 5):** a variation that conflicts with a stacked small is not offered, and a small that conflicts with a live default is withheld for that stage (5). Owner to confirm.
- **Boss patches are named** (only stage defaults are hidden). Alternative: the boss's pushes are hidden too until rolled back.
- **Boss rollbacks do not feed taste** (only stage-default rollbacks do). Alternative: both count, as ROADMAP 1.3 rule 3 reads literally.
- **Run 1's short offers:** with 8 starter smalls and 6 prompts, the last prompts show 3 or fewer cards with little lean (7). Accepted as the cost of the ~8 starter set; the owner may want to know.
- **Boss charges:** unchanged (owner decision 2). If G8 finds too few for the boss, the owner decides.
- **When a hidden default is named:** on rollback or at stage end only. Alternative: the AI names it after 60 s.
- **The boss's win condition:** Core HP with armor per live patch. Alternative: survive N pushes.
- **HP across stages:** kept, plus 1 heal at each clear.
- **The third big:** Stealth or On the beat, picked at G7.

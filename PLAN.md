# Build Plan v2 — Core Prototype (working title: "Alone Alone Lab")

**For:** Fable 5.2 (builder agent)
**Goal of this build:** a small playable prototype that proves *changing a game's fundamental rules mid-run is technically clean and fun*.
**Engine:** Godot **4.7.x stable**, pinned for the whole prototype (never 4.8), standard build, GDScript. The simulation is 2D.
**Supersedes:** `PLAN.v1.md` (kept for reference). v2 folds in the pre-build audit and the owner's decisions.

---

## 0. Read this first

You are building the **core** of a meta-roguelike where a fictional AI developer proposes "patches" that rewrite the game while the player plays it. Narrative, AI personality, meta-progression and UI experiments come later and are **out of scope**.

### The three non-negotiable principles

1. **One world, many genres.** ONE simulation. A "genre" is a set of values in `WorldRules`. Top-down vs platformer = gravity off vs on, in the same level, with the same entities. Nothing branches on "mode".
2. **Run state = base + ordered patch list.** State falls in three classes:
   - **(A) Derived** — `WorldRules` and everything computed from it (effective max HP, camera zoom, body motion mode, `Engine.time_scale`). Always recomputed from `base + stack`; never stored where a recompute cannot overwrite it.
   - **(B) Patch-owned** — components and EventBus connections added by a patch. Tagged with the patch id and removed on revert.
   - **(C) Simulation** — positions, velocities, damage taken, live entities (including ones a patch spawned), kills, the run log. Never touched by apply/revert.
3. **Simulation is separate from presentation.** Entities are simulation objects with visuals as replaceable children; nothing in gameplay logic reads the screen, the camera or the mouse position directly. This is what keeps a later first-person view possible (section 15).

If a design choice conflicts with a principle, stop and flag it.

### Out of scope (do not build)
- Meta-progression, unlocks, saves between runs (the telemetry file in section 8 is not a save: nothing reads it back)
- AI narrative arc, personality evolution, menu takeovers, music changes
- Real generative AI — the "AI" is scripted
- Final art/audio — colored shapes, simple particles, generated placeholder SFX
- Any 3D or first-person rendering (seams only, section 15)

---

## 1. Project layout

```
res://
  core/
    event_bus.gd          # autoload "EventBus" — signals only
    world_rules.gd        # class_name WorldRules (Resource)
    base_rules.tres       # WorldRules defaults
    run_state.gd          # autoload "RunState" — stack, recompute, spawn, reset, pause owner
    mutation.gd           # class_name Mutation (Resource, base class)
    mutation_db.gd        # autoload "MutationDB" — loads all mutation resources
    component.gd          # class_name Component (Node, base class)
    damage_info.gd        # class_name DamageInfo (RefCounted)
    player_input.gd       # PlayerInput seam; human_input.gd, bot_input.gd
    input_setup.gd        # autoload — registers InputMap actions in code
    tuning.gd / tuning.tres   # autoload "Tuning" — every non-rule constant
  components/             # Health, Mover, Shooter, Dasher, Floating, LandingSlam, ...
  entities/               # player, enemy_chaser, enemy_shooter, enemy_tank, projectile, explosion
  systems/                # spawner.gd, transition.gd, camera_rig.gd
  mutations/<id>/         # <id>.tres (+ <id>.gd if it has behaviour, + its own components)
  director/               # ai_director.gd, dialogue.gd (generic lines only)
  ui/                     # prompt_panel, patch_history, hud, debug_overlay, report_screen, start_screen
  levels/                 # arena.tscn + arena.gd (blocks as data)
  tests/gut/              # GUT tests
  tools/check.ps1         # import + boot + tests + log scan
```

- Autoload scripts declare no `class_name`.
- **Vocabulary:** a *Mutation* is a definition in the pool; a *patch* is a mutation currently in the stack.
- **Adding a mutation** touches only new files under `mutations/<id>/`. Its card title, description and AI lines are exported fields on its `.tres`. Exception, stated honestly: a mutation needing a new rule adds one field to `WorldRules` and one reader in the owning system.
- **Authoring:** scripts, scenes and resources are written as text files and verified headless. Scenes stay thin (root, collision shape, placeholder visual, component children); anything repetitive is built in code. The editor plugin is used only for running the game, screenshots and logs.

---

## 2. Core contracts

### 2.1 `WorldRules` (Resource)
Plain data. Every field is `@export` and a value type (no Array/Dictionary/Resource fields).

| Field | Type | Base |
|---|---|---|
| `gravity_enabled` | bool | false |
| `gravity_dir` | Vector2 | (0, 1) |
| `gravity_strength` | float | 1800 |
| `jumps` | int | 0 |
| `auto_attack` | bool | false |
| `spawn_rate_mult` | float | 1.0 |
| `max_enemies` | int | 25 |
| `enemy_hp_mult` | float | 1.0 |
| `camera_zoom` | float | 1.0 |
| `projectile_max_bounces` | int | 0 |
| `projectile_gravity_scale` | float | 0.0 |
| `time_scale` | float | 1.0 |

The two `projectile_*` fields apply to player projectiles. Composition convention for `apply_rules`: `*_mult` and zoom are multiplied, counts are added, bools are only turned on, `gravity_dir` is flipped (`= -gravity_dir`), never assigned.

### 2.2 `EventBus` (autoload)
Signals only. `entity_spawned(e)`, `entity_damaged(target, info)`, `enemy_killed(e, info)`, `player_hit(info)`, `player_died`, `projectile_fired(p)`, `projectile_hit(p, target, pos)`, `projectile_hit_wall(p, pos, normal)`, `player_jumped`, `player_landed(pos, impact_speed)`, `player_dashed`, `patch_applied(m)`, `patch_reverted(m)`, `rules_changed(rules)`, `milestone_reached(id)`, `run_started(seed)`, `run_ended(outcome)`.

- `DamageInfo`: `amount`, `kind` (&"projectile"/&"explosion"/&"contact"/&"slam"), `faction`, `source_patch: StringName` (empty = base weapon), `pos`. All damage goes through `Health.take(info)`, the only emitter of `entity_damaged` / `enemy_killed`. Projectiles and explosions copy `source_patch` from their creator. Kill attribution is last hit.
- Hit signals fire on **every** contact, before the despawn decision.
- Handlers validate node arguments (`is_instance_valid`) and never free or add physics nodes synchronously; they go through `RunState.spawn()`.
- Synergies emerge from mutations listening to events, never from combo code.

### 2.3 Entities, components, spawning
- **Entity** = any node in group `entities`, plus one kind group: `player`, `enemy`, `player_projectile`, `enemy_projectile`. Entities register in `_ready`.
- **One spawn path:** `RunState.spawn(scene, pos, params) -> Node` (null at cap). It checks the hard caps in Tuning (enemies, projectiles), sets fields, adds the node deferred, runs every patch's `on_entity_spawned` in stack order, then emits `entity_spawned`. `rules.max_enemies` gates only the wave spawner; patch-spawned enemies bypass it but obey the hard cap. Caps never cull existing entities.
- **Component** (Node): has `source_patch: StringName` (empty = innate). Attached only through `Component.attach(entity, script, source_patch)`, a no-op if already present from that patch. Components read `RunState.rules` live and never write persistent fields on their host; they undo anything else in `_exit_tree()`.
- **Height:** every Mover has a scalar `height` (0 = on the ground plane) used only when gravity is off (section 5, `jump_button`). An entity with `height > 0` is airborne: it takes no contact damage and ground-level projectiles pass under it. Visual: sprite scale-up plus an offset shadow.
- **Health** stores `base_max_hp` and `hp_ratio`. Effective max = `base_max_hp * rules.enemy_hp_mult` (enemies), read live; the ratio is preserved when rules change.
- **Collision layers (fixed at M0):** 1 world, 2 player body, 3 enemy body, 4 player hurtbox, 5 enemy hurtbox. Enemy bodies collide with the world only; enemies keep apart with a soft separation push.
- **Projectile:** moves by a swept query each physics tick that yields collider, position and normal (ray or `move_and_collide`; no overlap-signal bullets). On a wall hit it bounces (`velocity.bounce(normal)`, restitution ~0.8) while its bounce count `< rules.projectile_max_bounces`, otherwise it despawns. It is consumed on an entity hit. When `rules.gravity_enabled`, player projectiles accelerate by `gravity_dir * gravity_strength * rules.projectile_gravity_scale`; enemy projectiles never arc. Max lifetime 3 s. Spawned from a muzzle point checked to be outside solids.

### 2.4 `Mutation` (Resource base class)
```gdscript
class_name Mutation extends Resource
@export var id: StringName               # equals the folder/file name
@export var title: String                # card title
@export var description: String          # one-line effect summary
@export var line_proposal: String        # AI lines live on the resource
@export var line_applied: String
@export var line_reverted: String
@export var tags: Array[StringName]
@export var requires: Array[StringName]  # mutation ids only, all-of
@export var conflicts: Array[StringName] # mutation ids only, checked both ways
@export var weight: float = 1.0
@export var is_mode_switch: bool = false # selects the long transition presentation

func apply_rules(rules: WorldRules) -> void: pass    # pure
func on_entity_spawned(entity: Node) -> void: pass   # attach components; must be idempotent
func enable() -> void: pass                          # connect via _listen() only
func _listen(sig: Signal, method: Callable) -> void  # records the connection; no lambdas
func disable() -> void                               # base class disconnects everything recorded
```
Mutation resources are **stateless** (loaded `.tres` files are shared instances that outlive a run). Any per-run state lives in `RunState.patch_state[id]`, cleared on revert and reset.

### 2.5 `RunState` (autoload)
- `base_rules`, `rules` (computed), `stack: Array[Mutation]`, `patch_state`, the run log, the RNG streams.
- `can_apply(m)`: not in stack, requires met, no conflict.
- `apply(m)`: assert `can_apply` → push → `recompute()` → `m.enable()` → `on_entity_spawned` on all live entities → emit `patch_applied`.
- `revert(m)`: revert dependents first (reverse stack order) → remove → `m.disable()` → strip its components (`remove_child` then `queue_free`, so removal is synchronous) → `recompute()` → emit `patch_reverted`.
- `recompute()`: `rules = base_rules.duplicate()`; each patch's `apply_rules` in order; emit `rules_changed`.
- `reset(seed)`: revert everything through the normal path, clear log and `patch_state`, reseed, `Engine.time_scale = 1`, unpause. "New build" calls only this, then reloads the scene. Tests call it in setup.
- `live_entities()`: group members that are valid and not queued for deletion.
- **Pause and time, single owner:** a set of pause reasons `{prompt, history, transition, report}`; the tree is paused while the set is non-empty. Gameplay is pausable; UI and transition nodes use `PROCESS_MODE_ALWAYS`. RunState is the only writer of `Engine.time_scale`, which is never set to 0 and is restored from `rules.time_scale`. Nothing but `apply_rules` ever writes a rule.
- **RNG:** separate `RandomNumberGenerator` streams for the Director and for gameplay, both derived from the run seed. Reproducible means: same seed + same choices and reverts → same offers. Gameplay is not replayable.
- **Run log:** patch applied/reverted with game time, offers and pick per prompt, kills and damage by `source_patch`, reverts with HP at the time, Patch History opens.
- **Version label:** monotonic build counter in the run log. Every apply or revert is a new build (`v0.4 Revert: Implement gravity`).

**Invariant (must be tested):** after any legal sequence of apply/revert/reset leaving stack S, these equal the result of `reset()` followed by applying S in order on the same fixture: (1) `rules`, compared field-wise; (2) per entity, the sorted list of (component script, `source_patch`); (3) per EventBus signal, the set of mutation-owned connections.

### 2.6 `MutationDB` (autoload)
Enumerates with `ResourceLoader.list_directory("res://mutations/")` (never `DirAccess` on `res://`), loads every Mutation `.tres`, validates (unique id, id equals file name, referenced ids exist), and stores them **sorted by id**.

---

## 3. Base gameplay (zero mutations)

- **Display:** base viewport 1280×720, stretch `canvas_items`, 60 physics ticks. Tile unit 48 px.
- **Input (fixed meaning in every rule state):** `move_*` WASD/arrows/left stick · `aim` mouse/right stick · `shoot` LMB/RT · `dash` Shift or RMB / LT · `jump` Space / A · `patch_history` Tab/Select · `pause` Esc/Start · `choose_1..3` · debug F-keys. W/Up never jumps. `jump` does nothing while `rules.jumps == 0`.
- **PlayerInput seam:** entities never call `Input`. The player reads a `PlayerInput` node (`move`, `aim_dir`, `fire`, `dash_pressed`, `jump_pressed`). `HumanInput` fills it from InputMap; `BotInput` fills it from a simple policy (aim at nearest enemy, fire, strafe from threats, jump when blocked) and exists for automated runs.
- **Player:** `CharacterBody2D`. Movement with slight acceleration/friction. Shoot cooldown ~0.18 s. Dash: direction = move input (falls back to facing, never the mouse), ~3.5 tiles in 0.15 s with i-frames, cooldown ~0.8 s, same definition in every rule state. 5 HP, brief invulnerability on hit.
- **Enemies (3):**
  - *Chaser* — runs at the player, contact damage.
  - *Shooter* — keeps distance, fires slow projectiles. Has `Floating` (ignores gravity), as do its projectiles.
  - *Tank* — slow, high HP, knockback-resistant.
  - Movement without gravity: steer at the player with wall sliding and a two-ray obstacle avoidance; if no net progress for 2 s, wander 1.5 s.
- **Arena:** ~2.5 × 1.5 screens (about 66 × 22 tiles). Blocks are axis-aligned rectangles declared as data (`Array[Rect2]` on `arena.gd`), built into one StaticBody2D at `_ready`. Border one tile thick on all four sides (it is the floor under gravity and the ceiling-floor under reversed gravity). Three layout rules: every ledge is reachable with the tuned jump without dash; no enclosed pockets deeper than the jump height from floor or ceiling; open vertical lanes so top-down movement is not a striped maze. 12–16 spawn markers in free space, valid in all gravity states; the spawner picks ones off-camera and away from the player.
- **Camera:** `CameraRig` follows the player with arena limits and derives zoom from `rules.camera_zoom`. It never rotates.
- **Minimum feedback (before the feel gate):** hit flash, knockback, small screen shake on player hit, death puff (CPUParticles2D).
- **HUD:** HP, kill count, build version, `Rollbacks: 2 [Tab]`.

---

## 4. Gravity

`Mover` derives body settings from rules every physics tick, never from a stored mode:
- `rules.gravity_enabled`: `motion_mode = GROUNDED`, `up_direction = -gravity_dir`, velocity accelerates along `gravity_dir`. Lateral movement is the input with its component along `gravity_dir` removed (screen-space left/right stays left/right, even reversed). Jump impulse along `up_direction`.
- otherwise: `motion_mode = FLOATING`, `wall_min_slide_angle = 0`.
- Starting tuning: gravity 1800 px/s², jump velocity 720 px/s (apex 3 tiles), ×1.4 gravity when falling, terminal 900 px/s, variable jump height, coyote 0.10 s, jump buffer 0.10 s.
- Jumps available = `rules.jumps` (air jumps included). `gravity_on` contributes 1.
- `player_landed` is emitted when the player touches down above a small impact speed (or when `height` returns to 0).

**What gravity affects:** player, chasers, tanks, split children, debris particles. Not shooters or enemy projectiles. Player projectiles only through `rules.projectile_gravity_scale`.

**Chasers under gravity** (rules read sensors, not mode): walk toward the player along the lateral axis; hop when a low wall is ahead; hop when the player is above and an overhead ray is clear; if overhead is blocked keep walking, do not reverse under a ledge; same stuck-timer wander. Tanks use the same rules with a long hop cooldown.

**Readability cues (rule-driven, no art):** background is a floor grid without gravity and a gradient darkening toward `gravity_dir` with it; blocks show a bright strip on their standable face.

**Transition** (`systems/transition.gd`). Safety handling runs whenever `gravity_enabled` or `gravity_dir` differs between old and new rules, on apply and on revert:
1. Pause (reason `transition`), optional 0.15 s slow-down that ignores time scale.
2. Overlay: terminal text from the AI over the **still-visible** frozen world; the camera does not cut. `is_mode_switch` selects the long version (~0.8 s, "compiling…"); otherwise a short one (~0.3 s). Reverts show "rolling back vX.Y".
3. Apply or revert the patch.
4. Unpause — everything falls/settles under the new rules. Velocity along the old gravity axis is cleared; held inputs need a fresh press.
5. Grace: enemies deal no damage for a tunable ~1.5 s of game time.

---

## 5. Mutation set (8)

| id | Kind | Effect | Requires |
|---|---|---|---|
| `gravity_on` | rules, mode switch | `gravity_enabled = true`, `jumps += 1` | — |
| `gravity_reversed` | rules | `gravity_dir = -gravity_dir`; short transition | `gravity_on` |
| `jump_button` | rules + component | `jumps += 1`; player gets `LandingSlam` | — |
| `auto_attack` | rules | Shooter fires at the nearest enemy in line of sight when fire is not held | — |
| `horde_mode` | rules | `spawn_rate_mult *= 3`, `max_enemies *= 3`, `camera_zoom *= 0.75`, `enemy_hp_mult *= 0.6` | — |
| `bouncing_projectiles` | rules | `projectile_max_bounces += 3`, `projectile_gravity_scale += 0.5` | — |
| `explode_on_hit` | event | On player-projectile wall and entity hits: small AoE | — |
| `enemies_split` | event | On `enemy_killed` of a generation-0 enemy: spawn 2 smaller, weaker copies | — |

Details that must hold:
- **`jump_button`** ("Add a jump button") replaces v1's `double_jump` and has no requirement. Without gravity, `jumps` is 1: Space performs a hop on the `height` axis (~0.35 s airborne, passes over enemies and ground projectiles, still blocked by walls). With gravity, `jumps` is 2: a double jump. `LandingSlam` listens for `player_landed` and deals a small AoE (damage + knockback, `kind = &"slam"`) around the landing point, so hopping onto enemies in top-down and stomping them in platformer are the same code. It is the set's component-type mutation.
- **`auto_attack`** is an input source for the one existing Shooter, on the one cooldown. Holding fire aims manually instead. Fire rate never doubles.
- **`explode_on_hit`**: player projectiles only. The explosion is a one-shot shape query; it damages enemies only, applies knockback to everyone including the player, and never re-emits projectile hit signals. Spawned through a plain `spawn_explosion(pos, radius, source_patch)` helper.
- **`enemies_split`**: `generation` lives on the entity. Children persist after revert.
- **`gravity_reversed`**: camera does not rotate, left/right unchanged, jump pushes along `up_direction`, sprites flip vertically. Built last; first cut if the schedule slips.

Each mutation ships a card title, a one-line description and its AI lines on the resource.

**Acceptance:** any legal subset, in any order, runs without errors (smoke matrix, section 11), and `bouncing_projectiles + explode_on_hit + gravity_on` gives arcing explosive ricochets (≥2 bounces on a projectile and ≥3 explosions within 10 s) with no mutation id referenced outside its own folder.

---

## 6. AI Director (scripted)

- **Trigger:** a prompt opens when (counted kills ≥ N **and** ≥ `T_min` of game time since the last prompt) **or** `T_max` has passed. Only spawner-spawned, generation-0 enemies count. Start: N = 15 then +10, `T_min` 60 s, `T_max` 150 s; set N from measured kills/min at the feel gate.
- **Offer:** 3 mutations sampled without replacement, weighted, from those passing `can_apply` and not previously reverted. Fewer than 3 eligible → show that many; none → skip and log. No skip or reroll.
- **Gravity guarantee:** if `gravity_on` is not in the stack at prompt 2, prompt 2 is a single mandatory card ("I already merged it"). Controlled by a Tuning flag.
- **Hotfix:** each applied patch heals 1 HP (max 5).
- **Prompt panel:** pauses (reason `prompt`), opens deferred at end of frame, ignores input for 0.5 s and needs a fresh press; keyboard 1/2/3, mouse, gamepad focus. Same grace as the transition on close.
- **Interface:** `should_prompt(ctx) -> bool`, `get_offer(ctx) -> Offer`, `on_choice(offer, m)`, `on_revert(m)`. `Offer` carries `cards`, `line`, `prompt_index`, `mandatory`.

---

## 7. Revert / patch history

- `Tab` opens **Patch History** (pauses; unavailable during prompt, transition and report): the append-only build log with version labels.
- **2 reverts per run**, free. One revert action costs one charge even when it cascades to dependents (warning shown first); a cascade plays one transition.
- A one-time AI hint points at Tab after the first patch.
- Every revert and every history open is logged.

---

## 8. Run loop

- **Target:** 6–10 minutes of unpaused time, 4 prompts.
- **Win:** after the 4th prompt, a "release candidate" wave (~90 s). The spawner owns the phase curve outside `WorldRules`: effective rate and cap are phase multipliers times the rule values. Survive → `v1.0 shipped`.
- **Lose:** HP reaches 0.
- **Playtest Report** (both outcomes): time, kills, version reached, build log, kills and damage by source, reverts used, one AI comment line. Buttons: "New build", "Copy report".
- **Telemetry:** on run end append one JSON line to `user://playtest/runs.jsonl` (build version, seed, session id, run index, outcome, duration, apply/revert events with timestamps, offers and pick per prompt, kills by source). Never read back by gameplay.
- **Start screen:** Start button, seed field, fullscreen toggle, master volume.

---

## 9. Debug tools (first code milestone)

`F1` overlay (rules, stack, seed, entity count, FPS, physics time) · `F2` mutation console (apply/revert anything) · `F3` invincibility · `F4` spawn wave · `F5` restart with same seed · `F6` open prompt now · `F7` toggle bot.

---

## 10. Milestones

Each milestone has a **builder gate** (objective, blocks the next milestone) and some have an **owner gate** (the builder stops, hands over a build and a short report, and waits).

| # | Milestone | Builder gate | Owner gate |
|---|---|---|---|
| M0 | Setup | `git init` + .gitignore (`.godot/`); project boots headless with a banner line and no error lines; GUT smoke test passes through `tools/check.ps1`; InputMap, collision layers, PlayerInput seam, Tuning in place | — |
| M1 | Thin core + skeleton | WorldRules, RunState, EventBus, Mutation, Component, MutationDB, debug tools; greybox arena; component-built player and one chaser; invariant tests green | — |
| M2 | Gravity spike | `gravity_on` toggled live from F2, no transition; platformer Mover; chaser gravity rules; 50 seeded toggles leave nothing out of bounds or inside solids; bot reaches every ledge | **G1:** is the flip interesting, is the jump acceptable, does the arena read both ways? |
| M3 | Combat feel | Shooting, dash, 3 enemies, spawner, minimum feedback, HUD; perf smoke (75 enemies + 100 projectiles, FPS and physics time reported) | **G2:** is plain play fun for 5 minutes? |
| M4 | Mutations + transition | All of section 5 (reversed last), transition sequence; section 5 acceptance; smoke matrix green; perf smoke with horde + split + explode | — |
| M5 | Director + UI | Prompt panel, patch history, reverts, pacing rule, mandatory gravity card | — |
| M6 | Run loop | Win/lose, report, telemetry, start screen, restart; 3–5 seeded bot runs end to end with no errors | — |
| M7 | Polish | Transition polish, particles, generated SFX, Windows export that boots and lists all mutations | **G3:** playtest build |

- After adding or renaming a `class_name` script, re-run `--import` before running anything.
- A run passes only if the exit code is 0 **and** the expected summary/banner is present **and** the log has no `SCRIPT ERROR` / `ERROR` / `Parse Error` lines.
- Commit whenever the check is green and a coherent step is done; tag each milestone.
- **Milestone report:** what was built, check output, proxy numbers, decisions and tuning values chosen, known issues and what is untested.

**Cut order if needed (first to last):** gamepad (seam stays) → damage numbers and glitch shader → settings → `gravity_reversed` → AI comment templates → SFX. Never cut: revert, tests, the transition, telemetry.

---

## 11. Tests (GUT, headless)

- **Replay-equivalence invariant** (2.5) over every legal sequence generated by picking uniformly among legal operations (length 5–30, seeded, ≥200 sequences), plus fixture mutations that use `conflicts`.
- **Rules canary:** every `WorldRules` script variable is exported and survives `duplicate()`.
- **Compatibility filter:** the Director never offers a mutation that fails `can_apply`; same seed + same choices → same offers.
- **Listener hygiene:** after `disable()` or `reset()`, no EventBus connection belongs to a mutation.
- **Revert cascade:** reverting `gravity_on` removes `gravity_reversed`, costs one charge.
- **Reset:** after N random applies and `reset()`, stack empty, rules equal base, time scale 1, tree unpaused.
- **Revert of derived stats:** horde applied then reverted leaves a live enemy's effective max HP at base and its ratio unchanged.
- **Scene smoke matrix:** in the real arena with the bot, for each legal subset of mutations: apply, simulate 120–300 physics frames, revert all, simulate 60 more. Assert no log errors, finite in-bounds positions, counts within caps, invariant holds.
- **Pacing:** with kills simulated at 5/s under horde + split, the gap between prompts is never below `T_min`.
- Tests drive choices through `Director.on_choice` and input through `BotInput`; no synthetic mouse clicks.

---

## 12. Engineering rules

- Systems read `RunState.rules`; nothing branches on "mode".
- No combo-specific code. If two mutations need special handling together, flag it.
- Mutations must be fully reversible in classes A and B. If one can't be, flag it.
- Hard caps (entities, projectiles, split generation) live in Tuning and are enforced in `RunState.spawn`.
- Three tunable locations only: `base_rules.tres`, `tuning.tres`, and each mutation's own resource.
- Placeholder visuals: distinct colors per entity type, readable at a glance. Particles are CPUParticles2D.
- Gameplay timers (cooldowns, i-frames, grace, Director timers) run on pausable game time.

---

## 13. What this prototype must answer

1. Is the base gameplay fun between prompts?
2. Does the gravity switch create a real "whoa" moment?
3. Do mutation combinations make players want another run?
4. Is revert ever used, and does it feel meaningful?
5. Does adding a mutation touch only its own folder?

Q2 and Q3 need testers who do not already know the twist.

## 14. Still open
- Who playtests, and how many people.
- Whether to upgrade the installed Godot 4.7.0 to 4.7.2 (changes the machine; the two `godot.cmd` wrappers need fixing afterwards).
- Whether card trade-offs (downsides on every patch) are wanted to make revert matter more.

## 15. Future view: first person (not built now)

A later "Render in first person" patch is possible as a **view of the same flat simulation**: walls extruded from the arena's block rectangles, entities drawn as billboards at their 2D positions, a camera at the player's position looking along the aim direction, and the `height` axis giving jumps. It would be one more rule (`view`) read by the presentation layer, with the simulation unchanged.

Seams this prototype keeps for it, at no extra cost:
- Arena geometry is data, not hand-drawn art.
- Aim is a direction from `PlayerInput`, never a screen position read by gameplay.
- Visuals are replaceable children of simulation entities; the camera is a rig driven by rules.
- `height` exists as a core entity property.

Limits to know now: that view works on the ground plane (gravity off). With gravity on, the world is a vertical slice with no depth, so first person there has nothing to look at; the two would conflict or need a design answer. Free vertical aiming, multi-storey levels and true 3D physics would require a 3D simulation, which is a different foundation from this plan.

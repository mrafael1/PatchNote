# Build Plan — Core Prototype (working title: "Alone Alone Lab")

**For:** Fable 5.2 (builder agent)
**Goal of this build:** a small playable 2D prototype that proves *changing a game's fundamental rules mid-run is technically clean and fun*.
**Engine:** Godot 4.x (latest stable 4.x), GDScript, 2D only.

---

## 0. Read this first

You are building the **core** of a meta-roguelike where a fictional AI developer proposes "patches" that rewrite the game while the player plays it (e.g., "Implement gravity", "Make projectiles bounce"). The full game will later add narrative, an AI personality, meta-progression and UI experiments. **None of that is in scope.** Your job is the foundation everything else plugs into.

### The two non-negotiable principles

1. **One world, many genres.** There are no separate "game modes" with their own players, enemies or levels. There is ONE simulation. A "genre" is just a set of values in `WorldRules` (gravity, camera, auto-attack, spawn rate…). Top-down vs platformer = gravity off vs gravity on, in the *same* level, with the *same* entities.
2. **Run state = base + ordered patch list.** The current game is always computed as `base rules + patches applied in order`. Reverting a patch = remove it from the list and recompute. Never mutate state in a way that can't be recomputed from the list.

If a design choice conflicts with either principle, stop and flag it instead of working around it.

### Out of scope (do not build)
- Meta-progression, unlocks, saves between runs
- AI narrative arc, personality evolution, menu takeovers, music changes
- Real generative AI — the "AI" is scripted (data + simple rules)
- Final art/audio — use colored shapes, simple particles, placeholder SFX
- Main menu beyond a "Start run" button; settings beyond volume + fullscreen

---

## 1. Project layout

```
res://
  core/
    event_bus.gd          # autoload "EventBus"
    world_rules.gd        # class_name WorldRules (Resource)
    run_state.gd          # autoload "RunState" — patch stack + recompute
    mutation.gd           # class_name Mutation (Resource, base class)
    mutation_registry.gd  # autoload "Mutations" — loads all mutation resources
    component.gd          # class_name Component (Node, base class)
  components/             # Health, Mover, Shooter, Bouncy, SplitsOnDeath, ...
  entities/               # player.tscn, enemy_chaser.tscn, enemy_shooter.tscn, enemy_tank.tscn, projectile.tscn
  systems/                # spawner.gd, auto_attack.gd, transition.gd
  mutations/              # one .gd + one .tres per mutation
  director/               # ai_director.gd, dialogue.gd (lines per mutation)
  ui/                     # prompt_panel, patch_history, hud, debug_overlay, report_screen
  levels/                 # arena.tscn
  tests/                  # GdUnit4 (or GUT) tests
```

Each mutation lives in **one script + one resource**. Adding a mutation must not require editing core files.

---

## 2. Core contracts

### 2.1 `WorldRules` (Resource)
Plain data, read by systems every frame. Suggested fields (extend as needed):

| Field | Type | Default (base) |
|---|---|---|
| `gravity_enabled` | bool | false |
| `gravity_dir` | Vector2 | (0, 1) |
| `gravity_strength` | float | 1800 |
| `auto_attack` | bool | false |
| `spawn_rate_mult` | float | 1.0 |
| `max_enemies` | int | 25 |
| `camera_zoom` | float | 1.0 |
| `projectile_max_bounces` | int | 0 |
| `time_scale` | float | 1.0 |

Systems **never** check "which mode are we in". They read rule values.

### 2.2 `EventBus` (autoload)
Signals only, no logic. Minimum set:
`enemy_spawned(e)`, `enemy_killed(e, killer)`, `player_hit(amount, source)`, `player_died`, `projectile_fired(p)`, `projectile_hit(p, target)`, `projectile_hit_wall(p, pos, normal)`, `player_jumped`, `player_dashed`, `entity_spawned(e)`, `patch_applied(m)`, `patch_reverted(m)`, `rules_changed(rules)`, `milestone_reached(id)`.

Synergies must emerge from mutations listening to events, never from hand-written combo code.

### 2.3 `Component` (Node base class)
Small behavior nodes attached to entities (`Health`, `Mover`, `Shooter`, `Dasher`, `Bouncy`, `ExplodeOnHit`, `SplitsOnDeath`, `Floating`…).
- Every component has `source_patch: StringName` (empty = innate).
- Components read `RunState.rules` rather than caching values.

### 2.4 `Mutation` (Resource base class)
```gdscript
class_name Mutation extends Resource
@export var id: StringName
@export var title: String            # shown on the prompt card ("Implement gravity")
@export var description: String      # one-line effect summary
@export var tags: Array[StringName]  # e.g. [&"physics", &"projectile"]
@export var requires: Array[StringName]   # mutation ids or capability tags
@export var conflicts: Array[StringName]
@export var weight: float = 1.0
@export var is_mode_switch: bool = false  # triggers the transformation sequence

func apply_rules(rules: WorldRules) -> void: pass       # pure: modify rules only
func on_entity_spawned(entity: Node) -> void: pass      # add components (set source_patch = id)
func enable() -> void: pass                             # connect EventBus listeners
func disable() -> void: pass                            # disconnect EVERYTHING enable() connected
```

### 2.5 `RunState` (autoload)
- `base_rules: WorldRules`, `rules: WorldRules` (computed), `stack: Array[Mutation]`
- `apply(m)`: push → `m.enable()` → `recompute()` → run `m.on_entity_spawned` on all live entities → emit `patch_applied`
- `revert(m)`: remove from stack → `m.disable()` → strip components where `source_patch == m.id` from all live entities → `recompute()` → emit `patch_reverted`
- `recompute()`: `rules = base_rules.duplicate()`; for each patch in order: `apply_rules(rules)`; emit `rules_changed`
- On any entity spawn: run every patch's `on_entity_spawned` in stack order.
- Keep a run log (patch applied/reverted with timestamp, kills, damage by source) for the playtest report.

**Invariant (must be tested):** for any sequence of apply/revert, final `rules` == recompute from scratch over the remaining stack, and no live entity holds a component whose `source_patch` is not in the stack.

---

## 3. Base gameplay (zero mutations)

This must feel good on its own before any mutation work.

- **Player:** `CharacterBody2D`. 8-direction movement with slight acceleration/friction. Aim with mouse, shoot with left click (cooldown ~0.18s). Dash on Space/Shift (short i-frames, cooldown ~0.8s). 5 HP, brief invulnerability on hit.
- **Gamepad support:** left stick move, right stick aim, triggers shoot/dash. Nice-to-have, but keep input actions abstract from day one (`InputMap`).
- **Enemies (3):**
  - *Chaser* — runs at player, contact damage.
  - *Shooter* — keeps distance, fires slow projectiles. Has `Floating` (ignores gravity).
  - *Tank* — slow, high HP, big knockback resistance.
- **Arena:** one hand-built level (~2.5 screens wide, 1.5 tall) made of solid blocks that **work in both views**: an outer border, a solid floor along the bottom, and interior blocks/ledges at varied heights. In top-down they are obstacles; with gravity they are floors/platforms. Validate both readings while designing.
- **Juice:** hit flash, small screen shake, knockback, death particles, damage numbers optional.
- **HUD:** HP, kill count, build version label (`v0.1`, increments with each patch).

**Acceptance:** 5 minutes of plain play is engaging enough that moving/shooting/dashing is satisfying.

---

## 4. The gravity switch (the showcase transformation)

`gravity_on` is a mode-switch mutation. When `rules.gravity_enabled` is true:
- Player `Mover` switches to platformer control: horizontal input + jump (Space or W/Up); dash becomes horizontal/aimed burst. `up_direction = -rules.gravity_dir`.
- Chasers walk along surfaces and hop when blocked or when the player is above.
- Shooters keep floating.
- Loot/pickups (if any) and corpses fall.

**Transformation sequence** (`systems/transition.gd`), triggered by any `is_mode_switch` patch:
1. Freeze gameplay (`time_scale` → 0 over 0.15s).
2. Overlay: fake terminal "compiling…" text from the AI (~0.8s), glitch/scanline effect.
3. Apply the patch.
4. Unfreeze — everything visibly falls/settles under the new rules.
5. Short grace period (~1s) where enemies don't deal damage.

Reverting `gravity_on` plays the same sequence in reverse.

---

## 5. Mutation set for the prototype (7)

| id | Type | Effect | Requires / Conflicts |
|---|---|---|---|
| `gravity_on` | mode switch | `gravity_enabled = true` | conflicts: — |
| `gravity_reversed` | mode switch | `gravity_dir = (0,-1)` | requires `gravity_on` |
| `auto_attack` | rules | Player auto-fires at nearest enemy; manual shooting still works | — |
| `horde_mode` | rules | `spawn_rate_mult ×3`, `max_enemies ×3`, `camera_zoom 0.75`; enemies −40% HP | — |
| `bouncing_projectiles` | component | Player projectiles get `Bouncy`, `projectile_max_bounces += 3` | — |
| `explode_on_hit` | event | On `projectile_hit_wall` and `projectile_hit`: small AoE explosion | — |
| `enemies_split` | event | On `enemy_killed`: spawn 2 smaller, weaker copies (max 1 generation) | — |

Plus **innate** double jump? No — keep it as an 8th optional mutation `double_jump` (requires `gravity_on`) only if time allows. It demonstrates the "adapted" state: in top-down it becomes a short hop that passes over enemies/projectiles.

Each mutation needs: a card title, a one-line description, and 2 AI dialogue lines (one on proposal, one after applying). Example for `explode_on_hit`: *"What if bullets exploded? Just a little. Responsibly."*

**Acceptance:** any subset of these, applied in any order, runs without errors, and `bouncing_projectiles + explode_on_hit + gravity_on` produces visibly chaotic arcing explosive ricochets with zero combo-specific code.

---

## 6. AI Director (scripted)

- Listens to `enemy_killed`; every **N kills** (start N = 15, then +10 each prompt) emits `milestone_reached` and opens the prompt panel.
- Builds the offer: 3 mutations from the pool filtered by `requires`/`conflicts` and not already applied; weighted random. Guarantee at least one mode switch is offered in the first 2 prompts.
- Seeded RNG (seed shown in debug overlay) for reproducible runs.
- **Prompt panel:** game pauses; styled like a coding-assistant chat/terminal; AI line at top, 3 cards below, keyboard (1/2/3) + mouse + gamepad selectable.
- Keep the Director behind a clean interface (`get_offer() -> Array[Mutation]`, `on_choice(m)`) so personality, live patches and trust mechanics can be added later without touching core.

---

## 7. Revert / patch history

- `Tab` opens **Patch History**: ordered list of applied patches (version label, title).
- Player may revert any one patch; **2 reverts per run** for the prototype.
- Reverting a mode switch plays the transition. Reverting a patch that another patch `requires` also reverts the dependent (show a warning first).

---

## 8. Run loop

- **Run length target:** 6–10 minutes, 4 prompts.
- **Win:** after the 4th prompt, a final "release candidate" wave (≈90s, higher spawn rate). Survive it → `v1.0 shipped`.
- **Lose:** HP reaches 0.
- **Playtest Report** screen (both outcomes): time, kills, version reached, ordered patch list, top damage source (which component/mutation killed the most), reverts used. One AI comment line chosen from a few templates. Button: "New build" (restart).

---

## 9. Debug tools (build these early — M2)

- `F1` overlay: current `WorldRules` values, patch stack, seed, live entity count, FPS.
- `F2` mutation console: apply/revert any mutation instantly.
- `F3` toggle invincibility. `F4` spawn enemy wave.

---

## 10. Milestones (in order — report after each)

| # | Milestone | Done when |
|---|---|---|
| M0 | Project setup | Godot project, folders, autoloads registered, InputMap defined, test framework installed |
| M1 | Base gameplay | Section 3 acceptance met, no mutation code yet |
| M2 | Core systems | WorldRules, EventBus, RunState, Mutation, Component in place; debug tools; **invariant tests pass** |
| M3 | Gravity switch | `gravity_on`, `gravity_reversed` + transition sequence; arena verified playable in both views |
| M4 | Remaining mutations | All 7 mutations; acceptance in Section 5 met |
| M5 | Director + UI | Prompt panel, patch history, reverts |
| M6 | Run loop | Win/lose, playtest report, restart |
| M7 | Juice pass | Feedback, transition polish, performance check (≥60 FPS with `horde_mode` + `enemies_split` + explosions) |

Don't start a milestone before the previous one's "done when" is true.

---

## 11. Tests (required)

- **Apply/revert invariant** (Section 2.5) over randomized sequences of the 7 mutations (≥200 seeded sequences).
- **Recompute determinism:** same stack → identical `WorldRules`.
- **Compatibility filter:** Director never offers a mutation whose `requires` are unmet or that `conflicts` with the stack.
- **Listener hygiene:** after `disable()`, a mutation has no remaining EventBus connections.
- **Component cleanup:** after revert, no live entity has a component from that patch.

---

## 12. Engineering rules for the builder

- Systems read `RunState.rules`; nothing branches on "mode".
- No combo-specific code. If two mutations need special handling together, flag it.
- Mutations must be fully reversible. If one can't be, flag it rather than shipping it.
- Cap runaway chaos defensively (max entities, max projectiles, max split generation) — chaos is a feature, crashes are not.
- Placeholder visuals only: distinct colors per entity type, readable at a glance.
- Tunables (speeds, cooldowns, N kills, spawn rates) live in one `tuning.gd`/`.tres`, not scattered.
- Commit per milestone with a short summary of what changed and what's untested.

---

## 13. What this prototype must answer (for the playtest)

1. Is the base gameplay fun between prompts?
2. Does the gravity switch create a real "whoa" moment?
3. Do mutation combinations make players want another run?
4. Is revert ever used, and does it feel meaningful?
5. Does the architecture make adding an 8th mutation a one-file job?

## 14. Open questions — builder may decide, but must report the choice
- Exact jump height / gravity feel in platformer view.
- Whether `auto_attack` should disable manual fire for clarity.
- Whether reverts should cost something (HP, time) instead of a fixed count.

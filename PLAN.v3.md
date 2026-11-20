# Build Plan v3 — Big Patches ("Patch Notes")

**For:** the builder agent
**Goal of this build:** add the first **big patches**: permanent genre shifts the AI proposes 2 times per run, built on the v2 core, and steered by the adaptive path (what the AI has learned about the player).
**Engine:** Godot **4.7.x stable**, unchanged, GDScript, 2D simulation.
**Roadmap:** `ROADMAP.md` (phases after this one, progression model, scope). This plan is its Phase 2.
**Supersedes:** `PLAN.v2.md` for scope and milestones. **Every v2 contract (v2 sections 1–4 and 9–12) stays in force** unless this document changes it explicitly. Read v2 first.

---

## 0. Read this first

v2 proved that small, reversible rule patches work. v3 adds a second scale of patch:

| | Small patch (v2) | Big patch (v3) |
|---|---|---|
| Changes | one mechanic (bounces, horde, a jump) | how the whole game is played (time, turns) |
| Per run | 4, at the normal prompts | 2, at their own BIG prompts |
| Rollback | yes, with the 2 rollback charges | **never**; only another big patch replaces it |
| Active at once | any legal set | **at most one** (the big slot) |
| Version | `v0.N` (unchanged) | also `v0.N`; the history marks it as MAJOR with a lock |

The owner decided (2026-11-19) that some choices may be permanent. This **amends v2 principle 2** and v2 rule 12 ("mutations must be fully reversible"): a big patch is still fully removable in classes A and B (it can be *replaced*), but the player cannot roll it back. Irreversibility must stay explicit: a field on the mutation, a lock in the UI, a guard in `revert()`, and tests. Nothing else may become irreversible quietly.

Principle 1 holds without change: a big patch is still a set of `WorldRules` values plus components and listeners. Nothing branches on "genre".

### Already done before v3 (M8)
The first step of the adaptive path (`director/taste.gd`): the Director scores mutations and tags from picks, passes, rollbacks and report ratings, leans its offers toward high scores, and keeps one card per offer (two after an unrated run) for its own agenda. In memory for the session only, fading by half each run. v3 builds on it; it does not redesign it.

### Out of scope (do not build)
- Stages, the AI boss, stage unlocks across runs
- Tower defense and JRPG card battle (later; they are stage types, not big patches)
- Multiple endings
- Saves or meta-progression on disk (the taste stays session-only)
- Real generative AI; final art/audio

---

## 1. Contracts

### 1.1 `Mutation` additions
```gdscript
@export var is_big := false        ## permanent; lives in the big slot, never in the stack
@export var genre_label := ""      ## short name for the HUD and the history ("Turn-based")
```
- A big patch has no `requires` and no `conflicts` (validated by `MutationDB`). Small patches may `require` or `conflict` with a big patch by id.
- A big patch sets `is_mode_switch = true` (long transition).
- Big patches live in `mutations/<id>/` like any other. Adding one touches only its folder, plus the rule fields it needs (v2 section 1 exception).

### 1.2 `RunState`: the big slot
- New: `big: Mutation` (null = base gameplay). `stack` still holds small patches only.
- `recompute()`: `rules = base.duplicate()` → `big.apply_rules(rules)` if any → each small patch in stack order. The genre sets the frame, then small patches modify it.
- `can_apply(m)` rejects big patches (they go through `swap_big`). Small patches whose `requires` names a big id need it in the slot.
- **`swap_big(m)`** (the only way into or out of the slot):
  1. remove, with no charge, every small patch that requires the old big (dependents first, as in `revert`);
  2. `old.disable()`, strip its components;
  3. set `big = m`, `recompute()`, `m.enable()`, `on_entity_spawned` on live entities;
  4. one build (`build_number += 1`), log `big_swap {from, to, removed}`, emit `EventBus.big_swapped(old, new)`.
- `revert(m)` asserts `not m.is_big` and returns nothing for a big patch. The Patch History cannot select one.
- `reset()` clears the slot through the same strip path (it is the only way back to no big patch).
- `on_entity_spawned`: big patch first, then the stack in order.

**Invariant (extends v2 2.5):** after any legal sequence of apply / revert / swap_big / reset, the state equals `reset()` → `swap_big(current big)` if any → apply the small stack in order. Same three comparisons as v2 (rules, components per entity, mutation-owned connections). Entities and kills from earlier big patches are simulation (class C) and are not compared.

### 1.3 `WorldRules` additions
| Field | Type | Base | Used by |
|---|---|---|---|
| `time_follows_motion` | bool | false | B1 |
| `idle_time_scale` | float | 1.0 | B1: time scale when the player stands still (multiplied) |
| `turn_based` | bool | false | B2 |
| `turn_duration` | float | 0.25 | B2: game seconds the world runs per player action |

Composition as in v2: bools only turned on, `*_scale` multiplied, durations assigned only by the one big patch that owns them (allowed because the slot holds one big patch; flagged in a comment).

### 1.4 Time ownership (amends v2 2.5)
`RunState` stays the **only writer** of `Engine.time_scale`. Until now it was `rules.time_scale`, set on recompute. It becomes:

`Engine.time_scale = max(rules.time_scale × motion_factor, MIN_TIME_SCALE)`, updated every physics tick by RunState.

`motion_factor` is 1 unless `time_follows_motion` is on (B1). This is the one place a derived value reads simulation state (the player's velocity); it stays a pure function of rules + that velocity and is recomputed every tick, so nothing stale survives a swap.

---

## 2. Big patch B1 — "Time moves when you move" (`time_follows_motion`)

- `motion_factor = lerp(idle_time_scale, 1.0, clamp(player_speed / player_max_speed, 0, 1))`, smoothed (~0.1 s, real time). Player speed is the body's velocity length, so falling under gravity also moves time.
- Shooting or dashing raises the factor to 1 for a short pulse (Tuning, ~0.15 s real time), so an idle shot still leaves the muzzle.
- B1 sets `idle_time_scale *= 0.08`.
- Everything that already runs on game time (cooldowns, i-frames, grace, Director timers, the RC wave) slows with it. The prompt panel, the history and transitions stay on pause reasons and are unaffected.
- Readability: a desaturation and vignette on the world that fade in as time slows (presentation only, reads `Engine.time_scale`); SFX pitch follows the time scale.
- With the gravity patches: no special code. A player standing on a ledge has slow time; jumping or falling runs it.

**Acceptance:** standing still for 3 s of real time advances game time by ≤0.4 s; moving at full speed runs it at ≥0.95; the scene smoke matrix passes with B1 in the slot.

## 3. Big patch B2 — "Turn-based" (`turn_based`)

v3 builds the **player half** of a turn-based game; enemies keep their real-time movement inside each turn. M13 adds the enemy half (section 3b).

- **The world runs only on the player's actions.** A `TurnClock` (systems/, `PROCESS_MODE_ALWAYS`) holds a new pause reason `turn` while waiting. A player action releases it for `rules.turn_duration` of game time, then it pauses again.
- **Actions:** one tile step (48 px, a tween over the turn), shoot (one shot, aim kept from `PlayerInput.aim_dir`), dash (2 tiles), jump (with gravity), and **wait** (new input action `wait`: `E` / Y, no-op outside B2). Held move repeats a step each turn. (M13 makes it one action per turn: section 3b.1.)
- The player reads input while the tree is paused: `PlayerInput` and `TurnClock` run always; the player's body moves only inside a turn.
- Movement snaps to the 48 px grid on entry into B2 (to the nearest free tile) and stays snapped while B2 is active. On a swap out, the player keeps its position (class C).
- Under gravity: lateral steps are on the grid; falling happens during turns and lands on tile rows.
- HUD: a turn counter and a tile highlight under the player and the aim line.
- The Director's pacing reads game time and kills as before, so prompts still come.

**Acceptance:** with no input for 5 s of real time, game time does not advance; 20 bot actions advance it by 20 × `turn_duration` (±1 tick); the player position is always on the grid at turn ends; smoke matrix passes with B2 in the slot. `BotInput` gets a turn policy (step away from threats, shoot nearest, wait otherwise).

## 3b. B2, the enemy half — enemies on the grid (M13)

**Why (owner, 2026-11-20, after G6):** B2 felt too much like B1. Both freeze the world while you stand and run it while you act. B2's enemies and shots still moved freely inside each turn, so it played like B1 cut into slices. G5 is answered "no". M13 builds the enemy half that section 3 put off, so B2 asks for a different skill: positioning with full information instead of dodging.

Words used below: a **tile** is a 48 px grid cell, named by its centre. **Free** means `TurnClock.is_free` (inside the arena, away from blocks). **Held** tiles: the player's current tile, `P` (below), every grid enemy's current tile, and every tile reserved this turn.

### 3b.1 The turn
One player action is one turn. The world still runs for `rules.turn_duration` of game time (cooldowns, i-frames, the Director, spawns), so pacing stays on game time. What changes: everything hostile **decides on tiles at the start of the turn and resolves on tiles at the end.**

**One action per turn (owner, 2026-11-20): step OR shoot OR dash OR wait.** A step no longer fires the held shot (amends section 3: "a held fire also shoots on that turn" is removed). Retreating costs a shot. Jump stays an action under gravity only, which B2 no longer meets in normal play (3b.6).
- **Step:** one tile, 4-way. Refused (no turn is taken) if the target tile is not free or is held by an enemy.
- **Dash:** up to 2 tiles. `P` is the farthest tile along the direction that is free and not held by an enemy, checked tile by tile. The dash moves exactly there. A dash that would move 0 tiles is refused. In B2 the dash grants **no** i-frames: it is movement, not protection.
- **Shot:** one player shot along `aim_dir`. Player shots stay free-aim real projectiles (bounces and explosions keep working), and they hit enemies by physics during the turn.
- **Wait.** With `auto_attack`, a wait turn becomes a shot at the nearest visible enemy. Auto-attack never fires during a step or a dash turn, so it cannot bring back step-and-shoot.

**Order of one turn:**
1. **Player.** `TurnClock` reads the action and fixes `P`, the tile the player will end on (the step or dash target, otherwise the current tile).
2. **Enemies plan,** one at a time in a fixed order: the order their `GridActor` was attached, from a counter (never `get_instance_id`). Each one takes **one action** (3b.2). A move reserves its target. No enemy plans a move into `P`, a reserved tile, or a tile still held by an enemy that has not planned yet.
3. **Shots plan:** each enemy shot computes the tiles it enters this turn (3b.3).
4. **Animate:** the player, the enemies and the shots tween to their tiles over the turn. Grid enemies and grid shots never hit anything by physics.
5. **Resolve at turn end,** in this order:
   1. Every grid enemy stops (`mover.stop()`), and every grid actor is set to its tile centre.
   2. Attacks from enemies still alive resolve against `P`.
   3. Shots that entered `P` this turn hit, or whose tile at the start of the turn was `P` (a head-on swap counts). A shot that hits is removed, even when i-frames block the damage.
   4. Shots out of tiles or turns are removed.
   5. Intents for the next turn are computed (3b.2), and the danger map is rebuilt (3b.4).
6. **No new turn starts on the tick that ended the previous one.** Input read on the next tick sees the new map. The bot and the overlay never act on a stale map.
7. **If resolution ends the run** (a lethal hit, or the RC win), `TurnClock` does not take the `turn` pause again. After `_end_turn()`, it returns when stopped or inactive, and `_wait_for_action()` returns at once when `_stopped`. Today a death can only happen inside a turn, while the world runs. 3b creates the turn-end path, and without this the report never opens.

**The danger promise:** the player is hit in B2 only at turn-end resolution, and only on a tile the danger map marked before the player acted. Exemptions are listed with the map (3b.4).

### 3b.2 Enemies
Distances are measured on one **distance field**, a breadth-first fill from `P` over free tiles, run once per turn (not per enemy). Moves are 4-way. When moves tie, the fixed order is right, left, down, up. A best move that is held falls back to the next best free neighbour, otherwise the enemy stays.

| Enemy | Acts | Attack tiles | Plan |
|---|---|---|---|
| Chaser | every turn | the 4 tiles next to it | attack if `P` is one of them, otherwise step down the field |
| Tank | every 2nd turn, counted from attach (a resting tank shows a mark) | the 8 tiles around it | as the chaser |
| Shooter | every turn | none (it fires shots) | see below |

**Shooter.** The band is `shooter_near`..`shooter_far` (5–8 tiles, from Tuning), measured on the field.
- **Fire:** if it aimed last turn, it fires along its locked line, wherever the player is. The shot is created at the shooter's tile centre and enters its first tiles this turn. The shooter does not move.
- **Aim:** otherwise, if `P` is on its row, column or diagonal, within `shooter_range`, with a clear line (3b.3), and its cooldown (in turns, `grid_shooter_cooldown`, on the `GridActor`; `Shooter._ready_in` is not used) is ready, it aims instead of moving. The line is locked and drawn.
- **Hold:** otherwise, if `P` is on its row, column or diagonal with a clear line in range and it stands in the band, it stays: it is only waiting on its cooldown (stepping would only make it jitter on and off the line).
- **Move:** otherwise it steps to the free neighbour that is in the band and aligned with `P`. Failing that, the neighbour in the band that brings it closest to aligned (smallest of |dx|, |dy|, ||dx|−|dy||, in tiles). Failing that, toward the band. Ties break in the fixed direction order.

**Every enemy on a grid:**
- Damage keeps each archetype's number: `*_contact_damage` for melee attacks, logged with kind `contact`, and projectile damage for shots, logged with kind `projectile`. The kinds match base, so the hit counts compare across genres.
- **Knockback does nothing while `rules.turn_based` is on,** for the player and for enemies.
- While a `GridActor` is attached, the enemy's script skips its steering, contact damage and firing. `mover.wish` is zero, and velocity is cleared on attach and at every turn end. All motion comes from the turn's tween.
- **Snapping:** when an enemy enters the grid (on B2 entry, spawn, split or RC wave), it takes the nearest tile that is free and not held. The search widens until it finds one and never falls back to a held tile. The tile is claimed right away in `on_entity_spawned`, so the second split child sees the first. The new enemy acts from the next turn. On B2 entry, the player snaps first and then the enemies, in attach order.

### 3b.3 Enemy shots on the grid
- **Motion in tiles:** a shot moves `grid_shot_tiles` (start: 2) steps per turn along an 8-way direction (dx, dy ∈ {−1, 0, 1}). Its position at each turn end is set to the exact tile centre. During the turn it tweens there (visual only). It never ray-tests bodies. `projectile.gd` changes for this: while the shot carries a `GridActor`, it skips its own motion, contact and `_age` lifetime. Its lifetime is `grid_shot_turns` (start: 8).
- **Walls, by tiles only:** a step is blocked if its target tile is not free. A diagonal step is also blocked if either orthogonal neighbour is not free (no corner cutting). The shooter's "clear line", the shot and the danger map all use this one rule.
- **B2 entry:** enemy shots already in flight are removed (class C, logged). Every shot on the grid comes from a grid shooter.

### 3b.4 The danger map
- `turn_mode` builds it at each turn end and publishes it on `TurnClock.danger`: a dictionary from tile to its sources, with `TurnClock` as the neutral owner. It is cleared on `_exit`. The overlay, the bot and the tests read only that field, so nothing outside `mutations/turn_mode/` names the mutation's code.
- **Marked tiles:** the attack tiles of each chaser and of each tank that acts next turn; the tiles a shooter that aimed this turn will hit with its first `grid_shot_tiles` steps next turn; for each live shot, its current tile plus the tiles it will enter next turn.
- **Hit only if marked:** every B2 `player_hit` is logged inside turn-end resolution, on a marked tile.
- **Marked means hit,** unless one of these applies, each logged with its reason:
  - the source died or was removed during the turn (for example by a player shot);
  - the hit was blocked: by i-frames, by grace, or by invincibility (logged as a blocked hit, as in M12);
  - the shot was never created (the projectile cap).
- **Grace stays.** While it is on, the overlay dims the danger tiles.
- **Height is ignored in B2:** tile hits land on an airborne player. Otherwise a hop with no cooldown would dodge every tile.

### 3b.5 Code shape (principle 1: rules, components, listeners)
- **`TurnClock` (systems/)** still owns the turn. It gains `player_tile` (`P`) and `danger`, it emits `EventBus.turn_started(number)` and `EventBus.turn_ended(number)`, and it gets the fixes in 3b.1 (the action economy, refused steps and dashes, the wait tick, stopping after a resolution death).
- **`mutations/turn_mode/`** holds everything on the enemy side:
  - the `GridActor` component (tile, role, rest counter, cooldown in turns, locked aim, attach order), which `turn_mode.on_entity_spawned` attaches to enemies and enemy shots;
  - the turn logic (distance field, planning, resolving, the danger map), which `turn_mode.enable()` connects to the two signals with `_listen`.
- Swapping B2 out strips the components and disconnects the listeners. Enemies then steer in real time again from where they stand, and grid shots fall back to real-time projectiles with their current velocity.
- **Changed outside the folder,** and nothing more:
  - the enemy scripts (skip their own behaviour while they carry a `GridActor`);
  - `projectile.gd` (the same skip);
  - `Mover.knockback` (no-op under `turn_based`);
  - `player.gd` (auto-attack only on wait turns);
  - the overlay and the bot (read `TurnClock.danger`).

### 3b.6 Gravity and BIG prompts (owner, 2026-11-20)
- **Turn-based is never offered while gravity is on.**
  - `gravity_on` lists `turn_mode` in `conflicts`.
  - `RunState.can_apply` also checks conflicts against the big patch in the slot (today it checks only the stack). So no gravity patch is offered with B2 in the slot.
  - `get_big_offer` skips a big patch that conflicts with a small patch in the stack.
- **The forced gravity card stops once a genre is in the slot:** `_mode_switch_applied()` also counts `RunState.big`. BIG prompt 1 always fills the slot before small prompt 2, so in practice the gravity guarantee no longer fires in a full run. Gravity still comes up as a normal card. BIG prompt 2 is lost only when the player took gravity and the slot holds B1: nothing compatible is left to offer, and the prompt is skipped as today.
- **One candidate at BIG prompt 1** (gravity taken at prompt 1, so B1 is the only candidate): the offer is marked mandatory, shows the mandatory line, stays out of Taste, and is logged as mandatory in `big_offers`.
- **`swap_big` drops conflicting patches** (reached only from the F2 console). The drop set is every stacked patch that conflicts with the new big patch, plus `dependents_of` each one (so `gravity_reversed` goes with `gravity_on`). Dependents are removed first. Nothing is charged, and all of them are logged as dropped.
- The M11 code for B2 under gravity stays as it is but is unreachable in normal play. M13 adds no gravity work.

### 3b.7 Presentation and bot
- **Overlay:** the danger tiles (red fill, dimmed in grace), each shooter's locked line, each shot's next tiles, a mark on a resting tank. The B2 card text says enemies move on the grid too, and that one turn is one action.
- **Bot:** the turn policy reads `TurnClock.danger` at decision time:
  - with an enemy in a clear line and the current tile unmarked, it shoots;
  - otherwise it moves to an unmarked reachable tile, preferring one with a clear line to an enemy;
  - otherwise it waits.

  The M12 shot estimate (`_danger`, `SHOT_*`) is removed, and the M12 "steps out of an enemy shot" test is rewritten against a grid shooter's locked line.

### 3b.8 Acceptance
- **Grid:** at every turn end, every enemy and every shot is on a tile centre, no two enemies share a tile, none shares the player's tile, and the player's tile equals `P`.
- **Steps and dashes:** a step into an enemy's tile is refused with no turn taken; a dash stops before walls and enemies; a dash that would move 0 tiles is refused.
- **One action:** a step with fire held does not shoot. Auto-attack shoots only on wait turns.
- **Enemies:** a chaser next to `P` attacks instead of moving; one around a wall follows the shortest free path. A tank acts every 2nd turn and hits all 8 neighbours. A shooter in the band with the player off its lines becomes aligned within 6 turns while the player waits. A shooter aims only with a clear line, then fires on its next action along the locked line. Its shot advances exactly `grid_shot_tiles` per turn, diagonals included, and stops at walls and corners.
- **Kills during a turn:** an adjacent enemy killed by the player's shot during the turn does not attack.
- **Death at turn end:** a 1-HP player ends a turn next to a chaser. The chaser's attack kills them at resolution. Afterwards the `turn` pause is off, game time advances, and the report opens. The same holds for a grid shot.
- **Danger is exact:** a seeded random policy (not the avoiding bot) plays at least 2 000 B2 turns, invincible, on several seeds, with horde, splits and shooters. It ends on marked tiles at least 200 times. Every hit, blocked or not, comes at resolution on a marked tile, and every marked tile ended on is hit unless a logged exemption covers it.
- **Same seed, same run:** the same seed with B2 and the invincible bot, 300 turns, run twice in the same process. The per-turn hash of the player tile, the enemy tiles and roles, the shot tiles and the hits matches.
- **Swaps:** B1↔B2 and none↔B2 mid-wave. On entry, enemies snap (player first) and shots in flight are removed. On exit, enemies steer in real time. The invariant tests see no leftover component or connection.
- **Gravity:** with B2 in the slot, no gravity patch is offered. With gravity in the stack, B2 is not offered. The console swap drops `gravity_on` and `gravity_reversed`. A fixture small patch that conflicts with fixture big B, plus a dependent of it, is added to `fixtures.make_bigs`, so the invariant sequences exercise this path.
- **BIG prompts:** with B1 in the slot, prompt 2 is not forced gravity, and BIG prompt 2 opens. A one-candidate BIG prompt 1 is mandatory and leaves Taste unchanged.
- **Smoke matrix:** legality includes the slotted big patch, with the expected count per slot (191 for none and B1, 63 for B2). The real-pool BIG offer test pins its small picks to non-gravity cards, and it gets a sibling test with gravity in the stack.
- **Bot sweep, reported:** 16 seeds, mortal. `--big=turn_mode --set=big_prompt_after=[]` against base with `--set=big_prompt_after=[] --set=force_gravity_at_prompt=0`. Report the median time to death and the hits by kind. Then one invincible full-run sweep, to compare the B2 stretch with M12's (~6.5 / ~4.5 min). Pacing is retuned only if the mean genre stretch moves by more than 20%.

**Cut order inside M13 (first to last):** the resting-tank mark → shooter diagonals (rows and columns only) → the tank's 8-tile attack (4, like the chaser) → the tank's resting turns. Never cut: tile-decided hits, the danger map and its exactness test, one action per turn, the overlay's danger tiles, the stop after a death at turn end.

---

## 4. Director: BIG prompts

- **Schedule:** a BIG prompt opens right after small prompts listed in `Tuning.big_prompt_after` (start: `[1, 3]`). The run then has 4 small and 2 BIG prompts. The BIG prompt follows the same pause and input-guard rules as a small one.
- **Pacing (M13 retune):** the first small prompt keeps v2's 60 s minimum gap (`first_prompt_min_gap`), so the first BIG prompt comes early; later small prompts wait at least 150 s; any gap ends at 180 s. `big_prompt_after` stays `[1, 3]`. The kill thresholds are met well before the gaps, so a full run is 60 + 3 × 150 + the 90 s RC wave = 10 min of game time: 60 s base, then 5 and 4 min in the two genre stretches. M12 had chosen 105 s from bot runs in which a projectile-cap leak (since M3) stopped all shooting after ~200 enemy shots; M13 fixed the leak (`RunState.spawn` counted an enemy shot under the scene's default kind) and retuned.
- **Offer:** up to 2 big patches, not the one in the slot, sampled weighted, leaned by `Taste`. With 2 or more candidates, one card is the AI's agenda (least liked), as for small offers. The second BIG prompt adds a **Keep <current genre>** card. There is no skip on the first BIG prompt.
- **Gravity guarantee:** prompt 2, small; from M13 it yields once a big patch is in the slot (section 3b.6).
- **Taste:** picking, passing and keeping big patches feed `Taste` like small ones. Rollbacks cannot target them, so a big patch is only scored by picks, passes, keeps and report ratings.
- **Hotfix heal:** a big patch heals 1 HP, like a small one.
- Interface additions: `get_big_offer(ctx) -> Offer` (with `offer.big = true`), and `on_choice` routes big picks to `RunState.swap_big`.

## 5. Presentation

- **Big prompt panel:** the same panel with a MAJOR frame, a lock icon, and one line under the cards: "This one stays. Only another major update can replace it." The AI line comes from the mutation's `line_proposal`.
- **Transition:** the long version, text "migrating engine…", for every swap.
- **Patch History:** big entries show the lock and the genre label and cannot be selected; small patches removed by a swap are listed as "dropped by <big>", not as rollbacks.
- **HUD:** the current genre label next to the build version (`v0.9 · Turn-based`).
- **Report:** a "Genres" line listing each big patch with the time spent in it. The report ratings (Keep / Cut) include big patches.

## 6. Telemetry
Add to the run record: `big_offers` (cards, agenda, pick per BIG prompt), `big_swaps` (time, from, to, dropped small patches), seconds per genre. Bot run records get the same fields.

---

## 7. Milestones

| # | Milestone | Builder gate | Owner gate |
|---|---|---|---|
| M8 | Adaptive path step 1 | Taste work committed; `tools/check.ps1` green | — |
| M9 | Big slot | 1.1–1.4 without real big patches: two **fixture** big patches in tests, `swap_big`, revert guard, invariant tests (≥200 sequences with swaps), F2 console can swap, time ownership moved to the per-tick formula with no behaviour change | — |
| M10 | B1 + BIG prompts | Section 2, section 4, section 5; smoke matrix with B1; bot runs end to end | **G4:** does a permanent shift feel like stakes? Is B1 fun for a whole stretch? |
| M11 | B2 turn-based | Section 3; smoke matrix with B2; bot turn policy; swap B1↔B2 both ways mid-wave without errors | **G5:** does turn-based feel like a different game in the same arena? |
| M12 | Run retune + export | Run length, `big_prompt_after`, prompt pacing retuned from bot runs; telemetry fields; Windows export lists all mutations, both big patches marked | **G6:** playtest build |
| M13 | B2 enemy half | Section 3b (acceptance 3b.8): one action per turn, danger-exactness test, gravity conflict and BIG prompt rules, bot policy on the danger map, bot sweep reported, export rebuilt | **G5 again:** does Turn-based now feel like a different game from B1? |

Check, commit and report rules: as in v2 section 10.

**Cut order if needed (first to last):** B1's desaturation and pitch → the Keep card → B2 tile highlight → B2 under gravity (make B2 conflict with `gravity_on` instead, stated in its resource) → B2. Never cut: the big slot, the revert guard, the invariant tests, telemetry.

---

## 8. Tests (additions to v2 section 11)

- **Extended invariant** (1.2) over random sequences of apply / revert / swap_big / reset, with fixture big patches that add rules, a component and a listener.
- **Revert guard:** `revert(big)` changes nothing and returns empty; Patch History offers no big entry.
- **Swap cascade:** a small patch that requires big A is removed when A is swapped for B, costs no rollback charge, and is logged as dropped.
- **Slot exclusivity:** never more than one big patch; `can_apply` rejects every big patch; `MutationDB` rejects a big patch with `requires` or `conflicts`.
- **Time ownership:** nothing but RunState writes `Engine.time_scale` (grep test); with no big patch, the per-tick formula equals v2's value.
- **B1 / B2 acceptance** numbers (sections 2 and 3).
- **Director:** BIG prompts open after the listed small prompts; never offer the slotted patch; same seed + same choices → same big offers; the agenda card is present with ≥2 candidates.
- **Scene smoke matrix:** each big slot value (none, B1, B2) × every legal small subset.

## 9. What v3 must answer
1. Does a permanent genre shift feel like a real stake, or like a loss of control?
2. Do players prefer one genre and want to push it further (the adaptive path's premise)?
3. Do small patches stay interesting inside each genre?
4. Does adding a big patch touch only its own folder and its rule fields?

## 10. Still open
- Gravity will be a **medium** patch (owner, 2026-11-19; `ROADMAP.md` 1.4). The medium tier is designed later; v3 leaves gravity exactly as it is.
- Rollbacks are under study (`ROADMAP.md` 1.5). v3 adds no rollback features and keeps v2's 2 charges, so telemetry measures them as they are.
- 2 or 3 BIG prompts per run (the owner said 2–3); v3 starts at 2.
- ~~Turn-based enemies on the grid (true turn order) — after G5.~~ G5 answered "too close to B1" (owner, 2026-11-20): pulled forward from v5 as M13 (section 3b).
- Whether to run the G3 playtest of the v2 build anyway; v3 goes features first by the owner's choice.

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

v3 builds the **player half** of a turn-based game; enemies keep their real-time movement inside each turn. Grid enemies are a later step.

- **The world runs only on the player's actions.** A `TurnClock` (systems/, `PROCESS_MODE_ALWAYS`) holds a new pause reason `turn` while waiting. A player action releases it for `rules.turn_duration` of game time, then it pauses again.
- **Actions:** one tile step (48 px, a tween over the turn), shoot (one shot, aim kept from `PlayerInput.aim_dir`), dash (2 tiles), jump (with gravity), and **wait** (new input action `wait`: `E` / Y, no-op outside B2). Held move repeats a step each turn.
- The player reads input while the tree is paused: `PlayerInput` and `TurnClock` run always; the player's body moves only inside a turn.
- Movement snaps to the 48 px grid on entry into B2 (to the nearest free tile) and stays snapped while B2 is active. On a swap out, the player keeps its position (class C).
- Under gravity: lateral steps are on the grid; falling happens during turns and lands on tile rows.
- HUD: a turn counter and a tile highlight under the player and the aim line.
- The Director's pacing reads game time and kills as before, so prompts still come.

**Acceptance:** with no input for 5 s of real time, game time does not advance; 20 bot actions advance it by 20 × `turn_duration` (±1 tick); the player position is always on the grid at turn ends; smoke matrix passes with B2 in the slot. `BotInput` gets a turn policy (step away from threats, shoot nearest, wait otherwise).

---

## 4. Director: BIG prompts

- **Schedule:** a BIG prompt opens right after small prompts listed in `Tuning.big_prompt_after` (start: `[1, 3]`). The run then has 4 small and 2 BIG prompts. The BIG prompt follows the same pause and input-guard rules as a small one.
- **Pacing (M12 retune):** the first small prompt keeps v2's 60 s minimum gap (`first_prompt_min_gap`), so the first BIG prompt comes early; later small prompts wait at least 105 s; any gap ends at 180 s. `big_prompt_after` stays `[1, 3]`. Bot runs: ~9.6 min of game time per full run (60 s base, then ~6.5 and ~4.5 min in the two genre stretches).
- **Offer:** up to 2 big patches, not the one in the slot, sampled weighted, leaned by `Taste`. With 2 or more candidates, one card is the AI's agenda (least liked), as for small offers. The second BIG prompt adds a **Keep <current genre>** card. There is no skip on the first BIG prompt.
- **Gravity guarantee:** unchanged (prompt 2, small).
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
- Turn-based enemies on the grid (true turn order) — after G5.
- Whether to run the G3 playtest of the v2 build anyway; v3 goes features first by the owner's choice.

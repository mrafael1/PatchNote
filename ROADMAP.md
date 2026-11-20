# Roadmap — "Patch Notes"

Where the game is going after the prototype, in phases. Each phase becomes a builder plan (`PLAN.md`) only when it starts; this file holds the direction, the progression model and the scope of each phase. Numbers are starting targets, to retune from playtests.

**The game in one line:** a roguelike where an AI developer rewrites the game while you play it, learns which kind of game you like, and keeps pushing you somewhere new.

**Never in scope:** RTS / squad control. Real generative AI at runtime (the AI stays scripted; it can get richer, not live).

---

## 1. Progression model

### 1.1 Inside a run (what the player builds)
| Layer | What it is | Can be undone? | Phase |
|---|---|---|---|
| Small patches | one mechanic each (bounces, horde, a jump) | yes, with rollback charges | done |
| Medium patches | how you move and see, in the same genre (gravity, reversed gravity) | yes (exact rules to define, 1.4) | v4 |
| Big patches | the genre (time, turns, later towers) | no; only replaced by another big patch | v3 |
| Stages | the run's chapters, each a new arena the AI "ships" | no; you move forward | v4 |
| Boss | the AI patching the arena against you; your rollbacks are weapons | — | v4 |

The run's tension: **patches make you stronger and stranger; rollbacks are scarce; big patches and stages are permanent.**

### 1.2 Across runs (what the game remembers)
| Layer | What it is | Visible to the player? | Phase |
|---|---|---|---|
| Taste | what the AI learned you like; leans its offers | **hidden** at first, revealed later by the AI's lines | session v3, saved v5 |
| Pool growth | the AI "ships" new mutations and big patches over runs (it starts with a small pool) | yes: "new in this build" | v4 |
| Stage unlocks | stage types and arenas you reached become available as starts or routes | yes | v4 |
| Path | the shape of your choices over many runs (which genres you pushed, what you refused) | partly, through the AI's personality and endings | v6 |
| Endings | a light summary of your path, one per main direction | yes, collected | v6 |

### 1.3 Rules progression must follow
1. **Never locked out.** Refusing or cutting something lowers its odds; it never removes it for good. The AI brings it back later as push-back.
2. **Push-back stays.** Even a player who loves one genre gets offers outside it (the agenda card). The share of agenda cards is a tuning value, never zero.
3. **Taste is a nudge, not a choice menu.** The player steers by playing, picking, rolling back and (optionally) rating; there is no "choose your genre" screen.
4. **Ignoring the ratings is allowed.** Then the AI takes more free rein (already in v3: 2 agenda cards after an unrated run).
5. **Power stays inside the run.** Across runs, the game unlocks *variety* (mutations, stages, genres), not stats. A first-run player and a 50-run player start with the same HP.

### 1.4 Patch tiers (owner, 2026-11-19)
Three tiers, by how much of the game a patch changes:
- **Small** — one mechanic. Reversible.
- **Medium** — how you move and see, inside the current genre. Gravity is the reference medium patch (`gravity_on`, `gravity_reversed`). Reversible; it already uses the long transition (`is_mode_switch`). To define: does a medium patch have its own prompt or slot, does its rollback cost more than a small one, does it survive a big swap.
- **Big** — the genre. Permanent; only replaced by another big patch.

v3 builds only the big tier; gravity keeps working as today (a small patch with the long transition) until the medium tier is designed.

### 1.5 Rollback study (open, owner, 2026-11-19)
Rollback is the prototype's least proven mechanic. Before v4 builds anything on it (boss weapons, per-stage charges), answer:
1. **Is it used?** v2/v3 telemetry already logs every rollback with game time and HP. Measure: share of runs with ≥1 rollback, what gets rolled back, how soon after the apply.
2. **Is it interesting?** A rollback is interesting only if the choice before it was risky. Without downsides on patches, it is mostly an "undo a bad card" button.
3. **Should it exist in every run?**

Options to compare:
- **A. As today:** 2 free charges per run.
- **B. Earned:** charges come from stages, kills or the boss, never at the start.
- **C. Priced:** a rollback costs HP, a future offer, or makes the AI sulk (its next offer is pure agenda).
- **D. Only as a weapon:** no rollbacks of your own patches; you roll back the *AI's* patches (the boss and stage hazards).
- **E. Rare unlock:** some runs, or some stages, grant it; most don't.

**Chosen direction: D** (owner, 2026-11-19): rollbacks become a weapon against the AI's patches (the boss, stage default patches and hazards) instead of an undo for your own picks. It gives rollbacks a target the player wants to remove. Still to settle in v4: whether a few self-rollbacks remain (e.g. one per run) or disappear entirely, and how charges are gained. v3 keeps A unchanged and adds no rollback features, so the telemetry stays clean.

---

## 2. Phases

### Phase 1 — Core prototype (v2, M0–M7) · **done**
One arena, 8 small patches, scripted Director, rollbacks, report, telemetry, Windows export.

### Phase 2 — Big patches (v3, M8–M13) · **current**
See `PLAN.v3.md`. Big slot, B1 "Time moves when you move", B2 "Turn-based" (player on the grid in M11, enemies on the grid in M13 after the owner found B2 too close to B1), 2 BIG prompts per run, adaptive path step 1 (taste, session only).
- **Content at the end:** 8 small patches, 2 big patches, 1 arena, 3 enemy types.
- **Run length:** ~10–12 min.
- **Must answer:** do permanent shifts feel like stakes? Do players gravitate to one genre?

### Phase 3 — Stages and the AI boss (v4)
- A run becomes **3 stages + a boss stage**. Each stage is an arena the AI proposes (2 choices, taste-leaned), with its own prompts; the big slot carries across stages.
- **A stage = an arena + its default patch** (owner, 2026-11-19). Each stage type ships with a patch that defines it (e.g. a low-gravity lab, an ice floor, a dark server room). Variations of the stage swap that default for a related patch, so the same arena plays differently from run to run. The default patch is the stage's, not the player's: it is not in the player's stack and ends with the stage. **The player is not told the default patch** (owner, 2026-11-19): the stage choice shows the arena, not its patch; the player discovers it by playing. Under rollback option D, the default patch is one of the AI patches the player can roll back.
- **Arenas as data:** 4–6 arenas built from block rectangles (the v2 seam), each readable top-down and with gravity.
- **Boss:** the AI patches the arena live (spawns, rules, walls) on a timer. The boss's role for rollbacks depends on the rollback study (1.5); option D makes its patches the rollback targets.
- **First save on disk:** unlocked stages and the pool size (pool growth starts here: the run's first offers come from a starter pool of ~8, the AI ships 1–2 new mutations per finished run).
- **Content at the end:** ~16 small patches, 3 big patches, the medium tier with gravity in it, 4–6 arenas, 5 enemy types, 1 boss.
- **Run length:** ~20–25 min.
- **Must answer:** do stages give a run a shape? Does the boss make rollbacks feel like a weapon?

### Phase 4 — More genres (v5)
- **Tower-defense big patch:** the player places turrets on the grid (B2's grid reused) between waves; shooting becomes building.
- ~~**Turn-based, full:** enemies move on the grid and in turn order.~~ Pulled forward to v3 M13 (owner, 2026-11-20).
- **JRPG card battle** as a **special stage type** (not a big patch): a stage where fights are turn-based card duels, entered from the stage choice.
- **Taste saved on disk**; end-of-run ratings become the hidden meta-progression.
- **Content at the end:** ~24 small patches, 4–5 big patches, 1 special stage type.
- **Must answer:** does each genre stand on its own for a whole stage? Do players push "their" genre further?

### Phase 5 — The AI as a character, and endings (v6)
- The AI's personality and lines evolve with your path (what you pushed, what you refused, how often you rolled it back).
- Menu takeovers, music changes, the AI "breaking" its own UI (previously out of scope).
- **Endings:** 3–4, each a summary of a main direction of play, reached after enough runs on that path.
- **Must answer:** does the player feel the AI knows them?

### Phase 6 — Content and release (v7)
- Art and audio direction (replacing placeholder shapes), a first-person view patch if the seams still hold (v2 section 15).
- Content pass to the release targets, balance from telemetry, a public demo (itch.io / Steam Next Fest), then release.

---

## 3. Scope at a glance

| | v2 (done) | v3 | v4 | v5 | v6 | release |
|---|---|---|---|---|---|---|
| Small patches | 8 | 8 | ~16 | ~24 | ~28 | 30+ |
| Big patches | 0 | 2 | 3–4 | 4–5 | 5 | 5–6 |
| Arenas / stages | 1 | 1 | 4–6 + boss | + card stage | — | 8+ |
| Enemy types | 3 | 3 | 5 + boss | 6 | — | 8+ |
| Run length | 6–10 min | 10–12 | 20–25 | 25–30 | — | 25–35 |
| Saved on disk | telemetry | telemetry | unlocks, pool | + taste | + path, endings | all |
| Playtest gate | G3 | G4–G6 | stages, boss | genres | personality | demo |

---

## 4. Open decisions
1. ~~Gravity: small or big?~~ **Medium** (owner, 2026-11-19). Still open: the medium tier's rules (1.4).
2. BIG prompts per run: 2 or 3, and whether they move to stage boundaries in v4.
3. ~~Rollback: keep, rework or replace?~~ **Option D, rollbacks as a weapon** (owner, 2026-11-19). Still open: keep any self-rollbacks, and how charges are gained (1.5).
4. Does a stage choice replace a BIG prompt, or do both exist?
5. ~~Does the player see a stage's default patch?~~ **No, it is discovered in play** (owner, 2026-11-19). Still open: can a stage's variation conflict with the player's patches?
6. Pool growth: does the AI ship new mutations on a schedule, or because of your taste (v4)?
7. When the first real playtest happens (skipped for v2 by choice; strongly needed before v4's boss, and the rollback study needs it).

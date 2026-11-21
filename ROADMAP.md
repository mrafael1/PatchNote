# Roadmap v2 — the game grows by versions

Where the game is going, in phases. Each phase becomes a builder plan (`PLAN.md`) only when it starts. This file holds the direction, the progression model and the scope of each phase. Numbers are starting targets, to retune from playtests.

**Supersedes:** `ROADMAP.v1.md` (owner direction change, 2026-11-21, from the concept doc `alone_alone_lab_progression.html` and the discussion that followed). PLAN v4 (`PLAN.md`) is **on hold after M14**; section 5 says which of its pieces survive.

**The game in one line:** a roguelike where an AI developer builds the game with you. Every run is a playtest of the current build. Between runs the AI ships the next version, so the game itself (its genres, its runs and its look) is the progression.

**Never in scope:** RTS / squad control. Real generative AI at runtime (the AI stays scripted; mockup images and clips are authored, never generated).

**Working name:** none for now (owner, 2026-11-21). "Patch Notes" stays in code and banners until a name is chosen.

---

## 1. The model

### 1.1 Three loops
| Loop | Where | What the player does |
|---|---|---|
| **Inside a run** | in a genre | plays; takes small and medium patches at prompts; at a stage end may switch genre |
| **Between runs** | the dev session | reads the playtest report, picks 1 of ~3 proposals, reads the patch notes of the new version |
| **Across runs** | the save | the game's version goes up; genres mature; the look improves; the AI remembers |

### 1.2 The game's version is the meta-progression
- A new save starts at **v0.0**: squares, one shooter arena, short runs (~3 min), very readable first prompts. Nobody sits through a long run on a flat prototype.
- Every dev session ships the change the player picked, so the version moves every run. No XP bars, no gauges: progress shows only as versions, patch notes and things that changed.
- The game reaches a **1.0 ending** (a "release" moment), then **keeps getting 1.x updates**: more depth, more genres, later features.
- **Proposed bump rule:** each dev-session pick is a patch step (v0.3.1 → v0.3.2). A genre stepping up its maturity ladder (1.3) or a look tier (1.6) is a minor step (v0.3.x → v0.4.0). **Proposed 1.0 rule:** 1.0 ships when the save reaches a total number of maturity steps, from any genres, so a player who sticks to one genre is never forced through all of them. To confirm (section 6).
- The in-run build counter stays as flavour: "v0.4.2 · build 5" during a run. The report no longer says "v1.0 shipped" at the end of a won run.

### 1.3 Genres, each a project of its own
**Genres ("at least 4/5 big games"):** top-down shooter, platformer, turn-based, a card dungeon crawler (owner: "card game could be one too"), and **a 5th slot left open**. Whether the 5th ships before or after 1.0 is undecided (section 6). Time-moves-when-you-move (B1) and horde are **patches, not genres**.

Every genre climbs the same ladder, on its own. A step is a state **in the player's save**:

| Step | What it means for the player |
|---|---|
| **Mockup** | a rough test build: one stage, rough look, a fixed starter set of patches. Born from a dev-session pick among 3 mockup takes (1.5). |
| **Playable** | the full pool of patches is offered in it. Can be a switch target. |
| **Stages** | its run has several stages with their own layouts and pacing. Its first mediums can arrive from here on. |
| **Boss** | it has a boss at the end of its run, designed for that genre. |
| **Deep** | its own enemies, more mediums, more patches built around it. |

- **What makes a genre grow: both picks and play.** A dev-session pick chooses the direction; a genre can't step up until it has been played enough (a hidden threshold, never shown as a bar). A Mockup genre gets that play from runs started in it (next point).
- **Each genre owns its run.** Its stages, pacing units (seconds, turns, rooms), controls, enemies, camera and boss belong to it. A genre is never limited by another genre.
- **The shell is thin and only shared where it adds something:** the save and version, run start, prompt points, stage ends, run end, report, dev session and patch notes. A genre tells the shell two things: "a stage ended" and "the run ended". Nothing in the shell may block a genre's feature.
- **Run start:** the player picks one of their Playable genres. The top-down shooter is the only Playable genre at v0.0. **Proposed:** Mockup genres are also listed, marked "test build", so the player chooses to try them. Never forced. To confirm (section 6).

### 1.4 Patches and the build
| Tier | Scope | Where it comes from |
|---|---|---|
| **Small** | one mechanic (bounces, explosions, splitting enemies) | prompts in every genre |
| **Medium** | how one genre moves or sees: a *change* to that genre's base (for the platformer, a gravity change such as reversed gravity) | prompts inside that genre; never a genre change |
| ~~Big~~ | ~~the genre~~ | gone: genres are picked at run start and switched between stages |

- **Patches and mockups are the core gimmick (owner)** and must feel rewarding. Each patch must be strong and visible. The next prompt is announced visually.
- **The build follows you.** A genre switch happens only **at a stage end, never during play**. The AI offers it and the player can always say no. Every patch in the build carries over.
- **No dormant patches.** Every patch, medium included, has its own take in every genre a switch can reach. A take is a **creative reinterpretation, not a literal port**: platformer gravity can be a card that throws enemies into the void, a black hole card, or a double-jump card that nods to Mario. The player should recognise their earlier build in the new genre.
- **Content rule (for us, at build time):** a patch ships in the pool only with a take in every genre past Mockup; a genre ships past Mockup only with a take for every pool patch. So content grows as patches × genres. Prefer fewer, stronger patches.
- **Inside a Mockup genre (for the player):** only its fixed starter set is offered, so every patch it offers has a take. A Mockup genre is never a switch target, so a build never has to cross into one.

Example takes (illustration only, to show the spirit):

| Patch | Shooter | Platformer | Turn-based | Card crawler |
|---|---|---|---|---|
| explode_on_hit | shots blast on contact | stomps blast | hits blast the 8 tiles around | "Volatile": attack cards hit neighbours |
| enemies_split | killed enemies split in 2 | split into falling halves | split into 2 grid actors | "Mitosis" enemy intent |
| gravity_reversed (platformer medium) | shots arc upward, enemies float | gravity flips | push an enemy off the grid edge | "Void" card throws an enemy out of the room |

### 1.5 Between runs: the dev session
1. **Playtest report:** what happened in the run. Wins and deaths both count and both lead to a dev session.
2. **About 3 proposals**, in one of two shapes:
   - **3 different changes**: "add stages to the platformer", "new enemy", "better hit feel".
   - **3 mockup takes on one change**: the same feature, genre or look done three ways. Each is shown as a still image or short clip plus one line. Short playable tastes come later if time allows. **Scope rule:** the three takes are presets of one build (parameters, rule sets, palettes or skins), never three separate builds. For a new genre, they are three flavours of the same Mockup code. An unpicked take can come back later as its own proposal.
3. **The player picks one.** **Proposed:** now and then the AI also ships a change of its own, shown in the notes. To confirm (section 6).
4. **Patch notes screen:** "Version 0.x.y" and what changed. Then the next run starts.

Proposals lean on what the AI learned you like (taste, hidden), what you played, and the AI's own agenda.

### 1.6 The look grows (shared by all genres)
Squares → juice (shake, particles, hit stop, muzzle flash) → palette and shaders → sprites and animation → music, menus and UI. Each tier is a dev-session proposal, often as 3 mockup takes ("which look do you prefer?").
- **The line between feel and look:** v0.0 has the **readability** that "fun before meta" needs (enemy telegraphs, a clear hit and kill confirmation). The **spectacle** is look tier 1. The shake and particles the shooter already has are turned down at v0.0 and come back as the first look ship, a cheap and visible first reward. **Shared art direction first:** a limited palette and assets reused across genres; genre-specific variants only where needed. Cheap steps (palette, shaders, juice, layered music) come before real sprites.

### 1.7 The AI
- It remembers your attempts, voices preferences, pushes back, and proposes its own ideas in dev sessions.
- **Later features (not core):** live patches during a run (it saves you, nerfs a monster that's too strong, or offers to keep a broken build), and rollbacks. A rollback could itself be something the AI ships ("I added an undo button").

### 1.8 Rules progression must follow
1. **Fun before meta.** Each genre must be fun with no AI at all. v0.0 is short and raw, but never boring.
2. **Hidden systems, visible growth.** No XP bars. The player sees versions, proposals and changes.
3. **Never locked out.** A refused proposal comes back later. Not yet built is not locked.
4. **Push-back stays.** In a "3 different changes" session, one card can be the AI's agenda. It is a tuning value, never zero over a run of sessions.
5. **Power stays inside the run.** Across runs the game gains variety and depth, never stats. A run-1 and a run-50 player start with the same HP.
6. **No genre change during play.** Switches happen at stage ends, offered, never forced.
7. **No dormant patches** (1.4).
8. **The shell never blocks a genre** (1.3).

---

## 2. Inside a run

- **Prompts:** small (and, in a genre that has them, medium) patches at prompt points the genre places. Picking heals 1 HP as today.
- **Stage end:** the genre reports it; the shell may offer a switch to another Playable genre (the build is translated, 1.4).
- **Run length:** ~3 min at v0.0, growing as the start genre matures (stages, then a boss); ~20–25 min is the 1.0 target for a full run.
- **Proposed run shape:** the start genre's maturity sets the run's stages. A switch target only needs to be Playable; until it has a boss, a genre without one plays its own harder final stage. To confirm (section 6).

---

## 3. What happens to the existing work

| Piece (built through M14, `875912f`) | Becomes |
|---|---|
| Top-down shooter (arena, player, 3 enemies, spawner, run loop) | the starting genre, ported into the genre interface |
| Gravity code (`gravity_on`'s rules, Mover physics, gravity-aware enemies) | the platformer's **base rules** (gravity is always on there). `gravity_on` stops being a patch. The platformer still needs levels with goals, pits/void and its own attack |
| `gravity_reversed` | a **platformer medium** (a gravity change); its `requires gravity_on` goes away |
| `jump_button` | stays a small patch (shooter take: hop + slam; platformer take: double jump) |
| Turn-based (B2: `turn_mode`, TurnClock, TurnLogic, overlay, ~1,400 test lines) | a genre, the closest to standalone. Also the seed for the card crawler's grid and enemy intents |
| B1 `motion_time` | a patch. Its logic moves out of RunState into the patch |
| `horde_mode` | already a small patch |
| Card dungeon crawler | new genre, built later |
| AI layer, option D rollbacks, hidden stage patches, M14 scaffold | **parked**: switched off, kept in git; may come back as live patches or rollbacks |
| Big slot, BIG prompts, `swap_big` | replaced by the run-start genre choice and the stage-end switch |
| In-run `build_number` as version | replaced by the saved game version |
| Session-only taste | saved on disk |
| Telemetry, bots, `check.ps1`, smoke matrix, export | kept; their genre keys change from "big patch id" to "genre" |

**Architecture contracts that change:**
- v3's "nothing branches on genre" is replaced by **per-genre takes**: a patch keeps one id and one folder, with a take per genre in `mutations/<id>/<genre>.gd` (the folder-isolation test still holds).
- `RunState` gets a `genre` field separate from the patch layers. Hooks dispatch to the active genre's take. `patch_state` is reset on a switch.
- `WorldRules` splits into a shared part plus per-genre rule bags (a card crawler has no gravity or projectiles).
- `main.gd` shrinks to the shell. Arena, spawner, TurnClock, TurnOverlay and TimeTint become genre-owned.
- Mediums get a genre field. Requires/conflicts become per-genre, and the cross-genre conflicts (e.g. `gravity_on` vs `turn_mode`) go away.

---

## 4. Phases

### Phase 1 — Core prototype (v2, M0–M7) · **done**
One arena, 8 small patches, scripted Director, rollbacks, report, telemetry, Windows export.

### Phase 2 — Big patches (v3, M8–M13) · **done**
Big slot, B1 and B2, 2 BIG prompts per run, session taste. See `PLAN.v3.md`.

### Phase 3 — Stages and the AI boss (v4) · **stopped after M14**
M14 built the AI layer, the medium tier and option D. The rest is replaced by this roadmap (section 5).

### Phase 4 — Foundations: versions, the dev session, v0.0 (PLAN v5) · **next**
- Save on disk: game version, genre maturity, play time per genre, taste, dev-session history, look tier.
- Thin shell + genre interface; the shooter ported as the first genre. Park the AI layer and rollbacks; turn B1 into a patch; remove the big slot.
- Per-genre takes in the patch data model (only the shooter's take exists yet).
- Dev-session screen (report → 3 proposals → patch notes), with **both shapes**. The first mockup session is look tier 1 for the shooter: 3 takes on its juice, each an image or clip with one line. That's cheap, and it tests the core gimmick from the start.
- Short v0.0 runs (~3 min, one arena).
- Readability pass on the shooter (fun before meta): enemy telegraphs, clear hit and kill confirmation, camera lookahead. The existing shake and particles are turned down at v0.0 for look tier 1.
- **Content at the end:** 1 genre (shooter, Playable), 7 smalls (today's 6 + `motion_time`), a first chain of dev-session changes for the shooter (a new enemy, new patches, look tier 1).
- **Must answer:** is v0.0 fun for 3 minutes? Does the dev session feel like a reward? Do players want "one more version"?

### Phase 5 — Stages, the second genre and the build crossing over
- Stage plumbing (M16's kept parts, section 5) and the shooter's Stages step. This comes first: the switch needs stage ends.
- Turn-based (proposed, since it is closest) as a genre: its own map, its own run, pacing in turns, a controller that no longer hijacks the shooter player. It starts as a Mockup picked from 3 flavours, then grows to Playable.
- Takes for every pool patch in turn-based; the stage-end switch with the build translated.
- **Must answer:** do players recognise their build after a switch? Do takes feel creative, not like a port?

### Phase 6 — Platformer, mediums, the look track
- Platformer as a genre: levels with goals, pits and void, a native attack; gravity always on; gravity changes (`gravity_reversed`, `low_gravity`) as its mediums.
- Look tiers 2–3 (palette and shaders, first music layers) as dev-session proposals.
- First bosses (shooter first), each designed for its genre.
- **Must answer:** does each genre stand on its own? Does the look improving feel rewarding?

### Phase 7 — Card dungeon crawler and 1.0
- Card dungeon crawler (seeded by TurnLogic's grid and intents).
- **Build goal:** every genre that ships for 1.0 has a boss built. **In-save goal:** the 1.0 rule (1.2), which never forces a player through every genre.
- Sprites, animation, menus and UI; the 1.0 ending.
- Content pass and balance from telemetry, a public demo (itch.io / Steam Next Fest), then release.
- **Must answer:** does the arc from v0.0 to 1.0 hold? Does the 1.0 moment land?

### After 1.0 — 1.x updates
Live patches, rollbacks, more depth per genre, playable mockup tastes, and the 5th genre if it doesn't make 1.0.

---

## 5. PLAN v4 pieces that survive

| v4 milestone | Fate |
|---|---|
| M15 Arenas as data | **kept**, re-scoped: arena validity is per genre (not "readable top-down and with gravity") |
| M16 Stage flow | **plumbing kept** (StageDef kind, run-loop sub-states, stage clear, carry table, cross-stage determinism test), built in Phase 5. The stage choice panel and BIG-at-stage-end become the stage-end switch offer. Dropped: the 3-stages-from-run-1 shape, hidden stage defaults and their reveal, earned charges. The vision mediums `close_camera`, `lights_out` and the `darkness` rule are proposed as shooter mediums |
| M17 Stage mediums | `low_gravity` kept as a **platformer medium**; `ice_floor`'s genre to decide |
| M18 New smalls | kept as content; each needs takes per genre; parity rule kept |
| M19 Save | **moved first** (Phase 4); its mechanics kept (inert by default, versioned, atomic, corrupt-file handling), its schema rewritten; taste-led 1+1 shipping replaced by the dev session |
| M20 Bomber, lancer | kept as shooter content |
| M21 Playtest build | kept as a discipline |
| M22 Boss | the "AI patches the arena + rollbacks as weapons" boss is parked with rollbacks and may return with them. **Proposed:** bosses designed per genre until then |
| M23 Third big | dropped; Stealth or On the beat can pitch for the open slot or become patches |
| M24 Retune to 20–25 min | dropped; run length now grows with the version |

`check.ps1`'s rollback gate (`--big=motion_time ... stage_reverts=1`) depends on the scaffold, B1-as-big and rollbacks, so it changes in Phase 4.

---

## 6. Open decisions
Each has a proposed default; owner to confirm.

1. **Version bump rule** (1.2): pick = patch step, maturity or look step = minor step.
2. **The 1.0 rule** (1.2): a total of maturity steps from any genres (proposed), or every genre has a boss (forces every player through every genre).
3. **The 5th genre:** before or after 1.0. Stealth or On the beat can pitch for it.
4. **Mockup genres at run start** (1.3): listed as "test build" and chosen freely (proposed), or reachable only some other way.
5. **The AI shipping its own change** in some dev sessions, on top of the player's pick (1.5).
6. **Run shape across a switch** (2): the start genre's maturity sets the stages; a switch target needs only Playable.
7. **Play threshold for a maturity step** (1.3): a number of runs or minutes played in that genre; values from playtests.
8. **How long is the arc to 1.0:** how many runs from v0.0 to 1.0 (~30 proposed).
9. **Second genre:** turn-based (closest in code) or platformer (closest to the concept doc).
10. **Genres of the leftover v4 mediums:** `ice_floor`, `close_camera`, `lights_out` (5).
11. **Report ratings (keep/cut):** keep as a taste input next to the dev-session pick, or drop.
12. **What carries between runs inside the build:** nothing (each run starts empty, as today), proposed.
13. **When the first real playtest happens:** strongly needed before Phase 4 closes, since "is v0.0 fun" can't be answered by bots.

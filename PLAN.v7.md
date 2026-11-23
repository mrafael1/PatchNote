# Build Plan v7 — The second genre: a tactical deckbuilder, and the stage-end switch

> **DROPPED (2026-11-23), never built.** The owner replaced this plan with the campaign vision in `ROADMAP.md` v3. The tactical deckbuilder, the stage-end switch and the "take in every genre" rule are out. The card ideas move to the RPG's Cards path. PLAN v8 (Phase 5: session runner, mascot, rule book, Stage 1) replaces it.

**For:** the builder agent
**Goal of this build:** the game gets its **second genre**, the owner's own design: a turn-based **tactical deckbuilder** on a grid (owner, 2026-11-23). It arrives the way the roadmap says a genre arrives: a dev-session question with three mockup flavours, then a rough test build you can start a run in, then a Playable genre. Once it is Playable, a staged shooter run can **switch into it at a stage end, and back**, and your build comes along, **translated**: every shooter patch has a card take.
**Engine:** Godot **4.7.x stable**, GDScript, 2D, unchanged.
**Roadmap:** `ROADMAP.md` Phase 5, second half (5b). The owner's genre replaces open decision 9 (turn-based or platformer) and merges the turn-based genre with Phase 7's card crawler.
**Supersedes:** `PLAN.v6.md` (Phase 5a, M31–M36). **Every v2–v6 contract stays in force** unless this document changes it.

Milestones continue from **M37**.

---

## 0. The owner's design (2026-11-23), and what v7 takes from it
The owner's words, translated from French:
> **Genre 2 — Tactical Deckbuilder.** A turn-based tactical roguelike combining deckbuilding with grid combat inspired by Dofus. The player builds their deck of cards over time to attack, defend, move and manipulate the terrain. Positioning, resource management and the order cards are played in are at the heart of the strategy. The genre's hallmark is **evolving and combinable cards** that can create complex, sometimes unexpected synergies. Some cards can change other cards' properties, fuse their effects, or trigger combos depending on the order they are played in. The meta-progression grows this mode from a rudimentary system with a few cards and enemies into a real tactical deckbuilder, with new systems, advanced mechanics, stages, bosses and great strategic depth.

What v7 builds of it, and what it leaves to later steps (the genre's own ladder, ROADMAP 1.3):

| Owner's design | v7 (Mockup → Playable) | Later (its Stages, Boss, Deep steps: PLAN v8+) |
|---|---|---|
| Grid combat, positioning | an 11 × 8 board with blocks; action points (AP) and movement points (MP) per turn | more boards, terrain types, line of sight |
| Deck of cards to attack, defend, move, manipulate terrain | a 10-card starter deck, a hand of 5, draw/discard piles; cards from all four families | card rewards beyond patches, removal, a shop |
| Resource management | 3 AP and 3 MP a turn; cards cost AP; some cards give MP or AP | more resources (energy that carries over, card upgrades) |
| Order matters, combos | the **Chain** keyword: a card gets a bonus when it follows a card of another family | combos as a system of their own |
| Cards change other cards, fuse | **modifiers**: most patch takes change your cards ("your attack cards also splash") | **Fuse** and **evolve** as their own big question (section 7) |
| A few cards and enemies at first | 3 enemy kinds, a dozen cards | more enemies, elites, a boss |

Dofus inspires the mechanics only (a grid, AP and MP). No names, classes or art from it.

---

## 1. The genre: Tactics (working title "Card Tactics")
Its id is `tactics`. Everything it owns lives in `genres/tactics/`: the shell never names it (the M34.2 lint).

### 1.1 A fight
- **The board:** 11 × 8 tiles, a few blocks, as data (`BoardDef`, like `ArenaDef`). The player is one unit; 3–5 enemy units start on the far side.
- **A turn:**
  1. Draw up to 5 cards.
  2. Get 3 AP and 3 MP.
  3. Spend them in any order: move one tile for 1 MP, or play a card for its AP cost.
  4. End the turn: the hand is discarded.
  5. Each enemy acts on the **intent** it showed (an arrow or a marked tile), then shows its next one.
- An empty draw pile reshuffles the discard pile, with the run's seeded RNG.
- **HP:** the player keeps the shooter's 5 HP; enemies deal 1. A patch pick heals 1, as in the shooter. Enemies have 2–4 HP and cards deal 1–3, so numbers stay small and readable.
- **Win** a fight by clearing the board. **Lose** the run at 0 HP.
- **Fun before meta (ROADMAP 1.8 rule 1):** a fight must be fun with no AI at all. The intents make it a puzzle you can read.

### 1.2 Cards
- Cards are data (`CardDef` in `genres/tactics/cards/`): title, cost, family (attack, defend, move, terrain), range and area, and a list of effects (damage, block, push, pull, gain MP, place block, break block).
- **The starter deck (10):**

  | Card | Cost | Family | Effect |
  |---|---|---|---|
  | Strike ×3 | 1 AP | attack | 2 damage, adjacent |
  | Bolt ×2 | 2 AP | attack | 1 damage, range 4, straight line |
  | Guard ×2 | 1 AP | defend | +2 block this turn |
  | Dash | 0 AP | move | +2 MP |
  | Shove | 1 AP | terrain | push adjacent 1 tile; into a block or a unit: 1 damage |
  | Raise | 1 AP | terrain | a block appears on an empty tile in range 3 (until the fight ends) |
- **Chain** (order matters): a card with *Chain* gets +1 to its effect when the card played just before it is of another family. Two starter cards have it (one Strike, the Shove).

### 1.3 Enemies
- Three archetypes, each with an intent the player can read:
  - **Grunt:** walks to you and hits.
  - **Archer:** shoots along a line and marks it.
  - **Brute:** spends a turn winding up, then charges in a line.
- **The save's enemy answer carries over:** the shooter's Tank, Bomber or Lancer has a tactics twin.
  - Tank: Brute with 2 more HP.
  - Bomber: explodes on the tiles around it when it dies.
  - Lancer: charges two lines.
  - The same `fork_enemy` answer shapes both games.

### 1.4 A run in Tactics
- **The Mockup run (a test build):** one stage of **3 fights**. After each fight the shell's prompt opens, and picking a patch adds a card or changes your cards (its tactics take). Only the Mockup's fixed starter set of patches is offered (ROADMAP 1.4).
- **Prompt points are the genre's:** a fight's end, not a meter of seconds and kills. The shell asks the genre (M37).
- **Pacing in turns:** a fight lasts about 6–10 turns, so a Mockup run is ~25 turns, about 5–8 minutes for a human. The bot's number is turns, not seconds.
- **The bot** plays greedily: kill if it can, otherwise step out of marked tiles, then close in. That is enough for pacing and crash sweeps. Bots read pacing, not fun.

### 1.5 The patches' takes: the build, translated
Every pool patch gets `mutations/<id>/tactics.gd`. A take is a creative reinterpretation, not a port (ROADMAP 1.4). Most of them **change your cards**, which is the owner's "cards that change other cards".

| Patch | Shooter | Tactics take (proposed) |
|---|---|---|
| explode_on_hit | shots explode | **Volatile:** attack cards also deal 1 to the tiles around the target |
| bouncing_projectiles | shots ricochet | **Ricochet:** Bolt hits a second enemy within 3 tiles of the first |
| enemies_split | killed enemies split | killed enemies split into two 1-HP units on free tiles nearby |
| jump_button | jump + landing slam | **Leap** card: jump 2 tiles over anything; landing deals 1 around |
| auto_attack | fires at the nearest | **Reflex:** each AP you don't spend fires a 1-damage bolt at the nearest enemy |
| motion_time | the world moves when you move | **Momentum:** each tile moved this turn adds +1 to your next attack |
| orbit | two shards circle you | **Orbit:** enemies that end a turn next to you take 1 |
| echo | shots fire again 0.6 s later | **Echo:** the first card you play each turn plays again at the start of the next |
| magnet | enemy shots curve into enemies | **Lure:** enemy line attacks bend into the first enemy in the line |
| well | a kill leaves a pull field | **Well:** a killed enemy leaves a tile that pulls units 1 tile a turn |
| elite | every 8th enemy is shielded | one enemy per fight has a 3-hit shield; killing it clears all intents for a turn |
| horde_mode | 3× enemies, −40% HP | twice the enemies at 1 HP less; you draw 1 more card |
| hunter | an unkillable stalker | a stalker unit follows you from fight to fight; 3 hits stun it for a turn |

- **The Mockup starter set:** explode_on_hit, enemies_split, bouncing_projectiles, jump_button (the shooter's starters minus the parked `turn_mode`).
- **Playable needs all 13** (the content rule): a pool patch ships only with a take in every genre past Mockup.

### 1.6 The three Mockup flavours (one build, three presets)
The question shows three stills, each a preset of the same code (a deck list, a board set, rule values), never three builds (ROADMAP 1.5):
- **Skirmish:** open boards, more enemies, a deck heavy in attack. Fast, aggressive.
- **Siege:** boards full of blocks, terrain cards (Shove, Raise, Break) in the deck, damage for pushing into walls. The board is the weapon.
- **Combo:** a hand of 4, more Chain cards, 0-cost connectors. Order is everything.

The flavour you pick stays the genre's base. A rework swaps it, as the Stages flavour (v6).

---

## 2. How the genre arrives in a save
| Step | How | Shape in the dev session |
|---|---|---|
| **Mockup** | the question "I want to try a second game. Three takes on it. Which one?" (3 flavour stills). Ready once the shooter has its Stages step and 10 shooter runs | FORK (big question, mockup stills): a new mechanic from a run's start |
| **Test build** | the start screen lists Tactics as **"test build"** next to the shooter. Never forced (ROADMAP open decision 4, the proposed default) | — |
| **Playable** | the AI announces it once Tactics has **4 runs** and all 13 takes exist: "Tactics is ready: every patch has its card now. It can come up at a stage end." | a new session shape, **STEP** (no question: owner, M34.2: questions only for big run-start features) |

- `GenreDef.playable` stops being a constant: it reads the save's step (`mockup` / `playable` / ...). The shooter starts Playable as before. Inert saves see every genre Playable, as "everything unlocked" has always meant.
- **The version:** the Mockup and Playable steps are minor bumps (maturity steps), like Stages.

---

## 3. The stage-end switch
Once Tactics is Playable, a staged run can cross between genres.
- **At a stage end** (not the last one), the shell offers: "Next stage in Tactics?" with **Stay** and **Switch**. It is offered, never forced (ROADMAP 1.8 rule 6), and its default is Stay.
  - **Who offers:** the AI, with a tuning chance per stage end (default 0.5), and never twice in a row in one run.
  - **The bot:** takes it with `--switch-chance`.
- **What carries:**
  - HP (the same 5-HP scale in both genres);
  - the stack of patches: each patch disables its old genre's take and enables its new one;
  - `patch_state`, which is reset (a take keeps no state across genres);
  - kills, the build counter and the run's taste.
- **What the switched stage is:** the target genre's own stage at that index. In Tactics, one fight per stage, harder as the index grows. A switch back at the next stage end returns to the shooter's next stage. The last stage is the release candidate in whichever genre it is played in.
- **The shell part:** a genre change mid-run, which v5 forbade (`RunState.genre` was "never set during a run"). It now changes **only at a stage end**, through one shell function (`switch_genre(id)`). It tears down the genre node and builds the next with the carried state. The determinism test covers a run that switches twice.
- **Telemetry:** a run record lists the genre of each stage (`stages.genres`), and the switch offers and answers.

---

## 4. Shell changes (what must stop assuming one genre)
- **Prompt points** come from the genre. The `Genre` contract gains `prompt_point()` (the genre says "open a prompt now"). The shooter keeps its meter by asking the Director on its own schedule. A genre may also say it has none.
- **The HUD:** a shared strip (HP, version, gauge or "patch after this fight") plus a genre panel. Tactics shows AP, MP, the hand, the piles and the intents.
- **The start screen:** a genre choice when more than one genre is listed (Playable, then test builds).
- **Run records:** keys are per genre. Pacing is in turns for Tactics (`pace_unit = turns`), and the bot reports turns.
- **The shell lint stays:** no genre id in `main.gd`, `ui/`, `director/`, `devsession/`, `core/`.

---

## 5. Milestones
| # | Milestone | What ships | Numbers / gate |
|---|---|---|---|
| M37 | A second genre can exist | Genre-placed prompt points; `GenreDef.playable` from the save; a start-screen genre choice; a genre HUD panel hook; `switch_genre()` plumbing, tested with a test genre. The shooter is unchanged. | the one-arena and Gauntlet run hashes still match; the shell lint passes |
| M38 | Tactics: a fight | `genres/tactics/`: board as data, units, AP/MP, the deck and its piles (seeded), `CardDef` and the starter deck, Chain, the 3 enemies with intents, win and lose, the tactics HUD panel, mouse and keyboard controls, the bot. | bot: a fight ends (win or lose) in every seed; median turns per fight 6–10; same seed, same fight |
| M39 | Tactics: a run, and the starter takes | The Mockup run (3 fights, a prompt after each), the 4 starter takes as cards and modifiers, the run record and report, bot runs and the run hash. The save's enemy answer gives the tactics twin. | bot: median Mockup run 20–30 turns; mortal bot win rate reported; same seed, same run |
| M40 | The Mockup question | The `tactics` fork with three flavours (Skirmish, Siege, Combo) as presets, stills via `mockup_capture.gd`, the Mockup step written on ship, the test build at run start, rework of the flavour. | each flavour: median turns and mortal win rate (bot); the question comes once after Stages + 10 runs in a bot chain |
| M41 | Takes for the whole pool → Playable | The 9 remaining tactics takes; the STEP session shape ("Tactics is ready"); the content-rule test (every offerable patch has a take in every genre past Mockup). | parity (ROADMAP 1.8 rule 5): mortal bot win rate with the starter set vs the full pool within ±15% |
| M42 | The stage-end switch | The offer at a stage end, `switch_genre()` live, the build translated, HP and stack carried, telemetry, the bot's `--switch-chance`. | a staged run that switches twice replays identically; no patch left enabled in the wrong genre (the invariant check); bot chains reach Playable and switch |
| M43 | Playtest build | Export, PLAYTEST.md for G13, boot line with genre steps. | **G13 — owner playtest.** Does Tactics stand on its own as a game? Do the three flavours feel different? After a switch, do you recognise your build? Are the card takes creative, not a port? |

**G12 is still open:** the M36 build is ready to play at any time. Its answers (is Rework found, is the staged run better) can change M42's switch offer, so playing it before M42 helps. Nothing before M42 waits for it.

**Cut order if needed (first to last):** the Combo flavour (two flavours plus a third preset of Skirmish) → Lure and Well takes simplified → the AI's switch chance (always offered instead) → the Siege flavour's Raise and Break. **Never cut:** the fight with readable intents, the deck, Chain, the starter takes, the switch with the build translated, the determinism test across a switch, G13.

---

## 6. Tests and gates (each milestone adds to `check.ps1`)
- **Tactics core:**
  - deck draws and reshuffles are seeded;
  - AP and MP are spent and refused correctly;
  - every card's effect has a test;
  - intents resolve in order;
  - Chain fires only after another family;
  - a fight can be won and lost.
- **Takes:** every tactics take has a test: the modifier shows on the card and works.
- **The switch:**
  - the stack carries;
  - each patch has exactly one take enabled, the current genre's;
  - `patch_state` is reset;
  - HP carries;
  - the same seed replays a run that switches.
- **The shell:** the lint, the start screen choice, prompt points from the genre, and an inert save sees both genres.
- **Bots:** `bot_runs.gd --genre=tactics`, `--switch-chance=`, turns in the run line.

---

## 7. After v7 (proposed, not built)
- **Tactics' Stages step:** several boards per stage and terrain types; a big question with three takes.
- **The evolving and combinable cards**, the owner's hallmark, as their own big question, "How should your cards grow?":
  - **Evolve:** a card levels up after N plays in a run.
  - **Fuse:** play two cards of the same family in a row to fuse them for the fight.
  - **Mutate:** after each fight, one card gains a random keyword.
- **Boss** for each genre; the platformer (Phase 6).

---

## 8. What v7 must answer
1. Is Tactics fun on its own, with no AI and no switch?
2. Do the three flavours play as different games?
3. After a switch, does the player recognise their build in the other genre?
4. Do the card takes feel creative (cards that change cards), not like a port?
5. Is the switch offered at the right moments, and do players take it?

## 9. Still open (each with a proposed default)
- **The genre's title:** "Card Tactics" (working title). The owner may name it.
- **When the question comes:** after the shooter's Stages step and 10 shooter runs. Alternative: right after the Stages question.
- **Playable as an AI announcement** (STEP) rather than a question. Alternative: a question with three takes on its first Playable content.
- **The switch's AI chance (0.5 per stage end)** and "never twice in a row". Alternative: offered at every stage end.
- **One fight per switched stage.** Alternative: two shorter fights.
- **HP:** the same 5 HP in both genres. Alternative: a tactics scale (×3) mapped across a switch.
- **The patch prompt is the only deckbuilding in v7** (picking a patch adds or changes cards). Alternative: a card reward after each fight on top of the prompt.
- **The numbers** (3 AP, 3 MP, a hand of 5, a deck of 10) are a starting point; G13 tunes them.

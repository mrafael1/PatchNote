# Roadmap v3 — the campaign: building a game with an AI developer

Where the game is going, in phases. Each phase becomes a builder plan (`PLAN.md`) only when it starts. This file holds the direction, the structure and the scope of each phase. Numbers are starting targets, to retune from playtests.

**Supersedes:** `ROADMAP.v2.md` (owner's "final idea of the product", 2026-11-23, given by voice and then as a written breakdown). `PLAN.md` v7 (the tactical deckbuilder) is **dropped before any of it was built**. Section 4 says what happens to the existing work.

**The game in one line (owner):** *"The core concept is not simply to play a roguelike, but to experience the creation of one."* A story-driven game where the player helps an AI developer build a video game from scratch. A campaign of scripted development sessions (first target ~2–3 h, growing toward ~5 h) ends on a final boss, then unlocks a replayable roguelike made of the game you built together.

**Never in scope:** real generative AI at runtime. The AI developer is authored (lines, reactions and rule edits are written by us), so it can feel like a developer without API keys, per-player costs or unpredictable edits. RTS or squad control. The platformer, the card dungeon crawler, the tactical deckbuilder (v7) and a 5th genre are **cut** (owner, 2026-11-23). There are two genres.

**Working name:** none for now. "Patch Notes" stays in code and banners.

---

## 1. The model

### 1.1 Two modes
| Mode | What it is | Length |
|---|---|---|
| **Campaign** | scripted development sessions, grouped in 5 stages, ending on a final boss and the game's 1.0 | **first ~2–3 h**, then grown toward ~5 h by polishing and adding sessions little by little (owner, 2026-11-23) |
| **Endgame** | a replayable roguelike built from the player's campaign choices. The AI keeps experimenting during runs. | open-ended |

There are **no roguelike runs during the campaign.** Each session is a test of the current build. It's a bit different every time, and it's there to try a variation, have fun and learn something (owner). The roguelike is what the campaign builds.

### 1.2 A session
1. **Intro:** the AI developer says what this build tries ("today: enemies that shoot back").
2. **Play the build.** A session has a goal (survive 90 s, clear the room, beat the boss) and lasts 1–4 min early on and 5–12 min later. The AI reacts live and may change rules (1.4). Scripted events can fire (1.5).
3. **Debrief:** the AI talks about what happened. It notices how you played, admits its mistakes and draws conclusions.
4. **A choice, in some sessions:** 3 development options (1.6).
5. **Patch notes:** the version goes up and the next session starts.

- **The version is the story's progress marker:** v0.0 at the first session, **v1.0 at the release in Stage 5**, 1.x in the endgame.
- **Dying in a normal session never blocks the story.** It ends the session early, the debrief still happens, and the AI owns the problem ("that was too hard, my bad"). It tunes the build or lets you retry (owner-confirmed).
- **Bosses are checkpoints** (owner): a stage's boss must be beaten to move on. Retries are unlimited and restart at the boss, never the whole stage. After a few losses the AI offers help (tuning, a hint, a rule edit in your favour), but the boss still has to fall.

### 1.3 The AI developer (the mascot)
The main character and the main mechanic. It replaces the old "patch every X kills" gauge.
- **On screen:** a small character in a screen corner that never hides play. It has expressions and speech bubbles, and it can grab attention (point, shake, cover its eyes).
- **It reacts to what is on screen:** enemy count, near deaths, a corner you camp in, a weapon you never use, a streak. Reactions are authored lines with triggers, priorities and cooldowns, so it never spams.
- **It hosts every conversation:** session intros, debriefs, choices (the choice cards come out of its speech) and patch notes. There is no separate dev-session screen any more.
- **The player picks it, from 3 mascots** (owner, 2026-11-23). It's a fork in Stage 1, the moment the AI "gets a face", and the player's first real choice. Proposed trio: **the Cursor** (a text caret that later becomes a mouse pointer and does its edits by hand), **the App window** (a tiny window with a face, whose own title bar says "Not Responding" during the crash) and **the Blob** (squishy and expressive). **Cost rule:** all three share the same lines and triggers; they differ in body, animations and a few signature lines each. They're drawn from shapes, so the look path's shaders restyle them for free (sum, not product).
- **It grows:** in Stage 1 it has no words (blinks, symbols, broken text), then learns to talk. Its look follows the art path (1.8).
- **It remembers:** your choices, how you play (taste), your deaths. It brings them up later.
- **Its power:** it is **the main force of the game, also in the endgame** (owner). The finished game must not feel like a "natural" game. The AI changes how things work.

### 1.4 The rule book: what the AI can change
Every rule the AI might touch is a **live variable**, not code baked into walls, enemies or the player. An AI edit is a layer on top of the build's rules: it can last a few seconds, a session or forever, and it always reverts cleanly.

| Target | Example edits |
|---|---|
| **Walls** | bouncy, damaging, solid for enemies only, moving, gone (the screen edges wrap around), walls that become enemies |
| **Enemies** | allies for 10 s, copy your moves, tiny or huge, heal each other, flee from you |
| **Player** | controls inverted or rotated 90°, can't stop moving, bullets that heal enemies then explode |
| **World** | gravity sideways, gravity **through the screen** (1.5), time follows your movement, the camera rotates, the arena shrinks |
| **The game itself** | UI overload, flicker, a fake crash, the score becomes your HP |

- **The AI always announces before it edits:** the mascot reacts, there's a short warning (1–2 s), then the edit lands. The chaos must feel intentional and funny, never cheap.
- **Campaign:** edits are scripted per session. **Endgame:** the AI picks them from the rule book based on how the run is going.

### 1.5 Scripted events ("what is happening?!")
Planned moments the player doesn't see coming:
- **The AI changes the wrong thing:** gravity flips to the left, the top or the bottom, and the AI apologises in words a non-developer understands ("oops, I flipped the wrong thing!"), not in developer jokes.
- **Gravity through the screen:** everything falls toward the player's face. Units grow, smack against the glass (squashed, maybe a crack), then slide down and pile up at the bottom edge. Owner-confirmed.
- **Overload:** too much UI, too many numbers, then flicker.
- **The fake crash:** an in-game simulation of a Windows app that stops responding. The screen fades to white and a "Not Responding" bar appears.

Rules for events:
- Each one fires **once per save**.
- **The fake crash must not be too convincing:** 3–5 s at most, with the music or cursor still slightly alive and the mascot reacting right after. We want "wait… WHAT?", not an Alt+F4 or a bug report.
- **Photosensitivity setting:** flicker and flashes have a gentle alternative, offered at first launch.

### 1.6 Choices
After some sessions the AI offers **3 development options**. They cover gameplay mechanics, visuals, UI/UX, enemies, bosses and level design (owner).
- **Big forks:** the shooter path, the RPG path and the look. **Smaller forks:** an enemy type, the HUD style, a level layout, a boss.
- **Different players finish with clearly different games** (owner). About 10–12 forks across the campaign.
- **Content rule (for us):** forks are **independent slots**, so content grows as the *sum* of the answers, not their product. The story is written to work on every path, with path-specific lines on top.
- **The shelf stays:** answers not picked are kept, never lost (v6). **Rework is parked until the endgame:** revisiting decisions is a future feature (owner), and a scripted campaign can't have its past rewritten mid-story.

### 1.7 The two genres
Each genre has **3 paths that share one foundation** (owner), so development stays manageable.

**Top-down shooter** (the first genre, Stages 1–2):
| Path | Identity | In-run growth |
|---|---|---|
| **Arsenal** | weapons are cards (pistol, shotgun, laser); upgrading a card upgrades the weapon | card picks and card upgrades |
| **Auto** | Vampire Survivors-inspired: automatic attacks, increasingly powerful upgrades | level-up picks |
| **Survival** | resources: weapons and ammo come from enemies and the ground, kills give HP | pickups |

**Turn-based RPG** (the second genre, Stage 3), inspired by Final Fantasy and Dragon Quest:
| Path | Identity |
|---|---|
| **Classic** | traditional turn-based combat: abilities, weaknesses, strategic decisions |
| **Cards** | combat with cards, combinations and synergies (v7's "cards that change other cards" ideas live here) |
| **Timing** | Mario & Luigi- and Clair Obscur-inspired: dodge, block and parry in real time during enemy turns |

- **The RPG path is a free choice and is not shaped by the shooter path** (owner: a 1:1 mapping is "a wrong concept"). Shared across both genres: the look, the AI, and its memory of you.
- No genre switching during play. Combining and switching genres is a future feature (owner).

### 1.8 The look: 3 art paths, cheap by design
The look is picked early and then grows in tiers inside the chosen path (juice → palette and shaders → richer assets → music and UI).
- **One set of shapes, three renderings.** Each path is mostly shaders, palettes and a small set of textures, never three full sprite sets. Proposed:
  1. **Pixel:** low-resolution render with a limited palette, a retro feel.
  2. **Dark / neon:** a black background, glowing outlines and bloom. The darker option, and the closest to today's squares.
  3. **Paper / sketch:** wobbly hand-drawn lines on a paper texture. Totally different, and needs almost no assets.
- The mascot and the UI follow the look.

### 1.9 Rules for us
1. **Fun before meta:** every session is fun to play with no AI involvement. The AI is the main force, but the base has to stand on its own.
2. **Something new every session:** a mechanic, an event, a joke, a visual step. Early sessions are short (owner: "they are not really interesting").
3. **The AI announces before it edits** (1.4).
4. **Content = sum, not product** (1.6).
5. **Story never stalled:** no death or choice can lock the campaign. Bosses are the only gates (checkpoints with unlimited retries and AI help).
6. **Events once per save, and never too real** (1.5).
7. **Power stays in the session:** the campaign adds variety and features, not stats.

---

## 2. The campaign (5 stages; first version ~2–3 h)
A first cut, to rewrite while building. **First version: ~2 h 30, about 22 sessions.** Each stage is then grown toward the ~5 h vision (the "full" column) by adding sessions in its middle, never by stretching existing ones. Stage-end bosses are checkpoints (1.2).

| Stage | First version | Full | What happens | Big forks | Events |
|---|---|---|---|---|---|
| **1. The prototype** | ~20 min, ~6 sessions of 1–4 min | ~30 min | Nothing, then movement, shooting, enemies, a level. The AI is wordless, then learns to talk and the mascot appears. | **the mascot** (when the AI gets a face), the look (end of stage), an enemy type | the AI changes the wrong thing (gravity sideways) |
| **2. The shooter** | ~45 min, ~6 sessions + boss | ~1 h 30 | The shooter becomes a game: its path, more enemies, level design, the first boss. | **shooter path** (first session), level layout, HUD style, shooter boss | gravity through the screen |
| **3. The RPG** | ~45 min, ~6 sessions + boss | ~1 h 30 | The AI is bored: "what if we tried turns?" A new prototype from nothing, faster this time, then a real RPG. | **RPG path**, RPG enemies, RPG boss | rule edits inside turns (a turn order that cheats, an enemy that refuses to act) |
| **4. Overload** | ~15 min, ~2 sessions | ~45 min | The AI tries to have everything: features pile up until the game literally breaks. | after the crash: "what do we keep?" | UI overload, flicker, **the fake crash** |
| **5. Release** | ~25 min, ~2 sessions + final boss | ~45 min | The AI rebuilds and polishes for 1.0. The final boss, release, credits, the endgame unlocks. | the final boss's form | the AI's last edits in the boss fight |

**Final boss (owner liked it, 2026-11-23):** a two-phase fight in **your** shooter path, then **your** RPG path. **Its parts come from your shelf:** the answers you didn't pick come back as the boss's weapons and attacks ("you didn't want the shotgun? it did."). This gives the shelf a story job and makes each final boss different.

---

## 3. The endgame: your own roguelike
- **A run:** the shooter stage(s) in your path → the RPG stage(s) in your path → the final boss. Permadeath, seeds, in-run growth from your paths, and the look you picked.
- **The AI keeps experimenting:** live rule edits from the rule book, chosen by a director this time instead of a script. Difficulty and replayability rise (an ascension-style ladder).
- **Future features (owner):** revisiting development decisions (Rework comes back here), alternative versions of your game, and combining or switching between gameplay styles.

---

## 4. What happens to the existing work

| Piece (built through M36, `3734a70`) | Becomes |
|---|---|
| Thin shell, genre interface, save, game version, patch notes | **kept**. The version is the story marker. The RPG is genre 2. |
| Dev-session screen (report → fork → notes) | **becomes the mascot's debrief.** Forks and the shelf are kept; Rework is parked until the endgame. |
| In-run patch prompts and the PATCH gauge | **replaced:** in-run growth comes from the shooter path (cards / level-ups / pickups), and the AI's live edits come through the mascot |
| Patch pool (16 mutations) | **content.** Upgrades (explode, bounce, echo, orbit, split) feed the paths; `auto_attack` is the seed of the Auto path; rules (gravity_on/reversed, motion_time, horde, elite, hunter, well, magnet) feed the rule book and events. `turn_mode` stays parked: the RPG is a new genre, not the shooter on a clock. |
| `WorldRules` (recomputed from base + patch stack) | the seed of the rule book: AI edits become a layer on top |
| Broken first runs (M29b) | the opening of Stage 1 |
| AI director, dialogue, taste | the base for the mascot's lines, reactions and memory |
| Looks (tier 0/1, punchy), `glitch.gdshader`, `screen_fx` | the base for the 3 art paths and the glitch events |
| Arenas and stages as data, the Stages step (M34–M35) | level design in Stage 2 |
| Enemies (chaser, shooter, tank, bomber, lancer), `fork_enemy` | shooter content |
| Bots, telemetry, `check.ps1`, export | **kept.** Bots play scripted sessions for crash sweeps and pacing (bots read pacing, not fun). |
| PLAN v7 (tactical deckbuilder, stage-end switch, "every patch has a take in every genre") | **dropped, never built.** Its card ideas go to the Cards RPG path. |
| G12 playtest build (M36) | optional: still a useful check of the shooter's feel |

---

## 5. Phases

### Phases 1–5a · **done**
Core prototype (v2), big patches (v3), the AI layer (v4, M14), foundations: versions, dev session, v0.0 (v5), divergence: forks, shelf, rework, the shooter's stages (v6, M31–M36).

### Phase 5 — The new spine and Stage 1 (PLAN v8) · **next**
- **The session runner:** sessions as data (intro, build config, goal, scripted events, debrief, fork), a campaign as an ordered list, branching on fork answers.
- **The mascot:** a corner widget with expressions and speech, a reaction system (triggers, priorities, cooldowns), and hosting the debrief and choices.
- **The rule book:** live, revertible edits for walls, enemies, player and world, with the telegraph (warning) rule.
- **The event framework,** with the first event: the AI changes the wrong thing (gravity sideways).
- **Stage 1 rebuilt as ~8 sessions** (~30 min), from nothing to a small shooter, with the mascot learning to talk.
- **Must answer:** does a scripted session with a reacting AI beat the old run loop? Is the mascot charming, not annoying? Does "something new every session" hold?

### Phase 6 — Stage 2: the shooter grows
- The 3 shooter paths on one foundation; the 3 art paths; level design, HUD and enemy forks; the shooter boss; gravity through the screen.
- **Must answer:** do the three paths feel like three games? Do the three looks feel worth choosing?

### Phase 7 — Stage 3: the RPG
- The RPG foundation (party, turns, abilities, enemies), then the Classic, Cards and Timing paths; the RPG boss; rule edits inside turns.
- **Must answer:** is the RPG fun on its own? Does the "new prototype from nothing" land as a story beat?

### Phase 8 — Stages 4–5, the final boss and the endgame
- Overload, the fake crash, "what do we keep", release and the 1.0 moment, the final boss built from the shelf, credits.
- The endgame roguelike: run structure, AI director for live edits, the difficulty ladder.
- **Must answer:** does the arc hold over the first ~2–3 h? Does the crash land without scaring players off? Does the endgame feel like *your* game?

### Phase 9 — Release
Content and balance pass from telemetry and playtests, a public demo (itch.io / Steam Next Fest), then release.

### After release
Revisiting decisions (Rework), alternative versions of your game, combining and switching genres.

---

## 6. Open decisions
Each has a proposed default; owner to confirm.

1. **The mascot:** **decided:** the player picks 1 of 3 (1.3). Proposed trio: Cursor, App window, Blob. Names to choose.
2. ~~Death in a session~~ **decided:** ends the session early, AI tunes or offers a retry. **Bosses are checkpoints** that must be beaten (1.2).
3. **Stage count:** 5 (proposed) or 4 (merge Overload into Release).
4. ~~The final boss~~ **decided:** two phases (your shooter path, then your RPG path), attacks taken from your shelf.
5. **When the look is chosen:** at the end of Stage 1 (proposed), so Stage 2 is already "yours".
6. **The three looks:** pixel / dark neon / paper sketch.
7. ~~Writing~~ **decided:** I draft every line, the owner edits for tone. English first.
8. **The campaign's fork list:** about 10–12 forks (section 2), each with 3 answers.
9. **Events once per save:** a new save replays them (proposed), with an option to skip events already seen.
10. **Session length targets:** 1–4 min in Stage 1, 5–12 min later. **Campaign length decided:** first version ~2–3 h, then grown little by little (section 2).
11. **Report ratings and taste:** kept as hidden inputs for the mascot's memory and the endgame director.

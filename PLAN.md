# Build Plan v8 — The new spine: sessions, the mascot, the rule book, and Stage 1

**For:** the builder agent
**Goal of this build:** the game stops being a loop of runs and dev sessions and becomes **the first stage of a campaign**. The player helps an AI developer build a game from nothing. Every play is a **scripted session** with a goal. The AI talks through a **mascot** in a screen corner, reacts live to what happens, **changes the rules** in front of you (always warning first), and pulls one planned "mistake" on you. By the end of v8, Stage 1 ("The prototype", ~20 min) plays from a black screen to a small shooter, with the player's first two choices: **the mascot** and **the enemy**.
**Engine:** Godot **4.7.x stable**, GDScript, 2D, unchanged.
**Roadmap:** `ROADMAP.md` **v3**, Phase 5 ("The new spine and Stage 1").
**Supersedes:** `PLAN.v7.md` (dropped, never built) and `PLAN.v6.md` (Phase 5a, done: M31–M36). **Every v2–v6 contract stays in force** unless this document changes it. Section 0 lists what changes.

Milestones continue from **M37** (v7's numbers were never used).

---

## 0. Read this first

### 0.1 The owner's vision (2026-11-23), in one paragraph
A story-driven game where the player helps an AI developer gradually create a video game from scratch. It begins as an extremely basic prototype. Through scripted play sessions the AI discovers problems, experiments, fixes mistakes and turns the prototype into a full game. After some sessions the player chooses between development options. The AI is **the main force of the game**: it changes how walls, enemies and the player work, and the finished game must not feel "natural". The campaign is ~2–3 h first (5 stages: Prototype, Shooter, RPG, Overload, Release), then a roguelike endgame built from the player's choices. Full text: `ROADMAP.md` v3.

### 0.2 What changes from v6

| | v6 (now) | v8 |
|---|---|---|
| What you play | a **run** (~3–6 min); the next one after the dev session | a **session**: authored data with a goal (survive 45 s, clear a wave), 1–4 min in Stage 1 |
| What comes next | `DevSession.plan()` picks a shape: BASIC, FORK, IMPLEMENT, REWORK | **the campaign's next session**, in order; forks come where the session data says |
| The AI | lines in toasts, a PATCH gauge, a dev-session screen | **the mascot**: a corner character that reacts live, then hosts the **debrief** (conversation + choice cards + patch notes) |
| In-run patches | prompts paced by the Director's kill meter | **off in the campaign.** The AI hands you things itself, as **rule edits** (1.4). The prompt code stays for later paths |
| Changing rules | only by stacking patches you picked | **the rule book**: the AI edits walls, enemies, the player and the world, live and revertible, always with a warning |
| Surprises | none | **scripted events**, once per save. v8 has one: *the wrong variable* (gravity flips) |
| Choices | `look_1`, `fork_enemy`, `stages` | Stage 1: **`fork_mascot`** (new) and `fork_enemy`. The look and Stages forks move to Stage 2 (Phase 6) |
| Rework | a card in sessions | **parked until the endgame** (ROADMAP v3 1.6). The shelf stays |
| Start screen | genre and save line | **New game / Continue**, the save line shows the stage and session |

### 0.3 Principles that hold
- **Fun before meta:** each session is fun with the mascot muted (a debug flag, `--mute-ai`, proves it).
- **The AI announces before it edits** (ROADMAP v3 1.4): a line, a warning, and only then the edit.
- **Story never stalled:** a death never blocks a session's way forward (1.2.4). Stage 1 has no boss.
- **The shell never names a genre or a session id.** Sessions are data; the shell runs whatever the campaign says.
- **The reversibility invariant holds for rule edits:** after an edit expires, the rules and every entity are as if it never happened (tested like patches).
- **Content = sum, not product:** the three mascots share every line and trigger.
- **No real generative AI.** Every line is authored.

### 0.4 Out of scope (Phase 6 and later)
- The 3 shooter paths (Arsenal, Auto, Survival), the 3 looks (pixel, neon, paper), level design and HUD forks, bosses, gravity through the screen. The `look_1` and `stages` forks stay in the data but are not in Stage 1 (section 9).
- The RPG, the Overload stage, the fake crash, the endgame, Rework.
- Voice acting, music beyond today's sound.

---

## 1. Contracts

### 1.1 The campaign as data
- **`SessionDef`** (`campaign/sessions/<id>.tres`, script `campaign/session_def.gd`):
  - `id`, `stage` (1–5), `title` (debug and notes)
  - **The build:** `basics: Array[StringName]` (movement / shooting / dash / enemies / level; v5 4.8's three plus the gun and the dash, owner 2026-11-23), `enemies: Array[StringName]` (archetypes allowed; `&"fork:fork_enemy"` means the save's answer), `arena: ArenaDef`, `rules: WorldRules` overrides (null = base), `patches: Array[StringName]` (applied at the start, by the AI, as a rule edit with no warning)
  - **The goal:** `goal: GoalDef` (`kind`: `survive` seconds / `kills` count / `stop` (the AI ends it, as the S1 smoke test) / `boss` (Phase 6); `value`; `time_limit`)
  - **The AI's script:** `intro: Array[Line]`, `cues: Array[Cue]` (1.5), `debrief: Array[Line]` (lines with conditions, 1.3)
  - `fork: StringName` (asked in the debrief; `&""` = none), `ships: Array[StringName]` (changes shipped when the session is done; the version bumps)
  - `face: bool`: the mascot has a body (false before `fork_mascot` is answered; the session data says it, not the shell)
- **`Line`** (`campaign/line.gd`): `text`, `expression`, `if: StringName` (a condition id: `died`, `won`, `fast`, `slow`, `hit_none`, `hit_lots`, `mascot:cursor`… evaluated against the session result and the save), `per_mascot: Dictionary` (mascot id → text override, used rarely, for signature lines).
- **`Campaign`** (`campaign/campaign.tres`): an ordered `Array[SessionDef]`. `CampaignDB` (autoload, like `ChangeDB`) loads it and validates it in `problems()`: unique ids, stages non-decreasing, every `fork` exists and is asked once, every `ships` id exists, every cue's edit and event exist, every `Line.if` is a known condition, no session needs a basic that no earlier session shipped.
- **One campaign** in v8 (Stage 1). Branching on fork answers is done with `Line.if` and `&"fork:…"` values, never with separate session lists (content = sum).

### 1.2 The shell runs a session
1. **`Main._ready`** asks `Campaign.current()` for the save's session (`SaveGame.state().campaign.index`), then builds the genre with it: `genre.build(self)` reads `RunState.session` (new field, set by `reset`).
2. **`TopdownGenre`** reads the session: basics (replacing `Unlocks.missing_basics()` for the campaign), enemies, arena, rules, start patches. `RunLoop` gets the goal: `survive` ends the run `won` at `value` seconds; `kills` at `value` kills; `stop` keeps the M30.1 "AI gives up" behaviour at `value` seconds.
3. **Intro:** the mascot says the intro lines over the first seconds of play (it does not pause the game; S1–S3 are calm enough). A session can set `intro_pause = true` to hold play until the lines are read (S1 uses it).
4. **Death:** the session ends `died`. The debrief plays its `died` lines and then offers **Retry** (same session, new seed) or **Move on** (the session counts as done, its `ships` ship). Move on appears after the **first** death in Stage 1. The AI owns it: "That one's on me. Want another go, or should I just patch it?" Telemetry logs both. Bosses (Phase 6) will not offer Move on.
5. **Debrief:** `DebriefFlow` (replaces `DevSessionFlow` in campaign mode, 2) plays the debrief lines, then the fork if any (cards in the mascot's speech), then ships `ships` + the fork answer and shows the patch notes. Then **Next session** reloads the scene with the next index.
6. **Save:** `campaign: {index, done: [ids], attempts: {id: n}, events_seen: [ids], mascot: id}` and `settings: {reduce_flashing}` go into the save. **Schema 2.** A schema-1 save (v5/v6) is moved aside as `save.v1.json` and a new campaign starts; the start screen says so once ("Old prototype save kept aside"). Tested.
7. **The legacy loop** (runs + `DevSession.plan`) stays reachable with `--legacy-loop` for the existing tests and bots. Nothing in the campaign calls it. It is removed in Phase 8, when the endgame decides what it reuses.

### 1.3 The mascot
- **`Mascot`** (`ui/mascot/mascot.gd`, a `CanvasLayer` child of the shell): a widget in the **top-right corner**, 112 × 112 px plus a speech bubble that grows to the left and down (max 360 px wide, 3 lines). It never covers the centre 70% of the screen. It is drawn with `_draw()` from shapes, so the look path's shaders restyle it later.
- **Three bodies** (`ui/mascot/bodies/*.gd`, one class each, a shared `MascotBody` base with `set_expression()`, `say_start()`, `say_end()`, `point_at(screen_pos)`, `glitch(seconds)`):
  - **Cursor:** a mouse pointer with a small blinking caret for a mouth. Its tilt and bounce carry the expressions. `point_at` flies it across the screen to the target (used by the rule-edit warning, 1.4) and back.
  - **Window:** a small OS-style window (title bar `ai.exe`, `_ □ ×`) with two eyes and a mouth in its body. Expressions are eye shapes. Surprise maximises it for 0.3 s. `point_at` stretches a title-bar arrow.
  - **Blob:** a squishy round body with two eyes. Squash and stretch carry the expressions. `point_at` stretches a pseudopod.
- **Before the face** (`SessionDef.face = false`): no body. The corner shows a **blinking text caret** and the bubble shows broken text (glyphs, then fragments). The wordless lines are written that way in the data (section 3); the mascot just types them.
- **Expressions (8):** `idle`, `happy`, `proud`, `worried`, `surprised`, `guilty`, `thinking`, `panic`. Every body implements all 8.
- **Speech:** a typewriter at 45 chars/s, then the line stays for `1.2 s + 0.05 s × length`. One bubble at a time. A queue with priorities: a higher-priority line cuts a lower one short (after 0.4 s minimum), equal priority waits. Hold **Tab** to keep the bubble open (accessibility).
- **`fork_mascot`** (new fork, 1.6) chooses the body; `SaveGame.state().campaign.mascot` stores it. Before it is answered, the debug default is `cursor`.

### 1.4 The rule book
- **`RuleEdit`** (`rules/<id>/<id>.tres` + optional `<id>.gd`, extends `Mutation` so it reuses `apply_rules`, `on_entity_spawned`, `enable`, `disable`, `state()`):
  - `target`: `walls`, `enemies`, `player`, `world`, `game` (for the warning icon and the notes)
  - `warn_line` (the mascot's line before), `done_line` (after it expires, optional), `warn_seconds` (default 1.5), `duration` (seconds; 0 = until the session ends)
  - `point_at`: `player`, `nearest_enemy`, `walls`, `centre`: where the mascot points during the warning
  - `photosensitive: bool`
- **Edits live in `RunState.ai`, the parked M14 AI layer, with owner `&"edit"`.** A rule edit is AI-tier (`is_ai_tier()` returns true for it). `add_ai` / `remove_ai` / `expire_ai` already recompute the rules, call `on_entity_spawned` on live entities, log, and keep the reversibility invariant. Un-park only what this needs. Rollback charges, stage owners and the boss stay parked.
- **`RuleBook`** (`systems/rule_book.gd`, a shell node):
  - `request(edit_id, by := &"cue") -> bool`: refuses if the edit is live or conflicts. Otherwise: the mascot says `warn_line` and points, a **warning marker** shows (the target icon on a pulsing ring at the screen edge, plus a short rising sound), then after `warn_seconds` it calls `RunState.add_ai(edit, &"edit")`, and after `duration` it calls `remove_ai(edit, &"expired")` and says `done_line`.
  - `clear()`: removes every edit (session end, death, scene reload).
  - With `reduce_flashing` on, a `photosensitive` edit uses its gentle variant (the edit's script reads the setting).
- **New `WorldRules` fields** for v8's edits (each composes as v2's convention says: multiply `*_mult`, add counts, turn bools on, assign nothing over another layer's work):
  - `input_rotation_deg` (added; 180 = inverted), read by `HumanInput` and `BotInput`
  - `enemy_scale_mult`, `enemy_speed_mult`, `player_speed_mult`
  - `wall_bounce` (bool): the player and enemies bounce off walls with a short knockback; player shots get +2 bounces
- **v8's edits (6):**

  | id | target | What it does | Duration |
  |---|---|---|---|
  | `edit_bouncy_walls` | walls | `wall_bounce` on | 20 s |
  | `edit_big_enemies` | enemies | enemies ×1.8 size, ×0.7 speed, +1 HP | 20 s |
  | `edit_tiny_enemies` | enemies | enemies ×0.5 size, ×1.4 speed, 1 HP | 20 s |
  | `edit_inverted` | player | `input_rotation_deg` +180 | 10 s |
  | `edit_slowmo` | world | `time_scale` ×0.6 | 8 s |
  | `edit_gift_explode` | player | the `explode_on_hit` patch as an edit ("try this") | until the session ends |

- **Gravity edits** (`edit_gravity_left`, `_up`, `_down`) exist for the event (1.5). They set `gravity_enabled`, assign `gravity_dir` (the only assignment allowed, since only one gravity edit is live at a time: they conflict with each other) and give `jumps = 1`, so the player is never stuck. They reuse `gravity_on`'s Mover physics and the gravity-aware enemies.

### 1.5 Cues and scripted events
- **`Cue`** (`campaign/cue.gd`): `when` (`at_seconds` / `at_kills` / `at_goal_pct` / `on_signal`: `player_hit`, `wave_cleared`, `edit_ended`), `value`, `once` (default true), then **one** action: `say` (a `Line`), `edit` (a rule edit id), `event` (a scripted event id), `spawn` (archetype × count, at the spawner's points).
- **`ScriptedEvent`** (`events/<id>/<id>.gd` + `.tres`): `id`, `once_per_save`, `photosensitive`. Its script is a coroutine `play(ctx)` that may say lines, request edits (with or without warning), pause and resume the session timer, and shake or glitch the mascot. `EventPlayer` (a shell node) runs one at a time, records it in `campaign.events_seen`, and **skips** a `once_per_save` event that has already been seen (the cue then does nothing; the session must still work, tested).
- **v8's event, `wrong_variable`** (Stage 1, session S5):
  1. At 40 s: the mascot, `thinking`: "Enemies feel slow. One sec, I'll bump their speed."
  2. Warning as usual (1.5 s), pointing at the nearest enemy.
  3. Instead, `edit_gravity_left` lands **with no extra warning**. Everything slides left. The mascot turns `surprised`: "That's… not speed."
  4. 4 s later: `panic`, "Wrong one! Hold on—", and gravity swaps to **up** (`edit_gravity_up` replaces `_left`).
  5. 3 s later, to **down**: "Nope. Nope."
  6. 3 s later all gravity edits are cleared: "There. Speed was the *other* slider." Enemies get `enemy_speed_mult` ×1.15 for the rest of the session (what it meant to do).
  7. The debrief opens on the `guilty` expression: "So. About the gravity thing. Let's never speak of it."
  - The session timer **pauses** during steps 3–6, so the player still gets the full goal.
  - Tuned so a human can survive it: enemies under gravity fall too, and contact damage is off for the first 0.5 s after each flip (`RunState.start_grace`).

### 1.6 Forks in the campaign
- `Fork`, `Change` and the shelf (v6 1.1) are kept as they are. A session's `fork` is asked in its debrief: the question is the mascot's line, and the cards are the options (mockup stills for `fork_mascot`, card text for `fork_enemy`). Picking ships the answer (patch step) and shelves the rest. **No AI's-wish card and no Rework card in the campaign.**
- **`fork_mascot`** (new, `devsession/forks/fork_mascot.tres`): "I think I need a face. Which one is me?" Options `mascot_cursor`, `mascot_window`, `mascot_blob` (changes with a `MockupTake` each; the stills are captured from the bodies by `tools/mockup_capture.gd`). Shipping one sets `campaign.mascot`.
- **`fork_enemy`** is unchanged (Tank · Bomber · Lancer), asked in S4's debrief.
- `DevSession` is not used by the campaign. Its `answers()` and its shelf helpers are, through `Fork`.

### 1.7 Live reactions
- **`ReactionDef`** (`campaign/reactions/*.tres`): `id`, `trigger` (below), `lines: Array[Line]` (one picked by the run seed), `expression`, `priority` (1 = chatter, 2 = notable, 3 = important), `cooldown` (default 30 s), `once_per_session`, `min_session` (a session index, so the AI only says what it knows by then).
- **Triggers (v8):** `enemy_count_at_least n`, `player_hp_at_most n`, `player_hit`, `near_miss` (a shot passes within 12 px), `kill_streak n` (n kills in 3 s), `camping` (in one 3-tile area for 8 s), `not_shooting` (8 s), `no_hit_for` (30 s), `wave_cleared`, `first_kill`, `session_half`, `last_seconds` (5 s left).
- **`Reactions`** (shell node) checks triggers at 4 Hz from a context snapshot plus EventBus signals. **Global rule: at most one chatter line every 8 s, and nothing while a cue or an edit warning is speaking.** Priority 3 ignores the global gap.
- **v8 writes ~30 reactions** (section 3.3). Every mascot shares them; a few have `per_mascot` overrides for flavour.

### 1.8 Telemetry (schema 4)
- A **session record** replaces the run and dev-session records in campaign mode: `session`, `stage`, `attempt`, `outcome` (`won`, `died`, `stopped`), `duration`, `deaths`, `kills`, `hits_taken`, `reactions: [ids]`, `edits: [{id, at, by}]`, `events: [ids]`, `fork: {id, pick, shelved}` or null, `moved_on: bool`, `mascot`, `reduce_flashing`.
- The legacy loop keeps writing schema 3 records.

### 1.9 Settings
- `settings.reduce_flashing` (save, schema 2): asked once on the start screen before the first New game ("Reduce flashing and screen shake?" Yes / No, changeable later in a small Settings panel). It halves screen shake, removes white flashes (explosion flash, kill pop flash), and switches photosensitive edits and events to their gentle variants.

---

## 2. Screens
- **Start screen:** **New game** (a confirmation if a campaign exists), **Continue** (shows "Stage 1 · Session 4 · v0.3"), **Settings**, **Quit**. Debug builds also list sessions to jump to (F-key, writes nothing to the real save).
- **In a session:** the HUD keeps HP and adds the goal at the top centre ("Survive 0:45", "Kills 12/20"). The PATCH gauge and the prompt panel are gone in campaign mode. The mascot sits top-right.
- **The debrief** (`ui/debrief_screen.gd`): the game dims, and the mascot moves from the corner to the left third at 3× size. Its lines play one by one (click / Space / Enter advances; a line can't be skipped in its first 0.3 s). A fork's cards rise from its bubble (the v6 card widget; keys 1–3). Then the **patch notes**: "v0.3 — what changed" typed by the mascot, with the shipped items. Then **Next session** (or **Retry / Move on** after a death, 1.2.4).
- **F1** adds `session=s1_04 attempt=2 edits=edit_inverted(3.1s) events=-`. **F2** lists the rule edits (request one: it runs with its warning) and the events (play one, ignoring "once per save" in debug).

---

## 3. Content: Stage 1, "The prototype" (~20 min)

### 3.1 The sessions
Target times are for a human. Each is a `SessionDef` in `campaign/sessions/`.

| # | id | Version | Build | Goal | What happens | Debrief → ships |
|---|---|---|---|---|---|---|
| S0 | `s1_00_nothing` | v0.0 | nothing: no movement, no gun, no dash, no enemies, no level | `stop` at 5 s | Black, one square that can do nothing. The caret blinks. Wordless glyph lines. At 5 s the AI gives up. | Glyphs; ships **movement** |
| S1 | `s1_01_move` | v0.1 | movement; an empty box | `stop` at 3 s (5 s in all; no goal text) | You can move, and nothing else happens. The AI's first fragments ("m0ve … ok", "ok!"). | "alone. boring?"; ships **enemies** |
| S2 | `s1_02_enemies` | v0.2 | + chasers; no gun; **no health** until the AI adds it at 11 s (M39.2) | **`overrun`** (no goal text; called off at 45 s) | The AI drops the first chaser at 1 s, then more and more by cue every 3 s (1, 2, 3, 5, 8, 12, 18, 25, 30). The first ones reach you and **nothing happens** (they stop around you: no rim, no flash, no HP): "...?" (on a first touch before 5 s) / 6.5 s "no ouch. forgot ouch." / 9.3 s "one sec." At 11.1 s `add health`: the red rims light, "HP 5" appears, "there. ouch.", 13.2 s "run.", and the first bite after a 2.5 s grace (13.6 s). Then "more?" / "no. stop. STOP." and you go down at some point. Going down is the end: the debrief offers Next, not Retry. | "too many. my fault. sorry." "ouch works, at least." "you. things. no gun."; notes "Getting hurt (sorry)", "Shooting" |
| S3 | `s1_03_shooting` | v0.3 | + the gun, health; shots **pass through** enemies until the AI adds `hits` at 9.5 s (M39.2) | `kills` 15 (time limit 2 min) | First real fight. Two chasers at 0.5 s and no others (the spawner waits for `hits`); the shots go through them: "...through?" / "they don't feel it. one sec." At 9.5 s `add hits`, and the spawner starts. The first kill brings the first full sentence ("Oh. That works."): no reaction before it. Reactions on (min_session 3), caret only. | **`fork_mascot`**: the AI gets a face; ships **level** and **dash** |
| S4 | `s1_04_level` | v0.4 | + the level (arena_0's walls), the dash, shooter enemies | `survive` 30 s (owner, M39.1) | The mascot in its body for the first time ("Better. Right?"), and it says what is new: the walls and the dash. Live reactions. One rule edit at 12 s, right after the intro, for 10 s (not its usual 20: it must end, and say its done line, before the session does): `edit_bouncy_walls` ("Walls are boring. Let me try something."). | **`fork_enemy`** (Tank · Bomber · Lancer) |
| S5 | `s1_05_wrong` | v0.5 | + the forked enemy | `survive` 90 s (the timer pauses during the event) | The **`wrong_variable`** event at 40 s (1.5). | Apology; no ship (the version still bumps: "v0.5 — gravity fixed (mostly)") |
| S6 | `s1_06_playground` | v0.6 | everything so far | `kills` 40 (time limit 4 min) | The AI is confident now: `edit_gift_explode` at 10 s ("Try this."), then `edit_big_enemies` at 60 s, `edit_inverted` at 110 s ("Quick test, don't panic."), `edit_slowmo` when HP ≤ 2 (once). | Stage 1 ends: "Okay. It's a game. A small one. Next: what *kind* of shooter is it?" (Stage 2 is not in v8; the screen says "To be continued" and returns to the start screen) |

- **Total:** ≈ 0:20 + 0:30 + 1:00 + 1:30 + ~2:00 + ~3:00 of play, plus debriefs (~40 s each), about 12–15 min at first play, ~20 with deaths and reading. Tune toward 20.
- **Difficulty:** S1–S3 can't really be lost. S4–S6 use today's v0.0 tuning, with S6 a step up. Target human death rate (G13): S4 < 20%, S5 < 30%, S6 < 40% on the first try.

### 3.2 Lines (my draft; the owner edits for tone)
Short, warm, a bit clumsy, never developer jargon (owner: "maybe not that meta, people will not understand").
- **S1 intro (glyphs):** "▯" · "▯▯ ?" · "…" Stop at 5 s: "▯ ✕" (the M30.1 stop line becomes a glyph line). Debrief: "▯ → ⇄ ?" (it figures out movement), then patch notes "v0.1 — movement".
- **S2:** "m0ve" · "ok" · (on spawn) "?" Debrief: "thing. shoot thing?" → "v0.2 — enemies".
- **S3:** at 20 s "Oh. That works." · at 45 s "You're good at this." Debrief: "I can talk now. Weird." · "I think I need a face. Which one is me?" (`fork_mascot`) → "v0.3 — a level, and a face".
- **S4:** intro "Better. Right? I made walls too." · "And you can dash now. Shift or right click." · edit "Walls are boring. Let me try something." · done "Hm. Keep or not? Kidding, it's temporary." Debrief (`won`): "Good run. I want a new enemy. Pick one." (`fork_enemy`); (`died`): "Too many at once. My bad."
- **S5:** the event lines (1.5). Debrief: "So. About the gravity thing." · "Let's never speak of it." · (`hit_none`) "You didn't even get hit. Show-off."
- **S6:** "Try this." · "Bigger targets. You're welcome." · "Quick test, don't panic." · (slow-mo) "Breathe. I've got you." Debrief: "Okay. It's a game. A small one." · "Next: what *kind* of shooter is it?"
- **Signature lines (per mascot)** on S4's intro: Cursor "Look, I can point now." · Window "Finally, a window of my own." · Blob "I'm… squishy? I'm squishy."

### 3.3 Reactions (~30; a sample)
| Trigger | Line(s) | Priority |
|---|---|---|
| `first_kill` | "First one!" | 2 |
| `kill_streak 4` | "Okay, okay!" · "Combo!" | 1 |
| `player_hp_at_most 1` | "Careful—" · "That's your last one." | 3 |
| `player_hit` (after `no_hit_for 30`) | "Ouch. Streak's over." | 1 |
| `camping` | "That corner again?" · "I see you hiding." | 1 |
| `not_shooting` | "You can shoot, you know." | 1 |
| `enemy_count_at_least 12` | "That's… a lot. Is that a lot?" | 2 |
| `near_miss` | "Close!" | 1 |
| `last_seconds` | "Almost there." | 2 |
| `wave_cleared` | "Clean." | 1 |

The builder writes the rest in this voice, about 30 in all, each tagged with `min_session`.

---

## 4. Bot and debug
- **`bot_runs.gd --campaign`** plays the campaign on a scratch save from S1 to the end, picking forks by seed. `--invincible` and mortal modes as before. On death it picks Retry once, then Move on. It prints a line per session: `session=s1_05_wrong outcome=won t=96.2 edits=3 events=wrong_variable reactions=7`.
- **`--mute-ai`** (game and bot): no mascot lines, no reactions (cues that edit still fire, silently): the fun-before-meta check.
- **`--session=<id>`** starts a session directly on an in-memory save (inert).
- `check.ps1 -BotRuns` adds: one full invincible campaign chain on a scratch save (all 7 sessions; ~10 min of game time at 4× speed), and one mortal chain.

---

## 5. Tests (additions)
- **Campaign data:** `CampaignDB.problems()` is empty; a broken fixture campaign reports each problem kind.
- **Session goals:** each goal kind ends the session with the right outcome; `stop` matches the M30.1 timing.
- **Death flow:** Retry replays the same session with a new seed; Move on ships `ships` and counts the session done; attempts are counted.
- **Save schema 2:** fresh save; resume at the saved index; a schema-1 save is moved aside and a campaign starts; corrupt and newer files as v5.
- **Mascot:** each body implements all 8 expressions and `point_at`; the speech queue respects priority and the 0.4 s minimum; Tab holds the bubble.
- **Reactions:** each trigger fires on a scripted context; the 8 s global gap; nothing while a warning speaks; `min_session` respected.
- **Rule book:** each edit applies after `warn_seconds`, never before; expires after `duration`; `clear()` on session end and death; the **reversibility invariant** per edit (rules and entity components equal before and after, as `test_mutations` does for patches); the gravity edits conflict with each other; `input_rotation_deg` composes.
- **Events:** `wrong_variable` plays its steps in order, pauses the timer, leaves no edit live, and is skipped on a second play in the same save (and the session still completes).
- **Determinism:** the same seed plays the same session twice with identical per-10-frame hashes, edits and events included (as `test_stages`).
- **Reduce flashing:** no white flash node is created; shake amplitude halves.
- **Legacy:** the v6 suite still passes under `--legacy-loop`.

---

## 6. Milestones

| # | Milestone | Builder gate | Owner gate |
|---|---|---|---|
| M37 | Campaign spine | 1.1, 1.2, 1.8, 1.9, the start screen: `SessionDef`, `Campaign`, `CampaignDB`, goals, death flow, save schema 2, the legacy flag. S1–S3 as data (S3 without its fork yet; the caret mascot is a placeholder label). Bot `--campaign`, `--session`. **Numbers:** a 3-session invincible chain finishes; same seed → same save; the v6 suite green under `--legacy-loop` | — |
| M38 | The mascot and the debrief | 1.3, 1.6, section 2's debrief: the three bodies, 8 expressions, speech queue, the caret, the debrief screen with forks and notes, `fork_mascot` with captured stills. S3's fork. **Numbers:** screenshots of each body × each expression (24) in `.check/` for review | **G13a (short):** the owner looks at the 3 bodies' screenshots and the debrief. Charming enough? Any body to swap? |
| M39 | Live reactions | 1.7, section 3.3: triggers, the queue rules, ~30 reactions, `--mute-ai`. **Numbers:** in 16 mortal S4 bot sessions, 4–12 chatter lines per 90 s (median), never two within 8 s, priority 3 always heard | — |
| M40 | The rule book | 1.4: `RuleEdit` on the AI layer, `RuleBook`, the warning marker, the new `WorldRules` fields, the 6 edits + 3 gravity edits, F2. **Numbers:** reversibility for each edit; mortal time-to-death on S4 (its 30 s goal lifted, so the bot plays until it dies) with each edit forced at 12 s (after S4's intro), within ±20% of none (except `edit_inverted`, reported) | — |
| M41 | Events | 1.5: `Cue`, `ScriptedEvent`, `EventPlayer`, `wrong_variable`, once per save, reduce-flashing variants. **Numbers:** 16 mortal S5 bot sessions: the event plays fully in all; bot death rate during the event ≤ 25% | — |
| M42 | Stage 1 complete + playtest build | S4–S6 data, every line of section 3.2, the reactions' `min_session`s, tuning to the 3.1 targets, export, `PLAYTEST.md` rewritten for G13. **Numbers:** invincible bot chain S1–S6 ≈ 9–11 min of play; mortal bot death rates reported per session | **G13: owner playtest of Stage 1** on a fresh save (section 7) |

`tools/check.ps1` is green before every commit; each milestone gets a tag and a report, as before.

### 6.1 As built (M37)
- **Lines and cues are plain text in the session's `.tres`**, not sub-resources, so the owner can edit tone in one place:
  - a line is `"[condition] [expression]: text"` (`Line.parse`); an unknown word before the colon stays part of the text;
  - a cue is `"<at N | kills N | pct N | hit>: <say … | spawn <archetype> [n] | edit <id> | event <id>>"` (`Cue.parse`);
  - the condition field is `when` (`if` is a keyword); `per_mascot` became the condition `mascot:<id>`, so a signature line is three conditioned lines;
  - `CampaignDB.problems()` rejects `edit` and `event` cues until M40/M41.
- **`GoalDef` is inlined** in `SessionDef` (`goal`, `goal_value`, `time_limit`). `RunLoop.set_goal()` runs it on a **goal clock** (game time that events can hold with `hold_clock`, for M41).
- **The version comes from the session:** each session has `bump` (minor in Stage 1) and `notes` (the patch notes). The basics are session data, so no `basic_*` change ships in the campaign. `ships` is there for real changes (fork answers from M38).
- **Campaign mode is `RunState.session != null`.** The shell sets it from `CampaignDB.session_for_game()` only while `CampaignDB.active` (start screen, `--session=<id>`, bot `--campaign`). GUT, `main.tscn` booted directly and every v6 tool still run the v6 loop without any flag. The start screen's v6 form is behind `StartScreen.legacy_loop` (`--legacy-loop`). The bot and `run_hash.gd` set it unless `--campaign`.
- **Outcomes:** the run loop ends `win`, `lose` or the new `stopped` (a stop goal, or a kills goal's time limit). The debrief names them `won`, `died`, `stopped`.
- **S1 stops at 5 s and ends at 7 s** (the stop line is a cue, plus the 2 s read beat). Table 3.1's "stop at 20 s" was the v5 smoke test's length.
- **Speech is paced in real time** (1.2 s + 0.05 s a character), and cues run on physics frames. Telemetry and the bot count lines said *or queued*, because a bot plays faster than speech.
- **Move on is offered after every death** (Stage 1's rule). The debrief is plain text until M38: the lines, `"v0.2.0 · what changed"` with the notes, and the buttons (Enter or 1/2).
- **Reduce flashing** halves camera shake and drops the white screen flash. An enemy's own hit flash stays: it's readability, not a flash.
- **No gun and no dash at first (owner, 2026-11-23, after M37):** `Unlocks.CAMPAIGN_BASICS` adds `shooting` and `dash` to v5's three. The player gets `shooting_locked` and `dash_locked` (no shot, no auto-attack, no barrel drawn, no dash line on the HUD). Outside a session both are always on, because the v6 loop never ships them. The owner then set the order (M37.1): **S0 nothing, S1 movement, S2 enemies (dodge only), S3 shooting with a kill count instead of a timer**, then the plan as written (the level and the dash ship after S3). Sessions are numbered from S0 on screen. `SessionDef` gained `spawn_rate` and `spawn_cap` (a StageDef's preset) for S2's few chasers. Then (M37.2): **S1 lasts 5 s with no goal text** (a `stop` goal), and **S2 is an overrun**: a new goal (`SessionDef.OVERRUN`) where cue waves pile on until you go down. That death is the expected end (`DebriefScreen.death_expected()`: Next session, no Retry), and still standing at `goal_value` seconds is "stopped". The mortal bot goes down at 30-33 s (seeds 2, 3, 5). M37.3 (owner: "a bit shorter"): waves every 3 s, called off at 45 s; the mortal bot goes down at 18-23 s (seeds 2, 3, 5, 7, 11).
- **Not built:** the start screen's debug session list (use `--session=<id>`) and `intro_pause` (no Stage 1 session needs it yet).
- **Numbers:**
  - Invincible bot chain S1–S3 on a fresh save: S1 stopped at 7.0 s, S2 won at 30.0 s, S3 won at 60.0 s, v0.0.0 → v0.3.0, 3 campaign telemetry lines.
  - Two mortal chains with the same seed (5) on fresh saves wrote byte-identical save files.
  - A forced-death chain (`--set=player_max_hp=1 --set=chaser_hp=40.0`) played S3 twice: died → Retry, died → Move on → v0.3.0 → the title screen.
  - Suite: 21 new tests in `test_campaign.gd`. The v6 tests were updated only for schema 2 and the start screen flag.

**Why this order:** the spine first, because everything plugs into sessions. Then the mascot, because it's the main character and the owner should see it early (G13a). Reactions and edits come next: they're the AI being "the main force". The event is last, because it uses all three.

**Cut order if needed (first to last):** `edit_tiny_enemies` → `edit_slowmo`'s HP cue → per-mascot signature lines → the Settings panel (keep the first-launch question) → reactions down to 15. **Never cut:** the three mascots, the warning-before-edit rule, `wrong_variable`, the death flow, save schema 2, G13.

---

### 6.2 As built (M38)
- **The mascot** (`ui/mascot/mascot.gd`): top-right, **below the HUD's two lines** (y 64, so it never covers HP and the version), 112 px, a bubble growing left. Typewriter 45 chars/s, then held `SessionRunner.read_seconds()`; Tab holds it. Priority queue: a higher priority cuts in once the line on screen has been up 0.4 s (typed or not); equal and lower wait. The session's script speaks at priority 2. `silence()` hides it when the debrief opens.
- **Bodies** (`ui/mascot/mascot_body.gd` + `bodies/`): cursor, window, blob, and the **caret** as a fourth body for "before the face". Shared eyes, mouths and poses for the 8 expressions; each body draws its shape around them. `point_at` and `glitch` are in (M40 and M41 use them). A body takes `gentle` (reduce_flashing) from whoever holds it: it never reads the save, so the capture tools run without autoloads.
- **The debrief** is staged: the mascot at 3x in the left third (the caret before the face), lines typed one by one as bubbles (Space, Enter or a click; not in a line's first 0.3 s; a read line moves on by itself), then the fork's question as one more line and its cards (keys 1-3), then the notes (with the pick as a bullet) and the buttons. **Move on with a fork still to ask asks it first**; its Next then moves on. `finish_lines()` and `pick(i)` drive it for the bot and tests.
- **`fork_mascot`** (`devsession/forks/`, `campaign = true`: the v6 dev session never offers it) with `mascot_cursor`, `mascot_window` and `mascot_blob` (new change kind `mascot`; `Change.MASCOTS`). Cards show the **live bodies**, not captured stills (they animate and react to hover/focus); `mockup` stays false. Picking swaps the big body in at once (a short glitch) and it says the take's line ("Better. Right? …"). `CampaignDB.complete(s, pick)` ships the pick and sets `campaign.mascot`; the campaign telemetry line logs `fork: {id, pick, shelved}` and the mascot.
- **S3 asks it.** Its old last line "I think I need a face." is now the fork's question.
- **Captures:** `tools/mascot_capture.gd` (a sheet per body: 8 expressions, talking, point, glitch → `.check/mascot_<body>.png`) and `tools/campaign_shots.gd` (S3 with a body in the corner, then the debrief at the cards, after a pick, and the notes → `.check/shot_*.png`). Both need a window.
- **The bot** plays the debrief through (`--campaign` picks a card by seed and prints `pick=`); the check wants S3's pick and a mascot in the save.

### 6.3 As built (M39)
- **`ReactionDef`** (`campaign/reaction_def.gd`, one `.tres` per reaction in `campaign/reactions/`, loaded and checked by `CampaignDB`): `trigger` is plain text ("kill_streak 4", "enemy_seen shooter"); `lines` use the Line syntax, so **per-mascot flavour is a `mascot:<id>` line**, and a mascot with lines of its own says only those. No separate `expression` field: each line carries its own.
- **Triggers:** the plan's twelve plus `kills_at_least n`, `enemy_seen <archetype>`, `first_dash`, `quiet n` (nothing said for n s), and `streak_broken n` (the plan's "player_hit after no_hit_for 30"). Edge triggers fire once each time their condition starts to hold.
- **`Reactions`** (`campaign/reactions.gd`, a shell node in campaign mode) checks at 4 Hz **on game time** (the ticks fall on fixed game-time slots), picks lines by the run seed, and estimates "still being spoken" from the line's length (typing at 45 chars/s plus reading), so **the same seed reacts the same** (tested). The speaking rules: priority 3 always speaks; below 3 nothing while a line is being spoken (a cue, an intro line, another reaction): the moment has passed, so the reaction is **dropped, not queued**; priority 1 also waits 8 s after the last reaction. Script lines speak at `SessionRunner.PRIORITY` (2). `--mute-ai` silences both.
- **30 reactions**, `min_session` 3 to 5 (S3 is the first session where the AI can talk; the enemy-seen ones wait for the session that brings that enemy).
- **S4 (`s1_04_level`) is built now** (M42 was to add it): M39's numbers are measured on it. It has the level, the dash, chasers and shooters, the mascot's body, its signature intro lines, `survive` 90 s and `fork_enemy` in its debrief. Its rule edit comes with M40. S3's notes now also announce "Enemies that shoot back", and S3's way on is Next session.
- **Owner feedback (M39.1):** S4 is `survive` **30 s** ("30sec is perfect"), and its intro says what is new: "Better. Right? I made walls too." · "And you can dash now. Shift or right click." (the AI announces what it adds, in the session it adds it). The intro now keeps the AI busy ~11 s, so the PENDING window (new enemy, first dash) counts only time the AI is **free**: the shooter warning and the dash line both get their turn. On the 30 s S4 the bot hears the 3 intro lines plus 3-4 reactions (one line every ~5 s); the M39 numbers above were measured on the 90 s S4.
- **Telemetry:** the campaign line's `reactions` lists the ids said.
- **Review (5 reviewers, 3 skeptics per finding; 23 findings, 10 upheld, all fixed):** script lines now count as "being spoken" from the moment they are **queued** (`SessionRunner.line_queued`, on game time), not when the runner lets them out on the wall clock, so a reaction can no longer slip in front of a cue and a seed no longer depends on the machine; a shot that reaches the player without doing damage (i-frames, a dash, the grace, an invincible bot) is not a near miss; a new enemy or the first dash seen while the AI is busy is still said within 6 s (`PENDING`): S4's intro talked over most first shooters; the no-hit lines say "a clean stretch", since they also fire after a hit.
- **Numbers (16 mortal S4 sessions, seeds 1-16):** chatter per 90 s median **5.4** (4.0-7.0; target 4-12); shortest gap between two chatter lines **8.3 s** (never under 8); priority 3 heard **11/11**. All reactions together: 8-13 a session (about one every 9 s), with first_dash, streak_3 and the crowd ones the most common; the first shooter is announced in 14 of 16. 8 of 16 died. (Measured after the review fixes.)
- **The bot:** `--campaign --only=<session> <seeds>` plays one session per seed (each on an in-memory save, the mascot picked by the seed) and sums up the reactions. Its per-session campaign line adds `reactions=`; the check wants some in S4.

### 6.4 As built (M39.2): nothing by default
Owner, 2026-11-23: "game strength is to play with rules so current top right UI can be added later on. health shouldn't be here by default => exemple first wave of ennemies rush to player but nothing happens. stuff like this". Designed by a workflow (3 audits of what is on by default, 3 schedules from different angles, a judge); the owner picked: HP shows with health, mid-S2; S3's gun starts broken.
- **Two new campaign basics:** `health` (damage, death, the red contact rim, hit feedback, the HP readout: a hit is never invisible) and `hits` (the player's shots collide with enemies). Outside a session both are always on: the v6 loop is untouched.
- **The `add` cue:** "at 11: add health" adds a basic live (`RunState.add_basic`, `EventBus.basic_added`, logged `basic_added`). It lives in `RunState.session_added`, cleared by `reset()`, so a Retry plays the session without it again; the `SessionDef` is never changed. `TopdownGenre.apply_basics()` re-sets the player's locks; adding `health` starts a 1.5 s grace. Checks: an unknown basic, a basic the session already has, and a basic the next session does not list are problems.
- **The `touch:` cue time:** the first time something tries to hurt the player while it has no `health` (`EventBus.player_touched`, sent by `Health.take`, which returns before i-frames, telemetry and `player_hit`). "touch 5:" gives it a deadline: a first touch after 5 s says nothing (the AI has moved on).
- **Harmless chasers stop at reach** (no steering in, separation only): they ring the square instead of burying it, with no red rim.
- **The corner in a session** (`Hud.session_text`) shows only what was added: "HP n" with `health`, the dash state with the dash, the version stamp with a `version` basic (S5, M42); never Kills (the goal text counts). Empty in S0, S1 and S2 before 11 s.
- **Leftovers removed from sessions:** a "stopped" session (S0, S1) plays no jingle; Tab opens no v6 build log (it holds the AI's line).
- **S3's AI says nothing before its first kill** (no body yet, `face` false), but its reactions follow what happens (quiet ticks), so no stale one (a low-HP warning) goes off at the kill: "Oh. That works." stays its first full sentence.
- **The spawner waits for `hits`** in a session that has the gun (S3): nobody faces a crowd they cannot kill. S2 has no gun at all, so its overrun runs.
- **Review (4 reviewers, 3 skeptics per finding; 7 findings, 3 upheld, all fixed):** S2's lines were timed by cue but shown by the mascot more slowly (typing + reading), so HP appeared during "one sec." and the bites came before "run.": the cues are re-spaced to what the mascot really shows and the grace after `add health` is 2.5 s (`Tuning.health_added_grace`); a late first touch said "...?" after the explanation: the touch cue's deadline; S3's first kill could start with a stale low-HP warning: the quiet ticks (and fewer chasers bite before the gun works).
- **Numbers (12 mortal bot sessions each, seeds 1-12):** S2 still always ends in death, at 17-28 s (median 23.7 s; it was 18-23 s with health from the start); S3 is won in 30-34 s (the gun broken for its first 9.5 s, and no spawner until then; it was 22-25 s).
- **Left for later (Stage 2 candidates):** death as its own gag ("HP 0 and nothing happens"), no i-frames or knockback, enemies that never die, a one-way gun, S1 gags (S1 stays 5 s), Kills back as a score, the Tab log back as the AI's notebook.

### 6.5 As built (M40): the rule book
- **`RuleEdit`** (`core/rule_edit.gd`) extends `Mutation` as planned and is always AI-tier. **`RuleDB`** (`core/rule_db.gd`) loads `rules/<id>/<id>.tres` and checks each edit: the id starts with `edit_` and is not a patch id, target and point_at are known, warn and duration are ≥ 0, no `requires`, conflicts are known edits, and the lines parse. `CampaignDB.problems()` includes these checks.
- **`RuleBook`** (`systems/rule_book.gd`, a campaign shell node) counts **its own physics ticks**: a warning or duration is the seconds the player lives through (slow motion does not stretch them), and the same seed lands the same edits on the same frames (tested). It ticks before the session runner, so an edit asked for mid-frame still gets its whole warning (90 frames at 1.5 s, tested).
  - `request(id, by, seconds = -1, warn = true)` refuses when the game is over, the id is unknown, the edit is pending or live, or it conflicts with one that is.
  - The warning: the warn line at **priority 3** (straight to the mascot, noted by Reactions), the mascot points (`Mascot.point_at_screen`), the **`EditMarker`** (the target's icon on a pulsing ring at the screen edge, towards the point, never over the HUD or the mascot; a slow pulse with reduce_flashing), and the `edit_warn` sound (appended last, so the other sounds keep their bytes).
  - It lands with `add_ai(e, &"edit")`. It expires with `remove_ai(…, &"expired")`, and the done line queues behind the script.
  - `remove()` (F2, M41) says no line. `clear()` runs on `run_ended`: everything back (`expire_ai(&"edit", &"cleared")`), pending edits never land, no lines. A gravity change starts `Tuning.edit_gravity_grace` (0.5 s).
  - `--mute-ai` mutes the lines; the marker and the edits stay.
- **New `WorldRules` fields**, each an exact no-op at its default (the v6 run hashes match M39's, both stage sets):
  - `input_rotation_deg`: the movement turns, aim does not;
  - `player_speed_mult`, `enemy_speed_mult`;
  - `enemy_scale_mult`: live collision and visual scale through `EnemyCommon.follow_scale`; `body_half()` replaces `half_width` in reach and steering;
  - `enemy_hp_add`, `enemy_hp_one`;
  - `wall_bounce`: `Mover._slide` sends a body back off a wall, only the speed *into* the wall comes back (×0.6) plus a 240 px/s kick, along-wall speed (a jump, a fall) is kept, never off a floor or ceiling of a falling body, one bounce per 0.3 s.
- **The 9 edits** follow the 1.4 table. The gift is its own listener copy of explode_on_hit's take (no patch id named). The gravity edits are the one rule allowed to assign `gravity_dir`, and they also give one jump. Lines not in 3.2 are mine: tiny "What if they were tiny?", done lines "Back to normal size." · "Okay. Normal size again." · "Fixed. Sorry about that." · "Okay, full speed.".
- **The `edit` cue** takes an optional duration: "at 12: edit edit_bouncy_walls 10". **S4** has it (lands at 13.5 s, gone at 23.5 s, done line before the end). The runner copies its cues (`drop_cues`, `inject` for the bot and tests). Telemetry's `edits` lists `{id, at, by}`.
- **F1** lists the live edits with their seconds left. **F2** has a RULE EDITS section on top (request with the warning / cancel / take back), and the console scrolls.
- **The bot:** `--only=<session> --edits=none,<id>[:<s>],… --lift=<s> --edit-at=<s>` plays each condition and prints a table against none. The campaign line adds `edits=`. The check wants S4's edit to land, plus a forced smoke run of the 6 edits (each lands at 13.5 s).
- **Review (5 reviewers, 3 skeptics per finding; 15 findings, 11 upheld = 8 distinct, all fixed):**
  - a cue-asked edit landed one frame early (the tick order);
  - cancelling one pending edit hid the marker of another still warning;
  - the bounce scaled along-wall speed (a jump against a wall lost 40%);
  - floating shooters skipped the wrong walls under a gravity edit;
  - the marker could sit on the mascot's corner;
  - a bad `--edits` condition left a live game behind;
  - two tests were vacuous (aim, speed).
- **Numbers (16 mortal bot sessions per condition, seeds 1-16, S4 lifted to 180 s, the edit forced at 12 s and landing at 13.5 s):**

  | Edit | Median time to death | Against none | Paired per-seed | Gate |
  |---|---|---|---|---|
  | none | 91.3 s | — | — | — |
  | `edit_bouncy_walls` (after the bounce fix) | 78.6 s | 0.86 | 0.90 | pass |
  | `edit_big_enemies` | 84.2 s | 0.92 | 0.91 | pass |
  | `edit_tiny_enemies` | 97.2 s | 1.06 | 1.07 | pass |
  | `edit_slowmo` | 82.3 s | 0.90 | 0.87 | pass |
  | `edit_gift_explode` for 20 s | 81.3 s | 0.89 | 0.93 | pass |
  | `edit_gift_explode` until the end (as designed) | 141.1 s | 1.55 | 1.50 | reported: a gift, 5 of 16 lived to 180 s |
  | `edit_inverted` | 83.2 s | 0.91 | 0.82 | reported (shortest: 21.2 s) |

  - No seed died before its edit landed.
  - The whole-session gift is the one edit that changes the odds a lot. It is meant to: "Try this.". On the real 30 s S4 it would last 18 s at most.
  - Reversibility: each of the 9 edits added and removed leaves the rules, every enemy's scale, half, speed and HP, the time scale and the player's speed exactly as before, including an enemy born under the edit (tested).

### 6.6 As built (M41): events
- **`ScriptedEvent`** (`core/scripted_event.gd`; `events/<id>/<id>.tres` + `.gd`):
  - fields: `once_per_save`, `photosensitive`, `steps`, and **its lines as data** (by key, in Line syntax), so the owner edits tone in the `.tres`;
  - its script is a coroutine `play(ctx)` over an **`EventContext`** (`systems/event_context.gd`), which can say a line, set a face, pose a warning, request / swap / remove edits, apply an event-owned mutation, hold the session clock, glitch the mascot, mark a step, and wait;
  - **`EventDB`** (`core/event_db.gd`) loads and checks them, `CampaignDB.problems()` includes them, and an `event` cue must name a known event.
- **`EventPlayer`** (`systems/event_player.gd`) is a campaign shell node at physics priority -7: after the rule book, before the session runner.
  - It runs one event at a time, on **its own physics ticks**, so the same seed plays the same event on the same frames (tested).
  - It speaks at priority 3 straight to the mascot, and can cut its own line.
  - It holds Reactions below priority 3 for the whole event. Priority 3 still speaks, and an enemy first seen during the event is never announced.
  - It marks a once_per_save event **seen when it starts**: on disk with the debrief's Retry / Move on, so quitting mid-S5 replays it. After that it skips the event: the cue does nothing and the session plays on (tested).
  - A death or the session's end aborts the event: the clock and the reactions are released, the rule book's `clear()` takes the edits back, the player takes back its own mutation, and the script returns at its next wait. Freeing the scene mid-event is safe (tested).
- **The rule book** gained two moves:
  - it can **pose** a warning (`request(…, posing_as)`): the speed warning shows, then gravity lands;
  - it can **swap** an edit in one frame (`swap()`), so no frame passes without gravity between left and up, and each swap starts one grace.
- **New edit `edit_enemy_speed`** (×1.15; it stacks with big/tiny enemies) serves twice: as the warning the event poses, and as the speed the event finally gives. The event applies that speed **itself** (owner `event`, not through the rule book). So S5 shows `edits=3`, and no rule-book edit is live after the event.
- **`wrong_variable`** plays as 1.5 describes, at warning +1.5 s, left +4 s, up +3 s, down +3 s, then the clear. Differences from 1.5:
  - the face turns `surprised` the frame left lands, but "That's… not speed." comes 0.8 s later, cutting line 1 (so line 1 is read first);
  - step 6's `proud` is new;
  - the event shakes no camera; it glitches the mascot (and the screen, once, at the first flip);
  - **known deviation:** shooters float, so they don't fall under gravity (1.5 says enemies fall too). Walkers fall, including the forked enemies.
  - The clock is held 10.0 s, from the first flip to the clear. A won S5 lasts 100 s. The goal label dims while the clock is held.
- **Reduce flashing:** no screen glitch and no glitch sound, the mascot only wobbles, and the marker pulses slowly. Camera shake is halved as before.
- **S5 (`s1_05_wrong`)** is built now (M42 was to add it):
  - the forked enemy, survive 90 s, the event at 40 s;
  - its debrief opens on `guilty` ("So. About the gravity thing." · "Let's never speak of it.") **only when the event played this attempt**, through the new Line condition `event:<id>`. A Retry skips the event, so its debrief never mentions gravity;
  - "Gravity fixed (mostly)", v0.5.0, then "To be continued" until S6;
  - its title and intro are mine: "The wrong slider"; "New enemy's in. The one you picked." · "Ninety seconds this time. I'll keep tuning things as we go.".
- **The arena** lights the face you stand on under sideways gravity. Before, it drew left gravity as down.
- **F1** shows PLAN 2's `session= attempt= edits= events=` line and the event's step. **F2** has an EVENTS section, which plays an event now, ignoring once per save, without marking it seen.
- **Telemetry:** the campaign line's `events` lists the events played.
- **The bot:**
  - `--only` answers the session's forks by seed (`enemy=`);
  - each seed prints `event=<id>@start-end steps=n/6 hits_in_event=n (unblocked, by kind)`, followed by an `events:` summary;
  - `--events=none` is the control;
  - the campaign line adds `events=`;
  - the check wants S5's event in the invincible chain (`edits=3 events=wrong_variable`) and a forced `--only=s1_05_wrong 3i` playing 40.0–51.5 s with all 6 steps.
- **`--session=<id>`** answers that session's unanswered forks with option 0 (in memory), so `--session=s1_05_wrong` on a fresh save still has its forked enemy.
- **Review (5 reviewers, 3 skeptics per finding; 14 findings, 9 upheld = 6 distinct, all fixed):**
  - `EventDB` checked `play()` in the script's source, which an exported build does not ship, so the export would have logged a false error at every boot. It now checks the method list.
  - `--session=` did not answer S5's fork.
  - Four tests could not fail: F2 marking nothing, freeing mid-event, S5's own problems, and the `surprised` face. Each one now fails without the code it covers (checked for the free).
- **Numbers (16 bot sessions per condition, seeds 1-16, S5 as shipped):**
  - **mortal (the gate):** all 16 reached the event and all 16 **played it fully**, read as "completed it, or died during it, with no hang or skip". 15 completed it. **1 of 16 died during it (6%; gate ≤ 25%)**: seed 9, at step 4, under up gravity, 4 contact hits. Hits taken during the event, over all seeds: 22, of which 18 contact and 4 projectile.
  - **invincible:** 16/16 completed, all won at 100.0 s.
  - **control, no event (`--events=none`):** 0 deaths in the same 40–52.5 s window.
  - **But the session gets harder:** 6/16 won with the event, against 10/16 without. Deaths come after the event (59–97 s), from the extra 10 s and the ×1.15 enemies, plus the HP lost to contacts in the flips. This is tuning for M42 (table 3.1's targets). The levers, if S5 should be gentler: pause spawns while the clock is held, a longer flip grace, or a shorter left flip.
  - The legacy run hashes match M40's (both stage sets).

### 6.7 As built (M42): Stage 1 complete, the G13 build
- **S6 (`s1_06_playground`, "Playground"):**
  - The goal is 60 kills, with a 4 min limit. Spawns are ×1.3.
  - Explosive shots arrive at 10 s, big enemies at 20 kills and inverted controls at 40 kills. These cues are by kills, not 60/110 s, so they land for any player.
  - Slow-mo comes once, when HP is ≤ 2. It uses the new `hp N:` cue time, and it waits while the rule book is busy (another warning, or a timed edit live).
  - The debrief: on a death, 1.2.4's line "That one's on me. Want another go, or should I just patch it?". Once the session is over for good: "Okay. It's a game. A small one." · "Next: what kind of shooter is it?".
  - Notes "A small game, start to finish", v0.7.0, then "To be continued" and the title.
  - Builder departures from 3.1/3.2, asked at G13 7j: 60 kills (not 40), and edits by kills.
- **The `ended` line condition:** won, stopped, or moved on after a death. Move on on a session with `ended` lines plays them first, then the notes and the way on. So a death + Move on on S6 still ends Stage 1.
- **The `version` basic:**
  - S5 adds the stamp live at 15 s: "See the number up there? That's my version.";
  - S6 has it from the start;
  - the campaign stamp is the version only, with no "build N".
- **S5 changes:**
  - the picked enemy spawns at 6 s, by cue (`spawn fork:<id>`);
  - spawns pause while the event holds the clock;
  - the flip grace is 1.5 s (was 0.5);
  - spawn_rate is 0.8;
  - the clear gives 1 HP back (the "sorry heal").
- **Reactions:**
  - New `max_session`: first_dash and shooter_seen stop after S4, and the picked enemy's line after S5.
  - kills_50 waits for S6.
  - streak_after_hit is renamed streak_4.
  - hp_two stays live in S6.
  - S4's hit_none line no longer repeats S5's.
- **Bot numbers (mortal bot; bands are 3.1's first-try targets):**

  | Session | Before | Shipped, seeds 1-16 | Pooled, 112 seeds | Band |
  |---|---|---|---|---|
  | S4 | – | 0/16 | – | ≤ 3/16 |
  | S5 | 10/16 | 2/16 | 21.4% | ≤ 4/16 |
  | S6 | – | 2/16 | 23.2% | ≤ 6/16, above S5 |

  - The order S4 < S5 < S6 holds pooled, thinly. On 16-seed sets S5 and S6 tie (seeds 1-16 and 17-32: 2/16 each).
  - S5 levers, each added on top of the last (deaths/16): base 10 → spawn pause 8 → 1.5 s grace 7 → spawn 0.8 6 → sorry heal 4 → enemy at 6 s 2. Died during the event: 1/16.
  - **Note:** S5 is now harder *without* the event (8/16, 47% pooled) than with it, because the pause and the heal make the event a breather.
  - S6 spawn 1.3 is the only setting in band. At 1.2 S6 was no harder than S5; at 1.35 it reached 40%.
  - Slow-mo lands in 9/16 mortal runs and costs +3.2 s of real time. Before the busy hold it collided with another edit in 7/16 runs.
  - After the review, an edit cue also waits while another edit's warning is pending: two priority-3 warnings would queue on the mascot, and the second edit would land before its line was read. An edit can still land while slow-mo is live, after its own warning. S6's numbers above are measured with this hold.
- **Pacing: the 9-11 min gate is not met.**
  - The invincible chain S0-S6 plays a median 295.9 s ≈ 4.9 min (range 292.6-297.3; 8 chains). The cause is the owner's cuts (S0/S1 5 s, S2 45 s, S4 30 s).
  - For context, the bot's reading estimate adds ≈ 150 s. Mortal chains (16): median total with retries ≈ 428 s, so about 7 min for a human.
  - Mortal first-try deaths per session: S5 1/16, S6 5/16, S2 16/16 by design, the rest 0.
  - 3.1's "tune toward 20" was not pursued (owner: early steps must be quick).
  - G13 decides (Q1, 7e) whether S6 should grow.
- **The bot:**
  - `--session-set=` for session fields;
  - a `deaths:` summary per `--only`, with hit kinds;
  - per-seed `landed=`;
  - the chain prints `chain:` totals, plus `enemy=` and `landed=`.
  - The check wants:
    - S5 to offer Next;
    - S6 to end Stage 1 at v0.6.0→v0.7.0 with 3 edits;
    - a `chain:` line;
    - the HP cue to land slow-mo after a hit (seed 15 at 3 max HP).
- **Export:**
  - **Fixed a shipping bug:** Godot's export converted text resources to binary, and that emptied every PackedStringArray. The build would have had no AI lines, cues, intros, debriefs or notes; the M36 build was probably hit too. `project.godot` now sets `editor/export/convert_text_resources_to_binary=false`.
  - The boot check now reads the session and requires "7 sessions … 30 reactions", plus a second boot into S5.
  - PatchNotes.exe is 104.7 MB.
- **PLAYTEST.md is the G13 sheet.** Facts it relies on:
  - `real_duration` excludes the debrief; the telemetry timestamp is written at the debrief button.
  - `--session=` jumps write telemetry, so send the files before Part B.
  - Part B needs `--autostart --session=…`: without `--autostart`, Continue / New game would write the real save.
  - A jumped session's stamp reads v0.0.1, because `answer_forks` ships the enemy as a patch.
- **Review (5 reviewers, 3 skeptics per finding; 3 upheld, all fixed):**
  - an edit cue could land before its warning was read (the hold above);
  - PLAYTEST's mute-AI replay lacked `--autostart` and would have reset the real save;
  - the S5 version-line test could not fail. It now checks that the intro and then the version line are queued by 20 s. Whether the mascot shows the line by then cannot be tested headless, because the runner paces lines by wall-clock reading time.
- **Fixes:** 6.6 said S5 shows v0.5.0; its notes read v0.6.0, the version after the session.

### 6.8 As built (M42.1): G13 feedback
The owner played Stage 1 to v0.7.0: "interactions were fun, gravity changes were good". They asked for two changes: the dash becomes a pick, and a killed bomber explodes, with a bigger blast.
- **The dash pick (`fork_dash`):**
  - Asked in S3's debrief, right after the face (new `SessionDef.more_forks`): "I think a dash would feel good. What do you want?".
  - The three cards are Classic dash / Grappling hook / Teleport. The pick ships with S3's own version bump, and it is exclusive and permanent.
  - **Grappling hook:** a box cast up to 7 tiles in the move direction, in a cone (0 / ±12 / ±24°).
    - It catches walls only.
    - `Mover.pull_to` pulls the player at 1400 px/s and stops 2 px short, at rest; slow-mo doesn't change that.
    - Cooldown 1.1 s. A miss costs 0.4 s and is visible and audible.
    - Under gravity it latches for 0.3 s on side walls only, and gives no air jumps back.
  - **Teleport:** 4 tiles in the move direction, through walls, to the nearest free spot.
    - It stays inside the border and never lands in a sealed pocket (a flood fill from the start).
    - 0.25 s of i-frames, cooldown 1.3 s. A fizzle (no free spot) costs nothing.
  - **Where the pick shows:** S4's intro says how to use the pick (new `dash:<style>` line condition), and so do first_dash's lines. The HUD reads "dash / hook / teleport ready".
  - **Old saves** already past S3 stay on the classic dash.
  - Telemetry adds `forks` and `dash`.
- **The bomber (campaign only; the v6 hashes are unchanged):**
  - A killed bomber blinks for 0.3 s, then explodes.
  - Both blasts reach 2.0 tiles (was 1.6).
  - Victims of a blast the player set off count as the player's kills.
  - Chains need an already-hurt bomber.
  - No blast hurts the player once the session is won.
  - bomber_seen says so: "Bomber! Stay back, it blows up even if you shoot it.".
- **Bot:**
  - `--dash=<classic|grapple|teleport|none>`;
  - the second pick is decorrelated from the first;
  - `pick=mascot_x,dash_y`;
  - per seed `dash= uses= misses= fizzles= air=`;
  - `by_dash=` in `deaths:`.
  - The check forces S4 with the grapple and with the teleport. Its invincible chain plays the grapple and its mortal chain the teleport.
  - The export boots S4 with the teleport.
- **Numbers (mortal bot; it dashes blindly every 2.5 s, so this is a sanity check, not balance):**

  | | classic | grapple | teleport | band |
  |---|---|---|---|---|
  | S4 deaths (16) | 0 | 0 | 0 | ≤ 3 |
  | S5 deaths (32) | 6 | 6 | 4 | ≤ 8 |
  | S6 deaths (32) | 5 | **13** | 12 | ≤ 12 |
  | S4 lifted, time to death vs classic | 1 | 1.08 (paired 1.32) | 1.07 | ±20% |

  - Classic is within 5% of no dash at all, so the bot can't value a dash.
  - **The grapple misses the S6 band** (7/16 on seeds 1-16). The blind hook carries the bot to walls, where shooters hit it: 88 projectile hits against 69 for classic. No lever in the map (range 6-10 T, cooldowns) moves it outside noise, so the numbers stay; the owner judges the feel at G13.1.
  - Grapple misses are 39-46% of presses, and teleport fizzles 23-31%: the bot backs into the border.
  - The bomber change adds 3-4 explosion hits per 32 runs. S5 classic goes from 4/32 to 6/32 deaths and S6 from 4/32 to 5/32, both in band. S6 is still not harder than S5 for classic, as at M42.
  - The invincible chain with the classic dash plays 295.75 s (M42: 295.9). Reading grows by about 14 s: the second question, its take line and the per-style lines.
- **Review (5 reviewers, 3 skeptics per finding; 2 upheld, both fixed, each test checked to fail without its fix):**
  - a gravity change mid-pull cut the pull but kept its 1400 px/s, flinging the player about 3 tiles past the hook. A cut pull now stops at rest;
  - a Space tap meant for the dash question could press the focused Classic card. Cards now take player input only after the buttons' 0.4 s delay.
- PatchNotes.exe is 104.8 MB. PLAYTEST.md is the G13.1 sheet. It re-asks where the dash is asked, the bomber's blink, and the open G13 items.

## 7. What v8 must answer (G13)
1. Is Stage 1 fun and quick (~20 min), with something new every session?
2. Is the mascot charming, not annoying? Too chatty, too quiet? Which body did you pick, and why?
3. Does the gravity mistake read as a funny accident, not a bug?
4. Do the rule edits feel like the AI being the main force, and does the warning make them fair?
5. Does the wordless start → first words → a face land as a small story?
6. Do you want to know what Stage 2 brings?

---

## 8. What happens to v6 pieces
| Piece | In v8 |
|---|---|
| `DevSession` shapes (BASIC, FORK, IMPLEMENT, REWORK), `DevSessionFlow`, the dev-session screen | legacy loop only (`--legacy-loop`); the campaign uses `DebriefFlow` |
| `Fork`, `Change`, `ForkDB`, the shelf | kept, used by the debrief |
| `AiDirector` prompts, the PATCH gauge, `PromptPanel` | off in the campaign; kept for the shooter paths (Phase 6) and the legacy loop |
| `RunState.ai` (M14's AI layer) | **un-parked** as the home of rule edits; rollback charges and boss owners stay parked |
| Basics and smoke tests (M29b, M30.1) | become S1–S3's session data |
| `look_1`, `stages` forks and the 3 stage takes | kept in data, not asked in Stage 1 (section 9) |
| Rework | parked until the endgame (ROADMAP v3 1.6) |

---

## 9. Still open (each with a proposed default)
- **The look is asked at the start of Stage 2, not at the end of Stage 1** (ROADMAP v3 section 2 says "end of stage"). Reason: the three new looks are built in Phase 6, and asking for a look we can't show yet would be a fake choice. Alternative: ask it at the end of S6 using today's three look takes as placeholders.
- **Mascot names:** placeholders `Cursor`, `Window`, `Blob` in the cards. Alternative: the AI names itself after the pick, or the player names it.
- **Move on after the first death** in Stage 1. Alternative: after the second.
- **The mascot sits top-right.** Alternative: top-left (the HUD's HP would move right).
- **Reaction rate:** 8 s global gap, 30 s per reaction. G13 decides.
- **Old saves are moved aside**, not converted. Alternative: convert a v6 save's answers (enemy) into a campaign at S5.
- **The legacy loop stays until Phase 8.** Alternative: remove it now with its tests (faster code, but loses ~1,400 lines of test coverage that Phase 6's shooter paths may want).
- **Lines are English only.** French later, if wanted.

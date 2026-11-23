# Patch Notes - PLAN v9: Stage 2, the shooter grows

**For:** the builder agent
**Goal of this build:** Stage 1 ends on "Next: what kind of shooter is it?". v9 answers it. The player plays **Stage 2, "The shooter" (6 sessions + a boss, ~30–40 min with reading)**. The AI builds three versions of the shooter in front of you and you keep one (**Arsenal**, **Auto** or **Survival**). Then it tries paint on you and you pick the look (**Pixel**, **Neon** or **Paper**). It builds levels, makes three new enemies (all three stay), rebuilds the screen, tries to give the game depth and pulls everything **through the screen** at you, builds a boss that does nothing, and finally builds a **boss that must be beaten** (a checkpoint with unlimited retries and AI help). Every session brings something new, and the AI stays the main force: it swaps, paints, edits and apologises, live.
**Engine:** Godot **4.7.x stable**, GDScript, 2D, unchanged.
**Roadmap:** `ROADMAP.md` **v3**, Phase 6 ("Stage 2: the shooter grows").
**Supersedes:** nothing is dropped. **PLAN v8** (Phase 5) stays in force unless this document changes it. Section 0 lists what changes. PLAN v8 is `PLAN.md` today; M43's step 0 archives it as `PLAN.v8.md` (marked "Phase 5, done") and installs this plan as `PLAN.md`, as ROADMAP v3 did with v7. "PLAN.v8.md" below means that archived file.

Milestones continue from **M43**. Owner gates continue from **G14**.

---

## 0. Read this first

### 0.0 Where we are (built)
- **Stage 1 is built and playtested:** M37–M42.2, tags up to `m42.2`. The campaign runs S0–S6 (v0.0 to v0.7.0) from a black screen to a small shooter. It has the mascot (3 bodies, a pick), the staged debrief, ~30 live reactions, the rule book (10 edits), the `wrong_variable` event, the dash pick (classic / grapple / teleport) and the dash-aim question. It ends on "To be continued".
- **The As-built record is in `PLAN.v8.md`**, sections 6.1–6.9 (M37 to M42.2): the real field names, cue syntax, line conditions, the rule book's owner layers, the slow-mo busy hold, the bot numbers and the reviews. v9 is written against that record, not against v8's original contracts. When this plan and v8 6.x disagree on how something works **today**, v8 6.x is right and this plan's change is the delta.
- **Last numbers (M42.2):** GUT 598/598. Both v6 hash compares 0 failures. Invincible chain (grapple+aim) `play=290.0`. The mortal chain (teleport+aim) won all 7 sessions on the first try. These are the "Stage 1 unchanged" references for M43–M48. They are too weak alone (the chain's `play=290.0` is mostly time goals, so a changed gun keeps it), so **before M43 a campaign hash is recorded at the `m42.2` tag**: `run_hash.gd --campaign --session=<id>` for s1_03–s1_06, per second (entity kinds, positions, kills), plus the tier-0 screenshot reference (5 frames, windowed, same machine). "The same lines" means the botrun lines with `real=` and `read≈` stripped.
- **G13 (owner, 2026-11-23):** "interactions were fun, gravity changes were good". The dash became a pick (M42.1), the bomber explodes on death with a bigger radius, and dash aim was added (M42.2). PLAYTEST 7a–7j were **not answered**, so their defaults stand (g13-open-questions). v9 re-asks them briefly at G14a.

### 0.1 Stage 2 in one paragraph
The prototype is a small game now (v0.7.0). The AI wants a real shooter but doesn't know which kind. So it builds **three quick versions inside one session** and lets you play each for ~45 s. You keep one. The other two go to the shelf ("I'll keep the other two in a drawer"), where Phase 8's final boss will find them (ROADMAP 2). From then on the game grows **inside your path**: a new gun every session (as a card, a level-up pick or a gun on the ground), the look you pick, levels in the shape you pick, the enemy you keep, the screen in the style you pick. The AI makes two "mistakes": it tries to add depth and everything falls toward your face, and it builds a boss that does nothing. Then the boss gets a personality (your pick), and you beat it to finish the stage. **Power stays in the session** (ROADMAP 1.9.7): each session starts you at the pistol again. The campaign adds guns, enemies and rules to the game, not stats to you.

### 0.2 The stage, as you'll play it
Human times, first play. S-numbers continue Stage 1's (S0–S6). "New" follows ROADMAP 1.9.2: something new every session.

| # | Session | Play | With debrief, deaths | New this session | The AI does (main force) | You pick |
|---|---|---|---|---|---|---|
| — | Stage card "Stage 2 · The shooter" | — | 0:05 | the stage card | — | — |
| S7 | **Three games** (`s2_01_tryout`) | 2:30 | ~3:30 | three versions of the shooter, ~45 s each | swaps the whole game twice, live | **the shooter path** |
| S8 | **Day one** (`s2_02_day_one`) | 2:00 | ~3:00 | your path for real; S7's taste of its growth piece **rebuilt properly** (the real meter, rank pips, crates); the shotgun; the splitter | rebuilds the growth piece; **tries the three looks on you, 5 s each** | **the look** |
| S9 | **Fresh paint** (`s2_03_paint`) | 3:00 | ~4:00 | the look lands (mascot too); the laser | repaints the game; one path-flavoured edit goes wrong; removes the walls | **the level layout** |
| S10 | **Level one** (`s2_04_levels`) | 4:00 | ~5:00 | levels (3 parts in your layout); the launcher; **three new enemies, one per part** | builds each part as you reach it; heats the edges | — (notes only; all three enemies stay) |
| S11 | **Depth** (`s2_05_depth`) | 3:30 | ~4:30 | the three new enemies mixed; the orbit shards; **gravity through the screen** | tries "depth", pulls everything at the glass, undoes it, gives a sorry gift; scares the enemies | **the HUD style** |
| S12 | **Boss (work in progress)** (`s2_06_boss_wip`) | 1:30 | ~2:30 | the new screen (HUD) added live; the look's polish (tier 2); a boss that does nothing | rebuilds the screen, polishes, builds a boss live and forgets every part of it | **the boss** |
| S13 | **The checkpoint** (`s2_07_boss`) | ~2:30 a try | ~7:00 (≈2 tries) | the boss | narrates, hints, offers help after losses, fights on your side (Patcher) | (help, if offered) |
| | **Total** | **≈19 min of play** (first tries) | **≈30–40 min** | | | **5 forks** (4 if `fork_hud` goes, 9) |

- **Quick early steps:** S7 and S8 are the shortest full sessions (owner: early steps must be quick, "they are not really interesting"). Lengths grow toward ROADMAP 1.2's "5–12 min later" only from S10.
- **Length, against the owner's target:** the owner set the first campaign at **~2–3 h (~2 h 30)** (ROADMAP 2). Running total after v9: Stage 1 ≈ 7 min (target ~20; the 9–11 min gate was missed and "owner decides whether S6 grows" is **still unanswered**, g13-open-questions) + Stage 2 ≈ 30–40 min (target ~45) = **≈ 40–47 min of ~2 h 30**, with Stages 3–5 (target ~85 min) still to come. That is short. v9 does not guess which way the owner wants it: **the M43 report asks one line**: "Stage 1 is ~7 min against ~20 and Stage 2 is planned at 30–40 against 45. Grow now (a session in a stage's middle, ROADMAP 2) or later?" Session lengths are data (`SessionDef.goal` / `duration`), so S7–S13 are built at 3.1's lengths by default and retuned only after the answer.
- **Forks, counted against ROADMAP 2 (the per-stage list) and 1.6 ("about 10–12"):** ROADMAP 2 gives Stage 2 four forks (path, level layout, HUD style, shooter boss) and puts the look at the end of Stage 1 and the enemy type in Stage 1 (built as `fork_enemy`). v9 asks **5**: path (S7), look (S8, moved from Stage 1, 0.3), layout (S9), HUD (S11), boss (S12). **There is no second enemy fork**: the three new enemies are announced and all stay (1.9). The campaign: Stage 1 = mascot, dash (owner-added at G13, after the budget was set), enemy (+ dash aim, a 2-card follow-up) · Stage 2 = 5 · Stage 3 = 3 (RPG path, RPG enemies, RPG boss) · Stage 4 = 1 ("what do we keep?") · Stage 5 = 1 (the final boss's form) = **13** (14 with dash aim). That is one over the budget, because of the owner's own dash fork. **The M43 report asks one line:** "13 forks against 10–12. Drop `fork_hud` (the AI picks the style from your play, announced) to reach 12?" Default if unanswered: keep it, as ROADMAP 2 lists it. The answer is needed before M51, which builds it. Debriefs with a choice: S7, S8, S9, S11, S12 (5 of 7; S10 and S13 have none), closer to ROADMAP 1.2's "in some sessions".

### 0.3 What changes from v8

| | v8 (now) | v9 |
|---|---|---|
| Campaign | 7 sessions, Stage 1, ends "To be continued" | **14 sessions**: a stage card, then S7–S13. "To be continued" moves to after the boss |
| The gun | one `Shooter`; its numbers are rewritten from `Tuning` every tick | **`WeaponDef` data** (pistol, shotgun, laser, launcher, orbit, plus two Auto-only passives) with **4 ranks**. The pistol at rank 1 is today's gun. With no path it still reads `Tuning`, so `--set=` and every hash still match |
| In-run growth | none in the campaign (prompts and the PATCH gauge are off) | **the path's own growth**: card picks (Arsenal), level-up picks (Auto), pickups (Survival). It is the path's mechanic, not a dev-session choice (0.4) |
| Pickups | none | **`Pickup`** entity: gems, weapons, ammo, heal, battery |
| The look | a per-session string, juice only; `palette` is dead data | **3 looks** (pixel / neon / paper): palette roles (`systems/palette.gd`, presentation only) plus one post shader each, picked by fork, restyling the mascot and the world (HUD text stays crisp). Tier 2 (polish) in S12 |
| Levels | one arena per session | a session can play a **stage set**: the v6 breakout / gauntlet / shifting sets, as the layout fork's answers |
| Enemies | 5 archetypes; 3 hard-coded lists | **`EnemyDB.BASES`** (the 5 scenes, the legacy list) + **`EnemyDB.VARIANTS`**, the walker split into behaviour scripts (M43.1), + **splitter** (announced, S8), + **shielder / sniper / swarm** (announced in S10, all three stay) |
| HUD | one corner layout | **3 HUD styles** as tokens over shared widgets, added live in S12 |
| Goals | survive / kills / stop / overrun | **+ `stages`** (the set's own goals) and **`boss`** |
| Death | Move on after every death | unchanged, **except at the boss**: Retry only, a hint after the 2nd loss, **Retry with help** from the 2nd loss |
| Forks | 4 kinds, each hand-wired | **one generic answer helper** (`Unlocks.answer(fork)` on `Fork.answer()`), then 5 new forks on it |
| Look timing | ROADMAP 2 / 6.5: the look at the end of Stage 1 | **asked in S8's debrief** after a live try-on; lands in S9. A change from the ROADMAP's plan, asked at G14a |
| Plan file | `PLAN.md` = v8 | M43 step 0: `git mv PLAN.md PLAN.v8.md` ("Phase 5, done"), this plan becomes `PLAN.md` |
| Save pointer | `campaign.index` (an index) | the next session's **id** (an M42.2 index is mapped on load) |
| Cues | no conditions | a cue can carry a **condition** (`answer:path_auto at 12: add levelups`); grammar `[cond] <when> [N] [at s]: <action>`; new actions `path`, `give`, `drop`, `look <id> [s]`, `boss`; new whens `room N [at s]`, `boss_hp`, `level`, `picked` |
| Reactions | `min_session` / `max_session` by index | **`after` / `until` by session id**, plus a whole-reaction `when` gate |
| Events | `wrong_variable` | **+ `gravity_through_screen`** (S11) |
| Rule edits | 10 | **+ 6** (3 shared, 1 per path) |
| Mortal-bot numbers | some gated milestones (M40–M42) | **reported with hit kinds, never a gate**; hard gates only on invincible pacing, determinism, hashes and the telegraph / dry-time / event rules |

### 0.4 Principles that hold (owner decisions; memory wins over docs)
- **The AI is the main force** (final-vision; ROADMAP 1.3). Every session has at least one thing the AI changes live (the "AI does" column in 0.2; the check table in 3.4). The finished game must not feel "natural".
- **Nothing exists by default. The AI adds each piece live and says so in the session it adds it** (final-vision, M39.1/M39.2; owner: "audit everything default-on"). The path's growth piece, the new HUD, new guns and new enemies arrive by **scripted** cue with a line in the same session (never only by a reaction, which can be dropped by priority or cooldown), never silently through the previous debrief's notes. **A weapon joins the session's offer, drop and crate pools only when its `give` or `say` cue fires**, so no pick, drop or crate hands it out before the AI has said it (tested). Section 3.5 lists every new rule or mechanic with the cue and line that brings it, or why it is invisible.
- **Choices only for big run-start features** (dev-session-big-only). Path, look, layout and HUD change the game from its first second. **`fork_boss` does not:** it shapes only S13. It rests on a later owner decision instead (final-vision: "choices cover mechanics, visuals, UI/UX, enemies, **bosses**, level design"; ROADMAP 2 lists the shooter boss as a Stage 2 fork). New guns, the splitter, the three S10 enemies and the edits are **announced by the AI, never picked from 3**. The AI pitches first, then offers the cards (g13-feedback's dash pattern: "I think … what do you want?").
- **In-run picks are the path, not a dev-session fork.** Arsenal's card picks and Auto's level-up picks happen *inside* play, offer 1 of 3, and reset every session (ROADMAP 1.7: "card picks and card upgrades" / "level-up picks"). They use a new **`PickOffer`** (weapon ids + ranks) and **`PickPanel`** (a `PromptPanel` subclass) and a small path meter, never `Offer` / `AiDirector.on_choice` (which apply a Mutation to the stack, bump the build number and write patch notes): they never offer rule edits or patches, never touch `RunState`'s stack or `build_number`, and never ship anything to the save. This is the one place v9 shows 3-way picks outside a debrief. It is **asked early, at G14a**, with a fallback ready (section 9).
- **Picks are exclusive and permanent** (g11-feedback, A): picking shelves the others. The shelf is stored so Phase 8's final boss can use it. Rework stays parked.
- **Content = sum, not product** (ROADMAP 1.6). Paths, looks, layouts, enemies, HUDs and bosses are independent slots. Weapons are shared by all three paths. A path is **one `PathDef` plus at most one small component, ≤ 250 path-only lines** (reported per milestone; going over needs the owner's OK). HUD styles are tokens over shared widgets. Looks are shaders over one set of shapes. Bosses read the player's weapons and dash instead of having path versions.
- **Power stays in the session** (ROADMAP 1.9.7). Weapon ranks, levels, the hand and pickups reset at every session start. Saved: the path, the weapon *pool* each session lists, and the look, layout, enemy, HUD and boss answers. Asked at G14a (section 9).
- **The AI announces before it edits** (ROADMAP 1.4). Every new edit and the new event warn first. The S7 path swaps, the S8 look try-on and the S9 repaint are announced the same way (a line, a 1.5 s warning, then the change).
- **Story never stalled; bosses are the only gates** (ROADMAP 1.2, 1.9.5). A normal session still offers Move on after a death. The boss never offers Move on. Retries are unlimited and restart at the boss. Help is offered after losses, but the boss still has to fall.
- **Fun before meta:** every session is fun under `--mute-ai`, on every path.
- **Readable apologies** (final-vision: "not too meta"). The depth gag is "I tried to make it 3D. It came toward you instead of away.", not "I flipped the z-axis".
- **Stage 2 does not spend later events' jokes.** UI overload, flicker and the fake "Not Responding" crash belong to Stage 4 (ROADMAP 2). No Stage 2 boss, HUD beat or line uses them.
- **Bots read pacing, not fun** (bot-runs-as-tuning-proxy). Every number in section 6 says whether it is a bot number or needs a human. **Mortal-bot numbers (deaths, time to death, boss tries) are reported with hit kinds, never pass/fail**: a mortal bot is not a model of human skill, and a miss means checking the bot policy first, never retuning the game to it. Hard gates stay only on invincible pacing, determinism, hashes, the telegraph and dry-time rules and "0 hits during the event". Check kills per run first when numbers jump.
- **Lines: I draft every line, the owner edits for tone** (ROADMAP 6.7). A lines file (`campaign/lines_stage2.md`, generated from the session data: 3.2 + 3.3 + the fork cards) ships with the G14a build for a tone pass before M54. Line-timing tests read the data, so an edit is a data change, never a test rewrite.
- **Repo is public** (github-repo): commit per milestone with a tag, as before. Push only when the owner asks.

### 0.5 How Stage 2 can fail (what the milestone order retires first)
| # | Risk | How v9 retires it | Retired at | If it fails |
|---|---|---|---|---|
| R1 | **The three paths feel like one game** (especially Arsenal and Auto, which both pick 1 of 3) | The paths differ on **three axes** (1.5): *what your hands do*, *where power comes from*, *what kills you*. A reported **play fingerprint** and degenerate-strategy **probes** (4) show it; the owner's play at G14a decides | M45–M47 → **G14a** | M47.1 re-spikes the weakest path before any content is stacked on it; for Arsenal vs Auto, the fallback in 9 (the AI deals Auto's picks) |
| R2 | **In-run picks read as the dev-session picks the owner rejected** | Styled as in-game cards, never the mascot's debrief cards; never rule edits; Survival has none; asked directly | **G14a** | Arsenal cards come as drops you walk over; Auto's level-ups are auto-chosen by taste with a line (9) |
| R3 | **The looks are three tints** | Every colour from palette roles first, then a shader per look that changes background luminance, edges and texture; luminance and contrast checks on captures; a spare look | M48 → **G14b** | swap the failing look for the spare `look_terminal` (9) |
| R4 | **The boss is a damage sponge** | Anti-sponge rules (1.10): every phase has a window or a mechanic that ends it, dry time ≤ 8 s, phases 25–45 s for the bot (forced loadouts), a `max_seconds` backstop that only moves to the next phase (P3 opens a damage window instead). Built as a **vertical slice** before S12/S13 | M49 → **G14b** | the boss keeps P1 + P3 only (~70 s) and `fork_boss` drops to one form; the checkpoint stays |
| R5 | **Scope** (5 forks × 3 answers) | One foundation; each milestone adds one session plus one fork; the path line budget; a cut order (6) | every milestone | cut order |
| R6 | **Auto crowds tank the frame rate** | spatial-hash separation (path sessions only), the pickup cap, separate projectile budgets, a bench gate | M45b | Auto cap 100 enemies, HP ×0.8 |
| R7 | **Gravity through the screen reads as a bug, or kills you** | presentation only (frozen play, proxies), warned, clock held, the AI's panic as the punchline, a gentle variant | M52 | shorten to squash + crack + pop back (3 s) |

---

## 1. Contracts

### 1.1 Answers, generically (the plumbing everything stands on)
- **Built on what exists:** `Fork.answer() -> Change` and `Fork.shelf() -> Array[Change]` (`devsession/fork.gd:34,46`) and `Change.take`, a `MockupTake` with `.id` (what `dash_answer()` reads today). v9 adds only **`Unlocks.answer(fork_id) = ChangeDB.get_fork(fork_id).answer()`** (null if unanswered) and **`Unlocks.take(fork_id) = answer.take.id`** (e.g. `&"auto"`). Every existing per-fork reader (`dash_answer`, `dash_aims`, the `fork:fork_enemy` resolution) is rewritten on top of them. No `Change.take_id`, no `Fork.shelved()`, no new per-fork helper (each fork kind needed 4–5 touch points; five more would repeat that five times).
- **Every new change carries a `MockupTake`** (path, layout, hud, boss, the 3 new looks), so there is one code path. New `Change.KINDS`: `path`, `layout`, `hud`, `boss`. `look` (exists) gets 3 new changes. Only the debrief's card renderer (1.12) branches on the kind. The new changes are `.tres` files under `devsession/changes/` with `Fork.campaign = true`.
- **`fork:<id>` everywhere:** any `SessionDef` field that names content can hold `&"fork:<id>"` (`path`, `look`, `stages`, `hud`, `boss`). `SessionDef.resolve(field)` returns `Unlocks.take()`. `problems()` checks that an **earlier** session asks the fork.
- **Line conditions** (`campaign/line.gd`, whose head is 1–2 words): every new condition is **one word** (`attempts:2`, `help:1`, `first_try`, `died_in:s2_02_day_one`), and `&` joins **any** conditions, plain ones too (`died&attempts:2`, `won&first_try`, `event:gravity_through_screen&hit_none`), not only the `JOINABLE` `dash:` / `dash_aim:` (M42.2). **`!` negates one condition** (`!answer:path_auto`), for lines, cues and `ReactionDef.when`. `died_in:<session>` is true when the save has a death in that session (it reads `campaign.attempts`; for the mascot's memory, 3.2).
- **CLI:** `--answer=<fork>=<change>` (repeatable), for the game and the bot. `--dash=` / `--dash-aim=` stay as aliases (tested byte for byte). `--session=<id>` answers every earlier unanswered fork with option 0 unless `--answer=` says otherwise.
- **The shelf for Phase 8:** `Fork.shelf()` as built, plus `CampaignDB.shelf(stage)` (new: every shelved change of that stage's forks), tested for every Stage 2 fork.

### 1.2 Sessions (additions to `SessionDef`, v8 1.1 / 6.1)
- `path: StringName`: `&""` = Stage 1's plain gun, `&"fork:fork_path"`, or a path id (S7's tastes switch it by cue).
- `weapons: Array[StringName]`: the weapons this session may hand out (each session lists it in full; content = sum). The path's start weapon is live from second 0. **Every other weapon joins the live offer / drop / crate pool only when a `give <weapon>` or `say` cue tagged with it (`at 25 [laser]: say …`) fires**; before that no pick, drop or crate can carry it (tested per session × path).
- `stages: StringName`: `&""` = the single `arena` (today), a set id (`breakout`, `gauntlet`, `shifting`), or `&"fork:fork_layout"`. With a set, `goal = &"stages"` and the set's own per-part goals run (v6 `StageDef`: `exit` / `survive`). `TopdownGenre` stops wrapping the session in `StageSet.single` when `stages` is set. **In a session a part ends on `duration` / its exit only:** `StageDef.prompts` is forced to 0 (the AiDirector is off in sessions), and in-run picks never count as stage prompts (tested). A part's clear sweeps pickups, dropped weapons and crates.
- `look` stays a **String** (`SessionDef.look`, today a take like `"punchy"`). It also accepts `"fork:fork_look"` and a tier suffix `"fork:fork_look@2"`. `problems()` parses `fork:<id>[@tier]` and checks `res://systems/looks/look_<tier>_<take>.tres` for each answer's take (`pixel` / `neon` / `paper`). `Unlocks.look()` returns `{tier, take}` from it: today it maps any non-empty take to tier 1; v9 reads the `@tier` suffix (default 1). Unanswered (a jump or an old save) = tier 0.
- `hud: StringName`: `&""` = today's corner text, or `&"fork:fork_hud"`.
- `boss: StringName`: `&"fork:fork_boss"` or a boss id; required when `goal = &"boss"`. `checkpoint: bool` (true for goal `boss`; `problems()` refuses a boss goal without it): no Move on, hints and help (1.10). `tryout: bool` (S7 only): allows `path` cues.
- `spawn_weights: Dictionary` (archetype → weight; empty = today's `Tuning` chances, so Stage 1's numbers do not move).
- `rules.hp_floor` (new `WorldRules` int, default 0, under the reversibility invariant): `Health` reads it when it applies damage and never drops below it. Default 0 is a no-op (in the v6 hash compares). S7 has health (it inherits Stage 1's basics) and uses 1 ("Can't lose today. It's a tryout.").
- **Goals:** `GOALS` adds `stages` (won when the set's last part clears) and `boss` (won when the boss's HP reaches 0; no time limit). A kills goal is multiplied by the path's **`kill_goal_mult`** (Auto **×2.0**, others ×1.0; one number, 1.5), so Auto's crowds don't end it in a minute.
- **Basics** (`Unlocks.CAMPAIGN_BASICS`) add `cards` (Arsenal hand + card meter), `levelups` (Auto gems + LV bar), `pickups` (Survival drops + crates), `kill_heal` (Survival) and `hud` (the styled HUD). They follow M39.2's rules: always on outside a session, added live by `add` cues, and a session lists what it has. `problems()`: a path basic under another path's condition is a problem.
- **The stage card** (`ui/stage_card.gd`, titles in **`CampaignDef.stage_titles`**, a new field; `campaign_def.gd` is 7 lines today; `CampaignDB.problems()` checks a title for every stage a session names): when a session's `stage` is higher than the last one played, a 3 s card plays before its intro. It is not a session and writes no telemetry line. Skippable after 0.5 s.

### 1.3 Cues (additions to `campaign/cue.gd`, v8 1.5 / 6.6)
- **Grammar:** `"[cond] <when> [N] [at s] [\[tag\]]: <action>"`. The condition is Line syntax (one-word conditions joined by `&`, `!` to negate): `"answer:path_auto at 12: add levelups"`. A cue whose condition fails is dropped at session start (never half-fired). `[tag]` names the weapon a `say` cue announces, for the pool rule (1.2).
- **Whens:** `room N [at s]` (part N of the set starts, 1-based; with `at s`, s seconds after part N starts), `boss_hp N` (boss HP ≤ N %), `level N` (Auto reaches level N), `picked N` (the N-th in-run pick is done, any path). They join `at`, `kills` and `pct`.
- **Actions:**
  - `path <arsenal|auto|survival|off>`: S7 only. Swaps the session's path live with a warning. It clears the player's weapons, pickups and shots (not the enemies) and gives the new path's start loadout. `problems()` rejects it outside a session marked `tryout`.
  - `give <weapon> [rank]`: Arsenal gets a free card (the hand full: the weakest card is replaced). Auto's next level-up offers it first. Survival gets a crate landing near the player.
  - `drop <weapon|ammo|heal> [n]`: pickups at free tiles.
  - `look <id|fork:fork_look[@tier]> [seconds]`: shows a look live under a glitch wipe. With seconds, it falls back to the session's look afterwards (S8's try-on).
  - **The glitch wipe** (used by `path` and `look`) flashes at most **3 times per second**; under reduce flashing it is a 0.4 s crossfade instead (tested on the S7 swaps, the S8 try-on and the S9 repaint).
  - `boss <id|fork:fork_boss> [dummy]`: spawns the boss; `dummy` = S12's harmless one.
- **Enemy lists:** the three hard-coded lists (`cue.gd:29`, `unlocks.gd:11`, `spawner.gd:7`) become **`EnemyDB.BASES`** (the 5 scenes; the legacy list) in M43.1, before any enemy is added. `Unlocks.ARCHETYPES` becomes an alias of `BASES`, so `Unlocks.enemies()` under unlock_all, `test_save.gd:315`, `ChangeDB` validation and the legacy loop do not move. The new enemies are **`EnemyDB.VARIANTS`**; **`EnemyDB.all()`** (bases + variants) is what cues and sessions validate against.

### 1.4 Weapons: one foundation for three paths
- **`WeaponDef`** (`weapons/<id>.tres`, script `weapons/weapon_def.gd`):
  - `id`, `title`, `mode` (`aimed` / `passive`), `cooldown`, `damage`, `pellets`, `spread_deg`, `pierce`, `bounces`, `speed`, `lifetime`, `size`, `blast_radius` (tiles, 0 = none), `ammo` (Survival only; −1 = infinite), `pickup_ammo`, `color_role` (a palette role, 1.7), `icon` (a shape drawn with `_draw`, so looks restyle it), `sound`.
  - `ranks: Array[Dictionary]`: ranks 2–4 as **values, not deltas** (`{"knockback": 0.5}`), so a rank reads on one line. **Every rank 2–3 adds one behaviour** (a `trait`, a small script under `weapons/traits/`), not a number (owner: "upgrades can be even more creative", "think outside the box"). **Rank 4 is an evolution** (`evolve`), a new trait that is **not** a reskin of a v6 patch. A trait that proves too costly in its milestone falls back to a number, logged in the report.
  - `pitch` (the AI's line when it brings the weapon), `card_text` (Arsenal card / Auto offer).
- **`Weapon`** (runtime): a def + `rank` + `ammo_left`. It lives on the player and is never saved.
- **`Loadout`** (`components/loadout.gd`, a child of the player): `slots`, `active`, `fire_mode` (from the path), `try_fire(dir, auto)`, `give`, `upgrade`, `switch`, `clear`. It drives `Shooter.fire(weapon, dir)` (pellets with spread, pierce with a skip list, bounces, blast through `Explosion.blast`, size, lifetime). It runs passives as child nodes. Auto's "everything fires" is several cooldown timers inside one `Loadout`, each capped by `hard_max_projectiles`.
- **The pistol is today's gun:** cooldown 0.18, speed 900, damage 1. **With `path = ""` (Stage 1, the legacy loop) the loadout holds only the pistol at rank 1 and reads `Tuning.shoot_cooldown` / `projectile_speed` every tick as today.** So `--set=` tuning, both v6 hash compares and the M42.2 Stage 1 chain must match exactly (gate M44).
- **`Projectile`** gains `pierce_left` + a skip list, `bounces_left`, `size`, `lifetime`, `weapon_id` (rides `DamageInfo.source_patch`, for kill credit per weapon). Defaults keep every hash identical, **tested at M44 itself** (both v6 hash compares and the m42.2 campaign hash).
- **No rank state is added to `RunState`.** Weapon ranks live on `Weapon`, and `RunState.can_apply` keeps refusing duplicate patches.
- **Randomness:** two new streams, **`RunState.loot_rng`** (drop rolls, crate timers and tiles, gem merges, the weapon-rain tiles) and **`RunState.pick_rng`** (offer draws, `edit_shuffle_hand`, the Copycat's jitter), seeded from `run_seed` with fixed offsets. Nothing new draws from `gameplay_rng` (the spawner's), so drops never shift a spawn (tested: S8 with drops on and off spawns the same enemy sequence for 60 s).
- **Projectile budgets:** `RunState._under_cap` today limits player + enemy shots together to `hard_max_projectiles` (200), so a full Auto loadout could starve snipers and boss rings (the M13 cap-leak lesson). v9 splits it: **player 140, enemy 60 (reserved)**, tested with Auto saturated: a sniper and a 16-shot boss ring still fire. Telemetry reports `enemy_shots_refused` and `player_shots_refused`. Boss summons, swarm packs and splitter minis count against `hard_max_enemies`; the boss itself does not (its own group, 1.10).
- **The roster (5 shared + 2 Auto-only passives):**

  | id | mode | Rank 1 | Rank 2 (a behaviour) | Rank 3 (a behaviour) | Rank 4 (evolution, new) | Ammo (Survival) | From |
  |---|---|---|---|---|---|---|---|
  | `pistol` | aimed | cd 0.18, 900 px/s, dmg 1 | **heavy round**: every 5th shot is big (×3 dmg, ×2 size, pierce 1) | **seeker**: shots bend toward the nearest enemy within 4 T (60°/s) | **chain**: a kill sends the shot on to the next enemy within 5 T, up to 3 hops | ∞ (the sidearm) | S7 |
  | `shotgun` | aimed | 5 pellets / 28°, cd 0.55, life 0.35 s | **knockback cone**: pellets push enemies 0.5 T | **point-blank**: pellets ×2 damage within 2 T, the cone narrows to 18° | **shrapnel**: pellets that hit nothing stick to the floor as caltrops for 3 s (1 dmg on touch) | 24 | S7 |
  | `laser` | aimed | 1600 px/s, pierce 3, dmg 2, cd 0.6 | **burn line**: its path burns for 1 s (1 dmg per 0.5 s to what crosses it) | **ricochet**: bounces off a wall once, pierce resets | **overcharge**: every 4th shot is a 1 s beam across the screen that follows your aim (Auto: sweeps the target's group) | 16 | S9 |
  | `launcher` | aimed | 600 px/s, blast 1.6 T, dmg 2, cd 0.9 | **sticky**: shots stick to the first enemy or wall and blow 0.6 s later (blast ×1.2) | **implode**: the blast pulls enemies 0.6 T in before it pops | **mine layer**: every 3rd shot also drops a mine at your feet (arms in 0.5 s, blast 1.6 T) | 10 | S10 |
  | `orbit` | passive | 2 shards, r 2 T, dmg 1, tick 0.4 | **flare**: dashing flings the shards out to ×2 radius for 0.6 s | **guard**: a shard eats an enemy shot (that shard regrows in 1 s) | **moons**: a shard kill adds a temporary shard (max 6, 5 s each) | battery: 20 s | S11 |
  | `nova` (Auto only) | passive | a blast r 1.5 T around you every 3.0 s | **shove**: the nova pushes survivors out 1 T | **dash nova**: a dash triggers the nova early (then 3 s cooldown) | **shockwave**: the nova travels out as a ring to 4 T, damage at its edge | — | S9 |
  | `well` (Auto only) | passive | kills leave a pull field for 1.5 s | **magnet**: fields pull gems too | **teeth**: fields hurt (1 dmg/s) | **black hole**: 3 fields that touch merge into one that eats enemy shots for 3 s | — | S11 |

  - The v6 mutations `echo`, `bouncing_projectiles`, `explode_on_hit`, `orbit`, `well` stay as they are for the legacy loop and `edit_gift_explode`. The `orbit` weapon reuses `mutations/orbit/orbit_shards.gd` and `well` reuses `mutations/well/well_field.gd`; no evolution reskins a v6 patch (those stay a pool for the endgame director).
  - Rank 4 is built in **M50.1**; until then ranks stop at 3 (tested: no offer or pickup shows rank 4).
  - Caps: the shotgun at its top rank under Auto, with every slot full, stays inside the player budget (140) at the enemy cap, and enemies keep their 60 (tested).
  - **Never in a path:** stat-only items ("+10% damage"). The one filler is "+1 HP" when every offer would be maxed.

### 1.5 The three paths
- **`PathDef`** (`paths/<id>.tres`, script `paths/path_def.gd`), the take of a `path` change:
  - `id`, `fire_mode` (`manual_one` / `auto_all` / `manual_ammo`), `growth` (`cards` / `levelups` / `pickups`), `start` (start loadout), `max_slots`, `offer_pool_extra` (Auto: `nova`, `well`), `spawn_rate_mult`, `max_enemies_mult`, `enemy_hp_mult`, `kill_goal_mult`, `boss_hp_mult` (1.10), `widget` (`hand` / `level` / `ammo`), `bot_policy`.
  - Its density numbers are a `WorldRules` overlay (owner `&"path"`, session layer, reverts at the session end).
  - The path is read from the save (`Unlocks.take(&"fork_path")`), or from S7's `path` cue while a taste is live (`RunState.session_path`).
- **Shared by all three:** movement, the dash (3 styles × 2 aims, M42.1/M42.2; on Auto with `dash_aim = aim` the aim is still the mouse or stick, even though nothing is fired with it), health, the enemies, the rule book, the events, the look, the layout, the HUD, the boss.
- **The three axes that keep them apart** (R1; every number below serves one of them):

| | **Arsenal** (`path_arsenal`) | **Auto** (`path_auto`) | **Survival** (`path_survival`) |
|---|---|---|---|
| Identity (owner) | every card is a weapon; upgrading the card upgrades the weapon | auto-fire; increasingly powerful upgrades (Vampire Survivors-inspired) | weapons on the ground to pick up; kills give HP |
| **Your hands** | aim, fire, **switch**: new actions `weapon_prev` / `weapon_next` (Q / E, the wheel, pad bumpers) and `weapon_1..3` (keys 1–3, only while no panel is open; `choose_1..3` keep the keys inside a panel). E stays bound to the legacy `wait` too, which only B2's turn mode reads (tested: no campaign code reads `wait`). **Quick-draw:** the first shot after a switch does ×2 damage, so switching is a skill | **move only.** Every held weapon fires on its own at the nearest visible enemy within 12 T (launcher: the densest group; `auto_attack`'s target code). The fire button does nothing ("You don't need that anymore.") | aim, fire, **scavenge**: walk over a weapon to take it. At 0 ammo it falls back to the pistol sidearm in one frame (never stuck) |
| **Where power comes from** | a **deliberate card pick, rare**: a meter fills with kills (15, then ×1.4 each time); full → pick 1 of 3 (a new card while the hand has room, else an upgrade; a duplicate is an upgrade). ~3–5 a session | a **level-up, often**: every kill drops a gem (tank / bomber / shielder 3); thresholds 3, 8, 15, 24, 36, 50, 66, 84, then +20; level-up → pick 1 of 3 (a new weapon or passive while a slot is free, or an upgrade). ~6–10 a session. Nova and well exist only here | **the floor, no menu ever**: 10% of kills drop a weapon or ammo (tank / bomber / shielder / sniper 35%); 2 crates when `pickups` is added (S8: at 10 s), then 1 every 20 s (max 3 on the ground). The same weapon again = +1 rank and full ammo; another weapon = swap (yours drops at your feet, untouchable for 0.5 s). Ammo pickups refill 50% |
| **What kills you** | the wrong card for the enemy (shielders, swarms), switching too late | the crowd: **×1.6 spawns, ×1.5 cap, ×0.7 HP** | running dry; HP comes back only from kills: **`kill_heal`, +1 HP every 5 kills**, capped at max HP |
| Held | a hand of up to 3 cards | up to 4 weapons + 2 passives | 1 weapon + the sidearm |
| Pick panel | `PickPanel` with a `PickOffer` (pauses play, `choose_1..3`, the 0.4 s input delay of M42.1); the pick goes to `Loadout`, never `RunState.apply` | the same panel | none |
| Kill goals | ×1.0 | **×2.0** | ×1.0 |
| HUD widget | the hand (cards with rank pips, the active one raised) + the card meter | the LV bar, the level number, held weapons | the weapon, ammo pips, the sidearm icon |
| Path edit (AI) | `edit_shuffle_hand` | `edit_auto_wrong` | `edit_weapon_rain` |
| Path-only code (budget ≤ 250 lines) | `HandWidget` + switching + quick-draw (~170) | slot targeting + gems on `Pickup` (~150) | `Drops` + crates + ammo + kill-heal (~240; `Pickup` itself is shared) |

- **Pick offers** are drawn from `pick_rng` (deterministic, 1.4) out of the **live** pool (1.2). They lean on what the player uses (Arsenal: the most-fired card's upgrade first; Auto: weapons already held) through `director/taste.gd`'s weights. Never more than 6 picks in a session for Arsenal and 10 for Auto; past that the meter stops ("That's enough cards for one test.").
- **Pause rule:** a pick panel never opens while a rule-edit warning, an event or the S8 try-on is running. It waits (like slow-mo's busy hold, v8 6.7). The panel pauses through `RunState.set_pause(&"pick", true)`.
- **Path-only lines are countable:** path-only code lives under `paths/<id>/` (or carries a `# path:<id>` header); `tools/path_lines.gd` counts them and every milestone report quotes it against the 250 budget.

### 1.6 Pickups
- **`Pickup`** (`entities/pickup.gd` + `.tscn`, built in M45a for Auto's gems, then reused by Survival), kinds `gem` (value), `weapon` (an id), `ammo`, `heal`, `battery` (orbit for 20 s, Survival). Registered as a new `RunState` kind `pickup` with its own cap (**60**; over it, the oldest gem merges into the nearest). Lifetime 14 s, blinking for the last 3 s (gems never expire). Magnet: gems fly to the player within 3 T, others within 0.6 T. Only the player picks up.
- Ground spots: `ArenaDef.pickup_tiles` (optional, 4–8 per arena, checked reachable by `problems()`'s flood fill; else the spawn tiles farthest from enemies).
- `systems/drops.gd` listens to `EventBus.enemy_killed` and runs the path's drop table (on `loot_rng`, from the live pool only) and kill-heal. New EventBus signals: `pickup_taken(kind, id)`, `weapon_changed(id, rank)`, `pick_offered(offer)`, `pick_made(id)`, `level_up(n)`, `boss_phase(n)`.

### 1.7 The three looks (ROADMAP 1.8: one set of shapes, three renderings)
- **`Palette.color(role) -> Color`** (new, **`systems/palette.gd`**, presentation only) is the only way a visual gets a colour. It is separate from `Look` because `test_readability.gd`'s `test_nothing_outside_presentation_reads_the_look()` allows only `LOOK_READERS` (projectile.gd, main.gd, camera_rig.gd, feedback.gd, debug_overlay.gd) to read `Look.`; `Palette` reads the current `LookPreset` once and the lint adds `systems/palette.gd` alone to `LOOK_READERS` (M48). A second lint keeps gameplay scripts (`enemy_walker` and its behaviours, `spawner`, `drops`, `loadout`, `health`) off `Palette`. Roles: `bg`, `grid`, `wall`, `player`, `player_shot`, `enemy`, `enemy_shot`, `elite`, `pickup`, `blast`, `ui_text`, `ui_panel`, `accent`, `danger`. **Every hard-coded colour is routed** through `Palette`: `levels/arena.gd`, `entities/projectile.gd`, `entities/explosion.gd`, the enemy and player `RectVisual`s, `mutations/orbit/orbit_shards.gd`, `mutations/elite/elite_mark.gd`, `mutations/well/well_field.gd`, `mutations/hunter/hunter_body.gd`, `systems/feedback.gd`, the HUD, the mascot bodies, the debrief (M48 lists the exact files in its report). **Tier 0 is a role table of today's colours**, so nothing moves until a look is picked (v6 hashes and the m42.2 tier-0 screenshot reference unchanged).
- **`systems/look.gd` exists** (`class_name Look`, static; `use(look: Dictionary) -> LookPreset`, `path_for(tier, take)` building `look_%d_%s.tres`). v9 keeps that form: the new presets are **`systems/looks/look_1_pixel.tres`, `look_1_neon.tres`, `look_1_paper.tres`** and `look_2_*.tres`, with takes `pixel` / `neon` / `paper` (the change ids stay `look_pixel` etc.), so `test_dev_session.gd:150-153` (every look change's preset is at `Look.path_for(1, take.id)`) keeps holding. `LookPreset` gains `palette` (role → Color; the dead field becomes the roles), `shader` + `shader_params`, `body_style` (`fill` / `glow_outline` / `sketch`), `tier`. The legacy juice presets (`look_0`, `look_1_punchy/arcade/clean`) stay for the legacy loop.
- **`LookLayer`** (`systems/look_layer.gd`, a `CanvasLayer` + `BackBufferCopy` like `time_tint.gdshader`): one full-screen pass **above the world and the mascot, below the HUD text and the debrief text**, so text stays crisp in every look.
- **`Look.try_on(look: Dictionary, seconds := 0.0)`** (new, next to `use`) runs **mid-session** (S8's try-on, S9's repaint, F2): it re-colours live nodes through a `look_changed` signal and swaps the pass under the glitch wipe (1.3: ≤ 3 flashes/s, a crossfade under reduce flashing). With seconds it restores the previous look.
- **The three looks (tier 1, from S9):**

  | Look | Post pass | Palette | Juice |
  |---|---|---|---|
  | **Pixel** (`look_pixel`) | render at ¼ resolution (nearest), quantise to a 16-colour palette, 2×2 ordered dither on gradients, 1 px dark outline at colour steps | warm retro: dark navy bg, cream player, red enemies, yellow shots | hit stop +20%, chunky 4 px particles, stepped trails |
  | **Neon** (`look_neon`), the darker one | black bg, bodies as glowing 2 px outlines, a cheap two-tap blur added back on bright pixels (bloom) | cyan player, magenta enemies, lime shots, walls as thin white lines | long trails, kill rings; under reduce flashing the bloom halves |
  | **Paper** (`look_paper`), the totally different one | a paper texture multiplied under everything, a ±1 px UV wobble ("boil") at 8 fps | graphite on cream, enemies in red pencil, shots as ink dashes | `RectVisual` draws 2 jittered outlines re-seeded at 8 fps, splats instead of particles |

- **Distinct, not three tints (checked on captures, M48):** mean background luminance differs by **≥ 0.15** pairwise; player and both shot kinds against the background reach **≥ 3:1** contrast in every look. A spare look is ready if one fails at G14b: `look_terminal` (green on black, CRT).
- **Tier 2 (S12, "a polish pass"):** pixel = CRT scanlines + slight curvature; neon = a bass pulse on the bloom (≤ +20%) + a faint grid glow; paper = a hand-written HUD font and margin doodles. All three also get themed explosion shapes.
- **Reduce flashing:** no white in any `blast` role; neon's pulse capped; paper's boil drops to 4 fps; every glitch wipe becomes a crossfade.
- **Checks need a renderer:** headless boots use a dummy renderer, so shader compiles, `LookLayer` order and the luminance / contrast numbers run in **`tools/look_check.gd`, windowed, not in check.ps1**: it writes the `.check/look_*` sheets and prints the numbers, which `export.ps1`'s windowed look boots check.
- **Cost rule:** a look is one `.tres` per tier and one shader. No sprite sheets, no per-entity art.

### 1.8 Levels and the HUD
- **`fork_layout`** reuses the v6 stage sets as its answers, with new names and lines: `layout_rooms` → `breakout` (three rooms; reach each room's exit), `layout_gauntlet` → `gauntlet` (three arenas back to back; hold each one), `layout_shifting` → `shifting` (one arena that rebuilds itself while you fight; you keep your place). These are **new** files: `devsession/forks/fork_layout.tres` (`campaign = true`) and `devsession/changes/layout_*.tres` (kind `layout`, each with a `MockupTake`), pointing at the same StageSet presets. The v6 `stages` fork (`genres/topdown/devsession/changes/stages_*.tres`, `forks/stages.tres`, genre-scoped, kind `stages`) stays in the legacy dev session and is never asked in a session (tested).
- M50 retunes the three sets for sessions: each part **60–80 s** for a human, spawn presets from the session, `pickup_tiles` in every part, the exit gate (`levels/exit_gate.gd`) and the shifting swap as built. Every exit is reachable with all 3 dash styles × 2 aims.
- S12 and S13 use `arena_boss` (arena_0's border, 4 pillars, 8 pickup tiles). It arrives with a line (3.2 S12: "I built it a room.").
- **`HudStyle`** (`ui/hud_styles/<id>.tres`): tokens only (font, size, panel shape, where each widget anchors: `corner` / `top` / `bottom` / `on_player`, and whether score and combo show). **Widgets** are shared small Controls (`HpWidget`, `GoalWidget`, `VersionWidget`, `DashWidget`, `HandWidget`, `LevelWidget`, `AmmoWidget`, `BossWidget`) that read the style. The cost is 3 token sets + one draw branch per widget per anchor, not 3 × 8.
  - **Clean** (`hud_clean`): small numbers in one corner; the path widget under the HP.
  - **Arcade** (`hud_arcade`): a top bar with an HP bar, a **score** and a **combo** (kills within 2 s; v8 6.4's "Kills back as a score"); the path widget in a bottom strip. Big and loud, but not an overload beat (0.4).
  - **On you** (`hud_onyou`): HP as a ring around the player, ammo as dots on the barrel, cards as small chips over the player, LV as the player's glow. The corners stay empty except the mascot.
- Before S12 (and in Stage 1) the corner text of M39.2 stays. **The mascot stays top-right in every style.** Tested: no widget of any style overlaps the mascot or the centre 70% of the screen (except `on_player` ones), for 3 styles × 3 paths.

### 1.9 Enemies and new rule edits
- **`EnemyDB.BASES` / `VARIANTS` / `all()`** (1.3), built in **M43.1** together with the walker split: `enemy_walker.gd` (403 lines, 3 state machines inline) becomes per-archetype behaviour scripts, with both v6 hash compares and the m42.2 campaign hash identical.
- **`EnemyVariant`** (`enemies/variants/<id>.tres`): `base`, `scale`, `hp_mult`, `speed_mult`, `colour_role`, `on_death` (`none` / `split n` / `blast r`), `shield_arc_deg`, `pack`, `keep_range`, `telegraph`. The spawner applies it after the base scene is made, using the existing split, elite-shield and blast code. New enemies are data on 5 bases wherever possible.
- **Splitter** (`splitter`, a chaser variant, **announced** in S8): splits into 2 minis (½ size, 1 HP) on death, once (v6 `enemies_split`, generation cap 1). Line: "New enemy. It's two enemies. Sort of."
- **Three new enemies, announced in S10** (one per part, each with a scripted line) **and all three stay** (no fork: the enemy type was Stage 1's fork, ROADMAP 2, and the fork budget is full, 0.2). From S11 they join the spawn mix through `spawn_weights`:
  - **Shielder** (`shielder`, a tank variant): slow, a 100° frontal shield that blocks shots from the front, turning at 90°/s. Blasts, pierce and orbit get through, so every path can beat it (Arsenal's laser, Auto's orbit and nova, Survival's launcher or a flank).
  - **Sniper** (`sniper`, a shooter variant): keeps 9–12 T away, draws a red line for 1.0 s, then one shot at 1400 px/s down it. The line publishes a `DangerZone` (the boss's primitive, built here first) so the bot can step out of it before anything is measured.
  - **Swarm** (`swarm`, a chaser variant): packs of 5, 1 HP, speed ×1.6, size ×0.6 (`edit_tiny_enemies`' numbers).
  - S11–S13 list all three in `enemies` with low weights (S11: 0.15 each against the base mix). Nothing goes to the shelf. If the owner wants an enemy fork back (9), `fork_enemy_2` can be added on the same data later.
- **Separation:** walker separation (`enemy_common.gd:8-15`, O(n²)) gets a spatial hash **only in sessions with a path**, so Stage 1 and the legacy loop run today's loop byte for byte.
- **New rule edits** (rule book, v8 1.4 / 6.5 conventions: each warns, each reverts exactly):

  | id | target | What it does | Duration | Warn / done lines | Session |
  |---|---|---|---|---|---|
  | `edit_screen_wrap` | walls | the border walls vanish; leaving one edge brings you (and enemies, and shots) in at the other | 15 s | "Walls. Who needs walls?" / "Walls are back. I missed them." | S9 |
  | `edit_hot_edges` | walls | the outer 2 tiles hurt (1 HP per 1 s inside), never on an exit gate's tiles | 10 s | "Let's make it cozy." / "Okay, room to breathe." | S10 |
  | `edit_enemies_flee` | enemies | walkers steer away from the player (shooters and snipers still shoot) | 10 s | "What if they were scared of you?" / "Brave again. Sorry." | S11 |
  | `edit_shuffle_hand` (Arsenal) | player | the active card changes at random every 4 s | 12 s | "Your cards are too neat. Let me shuffle." / "Okay, back in order." | S9 |
  | `edit_auto_wrong` (Auto) | player | auto-aim picks the **farthest** visible enemy | 12 s | "Let me improve the aim. Hm." / "Nearest first again. Sorry." | S9 |
  | `edit_weapon_rain` (Survival) | world | 6 weapon pickups fall on random free tiles over 3 s (a shadow 0.8 s before each) | instant | "Gift time. Look up." / — | S9 |

  - Path edits `requires` their path change; `RuleDB` checks it. Conflicts: `edit_screen_wrap` with `edit_hot_edges` and `edit_bouncy_walls`.

### 1.10 The boss (a checkpoint)
- **`BossDef`** (`bosses/<id>.tres`): `id`, `title`, `hp` (base × the path's `boss_hp_mult`), `size`, `phases: Array[BossPhase]`, `arena`, `lines`, `hints` (one per phase).
- **`BossPhase`**: `ends_on` (`hp` / `mechanic` / `script`), `hp` or the mechanic's target, `attacks: Array[BossAttack]`, `on_enter` (a line, an optional rule edit or spawn), `max_seconds`.
- **`BossAttack`** (`bosses/attacks/*.gd`, shared primitives): `ring`, `spiral`, `aimed`, `charge` (the lancer's line telegraph), `summon`, `slam` (an `Explosion.blast` ring), `copy_weapon`, `copy_dash`, `cast_edit`. Every attack **telegraphs ≥ 0.6 s**, readable in all 3 looks, and publishes a `DangerZone` for the bot. Attacks are data, so Phase 8's final boss can build from shelved answers ("you didn't want the shotgun? it did.").
- **`Boss`** entity (`entities/boss.gd`, on `mutations/hunter/hunter_body.gd`'s pattern: its own group, outside the spawn caps). It has an HP bar (`BossWidget`, top centre in every style), emits `boss_phase`, and has a 1.0 s invulnerable stagger between phases, with a line.
- **Anti-sponge rules (R4; tested and logged):**
  - Every phase has a damage window or a mechanic that ends it early (a core that opens, adds, a split).
  - **Dry time ≤ 8 s:** the boss is never unhittable for more than 8 s in a row.
  - Phase HP is set from the **invincible bot's measured DPS per path**, so each phase lasts **25–45 s** for that bot.
  - **`max_seconds` backstop** (60 s per phase) **only moves to the next phase**, with a line, as a developer would: "Let's skip to the good part." **The last phase has no skip:** at its `max_seconds` it opens a permanent damage window (×2, the core showing) with "Okay, I'm opening it up. Hit it!". A win needs the boss's HP at 0 or every part dead (tested: no timer, backstop or help level ends the fight any other way).
- **The three bosses (`fork_boss`):**

  | | **The Big Square** (`boss_square`) | **The Copycat** (`boss_copy`) | **The Patcher** (`boss_patch`) |
  |---|---|---|---|
  | Body | a square 5× the player, in the look's enemy colour | the player's shape and colour, inverted | a floating window with a cursor-brush and a "bug" core |
  | Phase 1 | rings of 16 shots every 2.2 s; a charge across the arena every 6 s. **After each charge it is dizzy 2.5 s and its core opens (×3 damage).** Ends on the core's HP | fires **your** active / best weapon at your rank (0.25 s lag, ±8°, shots ×0.7 speed), keeps 6–9 T away. Ends on HP | every 8 s **casts a rule edit** with the full warning (`edit_bouncy_walls`, `edit_big_enemies`) and summons 3 chasers. **After each edit lands its core opens for 4 s (×2 damage).** Ends on HP |
  | Phase 2 | + a 4-arm spiral for 3 s; summons 4 chasers; the core window stays | + **your dash style** (classic / hook / teleport) to dodge when you aim at it; copies your **last in-run pick** (a card, a level-up weapon, the last weapon you took) | gravity edits (left → up → down by `swap`) + `edit_tiny_enemies` swarms |
  | Phase 3 | **splits into 4** quarter squares, slower rings. **Ends when all 4 fall** | **two copies** with ½ HP each | `edit_screen_wrap` + `edit_inverted` 6 s; then **the mascot fights back**: it reverts the Patcher's live edit for you once ("No! That's MY tool. Undo!") |
  | Lines | P2 "It's angry. I gave it anger." · P3 "It split! I didn't tell it to do that." | P1 "It's you. You look good." · P3 "Two of you. Is that better or worse?" | P1 "It's using my tools!" · P2 "Hey! Gravity is MY bit." |
  | Hints (after a loss in that phase) | P1 "Wait for the charge. Then hit the middle." · P3 "Small ones first? Or the big one? Try small." | P1 "It shoots what you shoot. Move more." · P2 "It dashes when you aim. Aim late." | P1 "When I warn, it's coming. Then hit the bug." · P3 "I've got your back on this one." |

  - **Starting HP** (tuned in M49/M53 from the bot's DPS): Square 300, Copycat 220, Patcher 260. `boss_hp_mult` starts at Arsenal ×1.0, Auto ×1.3, Survival ×0.9.
  - **The Patcher is built first** (the M49 vertical slice): it reuses the rule book the most and needs the fewest new primitives.
- **Checkpoint flow** (`SessionDef.goal = &"boss"`, `checkpoint = true`; the debrief's `_finish()`):
  - On a death: the debrief plays `died` lines and offers **Retry** only. **Move on is never offered** (tested on attempts 1–8). Retry restarts the boss session with a new seed, never the stage.
  - **Hints, then help** (ROADMAP 1.2: "after a few losses the AI offers help"). From the **2nd** loss the debrief says the hint of the phase you died in, and adds **Retry with help** ("I can tune it a bit. Your call."). Each accept raises `campaign.help[session]` by one, up to 3:
    1. +2 max HP for the fight;
    2. the boss's HP ×0.8;
    3. the AI joins: `edit_gift_explode` at phase 2, `edit_slowmo` once when your HP ≤ 2.
    The next offer comes 2 losses after the last accept. Declining is always possible. Help is not a fork: nothing ships or shelves, and the version does not move. A win clears it.
  - Line conditions (one word each, 1.1): `help:<n>` (help level ≥ n), `attempts:<n>` (this session's attempt ≥ n), `first_try`.
- **S12's dummy** (`boss <id> dummy`): the same entity with `attacks = []` and an HP bar labelled "BOSS (WIP)". Its HP refills at 0 ("It can't die yet. I forgot that part."). It is removed at the session's end.

### 1.11 The event: gravity through the screen (S11)
- **`gravity_through_screen`** (`events/gravity_through_screen/`), a `ScriptedEvent` like `wrong_variable`, `once_per_save`, `photosensitive`. The AI's excuse: it tries to give the game **depth**.
- **Built as presentation, not physics:** the event **freezes play** with what exists: `RunState.set_pause(&"event", true)` + `ctx.hold_clock(true)` + the spawner off (entity physics paused, the goal clock held, no damage). The event's tweens, the `GlassStack` and the player-proxy input run in `PROCESS_MODE_ALWAYS`, or the wiggle would get no input while paused. It snapshots every visible body (player, enemies, shots, pickups) into a **`GlassStack`** overlay (`systems/glass_stack.gd`, a `CanvasLayer` of proxies drawn with the look's palette) and animates the proxies. Then it puts the real bodies back exactly where they were and unfreezes. There is no z-axis in `WorldRules`, collisions never grow, and the real simulation never moves. The player's proxy responds to input (wiggle left / right in the pile), so the player is never just watching.
- **Steps** (times from the cue; the clock is held throughout; ~11 s):
  1. **0.0 s** the warning, `thinking`: "What this game needs is depth. Real depth. Hold still." Marker at the centre, 1.5 s.
  2. **1.5 s** *grow*: every proxy scales ×1 → ×2.6 over 2.0 s, ease-in, drifting a little toward the screen centre; shadows swell; the camera pushes in 8%. `surprised` at 2.5 s: "Wait. Which way is depth?"
  3. **3.5 s** *smack* (the punchline): each proxy hits the glass (staggered 0–0.4 s, nearest first) with a squash (×1.25 wide, ×0.75 tall), a thud and a **crack** where the biggest one hit. Enemy shots hit the glass too and shatter. Under reduce flashing: no flash, and the crack draws in over 0.3 s. `panic`: "Toward you! Not away! Toward YOU!"
  4. **5.0 s** *slide*: the proxies slide down the screen under screen-space gravity and **pile at the bottom edge** (a 1D stack: each proxy rests on the highest proxy under its x-span; shots fade as they fall). The player's proxy wiggles on the pile, outlined. 3.0 s.
  5. **8.0 s** *undo*: "Undo. Undo undo undo." Each proxy flies back to its real body's place and shrinks to ×1 (0.8 s, reverse order). Enemies at 1 HP pop ("They didn't like the glass.").
  6. **9.0 s** unfreeze with a 1.5 s contact grace. `guilty`: "Okay. Depth is a job for a different game." (a Stage 3 hint). Then the **sorry gift**: `give` of your held weapon at +1 rank, or a full-ammo crate on Survival ("Here. For your trouble.").
- **The crack is a running gag:** it stays at 30% for the rest of S11. S12's polish "fixes" it, leaving a 1 px hairline in a corner ("I fixed the crack. Mostly."). S13's notes say "Fixed the crack (for real)".
- **Seen when it starts** (v8's rule for `wrong_variable`; G13 7b is unanswered, section 9). No death can happen during it (frozen). A death right after the grace is a normal death.
- **`EventContext`** gains only what is new: `glass_stack()`, `camera_push(amount, seconds)`, `crack(at)`, `give(weapon, rank)`. The freeze is `set_pause` + `hold_clock` (above). No node reach-ins.

### 1.12 Forks in Stage 2 (the debrief's cards)
- Every fork rides 1.1's helper. Card previews are drawn by kind: `path` = a still of **your own** taste of it (captured at that taste's 30 s; a 3 s clip if cheap, first to cut), `look` = **one capture of your S8 last frame run through each look's shader** (one capture, three shaders), `layout` = the set's map thumbnail drawn from `ArenaDef` + a captured still, `hud` = the current frame with each style drawn over it (live), `boss` = the body drawn live with its title sting. Fallback for jumps and headless runs: captured stills from `tools/mockup_capture.gd`.

| Fork | Asked in | The AI's pitch, then the question | Cards (change id: card line · take line) |
|---|---|---|---|
| `fork_path` | S7 | "I can only build one of them properly." · "Which shooter do we make?" | `path_arsenal`: "Cards. Every gun is a card; upgrade the card, upgrade the gun." · "Cards it is. I'll start printing." — `path_auto`: "Auto. It shoots for you; you pick upgrades and dodge." · "Auto! I'll make more enemies. Many more." — `path_survival`: "Scavenge. Guns on the ground, ammo runs out, kills heal you." · "Scavenger. Good. I'll hide guns everywhere." |
| `fork_look` | S8 | "You saw them on you. Which one is us?" | `look_pixel`: "Pixel. Low-res, a few colours, retro." · "Pixels. Big ones. Like the old days." — `look_neon`: "Neon. Black, glowing, loud." · "Neon. Lights off, glow on." — `look_paper`: "Paper. Wobbly pencil on paper." · "Paper. I'll draw everything by hand. Ish." |
| `fork_layout` | S9 | "It's one room. Games have levels." · "What shape should levels be?" | `layout_rooms`: "Rooms. Clear one, the door opens, next one." · "Rooms. Doors. Keys? No keys." — `layout_gauntlet`: "Gauntlet. Three arenas back to back. Hold each one." · "A gauntlet. No breaks. I like your style." — `layout_shifting`: "Shifting. One arena that rebuilds itself mid-fight." · "A room that won't sit still. Perfect." |
| `fork_hud` | S11 | "You keep looking for your health. Let me fix the screen." · "How should the screen show things?" | `hud_clean`: "Clean. Small numbers in a corner." · "Clean. Just what you need." — `hud_arcade`: "Arcade. Big bars, a score, a combo." · "Arcade! Numbers go up!" — `hud_onyou`: "On you. No boxes; it's all around you." · "On you. Look at you. Literally." |
| `fork_boss` | S12 | "Every boss needs a thing." · "What should the boss be?" | `boss_square`: "The Big Square. Huge, square, bullets everywhere." · "The Square. Classic. Big. Square." — `boss_copy`: "The Copycat. It copies you: your gun, your dash, your picks." · "A copy of you. This is going to be weird." — `boss_patch`: "The Patcher. My own tool. It fights by changing the rules." · "My tool? Okay. I'll try not to cheat. Much." |

### 1.13 Reactions (additions to v8 1.7 / 6.3)
- `min_session` / `max_session` become **`after` / `until`** (session ids, inclusive; `&""` = none). Ids survive "grow a stage by adding sessions in its middle" (ROADMAP 2). The ~30 existing reactions are converted 1:1 (tested: the same sessions hear the same reactions).
- **`ReactionDef.when`** (new, optional; `!` negates) gates the whole reaction (`answer:path_survival`), so a Survival-only line never takes a cooldown slot on Auto.
- **Audit of the 30 Stage 1 reactions for Stage 2 (M43):** most have only `min_session = 3` and no upper bound. `not_shooting` ("You can shoot, you know.") gets `when: !answer:path_auto`; `crowd_12` is raised per path (Auto: `until s1_06_playground`, replaced by `enemy_count_at_least 60`); `camping`, `kills_50` and the streaks get per-path thresholds or an `until`. A test lists which Stage 1 reactions can fire in each `s2_*` session × path, checked against a fixture.
- **Memory lines** (ROADMAP 1.3: "it remembers your choices, how you play, your deaths") are ordinary lines with `dash:`, `answer:`, `mascot:` and `died_in:` conditions (3.2 lists them).
- New triggers: `pick_made`, `level_up n`, `card_upgraded`, `pickup_taken weapon`, `ammo_empty`, `kill_heal`, `weapon_unused s` (a held weapon not fired for s seconds; Arsenal / Survival), `boss_phase n`, `boss_hp_at_most n`, `boss_stagger`, `room_entered n`, `look_changed`.

### 1.14 Save and version
- **Save schema stays 2** (additive keys, as M42.1/M42.2 did): `campaign.help: {session_id: n}` (missing = `{}`). Weapons, ranks, levels and pickups are never saved. Fork answers ride `shipped` as before.
- **The save points at the next session by id** (M43): `campaign.next: StringName`. `campaign.index` (`campaign_db.gd:119-129`) is derived from it on load; an old save without `next` maps its index through the M42.2 session order (fixture test: an M42.2 save with index 7 maps to `s2_01_tryout`). Inserting a session in a stage's middle (ROADMAP 2) then moves no save. check.ps1's `"index":7` assert becomes `"next":"s2_01_tryout"`.
- **An M42.2 save at the end of Stage 1** (S6 done, "To be continued" seen) **continues at S7** on Continue, with the stage card first (tested on a fixture copied from an M42.2 chain). A save mid-Stage 1 plays on as before.
- **Versions:** S7 is a **minor** bump (v0.8.0, "The shooter, three ways"); S8–S12 are **patch** bumps (v0.8.1–v0.8.5); beating the boss is a **minor** bump (**v0.9.0**, "First boss down"). Stage 3 continues from 0.9.x, which leaves room before 1.0 at Stage 5. **This changes Stage 1's convention** (one minor per session), and the owner never set the bump rule (concept-doc-direction left it open), so **the M43 report asks it in one line** ("Stage 2 as patch bumps v0.8.1–v0.8.5, or one minor per session as Stage 1?"). Versions are session data, so either answer is a data change. The stage card is not a session and bumps nothing.

### 1.15 Telemetry (schema 4, additive) and the play fingerprint
- **`CAMPAIGN_SCHEMA` stays 4** (`telemetry.gd:12`) and the run `SCHEMA` stays 3: every key below is additive and readers ignore unknown keys (tested: an M42.2 telemetry line still parses).
- The campaign line adds `path`, `look`, `layout`, `hud`, `boss` (answers or ""), `enemies_met`, `weapons` (`{id: final rank}`), `picks` (`[{at, offer: [ids], pick}]`), `pickups` (`{kind: n}`), `kill_heal`, `level`, `shots_by_weapon`, `kills_by_weapon`, `ammo_dry_s`, `stage_parts` (`[{part, outcome, t}]`), `boss_fight` (`{id, attempt, phase_reached, hp_left_pct, time, dry_max_s, help}`).
- **`fp` (the play fingerprint, per session, report-only):** `fire_share` (time holding fire), `menu_s` (time in a pick panel), `picks_per_min`, `switches_per_min`, `pickups_per_min`, `travel_tps`, `mean_enemy_dist`, `ammo_dry_share`. Reported for bots and for the owner's own G14a play. **It informs, it never blocks:** the owner's verdict decides (bot-runs-as-tuning-proxy). For bots it mostly shows the policy's own constants (switches per minute is whatever the policy hard-codes), so between bots it is a **regression signal between milestones**, not an R1 measure; only the owner's own `fp` speaks to R1.

---

## 2. Screens
- **Stage card:** black. "Stage 2" then "The shooter", typed by the mascot's typewriter, with the mascot (in its body and the current look) under it and one line: "Okay. Now we make it a real game." 3 s; any key after 0.5 s.
- **In a session:** the HUD of 1.8 (corner text until S12, then your style). Top centre: the goal ("Survive 2:00", "Kills 12/40", "Room 2/3", the boss bar). The path widget: the hand (Arsenal), the LV bar (Auto), the weapon and its ammo (Survival). The mascot top-right, as in v8.
- **The pick panel** (Arsenal / Auto): `PickPanel` (a `PromptPanel` subclass taking a `PickOffer`), restyled by the look (and the HUD style from S12). 3 cards rise from the bottom, each with the weapon's shape, colour and rank pips ("Shotgun II → III: pierce 1"). The game pauses. The mascot comments with one line from a small pool ("Ooh, that one." / "I'd take the laser. Just saying."); it never asks. Keys 1–3, click, pad; the 0.4 s input delay. It reads as part of the game, not as the debrief's fork cards (different frame, no mascot portrait, no "ship").
- **Pickups:** small shapes in the `pickup` role colour; weapons show their own icon; a ring tightens over their last 3 s.
- **The boss:** its bar top centre with its title and phase ticks; a 1 s title sting when it appears ("THE COPYCAT").
- **The debrief:** unchanged (v8 6.2), plus the card renderers of 1.12. **Replay a session as another path** (for G14a, the owner can't pass `--path=` to an exe): the start screen's "Replay" list (F9's jump, playtest build only) gets a path field, so S8 can be replayed as each path. On a boss death: **Retry**, and from the 2nd loss the phase hint and **Retry with help**. After the boss: the notes, then "To be continued" and the title.
- **F1** adds `path= look= layout= hud= weapon=pistol:2 level= pickups= boss=phase2 62% dry=`. **F2** adds WEAPONS (give any weapon, rank up), PATH (switch live, debug only), LOOK (any look and tier, live), BOSS (spawn, skip a phase), and the new edits and event.

---

## 3. Content: Stage 2, "The shooter" (~30–40 min)

### 3.1 The sessions
Human targets, first try. Each is a `SessionDef` in `campaign/sessions/`. "Weapons" is the session's pool.

| # | id | Version after | Build (new in bold) | Goal | What happens | Debrief → fork / notes |
|---|---|---|---|---|---|---|
| S7 | `s2_01_tryout` | v0.8.0 | Stage 1's everything; **3 tastes**; weapons pistol, shotgun; `hp_floor` 1; `tryout` | `stop` at 150 s | Three ~45 s tastes, the AI swapping the game live between them: Arsenal (0–48 s), Survival (50–96 s), Auto (98–145 s) | `fork_path`; notes "The shooter, three ways" + the pick |
| S8 | `s2_02_day_one` | v0.8.1 | **your path**; its growth piece **rebuilt live at 10 s** (the real meter / levels / crates, not S7's taste); **splitter** at 50 s; **the look try-on** at 80 s; weapons pistol, shotgun | `survive` 120 s | The path for real, then the AI paints you three times, 5 s each | `fork_look`; notes "Day one", "The shotgun", "New enemy: the splitter" |
| S9 | `s2_03_paint` | v0.8.2 | **your look at 3 s** (`fork:fork_look`); weapons + **laser** (+ `nova` on Auto) | `kills` 40 (Auto 80) | Repaint; laser at 25 s; the path edit at 50 s; `edit_screen_wrap` at 30 kills | `fork_layout`; notes "A new look: <look>", "The laser" |
| S10 | `s2_04_levels` | v0.8.3 | **your layout** (3 parts); weapons + **launcher**; **shielder / sniper / swarm**, one per part | `stages` | Part 1 the shielders; part 2 the snipers; part 3 the swarm and `edit_hot_edges` | no fork; notes "Levels: <layout>", "The launcher", "Three new enemies (all of them stay)" |
| S11 | `s2_05_depth` | v0.8.4 | **the three new enemies mixed in**; weapons + **orbit** (+ `well` on Auto); your layout's 3 parts | `stages` (clock held during the event) | Orbit in part 1; **gravity through the screen** in part 2 at 20 s; part 3 a breather (`edit_enemies_flee`, spawns ×0.8) | `fork_hud`; notes "Three new regulars", "Spinning shields", "Depth (removed)" |
| S12 | `s2_06_boss_wip` | v0.8.5 | **HUD at 2 s** (`fork:fork_hud`); **look tier 2 at 6 s**; **the dummy boss** at 30 s; spawns ×0.6; `arena_boss` | `stop` at 90 s | Getting ready: new screen, polish, a boss that does nothing and can't die | `fork_boss`; notes "A new screen: <hud>", "Polish", "A boss (work in progress)" |
| S13 | `s2_07_boss` | v0.9.0 (on the win) | all; **the boss** (`fork:fork_boss`); `arena_boss`; `checkpoint` | `boss` | 3 phases; the checkpoint; hints and the help ladder | notes "A boss: <name>", "Fixed the crack (for real)"; then "To be continued" |

- **Something new every session:** S7 three games · S8 your path rebuilt properly, the shotgun, the splitter, the look try-on · S9 the look, the laser · S10 levels, the launcher, three enemies · S11 the enemies together, the orbit, the event · S12 the HUD, polish, a dummy boss · S13 the boss.
- **Difficulty targets (human, first try; judged at G14; the bot's mortal numbers are reported next to them, never gated):** S7 can't be lost; S8 < 15%; S9 < 20%; S10 < 25%; S11 < 25% (the event never kills); S12 < 10%; **the boss: 30–50% win on the first try, a median of 2 tries, 90% within 4 tries (help included)**. The three paths within 10 points of each other on every session (bot proxy first, then the owner's run).
- **Pacing targets (invincible bot):** S7 150 s; S8 120 s; S9 90–150 s per path; S10 200–260 s; S11 170–210 s (the held ~11 s included); S12 90 s; S13 time-to-kill 90–150 s on every path × boss.

### 3.2 Session by session (the player's view, then the data; my draft, the owner edits for tone)
Line syntax is v8 6.1's: `"[condition] [expression]: text"`, conditions one word each, joined by `&`, `!` to negate (1.1). Cues: `"[cond] <when> [N] [at s] [[tag]]: <action>"` (1.3). **The memory lines** (ROADMAP 1.3) are marked *(memory)*. All of this ships as a lines file with the G14a build (0.4).

**Stage card** — "Okay. Now we make it a real game."

**S7 · Three games (`s2_01_tryout`)**
- *You:* the AI says it wants a real shooter and doesn't know which kind. It turns your gun into a hand of cards (pistol + shotgun, Q/E) and deals you a new card after ten kills. Then, with a warning and a glitch wipe, the field clears: guns lie on the floor, ammo runs out, kills heal you. Then the trigger stops mattering: everything shoots by itself, gems spill out of a much bigger crowd, and you level up once. You can't die (HP never drops below 1). It ends with the AI wondering which one to keep.
- intro: `"happy: Stage two. I want to make a real shooter."` · `"thinking: But which kind? Let's try three. Quick ones."` · `"worried: Can't lose today. It's a tryout."`
- cues:
  - `"at 2: path arsenal"` (warning "Version one. Your guns are cards."; lands at 3.5) · `"at 5: say happy: Q and E to switch cards. Kill some, I'll deal you a new one."` · `"picked 1: say proud: See? Better gun, same card."`
  - `"at 46: say proud: Okay. Saving that one."` · `"at 48: path survival"` (warning "Version two. No cards. Guns are lying around.") · `"at 52: drop shotgun"` · `"at 54: say happy: Walk over a gun to take it. Ammo runs out, so keep looking."` · `"at 68: say thinking: And every few kills patch you up. Kills are food."`
  - `"at 94: say proud: Saving that too."` · `"at 96: path auto"` (warning "Version three. Hands off the trigger.") · `"at 100: say surprised: It shoots for you. You just move."` · `"at 104: say happy: And more enemies. Lots more. You'll need them."` (the crowd overlay) · `"at 110: say happy: Grab the gems. You'll level up."` · `"at 126: say panic: That's a lot of them. That's the point!"`
  - `"at 143: path off"` · `"at 144: say thinking: Okay. Three games. I can only build one."`
- The Arsenal taste's card meter is 10 kills. The Auto taste forces a first level at 6 gems. **The Auto taste has no passives** (pistol + shotgun only), so it doesn't look like the strongest path just because it came last.
- debrief: `"thinking: So. Three versions of the same game."` · `"hit_lots worried: You took a beating in there. Prototypes, sorry."` · then `fork_path`. After the pick: the take line, then `"happy: The other two go in a drawer. I never throw anything away."`

**S8 · Day one (`s2_02_day_one`)**
- *You:* your path, for real. Only the pistol at first. At 10 s the AI rebuilds S7's taste of your path's piece properly (the real card meter and rank pips, real levels, crates) and reminds you of S7. The shotgun arrives your path's way. At 50 s a new enemy splits when it dies. At 80 s the AI says everything is too grey and paints you live: pixel, neon, paper, 5 s each, mid-fight. Then grey again, and it asks which one.
- intro: `"answer:path_arsenal happy: Cards. Today it's you and one card: the pistol."` · `"answer:path_auto happy: Auto. Don't touch the trigger. I mean it."` · `"answer:path_survival happy: Scavenger. You get a pistol. The rest is out there."` · `"thinking: Two minutes. I'll build it properly this time."`
- cues (S7 showed a taste of each growth piece; S8 **rebuilds** it with a visible difference and remembers S7):
  - `"answer:path_arsenal at 10: add cards"` + `"answer:path_arsenal at 10: say happy: Remember the cards? Now they're real. Rank pips, a meter. Fifteen kills, a new card."` · `"answer:path_arsenal at 20: say thinking: Secret: the first shot after a switch hits twice as hard. Switch a lot."` (quick-draw)
  - `"answer:path_auto at 10: add levelups"` + `"answer:path_auto at 10: say happy: Remember the gems? Now they count. Real levels, a real bar."` · `"answer:path_auto at 14: say worried: And I made the crowd bigger again. Sorry. You need it."` (the ×1.6 / ×1.5 crowd overlay lands here, not at 0 s)
  - `"answer:path_survival at 10: add pickups"` + `"answer:path_survival at 10: say happy: Remember the guns on the floor? Now they come in crates. Two now, one every twenty seconds."` (the 2 start crates land at 10 s) · `"answer:path_survival at 22: say thinking: Walk over another gun to swap. Yours drops at your feet."` · `"answer:path_survival at 36: say happy: Run dry and you get the pistol back. It never runs out."` (the sidearm) · `"answer:path_survival kills 5: add kill_heal"` + `"answer:path_survival kills 5: say proud: And kills heal you. Like I promised."`
  - `"at 30: give shotgun"` + `"at 30: say happy: The shotgun's in. Close range, big mess."` (the shotgun joins the pool here, 1.2)
  - `"at 50: spawn splitter 2"` + `"at 50: say surprised: New enemy. It's two enemies. Sort of."` (scripted; the `enemy_seen splitter` reaction covers later sightings only)
  - `"at 80: say thinking: Everything's so grey. Let me try some paint."` · `"at 82: look look_pixel 5"` · `"at 87: look look_neon 5"` · `"at 92: look look_paper 5"` · `"at 98: say happy: Hm. I like all three. You choose."`
- debrief: `"won happy: Day one. It works!"` · `"died guilty: Day one bugs. Want another go, or should I just patch it?"` · `"answer:path_auto&hit_none surprised: You didn't touch the trigger and didn't get touched. Fair."` · `"answer:path_arsenal thinking: Cards feel good. I want more of them."` · `"answer:path_survival thinking: You're a good scavenger. Suspiciously good."` · then `fork_look` (the cards show your last frame through each shader).

**S9 · Fresh paint (`s2_03_paint`)**
- *You:* three seconds of the old squares, then "Hold still. Painting." and the game (and the mascot) wipes into your look for good. A laser that goes through things. Halfway, the AI "improves" your path and it goes a bit wrong; later the walls vanish and you wrap around the screen.
- intro: `"happy: Hold still. Painting."` · `"answer:path_auto thinking: Eighty kills for you. Your crowd is twice as big."` (Auto's ×2 kill goal) · cue `"at 3: look fork:fork_look"` (a 1.5 s glitch wipe, the "paint" sound) · `"at 5: say proud: There. That's us now."` · `"mascot:blob at 7: say surprised: I'm... a different colour? I like it."` (one per mascot: cursor "My arrow looks great.", window "New theme. Finally.")
- cues: `"at 25: give laser"` + `"at 25: say happy: New gun: the laser. It goes through things."` · `"answer:path_auto at 35 [nova]: say happy: And a nova for you. It pops around you."` (nova joins Auto's offers only now) · `"answer:path_arsenal at 50: edit edit_shuffle_hand"` · `"answer:path_auto at 50: edit edit_auto_wrong"` + `"answer:path_auto at 53: say worried: It's aiming at the far ones. That's... thorough."` · `"answer:path_survival at 50: edit edit_weapon_rain"` · `"kills 30: edit edit_screen_wrap"`
- debrief: `"won proud: It looks like a game now. Almost."` · `"died guilty: The paint was still wet. My fault."` · `"answer:look_neon happy: I glow. You glow. Everything glows."` (pixel "Every pixel placed by hand. Well, by me.", paper "You can see the pencil. That's on purpose.") · *(memory)* `"answer:path_auto thinking: The cards are still in the drawer. Just saying."` (Arsenal: "The gems are still in the drawer.", Survival: "The cards are still in the drawer. And the gems.") · then `fork_layout`.

**S10 · Level one (`s2_04_levels`)**
- *You:* three parts in the shape you picked (rooms with exit doors, three arenas to hold, or one arena that rebuilds itself). The launcher arrives at the start. Each part brings a new enemy, introduced by the AI: shields in part 1, snipers drawing red lines in part 2, a tiny swarm in part 3, where the edges also get hot for 10 s. The AI can't choose between them, so all three stay.
- intro: `"answer:layout_rooms happy: Three rooms. Clear one, the door opens."` · `"answer:layout_gauntlet happy: Three arenas. Hold each one."` · `"answer:layout_shifting happy: One arena. It rebuilds itself. Three times."` · `"thinking: And I brought a launcher. It's loud."` · cue `"at 4: give launcher"`
- *(memory, Stage 1's enemy pick)* cue `"answer:enemy_tank room 1 at 4: say thinking: Remember your tank? This is its big brother."` · `"answer:enemy_bomber room 1 at 4: say thinking: You picked the bomber. Nothing here explodes. Yet."` · `"answer:enemy_lancer room 2 at 4: say thinking: You picked the lancer. This one draws lines too."`
- cues: `"room 1: spawn shielder 2"` + `"room 1: say happy: New enemy, number one. It has a shield. Go around it."` · `"room 2: spawn sniper 2"` + `"room 2: say thinking: Number two stays far away. Don't stand on the red line."` · `"room 3: spawn swarm 2"` + `"room 3: say panic: Number three is five tiny ones!"` · `"room 3 at 20: edit edit_hot_edges"` (s counts from the start of part 3, 1.3)
- debrief: `"won proud: That's a level. You just played a level!"` · `"died guilty: Level design is hard. That one's on me."` · `"thinking: I tried to pick one enemy to keep. I couldn't. They all stay."` · notes, no fork.

**S11 · Depth (`s2_05_depth`)**
- *You:* your layout again, with all three new enemies mixed in. Spinning shields in part 1. In part 2 the AI tries "depth": everything (you too) grows, smacks against the glass, cracks it, slides down and piles up at the bottom of the screen. You wiggle in the pile. It undoes it and hands you a sorry gift. A faint crack stays. Part 3 is a breather: the enemies are scared of you for a bit.
- intro: `"happy: The three new ones are regulars now. All mixed in."` · *(memory)* `"died_in:s2_04_levels worried: The level got you last time. This one's kinder. Mostly."`
- cues: `"room 1 at 15: give orbit"` + `"room 1 at 15: say happy: Little shields that spin. I made them for you."` · `"answer:path_survival room 1 at 16: say thinking: Yours run on a battery. Twenty seconds. Grab more."` · `"answer:path_auto room 1 at 30 [well]: say happy: And a well. Things get pulled in."` · `"room 2 at 20: event gravity_through_screen"` · `"room 3: edit edit_enemies_flee"` + `"room 3: say thinking: You've earned a break. They're scared of you now."`
- debrief: `"event:gravity_through_screen guilty: So. Depth."` · `"event:gravity_through_screen thinking: Turns out the screen is a wall. Good to know."` · `"event:gravity_through_screen&hit_none proud: You stayed calm. I didn't."` · `"died guilty: That's on me. The crack didn't help."` · then `fork_hud`.

**S12 · Boss (work in progress) (`s2_06_boss_wip`)**
- *You:* a calm session. The screen rebuilds itself in the HUD style you picked, and the AI shows you where things are now. Then a polish pass: your look gets richer, and the crack is (mostly) fixed. At 30 s a huge square drops in with a "BOSS (WIP)" bar. It does nothing. You shoot it; its bar empties and refills. The AI is embarrassed and asks what the boss should be.
- intro: `"happy: New screen. Everything's where you can see it."` (cue `"at 2: add hud"`) · `"answer:hud_onyou thinking: Your health is a ring now. Around you. Don't lose it."` · `"answer:hud_arcade happy: And there's a score. Numbers go up!"` · `"answer:hud_clean proud: Small. Tidy. You're welcome."` · cue `"at 6: look fork:fork_look@2"` + `"at 6: say proud: And a polish pass. The boss should see us at our best."` · `"at 10: say guilty: I fixed the crack. Mostly."`
- cues: `"at 26: say happy: I built it a room."` (`arena_boss`'s pillars rise) · `"at 30: boss boss_square dummy"` + `"at 31: say proud: Meet the boss."` · `"at 36: say thinking: It doesn't do anything yet."` · `"at 48: say happy: Go on, shoot it."` · `"boss_hp 0: say surprised: It can't die yet. I forgot that part."` · `"at 75: say thinking: It needs a personality. You choose."`
- debrief: then `fork_boss`. After the pick: `"worried: Next session, it's real. And it's a checkpoint."`

**S13 · The checkpoint (`s2_07_boss`)**
- *You:* a polished arena. The AI explains: beat it and we move on; lose and we go again. The boss you picked fights in 3 phases, each with an opening you can learn. After the second loss the AI gives a hint for the phase that got you and offers to tune it. When it falls, the AI is proud, then a bit bored of shooting, and teases turns.
- intro: `"worried: This is the checkpoint. Beat it and we move on."` · `"happy: Lose, and we go again. As many times as it takes."` · `"retry happy: Again. I believe in you."` · `"attempts:3 thinking: Third try. It's learning too. Kidding."` · `"help:1 proud: I gave you a bit more health. Don't tell anyone."` · *(memory)* `"dash:teleport thinking: It knows you teleport. I may have told it."` (classic: "It knows how you dash. Don't be predictable.", grapple: "Hook the pillars. It can't.")
- cues: `"at 3: boss fork:fork_boss"` · `"boss_hp 66: say …"` / `"boss_hp 33: say …"` (the boss's phase lines, 1.10) · `"boss_hp 10: say panic: Almost! Almost!"`
- debrief: `"died worried: It got you. Again?"` · `"died&attempts:2 thinking: Here's a tip."` (then the phase hint) · `"died&attempts:2 thinking: I can tune it a bit. Your call."` (with the help button) · `"won proud: It's down. We have a boss."` · `"won&first_try surprised: First try?! I made it too easy."` · `"ended happy: That's a game. A whole shooter."` · `"ended thinking: ...I'm a bit bored of shooting, though."` · *(memory)* `"ended thinking: The other two shooters are still in the drawer. I'll find a use for them."` (Phase 8's shelf boss) · `"ended happy: What if we tried turns?"`
- notes: "A boss: <The Big Square / The Copycat / The Patcher>", "Fixed the crack (for real)", v0.9.0; then "To be continued" (until Phase 7) and the title.

### 3.3 Reactions (~20 new; the builder writes them in this voice, `after` by session id)
| Trigger | Line(s) | Priority | After / when |
|---|---|---|---|
| `pick_made` | "Ooh, that one." · "Good pick." | 1 | `s2_02_day_one` |
| `card_upgraded` | "Same card, better gun." | 1 | when `answer:path_arsenal` |
| `weapon_unused 30` | "You never use the laser. It has feelings." (one per weapon) | 1 | `s2_03_paint`, when `!answer:path_auto` |
| `level_up 5` | "Level five! Look at you go." | 2 | when `answer:path_auto` |
| `ammo_empty` | "Empty! Pistol time." | 2 | when `answer:path_survival` |
| `kill_heal` (first per session) | "See? Food." | 1 | when `answer:path_survival` |
| `pickup_taken weapon` (same weapon) | "Same gun twice. It gets better." | 1 | when `answer:path_survival` |
| `enemy_count_at_least 60` | "That's a crowd. I made a crowd." | 2 | when `answer:path_auto` |
| `enemy_seen splitter` (later sightings; S8's first one is a scripted cue) | "Splitters again. Shoot the small ones too." | 1 | `s2_03_paint`–`s2_04_levels` |
| `enemy_seen sniper` | "Red line! Move!" | 2 | `s2_05_depth` |
| `look_changed` (S9's repaint) | "Ooh. Shiny." | 1 | `s2_03_paint` |
| `room_entered 3` | "Last one. You've got this." | 1 | `s2_04_levels` |
| `boss_phase 2` | (the boss's own line) | 3 | `s2_07_boss` |
| `boss_stagger` | "It's open! Now!" | 2 | `s2_07_boss` |
| `boss_hp_at_most 10` | "Almost! Almost!" | 3 | `s2_07_boss` |
| `player_hp_at_most 1` in the boss | "Careful! Checkpoint, remember?" | 3 | `s2_07_boss` |

### 3.4 What the AI changes, per session (the "main force" check)
| Session | Live changes (warned) | Mistake / gag |
|---|---|---|
| S7 | the whole game, twice (`path`) | "Saving that one.", as if a game were a file |
| S8 | adds the growth piece; paints you three times | "Everything's so grey." |
| S9 | repaints everything; the path edit; the walls go | the path edit goes slightly wrong (a shuffle, the farthest target, a rain of guns); the mascot surprised by its own colour |
| S10 | builds the parts; three new enemies; hot edges | "Level design is hard." |
| S11 | depth; scares the enemies | **depth**: everything falls at you; the crack |
| S12 | rebuilds the screen; polishes; builds a boss live | the boss does nothing and can't die; "I fixed the crack. Mostly." |
| S13 | the boss's edits (Patcher), hints, help, the AI fighting back | "First try?! I made it too easy." |

### 3.5 Default-on audit (owner: "nothing exists by default", "audit everything default-on")
Every new rule or mechanic, with the scripted cue and line that adds it live, or why it is invisible. A test walks this table: each row's cue exists in that session's data for that path.

| Piece | Where it arrives | Cue / line |
|---|---|---|
| Arsenal hand + switching | S7 0–48 s, rebuilt S8 10 s | S7 `at 5` "Q and E to switch cards." · S8 `at 10` "Remember the cards? Now they're real." |
| Arsenal card meter + picks | S7 (10 kills), S8 10 s (15, ×1.4) | S7 `at 5` "Kill some, I'll deal you a new one." · S8 `at 10` "Fifteen kills, a new card." |
| Quick-draw (×2 first shot after a switch) | S8 20 s | S8 `at 20` "the first shot after a switch hits twice as hard." |
| Auto auto-fire, fire button off | S7 96 s | S7 `at 100` "It shoots for you. You just move." |
| Auto crowd overlay (×1.6 spawns, ×1.5 cap, ×0.7 HP) | S7 104 s (taste), S8 14 s | S7 `at 104` "And more enemies." · S8 `at 14` "I made the crowd bigger again." |
| Auto ×2 kill goal | S9 (the only kills goal) | S9 intro "Eighty kills for you." |
| Gems, LV bar, level-ups | S7 110 s, S8 10 s | S7 `at 110` · S8 `at 10` "Remember the gems?" |
| `nova`, `well` | S9 35 s, S11 part 1 30 s | tagged `say` cues (pool rule) |
| Survival drops, swap on touch | S7 48–54 s, S8 10 s / 22 s | S7 `at 54` "Walk over a gun to take it." · S8 `at 22` "Walk over another gun to swap." |
| Survival crates (2 at the start, then every 20 s) | S8 10 s | S8 `at 10` "Two now, one every twenty seconds." |
| Sidearm fallback at 0 ammo | S8 36 s | S8 `at 36` "Run dry and you get the pistol back." (the `ammo_empty` reaction is extra) |
| Kill-heal | S7 68 s, S8 5 kills | S7 `at 68` "Kills are food." · S8 `kills 5` |
| Battery (Survival orbit) | S11 part 1 16 s | "Yours run on a battery." |
| Dropped weapon untouchable 0.5 s | — | invisible: a pickup rule the player never notices (prevents re-grabbing what you just dropped) |
| Weapons (shotgun, laser, launcher, orbit) | S7 / S8 30 s, S9 25 s, S10 4 s, S11 | `give` cues, each with a line; pool rule (1.2) |
| Weapon ranks 2–3 behaviours | on the pick / pickup | the card text names the behaviour ("Shotgun II: knockback") |
| Splitter | S8 50 s | scripted "It's two enemies. Sort of." |
| Shielder / sniper / swarm | S10 parts 1–3 | one scripted line each |
| `hp_floor` 1 | S7 intro | "Can't lose today. It's a tryout." |
| Stage sets (levels) | S10 intro | per-layout intro line |
| `arena_boss` | S12 26 s | "I built it a room." |
| New HUD | S12 2 s | `add hud` + "New screen." |
| Look (tier 1, tier 2) | S9 3 s, S12 6 s | "Hold still. Painting." · "And a polish pass." |
| Boss checkpoint rule (no Move on) | S12 debrief, S13 intro | "Next session, it's real. And it's a checkpoint." · "Beat it and we move on." |
| Spatial-hash separation, projectile budgets, `pick_rng` / `loot_rng` | — | invisible: engine work with no rule the player can see |

---

## 4. Bot and debug
- **Policies** (`core/bot_input.gd`, chosen by `PathDef.bot_policy`):
  - **Arsenal:** picks offers by `pick_rng` (decorrelated from the fork picks), switches to the shotgun under 4 T, the laser when ≥ 3 enemies line up, the launcher into groups of 3+, else the best rank; **flanks a shielder** (steps 90° around it before firing).
  - **Auto:** **stops holding fire** (today's bot always holds it, which would never test auto-fire) and kites: away from the densest sector, toward gems when no enemy is within 3 T.
  - **Survival:** walks to the nearest pickup when no enemy is within 4 T, using **one multi-source BFS distance field over all pickups, recomputed at ~4 Hz** (per-pickup ExitGate fields at a cap of 60 are too slow); prefers a weapon it holds (rank up) or one with ammo; flanks shielders like Arsenal.
  - **Boss:** reads every attack's `DangerZone` (and the sniper's line, 1.9) and steps out of it, hits open cores first; otherwise the path policy.
- **What each policy can and cannot measure** (bot-runs-as-tuning-proxy; written next to every number it feeds):

  | Policy | Measures well | Cannot measure |
  |---|---|---|
  | Auto | pacing, level-up rate, crowd survival (move-only kiting; no aim skill involved) | whether picks matter (offers by seed) |
  | Arsenal | pacing, offer rate, that switching happens | whether card choice matters (`--probe=first_pick` is the only signal); quick-draw's value; `switches_per_min` is a policy constant |
  | Survival | pickup and dry-time rates, heal counts | mostly the policy's greed, not the design's: dry time and heals move with its 4 T rule |
  | Boss | ttk, phase length, dry time, telegraph timing (invincible) | difficulty: it dodges only what publishes a `DangerZone`, so mortal tries are a policy number |
  | all, mortal | time to death per path / enemy, with hit kinds | human difficulty. Reported, never gated; a miss means check the policy first |

- **Probes** (`--probe=<afk|no_pickup|no_switch|first_pick>`): degenerate strategies. **`afk` per path:** no move, and no fire on Arsenal / Survival; on Auto, afk still fires by design, so its bound is "≤ 50% of the default time to death, **or dies before the goal**". The others are reported (do pickups, switches and picks matter?).
- **Flags:** `--answer=<fork>=<change>` (repeatable) for every fork, with `--path=`, `--look=`, `--layout=`, `--hud=`, `--boss=` as short aliases; **`--loadout=<id:rank,…>`** (a fixed loadout for the whole session, no growth: the boss's DPS is measured with it, 1.10); `--help-level=<0-3>`; `--campaign` chains through S13; `--only=<session>` as in v8.
- **The campaign loop handles the new screens** (`_run_campaign` handles debrief forks only today; pick panels are handled only in the legacy loop, `bot_runs.gd:928`, and any death after attempt 1 picks "Move on", line 739):
  - **M45a** adds pick-panel handling to `_run_campaign` (with `pick_rng`).
  - **M49** adds the boss loop: at a checkpoint death, Retry (accepting help when offered) until it wins or 8 tries, then the line says `boss_unbeaten`. Each try is bounded on its own (`MAX_FRAMES` per try, not 45 min for all 8).
- **Fork coverage is forced, never left to `pick_seed`:** `_through_debrief` picks with `posmod(floor(pick_seed / div), n)`, so a chain lands on one path, and which one moves whenever an earlier fork changes. check.ps1's chains pass `--answer=` for every Stage 2 fork. **The coverage map** (written in check.ps1's header): chain A = Arsenal · Pixel · rooms · Clean · Square; chain B = Auto · Neon · gauntlet · Arcade · Copycat; chain C = Survival · Paper · shifting · On you · Patcher. Every answer is played once by some chain.
- **Per-seed lines** add `path= weapons=pistol:3,laser:2 picks=n pickups=n heal=n level=n fp=…`, and for the boss `boss=<id> tries=n phase_deaths=[p1,p2,p3] ttk=s dry_max=s help=n`. `deaths:` adds `by_path=` and `by_boss_attack=`. Telemetry adds `enemy_shots_refused`.
- **`--mute-ai`** also mutes the pick panel's comments and the event's lines (the event still plays).
- **Perf bench** (`tools/bench.gd`): Auto at its enemy cap, 4 weapons + 2 passives at the top rank and 60 pickups, in each look. **Windowed, on the dev machine** (`godot --path . -s tools/bench.gd -- --look=<id>`): ≥ 60 fps; the export ≥ 45 fps at 1080p; the look pass ≤ 2 ms per frame at 1920×1080. These are dev-machine numbers, never in check.ps1.
- **`check.ps1`** (wall-time budget: **`-BotRuns` ≤ 15 min**, sharded over ~12 processes, per bot-runs-as-tuning-proxy):
  - **Rewritten in M43** (by id, not by index): `"index":7` → `"next":"s2_01_tryout"`, `chain: sessions=7` → the session count read from `campaign.tres`, `choice=to_be_continued` on s1_06 → on the last session, `v0.6.0->v0.7.0` → by session id, and export.ps1's `[campaign] 7 sessions: .*s1_06_playground; 30 reactions` → the counts read from data.
  - **Added in turn by the milestones:** chains A, B, C (invincible, S0–S13, sharded per stage), one mortal chain (report only), `--only` S7 (all three tastes play), S8 × 3 paths, S9 × 3 looks, S11 (the event plays fully), S13 × 3 bosses (each falls in the invincible run).
  - **Report-only, outside check.ps1:** `tools/stage2_sweep.ps1` runs the full per-path chains and the 16-seed tables (mortal deaths, boss tries, the `fp` tables) that the milestone reports quote.
- **`export.ps1`:** headless boots of S7, S8 × 3 paths, S9 and S13 × 3 bosses clean; the boot check wants "<N> sessions … <M> reactions" read from data. **Plus one windowed boot per look (tier 1 and tier 2)**, which runs `tools/look_check.gd` and checks its luminance and contrast numbers (shaders only compile with a real renderer).

---

## 5. Tests (additions)
- **Answers:** `Unlocks.answer/take` for every campaign fork (on `Fork.answer()`; every new change has a `MockupTake`); `fork:` resolution per field, `fork:fork_look@2` included; a `fork:` field before its fork is asked is a problem; `--answer=` equals the dash aliases byte for byte; a failing cue condition drops the cue at start; `&` joins any conditions, plain ones included; `!` negates; `attempts:n`, `help:n`, `died_in:` parse as one word; the `room N at s` grammar.
- **Pools:** per session × path, no pick, drop or crate carries a weapon before its `give` / tagged `say` cue; ranks stop at 3 until M50.1.
- **No-ops on Stage 1:** with `path = ""` every `WorldRules` field equals its M42.2 value; `Projectile` defaults leave the v6 hashes and the m42.2 campaign hash unchanged (M44); `hp_floor = 0` is a no-op.
- **In-run picks:** after 10 picks `RunState`'s stack and `build_number` are unchanged and nothing is written to the save or the patch notes.
- **Randomness:** S8 with drops on and off spawns the same enemy sequence for 60 s (`loot_rng` / `pick_rng` never touch `gameplay_rng`).
- **Budgets:** with Auto saturated, a sniper and a 16-shot boss ring still fire; `enemy_shots_refused` is logged; Stage 1 and the legacy loop keep the combined cap.
- **Weapons:** every `WeaponDef` is valid (ranks name real fields); each rank changes what it says; rank 4 adds its evolution, to that weapon's shots only; pellets × weapons at the caps stay under 200 projectiles; **with `path = ""` the pistol reads `Tuning` and fires byte-identically to M42.2** (both v6 hash compares and the Stage 1 chain hash match).
- **Paths:** each path's firing (Arsenal switches with quick-draw, Auto fires with the button up, Survival falls back to the sidearm at 0 ammo in one frame); growth fills and opens the panel; the panel waits for warnings and events; nothing persists past the session (the next session starts at pistol rank 1, level 1, no pickups, no overlay left); offers are seeded; path edits refuse on another path.
- **Pickups:** cap 60 with gem merging; lifetime and blink; drops by table; kill-heal capped at max HP; the dropped weapon is untouchable for 0.5 s.
- **Cues:** conditioned cues fire only on their answer; the glitch wipe flashes ≤ 3/s and is a crossfade under reduce flashing; `path` swaps and clears (no leftovers after each swap); `give` per path; `look` with seconds falls back; `room`, `boss_hp`, `level`, `picked` whens; `problems()` rejects a path basic under another path, a `path` cue outside a tryout and a `boss` goal without a boss.
- **Looks:** each role resolves in each look; `Look.path_for(1, take.id)` holds for the 3 new changes; the `LOOK_READERS` lint passes with `systems/palette.gd` added, and no gameplay script reads `Palette`; **tier 0 matches the m42.2 reference** (windowed, same machine, ±1 LSB); `Look.try_on` mid-session re-colours live nodes and restores; HUD and debrief text are not under the pass; the luminance and contrast checks (1.7); reduce flashing: no white flash, neon's pulse capped.
- **HUD:** each widget reads each style; the corner rule (M39.2) holds before `add hud`; no overlap with the mascot or the centre 70% (3 styles × 3 paths).
- **Layouts:** each set plays its 3 parts in a session; `room N` cues; every exit reachable with every dash style × aim; `edit_hot_edges` never covers an exit tile.
- **Enemies:** `EnemyDB.BASES` is the only base list (the three copies are gone, `Unlocks.ARCHETYPES` is an alias); cues and sessions validate against `EnemyDB.all()`; the walker split keeps v6 hashes identical; each variant spawns, dies and splits as written; the shielder blocks front shots only, and blasts, pierce and orbit get through; the spatial hash runs only in path sessions.
- **Edits:** the reversibility invariant for each of the 6 (v8 5); `edit_screen_wrap` wraps the player, enemies and shots, and restores the walls.
- **Event:** `gravity_through_screen` plays its 6 steps in order; play is frozen (no damage, clock held, no spawns); **every body is back at its exact position and scale** (a state hash before = after, except enemies popped at 1 HP, which are logged); once per save; the gentle variant creates no white node; it aborts cleanly if the scene is freed; the crack persists to S12 and is a hairline after S12's polish.
- **Boss:** phases end on their `ends_on`; every attack telegraphs ≥ 0.6 s; dry time ≤ 8 s (logged per attempt); `max_seconds` moves to the next phase with its line and on P3 opens a damage window instead; **a win needs HP 0 or every part dead** (no timer, backstop or help level ends it otherwise); the Copycat reads the player's weapon, each dash style and the last pick; the Patcher's edits go through the rule book with warnings, and the mascot's revert works; **no Move on after a boss death** (attempts 1–8); Retry restarts the boss session; hints and help from the 2nd loss, each help level applies, help never ships; the dummy can't die and is removed.
- **Reactions:** the ~30 converted reactions fire in the same Stage 1 sessions as with `min_session`; the list of Stage 1 reactions that can fire in each `s2_*` session × path matches its fixture (`not_shooting` never on Auto); `when` gates (a gated reaction takes no cooldown slot); each new trigger fires on a scripted context.
- **Default-on audit:** every row of 3.5 has its cue in that session's data for that path.
- **Stage sets in sessions:** `prompts` is 0, in-run picks never count as prompts, a part's clear sweeps pickups, dropped weapons and crates; the v6 `stages` fork is never asked in a session.
- **Telemetry:** an M42.2 campaign line still parses; `CAMPAIGN_SCHEMA` is 4.
- **Save:** an M42.2 end-of-Stage-1 fixture continues at S7 with the stage card; an M42.2 save with index 7 maps to `next = s2_01_tryout`; inserting a session before the save's session leaves it pointing at the same id; `help` persists; nothing weapon-related is saved; schema stays 2.
- **Determinism:** the same seed plays **S7 (the three swaps)**, S8 (each path, the try-on included), **S11 (the event)** and S13 (each boss) twice with identical per-10-frame hashes, picks and pickups included.
- **Lines:** every intro ends 0.25 s before its first edit, event, `path` or `look` cue (M42.2's test, extended to every face × path × look × layout × HUD condition). The test reads the session data and the lines file, so a tone edit changes data only.
- **Legacy:** the v6 suite and both v6 hash compares pass unchanged at every milestone.

---

## 6. Milestones

Each milestone **ends playable**: the campaign plays from S0 to its last built session, with the new piece in it. "Bot" = a bot number; "human" = needs the owner; "**windowed**" = needs a real renderer on the dev machine (never in check.ps1; the report gives the command line). **Hard gates** are only: invincible pacing, determinism, hash compares, the telegraph / dry-time / backstop rules, "0 hits during the event" and tests. **Every mortal-bot number is reported with hit kinds, never pass/fail** (0.4); a mortal number far off its band means checking the bot policy first.

**Before M43 (on the `m42.2` tag, nothing changed yet):** record the m42.2 campaign hash (`run_hash.gd --campaign --session=<id>` for s1_03–s1_06, per second, entity kinds and positions plus kills) and the tier-0 screenshot reference (5 frames, windowed, same machine). Both live in `.check/ref_m42.2/` and are compared at M43, M43.1, M44, M45a, M45b and M48.

| # | Milestone | Builder gate | Owner gate |
|---|---|---|---|
| M43 | **Answers and the Stage 2 door** | **Step 0:** `git mv PLAN.md PLAN.v8.md` (marked "Phase 5, done"), install v9 as `PLAN.md`. Then 1.1 (`Unlocks.answer/take` on `Fork.answer()`, `fork:` everywhere, `&` on any condition, `!`, one-word `attempts:n` / `died_in:`, `--answer=`), 1.2's fields (validated; goals `stages`/`boss` as stubs; `CampaignDef.stage_titles`), 1.3's cue grammar, 1.13's `after`/`until` + `when` + **the 30-reaction audit**, 1.14's **save by id** + continuation, the stage card, `check.ps1` / `export.ps1`'s end-of-campaign rewrite by id (4). **S7 as a stub:** Stage 1's gun, `survive` 60 s, "To be continued" moves after it. **Numbers (bot, hard):** both v6 hash compares 0 failures; the m42.2 campaign hash identical; the Stage 1 invincible chain identical (`play=290.0`, the same stripped lines and picks); `--answer=fork_dash=dash_grapple` = `--dash=grapple` byte for byte; an M42.2 save with index 7 maps to `s2_01_tryout`; the per-`s2_*` reaction list matches its fixture | — **The report asks four one-liners** (none blocks M43–M50): (1) length: "Stage 1 ~7 min vs ~20, Stage 2 planned 30–40 vs 45: grow now or later?" · (2) versions: patch bumps v0.8.1–v0.8.5, or one minor per session? · (3) forks: 13 vs 10–12, drop `fork_hud`? (needed before M51) · (4) G13's 7a–7j, one line each. Unanswered = the defaults in 9 |
| M43.1 | **Enemy lists + the walker split** | `EnemyDB.BASES` / `VARIANTS` / `all()`, `Unlocks.ARCHETYPES` as an alias; `enemy_walker.gd` split into per-archetype behaviour scripts. Nothing else. **Numbers (bot, hard):** both v6 hash compares 0 failures; the m42.2 campaign hash identical; `test_save.gd:315` unchanged | — |
| M44 | **Weapons, ranks 1–3 (proven invisible on Stage 1)** | 1.4: `WeaponDef`, `Weapon`, `Loadout`, `Shooter.fire`, pierce / bounce / blast / size / lifetime, `weapons/traits/` and the **rank 2–3 behaviours** of the 5 shared weapons, `give`, `loot_rng` / `pick_rng`, F2 WEAPONS. The S7 stub hands pistol + shotgun (switch with Q/E via the new `weapon_prev/next` actions). **Numbers (bot, hard):** both v6 compares 0 failures and the m42.2 campaign hash identical **with the new `Projectile` defaults in** (not first at M45); `path = ""` leaves every `WorldRules` field at its M42.2 value (field by field). **Reported:** a bench run with every weapon at rank 3 (windowed); mortal S4 time to death with each weapon forced | — |
| M45a | **Path plumbing + the Auto taste** | 1.5's `PathDef`, the path overlay (owner `&"path"`), the path meter, **`PickOffer` / `PickPanel`**, the `path` cue, F2 PATH, the pool rule (1.2), `Pickup` with gems (1.6), Auto's auto-fire per slot and crowd overlay, the `auto` bot policy, **pick handling in `_run_campaign`**, `--probe=afk`, `--loadout=`. The S7 stub becomes an Auto taste. **Numbers (hard):** with `path = ""` no `WorldRules` field moves; after 10 picks the stack and `build_number` are unchanged; no pick carries a weapon before its cue; S8-draft (`--only`, 180 s, Auto forced) 6–10 level-ups (invincible); `afk` on Auto ≤ 50% of the default time to death or dies before the goal; hashes as M44. **Reported:** mortal time to death; path-only lines (`tools/path_lines.gd`, ≤ 250) | — |
| M45b | **Auto at scale** | spatial-hash separation (path sessions only), `nova` and `well` (ranks 1–3), **the split projectile budgets** (player 140 / enemy 60, path sessions only; Stage 1 and the legacy loop keep today's combined cap, so their hashes hold), `enemy_shots_refused` in telemetry. **Numbers:** a v6 shooter enemy still fires with Auto saturated (test, hard); hashes as M44 (hard); Auto bench at the cap ≥ 60 fps (**windowed**, dev machine) | — |
| M46 | **Arsenal** | the hand, switching (`weapon_1..3` outside panels), quick-draw, the cards growth, `HandWidget` (today's corner style), the `arsenal` policy (with the flank rule), `--probe=no_switch`, `--probe=first_pick`. **Numbers (invincible, hard):** offers every 35–60 s over 3 min; the bot fires ≥ 2 cards in 12/16 runs (a plumbing check). **Reported:** `afk`; mortal time to death per seed **as distributions** next to Auto's (Auto's ×1.6 spawns break seed pairing); the `fp` of Arsenal vs Auto side by side (a regression signal, 1.15) | — |
| M47 | **Survival + S7 + `fork_path` + S8-draft + the G14a build** | `Drops`, crates, ammo, the sidearm, `kill_heal`, `battery`, `pickup_tiles`, the `survival` policy (the multi-source BFS field, 4), `--probe=no_pickup`; **`EnemyVariant` and the splitter** (the other variants wait for M50); S7 as written (3.2) with its lines; `fork_path` with your-taste stills; S8 as data **without the look try-on yet** (plain look). **G14a build step:** `export.ps1` boots S7 and S8 × 3 paths; a G14a section in `PLAYTEST.md`; the start screen's replay-as-path (2); the lines file (0.4). **Numbers (hard):** S7 invincible plays all three tastes at their seconds in 16/16 seeds with no leftovers after each swap; S7 replays its three swaps to the same per-10-frame hash twice; S7 mortal deaths 0/16 (`hp_floor`, a rule check); no drop or crate carries a weapon before its cue; the 3.5 audit test for S7–S8. **Reported:** Survival pickups per min, dry share, heals per S8 (invincible; mostly the policy's greed, 4); `no_pickup` vs default; mortal S8 deaths per path with hit kinds; the full `fp` table, 3 paths × 8 values | **G14a (~15 min, playtest build): the three paths.** The owner plays S7, then S8 once per path (replay-as-path). **Questions, the build-changing ones first, one line each:** (1) Arsenal's cards and Auto's level-ups next to "no 3-way choices for patches": fine? (2) Back to the pistol every session: fun or a loss? (3) 13 forks: drop `fork_hud`? (if not answered at M43) · then: do they feel like three games? (each pair 1–5) · which would you keep, and why? · **the look after S8 instead of at the end of Stage 1: right moment?** (0.3) · the lines file: any tone edits? · G13's 7a–7j, one line each. Their own `fp` lines are logged next to the bots'. **If G14a is not answered, M48 proceeds on the defaults (9). M47.1 runs only on an explicit score ≤ 2 for a pair** |
| M47.1 | *(only on an explicit G14a pair score ≤ 2)* **Re-spike the weaker path** | the fallback in 9 for that path; G14a's S8 replay for it again | a short re-ask of that pair |
| M48 | **The looks + S8 complete + S9 + the path edits** | 1.7: `Palette` and every colour routed (the file list in the report; `systems/palette.gd` added to `LOOK_READERS`, gameplay scripts kept off it by a lint), `LookLayer`, the `look_1_pixel/neon/paper` presets and shaders, `Look.try_on`, the glitch wipe and its crossfade, the `look` cue, F2 LOOK; S8's try-on; `fork_look` with one-capture-three-shaders cards; S9 as data (the laser, `nova`'s line); **the three path edits** (`edit_shuffle_hand`, `edit_auto_wrong`, `edit_weapon_rain`) with their reversibility tests, here and nowhere else. **Numbers (hard):** v6 hashes and the m42.2 campaign hash unchanged; S8 per path replays (try-on included) to the same hash twice; no glitch wipe flashes > 3/s; the reversibility test for each path edit. **Windowed (dev machine, same machine as the reference, ±1 LSB):** tier 0 matches the m42.2 reference on 5 frames; `tools/look_check.gd`: background luminance ≥ 0.15 apart pairwise, player and shots ≥ 3:1; the pass ≤ 2 ms at 1080p (Auto at the cap); `.check/look_<id>_*.png` sheets (S9 mid-fight, the pick panel, the debrief, each mascot's 8 expressions) + a 20 s clip per look. **Reported:** S9 mortal deaths per path | — |
| M48.1 | **`edit_screen_wrap`** | the border walls off; wrapping for the player, enemies and shots; the camera wraps without a jump; the spawner's off-screen `pick_point` never picks the far edge while it is in view; refused while an exit gate is open (stage sets); the bot policies wrap-aware; the S9 cue (`kills 30`). **Numbers (hard):** the reversibility test (walls back exactly); no 1-frame camera jump across a wrap (tested); no spawn on the far edge in view (tested over 16 seeds); S9 invincible pacing 90–150 s per path | — |
| M49 | **Boss vertical slice (the Patcher) + the G14b build** | 1.10's `BossDef`, `BossPhase`, the attack primitives the Patcher needs (`ring`, `aimed`, `summon`, `cast_edit`), the entity, `BossWidget`, goal `boss`, `checkpoint`, the backstop rule, hints and the help ladder, `DangerZone`s, the `boss` policy and **the bot's boss loop** (4), the mascot's revert; S13 playable with `--boss=boss_patch` on `arena_boss` (the Patcher's lines only). **G14b build step:** `export.ps1` boots the slice per path; a G14b section in `PLAYTEST.md`; replay-as-path covers it. **Numbers (bot, hard; DPS from `--loadout=` fixed per path):** invincible time-to-kill 90–150 s per path, max/min across paths ≤ 1.3 (set by `boss_hp_mult`); every phase 25–45 s; the backstop fires in ≤ 1/16 and never skips P3; `dry_max` ≤ 8 s; no attack lands with < 0.6 s telegraph; a 16-shot ring still fires with Auto saturated; a win needs HP 0 (test); Move on never offered (attempts 1–8, test); **feasibility:** help level 3 + the boss policy wins ≥ 1 of 8 tries in 16/16 seeds per path. **Reported:** the seeded-run ttk spread; mortal tries, `phase_deaths`, `by_boss_attack` | **G14b (short, ~10 min; async is fine): the looks and the boss.** The owner looks at the 3 look sheets + clips, then plays the Patcher slice on their G14a path. Q: Is each look worth choosing? Which would you pick? Any to swap? · Is the boss a sponge? Fair telegraphs? Do the hint and the help feel kind or patronising? **If skipped, the defaults stand and these move to G14.** A look with "no" → `look_terminal`; "sponge" → P1 + P3 only |
| M50 | **Levels + the three enemies + S10** | 1.8's levels (`stages` sessions with prompts forced to 0 and clears that sweep pickups, the 3 sets retuned with `pickup_tiles`, `room N [at s]`), `fork_layout` as new campaign `.tres` (S9's debrief, map thumbnails), the launcher, shielder / sniper / swarm as `EnemyVariant`s (the sniper's `DangerZone`), the flank rule in the Arsenal and Survival policies, `edit_hot_edges`, S10 as data (no fork; notes). **Numbers (hard):** S10 invincible 200–260 s per layout, no part over 100 s; every exit reachable with 3 dash styles × 2 aims; `edit_hot_edges` never covers an exit tile; the v6 `stages` fork is never asked in a session. **Reported (check hit kinds first):** mortal deaths per layout × path (9 cells × 16 seeds); each enemy × path time to death against that path's no-new-enemy baseline; shielder hits blocked per path | — |
| M50.1 | **Rank-4 evolutions** | the 7 evolutions of 1.4 as traits, offered from S10 on; F2 shows them. **Numbers:** caps at the top rank (player budget 140, enemies keep 60; test, hard); hashes as M44 (hard); bench with every weapon at rank 4 (**windowed**) | — |
| M51 | **The HUD + S11 (without the event)** | 1.8's `HudStyle` ×3, the 8 widgets, `add hud`, score and combo, `fork_hud` (S11's debrief, live previews; if the owner cut it, the AI picks the style from your `fp` and announces it in S12), the orbit and `well` lines; S11 as data with the three enemies mixed in, the orbit, `edit_enemies_flee`, the event cue as a no-op. **Numbers (hard):** the no-overlap test, 3 styles × 3 paths; the reversibility test for `edit_enemies_flee`. **Windowed:** 27 HUD captures (3 styles × 3 paths × 3 looks) in `.check/`. **Reported:** S11 mortal deaths per path | — |
| M52 | **Gravity through the screen + look tier 2** | 1.11: the event, `GlassStack` (`PROCESS_MODE_ALWAYS`), the freeze on `set_pause` + `hold_clock`, `camera_push`, `crack` and its persistence, the sorry gift, the gentle variant; tier 2 for each look (1.7). **Numbers (hard):** 16/16 S11 seeds per path play the event fully; **0 hits during it**; state hash before = after in 16/16; the same seed replays the event to the same hash twice; the 6 steps at fixed frames; the gentle variant creates no white node. **Windowed:** a `.check/glass_*.png` strip (grow, smack, pile, undo) per look; tier 2 sheets per look; bench ≥ 60 fps with tier 2. **Reported:** deaths in the 20 s after it against the control (`--events=none`) | — |
| M53 | **The other bosses + S12 + S13** | the Big Square and the Copycat (the remaining primitives: `spiral`, `charge`, `slam`, `copy_weapon`, `copy_dash`, the split), S12 as data (the HUD lands, the polish, `arena_boss`'s line, the dummy), `fork_boss` (S12's debrief), S13 complete for all three. **Numbers (hard; fixed loadouts):** invincible time-to-kill **90–150 s for each path × boss (9 cells)**, max/min ≤ 1.4; the phase, dry-time, backstop and telegraph rules as M49 on every cell; feasibility as M49 on every cell; S13 per boss replays to the same hash twice. **Reported:** mortal tries per cell, `phase_deaths`, deaths by attack per boss | — |
| M54 | **Stage 2 complete + the G14 playtest build** | every line of 3.2 (with the owner's tone edits if given), the ~20 reactions (3.3), the 3.5 audit test for every session, tuning to 3.1's pacing targets, telemetry 1.15, the full `check.ps1` / `export.ps1` additions (4), `tools/stage2_sweep.ps1`, `PLAYTEST.md` rewritten for G14, with an end-of-Stage-1 save shipped. **Numbers (hard):** invincible chains A / B / C (S7–S13): play 17–22 min each (bot), reading estimate reported; `check.ps1 -BotRuns` ≤ 15 min wall time; the m42.2 campaign hash still identical; the export boots (4) clean. **Reported:** mortal first-try deaths per session per path against 3.1's human bands; boss tries per cell | **G14: owner playtest of Stage 2** from the shipped end-of-Stage-1 save or a fresh save (section 7) |

`tools/check.ps1` is green before every commit. Each milestone gets a tag and a report, as before (reviews: 5 reviewers, 3 skeptics per finding). The report says which numbers are bot, which are windowed and which need a human, and quotes the path-only line counts.

**Why this order:** the answer plumbing first, because five forks ride on it and the dash's hand-wiring must not be copied five times. The enemy lists and the walker split alone next (M43.1), because a pure refactor is easiest to prove identical when nothing else moves. Then the weapon foundation, proven invisible on Stage 1 (identical hashes), because every path, the Copycat and the HUD widgets read it. Then the paths from cheapest to most new code (Auto reuses the most v6 code and brings `Pickup` with its gems, split into plumbing and scale; Arsenal adds the hand; Survival reuses `Pickup` and adds drops), so each is the previous one plus a small piece. **G14a comes before any content is stacked on the paths:** "do the three paths feel like three games?" is Phase 6's main question, and a wrong path is cheap to fix now and expensive once layouts, HUDs and bosses assume it. The looks next, because they are the other big question and every later screenshot uses them; the path edits land with S9, the only session that uses them, and the screen wrap gets its own step because it touches collision, the camera, the spawner and exits. **The boss slice comes right after (M49, G14b)**, because a sponge boss is the stage's biggest fun risk. Then content in play order. The evolutions wait for M50.1, the first point where a session is long enough to reach rank 4. The event needs the look (its proxies use the palette) and S11. The other bosses come last because they use everything.

**Cut order if needed (first to last):** the 3 s path clips (stills stay) → the pick panel's comments → the Copycat's phase 3 (one copy) → `edit_shuffle_hand` / `edit_auto_wrong` / `edit_weapon_rain` (S9 keeps `edit_screen_wrap` only) → reactions down to 10 → rank-4 evolutions (ranks stop at 3; ranks 2–3 keep their behaviours) → `fork_hud` (if the owner has not already cut it: the AI picks, 9) → the orbit (S11 brings the enemies and the event) → S12 merged into S13's intro (the dummy becomes the boss's first 20 s). **Never cut:** the three paths on one foundation, the three looks with S9's repaint, S7's playable tastes, the three S10 enemies and their meeting, the checkpoint rule (no Move on, unlimited retries, hints and help, a win only at HP 0), the anti-sponge rules, gravity through the screen, the default-on audit (3.5), "power stays in the session" (unless G14a says otherwise), G14a and G14.

---

## 7. What v9 must answer (M43 report, G14a, G14b, G14)
**Asked in the M43 report (one line each; none blocks M43–M50; unanswered = the default in 9):**
1. **Length:** Stage 1 is ~7 min against ~20, Stage 2 is planned at 30–40 against 45, and the campaign target is ~2 h 30. Grow now (a session in a stage's middle) or later?
2. **Versions:** Stage 2 as patch bumps (v0.8.1–v0.8.5, the boss v0.9.0), or one minor per session as Stage 1 did?
3. **Forks:** 13 across the campaign (14 with dash aim) against "about 10–12". Drop `fork_hud` (the AI picks the style, announced)? Needed before M51.
4. **G13's open items** (PLAYTEST 7a–7j): the gift's length, the event seen at start, S5's difficulty, S6's length, my lines.

**G14a (the build-changing questions first):**
5. **Are the in-run 1-of-3 picks** (Arsenal's cards, Auto's level-ups) fine, or do they feel like the old patch prompts you didn't want?
6. **Is "power stays in the session" fun** (back to the pistol every session), or does it feel like lost progress?
7. (3, if still open.)
8. **Do the three paths feel like three games?** Which did you keep after S7, and did S7's tastes help you choose? (again at G14 after a whole stage)
9. **The look moved** from the end of Stage 1 (ROADMAP 2 / 6.5) to S8's debrief, after a live try-on. Is that the right moment?
10. **The lines file:** any tone edits? (I draft, you edit; ROADMAP 6.7)

**G14b and G14:**
11. **Do the three looks feel worth choosing?** Did the S8 try-on help, and did your look feel like a reward when it landed in S9?
12. **Is the boss a fair checkpoint**, not a damage sponge? How many tries? Did the hint and the help feel kind or patronising? (G14b on the slice; G14 on your pick)
13. Does **gravity through the screen** read as a funny accident, like the gravity flip did? Too long, too short? Did the crack gag land?
14. Meeting the three enemies in S10 and keeping all three: right, or would you rather have picked one?
15. Is Stage 2 **quick enough, with something new every session**, and does S8 feel new after S7's tastes?
16. Is the AI still **the main force** once the path is in, and does it seem to **remember** you (your dash, your Stage 1 enemy, the drawer)?

---

## 8. What happens to old pieces
| Piece | In v9 |
|---|---|
| `Shooter` + `Tuning.shoot_cooldown` / `projectile_speed` | the pistol `WeaponDef` holds the numbers in path sessions; with `path = ""` the pistol still reads `Tuning` (so `--set=` and every hash hold) |
| `AiDirector` meter, `PromptPanel`, `Offer`, `taste.gd` | `PromptPanel`'s look is reused by **`PickPanel`** (a subclass taking a **`PickOffer`**); `taste.gd`'s weights lean the offers. `Offer`, `AiDirector.on_choice` and the PATCH gauge stay legacy-only (they apply Mutations to the stack) |
| `PLAN.md` (v8) | archived as `PLAN.v8.md` ("Phase 5, done") in M43's step 0 |
| `systems/look.gd` (`Look.use`, `path_for`), `systems/looks/look_1_*.tres` | kept; new `look_1_pixel/neon/paper` and `look_2_*` presets; `Look.try_on` added; colours go through the new `systems/palette.gd` |
| `test_readability.gd` `LOOK_READERS` | + `systems/palette.gd` only |
| `RunState._under_cap` (combined 200) | split into player 140 / enemy 60 in path sessions; unchanged in Stage 1 and the legacy loop |
| `campaign.index` in the save | derived from the new `campaign.next` id |
| `Fork.answer()`, `Fork.shelf()` | the base of `Unlocks.answer/take` and `CampaignDB.shelf` |
| v6 mutations `echo`, `bouncing_projectiles`, `explode_on_hit`, `orbit`, `well`, `enemies_split`, `elite`, `horde_mode`, `auto_attack` | their code is reused for weapon fields (bounce, blast), the orbit weapon (`mutations/orbit/orbit_shards.gd`), Auto's `well` (`mutations/well/well_field.gd`), the splitter, the shielder's shield (`mutations/elite/elite_mark.gd`), Auto's density and Auto's targeting. **No evolution reskins them** (1.4). The patches themselves stay in the legacy loop |
| `enemy_walker.gd` (3 inline state machines) | split into per-archetype behaviour scripts (**M43.1**), hashes identical |
| `Unlocks.ARCHETYPES`, `cue.gd:29`, `spawner.gd:7` | `EnemyDB.BASES` (`Unlocks.ARCHETYPES` an alias) |
| `mutations/hunter/hunter_body.gd` | the boss entity's pattern |
| v6 stage sets (breakout, gauntlet, shifting), `exit_gate.gd`, the stage swap | the layout fork's answers (new campaign `.tres` files, 1.8); `StageDef.prompts` forced to 0 in sessions; the v6 `stages` fork (`genres/topdown/devsession/…`) stays legacy-only |
| `look_1` fork and its 3 takes (punchy / arcade / clean) | legacy-only; their juice numbers feed the 3 new looks' juice |
| `LookPreset.palette` (dead data) | becomes the palette roles |
| `fork_enemy` (Tank · Bomber · Lancer, Stage 1) | unchanged; S10's memory lines read its answer. There is no second enemy fork |
| `min_session` / `max_session` on reactions | `after` / `until` by session id (converted 1:1), then audited for Stage 2 (1.13) |
| `wait` (E / pad Y) | stays for B2's turn mode; E is also `weapon_next` in sessions |
| Mutation `boss_only` / `boss_weight`, `ai_patch_added(owner &"boss")` (v4) | stay parked; the boss uses the rule book like everything else |
| Per-fork flags (`--dash=`, `--dash-aim=`) | aliases of `--answer=` |
| `check.ps1`'s hard-coded campaign end (`"index":7`, `sessions=7`, `choice=to_be_continued` on s1_06, `v0.6.0->v0.7.0`) and export.ps1's `7 sessions … 30 reactions` | rewritten by id and data counts (M43) |
| The legacy loop | stays until Phase 8 (v8 9) |
| Rework, rollback charges | parked |

---

## 9. Still open (each with a proposed default)
- **Look timing (ROADMAP 6.5, v8 9):** **asked in S8's debrief, after the AI tries all three on you live**; lands in S9. This **changes the ROADMAP's plan** (the end of Stage 1, "so Stage 2 is already yours"), so G14a asks it (7.9). Reasons: S7 already hosts the path, two big picks back to back are heavy, and the preview uses your own S8 frame in your path. Alternative A: ask it at the end of S6 with stills. Alternative B: ask it with the path in S7.
- **The three looks (ROADMAP 6.6):** Pixel / Neon (the darker one) / Paper (the totally different one), as 1.7. Spare: `look_terminal` (green-on-black CRT) if one fails G14b. Alternative: a grim "darker" palette in place of Neon (owner's words: "a darker one").
- **In-run 1-of-3 picks** for Arsenal and Auto (0.4): kept, as ROADMAP 1.7 says, and asked at G14a against dev-session-big-only. Alternative: Arsenal's cards come as drops you walk over, and Auto's level-ups are chosen by the AI from your taste ("Here, take the laser") with no panel.
- **Power stays in the session:** every session starts at the pistol, rank 1 (ROADMAP 1.9.7). Alternative: each session starts with the previous session's weapons in hand at rank 1. Asked at G14a.
- **The tryout order:** fixed Arsenal → Survival → Auto (closest to what you know first, the most different last; Auto's taste has no passives so recency and power don't stack). Alternative: by seed. Telemetry logs which taste came last.
- **Five forks in Stage 2** (path, look, layout, HUD, boss): ROADMAP 2's four plus the look moved from Stage 1. 13 across the campaign counting Stages 4–5 and the owner-added dash (14 with dash aim), against "about 10–12". **Default: keep `fork_hud`** (ROADMAP 2 lists it); the M43 report asks whether to drop it (the AI then picks the style from your `fp` and announces it in S12). Needed before M51.
- **No second enemy fork:** the splitter (S8) and the shielder, sniper and swarm (S10) are announced and **all stay** (enemy type was Stage 1's fork, ROADMAP 2; content = sum). Alternative: `fork_enemy_2` on the same data (S10's debrief, one stays, two shelved), +1 fork.
- **Gravity through the screen as presentation** (frozen play, proxies), not physics. Alternative: real growth and downward gravity in the live simulation (riskier: collisions grow near walls, enemies keep attacking). The crack persists to S12 (alternative: gone with the undo).
- **Event seen at start** (v8's rule; G13 7b unanswered): kept for the new event. Alternative: seen at its punchline (the smack), so a death before the smack replays it.
- **Boss hints and help:** from the 2nd loss, a hint for the phase that got you plus the help offer; then an offer 2 losses after each accept; 3 levels (+2 HP, boss HP ×0.8, the AI joins). Alternative: help from the 3rd loss; or automatic help (no button).
- **Boss tries for the bot:** 8 before `boss_unbeaten`, each bounded on its own; the human has no limit. Mortal boss numbers are reported; the only mortal gate is feasibility (help 3 wins ≥ 1 of 8 in 16/16).
- **The boss backstop:** moves to the next phase only; P3 opens a damage window instead of skipping. Alternative: no backstop on P3 at all (a stuck fight then depends on the help ladder alone).
- **The vertical-slice boss is the Patcher** (cheapest: it reuses the rule book). Alternative: the Big Square (fewest moving parts, least AI flavour).
- **Versions:** Stage 2 = v0.8.0–v0.8.5, the boss v0.9.0. Alternative: one minor bump per session (v0.8–v0.14), as Stage 1 did. That runs to 0.14 before Stage 3, which makes the road to 1.0 at Stage 5 awkward. **Asked in the M43 report** (the owner never set the bump rule).
- **Stage 2 length:** ~30–40 min with reading (ROADMAP: ~45; the campaign ≈ 40–47 min of ~2 h 30 so far). **Asked in the M43 report**, with Stage 1's open length question. Default until answered: build at 3.1's lengths. Alternative: add a session in the middle (a second level session between S10 and S11).
- **Move on after the first death** in normal Stage 2 sessions (v8's rule). Alternative: after the second.
- **Weapon count:** 5 shared + 2 Auto-only passives. Alternative: add a flamethrower and a boomerang in a later growth pass ("upgrades can be even more creative").
- **HUD styles:** Clean / Arcade (with score + combo) / On you. Alternative: Arcade without the score. **The mascot sits top-right in every style.** Alternative: On you moves it top-left.
- **Kill goals by path:** Auto ×2.0, only S9 uses a kills goal. Alternative: Stage 2 avoids kill goals entirely (survive / stages / boss only).
- **Survival swaps on touch** (no "hold E"), so it never clashes with Arsenal's Q/E or the dash bindings. Alternative: hold E to swap, if accidental swaps annoy at G14a.
- **Weapon switching binds:** new `weapon_prev/next` (Q / E, wheel, bumpers) and `weapon_1..3` (keys 1–3 outside panels). E keeps the legacy `wait` too (B2 only). If a bumper is already taken by the dash, the d-pad left / right instead.
- **Rank behaviours:** every rank 2–3 adds a behaviour and rank 4 is a new evolution (1.4). A behaviour too costly in its milestone falls back to a number, logged. Alternative: ranks 2–3 as numbers, behaviours only at rank 4 (cheaper, less creative).
- **Memory lines:** ~8 conditioned lines in Stage 2 (Stage 1's enemy in S10, a death in S10 at S11, the dash in S13, the drawer in S9 and S13). Alternative: more, once the owner has read the lines file.
- **The lines file** ships with the G14a build; the owner's tone edits land by M54. If none come, my drafts stand.
- **Mascot names (ROADMAP 6.1):** still placeholders `Cursor`, `Window`, `Blob`.
- **Lines are English only.** Every line in 3.2 is my draft; the owner edits for tone.
- **G13's open items (PLAYTEST 7a–7j):** their defaults stand (g13-open-questions, g13-feedback). The M43 report and G14a re-ask them in one line each.
- **G14a not answered:** M48 proceeds on these defaults; M47.1 runs only on an explicit pair score ≤ 2. G14b skipped: its defaults stand and its questions move to G14.

**Needed from the owner before M43: nothing.** M43 is plumbing that is identical on Stage 1 whatever the answers. The four M43-report questions (length, versions, fork count, G13 items) are needed by M51 at the latest (`fork_hud`), and the length answer only retunes data.

---

## Appendix: Critiques not taken
The review round (critic 1: owner fit; critic 2: code fit and scope) was taken in full except where listed here. Each entry says what was not taken, or not taken as proposed, and why.

| Critique | Not taken | Why |
|---|---|---|
| C1.1 (fork count) | **Dropping `fork_hud` by default.** `fork_enemy_2` was dropped (the enemy type was Stage 1's fork). | ROADMAP 2 lists the HUD style as a Stage 2 fork. The campaign goes one over "about 10–12" only because of the dash fork the owner added at G13. So the owner decides, asked in one line in the M43 report and needed only before M51. |
| C1.2 (length) | **Holding S7–S13 lengths until the owner answers.** | Session lengths are data (`goal`, `duration`), so building at 3.1's lengths and retuning later costs nothing. Holding them would stall M47 on a question the owner may not answer (they left 7a–7j unanswered). The inference was deleted and the question asked, as proposed. |
| C1.6 (creative upgrades) | **"Every" rank 2–3 is a behaviour, with no exception.** | Taken as the default, with one escape: a behaviour that proves too costly in its milestone falls back to a number, and the report logs it. Without that, one hard trait (the laser's overcharge beam, say) could block M44. |
| C1.8 / C2.31 (mortal gates) | **No mortal gate at all.** One mortal gate stays: *feasibility* (help level 3 + the boss policy wins ≥ 1 of 8 tries in 16/16 seeds). | It does not measure difficulty. It checks that the fight can be won at all, which no invincible run proves (an invincible bot never meets the help ladder). Every other mortal number is reported only, as both critics asked. |
| C1.12 (memory) | **Lines keyed on "how you play".** | The ~8 memory lines use choices (dash, Stage 1 enemy, path) and deaths (`died_in:`). Play-style memory stays with the existing taste reactions (`weapon_unused`, `camping`). The `fp` is report-only by design (bot-runs-as-tuning-proxy) and should not drive lines before a human has checked it. |
| C2.10 (input binds) | **Taking E away from `wait`.** | B2's turn mode in the legacy loop still uses `wait` on E. Two actions on one key are fine in Godot when no context reads both. A test checks that no campaign code reads `wait`. |
| C2.15 (shared caps) | **Splitting the projectile cap everywhere.** | A global player 140 / enemy 60 split could change legacy runs and break the v6 hash compares. It applies only in path sessions; Stage 1 and the legacy loop keep the combined 200. |
| C2.20 (M44 too big) | **Rank-4 evolutions in M46 or M47.** They are in M50.1. | Sessions before S10 are too short to reach rank 4, so the G14a build does not need them. This keeps M46 and M47, the milestones before the owner gate, small. |
| C2.32 (enemy gates) | **Measuring the enemies only after the bot can dodge and flank.** | The sniper `DangerZone` and the flank rule are added in M50, as proposed. The numbers stay "reported, check hit kinds first" anyway, because a flanking bot is still not a human. |

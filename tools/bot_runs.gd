extends SceneTree
## End-to-end bot runs (M6 gate): full-length runs with the real tuning, started from
## the start screen and chained through the report's "New build" button.
##
##   godot --headless --path . --fixed-fps 60 -s tools/bot_runs.gd -- 1 2 3 4i 5i
##
## Each argument is a seed; a trailing "i" makes that run invincible, so the win path
## is played too. Options (any position):
##   --set=<tuning var>=<value>   override a Tuning value for every run (retune sweeps),
##                                e.g. --set=prompt_min_gap=90
##   --set=<mutation id>.<var>=<value>   override a number on that patch's take for the
##                                run's genre (a parked legacy patch: on its resource),
##                                e.g. --set=explode_on_hit.radius=90
##   --big=<mutation id>          start every run with that parked big patch in the slot
##                                (PLAN v5 1.3: the slot is a test seam; nothing swaps it)
##   --apply=<mutation id>        apply that small patch at the start of every run, as if
##                                picked (M33 parity: a piece's own effect, without the
##                                offer pool's draws changing with the pool's size)
##   --stages=<set id>            every run plays that stage set (levels/stages/<id>.tres,
##                                PLAN v6 5), e.g. --stages=gauntlet: a 3-stage run
##   --log=<path>                 write telemetry there instead (parallel sweeps)
##   --save=<path>                play every run from that save, read-only: each run sees
##                                the same snapshot and nothing is written (PLAN v5 4.6)
##   --keep-save                  with --save: chain the runs through the file (each run's
##                                end is written, as in the real game)
##   --fresh                      start from a new save (v0.0.0) instead of the file, or,
##                                without --save, instead of everything unlocked
##   --rework-chance=<0..1>       in a fork session that offers Rework, rework instead of
##                                picking with this chance (default 0.2, PLAN v6 5); a
##                                REWORK-only session reworks or keeps, 50/50
##   --ship=<id>,<id>             ship these changes into the save before the first run,
##                                e.g. --fresh --ship=basic_movement,basic_world plays the
##                                v0.0.2 run instead of the smoke tests (PLAN v5 4.8)
##   --campaign                   play the campaign (PLAN v8 4) instead of the run loop:
##                                from the save's next session to the end so far, one
##                                "[botrun] session=<id>" line each. The first seed seeds
##                                the chain (each session's seed derives from it); a
##                                trailing "i" makes every session invincible. On a death
##                                the bot retries once, then moves on.
##   --only=<session id>          with --campaign: play only that session, once per seed
##                                (each on its own in-memory save, the mascot picked by
##                                the seed), and sum up the AI's reactions (PLAN v8 M39):
##                                chatter per 90 s, the shortest chatter gap, priority 3
##                                lines heard
##   --edits=none,<id>,...        with --only: one pass per condition (PLAN v8 M40). The
##                                session's own edit cues are dropped; <id> is forced in
##                                as a cue at --edit-at (default 12 s), warning included;
##                                <id>:<s> keeps it <s> seconds instead of its own duration.
##                                The summary sets each condition's median time against
##                                none's (inside 0.8..1.2: PASS; edit_inverted reported)
##   --lift=<s>                   with --only: the session's goal value becomes <s> (a
##                                30 s survive lasts <s>), so deaths can be compared
##   --events=none                with --only: drop the session's event cues (M41's control)
##   --session-set=<key>=<value>[,...]   with --only or the chain (M42): set a session's
##                                own field (spawn_rate, spawn_cap, goal_value, time_limit)
##                                on a copy of it, exactly as the .tres would ship it. In
##                                the chain it applies to every session; <session id>.<key>
##                                applies to that one only. goal_value also clears the
##                                copy's goal_by_path (M47.2: S8 Survival's 90 s)
##   --dash=<classic|grapple|teleport|none>   with --campaign (M42.1): the dash style.
##                                With --only, ships dash_<style> before the session (none:
##                                the player's dash stays locked, a control); in the chain,
##                                S3's debrief picks that option of fork_dash. Without it
##                                --only plays classic (fork_dash unanswered) and the chain
##                                picks by the seed. Each --only line ends with
##                                dash=<style> uses=n misses=n fizzles=n air=<s> (air: seconds
##                                off the floor under gravity), and "deaths:" adds by_dash=
##   --dash-aim=<aim|move>         with --campaign (M42.2): where the dash goes. With --only,
##                                ships dashdir_<x> before the session; in the chain, S3's
##                                debrief picks that option of fork_dash_aim. Without it
##                                --only plays move (unanswered) and the chain picks by the
##                                seed. Each --only line ends with aim=<aim|move> (after
##                                air=), and "deaths:" adds by_aim=
##   --loadout=<id:rank>[,<id:rank>...]   with --only (M44, bot only; M45a reuses it): on
##                                the session's first frame the player's loadout is cleared
##                                and each weapon set at exactly that rank (1-3), in order;
##                                the first aimed one is active (a passive rides along with
##                                the pistol). Each --only line then ends with
##                                weapons=<id:rank,...> (the loadout at the end), as it does
##                                for a session that lists weapons
##   --draft=<id or res path>     with --only (M45a): loads campaign/drafts/<id>.tres and puts
##                                it in this process's session list at cooking_index() (before
##                                the first cooking session, or current_index() would clamp
##                                past it), so --only=<id> plays the draft (the S8-draft: Auto)
##   --probe=afk                  with --only (PLAN v9 4, M45a): a degenerate strategy: no move,
##                                no dash, no jump, no fire (Auto still fires by itself). The
##                                line gets probe=afk at its end
##   --probe=no_switch            (M46) the arsenal policy never switches cards
##   --probe=no_pickup            (M47) the survival policy never walks to a pickup (it still
##                                takes what it walks over)
##   (M47) On Survival a "survival:" summary follows the paths: line (pickups per min, heals,
##   ammo_dry_share and crates taken per run: median min-max).
##   --probe=first_pick           (M46) every pick panel takes card 0; its own pick_rng draw is
##                                still consumed, but offers stay paired with the default only
##                                while both hands match: PickOffer.draw rolls once per card
##                                after `first`, so once the hands differ the candidate counts
##                                (and the stream) diverge. Not a paired-by-seed comparison
##   (M46) On Arsenal (cards growth) the --only line ends with cards=n offers=@t,... (game
##   time of each pick offer) cards_fired=k (cards that fired >= 1 player shot) and
##   shots=<id:pellets,...>, and an "arsenal:" summary follows (offers, gaps from the `add
##   cards` time, in_band = >= 3 offers, mean gap 35-60 s and a tail <= 60 s; cards_fired>=2).
##   --fp                         (M46) also print a "fp:" summary per path (the play
##                                fingerprint of PLAN v9 1.15: medians and min/max over the
##                                runs), fp=<key:value,...> at the very end of each path
##                                run's --only line, and t_list= (sorted times) to "deaths:".
##                                Off by default, so check.ps1's lines never move
##   (M45a) With a live path the --only line ends with path=<id> level=n picks=n pickups=n
##   (pickups taken), "deaths:" adds by_path=, and a "paths:" summary follows (M45b: it ends
##   with enemy_shots_refused median/max and player_shots_refused median); the chain line
##   gets the same fields after card=. Pick panels are chosen with RunState.pick_rng. With a
##   path, --loadout= is forced again each time the path starts, then growth is frozen (no
##   gems, no level-ups: a fixed loadout for the whole session).
##   (M47) On a tryout (S7) the --only and chain lines get swaps=<id>@<t>,... (each path
##   swap, game time) and leftovers=<n> (swaps that left something behind) right after the
##   path fields, and a "tryout:" summary follows (swaps in place, leftovers 0, the `picked`
##   line said before the second swap). --only answers every fork the session names (enemy
##   and path forks), by the seed unless --answer= names it; a path session that still
##   resolves no path fails.
##   --max-sessions=<n>           (M47) with --campaign (the chain): stop after n sessions
##   --answer=<fork>=<change>     with --campaign (PLAN v9 1.1, M43; repeatable): answers
##                                that fork with that option. With --only it ships before
##                                the session (before the seed answers its enemy fork); in
##                                the chain, the debrief picks it. --dash=<style> (not none)
##                                and --dash-aim=<aim> are its aliases (fork_dash=dash_<s>,
##                                fork_dash_aim=dashdir_<a>). Parsed by the game's own
##                                CampaignDB.answers_from_args: --answer= wins over its
##                                alias, and the first flag of one kind wins (a first
##                                --dash=none too); --dash=none with an --answer= for
##                                fork_dash fails
## A session that opens a stage card (PLAN v9 2) has it skipped on its first frame; the
## chain's line then ends with card=<stage> (after version=).
## With --only the session's forks are answered by the seed (enemy=), and a session with
## a scripted event prints event=<id>@start-end steps=n/N hits_in_event=n (unblocked,
## by kind) per seed and an "events:" summary: played fully, died during it (M41 gate).
## Without --edits each --only line ends with landed=<edit@t,...> (M42), and the summary
## is followed by "deaths:" (outcomes, median t, deaths by forked enemy, whole-run hits
## by kind). The chain line ends with enemy= and landed=, and a "chain:" total follows
## (play, real, an estimated reading time: lines x (read time + length/45) + 5 s a pick).
## Without --save or --fresh the save is inert (everything unlocked, no file), as in tests.
## With a live chain (--keep-save) the report's button opens the dev session (PLAN v5
## 4.6): the bot picks a card at random from the run's seed and presses "Play"; one
## "[botrun] session" line per session.
## The real save file is never used: --save must name another path.
## The bot plays and cards are picked at random from the seed. Rollbacks are parked
## (PLAN v5 1.3): the bot never rolls anything back. Even seeds leave notes on the
## report (keep the first patch,
## cut the second). Telemetry goes to user://playtest/bot_runs.jsonl, never to the
## playtest file.
## Prints one "[botrun]" line per run and exits 1 if any run did not reach its report,
## saw a BIG prompt, or rolled anything back (both are parked in v5).

const MAX_FRAMES := 60 * 60 * 45      # 45 real minutes at 60 physics frames a second (PLAN v4 9.4)
const DEFAULT_LOG := "user://playtest/bot_runs.jsonl"

var edit_conditions := PackedStringArray()   ## --edits (PLAN v8 M40)
var edit_at := 12.0                          ## --edit-at
var lift := 0.0                              ## --lift
var events_off := false                      ## --events=none
var session_set := PackedStringArray()       ## --session-set (M42), "[<session id>.]key=value"
const SESSION_KEYS := ["spawn_rate", "spawn_cap", "goal_value", "time_limit"]
const READ_CPS := 45.0                       ## the chain's reading estimate: characters a second
const FORK_SECONDS := 5.0                    ## ... and seconds a pick
const EVENT_TAIL := 1.0                      ## a death this soon after an event counts as during it

var LOG := DEFAULT_LOG
## core/save_game.gd, loaded in _run: naming SaveGame (or loading it this early) would
## compile it before the autoloads exist.
var save: GDScript
var start_big := &""
var start_apply := &""
var save_arg := ""
var keep_save := false
var fresh := false
var ship_ids := PackedStringArray()
var rework_chance := 0.2
var campaign := false
var only := &""
var dash_arg := ""                           ## --dash (M42.1): "" = by the seed / classic
var dash_aim_arg := ""                       ## --dash-aim (M42.2): "" = by the seed / move
## --answer (PLAN v9 M43) and the dash aliases: fork id -> change id.
var answers := {}
## --loadout (M44): [[id, rank], ...]
var loadout_arg: Array = []
var draft_arg := ""                          ## --draft (M45a)
var probe_arg := ""                          ## --probe (M45a): "" or afk; M46 no_switch, first_pick
var fp_arg := false                          ## --fp (M46)
var max_sessions := 0                        ## --max-sessions (M47): 0 = no limit
const PROBES := ["afk", "no_switch", "first_pick", "no_pickup"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var specs := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			if not _override(arg.trim_prefix("--set=")):
				print("[botrun] FAILED: bad override %s" % arg)
				quit(1)
				return
		elif arg.begins_with("--big="):
			start_big = StringName(arg.trim_prefix("--big="))
			# Untyped: naming class Mutation here would compile it before the autoloads exist.
			var big: Resource = root.get_node("MutationDB").get_mutation(start_big)
			if big == null or not big.get(&"is_big"):
				print("[botrun] FAILED: no big patch %s" % start_big)
				quit(1)
				return
		elif arg.begins_with("--stages="):
			var set_id := StringName(arg.trim_prefix("--stages="))
			if not load("res://levels/stage_set.gd").call(&"use_override", set_id):
				print("[botrun] FAILED: no stage set %s" % set_id)
				quit(1)
				return
		elif arg.begins_with("--apply="):
			start_apply = StringName(arg.trim_prefix("--apply="))
			var small: Resource = root.get_node("MutationDB").get_mutation(start_apply)
			if small == null or small.get(&"is_big") or small.get(&"parked"):
				print("[botrun] FAILED: no small patch %s" % start_apply)
				quit(1)
				return
		elif arg.begins_with("--log="):
			LOG = arg.trim_prefix("--log=")
		elif arg.begins_with("--save="):
			save_arg = arg.trim_prefix("--save=")
		elif arg == "--keep-save":
			keep_save = true
		elif arg == "--fresh":
			fresh = true
		elif arg.begins_with("--rework-chance="):
			rework_chance = float(arg.trim_prefix("--rework-chance="))
		elif arg.begins_with("--ship="):
			ship_ids = arg.trim_prefix("--ship=").split(",", false)
		elif arg == "--campaign":
			campaign = true
		elif arg.begins_with("--only="):
			only = StringName(arg.trim_prefix("--only="))
		elif arg.begins_with("--edits="):
			edit_conditions = arg.trim_prefix("--edits=").split(",", false)
		elif arg.begins_with("--edit-at="):
			edit_at = float(arg.trim_prefix("--edit-at="))
		elif arg.begins_with("--lift="):
			lift = float(arg.trim_prefix("--lift="))
		elif arg == "--events=none":
			events_off = true
		elif arg.begins_with("--session-set="):
			session_set.append_array(arg.trim_prefix("--session-set=").split(",", false))
		elif arg.begins_with("--dash="):
			var style := arg.trim_prefix("--dash=")
			if not StringName(style) in Change.DASHES and style != "none":
				print("[botrun] FAILED: bad --dash=%s (%s or none)" % [style, Change.DASHES])
				quit(1)
				return
			if dash_arg == "":
				dash_arg = style   # the first --dash= wins (CampaignDB.answers_from_args)
		elif arg.begins_with("--dash-aim="):
			var aim := arg.trim_prefix("--dash-aim=")
			if not StringName(aim) in Change.DASH_AIMS:
				print("[botrun] FAILED: bad --dash-aim=%s (%s)" % [aim, Change.DASH_AIMS])
				quit(1)
				return
			if dash_aim_arg == "":
				dash_aim_arg = aim
		elif arg.begins_with("--loadout="):
			var db_script: GDScript = load("res://weapons/weapon_db.gd")
			for pair in arg.trim_prefix("--loadout=").split(",", false):
				var wid := StringName(pair.get_slice(":", 0))
				var wrank := int(pair.get_slice(":", 1)) if ":" in pair else 1
				if not db_script.call(&"has", wid) or wrank < 1 or wrank > 3:
					print("[botrun] FAILED: bad --loadout entry %s (<weapon>:<rank 1-3>)" % pair)
					quit(1)
					return
				loadout_arg.append([wid, wrank])
		elif arg.begins_with("--draft="):
			draft_arg = arg.trim_prefix("--draft=")
		elif arg == "--fp":
			fp_arg = true
		elif arg.begins_with("--max-sessions="):
			max_sessions = int(arg.trim_prefix("--max-sessions="))
		elif arg.begins_with("--probe="):
			probe_arg = arg.trim_prefix("--probe=")
			if not probe_arg in PROBES:
				print("[botrun] FAILED: bad %s (--probe=%s)" % [arg, "|".join(PROBES)])
				quit(1)
				return
		elif arg.begins_with("--answer="):
			var pair := arg.trim_prefix("--answer=")
			var fork_id := StringName(pair.get_slice("=", 0))
			var change_id := StringName(pair.get_slice("=", 1) if "=" in pair else "")
			var fork: Resource = root.get_node("ChangeDB").get_fork(fork_id)
			if fork == null or not change_id in (fork.get(&"options") as Array):
				print("[botrun] FAILED: bad %s (--answer=<fork>=<one of its options>)" % arg)
				quit(1)
				return
		elif arg.begins_with("--look=") or arg == "--skins=off":
			pass   # M48b: read by main at boot (Skins.read_args), visual only
		else:
			specs.append(arg)
	# The game's own parser, so a bot line and a game jump with the same flags answer the
	# same forks (--answer= wins over its alias; the first of one kind wins).
	answers = root.get_node("CampaignDB").call(&"answers_from_args", OS.get_cmdline_user_args())
	if dash_arg == "none" and answers.has(&"fork_dash"):
		print("[botrun] FAILED: --dash=none (a locked dash) but fork_dash is answered %s" % answers[&"fork_dash"])
		quit(1)
		return
	if specs.is_empty():
		specs = PackedStringArray(["1", "2", "3", "4i", "5i"])
	var telemetry: GDScript = load("res://systems/telemetry.gd")
	telemetry.log_path = LOG
	if not _set_up_save():
		quit(1)
		return
	if draft_arg != "" and not _insert_draft():
		quit(1)
		return
	if not session_set.is_empty() and not _apply_session_set():
		quit(1)
		return
	var lines_before := _line_count()
	var failures := 0
	var started := Time.get_ticks_msec()
	if campaign and only != &"":
		failures = await _run_only(specs)
		quit(1 if failures > 0 else 0)
		return
	if campaign:
		failures = await _run_campaign(specs[0], lines_before)
		print("[botrun] summary: campaign, %d failures, %d telemetry lines, %.1f s wall" % [
			failures, _line_count() - lines_before, (Time.get_ticks_msec() - started) / 1000.0])
		quit(1 if failures > 0 else 0)
		return

	var start: Node = load("res://ui/start_screen.tscn").instantiate()
	root.add_child(start)
	current_scene = start
	await process_frame
	start.seed_field.text = _seed_of(specs[0])
	start.start()
	var pending_sessions := 0
	if start.dev_flow.is_open():   # the save had a pending session (PLAN v5 1.5)
		pending_sessions = 1
		print(await _answer_session(start.dev_flow, int(_seed_of(specs[0]))))

	for i in specs.size():
		var spec := specs[i]
		var game := await _wait_for_game(null if i == 0 else current_scene)
		if game == null:
			print("[botrun] seed=%s FAILED: game scene never loaded" % spec)
			failures += 1
			break
		var run_seed := int(_seed_of(spec))
		var result := await _play(game, run_seed, spec.ends_with("i"))
		if result == "" or result.contains(" FAILED"):
			failures += 1
		print(result if result != "" else "[botrun] seed=%d FAILED: no report after %d frames" % [run_seed, MAX_FRAMES])
		if i + 1 < specs.size():
			if not game.report.is_open():
				game.report.open(&"lose", {})   # keep the chain going after a failure
			if run_seed % 2 == 0:
				var ids: Array = game.report.rateable_ids(game.run_loop.record)
				for k in mini(2, ids.size()):
					game.report.rate(ids[k], 1 if k == 0 else -1)
			game.report.new_build(int(_seed_of(specs[i + 1])))
			if game.dev_flow.is_open():
				var line := await _answer_session(game.dev_flow, run_seed)
				print(line)
				if line.contains(" FAILED"):
					failures += 1

	var added := _line_count() - lines_before
	var runs := 0
	var notes := 0
	var sessions := 0
	var text := FileAccess.get_file_as_string(LOG).strip_edges().split("\n")
	for line in text.slice(maxi(0, text.size() - added)):
		var d: Variant = JSON.parse_string(line)
		if d is Dictionary:
			if d.get("type") == "run":
				runs += 1
			elif d.get("type") == "notes":
				notes += 1
			elif d.get("type") == "session":
				sessions += 1
	# One run line per run; one notes line per "New build" (every run but the last).
	# A live chain plays one dev session after every run but the last.
	var sessions_expected := specs.size() - 1 + pending_sessions if save.call(&"is_live") else 0
	if sessions != sessions_expected:
		print("[botrun] telemetry: expected %d session lines, found %d" % [sessions_expected, sessions])
		failures += 1
	if runs != specs.size() or notes != specs.size() - 1:
		print("[botrun] telemetry: expected %d run and %d notes lines, found %d and %d (%d lines)" % [
			specs.size(), specs.size() - 1, runs, notes, added])
		failures += 1
	if keep_save:
		var state: Dictionary = save.call(&"state")
		print("[botrun] save: %s runs=%d wins=%d version=%s genres=%s shipped=%s look=%s sessions=%d forks=%s" % [
			save_arg, state.runs, state.wins, save.call(&"version").label(), state.genres, state.shipped,
			state.look, (state.sessions as Array).size(), load("res://devsession/dev_session.gd").call(&"answers")])
	print("[botrun] summary: %d runs, %d failures, %d telemetry lines, %.1f s wall" % [
		specs.size(), failures, added, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures > 0 else 0)


## One session once per spec (PLAN v8 M39): the AI's reactions, summed up. Returns the
## number of failures.
func _run_only(specs: PackedStringArray) -> int:
	if edit_conditions.is_empty():
		return await _run_only_condition(specs, "")
	var failures := 0
	var times := {}   ## condition -> {seed: [duration, died]}
	for cond in edit_conditions:
		times[cond] = {}
		failures += await _run_only_condition(specs, cond, times[cond])
	_edit_summary(times)
	return failures


## The M40 table: each condition's median time-to-death (a run that lives to the end
## counts at its length) against none's, as a ratio and a median of per-seed ratios.
func _edit_summary(times: Dictionary) -> void:
	var base: Dictionary = times.get("none", {})
	for cond: String in times:
		var runs: Dictionary = times[cond]
		var durations: Array = runs.values().map(func(r: Array) -> float: return float(r[0]))
		var deaths := runs.values().filter(func(r: Array) -> bool: return bool(r[1])).size()
		var med := _median(durations)
		var ratio_text := "-"
		var paired_text := "-"
		var verdict := ""
		if not base.is_empty() and cond != "none":
			var base_med := _median(base.values().map(func(r: Array) -> float: return float(r[0])))
			var ratio := med / maxf(base_med, 0.001)
			var paired: Array = []
			for s: int in runs:
				if base.has(s):
					paired.append(float(runs[s][0]) / maxf(float(base[s][0]), 0.001))
			ratio_text = "%.2f" % ratio
			paired_text = "%.2f" % _median(paired)
			if cond.begins_with("edit_inverted"):
				verdict = " (reported)"
			else:
				verdict = " PASS" if ratio >= 0.8 and ratio <= 1.2 else " OUTSIDE"
		print("[botrun] edits: %s median t=%.1f deaths=%d/%d ratio=%s paired=%s%s" % [
			cond, med, deaths, runs.size(), ratio_text, paired_text, verdict])


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	var mid := v.size() / 2
	return float(v[mid]) if v.size() % 2 == 1 else (float(v[mid - 1]) + float(v[mid])) / 2.0


static func _join_or_dash(parts: Array) -> String:
	return ",".join(parts) if not parts.is_empty() else "-"


## "contact:n,projectile:n" sorted by kind, or "-".
static func _kinds_text(kinds: Dictionary) -> String:
	var ids: Array = kinds.keys()
	ids.sort()
	return _join_or_dash(ids.map(func(k: String) -> String: return "%s:%d" % [k, kinds[k]]))


## This run's unblocked player hits by kind (the whole run; the events: tally is the
## event window only).
func _hit_kinds() -> Dictionary:
	var kinds := {}
	for ev: Dictionary in root.get_node("RunState").run_log:
		if ev.get("event") != &"player_hit" or bool(ev.get("blocked", false)):
			continue
		var k := String(ev.get("kind", "?"))
		kinds[k] = int(kinds.get(k, 0)) + 1
	return kinds


## Skips the game's stage card if it is open (PLAN v9 2: the bot never waits on the
## paused tree). Returns the card's stage, or 0 when none was shown.
func _skip_card(game: Node) -> int:
	var card: Node = game.get(&"stage_card")
	if card == null or not card.call(&"is_open"):
		return 0
	card.call(&"skip")
	return int(card.get(&"stage"))


## The archetype a session's "fork:" enemy resolved to from the save ("-": none).
func _forked_enemy(session: Resource) -> String:
	if not (session.get(&"enemies") as Array).any(func(e: StringName) -> bool: return String(e).begins_with("fork:")):
		return "-"
	for t: StringName in session.call(&"enemy_types"):
		if not t in [&"chaser", &"shooter"]:
			return String(t)
	return "-"


func _edit_cue(cond: String) -> String:
	return "at %s: edit %s" % [edit_at, cond.replace(":", " ")]


func _run_only_condition(specs: PackedStringArray, cond: String, times := {}) -> int:
	if cond != "" and cond != "none":
		var problem: String = load("res://campaign/cue.gd").call(&"parse", _edit_cue(cond)).get(&"problem")
		if problem == "" and load("res://core/rule_db.gd").call(&"get_edit", StringName(cond.get_slice(":", 0))) == null:
			problem = "unknown edit %s" % cond
		if problem != "":
			print("[botrun] FAILED: %s" % problem)
			return 1
	var db: Node = root.get_node("CampaignDB")
	var run_state: Node = root.get_node("RunState")
	var main_script: GDScript = load("res://main.gd")
	var failures := 0
	var per_90: Array[float] = []
	var min_gap := INF
	var p3_said := 0
	var p3_heard := 0
	var ev_stats := {"reached": 0, "fully": 0, "completed": 0, "died_during": 0, "died_before": 0,
			"hits": 0, "kinds": {}, "id": ""}
	var outcomes := {}       ## outcome -> runs (M42 "deaths:")
	var durations: Array = []
	var by_enemy := {}       ## forked enemy -> [deaths, runs]
	var by_dash := {}        ## dash style -> [deaths, runs] (M42.1)
	var by_aim := {}         ## aim or move -> [deaths, runs] (M42.2)
	var all_kinds := {}      ## whole-run unblocked hits by kind
	var by_path := {}        ## live path -> [deaths, runs] (M45a)
	var path_runs: Array = []   ## {level, picks, pickups, gems, kills, id} per run with a path (M45a)
	var bus: Node = root.get_node("EventBus")
	var dash_count := {"uses": 0, "misses": 0, "fizzles": 0}
	bus.player_dashed.connect(func() -> void: dash_count.uses = int(dash_count.uses) + 1)
	bus.player_hook_missed.connect(func(_f: Vector2, _t: Vector2) -> void: dash_count.misses = int(dash_count.misses) + 1)
	bus.player_dash_fizzled.connect(func() -> void: dash_count.fizzles = int(dash_count.fizzles) + 1)
	# M46: per run, the pick offers' game times, the `add cards` time and player shots by weapon.
	var cards_run := {"offers": [], "cards_at": -1.0, "shots": {}}
	bus.pick_offered.connect(func(_o: RefCounted) -> void: (cards_run.offers as Array).append(float(run_state.game_time)))
	bus.basic_added.connect(func(id: StringName) -> void:
		if id == &"cards" and float(cards_run.cards_at) < 0.0:
			cards_run.cards_at = float(run_state.game_time))
	bus.projectile_fired.connect(func(p: Node) -> void:
		var wid := String(p.get(&"weapon_id")) if p.get(&"weapon_id") != null else ""
		if wid != "" and p.get(&"faction") == &"player":
			(cards_run.shots as Dictionary)[wid] = int((cards_run.shots as Dictionary).get(wid, 0)) + 1)
	var arsenal_runs: Array = []   ## {offers, gaps, mean, tail, fired} per Arsenal run (M46)
	var tryout_runs: Array = []    ## {swaps, leftovers, picked_at} per tryout run (M47)
	for spec in specs:
		var run_seed := int(_seed_of(spec))
		var invincible := spec.ends_with("i")
		save.call(&"go_inert")
		save.call(&"set_mascot", Change.MASCOTS[posmod(run_seed, Change.MASCOTS.size())])
		db.active = true
		if not db.jump_to(only):
			print("[botrun] FAILED: no session %s" % only)
			return failures + 1
		# --answer= (and the dash aliases) first, so the seed answers only what they leave.
		for f: StringName in answers:
			db.answer_fork(f, answers[f])
		var forked := _answer_forks(db.get_session(only), run_seed)
		_answer_path_fork(db.get_session(only), run_seed)
		main_script.set(&"next_seed", run_seed)
		var game: Node = load("res://main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await physics_frame
		_skip_card(game)
		run_state.invincible = invincible
		game.player.set_bot(true)
		if probe_arg != "":
			game.player.input.set(&"probe", StringName(probe_arg))
		dash_count.uses = 0
		dash_count.misses = 0
		dash_count.fizzles = 0
		cards_run.offers = []
		cards_run.cards_at = -1.0
		cards_run.shots = {}
		var air := 0.0
		var dash_name: String = "none" if dash_arg == "none" else String(game.player.dasher.style)
		var aim_name := "aim" if game.player.dasher.aims else "move"
		if lift > 0.0:
			game.run_loop.goal_value = lift
		var loadout: Node = game.player.get_node_or_null(^"Loadout")
		if not loadout_arg.is_empty() and loadout != null:
			_force_loadout(loadout)
		if cond != "":
			game.session_runner.drop_cues(&"edit")
			if cond != "none":
				game.session_runner.inject(_edit_cue(cond))
		if events_off:
			game.session_runner.drop_cues(&"event")
		var event_cue_at := _event_cue_at(game.session_runner)
		var opened := false
		var runner: Node = game.get(&"path_runner")
		var forced_starts := 0
		for frame in MAX_FRAMES:
			if game.debrief.is_open():
				opened = true
				break
			# M45a: --loadout= again after each path start (apply_path resets the loadout),
			# then no growth; an open pick panel is chosen from pick_rng.
			if runner != null and not loadout_arg.is_empty() and int(runner.get(&"starts")) != forced_starts:
				forced_starts = int(runner.get(&"starts"))
				_force_loadout(loadout)
				runner.call(&"freeze")
			_choose_pick(game)
			if dash_arg == "none":
				game.player.dash_locked = true   # a cue's apply_basics would unlock it
			var t0: float = run_state.game_time
			await physics_frame
			if run_state.rules.gravity_enabled and is_instance_valid(game.player) \
					and not game.player.is_on_floor():
				air += float(run_state.game_time) - t0
		if not opened:
			print("[botrun] session=%s seed=%d FAILED: no debrief" % [only, run_seed])
			failures += 1
		var rec: Dictionary = game.run_loop.record
		var fired: Array = game.reactions.fired
		var chatter := fired.filter(func(f: Dictionary) -> bool: return int(f.priority) == 1)
		var gap := INF
		for i in range(1, chatter.size()):
			gap = minf(gap, float(chatter[i].at) - float(chatter[i - 1].at))
		min_gap = minf(min_gap, gap)
		var duration := maxf(1.0, float(rec.get("duration", 1.0)))
		per_90.append(chatter.size() * 90.0 / duration)
		if cond != "":
			times[run_seed] = [duration, String(rec.get("outcome", "")) in ["lose", "died"]]
		var p3 := fired.filter(func(f: Dictionary) -> bool: return int(f.priority) == 3)
		var heard := p3.filter(func(f: Dictionary) -> bool: return String(f.text) in game.mascot.shown)
		p3_said += p3.size()
		p3_heard += heard.size()
		var landed: Array = game.rule_book.landed
		var edit_text := ""
		if cond != "":
			edit_text = " edit=%s landed=%s real=%.1f" % [cond,
					",".join(landed.map(func(l: Dictionary) -> String: return "%s@%.1f" % [l.id, l.at])),
					float(rec.get("real_duration", 0.0))]
			if cond != "none" and landed.is_empty() and duration > edit_at + 2.0:
				print("[botrun] session=%s seed=%d FAILED: %s never landed" % [only, run_seed, cond])
				failures += 1
		var event_text := ""
		if forked != "":
			event_text += " enemy=%s" % forked
			if forked == "-":
				print("[botrun] session=%s seed=%d FAILED: the fork did not resolve" % [only, run_seed])
				failures += 1
		if event_cue_at >= 0.0:
			var ev := _event_report(game, rec, event_cue_at, ev_stats)
			event_text += String(ev.text)
			if ev.failed:
				print("[botrun] session=%s seed=%d FAILED: %s" % [only, run_seed, ev.why])
				failures += 1
		# M43.2: the goal was reached during the event and waited for its end.
		if (run_state.run_log as Array).any(func(e: Dictionary) -> bool: return e.get("event") == &"goal_waited"):
			event_text += " goal_waited"
		var outcome := String(rec.get("outcome", "?"))
		var died := outcome in ["lose", "died"]
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
		durations.append(duration)
		if forked != "" and forked != "-":
			var e: Array = by_enemy.get(forked, [0, 0])
			by_enemy[forked] = [int(e[0]) + (1 if died else 0), int(e[1]) + 1]
		var dd: Array = by_dash.get(dash_name, [0, 0])
		by_dash[dash_name] = [int(dd[0]) + (1 if died else 0), int(dd[1]) + 1]
		var da: Array = by_aim.get(aim_name, [0, 0])
		by_aim[aim_name] = [int(da[0]) + (1 if died else 0), int(da[1]) + 1]
		var kinds := _hit_kinds()
		for k: String in kinds:
			all_kinds[k] = int(all_kinds.get(k, 0)) + int(kinds[k])
		var landed_text := ""   # M42: at the line's end, so check.ps1's --edits regexes keep matching
		if cond == "":
			landed_text = " landed=%s" % _join_or_dash(landed.map(
					func(l: Dictionary) -> String: return "%s@%.1f" % [l.id, l.at]))
		# M42.1: at the very end, after landed= (check.ps1 reads landed= as before).
		landed_text += " dash=%s uses=%d misses=%d fizzles=%d air=%.1f" % [dash_name, dash_count.uses,
				dash_count.misses, dash_count.fizzles, air]
		landed_text += " aim=%s" % aim_name   # M42.2: after air=, so dash=<s> uses= regexes hold
		# M44: at the very end, only where weapons are in play (every older assert holds).
		var listed: Array = run_state.session.weapons if run_state.session != null else []
		if loadout != null and is_instance_valid(loadout) and (not loadout_arg.is_empty() or not listed.is_empty()):
			landed_text += " weapons=%s" % loadout.summary()
		# M45a: at the very end, only when a path was live (every older assert holds).
		var path_text := _path_text(runner)
		landed_text += path_text
		var tryout_text := _tryout_text(runner)   # M47: right after the path fields
		landed_text += tryout_text
		if tryout_text != "":
			tryout_runs.append({"swaps": _swaps(), "leftovers": _leftover_count(),
					"picked_at": _picked_at(game.session_runner)})
		if run_state.session != null and String(run_state.session.path) != "" and runner != null \
				and String(runner.get(&"path_id")) == "":
			print("[botrun] session=%s seed=%d FAILED: no path (path %s resolved to nothing)" % [only,
					run_seed, run_state.session.path])
			failures += 1
		if path_text != "":
			var pid := String(runner.get(&"path_id"))
			var pp: Array = by_path.get(pid, [0, 0])
			by_path[pid] = [int(pp[0]) + (1 if died else 0), int(pp[1]) + 1]
			path_runs.append({"level": int(runner.call(&"level")), "picks": int(runner.get(&"picks")),
					"pickups": int(runner.get(&"pickups_taken")), "gems": int(runner.call(&"gems")),
					"enemy_shots_refused": int(run_state.get(&"enemy_shots_refused")),
					"player_shots_refused": int(run_state.get(&"player_shots_refused")),
					"kills": int(rec.get("kills", run_state.kills)), "id": pid,
					"fp": runner.call(&"fingerprint"), "heals": int(runner.call(&"heals")),
					"crates": int(runner.call(&"crates_taken"))})
		if probe_arg != "":
			landed_text += " probe=%s" % probe_arg
		# M46: Arsenal's cards, at the very end (Auto's lines are unchanged).
		if path_text != "" and runner.get(&"def") != null and runner.get(&"def").get(&"growth") == &"cards":
			var ar := _arsenal_run(cards_run, duration)
			arsenal_runs.append(ar)
			landed_text += " cards=%d offers=%s cards_fired=%d shots=%s" % [int(runner.call(&"cards")),
					_join_or_dash((cards_run.offers as Array).map(func(t: float) -> String: return "@%.1f" % t)),
					int(ar.fired), _join_or_dash(_shots_parts(cards_run.shots))]
		# M46: PLAN 4's per-seed fp=, only behind --fp (check.ps1's anchored regexes never see it).
		if fp_arg and path_text != "":
			landed_text += " fp=%s" % _fp_text(runner.call(&"fingerprint"))
		print("[botrun] session=%s seed=%d%s mascot=%s outcome=%s t=%.1f%s%s reactions=%d chatter=%d p2=%d p3=%d/%d min_gap=%s ids=%s%s" % [
			only, run_seed, " (invincible)" if invincible else "", save.call(&"mascot"), outcome,
			duration, edit_text, event_text, fired.size(), chatter.size(),
			fired.filter(func(f: Dictionary) -> bool: return int(f.priority) == 2).size(),
			heard.size(), p3.size(), "-" if gap == INF else "%.1f" % gap,
			",".join(fired.map(func(f: Dictionary) -> String: return String(f.id))), landed_text])
		game.debrief.close()
		root.remove_child(game)
		game.free()
		await process_frame
	per_90.sort()
	var median := 0.0
	if not per_90.is_empty():
		var mid := per_90.size() / 2
		median = per_90[mid] if per_90.size() % 2 == 1 else (per_90[mid - 1] + per_90[mid]) / 2.0
	print("[botrun] summary: %s x%d, chatter per 90 s median %.1f (min %.1f, max %.1f), shortest chatter gap %s, priority 3 heard %d/%d, %d failures" % [
		only, specs.size(), median, per_90.front() if not per_90.is_empty() else 0.0,
		per_90.back() if not per_90.is_empty() else 0.0, "-" if min_gap == INF else "%.1f s" % min_gap,
		p3_heard, p3_said, failures])
	var enemy_parts: Array = []
	var enemy_ids: Array = by_enemy.keys()
	enemy_ids.sort()
	for e: String in enemy_ids:
		enemy_parts.append("%s:%d/%d" % [e, by_enemy[e][0], by_enemy[e][1]])
	var dash_parts: Array = []
	var dash_ids: Array = by_dash.keys()
	dash_ids.sort()
	for d: String in dash_ids:
		dash_parts.append("%s:%d/%d" % [d, by_dash[d][0], by_dash[d][1]])
	var aim_parts: Array = []
	var aim_ids: Array = by_aim.keys()
	aim_ids.sort()
	for d: String in aim_ids:
		aim_parts.append("%s:%d/%d" % [d, by_aim[d][0], by_aim[d][1]])
	var path_parts: Array = []
	var path_ids: Array = by_path.keys()
	path_ids.sort()
	for d: String in path_ids:
		path_parts.append("%s:%d/%d" % [d, by_path[d][0], by_path[d][1]])
	print("[botrun] deaths: %s lose=%d/%d win=%d stopped=%d median_t=%.1f by_enemy=%s by_dash=%s by_aim=%s hits=%s%s%s%s" % [
		only, int(outcomes.get("lose", 0)) + int(outcomes.get("died", 0)), specs.size(),
		int(outcomes.get("win", 0)), int(outcomes.get("stopped", 0)), _median(durations),
		_join_or_dash(enemy_parts), _join_or_dash(dash_parts), _join_or_dash(aim_parts), _kinds_text(all_kinds),
		" edit=%s" % cond if cond != "" else "", " by_path=%s" % ",".join(path_parts) if not path_parts.is_empty() else "",
		" t_list=%s" % _t_list(durations) if fp_arg else ""])
	if not path_runs.is_empty():
		var col := func(key: String) -> Array: return path_runs.map(func(r: Dictionary) -> int: return int(r[key]))
		var levels: Array = col.call("level")
		var refused: Array = col.call("enemy_shots_refused")
		print("[botrun] paths: %s %s levels median=%.1f min=%d max=%d levelups=%s picks median=%.1f pickups median=%.1f gems median=%.1f kills median=%.1f per_seed_kills=%s enemy_shots_refused median=%.1f max=%d player_shots_refused median=%.1f" % [
			only, ",".join(path_ids), _median(levels), levels.min(), levels.max(),
			",".join(levels.map(func(l: int) -> String: return str(l - 1))), _median(col.call("picks")),
			_median(col.call("pickups")), _median(col.call("gems")), _median(col.call("kills")),
			",".join(col.call("kills").map(func(k: int) -> String: return str(k))),
			_median(refused), refused.max(), _median(col.call("player_shots_refused"))])
		if fp_arg:
			for fp_id: String in path_ids:
				_fp_summary(fp_id, path_runs.filter(func(r: Dictionary) -> bool: return r.id == fp_id))
		var surv := path_runs.filter(func(r: Dictionary) -> bool: return r.id == "survival")
		if not surv.is_empty():
			var parts: Array[String] = []
			for pair: Array in [["pickups_per_min", func(r: Dictionary) -> float: return float(r.fp.pickups_per_min)],
					["heals", func(r: Dictionary) -> float: return float(r.heals)],
					["dry_share", func(r: Dictionary) -> float: return float(r.fp.ammo_dry_share)],
					["crates", func(r: Dictionary) -> float: return float(r.crates)]]:
				var vals: Array = surv.map(pair[1])
				parts.append("%s median=%.2f (%.2f-%.2f)" % [pair[0], _median(vals), vals.min(), vals.max()])
			print("[botrun] survival: %s n=%d %s" % [only, surv.size(), " ".join(parts)])
	if not tryout_runs.is_empty():
		var swaps_ok := tryout_runs.filter(func(r: Dictionary) -> bool: return r.swaps == tryout_runs[0].swaps).size()
		var clean := tryout_runs.filter(func(r: Dictionary) -> bool: return int(r.leftovers) == 0).size()
		var second := _second_swap_at(tryout_runs[0].swaps)
		var picked_ok := tryout_runs.filter(func(r: Dictionary) -> bool:
			return float(r.picked_at) >= 0.0 and float(r.picked_at) < second).size()
		print("[botrun] tryout: %s swaps=%s same %d/%d leftovers=0 %d/%d picked_before=%.1f %d/%d picked_at=%s" % [
			only, _join_or_dash(tryout_runs[0].swaps), swaps_ok, tryout_runs.size(), clean, tryout_runs.size(),
			second, picked_ok, tryout_runs.size(),
			",".join(tryout_runs.map(func(r: Dictionary) -> String: return "%.1f" % float(r.picked_at)))])
	if not arsenal_runs.is_empty():
		var in_band := arsenal_runs.filter(func(r: Dictionary) -> bool: return bool(r.ok)).size()
		var fired2 := arsenal_runs.filter(func(r: Dictionary) -> bool: return int(r.fired) >= 2).size()
		var all_gaps: Array = []
		for r: Dictionary in arsenal_runs:
			all_gaps.append_array(r.gaps)
		print("[botrun] arsenal: %s offers median=%.1f per_seed=%s gaps median=%.1f min=%.1f max=%.1f per_seed_mean_gap=%s tails=%s in_band=%d/%d cards_fired>=2 %d/%d" % [
			only, _median(arsenal_runs.map(func(r: Dictionary) -> int: return int(r.offers))),
			",".join(arsenal_runs.map(func(r: Dictionary) -> String: return str(r.offers))),
			_median(all_gaps), all_gaps.min() if not all_gaps.is_empty() else 0.0,
			all_gaps.max() if not all_gaps.is_empty() else 0.0,
			",".join(arsenal_runs.map(func(r: Dictionary) -> String: return "%.1f" % float(r.mean))),
			",".join(arsenal_runs.map(func(r: Dictionary) -> String: return "%.1f" % float(r.tail))),
			in_band, arsenal_runs.size(), fired2, arsenal_runs.size()])
	if int(ev_stats.reached) + int(ev_stats.died_before) > 0:
		var reached := int(ev_stats.reached)
		var rate := float(ev_stats.died_during) / maxf(1.0, reached)
		var kinds: Array[String] = []
		for k: String in ev_stats.kinds:
			kinds.append("%s:%d" % [k, ev_stats.kinds[k]])
		print("[botrun] events: %s %s reached=%d/%d played_fully=%d/%d completed=%d died_during=%d/%d (%d%%, <=25%%: %s) died_before=%d hits_in_event=%d (%s)" % [
			only, ev_stats.id, reached, specs.size(), ev_stats.fully, reached, ev_stats.completed,
			ev_stats.died_during, reached, roundi(rate * 100.0), "PASS" if rate <= 0.25 else "FAIL",
			ev_stats.died_before, ev_stats.hits, ",".join(kinds) if not kinds.is_empty() else "-"])
	return failures


## M46: one Arsenal run's offer cadence (PLAN M46, H1): gaps from the `add cards` time
## (0 if it never came), each offer to the next; the tail is the run's end minus the last
## offer. ok = >= 3 offers, the mean gap in [35, 60] s and the tail <= 60 s. fired = cards
## that fired >= 1 player shot (H2).
static func _arsenal_run(run: Dictionary, duration: float) -> Dictionary:
	var offers: Array = run.offers
	var from := maxf(0.0, float(run.cards_at))
	var gaps: Array = []
	var last := from
	for t: float in offers:
		gaps.append(t - last)
		last = t
	var mean := 0.0
	for g: float in gaps:
		mean += g
	mean = mean / gaps.size() if not gaps.is_empty() else 0.0
	var tail := duration - last
	var fired := (run.shots as Dictionary).keys().filter(func(k: String) -> bool: return int(run.shots[k]) > 0).size()
	return {"offers": offers.size(), "gaps": gaps, "mean": mean, "tail": tail, "fired": fired,
			"ok": offers.size() >= 3 and mean >= 35.0 and mean <= 60.0 and tail <= 60.0}


static func _shots_parts(shots: Dictionary) -> Array:
	var ids: Array = shots.keys()
	ids.sort()
	return ids.map(func(k: String) -> String: return "%s:%d" % [k, int(shots[k])])


static func _t_list(durations: Array) -> String:
	var t := durations.duplicate()
	t.sort()
	return ",".join(t.map(func(d: float) -> String: return "%.1f" % d))


const FP_KEYS := ["fire_share", "menu_s", "picks_per_min", "switches_per_min", "pickups_per_min",
		"travel_tps", "mean_enemy_dist", "ammo_dry_share"]


## --fp (M46): "fire_share:0.996,menu_s:0.071,..." (the 8 values of PLAN v9 1.15).
static func _fp_text(fp: Dictionary) -> String:
	return ",".join(FP_KEYS.map(func(k: String) -> String: return "%s:%.3f" % [k, float(fp.get(k, 0.0))]))


## --fp (M46): one "fp:" line per path, each of the 8 values as median (min-max) over its runs.
func _fp_summary(path_id: String, runs: Array) -> void:
	if runs.is_empty():
		return
	var parts: Array[String] = []
	for key: String in FP_KEYS:
		var vals: Array = runs.map(func(r: Dictionary) -> float: return float((r.fp as Dictionary).get(key, 0.0)))
		parts.append("%s median=%.3f (%.3f-%.3f)" % [key, _median(vals), vals.min(), vals.max()])
	print("[botrun] fp: %s %s n=%d %s" % [only, path_id, runs.size(), " ".join(parts)])


## --loadout (M44): clear, then each weapon at exactly its rank; the first aimed one active.
func _force_loadout(loadout: Node) -> void:
	loadout.clear()
	var first_aimed := &""
	for pair: Array in loadout_arg:
		loadout.set_weapon(pair[0], pair[1])
		var def: Resource = load("res://weapons/weapon_db.gd").call(&"get_weapon", pair[0])
		if first_aimed == &"" and def.get(&"mode") == &"aimed":
			first_aimed = pair[0]
	if first_aimed != &"":
		loadout.select(first_aimed)


## With --only: answers each fork the session's enemies name, picked by the seed (an
## inert save answers none). Returns the forked archetype, "-" if it did not resolve, or
## "" when the session has no fork.
func _answer_forks(session: Resource, run_seed: int) -> String:
	var out := ""
	for e: StringName in session.get(&"enemies"):
		if not String(e).begins_with("fork:"):
			continue
		var f: Resource = root.get_node("ChangeDB").get_fork(StringName(String(e).trim_prefix("fork:")))
		var opts: Array = f.call(&"changes")
		var pick: Resource = f.call(&"answer")   # answered already (--answer=): keep it
		if pick == null:
			pick = opts[posmod(run_seed, opts.size())]
			save.call(&"ship", pick.get(&"id"), &"patch")
		out = "-"
		var types: Array = session.call(&"enemy_types")
		for t: StringName in types:
			if not t in [&"chaser", &"shooter"] and String(pick.get(&"id")).ends_with(String(t)):
				out = String(t)
	return out


## The goal-clock time of the session's event cue (-1: none).
func _event_cue_at(runner: Node) -> float:
	if not runner.call(&"has_cue", &"event"):
		return -1.0
	for c: RefCounted in runner.get(&"_cues"):
		if c.get(&"action") == &"event":
			return float(c.get(&"value"))
	return -1.0


## One seed's event: {text, failed, why}; adds to stats.
func _event_report(game: Node, rec: Dictionary, cue_at: float, stats: Dictionary) -> Dictionary:
	var out := {"text": "", "failed": false, "why": ""}
	var played: Array = game.event_player.played
	var died: bool = String(rec.get("outcome", "")) in ["lose", "died"]
	if played.is_empty():
		if died:
			stats.died_before = int(stats.died_before) + 1
			out.text = " event=- (died before)"
		else:
			out.failed = true
			out.why = "the clock passed %.0f s with no event" % cue_at
			out.text = " event=-"
		return out
	var r: Dictionary = played[0]
	stats.id = r.id
	stats.reached = int(stats.reached) + 1
	if r.skipped:
		out.text = " event=%s skipped" % r.id
		stats.fully = int(stats.fully) + 1
		return out
	var duration := float(rec.get("duration", 0.0))
	var died_during: bool = died and (bool(r.aborted) or duration <= float(r.end) + EVENT_TAIL)
	var hits := 0
	var kinds := {}
	for ev: Dictionary in root.get_node("RunState").run_log:
		if ev.get("event") != &"player_hit" or bool(ev.get("blocked", false)):
			continue
		var t := float(ev.get("time", -1.0))
		if t >= float(r.start) and t <= float(r.end) + EVENT_TAIL:
			hits += 1
			var k := String(ev.get("kind", "?"))
			kinds[k] = int(kinds.get(k, 0)) + 1
			stats.kinds[k] = int(stats.kinds.get(k, 0)) + 1
	stats.hits = int(stats.hits) + hits
	if r.completed:
		stats.completed = int(stats.completed) + 1
	if died_during:
		stats.died_during = int(stats.died_during) + 1
	if r.completed or died_during:
		stats.fully = int(stats.fully) + 1
	elif not r.aborted:
		out.failed = true
		out.why = "the event hung at step %d" % int(r.steps_done)
	else:
		out.failed = true
		out.why = "the event was aborted with the player alive"
	var kind_text: Array[String] = []
	for k: String in kinds:
		kind_text.append("%s:%d" % [k, kinds[k]])
	out.text = " event=%s@%.1f-%.1f steps=%d/%d%s%s hits_in_event=%d (%s)" % [r.id, r.start, r.end,
			r.steps_done, r.steps, " aborted" if r.aborted else "", " DIED_IN_EVENT" if died_during else "",
			hits, ",".join(kind_text) if not kind_text.is_empty() else "-"]
	return out


## Plays the debrief to its buttons the way a player would, faster: every line at once,
## a card picked by the seed when the session asks a fork. Several forks (M42.1, S3: the
## face then the dash): the k-th fork's index is posmod(int(pick_seed / the product of
## the earlier forks' option counts), n), so the first pick is as before and the second is
## not tied to it; --dash= picks its option in fork_dash. M42.2: the third (fork_dash_aim)
## is posmod(floor(pick_seed / 9), 2), so chains 1i (seed 5) and 2 (seed 6) both play aim;
## --dash-aim= picks its option. Returns the picks' ids joined by "," or "".
func _through_debrief(debrief: Node, pick_seed: int) -> String:
	var picks: Array[String] = []
	var div := 1
	for i in 6:
		debrief.finish_lines()
		if debrief.phase == &"fork":
			var options: Array = debrief.fork_options()
			var index := posmod(floori(float(pick_seed) / float(div)), options.size())
			# --answer= (and --dash= / --dash-aim=): that fork picks its named option.
			var fork_id: StringName = options[0].fork if not options.is_empty() else &""
			if answers.has(fork_id):
				for k in options.size():
					if options[k].id == answers[fork_id]:
						index = k
			div *= options.size()
			picks.append(String(options[index].id))
			debrief.pick(index)
			continue
		break
	var until := Time.get_ticks_msec() + 3000   # the buttons' input delay is real time
	while not debrief.can_choose() and Time.get_ticks_msec() < until:
		await process_frame
	return ",".join(picks)


## The campaign (PLAN v8 4): the start screen's Continue/New game, then every session to
## the end so far. Returns the number of failures.
func _run_campaign(spec: String, lines_before: int) -> int:
	var base := int(_seed_of(spec))
	var invincible := spec.ends_with("i")
	var db: Node = root.get_node("CampaignDB")
	var start: Node = load("res://ui/start_screen.tscn").instantiate()
	root.add_child(start)
	current_scene = start
	await process_frame
	if start.seed_field == null:   # M47.4: a save at S7+ opens the title (no seed row)
		start.seed_field = LineEdit.new()
		start.add_child(start.seed_field)
	start.seed_field.text = str(base)
	start.start()
	var failures := 0
	var played := 0
	var previous: Node = null
	var step := 0
	var seen := {}           ## session ids played (M42 "chain:")
	var play_sum := 0.0
	var real_sum := 0.0
	var read_sum := 0.0
	var cooked := false      ## M43.2: the cooking screen was shown (and skipped)
	while true:
		var game := await _wait_for_game(previous)
		if game == null:
			print("[botrun] campaign FAILED: the game scene never loaded (step %d)" % step)
			return failures + 1
		previous = game
		if _is_cooking_screen(game):
			# M43.2: nothing playable is left (a save past Stage 1 starts here).
			_cook_line(game)
			cooked = true
			break
		var run_state := root.get_node("RunState")
		var session: Resource = run_state.session
		if session == null:
			print("[botrun] campaign FAILED: the game runs no session")
			return failures + 1
		run_state.invincible = invincible
		game.player.set_bot(true)
		var attempt: int = db.attempt(session.id)
		var card_stage := _skip_card(game)
		var opened := false
		for frame in MAX_FRAMES:
			if game.debrief.is_open():
				opened = true
				break
			_choose_pick(game)   # M45a: an in-run pick panel, from pick_rng
			await physics_frame
		played += 1
		step += 1
		if not opened:
			print("[botrun] session=%s FAILED: no debrief after %d frames" % [session.id, MAX_FRAMES])
			return failures + 1
		var pick := await _through_debrief(game.debrief, base + step)
		var outcome: StringName = game.debrief.outcome
		var choices: Array = game.debrief.choices()
		var choice: String = choices[0]
		if outcome == &"died" and attempt > 1:
			choice = "Move on"
		var rec: Dictionary = game.run_loop.record
		var version_before: String = load("res://core/save_game.gd").call(&"version").label()
		var line := "[botrun] session=%s attempt=%d%s outcome=%s t=%.1f real=%.1f kills=%d hits=%d said=%d cues=%d choice=%s" % [
			session.id, attempt, " (invincible)" if invincible else "", outcome, rec.duration,
			rec.real_duration, rec.kills, game.session_runner.hits, game.session_runner.line_count(),
			game.session_runner.fired_count(), choice.to_snake_case()]
		line += " reactions=%d" % game.reactions.fired.size()
		line += " edits=%d" % game.rule_book.landed.size()
		var played_events: Array = game.event_player.played_ids()
		line += " events=%s" % (",".join(played_events) if not played_events.is_empty() else "-")
		# M42: after events= (check.ps1 reads "edits=N events=" side by side).
		line += " enemy=%s" % _forked_enemy(session)
		line += " landed=%s" % _join_or_dash(game.rule_book.landed.map(func(l: Dictionary) -> String: return String(l.id)))
		seen[session.id] = true
		play_sum += float(rec.duration)
		real_sum += float(rec.real_duration)
		game.debrief.next_seed = base * 100 + step
		if not game.debrief.choose(choice):
			print(line + " FAILED: could not choose")
			return failures + 1
		if game.debrief.is_open() and game.debrief.phase != &"done":
			# Move on with a fork to ask: it comes now, then Next moves on.
			pick = await _through_debrief(game.debrief, base + step)
			if not game.debrief.choose(game.debrief.choices()[0]):
				print(line + " FAILED: could not move on after the fork")
				return failures + 1
		if pick != "":
			line += " pick=" + pick
			read_sum += FORK_SECONDS * pick.split(",").size()
		read_sum += _read_estimate(game)
		var last: bool = db.is_done()   # the title screen comes next
		line += " version=%s->%s" % [version_before, load("res://core/save_game.gd").call(&"version").label()]
		if card_stage > 0:
			line += " card=%d" % card_stage   # PLAN v9 2: last, so the Stage 1 lines stay byte-identical
		line += _path_text(game.get(&"path_runner"))   # M45a: after card=, only with a live path
		line += _tryout_text(game.get(&"path_runner"))   # M47: a tryout's swaps and leftovers
		print(line)
		if last:
			break
		if max_sessions > 0 and played >= max_sessions:
			break
		if step > 50:
			print("[botrun] campaign FAILED: more than 50 sessions played")
			return failures + 1
	# M43.2: after the last playable session, the cooking screen (when a session is
	# cooking), then the title.
	var early: bool = max_sessions > 0 and played >= max_sessions and not db.is_done()
	if not cooked and not early:
		for f in 300:
			await process_frame
			if current_scene != null and current_scene != previous and _is_cooking_screen(current_scene):
				_cook_line(current_scene)
				break
			if current_scene != null and current_scene.has_method(&"refresh_campaign"):
				break
	print("[botrun] chain: sessions=%d attempts=%d play=%.1f real=%.1f read≈%.1f total≈%.1f" % [
		seen.size(), played, play_sum, real_sum, read_sum, play_sum + read_sum])
	# The title screen comes back after the last session (not after --max-sessions).
	for f in (0 if early else 300):
		await process_frame
		if current_scene != null and current_scene.get(&"run_loop") == null and current_scene.has_method(&"refresh_campaign"):
			break
	if not early and (not current_scene or not current_scene.has_method(&"refresh_campaign")):
		print("[botrun] campaign FAILED: no title screen after the last session")
		failures += 1
	var added := _line_count() - lines_before
	var lines := 0
	var text := FileAccess.get_file_as_string(LOG).strip_edges().split("\n")
	for l in text.slice(maxi(0, text.size() - added)):
		var d: Variant = JSON.parse_string(l)
		if d is Dictionary and d.get("type") == "campaign":
			lines += 1
	if lines != played:
		print("[botrun] telemetry: expected %d campaign lines, found %d" % [played, lines])
		failures += 1
	var state: Dictionary = save.call(&"state")
	print("[botrun] save: %s version=%s campaign=%s shipped=%s" % [save_arg if save_arg != "" else "in memory",
			save.call(&"version").label(), JSON.stringify(state.campaign), JSON.stringify(state.shipped)])
	return failures


## --draft (M45a): the draft session joins this process's list at cooking_index(), before
## the first cooking session, so a jump to it is not clamped back to the cooking one.
func _insert_draft() -> bool:
	if not campaign or only == &"":
		print("[botrun] FAILED: --draft needs --campaign --only=<id>")
		return false
	var path := draft_arg if draft_arg.begins_with("res://") else "res://campaign/drafts/%s.tres" % draft_arg
	var d: Resource = load(path) if ResourceLoader.exists(path) else null
	if d == null or d.get(&"id") == null:
		print("[botrun] FAILED: no draft session at %s" % path)
		return false
	var db: Node = root.get_node("CampaignDB")
	var problems: Array = d.call(&"problems")
	if not problems.is_empty():
		print("[botrun] FAILED: draft %s: %s" % [path, "; ".join(problems)])
		return false
	var at: int = db.call(&"cooking_index")
	(db.get(&"campaign").get(&"sessions") as Array).insert(at, d)
	print("[botrun] draft %s inserted at %d" % [d.get(&"id"), at])
	return true


## M47: on a tryout, " swaps=<id>@<t>,... leftovers=<n>" (else "").
func _tryout_text(runner: Node) -> String:
	var session: Resource = root.get_node("RunState").session
	if runner == null or session == null or not session.get(&"tryout"):
		return ""
	return " swaps=%s leftovers=%d" % [_join_or_dash(_swaps()), _leftover_count()]


func _swaps() -> Array:
	var out: Array = []
	for e: Dictionary in root.get_node("RunState").run_log:
		if e.get("event") == &"path_swapped":
			out.append("%s@%.1f" % [e.get("to", ""), float(e.get("time", 0.0))])
	return out


func _leftover_count() -> int:
	var n := 0
	for e: Dictionary in root.get_node("RunState").run_log:
		if e.get("event") == &"path_leftovers" and not (e.get("left", []) as Array).is_empty():
			n += 1
	return n


## The game time the session's `picked` say cue fired (-1: never).
func _picked_at(runner: Node) -> float:
	var cues: Array = runner.get(&"_cues")
	for e: Dictionary in root.get_node("RunState").run_log:
		if e.get("event") == &"cue" and int(e.get("index", -1)) < cues.size() \
				and cues[int(e.index)].get(&"when") == &"picked":
			return float(e.get("time", -1.0))
	return -1.0


static func _second_swap_at(swaps: Array) -> float:
	return float(String(swaps[1]).get_slice("@", 1)) if swaps.size() > 1 else INF


## M47 (C2.9): --only answers the session's path fork too (by the seed; an --answer= for it
## came first), so a fork:fork_path session never plays with no path.
func _answer_path_fork(session: Resource, run_seed: int) -> void:
	var fork_id := String(session.get(&"path")).trim_prefix("fork:").get_slice("@", 0)
	if not String(session.get(&"path")).begins_with("fork:"):
		return
	var f: Resource = root.get_node("ChangeDB").get_fork(StringName(fork_id))
	if f == null or f.call(&"answer") != null:
		return
	var opts: Array = f.call(&"changes")
	save.call(&"ship", opts[posmod(run_seed, opts.size())].get(&"id"), &"patch")


## The PathRunner's line fields (M45a): " path=<id> level=n picks=n pickups=n", or "" when
## no path was live.
static func _path_text(runner: Node) -> String:
	if runner == null or int(runner.get(&"starts")) == 0:
		return ""
	var id := String(runner.get(&"path_id"))
	return " path=%s level=%d picks=%d pickups=%d" % [id if id != "" else "off", int(runner.call(&"level")),
			int(runner.get(&"picks")), int(runner.get(&"pickups_taken"))]


## An open pick panel gets a card from RunState.pick_rng (PLAN v9 4). True if it chose.
func _choose_pick(game: Node) -> bool:
	var panel: Node = game.get(&"pick_panel")
	if panel == null or not panel.call(&"can_choose"):
		return false
	var n: int = (panel.get(&"offer").get(&"cards") as Array).size()
	panel.call(&"choose", pick_card(root.get_node("RunState").get(&"pick_rng"), n, probe_arg))
	return true


## The card the bot takes out of `n`: a pick_rng draw; --probe=first_pick (M46) takes card 0
## but still consumes this draw. Only this draw is kept: PickOffer.draw's rolls depend on the
## hand's candidates, so later offers match the default run only while the hands match.
static func pick_card(rng: RandomNumberGenerator, n: int, probe: String) -> int:
	var drawn := rng.randi_range(0, n - 1)
	return 0 if probe == "first_pick" else drawn


## --session-set (M42): each session it names becomes a copy with the field set, in
## CampaignDB's list for this process (the game scene reads its session from there), so
## the knob is exactly the field the .tres ships. Without a <session id>. prefix it
## applies to the --only session, or to every session in the chain. Returns false (and
## says why) on a bad entry.
func _apply_session_set() -> bool:
	if not campaign:
		print("[botrun] FAILED: --session-set needs --campaign")
		return false
	var sessions: Array = root.get_node("CampaignDB").get(&"campaign").get(&"sessions")
	var copies := {}   ## index -> the session's copy
	for entry in session_set:
		var at := entry.find("=")
		var key := entry.left(at) if at > 0 else ""
		var target := String(only)
		if key.contains("."):
			target = key.get_slice(".", 0)
			key = key.get_slice(".", 1)
		var text := entry.substr(at + 1) if at > 0 else ""
		if not key in SESSION_KEYS or not text.is_valid_float():
			print("[botrun] FAILED: bad --session-set %s (keys: %s)" % [entry, ", ".join(SESSION_KEYS)])
			return false
		var found := false
		for i in sessions.size():
			if target != "" and String(sessions[i].get(&"id")) != target:
				continue
			if not copies.has(i):
				copies[i] = sessions[i].duplicate()
				sessions[i] = copies[i]
			set_session_field(copies[i], key, float(text))
			found = true
		if not found:
			print("[botrun] FAILED: --session-set %s: no session %s" % [entry, target])
			return false
		print("[botrun] session-set %s: %s = %s" % [target if target != "" else "every session", key, float(text)])
	return true


## Sets one --session-set field on a session's copy. M47.2: goal_value also clears the
## copy's goal_by_path (it would shadow the set value on that path: S8 Survival's 90 s).
static func set_session_field(copy: Resource, key: String, value: float) -> void:
	copy.set(key, value)
	if key == "goal_value" and not (copy.get(&"goal_by_path") as Dictionary).is_empty():
		copy.set(&"goal_by_path", Dictionary({}, TYPE_STRING_NAME, &"", null, TYPE_FLOAT, &"", null))
		print("[botrun] %s: goal_value=%s replaces goal_by_path" % [copy.get(&"id"), value])


## Estimated seconds a player spends reading this attempt's lines (M42 "chain:"): the
## intro and cue lines said or still queued, and the debrief's lines shown, each its
## bubble time plus its length at READ_CPS characters a second.
func _read_estimate(game: Node) -> float:
	var texts: Array = (game.session_runner.said as Array).duplicate()
	for l: RefCounted in game.session_runner.queued_lines():
		texts.append(String(l.get(&"text")))
	texts.append_array(game.debrief.said)
	var runner_script: GDScript = load("res://campaign/session_runner.gd")
	var out := 0.0
	for t: String in texts:
		out += float(runner_script.call(&"read_seconds", t)) + t.length() / READ_CPS
	return out


## "name=value" onto the Tuning autoload; value is parsed as a Godot literal.
func _override(pair: String) -> bool:
	var at := pair.find("=")
	if at <= 0:
		return false
	var tuning: Object = root.get_node("Tuning")
	var key := pair.left(at)
	if key.contains("."):   # <mutation id>.<var>: on its take for the run's genre (PLAN v5 1.2)
		# Untyped: naming Mutation here would compile it before the autoloads exist.
		var m: Object = root.get_node("MutationDB").get_mutation(StringName(key.get_slice(".", 0)))
		key = key.get_slice(".", 1)
		if m == null:
			return false
		var take: Object = m.call(&"take_for", root.get_node("RunState").genre)
		tuning = take if take != null else m
	var value: Variant = str_to_var(pair.substr(at + 1))
	if not key in tuning or value == null:
		return false
	var current: Variant = tuning.get(key)
	if current is Array and value is Array:
		(current as Array).assign(value)
	elif current is float and (value is int or value is float):
		tuning.set(key, float(value))
	elif typeof(current) == typeof(value):
		tuning.set(key, value)
	else:
		return false
	print("[botrun] tuning %s = %s" % [pair.left(at), tuning.get(key)])
	return true


func _seed_of(spec: String) -> String:
	return spec.trim_suffix("i")


func _wait_for_game(previous: Node) -> Node:
	for f in 300:
		await process_frame
		var scene := current_scene
		if scene != null and scene != previous and _is_cooking_screen(scene):
			return scene
		if scene != null and scene != previous and scene.get(&"run_loop") != null:
			await physics_frame
			return scene
	return null


## The cooking screen (M43.2): where the campaign stands when its next session is cooking.
func _is_cooking_screen(scene: Node) -> bool:
	return scene.scene_file_path == "res://ui/cooking_screen.tscn"


## Prints the cooking screen's line and skips its card (the bot never waits on the paused
## tree): "[botrun] cooking: session=<id> stage=<n> lines=<k> building=<vX> then=to_be_continued card=<n>".
func _cook_line(screen: Node) -> void:
	var card: Node = screen.get(&"card")
	var session: Resource = screen.get(&"session")
	if card == null or session == null:
		print("[botrun] cooking: FAILED: no card")
		return
	card.call(&"skip")
	print("[botrun] cooking: session=%s stage=%d lines=%d building=%s then=%s card=%d" % [session.get(&"id"),
			int(session.get(&"stage")), (session.get(&"cooking") as PackedStringArray).size(),
			String(card.get(&"building")), String(card.call(&"ending_text")), int(card.get(&"stage"))])


## Plays one run to its report. Returns the summary line, or "" on timeout.
func _play(game: Node, run_seed: int, invincible: bool) -> String:
	var run_state := root.get_node("RunState")
	if run_state.run_seed != run_seed:
		return "[botrun] seed=%d FAILED: game started with seed %d" % [run_seed, run_state.run_seed]
	run_state.invincible = invincible
	game.player.set_bot(true)
	if start_big != &"":
		run_state.swap_big(root.get_node("MutationDB").get_mutation(start_big))
	if start_apply != &"":
		run_state.apply(root.get_node("MutationDB").get_mutation(start_apply))
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	for frame in MAX_FRAMES:
		if game.report.is_open():
			var rec: Dictionary = game.run_loop.record
			var picks: Array = (rec.prompts as Array).map(func(p: Dictionary) -> String: return p.pick)
			var big_prompts := (rec.big_offers as Array).size()
			var fail := " FAILED: %d BIG prompts" % big_prompts if big_prompts > 0 else ""
			if rec.reverts_used > 0:
				fail += " FAILED: %d rollbacks" % rec.reverts_used
			return "[botrun] seed=%d%s%s outcome=%s time=%.1fs real=%.1fs stage=%s genre=%s version=%s build=%s %s kills=%d prompts=%s big=%s genres=%s hits=%s kinds=%s reverts=%d ai=%s rc=%s agenda=%d first_offer_%s" % [
				run_seed, " (invincible)" if invincible else "", fail, rec.outcome, rec.duration, rec.real_duration,
				"%d/%d" % [rec.stages.reached, rec.stages.total], rec.genre, rec.game_version, rec.version, load("res://core/unlocks.gd").call(&"summary"), rec.kills, picks, rec.final_big if rec.final_big != "" else "-", rec.genre_seconds,
				rec.genre_hits, rec.genre_hits_by_kind, rec.reverts_used, _ai_line(rec), rec.reached_release_candidate,
				rec.agenda_cards, _first_line(game)]
		if game.prompt_panel.can_choose():
			game.prompt_panel.choose(rng.randi_range(0, game.prompt_panel.offer.cards.size() - 1))
		await physics_frame
	return ""


## Answers a dev session (PLAN v5 4.6, v6 5): a card at random from the seed, or, where
## Rework is offered, a random swap (--rework-chance; 50/50 against "Keep it as it is"
## in a REWORK-only session); then "Play" on the patch notes (or on a session with
## nothing to ship). Returns the summary line.
func _answer_session(flow: Node, run_seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7919 + 17
	var session: RefCounted = flow.session
	var rework_only: bool = session.shape == &"rework"
	for f in 600:
		if flow.screen.can_pick():
			if flow.screen.has_rework_card() and rng.randf() < rework_chance:
				flow.screen.open_rework()
			else:
				flow.screen.pick(rng.randi_range(0, (session.cards as Array).size() - 1))
		elif flow.screen.list_ready():
			var targets: Array = flow.screen.rework_targets()
			if rework_only and rng.randf() < 0.5:
				flow.screen.press_list_button()   # keep it as it is
				return _session_line(session)
			var t: Array = targets[rng.randi_range(0, targets.size() - 1)]
			flow.screen.rework(t[0], t[1])
		elif flow.screen.input_ready() and (session.cards as Array).is_empty() and not rework_only \
				and not flow.screen.list_open():
			if flow.screen.has_rework_card() and rng.randf() < rework_chance:
				flow.screen.open_rework()   # IMPLEMENT: the AI's patch ships anyway
			else:
				flow.screen.play()
		elif flow.notes.is_open():
			var line := _session_line(session)
			flow.notes.play()
			return line
		await process_frame
	return "[botrun] session FAILED: never finished (%s)" % [session.shape if session else "no session"]


func _session_line(session: RefCounted) -> String:
	var e: Dictionary = session.log_entry()
	return "[botrun] session=%d after_run=%d kind=%s fork=%s cards=%s pick=%s shelved=%s agenda=%s ai_ship=%s ai_fork=%s rework=%s kept=%s version=%s->%s" % [
		session.number, session.after_run, e.shape, e.fork if e.fork != "" else "-", e.cards,
		e.pick if e.pick != "" else "-", e.shelved, e.agenda if e.agenda != "" else "-",
		e.ai_ship if e.ai_ship != "" else "-", e.ai_fork if e.ai_fork != "" else "-",
		e.rework if e.rework != "" else "-", e.kept,
		session.version_before.label(), session.version_after().label()]


## "id+@time,id-rollback@time" from the record's ai_events; "-" when there are none.
func _ai_line(rec: Dictionary) -> String:
	var parts: Array[String] = []
	for e: Dictionary in rec.get("ai_events", []):
		parts.append("%s%s@%.0f" % [e.id, "+" if e.op == "add" else "-" + String(e.reason), e.time])
	return ",".join(parts) if not parts.is_empty() else "-"


## The save the runs play from (see the header). The start screen is told not to make
## the real save live. Returns false (and says why) on a bad combination.
func _set_up_save() -> bool:
	save = load("res://core/save_game.gd")
	var start_script: GDScript = load("res://ui/start_screen.gd")
	start_script.save_live = false
	start_script.legacy_loop = not campaign   # the v6 run loop unless --campaign (PLAN v8)
	if save_arg != "" and save_arg == save.DEFAULT_PATH:
		print("[botrun] FAILED: --save must not be the real save (%s)" % save_arg)
		return false
	if keep_save:
		if save_arg == "":
			print("[botrun] FAILED: --keep-save needs --save=<path>")
			return false
		save.call(&"go_live", save_arg, fresh)
	elif save_arg != "" or fresh:
		save.call(&"use_snapshot", save_arg, fresh)
	else:
		save.call(&"go_inert")
	if save.read_only:
		print("[botrun] FAILED: %s is from a newer build" % save_arg)
		return false
	for id in ship_ids:
		var c: Resource = root.get_node("ChangeDB").get_change(StringName(id))
		if c == null or save.unlock_all:
			print("[botrun] FAILED: cannot ship %s (%s)" % [id, "inert save" if c else "no such change"])
			return false
		save.call(&"ship", c.id, c.bump)
	print("[botrun] save: %s" % ("inert" if save.unlock_all else "%s%s%s" % [
		save_arg if save_arg != "" else "in memory", " (fresh)" if fresh else "",
		", chained" if keep_save else ", read-only"]))
	return true


func _line_count() -> int:
	if not FileAccess.file_exists(LOG):
		return 0
	var text := FileAccess.get_file_as_string(LOG).strip_edges()
	return 0 if text == "" else text.split("\n").size()


func _first_line(game: Node) -> String:
	for e: Dictionary in root.get_node("RunState").run_log:
		if e.event == &"prompt":
			return "agenda=%s" % [e.get("agenda", [])]
	return ""

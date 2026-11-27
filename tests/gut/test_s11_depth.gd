extends GutTest
## M51 (PLAN v9 1.9, 1.12, 3.2 S11, 3.5): S11 "Depth", without the event. The session as data
## (the last one; S10 now offers Next; S11 asks fork_hud), fork_hud's three text-only cards,
## the three new enemies mixed in through spawn_weights (a weighted variant spawns its base with
## its data and its pack), part 3's slower spawns (part_rate), edit_enemies_flee (walkers turn
## away and come back exactly), the orbit on every path with Survival's battery, Auto's well
## behind its tagged say, the event cue as a logged no-op, and PLAN 3.5's S11 rows. Every game
## is jumped to on an inert save; time is moved, never waited on.

const TEST_LOG := "user://save_s11_depth_test/runs.jsonl"
const S11 := &"s2_05_depth"
const S10 := &"s2_04_levels"
const PATHS: Array[StringName] = [&"arsenal", &"auto", &"survival"]
const CHASER := preload("res://entities/enemy_chaser.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")

var game: Main


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	Skins.disabled = false
	Skins.use(null)


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	RunState.session = null
	SaveGame.go_inert()
	Skins.disabled = false
	Skins.use(null)
	RunState.reset(0)
	RunState.world = null


func _jump(id: StringName, p: StringName, layout: StringName = &"layout_gauntlet", invincible := true) -> Main:
	SaveGame.go_inert()
	assert_true(CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p)))
	if layout != &"":
		assert_true(CampaignDB.answer_fork(&"fork_layout", layout))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	RunState.invincible = invincible
	return g


func _s11(p: StringName = &"arsenal", layout: StringName = &"layout_gauntlet") -> Main:
	return await _jump(S11, p, layout)


## The live part's clock at `seconds` (room N at s cues read it).
func _room_at(seconds: float) -> void:
	game.run_loop.stage_started_at = RunState.game_time - seconds - 0.01
	await wait_physics_frames(3)


func _quiet() -> void:
	game.spawner.enabled = false
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(3)


## This part's share is out and dead, then the beat skipped: the next part plays.
func _next_part() -> void:
	var loop := game.run_loop
	game.spawner.spawned = game.spawner.budget
	loop.stage_started_at = RunState.game_time - 200.0
	await wait_physics_frames(4)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(4)
	loop._clear_until = RunState.game_time
	await wait_physics_frames(3)


func _variant(id: StringName) -> Array:
	return get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool:
		return e.get(&"variant") == id and not e.is_queued_for_deletion())


func _logged(event: StringName) -> Array:
	return RunState.run_log.filter(func(r: Dictionary) -> bool: return r.event == event)


func _debrief() -> DebriefScreen:
	var d := DebriefScreen.new()
	add_child_autofree(d)
	d.input_delay = 0.0
	return d


# --- Data ----------------------------------------------------------------------------------

func test_s11_follows_s10_and_is_the_last() -> void:
	assert_eq(CampaignDB.index_of(S11), 11)
	assert_eq(CampaignDB.size(), 12, "S11 is the last session")
	assert_eq(CampaignDB.session(11).id, S11)
	var s := CampaignDB.get_session(S11)
	assert_eq(s.problems(), [] as Array[String])
	assert_eq(CampaignDB.problems(), [] as Array[String], "nothing in the campaign is unbuilt or wrong")
	assert_eq([s.title, s.stage, s.goal, s.stages, s.fork, s.bump, s.skin, s.hud], ["Depth", 2, SessionDef.CLEAR,
			&"fork:fork_layout", &"fork_hud", &"patch", &"pixel", &""])
	assert_eq(s.weapons, [&"pistol", &"shotgun", &"laser", &"launcher", &"orbit"] as Array[StringName])
	assert_eq(s.known, [&"shotgun", &"laser", &"launcher", &"nova", &"haste", &"area", &"might"] as Array[StringName])
	assert_eq(s.enemies, [&"chaser", &"shooter", &"fork:fork_enemy", &"shielder", &"sniper", &"swarm"] as Array[StringName])
	assert_eq(s.spawn_weights, {&"shielder": 0.15, &"sniper": 0.15, &"swarm": 0.15})
	assert_eq(s.part_rate, PackedFloat32Array([1.0, 1.0, 0.8]))
	assert_true(s.fresh_start)
	assert_gt(s.time_limit, 0.0, "a hidden cap")
	for p in PATHS:
		assert_gt(s.enemy_total_for(p), 0, String(p))
	for c in s.cue_list():
		assert_eq(c.problem, "", c.source)
		assert_ne(c.action, &"spawn", "no scripted spawns: the three come from the weights (%s)" % c.source)
	# The chain: S10 now offers Next, S11 is "to be continued".
	var d := _debrief()
	d.open(CampaignDB.get_session(S10), &"win", 0)
	d.finish_lines()
	assert_eq(d.choices(), [DebriefScreen.NEXT], "S10 is no longer the last (M51)")
	d.close()
	# One patch bump: S10 ends on v0.8.3 (check.ps1's chain), S11 on v0.8.4.
	var v := GameVersion.make(0, 8, 3)
	assert_true(v.bump(s.bump))
	assert_eq(v.label(), "v0.8.4")


func test_fork_hud_is_campaign_data() -> void:
	var f := ChangeDB.get_fork(&"fork_hud")
	assert_not_null(f)
	assert_true(f.campaign)
	assert_eq(f.question, "How should the screen show things?")
	assert_eq(f.options, [&"hud_clean", &"hud_arcade", &"hud_onyou"] as Array[StringName])
	var want := {&"hud_clean": [&"clean", "Clean. Small numbers in a corner.", "Clean. Just what you need."],
			&"hud_arcade": [&"arcade", "Arcade. Big bars, a score, a combo.", "Arcade! Numbers go up!"],
			&"hud_onyou": [&"onyou", "On you. No boxes; it's all around you.", "On you. Look at you. Literally."]}
	for id: StringName in want:
		var c := ChangeDB.get_change(id)
		assert_not_null(c, String(id))
		assert_eq(c.kind, &"hud")
		assert_eq(c.fork, &"fork_hud")
		assert_eq([c.take.id, c.pitch, c.take.line], want[id], String(id))
		assert_null(c.take.image, "%s: a text-only card (no HudStyle to preview yet)" % id)
		assert_eq(ChangeDB.problems(c), [] as Array[String], String(id))
	assert_true(&"hud" in Change.KINDS)
	assert_eq(Change.HUDS, [&"clean", &"arcade", &"onyou"] as Array[StringName])
	var bad := Change.new()
	bad.id = &"hud_probe"
	bad.kind = &"hud"
	assert_string_contains("
".join(ChangeDB.problems(bad)), "Hud change 'hud_probe' has no take naming a style")
	bad.take = MockupTake.new()
	bad.take.id = &"neon"
	assert_string_contains("
".join(ChangeDB.problems(bad)), "no take naming a style")


func test_s11_asks_fork_hud_after_its_pitch() -> void:
	var s := CampaignDB.get_session(S11)
	assert_eq(s.asked_forks(), [&"fork_hud"] as Array[StringName])
	assert_eq(Array(s.notes), ["Three new regulars", "Spinning shields"])
	var debrief := Array(s.debrief)
	assert_eq(debrief.back(), "thinking: You keep looking for your health. Let me fix the screen.", "the pitch is last")
	assert_false(" ".join(debrief).contains("event:"), "the event lines come with the event (M52)")
	var d := _debrief()
	d.open(s, &"win", 0)
	d.finish_lines()
	var pitch := d.said.find("You keep looking for your health. Let me fix the screen.")
	assert_gt(pitch, 0, "the pitch is said")
	assert_eq(d.said.slice(pitch + 1), ["How should the screen show things?"] as Array[String], "then the question")
	assert_true(d.said.has("All three at once. You handled it."))
	assert_eq(d.fork().id, &"fork_hud")
	assert_eq(d.fork_options().map(func(c: Change) -> StringName: return c.id),
			[&"hud_clean", &"hud_arcade", &"hud_onyou"])
	d.close()
	d = _debrief()
	d.open(s, &"lose", 2)
	d.finish_lines()
	assert_true(d.said.has("That's on me."))
	d.close()
	var intro := " | ".join(Array(s.intro))
	assert_string_contains(intro, "happy: The three new ones are regulars now. All mixed in.")
	assert_string_contains(intro, "died_in:s2_04_levels worried: The level got you last time. This one's kinder. Mostly.")


# --- The three enemies, mixed in -------------------------------------------------------------

func test_weights_spawn_the_three_variants() -> void:
	await _s11(&"arsenal")
	await _quiet()
	var sp := game.spawner
	assert_eq(TopdownGenre.spawn_weights_for(RunState.session), {&"shielder": 0.15, &"sniper": 0.15, &"swarm": 0.15},
			"the variants stay in the spawner's weights")
	sp.budget = -1
	sp.weights = {&"swarm": 0.999999}
	var before := sp.spawned
	assert_not_null(sp.spawn_one())
	await wait_physics_frames(3)
	assert_eq(sp.spawned, before + 1, "a pack is one budget unit")
	assert_eq(_variant(&"swarm").size(), 5, "a weighted swarm comes as its pack of five")
	for e: EnemyWalker in _variant(&"swarm"):
		assert_eq([e.health.max_hp(), e.size_mult], [1.0, 0.6])
	sp.weights = {&"shielder": 0.999999}
	assert_not_null(sp.spawn_one())
	await wait_physics_frames(3)
	assert_eq(_variant(&"shielder").size(), 1)
	assert_not_null(_variant(&"shielder")[0].get_node_or_null("ShieldArc"), "the shielder with its arc")
	assert_eq(String(_variant(&"shielder")[0].get(&"archetype")), "tank", "on its tank base")
	sp.weights = {&"sniper": 0.999999}
	assert_not_null(sp.spawn_one())
	await wait_physics_frames(3)
	assert_eq(_variant(&"sniper").size(), 1)
	assert_not_null(_variant(&"sniper")[0].get_node_or_null("SniperLine"), "the sniper with its line")
	assert_eq(sp.spawned, before + 3)


func test_base_weights_draw_as_before() -> void:
	# The spawner's refactor (variants through one helper) leaves a base pick as it was: one
	# enemy of the base scene, no variant, no pack (S5's weights; its hash is the gate).
	await _s11(&"arsenal")
	await _quiet()
	var sp := game.spawner
	sp.budget = -1
	sp.weights = {&"tank": 0.999999}
	assert_not_null(sp.spawn_one())
	await wait_physics_frames(3)
	var all := get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool: return not e.is_queued_for_deletion())
	assert_eq(all.size(), 1)
	assert_eq([String(all[0].get(&"archetype")), String(all[0].get(&"variant"))], ["tank", ""])
	var s5 := CampaignDB.get_session(&"s1_05_wrong")
	for k: Variant in TopdownGenre.spawn_weights_for(s5):
		assert_true(Spawner.SCENES.has(k), "S5 weights bases only: %s" % k)


func test_part_rate_slows_the_third_part() -> void:
	await _s11(&"arsenal", &"layout_gauntlet")
	var loop := game.run_loop
	var set := loop.stages
	assert_eq(set.size(), 3)
	assert_almost_eq(game.spawner.phase_rate, set.stage(0).spawn_rate * 1.3, 0.001, "part 1 at the session's rate")
	await _next_part()
	assert_eq(loop.stage_index, 1)
	assert_almost_eq(game.spawner.phase_rate, set.stage(1).spawn_rate * 1.3, 0.001, "part 2 too")
	await _next_part()
	assert_eq(loop.stage_index, 2)
	assert_almost_eq(game.spawner.phase_rate, set.stage(2).spawn_rate * 1.3 * 0.8, 0.001, "part 3 is a breather")
	assert_almost_eq(game.spawner.phase_cap, set.stage(2).spawn_cap * 1.3, 0.001, "the cap is not slowed")
	var s := SessionDef.new()
	s.id = &"probe"
	s.stage = 2
	s.goal = SessionDef.CLEAR
	s.enemy_total = 10
	s.stages = &"gauntlet"
	s.part_rate = PackedFloat32Array([1.0, 0.8])
	assert_string_contains(str(s.problems()), "part_rate")
	s.part_rate = PackedFloat32Array([1.0, 0.0, 1.0])
	assert_string_contains(str(s.problems()), "part_rate")
	s.part_rate = PackedFloat32Array([1.0, 1.0, 0.8])
	assert_false(str(s.problems()).contains("part_rate"))


# --- edit_enemies_flee -------------------------------------------------------------------------

func test_enemies_flee_turns_walkers_away_and_back() -> void:
	var edit := RuleDB.get_edit(&"edit_enemies_flee")
	assert_not_null(edit)
	assert_eq(RuleDB.problems(edit), [] as Array[String])
	assert_eq([edit.duration, edit.target], [10.0, &"enemies"])
	assert_eq([edit.warn().text, edit.done().text], ["What if they were scared of you?", "Brave again. Sorry."])
	await _s11(&"arsenal", &"layout_gauntlet")
	await _quiet()
	game.session_runner.set_physics_process(false)
	var here := game.player.global_position
	var chaser := RunState.spawn(CHASER, game.arena.free_tile_near(here + Vector2(240, 0))) as EnemyWalker
	var shooter := RunState.spawn(SHOOTER, game.arena.free_tile_near(here + Vector2(-300, 0))) as Node2D
	await wait_physics_frames(3)
	var away := func() -> float: return chaser.mover.wish.dot((chaser.global_position - game.player.global_position).normalized())
	assert_lt(away.call(), 0.0, "it comes for the player")
	assert_eq(RunState.rules.enemies_flee, 0)
	assert_true(RunState.add_ai(edit, &"edit"))
	await wait_physics_frames(2)
	assert_eq(RunState.rules.enemies_flee, 1)
	game.player.global_position = here
	assert_gt(away.call(), 0.0, "scared: it walks away")
	var waited := 0
	while not shooter.call(&"is_winding_up") and waited < 400:
		await wait_physics_frames(1)
		waited += 1
	assert_true(shooter.call(&"is_winding_up"), "a shooter still shoots")
	# M51 review: past Tuning.stuck_time of fleeing, the stuck detector starts no wander (it
	# would outlive the edit and burn gameplay_rng draws).
	await wait_physics_frames(int(Tuning.stuck_time * 60.0) + 30)
	assert_eq(RunState.rules.enemies_flee, 1, "still scared")
	assert_eq(float(chaser.get(&"_wander_left")), 0.0, "no wander while fleeing")
	RunState.remove_ai(edit, &"expired")
	await wait_physics_frames(2)
	assert_eq(RunState.rules.enemies_flee, 0, "exactly back")
	assert_lt(away.call(), 0.0, "brave again")


# --- The event cue: a placeholder until M52 ---------------------------------------------------

func test_the_event_cue_is_a_placeholder() -> void:
	assert_true(&"gravity_through_screen" in Cue.PLACEHOLDER_EVENTS)
	assert_null(EventDB.get_event(&"gravity_through_screen"), "no event yet")
	assert_false(DirAccess.dir_exists_absolute("res://events/gravity_through_screen"))
	var bad := SessionDef.new()
	bad.id = &"probe"
	bad.stage = 2
	bad.goal = SessionDef.SURVIVE
	bad.goal_value = 10.0
	bad.cues = PackedStringArray(["at 2: event gravity_through_nothing"])
	assert_string_contains(str(bad.problems()), "unknown event gravity_through_nothing")
	var ok := bad.duplicate() as SessionDef   # a fresh one: cue_list() is parsed once
	ok.cues = PackedStringArray(["at 2: event gravity_through_screen"])
	var text := "
".join(ok.problems())
	assert_false(text.contains("unknown event"), text)
	await _s11(&"arsenal", &"layout_gauntlet")
	await _quiet()
	await _next_part()
	assert_eq(game.session_runner.room(), 2)
	await _room_at(19.0)
	assert_eq(_logged(&"event_placeholder").size(), 0)
	await _room_at(20.0)
	var logged := _logged(&"event_placeholder")
	assert_eq(logged.size(), 1, "the cue fired and logged")
	assert_eq(logged[0].get("id"), "gravity_through_screen")
	assert_eq(game.event_player.played_ids(), [] as Array[String], "nothing played")
	assert_false(game.event_player.is_playing())
	assert_false(game.event_player.clock_held(), "the clock runs on")
	assert_false(SaveGame.event_seen(&"gravity_through_screen"), "nothing marked seen")
	assert_false(get_tree().paused)
	assert_eq(_logged(&"event_started").size(), 0)


# --- The orbit, the battery, the well -----------------------------------------------------------

func test_orbit_reaches_every_path() -> void:
	for p in PATHS:
		await _s11(p, &"layout_gauntlet")
		await _quiet()
		await _room_at(14.0)
		assert_false(&"orbit" in game.path_runner.offer_pool(), "%s: not before the AI brings it" % p)
		await _room_at(15.0)
		assert_true(&"orbit" in game.path_runner.offer_pool(), "%s: the orbit is in" % p)
		var lo := game.path_runner.loadout()
		if p == &"arsenal":
			assert_true(lo.passives.any(func(w: Weapon) -> bool: return w.def.id == &"orbit"), "Arcade: the passive slot")
		elif p == &"auto":
			assert_eq(game.path_runner.get(&"_first"), &"orbit", "Auto: first in the next level-up")
		else:
			var crates := get_tree().get_nodes_in_group(&"pickup").filter(func(n: Node) -> bool:
				return n.get(&"weapon_id") == &"orbit")
			assert_eq(crates.size(), 1, "Survival: a crate")
			# Its battery: the scripted drops land batteries, and one fills it back up.
			assert_true(lo.give(&"orbit"))
			assert_almost_eq(lo.battery(&"orbit"), 20.0, 0.01, "twenty seconds")
			lo.set(&"_battery", {&"orbit": 3.0})
			await _room_at(36.0)
			var cells := get_tree().get_nodes_in_group(&"pickup").filter(func(n: Node) -> bool:
				return n.get(&"pickup_kind") == &"battery" and not n.is_queued_for_deletion())
			assert_eq(cells.size(), 1, "room 1 at 36: one battery")
			Scavenge.take(lo, cells[0] as Pickup, game.player.global_position)
			assert_almost_eq(lo.battery(&"orbit"), 20.0, 0.01, "full again")
		game.queue_free()
		await wait_physics_frames(3)
		RunState.reset(0)
		RunState.world = null


func test_well_joins_auto_after_its_tagged_say_only() -> void:
	await _s11(&"auto", &"layout_gauntlet")
	await _quiet()
	await _room_at(29.0)
	assert_false(&"well" in game.path_runner.offer_pool(), "not before its line")
	await _room_at(30.0)
	assert_true(&"well" in game.path_runner.offer_pool(), "the [well] say adds it")
	var tagged := CampaignDB.get_session(S11).cue_list().filter(func(c: Cue) -> bool: return c.tag == &"well")
	assert_eq(tagged.size(), 1)
	assert_string_contains(tagged[0].cond, "answer:path_auto")


## PLAN 3.5's S11 rows, per path: each piece S11 brings has its cue in the data.
func test_s11_default_on_audit() -> void:
	var s := CampaignDB.get_session(S11)
	var rows := [
		["-", "^room 1 at 15: give orbit$", "orbit (every path)"],
		["arsenal", "^!answer:path_auto room 1 at 15: say happy: Little shields that spin\\.", "the orbit's line"],
		["survival", "^!answer:path_auto room 1 at 15: say happy: Little shields that spin\\.", "the orbit's line"],
		["auto", "^answer:path_auto holds orbit: say happy: Little shields that spin\\.", "the orbit's line, once held"],
		["survival", "^answer:path_survival room 1 at 16: say thinking: Yours run on a battery\\.", "battery"],
		["survival", "^answer:path_survival room 1 at 36: drop battery$", "a battery to grab"],
		["auto", "^answer:path_auto room 1 at 30 \\[well\\]: say happy: And a well\\.", "well (pool rule)"],
		["-", "^room 3 at 8: edit edit_enemies_flee$", "the flee edit"],
		["-", "^room 3 at 6: say thinking: You've earned a break\\.$", "the flee edit's say"],
		["-", "^room 2 at 20: event gravity_through_screen$", "the event's slot (a no-op)"],
		["arsenal", "^answer:path_arsenal at 0: add fusion$", "Arcade's basics"],
		["auto", "^answer:path_auto at 0: add evolve$", "Auto's basics"],
		["survival", "^answer:path_survival at 0: add kill_heal$", "Survival's basics"],
	]
	for row: Array in rows:
		var re := RegEx.create_from_string(row[1])
		var found := false
		for c in s.cue_list():
			if re.search(c.source) != null and (row[0] == "-" or SessionDef._cue_can_run_on(c, StringName(row[0]))):
				found = true
		assert_true(found, "S11 audit: %s (%s)" % [row[2], row[0]])
	assert_eq(s.spawn_weights.keys().map(func(k: Variant) -> String: return String(k)).filter(
			func(k: String) -> bool: return k in ["shielder", "sniper", "swarm"]).size(), 3, "the three, mixed in")


# --- M51 review fixes -------------------------------------------------------------------------

## Auto gets the orbit through a level-up: its line waits until the orbit is held.
func test_auto_says_the_orbit_line_once_it_holds_it() -> void:
	var s := CampaignDB.get_session(S11)
	var orbit_says := s.cue_list().filter(func(c: Cue) -> bool:
		return c.action == &"say" and c.source.contains("Little shields that spin"))
	assert_eq(orbit_says.size(), 2)
	for c: Cue in orbit_says:
		assert_eq(SessionDef._cue_can_run_on(c, &"auto"), c.when == &"holds", c.source)
		assert_eq(SessionDef._cue_can_run_on(c, &"arsenal"), c.when != &"holds", c.source)


## The flee edit lands at part 3 + 8 s, after its say at 6 s, so enemies are up to run away.
func test_the_flee_edit_waits_for_part_three_to_fill() -> void:
	await _s11(&"arsenal", &"layout_gauntlet")
	await _quiet()
	await _next_part()
	await _next_part()
	assert_eq(game.session_runner.room(), 3)
	await _room_at(7.0)
	assert_eq(RunState.rules.enemies_flee, 0, "not yet")
	await _room_at(8.0)
	await wait_physics_frames(int(1.6 * 60.0))   # the warning, then it lands
	assert_eq(RunState.rules.enemies_flee, 1, "scared now")


## PLAN 3.3: "enemy_seen sniper" fires on a sniper (a shooter variant), only in S11.
func test_a_sniper_is_seen_under_its_own_id() -> void:
	var r := CampaignDB.reactions.filter(func(d: ReactionDef) -> bool: return d.id == &"sniper_seen")
	assert_eq(r.size(), 1)
	assert_eq([r[0].trigger, r[0].after, r[0].until], ["enemy_seen sniper", S11, S11])
	assert_string_contains(str(Array(r[0].lines)), "Red line! Move!")
	await _s11(&"arsenal")
	await _quiet()
	game.spawner.weights = {&"sniper": 0.999999}
	game.spawner.budget = -1
	assert_not_null(game.spawner.spawn_one())
	await wait_physics_frames(3)
	var seen: Dictionary = game.reactions.get(&"_seen")
	assert_true(seen.has("sniper"), "seen as a sniper")
	assert_true(seen.has("shooter"), "and still as its base")


## The terminal rows of fork_hud's cards do not repeat the style's name.
func test_card_rows_do_not_repeat_the_name() -> void:
	for id: StringName in [&"hud_clean", &"hud_arcade", &"hud_onyou"]:
		var c := ChangeDB.get_change(id)
		assert_eq(DebriefScreen.card_row(c), c.pitch, "%s: the pitch only" % id)
	var other := Change.new()
	other.title = "Classic dash"
	other.pitch = "A quick burst."
	assert_eq(DebriefScreen.card_row(other), "classic dash  A quick burst.", "a pitch without the name keeps it")


## Survival's AMMO module reads the orbit's battery: seconds left, then out.
func test_survival_rail_shows_the_orbit_battery() -> void:
	await _s11(&"survival")
	await _quiet()
	var lo := game.path_runner.loadout()
	assert_eq(String(RailState._ammo(game.path_runner, lo).battery_title), "", "no battery before the orbit")
	assert_true(lo.give(&"orbit"))
	var d := RailState._ammo(game.path_runner, lo)
	assert_eq([d.battery_title, d.battery], ["Orbit", 20.0])
	lo.set(&"_battery", {&"orbit": 0.0})
	assert_eq(float(RailState._ammo(game.path_runner, lo).battery), 0.0, "out")

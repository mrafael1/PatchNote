extends GutTest
## M50.2b (Arcade through S10 design 2, .check/arcade_s10/design.md): the give step. A `give`
## on a full pack hand no longer queues in the next packs (G4 retired from the runner): it
## opens the replace step on the given card alone ("Replace <card>" per slot, then "Keep your
## hand"), on the first free tick (never on the misfuse's last tick, before an owed pack, which
## then waits PACK_GAP). No slot is locked; the recipe partner carries a hint, named only once
## the `fusion` basic is live. It draws nothing and is not a pack pick. The grammar: the cue
## when `give_choice n`, the conditions give_kept / give_taken / paired (a live hand fact) /
## made:<id>, and SessionDef.problems(). S9 on Arsenal: the laser's give step at 86 s.

const BotRuns := preload("res://tools/bot_runs.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_LOG := "user://save_give_step_test/runs.jsonl"

var game: Main
var player: CharacterBody2D
var done: Array = []   ## give_done (offer, slot) pairs


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	done.clear()


func after_each() -> void:
	await wait_physics_frames(2)
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	RunState.set_pause(PickPanel.PAUSE, false)
	RunState.session = null
	CampaignDB.active = false
	SaveGame.go_inert()
	Skins.disabled = false
	Skins.use(null)
	RunState.reset(0)
	RunState.world = null


## The legacy arena on Arsenal through F2 (outside a session every basic is on).
func _arena() -> PathRunner:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(1)
	player = game.player
	player.set_input(load("res://tests/gut/fixtures.gd").ScriptedInput.new())
	await wait_physics_frames(1)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true
	assert_true(game.debug.switch_path(&"arsenal"))
	game.pick_panel.input_delay = 0.0
	game.pick_panel.give_done.connect(func(o: PickOffer, s: int) -> void: done.append([o, s]))
	await wait_physics_frames(1)
	return game.path_runner


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


## S9's 86 s hand: Pistol 12 + Shotgun 9, both in the pool.
func _full_hand(r: PathRunner, active := 0) -> Loadout:
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"pistol", 12)
	lo.set_weapon(&"shotgun", 9)
	lo.active = active
	r.announce(&"pistol")
	r.announce(&"shotgun")
	return lo


## Gives the laser at rank 3 and waits for the give step.
func _give_laser(r: PathRunner) -> PickPanel:
	assert_true(r.give(&"laser", 3), "a full hand: the give step")
	await wait_physics_frames(2)
	assert_true(game.pick_panel.giving(), "the give step is open")
	return game.pick_panel


func _choices(e: String) -> Array:
	return RunState.run_log.filter(func(x: Dictionary) -> bool: return x.get("event") == StringName(e))


# --- The step ---------------------------------------------------------------------------------

func test_a_full_hand_give_opens_the_give_step_not_g4() -> void:
	var r := await _arena()
	var lo := _full_hand(r)
	var state := RunState.pack_rng.state
	var packs := r.packs()
	var offered := []
	var on_offer := func(o: RefCounted) -> void: offered.append(o)
	EventBus.pick_offered.connect(on_offer)
	var picked := []
	var on_pick := func(o: PickOffer, i: int) -> void: picked.append(i)
	game.pick_panel.picked.connect(on_pick)
	var panel := await _give_laser(r)
	var o := panel.offer
	assert_true(o.give_step)
	assert_eq(o.cards.size(), 1, "the given card alone")
	var c: Dictionary = o.cards[0]
	assert_eq([c.id, c.kind, c.rarity, int(c.rank)], [&"laser", &"new", BoosterPack.RARE, 3], "a gold card at the cue's rank")
	assert_eq(o.line, "A gold card: Laser 3.")
	assert_eq(panel.replace_count(), 2)
	assert_eq(panel._buttons.size(), 3, "Replace x2, then Keep your hand")
	assert_true(RunState.is_paused_for(PickPanel.PAUSE))
	assert_eq(RunState.pack_rng.state, state, "no pack_rng draw")
	assert_eq(r.pending_picks(), 0, "_want untouched")
	assert_eq(r.packs(), packs, "the PackMeter untouched")
	assert_eq(offered.size(), 0, "not a pack: no pick_offered")
	assert_eq(lo.summary(), "pistol:12,shotgun:9", "nothing replaced yet")
	assert_eq(_choices("give_offered").size(), 1)
	assert_eq(_choices("give_queued").size(), 0, "G4 retired")
	panel.choose(2)
	assert_eq(picked.size(), 0, "`picked` is not emitted")
	assert_eq(done.size(), 1, "give_done is")
	EventBus.pick_offered.disconnect(on_offer)
	game.pick_panel.picked.disconnect(on_pick)


func test_replace_one_replace_two_and_keep() -> void:
	var r := await _arena()
	var lo := _full_hand(r, 0)
	var panel := await _give_laser(r)
	panel.choose(0)
	assert_eq(lo.summary(), "laser:3,shotgun:9", "Replace Pistol: the laser takes slot 1")
	assert_eq(lo.active, 0, "the active slot stays active")
	assert_eq(done.back()[1], 0)
	assert_false(RunState.is_paused_for(PickPanel.PAUSE))
	assert_eq(_choices("give_choice").back().choice, "replace:pistol")
	assert_true(r.paired(), "Laser + Shotgun: a recipe pair")
	# Replace 2, the active slot.
	_full_hand(r, 1)
	panel = await _give_laser(r)
	panel.choose(1)
	assert_eq(lo.summary(), "pistol:12,laser:3")
	assert_eq(lo.active, 1)
	assert_false(r.paired())
	# Keep: the hand stays and the laser stays in the pool.
	_full_hand(r, 0)
	panel = await _give_laser(r)
	panel.choose(2)
	assert_eq(lo.summary(), "pistol:12,shotgun:9", "Keep your hand")
	assert_eq(done.back()[1], -1)
	assert_eq(_choices("give_choice").back().choice, "keep")
	assert_eq(int(r.pack_picks.give_kept), 1)
	assert_eq(r.give_steps(), 3)
	assert_true(&"laser" in r.live_pool, "kept: the laser is still in the live pool")
	var cands := BoosterPack.candidates(lo, r.offer_pool())
	assert_true(cands.any(func(x: Dictionary) -> bool: return x.id == &"laser" and x.kind == &"new"),
			"the next pack can show it as NEW")


func test_no_slot_is_locked_and_the_hint_names_the_recipe_only_after_fusion() -> void:
	var r := await _arena()
	_full_hand(r)
	var panel := await _give_laser(r)
	assert_eq(int(panel.offer.cards[0].links), 1, "the shotgun is its partner")
	assert_eq(panel.kept_slot(), -1, "no keep on a give step")
	for b in panel._buttons:
		assert_false(b.disabled, "every choice is enabled")
	assert_eq(PickPanel.give_text(panel.offer, 0, Callable(), false), "Replace Pistol 12")
	assert_eq(PickPanel.give_text(panel.offer, 1, Callable(), false),
			"Replace Shotgun 9\n(it links with the Laser: Prism)", "the fusion basic is live in the arena")
	assert_eq(PickPanel.give_text(panel.offer, 2, Callable(), false), "Keep your hand")
	assert_string_contains(PickPanel.give_text(panel.offer, 2), "]  Keep your hand", "with its key")
	panel.choose(2)
	# Before the fusion basic: the hint without the name.
	var s := SessionDef.new()
	s.basics = [&"movement", &"shooting", &"cards"] as Array[StringName]
	RunState.session = s
	assert_false(r.fusion_live())
	panel = await _give_laser(r)
	assert_eq(PickPanel.give_text(panel.offer, 1, Callable(), false), "Replace Shotgun 9\n(it links with the Laser)")
	assert_false(PickPanel.give_text(panel.offer, 1, Callable(), false).contains("Prism"))
	panel.choose(2)
	RunState.session = null


func test_a_pending_give_opens_by_itself_before_a_stacked_pack_which_waits_to_be_asked() -> void:
	var r := await _arena()
	_full_hand(r)
	r.want_pick()
	var panel := await _give_laser(r)   # M50.6: the give step opens by itself (it is the AI's)
	assert_true(panel.offer.give_step, "the give step first")
	assert_eq(r.pack_stack(), 1, "the pack stays on the stack")
	panel.choose(2)
	await wait_physics_frames(roundi(PathRunner.PACK_GAP * 60.0) + 20)
	assert_false(panel.is_open(), "M50.6: the stacked pack never follows by itself")
	assert_true(r.open_pack())
	await wait_physics_frames(2)
	assert_true(panel.is_open() and not panel.offer.give_step, "asked: the pack")
	panel.choose(0)


func test_the_give_step_waits_for_the_misfuse_and_opens_the_tick_after() -> void:
	var r := await _arena()
	_full_hand(r)
	assert_true(r.fuse_fail())
	assert_true(r.give(&"laser", 3))
	var open_frame := -1
	var end_frame := -1
	for i in roundi(PathRunner.MISFUSE_SECONDS * 60.0) + 10:
		await wait_physics_frames(1)
		assert_false(r.misfusing() and game.pick_panel.is_open(), "never over the misfuse")
		if end_frame < 0 and not r.misfusing():
			end_frame = r._tick
		if open_frame < 0 and game.pick_panel.giving():
			open_frame = r._tick
	assert_gt(end_frame, 0)
	assert_eq(r._misfuse_end_tick, end_frame, "the undo's tick")
	assert_gt(open_frame, r._misfuse_end_tick, "the give step opens after the undo's tick")
	game.pick_panel.choose(2)


func test_a_give_with_room_joins_at_once_and_a_held_one_ranks_up() -> void:
	var r := await _arena()
	var lo := _loadout()
	assert_eq(lo.summary(), "pistol:1")
	assert_false(r.give(&"laser", 3), "room: the caller gives it (no step)")
	assert_eq(r.give_pending(), &"")
	# A give that waits while the hand changes: room again when it opens -> it joins.
	_full_hand(r)
	RunState.set_pause(&"test", true)
	assert_true(r.give(&"laser", 3))
	lo.slots.remove_at(1)
	lo.active = 0
	RunState.set_pause(&"test", false)
	await wait_physics_frames(2)
	assert_false(game.pick_panel.is_open(), "no step: the hand had room")
	assert_eq(lo.summary(), "pistol:12,laser:3")


func test_the_bot_follows_the_hint_and_the_probes() -> void:
	var r := await _arena()
	var lo := _full_hand(r)
	var panel := await _give_laser(r)
	assert_eq(BotRuns.give_choice(panel, lo, ""), 0, "default: the non-partner goes")
	assert_eq(BotRuns.give_choice(panel, lo, "human"), 0, "human follows the hint")
	assert_eq(BotRuns.give_choice(panel, lo, "give_swap"), 1, "give_swap: the partner goes")
	assert_eq(BotRuns.give_choice(panel, lo, "give_keep"), 2, "give_keep")
	BotRuns.choose_pack(panel, game, "")
	assert_eq(lo.summary(), "laser:3,shotgun:9")
	# Nothing links: the lowest rank.
	lo.slots.clear()
	lo.set_weapon(&"pistol", 12)
	lo.set_weapon(&"launcher", 4)
	panel = await _give_laser(r)
	assert_eq(int(panel.offer.cards[0].links), -1)
	assert_eq(BotRuns.give_choice(panel, lo, ""), 1)
	panel.choose(2)


# --- Grammar ----------------------------------------------------------------------------------

func test_give_choice_and_the_conditions() -> void:
	var c := Cue.parse("answer:path_arsenal give_choice 1: say give_kept thinking: x")
	assert_eq(c.problem, "")
	assert_eq([c.when, c.value, c.cond, String(c.line.when)], [&"give_choice", 1.0, "answer:path_arsenal", "give_kept"])
	assert_false(c.due({"give_choices": 0}))
	assert_true(c.due({"give_choices": 1}))
	for bad in ["give_choice: say x", "give_choice 0: say x", "give_choice 1.5: say x"]:
		assert_ne(Cue.parse(bad).problem, "", bad)
	var both := Line.parse("give_taken&paired happy: x")
	assert_eq(both.problem, "")
	assert_true(both.passes({"give_taken": true, "paired": true}))
	assert_false(both.passes({"give_taken": true, "paired": false}))
	assert_false(Line.parse("!paired thinking: x").passes({}), "no paired key (a debrief): fails")
	assert_true(Line.parse("!paired thinking: x").passes({"paired": false}))
	assert_true(Line.parse("made:prism proud: x").passes({"made": ["prism"]}))
	assert_false(Line.parse("made:prism proud: x").passes({"made": []}))
	assert_ne(Line.parse("made:pistol proud: x").problem, "", "made: needs a fusion id")
	assert_ne(Line.parse("made:bogus proud: x").problem, "")
	# From the run log.
	var s := CampaignDB.get_session(&"s2_03_paint")
	var ctx := CampaignDB.line_context(s)
	assert_eq([ctx.give_kept, ctx.give_taken, ctx.made], [false, false, []])
	RunState.log_event(&"give_choice", {"weapon": "laser", "rank": 3, "choice": "keep", "t": 86.0})
	assert_true(CampaignDB.line_context(s).give_kept)
	RunState.log_event(&"give_choice", {"weapon": "laser", "rank": 3, "choice": "replace:pistol", "t": 90.0})
	assert_true(CampaignDB.line_context(s).give_taken)
	RunState.log_event(&"fused", {"weapon": "prism", "from": [], "rank": 5})
	assert_eq(CampaignDB.line_context(s).made, ["prism"])
	assert_false(CampaignDB.line_context(s).has("paired"), "paired is never in the debrief's context")


func test_session_problems_gate_the_give_grammar() -> void:
	var probs := func(cues: Array, fork := false, intro: Array = [], debrief: Array = []) -> String:
		var s := SessionDef.new()
		s.id = &"x"
		s.goal = SessionDef.SURVIVE
		s.goal_value = 100.0
		if fork:
			s.path = &"fork:fork_path"
		s.cues = PackedStringArray(cues)
		s.intro = PackedStringArray(intro)
		s.debrief = PackedStringArray(debrief)
		return str(s.problems())
	assert_string_contains(probs.call(["give_choice 1: say x"]), "give_choice needs the cards basic")
	var adds := ["answer:path_arsenal at 0: add cards", "answer:path_arsenal at 0: add fusion"]
	var p: String = probs.call(adds + ["give_choice 1: say x", "at 5: say paired happy: x"], true)
	assert_string_contains(p, "a fusion cue needs answer:path_arsenal")
	assert_string_contains(p, "a give / paired / made: line needs answer:path_arsenal")
	var ok: String = probs.call(adds + ["answer:path_arsenal give_choice 1: say give_kept thinking: x",
			"answer:path_arsenal at 5: say !paired happy: x", "answer:path_arsenal at 6: say made:prism happy: x"], true)
	assert_eq(ok, "[]", ok)
	assert_string_contains(probs.call(adds, true, ["paired happy: x"]), "an intro line cannot depend on a fusion")
	assert_string_contains(probs.call(adds, true, ["give_kept happy: x"]), "an intro line cannot depend on a fusion")
	assert_string_contains(probs.call(adds, true, [], ["answer:path_arsenal&paired happy: x"]),
			"a debrief line cannot read paired")
	assert_eq(probs.call(adds, true, [], ["answer:path_arsenal&give_kept happy: x", "answer:path_arsenal&made:prism happy: x"]),
			"[]", "a debrief may read give_kept and made:")


func test_draw_with_a_give_still_puts_it_second_test_only() -> void:
	var lo := Loadout.new()
	lo.apply_path(PathDB.get_def(&"arsenal"))
	lo.slots.clear()
	lo.set_weapon(&"pistol", 2)
	lo.set_weapon(&"shotgun", 2)
	autofree(lo)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pool: Array[StringName] = [&"pistol", &"shotgun", &"laser"]
	var o := BoosterPack.draw(lo, PathDB.get_def(&"arsenal"), pool, {"id": &"laser", "rank": 3}, rng, Taste.new())
	assert_eq([o.cards[1].id, o.cards[1].rarity, int(o.cards[1].rank)], [&"laser", BoosterPack.RARE, 3], "G4 still works for fixtures")


# --- S9 ---------------------------------------------------------------------------------------

func _s9() -> Main:
	SaveGame.go_inert()
	assert_true(CampaignDB.answer_fork(&"fork_path", &"path_arsenal"))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(&"s2_03_paint"))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	player = g.player
	RunState.invincible = true
	g.pick_panel.input_delay = 0.0
	g.pick_panel.give_done.connect(func(o: PickOffer, s: int) -> void: done.append([o, s]))
	return g


func _at(seconds: float) -> void:
	game.run_loop.goal_clock = seconds - 0.01
	await wait_physics_frames(3)


## S9 at 86 s on Arsenal: the laser opens the give step; returns the lines said after it.
func _s9_give(choice: int) -> Array[String]:
	await _s9()
	var said: Array[String] = []
	game.session_runner.line_queued.connect(func(l: Line) -> void: said.append(l.text))
	var r := game.path_runner
	await _at(20.0)
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"pistol", 12)
	lo.set_weapon(&"shotgun", 9)
	lo.active = 0
	r._want = 0
	await _at(79.0)
	assert_true(r.misfusing(), "the misfuse at 79 s")
	r._end_misfuse(true)
	r._misfuse_end_tick = r._tick
	await _at(86.0)
	await wait_physics_frames(2)
	assert_true(game.pick_panel.giving(), "the laser's give step at 86 s")
	assert_false(Unlocks.has_basic(&"fusion"), "before the fusion basic")
	assert_eq(PickPanel.give_text(game.pick_panel.offer, 1, Callable(), false), "Replace Shotgun 9\n(it links with the Laser)")
	said.clear()
	game.pick_panel.choose(choice)
	game.session_runner._last_say = -1.0   # the say gap is over
	await wait_physics_frames(3)
	return said


func test_s9_replace_pistol_plays_the_paired_line_before_fusion() -> void:
	var said := await _s9_give(0)
	assert_eq(_loadout().summary(), "laser:3,shotgun:9")
	assert_true(game.path_runner.paired(), "paired before the fusion basic")
	assert_eq(said, ["Laser and shotgun. Those two go together."] as Array[String], "the give_taken&paired line, once")
	await _at(94.0)
	assert_true(Unlocks.has_basic(&"fusion"))
	assert_true(said.has("Real fusion now. Two cards at rank four light a link."), "the paired 94 s line")
	assert_false(said.has("Real fusion now. The laser and the shotgun make something. Hold both."))
	# A forced loadout reaches FUSE.
	_loadout().set_weapon(&"laser", 4)
	assert_false(game.path_runner.fuse_option().is_empty(), "Laser 4 + Shotgun 9: FUSE")


func test_s9_replace_shotgun_and_keep_play_their_lines() -> void:
	var said := await _s9_give(1)
	assert_eq(_loadout().summary(), "pistol:12,laser:3")
	assert_eq(said, ["Laser and pistol. No recipe for those two. Yet."] as Array[String])
	await _at(94.0)
	assert_true(said.has("Real fusion now. The laser and the shotgun make something. Hold both."), "the !paired 94 s line")
	var lo := _loadout()
	var cands := BoosterPack.candidates(lo, game.path_runner.offer_pool())
	assert_true(cands.any(func(x: Dictionary) -> bool: return x.id == &"shotgun" and x.kind == &"new"), "the shotgun comes back NEW")
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 4)
	lo.set_weapon(&"laser", 4)
	assert_false(game.path_runner.fuse_option().is_empty(), "a forced pair reaches FUSE")
	game.free()
	var kept := await _s9_give(2)
	assert_eq(_loadout().summary(), "pistol:12,shotgun:9")
	assert_eq(kept, ["Keeping your hand? Fair. The laser's in the packs now."] as Array[String])
	assert_true(&"laser" in game.path_runner.live_pool)

extends GutTest
## M50.7 (the Arcade and Auto polish plan, .check/polish_m51c/plan.md; built as M50.7): presentation,
## debug UI, bot-only and text. Each test below names its plan item. New members are reached
## through has_method / get so the file parses on the base tree and each test fails there on its own.

const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_LOG := "user://m50_7_test/t.jsonl"
## Item 17: every sound built before M50.7 (sha256 of their bytes, in build order), from the base.
const OLD_SOUNDS := "501e3a561b21322da23ac715a2ff8064adfcd909358b883ac4bfe8fcf80167d4"
const OLD_SOUND_KEYS: Array[StringName] = [&"shoot", &"enemy_shoot", &"hit", &"kill", &"player_hit", &"player_died",
		&"jump", &"land", &"dash", &"explosion", &"bounce", &"patch_apply", &"patch_revert", &"prompt", &"click",
		&"compile", &"glitch", &"release_candidate", &"win", &"lose", &"edit_warn", &"hook", &"hook_miss", &"teleport",
		&"teleport_fizzle"]

var panel: PickPanel
var picked_i: Array = []
var fused: Array = []
var game: Main
var player: CharacterBody2D


func before_each() -> void:
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	await wait_physics_frames(2)
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)
	RunState.invincible = false
	RunState.session_path = &""
	RunState.clear_pauses()
	RunState.wave_closed = false
	RunState.session = null
	SaveGame.set_setting("reduce_flashing", false)
	SaveGame.go_inert()
	Skins.disabled = false
	Skins.use(null)
	RunState.reset(0)
	RunState.world = null


# --- Helpers ----------------------------------------------------------------------------------

func _panel() -> PickPanel:
	panel = PickPanel.new()
	add_child_autofree(panel)
	await wait_physics_frames(1)
	picked_i.clear()
	fused.clear()
	panel.picked.connect(func(_o: PickOffer, i: int) -> void: picked_i.append(i))
	panel.fuse_requested.connect(func(o: PickOffer) -> void: fused.append(o))
	return panel


func _card(id: StringName, kind: StringName, rarity: StringName, rank: int, from: int) -> Dictionary:
	var title := String(WeaponDB.get_weapon(id).title)
	return {"id": id, "kind": kind, "rarity": rarity, "rank": rank, "from": from,
			"title": "%s %d -> %d" % [title, from, rank] if kind == &"upgrade" else "%s %d" % [title, rank],
			"gain": "a gain line", "text": title}


func _pack(hand: Array, with_fuse := false) -> PickOffer:
	var o := PickOffer.new()
	o.pack = true
	o.line = "Pack. Pick one."
	o.max_slots = 2
	for h: Array in hand:
		o.hand.append({"id": h[0], "title": String(WeaponDB.get_weapon(h[0]).title), "rank": h[1]})
	o.cards.append(_card(&"shotgun", &"upgrade", BoosterPack.COMMON, 6, 5))
	o.cards.append(_card(&"laser", &"upgrade", BoosterPack.RARE, 5, 4))
	o.cards.append(_card(&"pistol", &"new", BoosterPack.COMMON, 1, 0))
	if with_fuse:
		o.fuse = {"a": &"shotgun", "b": &"laser", "id": &"prism", "rank": 5,
				"title": "FUSE: Shotgun 5 + Laser 4 -> Prism 5", "keeps": ["knockback cone"], "loses": [],
				"text": "FUSE: Shotgun 5 + Laser 4 -> Prism 5"}
	return o


func _level_offer() -> PickOffer:
	var o := PickOffer.new()
	o.level = 3
	o.cap = 6
	o.cards.append({"id": &"pistol", "rank": 3, "kind": &"upgrade", "text": "Pistol 3"})
	o.cards.append({"id": &"shotgun", "rank": 1, "kind": &"new", "text": "Shotgun 1"})
	o.cards.append({"id": &"haste", "rank": 1, "kind": &"new", "item": true, "text": "Haste 1"})
	return o


func _arena() -> void:
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


func _auto_runner() -> PathRunner:
	await _arena()
	RunState.session_path = &"auto"
	var r := game.ensure_path_runner()
	r.freeze()
	r.begin()
	r.frozen = false
	await wait_physics_frames(1)
	return r


## A static call through the script object (the member may not exist on the base tree).
func _sc(cls: Variant, m: StringName, args: Array) -> Variant:
	return (cls as Object).callv(m, args)


func _steps(p: Node, seconds: float, dt := 0.05) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		p.call(&"_process", dt)
		t += dt


## A runner stand-in for RailState / HandWidget (items 10, 11).
class FakeRunner:
	extends Node
	var stack := 0
	var packs_opened := 0
	var _meter: RefCounted
	var _lo: Loadout
	var pool: Array[StringName] = []
	var showing := 0

	func meter() -> RefCounted:
		return _meter

	func pack_stack() -> int:
		return stack

	func loadout() -> Loadout:
		return _lo

	func offer_pool() -> Array[StringName]:
		return pool

	func pack_on_screen() -> int:
		return showing


class FakeMeter:
	extends RefCounted
	var kills := 2
	var cards := 0

	func kills_left() -> int:
		return 4

	func progress() -> float:
		return 0.3


# --- 1. Auto level-up cards: hover lights the card, no tooltip ---------------------------------

func test_item1_mouse_over_a_level_card_focuses_it_and_no_tooltip() -> void:
	var p := await _panel()
	p.input_delay = 0.0
	assert_true(p.open(_level_offer()))
	assert_true(p.dressed())
	for b in p._buttons:
		assert_eq(b.tooltip_text, "", "no grey tooltip over the dressed card")
	assert_true(p._buttons[0].has_focus(), "keyboard focus starts on card 1")
	p._buttons[1].mouse_entered.emit()
	assert_true(p._buttons[1].has_focus(), "mouse over card 2 lights card 2")
	assert_eq(p.focused_choice(), 1, "the rail / slot preview follows")
	p.dismiss()


# --- 2. Give / replace steps: dressed hand cards -----------------------------------------------

func test_item2_the_replace_step_shows_hand_cards_and_a_dim_locked_one() -> void:
	var p := await _panel()
	p.input_delay = 0.0
	var o := _pack([[&"shotgun", 5], [&"laser", 4]])
	o.cards[2]["keep"] = 1   # the pistol keeps the laser (as mark_keeps would for a recipe)
	assert_true(p.open(o))
	p.choose(2)
	assert_eq(p.replacing(), 2)
	assert_true(p.has_method(&"choice_faces"), "the steps have hand card faces")
	if not p.has_method(&"choice_faces"):
		return
	var faces: Array = p.call(&"choice_faces")
	assert_eq(faces.size(), o.hand.size(), "one mini card per hand card")
	p._update_reveal()
	var locked: CardFace = faces[1]
	assert_true(bool(locked.face.get("lock", false)), "the kept partner is drawn locked")
	assert_false(locked.lit, "the disabled option is never lit")
	assert_true((faces[0] as CardFace).lit, "the focused option is lit")
	p._buttons[2].grab_focus()   # Back
	p._update_reveal()
	var lit := 0
	for f: CardFace in faces:
		lit += 1 if f.lit else 0
	assert_eq(lit, 0, "focus on Back: no hand card lit")
	assert_eq(String((faces[0] as CardFace).face.get("foot", "")), "[%s]" % InputSetup.expand_keys("{key:choose_1}"))
	p.dismiss()


## The chip is as wide as its text: on Pixel "Back to the pack" read "Back to the pac" in a
## 200 px chip.
func test_item2_the_back_chip_fits_its_text_on_pixel() -> void:
	Skins.use(Skins.pixel())
	assert_true(CardFace.pixel(), "the Pixel UI panel is on")
	var p := await _panel()
	p.input_delay = 0.0
	var o := _pack([[&"shotgun", 5], [&"laser", 4]])
	assert_true(p.open(o))
	p.choose(2)
	var chip: Button = p._buttons[p._buttons.size() - 1]
	var f := UiTheme.pixel_font(true)
	var key := String((chip.get_child(0) as CardFace).face.get("foot", ""))
	var kw := maxf(26.0, f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12.0) if key != "" else -10.0
	# The face draws: 12 margin, the key chip, 10 gap, the text, 8 right margin.
	var need := 12.0 + kw + 10.0 + f.get_string_size("Back to the pack", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.pixel_size(17)).x + 8.0
	assert_gte(chip.custom_minimum_size.x, need, "the Back chip fits its text and key")
	p.dismiss()
	Skins.use(null)


func test_item2_the_give_step_marks_the_link_apart_from_the_focus() -> void:
	var p := await _panel()
	p.input_delay = 0.0
	var o := PickOffer.new()
	o.pack = true
	o.give_step = true
	o.max_slots = 2
	o.line = "A gold card: Laser 3."
	o.hand.append({"id": &"pistol", "title": "Pistol", "rank": 12})
	o.hand.append({"id": &"shotgun", "title": "Shotgun", "rank": 9})
	var c := _card(&"laser", &"new", BoosterPack.RARE, 3, 0)
	c["links"] = 1
	c["recipe"] = ""
	o.cards.append(c)
	assert_true(p.open_give(o))
	assert_true(p.has_method(&"choice_faces"))
	if not p.has_method(&"choice_faces"):
		return
	var faces: Array = p.call(&"choice_faces")
	assert_eq(faces.size(), 2)
	p._update_reveal()
	assert_true(bool((faces[1] as CardFace).face.get("link", false)), "the recipe partner wears the link")
	assert_false((faces[1] as CardFace).lit, "the link is not the gold focus")
	assert_true((faces[0] as CardFace).lit)
	assert_eq(p._buttons.size(), 3, "Replace x2, Keep your hand")
	p.choose(2)


# --- 3. Rank-up feedback on the hand ----------------------------------------------------------

func _widget(lo: Loadout) -> Control:
	var w: Control = HandWidget.new()
	w.loadout = lo
	w.manual = true
	add_child_autofree(w)
	await wait_physics_frames(1)
	return w


func _arsenal_lo(ranks: Array) -> Loadout:
	var lo := Loadout.new()
	lo.apply_path(PathDB.get_def(&"arsenal"))
	lo.set_weapon(&"pistol", ranks[0])
	if ranks.size() > 1:
		lo.set_weapon(&"shotgun", ranks[1])
	autofree(lo)
	return lo


func test_item3_a_rank_up_bursts_on_its_hand_card() -> void:
	var lo := _arsenal_lo([4, 2])
	var w := await _widget(lo)
	w.step(0.016)
	assert_true(w.has_method(&"rank_up_left"))
	if not w.has_method(&"rank_up_left"):
		return
	assert_eq(float(w.call(&"rank_up_left", 0)), 0.0, "no burst at the start")
	lo.set_weapon(&"pistol", 5)
	w.step(0.016)
	assert_gt(float(w.call(&"rank_up_left", 0)), 0.0, "the pistol card bursts")
	assert_eq(float(w.call(&"rank_up_left", 1)), 0.0, "the other card does not")
	assert_eq(String(w.call(&"rank_tag", 0)), "RANK 5!")
	var a := float(w.call(&"rank_glow", 0))
	w.step(0.2)
	assert_ne(float(w.call(&"rank_glow", 0)), a, "the burst fades")
	w.step(0.6)
	assert_eq(float(w.call(&"rank_up_left", 0)), 0.0, "gone after ~0.6 s")
	SaveGame.set_setting("reduce_flashing", true)
	lo.set_weapon(&"pistol", 6)
	w.step(0.016)
	var steady := float(w.call(&"rank_glow", 0))
	w.step(0.2)
	assert_eq(float(w.call(&"rank_glow", 0)), steady, "reduce flashing: a steady highlight")
	assert_gt(steady, 0.0)


# --- 4. Pack opening beats --------------------------------------------------------------------

func test_item4_the_pack_drops_tears_deals_and_slots_in_while_paused() -> void:
	var p := await _panel()
	p.set_process(false)   # the test steps real time itself
	assert_true(p.get(&"beats") != null, "the beats flag")
	if p.get(&"beats") == null:
		return
	p.set(&"beats", true)
	p.input_delay = 0.4
	assert_true(p.open(_pack([[&"shotgun", 5], [&"laser", 4]])))
	assert_eq(p.call(&"beat_phase"), &"drop")
	assert_true(RunState.is_paused_for(PickPanel.PAUSE))
	_steps(p, 0.30)
	assert_eq(p.call(&"beat_phase"), &"tear")
	_steps(p, 0.25)
	assert_eq(p.call(&"beat_phase"), &"deal")
	p.choose(0)
	assert_eq(picked_i, [], "input before the lock is ignored")
	_steps(p, 0.35)
	assert_false(p.can_choose(), "still locked 0.35 s after the deal")
	_steps(p, 0.10)
	assert_true(p.can_choose(), "pickable 0.4 s after the cards are dealt")
	p.choose(0)
	assert_eq(p.call(&"beat_phase"), &"slot")
	assert_true(p.is_open())
	assert_true(RunState.is_paused_for(PickPanel.PAUSE), "the tree stays paused through the slot-in")
	assert_eq(picked_i, [])
	_steps(p, 0.35)
	assert_eq(picked_i, [0], "picked once the card is in its slot")
	assert_false(p.is_open())
	assert_false(RunState.is_paused_for(PickPanel.PAUSE))
	# Headless default: no beats (bots and hashes keep their wall time).
	var q := PickPanel.new()
	add_child_autofree(q)
	assert_false(bool(q.get(&"beats")), "headless: the beats are skipped")


# --- 5. The fuse moment -----------------------------------------------------------------------

func test_item5_the_fuse_shows_two_parents_then_the_result() -> void:
	var p := await _panel()
	p.set_process(false)
	p.input_delay = 0.0
	var o := _pack([[&"shotgun", 5], [&"laser", 4]], true)
	assert_true(p.open(o))
	p.choose(3)
	assert_eq(fused.size(), 1)
	var next := _pack([[&"prism", 5]])
	next.max_slots = 2
	p.after_fuse(next, "Prism 5")
	assert_true(p.fusing())
	assert_true(p.has_method(&"fuse_faces"))
	if not p.has_method(&"fuse_faces"):
		return
	assert_eq((p.call(&"fuse_faces") as Array).size(), 2, "the two parents")
	_steps(p, PickPanel.FUSE_TIME * 0.6, 0.02)
	var faces: Array = p.call(&"fuse_faces")
	assert_eq(faces.size(), 1, "then the fused card")
	assert_eq(String((faces[0] as CardFace).face.get("title", "")), "Prism")
	_steps(p, PickPanel.FUSE_TIME, 0.02)
	assert_false(p.fusing())
	p.dismiss()


# --- 6. The link socket in the pack's hand preview --------------------------------------------

func test_item6_the_hand_preview_shows_the_link_socket() -> void:
	var p := await _panel()
	p.input_delay = 0.0
	assert_true(p.has_method(&"hand_link"))
	if not p.has_method(&"hand_link"):
		return
	p.open(_pack([[&"shotgun", 4], [&"laser", 4]]))
	assert_eq(int(p.call(&"hand_link")), 2, "a recipe pair at rank 4: fuse ready")
	p.dismiss()
	var q := await _panel()
	q.input_delay = 0.0
	q.open(_pack([[&"shotgun", 3], [&"laser", 4]]))
	assert_eq(int(q.call(&"hand_link")), 1, "a half below rank 4: the dim socket")
	q.dismiss()
	var r := await _panel()
	r.input_delay = 0.0
	r.open(_pack([[&"pistol", 6], [&"shotgun", 6]]))
	assert_eq(int(r.call(&"hand_link")), 0, "not a recipe: no socket")
	r.dismiss()


# --- 7. Arcade pips, mechanic icons, the next teaser ------------------------------------------

func test_item7_odd_ranks_tease_the_next_mechanic_and_faces_carry_it() -> void:
	var shotgun := WeaponDB.get_weapon(&"shotgun")
	var odd := WeaponCurve.gain_text(shotgun, 2, 3)
	assert_string_contains(odd.to_lower(), "next:", "a numbers-only rank names what comes next")
	var even := WeaponCurve.gain_text(shotgun, 3, 4)
	assert_false(even.to_lower().contains("next:"), "an unlock rank says its unlock")
	var f := CardFace.face_of(_card(&"shotgun", &"upgrade", BoosterPack.COMMON, 4, 3))
	assert_ne(f.get("mech", &""), &"", "the unlock rank carries its mechanic")
	var g := CardFace.face_of(_card(&"shotgun", &"upgrade", BoosterPack.COMMON, 3, 2))
	assert_eq(g.get("mech", &""), &"", "a damage rank has no mechanic icon")
	# The teaser is its own tag on the face (in the gain line it fell past the second line).
	var c := _card(&"pistol", &"upgrade", BoosterPack.COMMON, 7, 6)
	c["gain"] = WeaponCurve.gain_text(WeaponDB.get_weapon(&"pistol"), 6, 7)
	assert_string_contains(String(c.gain), "next:")
	var h := CardFace.face_of(c)
	assert_ne(String(h.get("next", "")), "", "the face carries the teaser")
	assert_false(String(h.gain).contains("next:"), "the gain line keeps the breakpoints")
	var face := CardFace.new()
	face.face = h
	face.size = CardFace.SIZE
	add_child_autofree(face)
	await wait_process_frames(2)
	assert_true("next_drawn" in face, "the face records the teaser it drew")
	if "next_drawn" in face:
		assert_string_contains(String(face.get(&"next_drawn")), "NEXT", "the teaser is drawn on the card")


# --- 8. The live patch note for the Auto nerf -------------------------------------------------

func test_item8_the_nerf_is_announced_and_the_log_is_unchanged() -> void:
	var r := await _auto_runner()
	assert_true(r.has_signal(&"nerf_landed"), "the runner announces the nerf")
	if not r.has_signal(&"nerf_landed"):
		return
	var got: Array = []
	r.connect(&"nerf_landed", func(text: String, id: StringName) -> void: got.append([text, id]))
	var lo := r.loadout()
	lo.set_weapon(&"pistol", 6)
	lo.add_item(&"haste")
	var ev := r.evolve_option()
	r.want_pick()
	r._take_evolve(lo, ev)
	assert_true(r.arm_nerf(0.1))
	var before := RunState.run_log.size()
	await wait_physics_frames(12)
	assert_eq(got.size(), 1)
	assert_eq(got[0][0], r.nerf.text)
	assert_eq(got[0][1], &"minigun")
	var events: Array = []
	for e: Dictionary in RunState.run_log.slice(before):
		events.append(String(e.get("event", "")))
	assert_eq(events, ["patch_note", "nerfed"], "the same events, the same order")
	var mains := (load("res://main.gd") as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	assert_eq(String(_sc(Main, &"nerf_row_text", [&"minigun"])) if "nerf_row_text" in mains else "", "hotfix minigun")
	assert_true(game.pick_panel.toasting(), "the flat HUD shows the note")
	assert_eq(game.pick_panel._toast.text, r.nerf.text)
	lo.clear()


# --- 9. F2 ITEMS and EVOLUTIONS ---------------------------------------------------------------

func test_item9_f2_gives_items_and_evolutions() -> void:
	var r := await _auto_runner()
	var dbg: DebugOverlay = game.debug
	assert_true(dbg.has_method(&"give_evolution"))
	if not dbg.has_method(&"give_evolution"):
		return
	var evo: Dictionary = dbg.get(&"_evolution_buttons")
	for e in WeaponDB.evolutions():
		assert_true(evo.has(e.id), "a button for %s" % e.id)
		assert_eq((evo[e.id] as Button).disabled, not WeaponDB.evolution_built(e.id))
	assert_true(dbg.call(&"give_evolution", &"supernova"))
	assert_not_null(r.loadout().held(&"supernova"), "Supernova from F2")
	assert_true(dbg.call(&"give_evolution", &"thunderclap"))
	assert_not_null(r.loadout().held(&"thunderclap"))
	assert_true(dbg.call(&"give_item", &"haste"))
	assert_eq(r.loadout().item_level(&"haste"), 1)
	assert_true(dbg.call(&"give_item", &"haste"))
	assert_eq(r.loadout().item_level(&"haste"), 2, "+1 per press")
	var items: Dictionary = dbg.get(&"_item_buttons")
	for it in WeaponDB.items():
		assert_eq(items.has(it.id), it.built(), "built items only: %s" % it.id)
	r.loadout().clear()


# --- 10. Rail and HUD pack text ---------------------------------------------------------------

func test_item10_the_rail_counts_carried_packs_and_the_real_card_count() -> void:
	var fr := FakeRunner.new()
	autofree(fr)
	fr._meter = FakeMeter.new()
	fr._lo = _arsenal_lo([3, 2])
	fr.pool = [&"pistol", &"shotgun"]
	fr.stack = 3
	var d: Dictionary = RailState._pack(fr, PathDB.get_def(&"arsenal"))
	assert_eq(int(d.get("waiting", -1)), 3, "3 waiting")
	assert_eq(int(d.next), 4, "the next earned pack is pack 4, not pack 1")
	assert_eq(int(d.get("cards_next", -1)), 2, "a two-weapon pool on a full hand: 2 cards")
	assert_true("pick_line" in (RailState as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name))
	if "pick_line" in (RailState as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name):
		assert_eq(String(_sc(RailState, &"pick_line", [2])), "pick 1 of 2")
		assert_eq(String(_sc(RailState, &"pick_line", [3])), "pick 1 of 3")
	var lo := _arsenal_lo([4, 4])
	lo.set_weapon(&"pistol", 4)
	var epic := BoosterPack.epic_card(_arsenal_lo([4]), &"prism")
	assert_string_contains(String(epic.gain), "fusion of", "the epic card names its recipe as a fusion")


## The pack on screen is opened (packs_opened counts it) but still on the stack until the pick:
## counted once, so "pack N" does not drop by one when the panel closes.
func test_item10_the_pack_on_screen_is_counted_once() -> void:
	var fr := FakeRunner.new()
	autofree(fr)
	var m := FakeMeter.new()
	m.kills = 20
	m.cards = 3
	fr._meter = m
	fr._lo = _arsenal_lo([3, 2])
	fr.pool = [&"pistol", &"shotgun"]
	fr.packs_opened = 3
	fr.stack = 1
	fr.showing = 1
	var d: Dictionary = RailState._pack(fr, PathDB.get_def(&"arsenal"))
	assert_eq(int(d.next), 4, "three earned, the third on screen: the next is pack 4")
	assert_eq(int(d.get("waiting", -1)), 0, "the pack on screen is not waiting")
	fr.stack = 0
	fr.showing = 0
	d = RailState._pack(fr, PathDB.get_def(&"arsenal"))
	assert_eq(int(d.next), 4, "after the pick: still pack 4")


# --- 11. Pack-earned feedback -----------------------------------------------------------------

func test_item11_a_landed_pack_pulses_the_stack_chip() -> void:
	var fr := FakeRunner.new()
	add_child_autofree(fr)
	var w := await _widget(_arsenal_lo([3, 2]))
	w.runner = fr
	w.step(0.016)
	assert_true(w.has_method(&"stack_pulse"))
	if not w.has_method(&"stack_pulse"):
		return
	assert_eq(float(w.call(&"stack_pulse")), 0.0)
	fr.stack = 1
	w.step(0.016)
	assert_gt(float(w.call(&"stack_pulse")), 0.0, "the chip pulses once")
	var a := float(w.call(&"stack_glow"))
	w.step(0.1)
	assert_ne(float(w.call(&"stack_glow")), a)
	SaveGame.set_setting("reduce_flashing", true)
	fr.stack = 2
	w.step(0.016)
	var s := float(w.call(&"stack_glow"))
	w.step(0.1)
	assert_eq(float(w.call(&"stack_glow")), s, "reduce flashing: no alpha change")


# --- 12. Auto card text: real numbers ---------------------------------------------------------

func test_item12_breakpoints_read_the_path_hp_and_haste_reads_ticks() -> void:
	var shotgun := WeaponDB.get_weapon(&"shotgun")
	var args := (WeaponCurve as Script).get_script_method_list().filter(
			func(m: Dictionary) -> bool: return m.name == "breakpoint_text")
	assert_gte((args[0].args as Array).size(), 4, "breakpoint_text takes the HP mult")
	if (args[0].args as Array).size() < 4:
		return
	var full := String(_sc(WeaponCurve, &"breakpoint_text", [shotgun, 2, 3, 1.0]))
	var auto := String(_sc(WeaponCurve, &"breakpoint_text", [shotgun, 2, 3, 0.7]))
	assert_ne(auto, full, "Auto's 0.7 HP moves the counts")
	assert_eq(_hits_sum(auto) <= _hits_sum(full), true, "fewer hits at 0.7: %s / %s" % [auto, full])
	assert_true("haste_rate_text" in (LevelCard as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name))
	if "haste_rate_text" in (LevelCard as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name):
		var t := String(_sc(LevelCard, &"haste_rate_text", [0.18, 0, 1, -0.06]))
		assert_string_contains(t, "5.5/s -> 5.5/s", "a 0% step reads honestly: " + t)


func _hits_sum(t: String) -> int:
	var n := 0
	var rx := RegEx.create_from_string("in (\\d+)")
	for m in rx.search_all(t):
		n += int(m.get_string(1))
	if t.contains("one-shots"):
		n += 0
	return n


# --- 13. The gift marker ----------------------------------------------------------------------

func test_item13_the_given_card_is_tagged_gift() -> void:
	var c := {"id": &"haste", "rank": 1, "kind": &"new", "item": true, "text": "Haste 1"}
	var d: Dictionary = _sc(LevelCard, &"data_for", [c, 6, "1", {}, {"given": &"haste"}]) if _data_for_takes_ctx() else {}
	assert_true(bool(d.get("given", false)), "the gift card")
	if _data_for_takes_ctx():
		var e: Dictionary = _sc(LevelCard, &"data_for", [{"id": &"pistol", "rank": 2, "kind": &"upgrade", "text": "x"}, 6, "2", {}, {"given": &"haste"}])
		assert_false(bool(e.get("given", true)))
	assert_true("given" in PickOffer.new(), "the offer carries the given id")


func _data_for_takes_ctx() -> bool:
	var m := (LevelCard as Script).get_script_method_list().filter(func(x: Dictionary) -> bool: return x.name == "data_for")
	return (m[0].args as Array).size() >= 5


# --- 14. Fewer pick lines on Auto -------------------------------------------------------------

func test_item14_ten_level_ups_speak_three_pick_lines() -> void:
	var names := (PathRunner as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	assert_true("pick_line_due" in names)
	if not "pick_line_due" in names:
		return
	var spoken := 0
	for picks in range(1, 11):
		spoken += 1 if _sc(PathRunner, &"pick_line_due", [picks]) else 0
	assert_eq(spoken, 3, "the first two, then every 5th")


# --- 15. The mascot bubble clears the pick panels ---------------------------------------------

func test_item15_the_bubble_hides_while_a_panel_is_open() -> void:
	var m := Mascot.new()
	add_child_autofree(m)
	await wait_physics_frames(1)
	var p := await _panel()
	p.input_delay = 0.0
	assert_true("mascot" in p, "the panel knows the mascot")
	if not "mascot" in p:
		return
	p.set(&"mascot", m)
	m.say(Line.parse("happy: A line under the panel."), 2)
	m.step(0.01)
	assert_true(bool(m.call(&"bubble_shown")))
	p.open(_level_offer())
	assert_false(bool(m.call(&"bubble_shown")), "no bubble over the panel")
	p.choose(0)
	m.step(0.01)
	assert_true(bool(m.call(&"bubble_shown")), "it comes back after")


# --- 16. Small text ---------------------------------------------------------------------------

func test_item16_the_caption_names_the_path_title_and_plates_use_block_capitals() -> void:
	var f := RailFrame.new()
	autofree(f)
	f.snap = {"stage": 2, "title": "Fresh Paint", "path": {"id": &"arsenal", "title": "ARCADE"}}
	assert_eq(f.caption(), "stage 2 · fresh paint · arcade")
	Skins.use(Skins.pixel())
	var c := LevelCard.new()
	c.set_card(LevelCard.data_for({"id": &"pistol", "rank": 3, "kind": &"upgrade", "text": "x"}, 6, "1"), true)
	c.size = LevelCard.SIZE
	add_child_autofree(c)
	await wait_process_frames(2)
	assert_true("plate_drawn" in c)
	if "plate_drawn" in c:
		var pd: Dictionary = c.get(&"plate_drawn")
		assert_eq(String(pd.get("text", "")), "PISTOL")
		assert_gt(float(pd.get("cell", 0.0)), 0.0, "the rail's block capitals")
	Skins.use(null)


# --- 17. Sounds -------------------------------------------------------------------------------

func test_item17_new_sounds_append_and_old_bytes_stay() -> void:
	var s := Sound.new()
	add_child_autofree(s)
	await wait_physics_frames(1)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for k in OLD_SOUND_KEYS:
		h.update((s.streams[k] as AudioStreamWAV).data)
	var digest := h.finish().hex_encode()
	gut.p("old sound digest: " + digest)
	assert_eq(digest, OLD_SOUNDS, "the sounds before M50.7 keep their bytes")
	for k: StringName in [&"pack_tear", &"card_flip", &"card_slot", &"fuse_chime"]:
		assert_true(s._players.has(k), "a %s sound" % k)


# --- 18. The bot hunts the last enemies (bot_runs only) --------------------------------------

func test_item18_hunt_last_is_off_by_default_and_hunts_when_on() -> void:
	await _arena()
	assert_true(game.debug.switch_path(&"arsenal"))
	var bot := BotInput.new()
	assert_true("hunt_last" in bot)
	if not "hunt_last" in bot:
		bot.free()
		return
	assert_false(bool(bot.get(&"hunt_last")), "run_hash's bot: off")
	player.set_input(bot)
	bot.set_physics_process(false)
	await wait_physics_frames(1)
	RunState.session = load("res://campaign/sessions/s2_02_day_one.tres")
	RunState.wave_closed = true
	var e := RunState.spawn(preload("res://entities/enemy_chaser.tscn"), (OPEN + Vector2(8, 0)) * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	player.global_position = OPEN * T
	bot._physics_process(1.0 / 60.0)
	var to := (e.global_position - bot.origin()).normalized()
	assert_true(bot.move.is_equal_approx(to.rotated(1.2) * 0.6), "flag off: today's orbit, byte for byte")
	bot.set(&"hunt_last", true)
	player.global_position = OPEN * T
	bot._physics_process(1.0 / 60.0)
	assert_gt(bot.move.normalized().dot(to), 0.7, "flag on: toward the last enemy")


# --- Text-only line edits ---------------------------------------------------------------------

func test_the_s8_and_s9_lines_read_the_new_text() -> void:
	var s8: SessionDef = load("res://campaign/sessions/s2_02_day_one.tres")
	var s9: SessionDef = load("res://campaign/sessions/s2_03_paint.tres")
	assert_true("answer:path_arsenal at 16: say thinking: A copy of a card ranks it up. No top rank." in s8.cues)
	assert_true("answer:path_auto at 94 [might]: say thinking: Might makes everything hit harder. Nova evolves with it, one day." in s9.cues)
	assert_true("answer:path_auto evolve_ready 1: say happy: It's ready. Take EVOLVE." in s9.cues)


# --- Review fixes (M50.7 review pass) ---------------------------------------------------------

func test_review_pack_cards_take_the_focus_under_the_mouse() -> void:
	var p := await _panel()
	p.input_delay = 0.0
	assert_true(p.open(_pack([[&"shotgun", 5], [&"laser", 4]])))
	assert_true(p._buttons[0].has_focus())
	p._buttons[1].mouse_entered.emit()
	assert_true(p._buttons[1].has_focus(), "hover on a pack card moves the focus (one lit card)")
	p._update_reveal()
	var lit := 0
	for f: CardFace in p._faces:
		lit += 1 if f.lit else 0
	assert_eq(lit, 1, "one card lit")
	p.dismiss()


func test_review_the_slot_in_flies_to_the_hand_target() -> void:
	var p := await _panel()
	assert_true(p.has_method(&"slot_target"))
	if not p.has_method(&"slot_target"):
		return
	p.set(&"hand_target", func() -> Variant: return Vector2(700, 900))
	assert_eq(p.call(&"slot_target"), Vector2(700, 900), "the rail's HAND (below the view), not the flat corner")
	p.set(&"hand_target", func() -> Variant: return null)
	var view := p.get_viewport().get_visible_rect().size
	assert_eq(p.call(&"slot_target"), Vector2(80.0, view.y - 60.0), "no target: the flat hand's corner")


func test_review_the_fuse_shows_its_result_longer_in_a_window_and_the_rail_keeps_the_parents() -> void:
	var p := await _panel()
	p.set_process(false)
	p.input_delay = 0.0
	p.beats = true
	var o := _pack([[&"shotgun", 5], [&"laser", 4]], true)
	assert_true(p.open(o))
	_steps(p, 1.0, 0.02)   # the drop and tear
	p.choose(3)
	assert_eq(fused.size(), 1)
	var next := _pack([[&"prism", 5]])
	p.after_fuse(next, "Prism 5")
	assert_true(p.has_method(&"fuse_hand"))
	if not p.has_method(&"fuse_hand"):
		p.beats = false
		p.dismiss()
		return
	assert_eq(float(p.call(&"fuse_time")), PickPanel.FUSE_BEAT, "a real window: the long fuse")
	var parents: Array = p.call(&"fuse_hand")
	assert_eq(parents.map(func(h: Dictionary) -> String: return "%s %d" % [h.title, h.rank]), ["Shotgun 5", "Laser 4"],
			"the rail shows the parents while they slide together")
	_steps(p, PickPanel.FUSE_BEAT * 0.6, 0.02)
	assert_eq((p.call(&"fuse_hand") as Array).size(), 0, "then the result")
	assert_true(p.fusing(), "the result is still showing past FUSE_TIME")
	p.beats = false
	p.dismiss()


func test_review_the_pack_count_is_what_waits_and_says_when_an_epic_may_join() -> void:
	assert_eq(String(_sc(RailState, &"pick_line", [2, 3])), "pick 1 of 2 or 3")
	assert_eq(String(_sc(RailState, &"pick_line", [1, 2])), "1 card, or pick 1 of 2")
	assert_eq(String(_sc(RailState, &"pick_line", [3, 3])), "pick 1 of 3")
	var fr := FakeRunner.new()
	add_child_autofree(fr)
	var w := await _widget(_arsenal_lo([3, 2]))
	w.runner = fr
	fr.stack = 1
	fr.showing = 1
	assert_eq([w.call(&"stack_text"), w.call(&"stack_hint")], ["", ""], "the one pack is open: nothing waits")
	fr.stack = 2
	assert_eq(String(w.call(&"stack_text")), "1 pack", "two stacked, one open: 1 waits")


func test_review_nerf_cues_read_their_path_condition() -> void:
	var names: Array = (PathRunner as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	assert_true("path_cond_fits" in names)
	if not "path_cond_fits" in names:
		return
	assert_true(bool(_sc(PathRunner, &"path_cond_fits", ["answer:path_auto ", &"auto"])))
	assert_false(bool(_sc(PathRunner, &"path_cond_fits", ["answer:path_arsenal ", &"auto"])))
	assert_false(bool(_sc(PathRunner, &"path_cond_fits", ["!answer:path_auto ", &"auto"])), "negated: not this path")
	assert_true(bool(_sc(PathRunner, &"path_cond_fits", ["!answer:path_arsenal ", &"auto"])))
	assert_true(bool(_sc(PathRunner, &"path_cond_fits", ["", &"auto"])))


func test_review_the_next_tag_wraps_in_block_capitals() -> void:
	var names: Array = (CardFace as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	assert_true("next_rows" in names)
	if not "next_rows" in names:
		return
	var rows: Array = _sc(CardFace, &"next_rows", ["NEXT +KNOCKBACK CONE", 189.0, 2.0])
	assert_eq(rows.size(), 2, "two rows, not a cut")
	for r: String in rows:
		assert_lte(RailArt.digits_width(r, 2.0), 189.0)
	assert_eq(" ".join(rows), "NEXT +KNOCKBACK CONE", "every word drawn")


func test_review_a_long_gain_drops_whole_sentences() -> void:
	var f := CardFace.new()
	f.face = CardFace.face_of({"id": &"pistol", "kind": &"new", "rarity": BoosterPack.COMMON, "rank": 1, "from": 0,
			"gain": "joins your hand: The gun you started with. It still works. It has always worked, and it will keep working."})
	f.custom_minimum_size = CardFace.SIZE
	f.size = CardFace.SIZE
	add_child_autofree(f)
	await wait_process_frames(2)
	var g := String(f.get(&"gain_drawn"))
	assert_true(g.ends_with("."), "ends on a whole sentence: " + g)
	assert_false(g.ends_with("It still"), g)


func test_review_auto_weapon_cards_keep_a_damage_line_on_the_auto_hp() -> void:
	var ctx := {"hp_mult": 0.7}
	var checked := 0
	for id: StringName in [&"pistol", &"shotgun", &"laser", &"nova", &"seeker"]:
		var wd := WeaponDB.get_weapon(id)
		if wd == null or wd.is_passive():
			continue
		for to in range(2, 15):
			if WeaponCurve.mult(to) == WeaponCurve.mult(to - 1):
				continue
			var d := LevelCard.data_for({"id": id, "rank": to, "kind": &"upgrade", "text": ""}, 20, "", {}, ctx)
			var e := String(d.effect)
			checked += 1
			assert_true(e.contains("damage") or e.contains("one-shots") or RegEx.create_from_string(" in \\d").search(e) != null,
					"%s %d: a damage line: %s" % [id, to, e])
	assert_gt(checked, 0)


func test_review_haste_reads_the_evolved_gun() -> void:
	var names: Array = (LevelCard as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	assert_true("paired_now" in names)
	var lo := Loadout.new()
	lo.apply_path(PathDB.get_def(&"auto"))
	autofree(lo)
	lo.set_weapon(&"pistol", 6)
	assert_true(lo.evolve(&"pistol", &"minigun"))
	var d := LevelCard.data_for({"id": &"haste", "rank": 3, "kind": &"upgrade", "item": true, "text": ""}, 6, "", {},
			{"loadout": lo})
	assert_string_contains(String(d.pair), "Minigun", "the Pistol became the Minigun")


func test_review_the_hotfix_slip_keeps_its_numbers_whole() -> void:
	var chat: GDScript = load("res://ui/rail/rail_chat.gd")
	var names: Array = chat.get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	assert_true("slip_body" in names)
	if not "slip_body" in names:
		return
	var note := "Balance: Minigun 30 -> 15 shots/s, damage 2 -> 1.5"
	assert_eq(String(chat.call(&"slip_body", note, 100000.0, 12)), "Minigun 30 -> 15 shots/s, damage 2 -> 1.5")
	var one := RailFrame.text_w("Minigun 30 -> 15 shots/s", 12) + 4.0
	assert_eq(String(chat.call(&"slip_body", note, one, 12)), "Minigun 30 -> 15 shots/s", "a whole part dropped, none cut")

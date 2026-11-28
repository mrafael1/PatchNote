extends GutTest
## M48.6d: the Arcade dock and the pack stage of the cabinet (PLAN 0.9.2 "Packs and cards").
## The dock (the two-card hand, the fuse link, the package and its call) stands where the rail's
## HAND / PACK modules were; one press opens EVERY stacked pack (one row a pack, the front row
## alone live, "+N more" past four); the packs are drawn exactly as the one-by-one flow draws
## them (same offers, same hand, same pack_rng state); the fuse card is the row's 4th; the four
## tiers wear their own frames with the text inside the paper box; no ray, no halo, no banner on
## a card, every flip the same length; reduce flashing leaves fades only. Hosts here are tool
## hosts on an inert save (never live, no window change).

const Fixtures := preload("res://tests/gut/fixtures.gd")
const S8 := &"s2_02_day_one"
const TEST_LOG := "user://m48_6d_test/t.jsonl"

var _was: ArtSkin
var host: GameHost
var game: Main
var runner: PathRunner
var panel: PickPanel
var cab: CabinetFrame


func before_each() -> void:
	_was = Skins.current
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	await _drop()
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)
	Skins.disabled = false
	Skins.use(_was)
	Skins.reset_reveal(false)
	SaveGame.set_setting("reduce_flashing", false)
	Main.next_seed = -1


## Frees the host and resets what a hosted session touched (a test may host twice).
func _drop() -> void:
	if host != null and is_instance_valid(host):
		host.queue_free()
	host = null
	cab = null
	await wait_physics_frames(3)
	RunState.invincible = false
	RunState.clear_pauses()
	CampaignDB.active = false
	CampaignDB.jumped = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _engine_note() -> void:
	for e in get_errors():
		if e.contains_text("Camera2D overridden to physics process mode"):
			e.handled = true


## S8 on Arsenal in a tool host, seeded, three weapons in the pool, an input that never asks for
## a pack. `pixel`: the cabinet on (the Pixel look), else the flat look (no rail).
func _arcade(run_seed := 5, pixel := true) -> void:
	SaveGame.go_inert()
	Skins.use(null)
	Main.next_seed = run_seed
	assert_true(CampaignDB.answer_fork(&"fork_path", &"path_arsenal"))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(S8))
	game = load("res://main.tscn").instantiate()
	host = GameHost.host_for_tools(game)
	add_child(host)
	if game.stage_card != null:
		game.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	host.skip_handoff()
	for b: StringName in [&"cards", &"levelups", &"pickups"]:
		RunState.add_basic(b)
	await wait_physics_frames(2)
	game.player.set_input(Fixtures.ScriptedInput.new())
	runner = game.path_runner
	panel = game.pick_panel
	panel.input_delay = 0.0
	for w: StringName in [&"shotgun", &"laser", &"launcher"]:
		runner.announce(w)
	if pixel:
		Skins.use(Skins.pixel())
		_engine_note()
		assert_true(host.rail is CabinetFrame, "the cabinet is on")
		cab = host.rail as CabinetFrame
		host.relayout(Vector2(1600, 900))
		await wait_process_frames(2)
		cab.refresh()


## The hand as [[id, rank], ...], the first one active.
func _hand(cards: Array) -> void:
	var lo := runner.loadout()
	lo.slots.clear()
	for c: Array in cards:
		lo.set_weapon(c[0], c[1])
	lo.active = 0
	await wait_physics_frames(1)
	if cab != null:
		cab.refresh()


func _stack(n: int) -> void:
	runner._want = n
	if cab != null:
		cab.refresh()


## Waits for a row that takes a pick. False when the stage closed (or nothing opened).
func _row(max_frames := 240) -> bool:
	for i in max_frames:
		if panel.is_open() and panel.can_choose():
			return true
		if i > 3 and cab != null and not cab.packs.active and not panel.is_open():
			return false
		await wait_physics_frames(1)
	return false


## Picks card i; a NEW card on a full hand replaces the first slot it may.
func _pick(i: int) -> void:
	panel.choose(i)
	for k in 20:
		if not panel.is_open() or panel.replacing() < 0:
			return
		if panel.can_choose():
			panel.choose(1 if panel.kept_slot() == 0 else 0)
		await wait_physics_frames(1)


func _offer_ids() -> Array:
	var out := []
	for c: Dictionary in panel.offer.cards:
		out.append("%s:%d" % [c.id, int(c.rank)])
	return out


func _hand_ids() -> Array:
	var out := []
	for w: Weapon in runner.loadout().slots:
		out.append("%s:%d" % [w.id(), w.rank])
	return out


# --- 1. The dock ----------------------------------------------------------------------------------

func test_the_dock_shows_the_hand_where_the_modules_were() -> void:
	await _arcade()
	var dock := cab.dock
	assert_not_null(dock)
	assert_true(dock.shown(), "the dock shows on Arcade")
	# The rail's HAND / PACK modules have no cell in the cabinet any more.
	var shown: Array[StringName] = cab.modules.shown_modules()
	assert_false(&"path" in shown, "no docked HAND module")
	assert_false(&"pack" in shown, "no docked PACK module")
	assert_false(cab.layout.cells.has(&"hand"))
	assert_false(cab.layout.cells.has(&"pack"))
	# One card: the first slot holds it (active), the second is EMPTY.
	await _hand([[&"pistol", 1]])
	var sl := dock.slots()
	assert_eq(sl.size(), 2, "a two-card hand")
	assert_eq(sl[0].state, &"active")
	assert_eq(sl[0].name, "PISTOL")
	assert_eq(sl[0].rank, 1)
	assert_eq(sl[0].tab, "ACTIVE")
	assert_eq(sl[0].key, "1")
	assert_eq(sl[1].state, &"empty")
	assert_eq(sl[1].name, "EMPTY")
	assert_eq(sl[1].tab, "")
	assert_eq(sl[1].key, "2")
	assert_eq(dock.link(), 0, "no link with one card")
	# Two cards: the first active, the second held, each with its rank and its weapon's tier.
	await _hand([[&"shotgun", 2], [&"laser", 3]])
	sl = dock.slots()
	assert_eq([sl[0].state, sl[0].id, sl[0].rank, sl[0].tab], [&"active", &"shotgun", 2, "ACTIVE"])
	assert_eq([sl[1].state, sl[1].id, sl[1].rank, sl[1].tab], [&"idle", &"laser", 3, "HELD"])
	assert_eq(sl[1].tier, WeaponDB.get_weapon(&"laser").rarity, "the slot wears its weapon's tier")
	assert_eq(sl[0].tier, &"common")
	assert_false(dock.link_lit(), "no fuse link before fusion is added")
	assert_eq(dock.link(), 0)
	runner.loadout().select_slot(1)
	await wait_physics_frames(1)
	cab.refresh()
	sl = dock.slots()
	assert_eq([sl[0].state, sl[1].state], [&"idle", &"active"], "the ACTIVE tag follows the active card")
	# The layout: in the deck, right of the caption, the slots and the package apart.
	var l := cab.layout
	assert_true((l.deck as Rect2).grow(1.0).encloses(dock.rect()), "the dock in the deck")
	assert_gt(dock.rect().position.x, (l.cap as Rect2).end.x - 1.0, "right of the caption")
	assert_false(dock.slot_rect(0).intersects(dock.slot_rect(1)), "slot / slot")
	assert_false(dock.slot_rect(1).intersects(dock.pack_rect()), "hand / package")
	assert_false(dock.pack_rect().intersects(dock.call_rect()), "pack / call")
	dock.queue_redraw()
	await wait_process_frames(2)


func test_the_fuse_link_lights_only_when_the_pair_can_fuse() -> void:
	await _arcade()
	var dock := cab.dock
	RunState.add_basic(&"fusion")
	var at := BoosterPack.FUSE_RANK
	await _hand([[&"shotgun", at - 1], [&"laser", at]])
	assert_eq(dock.link(), 1, "a recipe pair below the fuse rank: the link is there, idle")
	assert_false(dock.link_lit())
	await _hand([[&"shotgun", at], [&"laser", at]])
	assert_true(BoosterPack.can_fuse(runner.loadout()))
	assert_eq(dock.link(), 2)
	assert_true(dock.link_lit(), "both at the fuse rank: lit")
	await _hand([[&"shotgun", at]])
	assert_eq(dock.link(), 0, "one card: no link")
	assert_false(dock.link_lit())


func test_the_package_shows_its_badge_gauge_and_call() -> void:
	await _arcade()
	var dock := cab.dock
	await _hand([[&"shotgun", 2], [&"laser", 3]])
	_stack(0)
	var pk := dock.package()
	assert_true(pk.on, "the package is there once packs are")
	assert_eq(pk.badge, "", "no badge with no pack")
	assert_false(pk.live, "the call sleeps with no pack")
	assert_eq(pk.queue, "none yet")
	assert_false(dock.open_all(), "nothing to open")
	var every: int = pk.every
	assert_gt(every, 1)
	assert_eq(pk.next, "%d kills to next" % (every - int(pk.kills)))
	# Kills fill the gauge.
	for i in 2:
		runner._on_enemy_killed(null, DamageInfo.make(1.0, &"projectile", &"player"))
	cab.refresh()
	pk = dock.package()
	assert_eq(pk.kills, 2, "the gauge counts the kills")
	assert_eq(pk.lit, floori(6.0 * 2 / every))
	assert_eq(pk.next, "%d kills to next" % (every - 2))
	# One pack: the call wakes, no badge yet (the badge says more than one).
	_stack(1)
	pk = dock.package()
	assert_eq(pk.waiting, 1)
	assert_eq(pk.badge, "")
	assert_true(pk.live)
	assert_eq(pk.call, "[%s] OPEN ALL" % PathRunner.open_key().to_upper())
	assert_eq(pk.queue, "1 waiting")
	_stack(3)
	pk = dock.package()
	assert_eq(pk.badge, "x3", "the red badge counts the stack")
	assert_eq(pk.stacked, 3)
	assert_eq(pk.queue, "3 waiting")
	assert_true((cab.layout.deck as Rect2).grow(1.0).encloses(dock.call_rect()), "the call in the deck")


# --- 2. Open all ----------------------------------------------------------------------------------

func test_one_press_opens_every_stacked_pack() -> void:
	await _arcade()
	var packs := cab.packs
	assert_not_null(packs)
	assert_eq(panel.stage, packs, "the panel hands its packs to the stage")
	for n: int in [1, 3, 6]:
		await _hand([[&"shotgun", 2], [&"laser", 3]])
		_stack(n)
		var opened0 := runner.packs_opened
		assert_true(cab.dock.open_all(), "%d: the one press" % n)
		var rows_seen := 0
		while await _row():
			rows_seen += 1
			assert_true(packs.active, "%d: the stage is up" % n)
			assert_eq(packs.total, n, "%d: every stacked pack is on the stage" % n)
			assert_true(panel.staged())
			assert_false(cab.dock.package().live, "%d: the call sleeps while the stage is up" % n)
			var left := n - rows_seen   # packs behind the front row
			var rows := packs.rows()
			assert_eq(rows.size(), 1 + mini(left, CabinetPacks.SHOWN - 1), "%d: a row a pack, four at most" % n)
			assert_true(rows[0].front)
			assert_true(rows[0].live, "%d: the front row takes the pick" % n)
			assert_eq((rows[0].cards as Array).size(), panel.offer.cards.size())
			for k in range(1, rows.size()):
				assert_false(rows[k].live, "%d: row %d behind waits" % [n, k])
				assert_true((rows[k].cards as Array).is_empty(), "%d: a row behind is face-down (not drawn yet)" % n)
				assert_lt((rows[k].rects[0] as Rect2).size.x, (rows[0].rects[0] as Rect2).size.x, "smaller")
				assert_lt((rows[k].rects[0] as Rect2).position.y, (rows[0].rects[0] as Rect2).position.y, "higher")
			assert_eq(packs.more(), maxi(0, left - (CabinetPacks.SHOWN - 1)))
			assert_eq(packs.more_text(), "+2 more packs waiting" if left == 5 else ("+1 more pack waiting" if left == 4 else ""))
			assert_eq(packs.header()[0], "%d PACKS · PICK 1 FROM EACH" % n if n > 1 else "PACK · PICK 1")
			assert_eq(packs.header()[1], "game paused · pack %d of %d" % [rows_seen, n])
			# Only the front row has buttons: one per card, under the cards.
			assert_eq(panel._buttons.size(), panel.offer.cards.size(), "%d: one button a front card" % n)
			var hits := packs.hit_rects(panel._buttons.size())
			for b in panel._buttons.size():
				assert_almost_eq(panel._buttons[b].global_position.x, hits[b].position.x, 1.0)
			assert_true(RunState.is_paused_for(PickPanel.PAUSE), "%d: the game is paused on a row" % n)
			await _pick(0)
		assert_eq(rows_seen, n, "%d: one row for each pack" % n)
		assert_eq(runner.packs_opened - opened0, n, "%d: every pack was opened" % n)
		assert_eq(runner.pack_stack(), 0, "%d: and consumed" % n)
		assert_false(packs.active, "%d: the stage closed" % n)
		assert_false(panel.is_open())
		assert_false(RunState.is_paused_for(PickPanel.PAUSE))
	packs.queue_redraw()
	await wait_process_frames(2)


## The same seed, the same picks, through the one-by-one flow (the flat look: a press a pack)
## and through open-all: `{offers, hand, rng}`.
func _flow(staged: bool, n: int) -> Dictionary:
	await _arcade(11, staged)
	await _hand([[&"shotgun", 2], [&"laser", 3]])
	_stack(n)
	var offers := []
	if staged:
		assert_true(cab.dock.open_all())
	for k in n:
		if not staged:
			assert_true(runner.open_pack(), "a press a pack")
		if not await _row():
			break
		offers.append(_offer_ids())
		await _pick(k % 3 if k % 3 < panel.offer.cards.size() else 0)
		await wait_physics_frames(1)
	await wait_physics_frames(3)
	var out := {"offers": offers, "hand": _hand_ids(), "rng": RunState.pack_rng.state, "left": runner.pack_stack(),
			"staged": panel.stage != null and panel.staged() or (cab != null)}
	await _drop()
	return out


func test_open_all_draws_the_packs_as_the_one_by_one_flow_does() -> void:
	var old := await _flow(false, 4)
	assert_false(old.staged, "the flat look keeps the old panel (no stage)")
	var all := await _flow(true, 4)
	assert_true(all.staged)
	assert_eq(old.offers.size(), 4)
	assert_eq(all.offers, old.offers, "the same cards are offered, in the same order")
	assert_eq(all.hand, old.hand, "and the hand ends the same")
	assert_eq(all.rng, old.rng, "pack_rng was drawn the same number of times")
	assert_eq([old.left, all.left], [0, 0])


func test_the_stage_closes_when_the_next_pack_may_not_open() -> void:
	await _arcade()
	var packs := cab.packs
	await _hand([[&"shotgun", 2], [&"laser", 3]])
	_stack(3)
	assert_true(cab.dock.open_all())
	assert_true(await _row())
	runner._misfuse_left = 100000   # stands for anything that holds a pack (a warning, a swap)
	await _pick(0)
	for i in 90:
		if not packs.active:
			break
		await wait_process_frames(1)
	assert_false(packs.active, "nothing may open: the stage closes")
	assert_eq(runner.pack_stack(), 2, "and the packs stay on the stack")
	assert_false(panel.is_open())
	runner._misfuse_left = 0


# --- 3. The fuse ----------------------------------------------------------------------------------

func test_the_fuse_card_is_the_fourth_and_the_moment_plays() -> void:
	await _arcade()
	var packs := cab.packs
	RunState.add_basic(&"fusion")
	var at := BoosterPack.FUSE_RANK
	await _hand([[&"shotgun", at], [&"launcher", at + 1]])
	assert_true(cab.dock.link_lit())
	_stack(2)
	assert_true(cab.dock.open_all())
	assert_true(await _row())
	assert_true(panel.has_fuse(), "the hand qualifies: the pack offers the fuse")
	var n := panel.offer.cards.size()
	assert_eq(packs.specs.size(), n + 1, "the fuse card is one more card of the front row")
	var f: Dictionary = packs.specs[n]
	assert_eq(f.tier, &"fuse")
	assert_true(f.fuse)
	assert_eq(f.key, CabinetPacks.key_label(n), "on the next key")
	assert_eq(f.tags[0][0], "PERMANENT")
	assert_eq(f.name, "CLUSTER")
	assert_eq(panel._buttons.size(), n + 1, "and it takes a pick")
	assert_string_contains(packs.footer(), CabinetPacks.key_label(n) + " fuse")
	# The moment (in a window: beats on).
	panel.beats = true
	panel.choose(n)
	assert_true(packs.in_fuse(), "the fuse moment plays")
	assert_eq(panel._fuse_total, CabinetPacks.FUSE_TIME)
	assert_true(packs.hand_hidden(), "the two cards left the dock")
	for d: Dictionary in cab.dock.slots():
		assert_eq(d.state, &"empty")
	assert_eq(cab.dock.link(), 0)
	var note := packs.fuse_note()
	assert_eq(note[0].t, "KEEPS")
	assert_eq(note[-1].t, "PERMANENT · RANK %d" % (at + 1))
	var lay := packs.fuse_layout()
	var view: Rect2 = cab.layout.view
	assert_true(view.encloses(lay.card), "the fused card in the view")
	assert_true(view.encloses(lay.note), "the note in the view")
	assert_false((lay.card as Rect2).intersects(lay.note), "the note beside the card, never on it")
	assert_false((lay.card as Rect2).intersects(lay.stamp), "the FUSED! stamp over the card's top edge, not on its face")
	# Halfway: the flash, the shake and the burst have fired.
	for i in 16:
		packs._process(0.1)
		panel._process(0.1)
	assert_true(packs._events.has("hit"))
	assert_true(packs._events.has("slam"))
	for i in 20:
		packs._process(0.1)
		panel._process(0.1)
	assert_false(packs.in_fuse(), "the moment ends")
	panel.beats = false
	cab.refresh()
	assert_eq(_hand_ids(), ["cluster:%d" % (at + 1)], "the hand holds the fused card")
	assert_eq(cab.dock.slots()[0].id, &"cluster")
	# The same pack comes back for the new hand; the stage goes on to the last pack.
	assert_true(await _row())
	assert_false(panel.has_fuse())
	await _pick(0)
	assert_true(await _row())
	await _pick(0)
	assert_false(await _row())
	assert_eq(runner.pack_stack(), 0)


# --- 4. The cards ---------------------------------------------------------------------------------

func test_each_tier_wears_its_own_frame() -> void:
	await _arcade()
	var lo := runner.loadout()
	await _hand([[&"shotgun", 2], [&"laser", 3]])
	var tiers := {}
	for id: StringName in [&"pistol", &"shotgun", &"laser", &"launcher"]:
		var c := BoosterPack.card(lo, id)
		var spec := CabinetCard.spec_of(c, "1")
		assert_eq(spec.tier, WeaponDB.get_weapon(id).rarity, "%s: the card wears its weapon's rarity" % id)
		tiers[spec.tier] = true
	assert_true(tiers.has(&"common"))
	assert_true(tiers.has(&"rare"))
	var epic := BoosterPack.epic_card(lo, &"prism")
	assert_eq(CabinetCard.spec_of(epic, "3").tier, &"epic", "a ready-made fusion is epic")
	assert_eq(CabinetCard.fuse_spec({"id": &"cluster", "a": &"shotgun", "b": &"launcher", "rank": 5}, "4").tier, &"fuse")
	# Four frames in the kit, each its own art; the back is one more.
	var seen := {}
	for tier: StringName in CabinetCard.TIERS:
		assert_true(ArcadeArt.CARD.has(tier), "%s has a frame" % tier)
		assert_true(ArcadeArt.CARD_LAYOUT.has(tier))
		var tex := ArcadePaint.frame_tex(tier, 0)
		assert_eq(tex.get_size(), Vector2(CabinetCard.W, CabinetCard.H))
		seen[tex.get_image().get_data()] = true
	assert_eq(seen.size(), CabinetCard.TIERS.size(), "four different frames")
	assert_eq(CabinetCard.TIERS.size(), 4)
	assert_eq(ArcadePaint.back_tex().get_size(), Vector2(CabinetCard.W, CabinetCard.H))
	for id: StringName in [&"pistol", &"shotgun", &"laser", &"launcher", &"prism", &"cluster"]:
		assert_true(ArcadePaint.has_splash(id), "%s has its splash art" % id)


func test_a_card_says_two_or_three_lines_inside_its_paper_box() -> void:
	await _arcade()
	var lo := runner.loadout()
	var specs := []
	for hand: Array in [[[&"pistol", 1]], [[&"shotgun", 2], [&"laser", 3]], [[&"shotgun", 5], [&"launcher", 6]], [[&"laser", 7], [&"pistol", 8]]]:
		await _hand(hand)
		var full := lo.hand_full()
		for id: StringName in [&"pistol", &"shotgun", &"laser", &"launcher"]:
			var c := BoosterPack.card(lo, id)
			specs.append(CabinetCard.spec_of(c, "1", full and c.kind == &"new"))
	await _hand([[&"shotgun", 4], [&"laser", 4]])
	specs.append(CabinetCard.spec_of(BoosterPack.epic_card(lo, &"prism"), "3", true))
	RunState.add_basic(&"fusion")
	await _hand([[&"shotgun", 5], [&"launcher", 6]])
	specs.append(CabinetCard.fuse_spec(BoosterPack.fuse_option(lo), "4"))
	specs.append(CabinetCard.fused_spec(&"cluster", 6))
	for a_s: Array in [[3.0, 1.0], [3.6, 1.2], [6.0, 2.0]]:
		var a: float = a_s[0]
		var s: float = a_s[1]
		for spec: Dictionary in specs:
			var rows := CabinetCard.text_rows(spec, a, s)
			var n: int = (rows.rows as Array).size()
			assert_between(n, 1, CabinetCard.ROWS, "%s: one to three rows" % spec.name)
			assert_eq(rows.size, CabinetLayout.text_px(2, s), "%s: at the readable size" % spec.name)
			var paper := CabinetCard.paper_rect(spec, Vector2.ZERO, a)
			assert_true(paper.grow(0.5).encloses(CabinetCard.text_rect(spec, Vector2.ZERO, a, s)),
					"%s at %s: the text inside the paper box (%s)" % [spec.name, a, rows.rows])
			assert_ne(String(spec.name), "")


# --- 5. The reveals -------------------------------------------------------------------------------

func test_no_ray_no_halo_and_no_banner_on_a_card() -> void:
	await _arcade()
	var packs := cab.packs
	# Every flip is the same length, whatever the tier; a row's deal depends only on its size.
	for tier: StringName in CabinetCard.TIERS:
		assert_eq(CabinetPacks.flip_time(tier), CabinetPacks.FLIP, "%s flips as fast as a common card" % tier)
	assert_eq(CabinetPacks.deal_time(3), 2 * CabinetPacks.FLIP_STEP + CabinetPacks.FLIP)
	# The stage draws itself: no child node (no Rays, no Banner, no particle node).
	assert_eq(packs.get_child_count(), 0)
	for node: Node in host.find_children("*", "", true, false):
		var nm := String(node.name).to_lower()
		for word: String in ["ray", "halo", "banner"]:
			assert_false(nm.contains(word), "no node named %s (%s)" % [word, node.name])
	# The kit holds no ray or halo sheet; the stage's code asks for none, nor for a banner but
	# the FUSED! stamp (checked off the card in the fuse test).
	for sheet: StringName in ArcadeArt.FX:
		var s := String(sheet)
		assert_false(s.contains("ray") or s.contains("halo") or s.contains("beam"), "no %s sheet" % s)
	var code := FileAccess.get_file_as_string("res://ui/cabinet/cabinet_packs.gd") + FileAccess.get_file_as_string("res://ui/cabinet/cabinet_card.gd")
	var body := ""
	for line: String in code.split("\n"):
		body += line.split("#")[0] + "\n"
	var word := RegEx.create_from_string("(?i)(^|[^a-z])(rays?|halos?|beams?)([^a-z]|$)")
	assert_null(word.search(body), "no ray, halo or beam in the stage's code")
	assert_eq(body.count("banner"), 1, "one banner sheet only: the FUSED! stamp")
	assert_string_contains(body, "&\"banner_fused\"")
	# A rare's and an epic's juice: bursts, rings and sparks (an epic adds the flash and the shake).
	panel.beats = true
	var r := Rect2(400, 300, 216, 327)
	packs.juice_rare(r)
	assert_gt(packs._parts.size(), 0, "a rare bursts")
	assert_gt(packs._rings.size(), 0, "with a ring")
	assert_true(packs._flash.is_empty(), "no flash for a rare")
	assert_lt(packs._shake_t, 0.0, "no shake for a rare")
	var rare_parts := packs._parts.size()
	packs._reset()
	packs.juice_epic(r)
	assert_gt(packs._parts.size(), rare_parts, "an epic bursts bigger")
	assert_false(packs._flash.is_empty(), "with a short flash")
	assert_gte(packs._shake_t, 0.0, "and a small shake")
	packs._reset()
	panel.beats = false


func test_reduce_flashing_leaves_fades_only() -> void:
	await _arcade()
	var packs := cab.packs
	SaveGame.set_setting("reduce_flashing", true)
	panel.beats = true
	RunState.add_basic(&"fusion")
	var at := BoosterPack.FUSE_RANK
	await _hand([[&"shotgun", at], [&"launcher", at]])
	_stack(1)
	assert_true(cab.dock.open_all())
	for i in 30:
		if panel.is_open():
			break
		await wait_physics_frames(1)
	assert_true(panel.is_open())
	assert_eq(panel._intro_total, CabinetPacks.INTRO_REDUCE, "a short fade, no flight")
	assert_eq(packs.outro_time(), CabinetPacks.OUTRO_REDUCE)
	assert_eq(packs.fuse_time(), CabinetPacks.FUSE_REDUCE)
	# The row turns up: no burst, no ring, no flash, no shake.
	for i in 20:
		packs._process(0.1)
		panel._process(0.1)
	assert_true(panel.can_choose())
	assert_true(packs._parts.is_empty(), "no sparks")
	assert_true(packs._rings.is_empty(), "no ring")
	assert_true(packs._flash.is_empty(), "no flash")
	assert_lt(packs._shake_t, 0.0, "no shake")
	assert_eq(packs._shake_offset(), Vector2.ZERO)
	# The fuse: the same, with the note and the stamp fading.
	assert_true(panel.has_fuse())
	panel.choose(panel.offer.cards.size())
	assert_true(packs.in_fuse())
	for i in 20:
		packs._process(0.1)
		panel._process(0.1)
		assert_true(packs._parts.is_empty() and packs._rings.is_empty() and packs._flash.is_empty(), "the fuse: fades only")
		assert_lt(packs._shake_t, 0.0)
	assert_false(packs.in_fuse())
	# A pick: the card fades out, nothing flies.
	assert_true(await _row())
	panel.choose(0)
	if panel.replacing() >= 0:
		panel.choose(1 if panel.kept_slot() == 0 else 0)
	assert_true(packs._flights.is_empty(), "nothing flies")
	assert_true(packs._parts.is_empty() and packs._rings.is_empty())
	for i in 10:
		packs._process(0.1)
		panel._process(0.1)
	assert_false(panel.is_open())
	panel.beats = false


# --- 6. Off the cabinet ---------------------------------------------------------------------------

func test_the_flat_look_keeps_its_panel_and_one_pack_a_press() -> void:
	await _arcade(5, false)
	assert_false(host.rail is CabinetFrame, "no cabinet on the flat look")
	assert_false(panel.staged())
	await _hand([[&"shotgun", 2], [&"laser", 3]])
	_stack(3)
	assert_true(runner.open_pack())
	assert_true(await _row())
	assert_gt(panel._faces.size(), 0, "the flat panel's own card faces")
	await _pick(0)
	for i in 40:
		await wait_physics_frames(1)
	assert_false(panel.is_open(), "a press opens one pack")
	assert_eq(runner.pack_stack(), 2, "the others wait for theirs")

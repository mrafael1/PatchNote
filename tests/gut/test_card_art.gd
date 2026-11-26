extends GutTest
## M50.2c (Arcade through S10 design 2.5, .check/arcade_s10/design.md): pack opening and card
## art. Every card kind (common, rare, NEW, FUSE, give) has a face on tier 0 and on Pixel; the
## card frames live in their own baked art (CardFaceArt) with a pinned digest, outside the arena
## atlas (whose digest stays put); the deal's flips end inside the panel's input delay; under
## reduce flashing the deal is a fade only (no flip, flash or shine); the choices, their keys
## and the replace step are unchanged; the 1-card toast wears a small card.

const CARD_DIGEST := "68031465aa5208bba7dd7b238a67e8ce408c129130a8f9de08d29f5af82aed7a"   # M50.6: + the card_epic frame (e4f73d12... before)
## M50.3a moved the arena atlas once (the launcher's sprites and the card_rare role); the card
## art's own digest did not move (it reads card_rare at draw time).
const ATLAS_DIGEST := "db2c84518e7d82a873ca4e25d72e9e3b52cec842b029f950bf48992a19bd29ad"   # M50.6b: the projectile sheet redrew the shots (30a94910... before, M50.5's merged atlas)

var panel: PickPanel
var picked_i: Array = []
var fused: Array = []


func after_each() -> void:
	RunState.set_pause(PickPanel.PAUSE, false)
	SaveGame.go_inert()
	Skins.disabled = false
	Skins.use(null)


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


func _fuse() -> Dictionary:
	return {"a": &"shotgun", "b": &"laser", "id": &"prism", "rank": 5,
			"title": "FUSE: Shotgun 5 + Laser 4 -> Prism 5", "keeps": ["knockback cone", "burn line"],
			"loses": [], "text": "FUSE: Shotgun 5 + Laser 4 -> Prism 5"}


## A 3-card pack on the hand Shotgun 5 + Laser 4 (full), with FUSE.
func _pack(with_fuse := true) -> PickOffer:
	var o := PickOffer.new()
	o.pack = true
	o.line = "Pack. Pick one."
	o.max_slots = 2
	o.hand.append({"id": &"shotgun", "title": "Shotgun", "rank": 5})
	o.hand.append({"id": &"laser", "title": "Laser", "rank": 4})
	o.cards.append(_card(&"shotgun", &"upgrade", BoosterPack.COMMON, 6, 5))
	o.cards.append(_card(&"laser", &"upgrade", BoosterPack.RARE, 6, 4))
	o.cards.append(_card(&"pistol", &"new", BoosterPack.COMMON, 1, 0))
	if with_fuse:
		o.fuse = _fuse()
	return o


func _faces_all() -> Dictionary:
	var give := _card(&"laser", &"new", BoosterPack.RARE, 3, 0)
	return {
		"common": CardFace.face_of(_card(&"shotgun", &"upgrade", BoosterPack.COMMON, 4, 3), "[1]"),
		"rare": CardFace.face_of(_card(&"laser", &"upgrade", BoosterPack.RARE, 4, 3), "[2]"),
		"epic": CardFace.face_of(_card(&"prism", &"absorb", BoosterPack.EPIC, 4, 0), "[3]"),
		"new": CardFace.face_of(_card(&"laser", &"new", BoosterPack.COMMON, 1, 0), "[3]"),
		"fuse": CardFace.fuse_face(_fuse(), "[4]"),
		"give": CardFace.face_of(give, "", true),
	}


func test_every_card_kind_has_a_face_on_tier_0_and_pixel() -> void:
	var f := _faces_all()
	assert_eq([f.common.style, f.rare.style, f.epic.style, f.new.style, f.fuse.style, f.give.style],
			[&"card_common", &"card_rare", &"card_epic", &"card_common", &"card_fuse", &"card_give"])
	assert_eq([f.common.tag, f.rare.tag, f.epic.tag, f.new.tag, f.fuse.tag], ["3 > 4", "3 > 4", "NEW", "NEW", "FUSE"])
	# M50.6: the ribbon is the card's tier (never "RARE +2": every card is +1).
	assert_eq([f.common.ribbon, f.rare.ribbon, f.epic.ribbon, f.new.ribbon, f.give.ribbon],
			["COMMON", "RARE", "EPIC", "COMMON", "GOLD CARD"])
	assert_eq([f.fuse.title, int(f.fuse.rank), f.fuse.icon_a, f.fuse.icon_b], ["Prism", 5, &"fan", &"line"],
			"FUSE: both parents' pictures")
	assert_string_contains(f.fuse.foot, "Shotgun 5 + Laser 4")
	assert_eq([f.common.title, f.common.icon], ["Shotgun", &"fan"])
	for id: StringName in [&"card_common", &"card_rare", &"card_epic", &"card_fuse", &"card_give", &"card_back", &"ribbon"]:
		assert_not_null(CardFaceArt.frame(id), "a Pixel frame: %s" % id)
	# Drawn on each look: tier 0 (no look), then Pixel (its UI panel on).
	for look: StringName in [&"off", &"pixel"]:
		Skins.use(Skins.pixel() if look == &"pixel" else null)
		assert_eq(CardFace.pixel(), look == &"pixel")
		var cards: Array[CardFace] = []
		for k: String in f:
			var c := CardFace.new()
			c.face = f[k]
			c.size = CardFace.SIZE
			add_child_autofree(c)
			cards.append(c)
		await wait_process_frames(2)
		# M50.5a: the pictures are Auto's gun art on both looks (Pixel: CardArt, tier 0: flat guns).
		for c in cards:
			assert_false(c.art_drawn.is_empty(), "%s: a picture" % c.face.title)
			for d: Array in c.art_drawn:
				assert_eq(d[1], &"gun" if look == &"pixel" else &"flat", "%s on %s: %s" % [c.face.title, look, d[0]])


func test_card_art_is_its_own_bake_and_the_atlas_does_not_move() -> void:
	var a := ArtSkin.bake(load("res://systems/skins/art/card_face_art.gd"), &"cards")
	assert_eq(a.problems, [] as Array[String])
	assert_eq(a.digest(), CardFaceArt.digest(), "two bakes match")
	assert_eq(CardFaceArt.digest(), CARD_DIGEST, "the card art's digest (pinned)")
	assert_eq(Skins.pixel().digest(), ATLAS_DIGEST, "the arena atlas is unchanged")
	assert_false(Skins.pixel().has(&"card_rare"), "no card frame in the atlas")
	assert_eq(a.size_of(&"card_common"), Vector2(16, 16))


func test_the_deal_ends_inside_the_input_delay() -> void:
	for n in range(1, PickPanel.CHOICES + 1):
		assert_true(CardFace.reveal_end(n) <= PickPanel.INPUT_DELAY, "%d cards" % n)
	var p := await _panel()
	p.input_delay = PickPanel.INPUT_DELAY
	assert_true(p.open(_pack()))
	assert_true(p.revealing())
	assert_eq(p._faces.size(), 4, "3 cards and FUSE")
	assert_true(p._faces.all(func(f: CardFace) -> bool: return f.back), "dealt face-down")
	var t := 0.0
	while not p.can_choose():
		p._process(0.02)
		t += 0.02
		if not p.can_choose():
			assert_lt(t, PickPanel.INPUT_DELAY + 0.03, "the lock is the input delay, as before")
	assert_almost_eq(t, PickPanel.INPUT_DELAY, 0.03)
	assert_false(p.revealing())
	for f in p._faces:
		assert_false(f.back, "face-up once a choice is possible")
		assert_almost_eq(f.flip_sx, 1.0, 0.001)


func test_reduce_flashing_deals_with_a_fade_only() -> void:
	var flashes := 0
	var backs := 0
	for k in 30:
		var t := k * 0.02
		for i in 4:
			var calm := CardFace.reveal_at(t, i, true)
			assert_eq([calm.sx, calm.back, calm.flash], [1.0, false, 0.0], "no flip, no flash")
			assert_between(float(calm.alpha), 0.0, 1.0)
			var lively := CardFace.reveal_at(t, i, false)
			flashes += 1 if lively.flash > 0.0 else 0
			backs += 1 if lively.back else 0
	assert_gt(flashes, 0, "the default deal flashes each landing")
	assert_gt(backs, 0, "and flips")
	var shone := false
	for k in 200:
		assert_eq(CardFace.shine_at(k * 0.02, 3, true), -1.0, "no shine under reduce flashing")
		shone = shone or CardFace.shine_at(k * 0.02, 3, false) >= 0.0
	assert_true(shone, "a rare card shines by default")
	# On the panel: a fade.
	var p := await _panel()
	SaveGame.set_setting("reduce_flashing", true)
	p.input_delay = PickPanel.INPUT_DELAY
	p.open(_pack())
	p._process(0.05)
	for f in p._faces:
		assert_false(f.back)
		assert_eq(f.flash, 0.0)
		assert_eq(f.shine, -1.0)
	assert_lt(p._faces[3].modulate.a, 1.0, "the last card is still fading in")
	for k in 30:
		p._process(0.02)
	assert_eq(p._faces[1].shine, -1.0, "the rare card never shines")
	assert_eq(p._faces[3].modulate.a, 1.0)


func test_the_choices_and_their_keys_are_unchanged() -> void:
	var p := await _panel()
	p.input_delay = 0.0
	assert_true(p.open(_pack()))
	assert_eq(p._buttons.size(), 4, "cards 1-3 then FUSE (choose_4)")
	assert_eq(p._faces.size(), 4)
	for i in 4:
		assert_true(p._faces[i].get_parent() == p._buttons[i], "each face is its choice's button")
		assert_string_contains(p._faces[i].face.foot, "[%s]" % InputSetup.expand_keys("{key:choose_%d}" % (i + 1)))
	assert_eq(p._faces[3].face.style, &"card_fuse")
	var e := InputEventAction.new()
	e.action = &"choose_4"
	e.pressed = true
	p._unhandled_input(e)
	assert_eq(fused.size(), 1, "choose_4 is FUSE")
	# A NEW card on a full hand: the replace step, its card's face over Replace x2 + Back.
	p.dismiss()
	var q := await _panel()
	q.input_delay = 0.0
	q.open(_pack(false))
	q.choose(2)
	assert_eq(q.replacing(), 2)
	assert_eq(q._buttons.size(), 3, "Replace Shotgun 5, Replace Laser 4, Back")
	assert_true(q._give_face.visible, "the waiting card's face")
	assert_eq(q._give_face.face.title, "Pistol")
	q.choose(2)
	assert_eq(q.replacing(), -1, "Back")
	assert_false(q._give_face.visible)
	q.choose(0)
	assert_eq(picked_i, [0])
	# A level-up offer (not a pack) keeps its plain buttons.
	var r := await _panel()
	r.input_delay = 0.0
	var lv := PickOffer.new()
	lv.cards.append({"id": &"pistol", "rank": 2, "kind": &"upgrade", "text": "Pistol II"})
	r.open(lv)
	assert_eq(r._faces.size(), 0)
	assert_eq(r._buttons.size(), 1)
	assert_eq(r._buttons[0].text, "[%s]  Pistol II" % InputSetup.expand_keys("{key:choose_1}"))


func test_the_give_step_shows_the_gold_card_and_the_toast_a_small_one() -> void:
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
	assert_true(p._give_face.visible)
	assert_eq([p._give_face.face.style, p._give_face.face.ribbon], [&"card_give", "GOLD CARD"])
	assert_eq(p._buttons.size(), 3, "Replace x2, Keep your hand")
	p.choose(2)
	# The toast.
	var t := PickOffer.new()
	t.pack = true
	t.cards.append(_card(&"laser", &"upgrade", BoosterPack.RARE, 6, 5))
	p.toast(t)
	assert_true(p.toasting())
	assert_eq(p._toast_face.mini, &"toast")
	assert_true(p._toast_face.get_parent() == p._toast, "it fades with the toast's line")
	assert_eq([p._toast_face.face.title, p._toast_face.face.style], ["Laser", &"card_rare"])
	assert_eq(p._toast.text, "Pack: Laser +1  RARE")


## M50.2c review: the FUSE face shows every kept mechanic and the whole "loses:" list (it is
## the irreversible choice), fitted into its text box on both looks, never cut to two lines;
## the FUSE button's tooltip carries the full fuse_text too.
func test_the_fuse_face_shows_every_kept_mechanic_and_the_losses() -> void:
	var f := _fuse()
	f.keeps = ["knockback cone: pellets shove enemies back.", "burn line: the beam sets enemies on fire.",
			"pierce: shots pass through 2 enemies.", "ricochet: shots bounce once off the walls."]
	f.loses = ["spread", "chain", "overcharge"]
	f.text = "FUSE: Shotgun 5 + Laser 4 -> Prism 5\n" + "\n".join(f.keeps) + "\nloses: spread, chain, overcharge"
	for look: StringName in [&"off", &"pixel"]:
		Skins.use(Skins.pixel() if look == &"pixel" else null)
		var c := CardFace.new()
		c.face = CardFace.fuse_face(f, "[4]")
		c.size = CardFace.SIZE
		add_child_autofree(c)
		await wait_process_frames(2)
		assert_false(c.fuse_drawn.is_empty(), "%s: the FUSE text box was drawn" % look)
		var drawn := String(c.fuse_drawn.get("text", ""))
		for k: String in f.keeps:
			assert_string_contains(drawn, k)
		assert_string_contains(drawn, "loses: spread, chain, overcharge")
		var box: Rect2 = c.fuse_drawn.get("box", Rect2())
		assert_lte(float(c.fuse_drawn.get("height", 1e9)), box.size.y, "%s: the whole text fits its box" % look)
		assert_lte(box.end.y, CardFace.SIZE.y * (211.0 if look == &"pixel" else 216.0) / 232.0 + 0.5, "%s: above the foot line" % look)
	Skins.use(null)
	var o := _pack()
	o.fuse = f
	var p := await _panel()
	assert_true(p.open(o))
	assert_eq(p._buttons[3].tooltip_text, String(f.text), "the FUSE button's tooltip is the full fuse text")


## M50.3a review: the launcher's icon became `bomb`, and a key missing from BAND falls back to
## the misfuse lilac, so every base weapon's icon and every glyph key must have its own band.
func test_every_weapon_icon_and_glyph_key_has_a_band() -> void:
	for w in WeaponDB.all():
		assert_true(CardFaceArt.BAND.has(w.icon), "%s's icon %s has a band" % [w.id, w.icon])
	for key in WeaponGlyph.KEYS:
		assert_true(CardFaceArt.BAND.has(key), "glyph key %s has a band" % key)
	var misfuse := CardFaceArt.band(&"misfuse")
	assert_ne(CardFaceArt.band(WeaponDB.get_weapon(&"launcher").icon), misfuse, "the launcher is not lilac")
	assert_eq(CardFaceArt.band(&"bomb"), [Color.html("#ff9a6b"), Color.html("#e0664f")], "the launcher keeps its orange")
	assert_ne(CardFaceArt.band(&"cluster"), misfuse, "Cluster is not lilac")


## M50.5a (the Arcade_Cards / Arcade_Pack sheets): every Arsenal card shows its gun, not its
## shot: the common, RARE and NEW cards, the launcher, FUSE (the fused gun and both parents),
## the give card, the hand under a pack and the toast, Pixel and tier 0. The Pixel guns are
## CardArt's (Prism and Cluster added), the flat ones WeaponGlyph's (both added).
func test_every_arsenal_card_draws_its_gun_on_both_looks() -> void:
	var faces := [
		CardFace.face_of(_card(&"pistol", &"upgrade", BoosterPack.COMMON, 7, 6), "[1]"),
		CardFace.face_of(_card(&"shotgun", &"upgrade", BoosterPack.RARE, 4, 2), "[2]"),
		CardFace.face_of(_card(&"laser", &"new", BoosterPack.COMMON, 1, 0), "[3]"),
		CardFace.face_of(_card(&"launcher", &"new", BoosterPack.COMMON, 1, 0), "[1]"),
		CardFace.fuse_face(_fuse(), "[4]"),
		CardFace.fuse_face({"a": &"shotgun", "b": &"launcher", "id": &"cluster", "rank": 5,
				"title": "FUSE: Shotgun 5 + Launcher 4 -> Cluster 5", "keeps": ["knockback cone"], "loses": []}, "[4]"),
		CardFace.face_of(_card(&"laser", &"new", BoosterPack.RARE, 3, 0), "", true),
	]
	var minis := [[&"hand", CardFace.hand_face({"id": &"prism", "title": "Prism", "rank": 6})],
			[&"hand", CardFace.hand_face({"id": &"cluster", "title": "Cluster", "rank": 5})],
			[&"hand", CardFace.hand_face({"id": &"pistol", "title": "Pistol", "rank": 14})],
			[&"toast", CardFace.face_of(_card(&"shotgun", &"upgrade", BoosterPack.RARE, 7, 5))]]
	for icon: StringName in [&"prism", &"cluster"]:
		assert_true(CardArt.GUNS.has(icon), "%s has a Pixel gun" % icon)
		assert_true(icon in WeaponGlyph.FLAT_GUNS, "%s has a flat gun" % icon)
		var grid: Array = CardArt.GUNS[icon][0]
		for row: String in grid:
			assert_eq(row.length(), String(grid[0]).length(), "%s: rows are one width" % icon)
			for ch in row:
				assert_true(ch == "." or (CardArt.GUNS[icon][1] as Dictionary).has(ch), "%s: %s has a colour" % [icon, ch])
		for role: StringName in (CardArt.GUNS[icon][1] as Dictionary).values():
			assert_ne(CardArt.c(role), Color.MAGENTA, "%s: %s is a card colour" % [icon, role])
	for look: StringName in [&"off", &"pixel"]:
		Skins.use(Skins.pixel() if look == &"pixel" else null)
		var want := &"gun" if look == &"pixel" else &"flat"
		var cards: Array[CardFace] = []
		for fc: Dictionary in faces:
			var c := CardFace.new()
			c.face = fc
			c.size = CardFace.SIZE
			add_child_autofree(c)
			cards.append(c)
		for m: Array in minis:
			var c := CardFace.new()
			c.mini = m[0]
			c.face = m[1]
			c.size = CardFace.MINI_HAND if m[0] == &"hand" else CardFace.MINI_TOAST
			add_child_autofree(c)
			cards.append(c)
		await wait_process_frames(2)
		for c in cards:
			var icons := []
			for d: Array in c.art_drawn:
				assert_eq(d[1], want, "%s %s on %s: %s is a gun" % [c.face.title, c.mini, look, d[0]])
				icons.append(d[0])
			var expect := [c.face.icon_a, c.face.icon_b, c.face.icon] if c.face.style == &"card_fuse" and c.mini == &"" else [c.face.icon]
			assert_eq(icons, expect, "%s %s on %s: its pictures" % [c.face.title, c.mini, look])


## M50.6a: on Pixel the ribbon's word is block capitals drawn as art (RailArt.DIGITS), since the
## body font closed its C into a D at the ribbon's size ("DOMMON", "EPID"). Every ribbon word has
## all its letters, C / D / O / G / Q are five different glyphs, and the word fits its box.
func test_the_pixel_ribbon_is_block_capitals_that_tell_c_from_d() -> void:
	var seen := {}
	for ch: String in ["C", "D", "O", "G", "Q"]:
		assert_true(RailArt.DIGITS.has(ch), "a block %s" % ch)
		var g: Array = RailArt.DIGITS[ch]
		assert_eq(g.size(), 7)
		seen["".join(g)] = true
	assert_eq(seen.size(), 5, "five different glyphs")
	var c: Array = RailArt.DIGITS["C"]
	for y in range(1, 6):
		assert_eq(String(c[y])[4], ".", "the C is open on its right (row %d)" % y)
	var f := _faces_all()
	for word: String in ["COMMON", "RARE", "EPIC", "GOLD CARD"]:
		for ch in word:
			assert_true(RailArt.DIGITS.has(ch), "%s: a glyph for '%s'" % [word, ch])
	for look: StringName in [&"off", &"pixel"]:
		Skins.use(Skins.pixel() if look == &"pixel" else null)
		for k: String in ["common", "rare", "epic", "give"]:
			var card := CardFace.new()
			card.face = f[k]
			card.size = CardFace.SIZE
			add_child_autofree(card)
			await wait_process_frames(2)
			var d := card.ribbon_drawn
			assert_eq(d.get("text", ""), f[k].ribbon, "%s on %s" % [k, look])
			if look == &"pixel":
				var cell := float(d.cell)
				assert_gte(cell, 1.0, "%s: drawn as block capitals" % k)
				assert_eq(cell, roundf(cell), "whole pixels")
				var r: Rect2 = d.rect
				assert_lte(RailArt.digits_width(d.text, cell), r.size.x - 6.0, "%s: the word fits its box" % k)
				assert_lte(7.0 * cell, r.size.y - 6.0)
				assert_gte(r.position.x, 0.0, "the box stays on the card")
			else:
				assert_eq(float(d.cell), 0.0, "tier 0 keeps the look's font")
	Skins.use(null)

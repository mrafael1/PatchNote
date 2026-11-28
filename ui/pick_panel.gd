class_name PickPanel
extends CanvasLayer
## The in-run pick (PLAN v9 2): up to three weapon cards over the paused game, for Auto's
## level-ups now (Arsenal's cards in M46). Its own panel, not a PromptPanel (whose signal
## and open() take an Offer and whose pause reason is &"prompt"): it pauses with &"pick" on
## open, choose and dismiss, so a panel closed at the session's end never leaves the tree
## paused. A different frame from the debrief's cards: no mascot portrait, no "ship".
## Keys 1-3 (choose_1..3, named on the player's layout), click, pad focus; 0.4 s of input
## delay after opening (the debrief's, M42.1).
##
## M50.1a (Arsenal's booster packs, PickOffer.pack): each card shows its title with the rank
## arrow, its tags (NEW, its tier; M50.6) and its gain; a rare card sits in a frame of the look's
## card_rare role, an epic one (M50.6) in card_epic's. Under the cards the hand at 60% size. A NEW card on a full hand opens the
## replace step on the same panel: the hand's cards are choices 1-2 ("Replace Pistol 7"),
## Back is the next one (a key and a button; never Esc / ui_cancel, the pause menu's). Back
## returns to the same pack: nothing is drawn again and `picked` is not emitted. Each step
## has its own input delay.
##
## M50.1b (fusion): when the pack carries a FUSE choice (PickOffer.fuse) it is the choice after
## the cards (key choose_4 on a 3-card pack), in a frame of the hand's lit colour: the link,
## "FUSE: Shotgun 5 + Laser 4 -> Prism 5", the 4 kept mechanics and one dim "loses:" line.
## Choosing it emits fuse_requested; the PathRunner fuses and hands back the same pack for the
## new hand (after_fuse): the cards hide for FUSE_TIME (real time, the tree stays paused, so the
## hand's merge shows) and the pack comes back with its own input delay.
##
## M50.4b (Auto depth design 7, the M50.4m sheet): a level-up offer (PickOffer.level > 0, not a
## pack) shows dressed cards (LevelCard: kind, level badge, glyph window, name plate, pips, the
## effect, an item's pairing; the Pixel cards once the UI look is revealed, else the flat ones)
## under a "LEVEL n" banner. Each is still a Button (keys, click, pad focus, the input delay); its
## text stays empty and the card's line lives in card_text() and the logs. The pack and gift
## branches are untouched.
##
## M50.4c1: a level-up offer that carries an EVOLVE choice (PickOffer.evolve) shows it after the
## cards (key choose_4 on 3 cards, choose_3 on 2): the dressed gold EVOLVE card, or a gold-framed
## button on the plain panel. Choosing it emits `picked` with index cards.size() (the PathRunner
## evolves; it spends the level-up).
##
## M50.2a (pack tuning, D3): a 1-card pack has no choice, so it never opens the panel: toast()
## shows a short line at the game's bottom right, next to the rail's PACK module ("Pack:
## Pistol +1", gold when rare) for TOAST_TIME of real time, fading out at the end (a fade only,
## no shine, whatever reduce_flashing says). No pause, no input. A plain label until M50.2c
## dresses it as a small card face.
##
## M50.2b (the give step, PickOffer.give_step): a `give` on a full pack hand opens the replace
## step straight on the given card: its face (gold frame when rare) under "A gold card: Laser
## 3.", then "Replace Pistol 12" per hand card and "Keep your hand" (the choice after them,
## where a pack's step has Back). No slot is locked: the hand card the given card makes a built
## recipe with reads "(it links with the Laser)" in a lit frame, still a choice; the recipe's
## name shows only once the `fusion` basic is live. Closing emits give_done (slot -1 = kept),
## never `picked`. The same pause, input delay and keys as a pack.
##
## M50.2c (pack opening and card art, design 2.5): a pack's cards and its FUSE choice are card
## faces (CardFace: a frame by rarity, the weapon's picture, rank badge and pips, the NEW / tier
## / FUSE marks; M50.6: every card is +1), each the visible part of a frameless Button (same keys, focus, click). They
## are dealt face-down and flip in sequence inside the INPUT_DELAY (CardFace.reveal_at; a fade
## only under reduce_flashing), so no choice opens earlier or later. The give step and the
## replace step show their card's face over the choices; the hand under a pack and the 1-card
## toast use the small faces. Tier 0 before S9's `skin ui`, CardFaceArt's Pixel frames after it.
## A level-up offer (not a pack: Auto, S7) is M50.4b's dressed LevelCard panel above (M50.5:
## Arcade's CardArt is CardFaceArt, Auto's level-up art kept the CardArt name).
##
## M50.7 (polish): a dressed level-up card lights under the mouse (hover takes the focus; no Godot
## tooltip over the art). The give and replace steps show each hand card as a mini card face with
## its key (CardFace MINI_CHOICE: the focus is a gold ring, the recipe partner a mint edge and a
## link socket, the locked partner dim with a lock), "Keep your hand" / "Back" as a chip. The
## pack's hand preview has the link socket between the two cards (hand_link). With `beats` (a real
## window; never headless, so bots and hashes keep their wall time) a pack drops (DROP_TIME) and
## tears (TEAR_TIME) before its cards are dealt, and after the pick the losers flip back and drop
## while the chosen card flies to the hand (SLOT_TIME) before the tree unpauses; the input delay
## still runs from the deal. The fuse shows the two parents sliding together, then the fused card
## flipping in, inside fuse_time() (FUSE_BEAT in a real window). The mascot's bubble parks while a panel is open. A live nerf's
## note can show as a toast (note()). Every beat is real time inside the pause; reduce flashing
## keeps fades only (no shake, no flash) and shortens them.
##
## M48.6d (the cabinet's packs): while the cabinet shows (`stage` set and live), a pack's own step
## is drawn by the cabinet's pack stage (CabinetPacks, over the view at the window's own pixels):
## this panel keeps the pause, the input delay, the keys and the focus, and its buttons are
## frameless hit areas under the stage's cards (no card face, no dim, no hand preview here). The
## replace step and the give step stay this panel's. With `beats` the intro, the slot-in and the
## fuse take the stage's times; headless they take none, as before.

signal picked(offer: PickOffer, index: int)
## M50.1a: the replace step's Back (the pack stays open).
signal went_back(offer: PickOffer)
## M50.1b: the pack's FUSE was chosen (the PathRunner answers with after_fuse).
signal fuse_requested(offer: PickOffer)
## M50.2b: the give step closed: the hand slot the given card replaced, or -1 (hand kept).
signal give_done(offer: PickOffer, slot: int)

const PAUSE := &"pick"
const INPUT_DELAY := 0.4
const LAYER := 72   ## over the HUD (50) and the mascot (60), under the debrief (95)
const CHOICES := 4  ## choose_1..4 (M50.1a: the replace step's Back, M50.1b's FUSE)
const HAND_SCALE := 0.6
const FUSE_TIME := 0.4   ## M50.1b: the fuse animation (real time)
const FUSE_BEAT := 0.9   ## M50.7 review: the fuse with beats (a real window): the result shows ~0.4 s
const TOAST_TIME := 1.6  ## M50.2a: the 1-card pack's toast (real time)
const TOAST_FADE := 0.4  ## its fade-out at the end
const DROP_TIME := 0.30   ## M50.7: the pack drops in (beats)
const TEAR_TIME := 0.25   ## M50.7: the pack tears open
const SLOT_TIME := 0.35   ## M50.7: the chosen card flies to the hand, the others drop
const REDUCE_BEAT := 0.15 ## M50.7: the intro is 2 x this under reduce flashing (fades; intro_time)
const NOTE_TIME := 3.5    ## M50.7: a live nerf's note toast
const EPS := 0.0005

var offer: PickOffer
var input_delay := INPUT_DELAY   ## tests set 0
## M50.7: the pack beats play (a real window only: headless bots, hashes and tests skip them).
var beats := DisplayServer.get_name() != "headless"
## M50.7: main sets these (null-safe): the mascot (its bubble parks under the panel), the sounds.
var mascot: Node
var sound: Node

var _root: Control
var _line: Label
var _cards: HBoxContainer
var _buttons: Array[Button] = []
var _frames: Array[Control] = []
var _hand_row: HBoxContainer
var _replacing := -1        ## M50.1a: the pack card waiting for a slot (-1: the pack itself)
var _locked_for := 0.0
var _fusing := 0.0          ## M50.1b: seconds left of the fuse animation
var _fuse_total := FUSE_TIME   ## M50.7 review: its length (fuse_time())
var _fused_title := ""
var _dismissed := false   ## the run is over: never open again
var _banner: LevelCard.Banner   ## M50.4b: the dressed panel's "LEVEL n"
var _cards_dressed: Array[LevelCard] = []   ## M50.4b: tests
## M50.4f: the PathRunner (main.gd sets it), for the flat look's slot bar under the dressed cards.
var runner: Node
var _slot_bar: Control   ## M50.4f: the flat slot bar (null in the Pixel look: the rail shows it)
var _gap: Control   ## M50.4f: the space under the cards (smaller under the flat slot bar)
var _toast: Label         ## M50.2a: the 1-card pack's line
var _give_face: CardFace   ## M50.2b: the given card's face (give step; M50.2c: also the replace step)
var _toast_left := 0.0
var _faces: Array[CardFace] = []   ## M50.2c: the pack's card faces, choice order
var _reveal_t := -1.0              ## M50.2c: real seconds since the faces were dealt (-1: shown)
var _toast_face: CardFace          ## M50.2c: the toast's small card
var _choice_faces: Array[CardFace] = []   ## M50.7: the give / replace step's hand cards (choice order)
var _intro := 0.0                  ## M50.7: real seconds left of the drop and tear
var _intro_total := 0.0
var _outro := 0.0                  ## M50.7: real seconds left of the slot-in
var _outro_total := 0.0
var _outro_pick := -1
var _fuse_faces: Array[CardFace] = []   ## M50.7: the parents, then the fused card
var _fuse_parts := {}              ## M50.7: {a, b, id, rank} of the fuse playing
var _fuse_second := false
var _pack_art: Control             ## M50.7: the falling, tearing pack
var _hand_link := 0                ## M50.7: the preview's socket (0 none, 1 dim, 2 ready)
var _line_gap: Control             ## M50.7 review: room between a pack's title and its lifted cards
## M50.7 review: where the chosen card flies (a point in this panel's coordinates); main sets it to
## the rail's HAND module or the flat hand widget. Unset: the flat hand's corner.
var hand_target: Callable
## M48.6d: the cabinet's pack stage (CabinetFrame binds it; null with no cabinet).
var stage: CabinetPacks
var _dim: ColorRect
var _hits: Control                 ## M48.6d: the staged pack's hit buttons (placed by the stage's rects)
var _staged_built := false
var _deal_fresh := true


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(Palette.SCRIM_PICK, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override(&"separation", 18)
	_root.add_child(column)
	_banner = LevelCard.Banner.new()
	_banner.visible = false
	_banner.custom_minimum_size = Vector2(420, 84)
	column.add_child(_banner)
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_font_size_override(&"font_size", 28)
	_line.add_theme_color_override(&"font_color", Palette.INFO)
	_line.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	_line.add_theme_constant_override(&"outline_size", 6)
	column.add_child(_line)
	_line_gap = Control.new()
	_line_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_line_gap)
	_give_face = CardFace.new()
	_give_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_give_face.custom_minimum_size = CardFace.SIZE
	_give_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_give_face.visible = false
	column.add_child(_give_face)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override(&"separation", 20)
	column.add_child(_cards)
	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override(&"separation", 12)
	column.add_child(_hand_row)
	_gap = Control.new()
	_gap.custom_minimum_size = Vector2(0, 60)
	column.add_child(_gap)
	_pack_art = PackArt.new()
	_pack_art.set(&"panel", self)
	_pack_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pack_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pack_art)
	_hits = Control.new()
	_hits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hits)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_right = -28
	_toast.offset_bottom = -24
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.add_theme_font_size_override(&"font_size", 22)
	_toast.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	_toast.add_theme_constant_override(&"outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)
	_toast_face = CardFace.new()
	_toast_face.mini = &"toast"
	_toast_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_face.anchor_left = 0.0
	_toast_face.anchor_right = 0.0
	_toast_face.anchor_top = 1.0
	_toast_face.anchor_bottom = 1.0
	_toast_face.offset_left = -CardFace.MINI_TOAST.x - 12.0
	_toast_face.offset_right = -12.0
	_toast_face.offset_top = -CardFace.MINI_TOAST.y
	_toast_face.offset_bottom = 0.0
	_toast.add_child(_toast_face)


func is_open() -> bool:
	return _root.visible


## M48.6d: the cabinet's pack stage draws this offer (a pack, not a give step, the cabinet live).
func staged() -> bool:
	return stage != null and is_instance_valid(stage) and offer != null and offer.pack and not offer.give_step and stage.live()


## M50.2a: a 1-card pack, applied by the PathRunner without a pause: its line shows for
## TOAST_TIME (a new toast replaces the one showing).
func toast(p_offer: PickOffer) -> void:
	if _dismissed or p_offer == null or p_offer.cards.is_empty():
		return
	var c: Dictionary = p_offer.cards[0]
	_toast.text = toast_text(c)
	var tone := Palette.INFO
	if c.get("rarity") == BoosterPack.RARE:
		tone = Palette.color(&"card_rare")
	elif c.get("rarity") == BoosterPack.EPIC:
		tone = Palette.color(&"card_epic")
	_toast.add_theme_color_override(&"font_color", tone)
	_toast_face.face = CardFace.face_of(c)
	_toast_face.visible = true
	_toast_face.queue_redraw()
	_toast.modulate = Color(1, 1, 1, 1)
	_toast.visible = true
	_toast_left = TOAST_TIME
	if stage != null and is_instance_valid(stage):   # M48.6d: its card flies into the hand slot
		stage.toasted(p_offer)


## M50.7: a line in the toast's place with no card (a live nerf's patch note on the flat HUD),
## for NOTE_TIME of real time. No pause, no input.
func note(text: String) -> void:
	if _dismissed or text == "":
		return
	_toast.text = text
	_toast.add_theme_color_override(&"font_color", Palette.INFO)
	_toast_face.visible = false
	_toast.modulate = Color(1, 1, 1, 1)
	_toast.visible = true
	_toast_left = NOTE_TIME


## M50.2a: the toast is showing (tests, captures).
func toasting() -> bool:
	return _toast != null and _toast.visible


## M50.2a: "Pack: Pistol +1", "Pack: Laser +1  RARE", "Pack: Laser 1 joins  RARE" (M50.6: the
## tier after it when it is not common).
static func toast_text(c: Dictionary) -> String:
	var w := WeaponDB.get_weapon(c.get("id", &""))
	var title := String(w.title) if w != null else String(c.get("id", ""))
	var tier: StringName = c.get("rarity", BoosterPack.COMMON)
	var text := ""
	if c.get("kind") == &"upgrade":
		text = "Pack: %s +%d" % [title, int(c.get("rank", 0)) - int(c.get("from", 0))]
	else:
		text = "Pack: %s %d joins" % [title, int(c.get("rank", 1))]
	return text + ("  " + String(tier).to_upper() if tier != BoosterPack.COMMON else "")


## Opens now (the caller defers: never pause the tree inside a physics callback). Refused
## once dismissed.
func open(p_offer: PickOffer) -> bool:
	if _dismissed or p_offer == null or p_offer.cards.is_empty():
		return false
	offer = p_offer
	_replacing = -1
	_fusing = 0.0
	_outro = 0.0
	RunState.set_pause(PAUSE, true)
	_reveal_t = 0.0
	# M50.7: a pack drops and tears first (beats); the deal and the input delay start after it.
	_intro_total = intro_time() if beats and offer.pack else 0.0
	if staged():   # M48.6d: the stage's intro (the packs fly out, or the next row comes forward)
		_intro_total = stage.opening(self)
	_intro = _intro_total
	_build()
	_locked_for = input_delay
	_root.visible = true
	_park(true)
	if _intro > 0.0:
		_update_reveal()
		return true
	if _locked_for <= 0.0:
		_unlock()
	return true


## M50.7: the drop + tear (shorter fades under reduce flashing: 2 x REDUCE_BEAT in all, split
## between the fade in and the fade out in the DROP_TIME : TEAR_TIME ratio).
static func intro_time() -> float:
	return 2.0 * REDUCE_BEAT if SaveGame.reduce_flashing() else DROP_TIME + TEAR_TIME


## M50.7: the slot-in after the pick.
static func outro_time() -> float:
	return REDUCE_BEAT * 1.5 if SaveGame.reduce_flashing() else SLOT_TIME


## M50.7: where the open pack is: &"drop", &"tear", &"deal" (the cards are out), &"slot" (the
## chosen card flies in), &"fuse", or &"" (closed).
func beat_phase() -> StringName:
	if not is_open():
		return &""
	if _intro > EPS:
		return &"drop" if _intro > _intro_total * (TEAR_TIME / (DROP_TIME + TEAR_TIME)) + EPS else &"tear"
	if _outro > EPS:
		return &"slot"
	if _fusing > 0.0:
		return &"fuse"
	return &"deal"


## M50.7: the intro's progress for the pack art: [phase 0 drop / 1 tear, 0..1 within it].
func intro_progress() -> Array:
	if _intro <= EPS or _intro_total <= 0.0:
		return [-1, 0.0]
	var tear := _intro_total * (TEAR_TIME / (DROP_TIME + TEAR_TIME))
	var drop := _intro_total - tear
	var done := _intro_total - _intro
	if done < drop:
		return [0, clampf(done / drop, 0.0, 1.0)]
	return [1, clampf((done - drop) / tear, 0.0, 1.0)]


func _play(key: StringName) -> void:
	if sound != null and is_instance_valid(sound) and sound.has_method(&"play"):
		sound.call(&"play", key)


## M50.7: the mascot's bubble parks while a panel is open (it sits over the panel's title).
func _park(on: bool) -> void:
	if mascot != null and is_instance_valid(mascot) and mascot.has_method(&"park_bubble"):
		mascot.call(&"park_bubble", on)


## M50.2b: opens the give step (PickOffer.give_step: one given card, a full hand). The caller
## defers, as for open().
func open_give(p_offer: PickOffer) -> bool:
	if _dismissed or p_offer == null or not p_offer.give_step or p_offer.cards.is_empty():
		return false
	offer = p_offer
	_replacing = 0
	_fusing = 0.0
	_intro = 0.0
	_outro = 0.0
	RunState.set_pause(PAUSE, true)
	_reveal_t = 0.0
	_build()
	_locked_for = input_delay
	_root.visible = true
	_park(true)
	if _locked_for <= 0.0:
		_unlock()
	return true


## M50.2b: the give step is showing.
func giving() -> bool:
	return _root.visible and offer != null and offer.give_step


## The buttons for the offer (a pack's cards, or its replace step).
func _build() -> void:
	for b in _frames:
		b.queue_free()
	_frames.clear()
	_buttons.clear()
	for c in _hand_row.get_children():
		c.queue_free()
	_cards_dressed.clear()
	_slot_bar = null
	_gap.custom_minimum_size.y = 60.0
	_banner.visible = false
	_line.visible = true
	_faces.clear()
	_choice_faces.clear()
	_fuse_faces.clear()
	_hand_link = 0
	_staged_built = staged()
	var on_stage := _staged_built and _replacing < 0
	_dim.visible = not on_stage
	_pack_art.visible = not _staged_built
	# M50.7 review: a pack's lifted card (its tier plate) cleared the title only by a few px.
	_line_gap.custom_minimum_size.y = 26.0 if offer.pack and not offer.give_step and _replacing < 0 else 0.0
	var hints := Settings.key_hints()
	_give_face.visible = offer.give_step or _replacing >= 0
	if offer.give_step:
		var c: Dictionary = offer.cards[0]
		_line.text = offer.line
		_give_face.face = CardFace.face_of(c, "", c.get("rarity") == BoosterPack.RARE)   # M50.2c: the gold card
		_faces.append(_give_face)
		# M50.7: each hand card as a mini card with its key; the recipe partner wears the link.
		var w := WeaponDB.get_weapon(c.id)
		var given := String(w.title) if w != null else String(c.id)
		for j in replace_count() + 1:
			var linked := j == int(c.get("links", -1))
			var link_note := ""
			if linked:
				link_note = "links with %s%s" % [given, ": " + String(c.recipe) if String(c.get("recipe", "")) != "" else ""]
			_add_choice(choice_face(offer, j, _key(j, hints), "Keep your hand", linked, false, link_note), choose.bind(j))
		_update_reveal()
		return
	if _replacing >= 0:
		_line.text = "Your hand is full. %s replaces:" % offer.cards[_replacing].get("title", "")
		_give_face.face = CardFace.face_of(offer.cards[_replacing])   # M50.2c: the waiting card
		_give_face.set_reveal(CardFace.reveal_at(1.0, 0, true))
		_give_face.shine = -1.0
		_give_face.queue_redraw()
		var new_name := String(WeaponDB.get_weapon(offer.cards[_replacing].id).title)
		for j in replace_count() + 1:
			var kept := j == kept_slot()
			_add_choice(choice_face(offer, j, _key(j, hints), "Back to the pack", kept, kept,
					"links with the %s" % new_name if kept else ""), choose.bind(j))
		_update_reveal()
		return
	if _fusing > 0.0:
		_line.text = "Fusing... %s" % _fused_title
		if on_stage:   # M48.6d: the stage plays the fuse moment
			_line.visible = false
			return
		_build_fuse_faces()
		return
	_line.text = offer.line + waiting_text()
	if dressed():
		_build_dressed(hints)
		return
	if on_stage:   # M48.6d: the stage draws the row; the buttons are the hit areas under its cards
		_line.visible = false
		var n := offer.cards.size() + (1 if has_fuse() else 0)
		for i in n:
			_add_hit(choose.bind(i))
		_place_hits()
		stage.dealt(self, _deal_fresh)
		_deal_fresh = true
		return
	for i in offer.cards.size():
		if offer.pack:   # M50.2c: a card face
			_add_card(CardFace.face_of(offer.cards[i], _key(i, hints)), choose.bind(i))
		else:
			_add_button(card_text(offer, i, Callable(), hints), choose.bind(i), false)
	if has_fuse():
		_add_card(CardFace.fuse_face(offer.fuse, _key(offer.cards.size(), hints)), choose.bind(offer.cards.size()),
				fuse_text(offer, Callable(), false))
	if has_evolve():
		_add_button(evolve_text(offer, Callable(), hints), choose.bind(offer.cards.size()), false, true)
	if offer.pack:
		_add_hand_preview()
	_update_reveal()


## M50.2c: choice i's key hint on a card face ("[1]"; "" with key hints off).
static func _key(i: int, hints: bool) -> String:
	return "[%s]" % InputSetup.expand_keys("{key:choose_%d}" % (i + 1)) if hints else ""


## M50.2c: a pack card (or FUSE) as a card face over a frameless Button (its keys, focus and
## click; the face draws the focus).
func _add_card(face: Dictionary, on_press: Callable, tip := "") -> void:
	var b := Button.new()
	b.custom_minimum_size = CardFace.SIZE
	b.tooltip_text = tip   # M50.2c review: FUSE carries its full text (fuse_text) on hover too
	var empty := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.disabled = true
	b.pressed.connect(on_press)
	b.mouse_entered.connect(_hover.bind(b))   # M50.7 review: the mouse takes the focus here too
	var f := CardFace.new()
	f.face = face
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(f)
	_cards.add_child(b)
	_frames.append(b)
	_buttons.append(b)
	_faces.append(f)


## M48.6d: a staged pack card's hit area: a frameless Button (its keys, focus, click and the input
## delay) with nothing drawn; the stage draws the card over it.
func _add_hit(on_press: Callable) -> void:
	var b := Button.new()
	var empty := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.disabled = true
	b.pressed.connect(on_press)
	b.mouse_entered.connect(_hover.bind(b))
	_hits.add_child(b)
	_frames.append(b)
	_buttons.append(b)


## M48.6d: the hit areas follow the stage's cards (the window can resize under an open pack).
func _place_hits() -> void:
	if stage == null or not is_instance_valid(stage) or _buttons.is_empty():
		return
	var rects := stage.hit_rects(_buttons.size())
	for i in _buttons.size():
		if _buttons[i].get_parent() == _hits:
			_buttons[i].position = rects[i].position
			_buttons[i].size = rects[i].size


## M48.6d: the slot-in's progress for the stage: [the picked choice, 0..1], [-1, 0.0] when none.
func outro_progress() -> Array:
	if _outro <= EPS or _outro_total <= 0.0:
		return [-1, 0.0]
	return [_outro_pick, clampf(1.0 - _outro / _outro_total, 0.0, 1.0)]


## M50.7: the give / replace step's choice j as a mini face: a hand card ("Replace Pistol 12":
## its picture, name, rank and key; `linked` the recipe partner's mint edge and socket, `locked`
## the kept partner's lock), or after the hand the chip (`chip_text`: Keep your hand / Back).
static func choice_face(p_offer: PickOffer, j: int, key: String, chip_text: String, linked := false, locked := false,
		link_note := "") -> Dictionary:
	if j >= p_offer.hand.size():
		return {"style": &"chip", "title": chip_text, "foot": key, "rank": 0, "icon": &"", "tag": "", "ribbon": "",
				"gain": ""}
	var f := CardFace.hand_face(p_offer.hand[j])
	f["foot"] = key
	f["verb"] = "keep" if locked else "replace"
	f["link"] = linked
	f["lock"] = locked
	f["note"] = link_note
	return f


## M50.7: a step's choice: a frameless Button (keys, focus, click, the input delay) holding its
## mini face (the face draws the focus).
func _add_choice(face: Dictionary, on_press: Callable) -> void:
	var b := Button.new()
	var chip: bool = face.get("style") == &"chip"
	b.custom_minimum_size = CardFace.MINI_CHIP if chip else CardFace.MINI_CHOICE
	if chip:
		b.custom_minimum_size.x = CardFace.chip_width(String(face.get("title", "")), String(face.get("foot", "")))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var empty := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.disabled = true
	b.pressed.connect(on_press)
	b.mouse_entered.connect(_hover.bind(b))
	var f := CardFace.new()
	f.mini = &"choice"
	f.face = face
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(f)
	_cards.add_child(b)
	_frames.append(b)
	_buttons.append(b)
	_faces.append(f)
	_choice_faces.append(f)


## M50.7 (tests, captures): the give / replace step's mini faces, hand order (the chip not included).
func choice_faces() -> Array[CardFace]:
	var out: Array[CardFace] = []
	for f in _choice_faces:
		if f.face.get("style") != &"chip":
			out.append(f)
	return out


## M50.7: the mouse over a choice takes the focus (so hover and keys light the same card).
func _hover(b: Button) -> void:
	if is_instance_valid(b) and not b.disabled and b.is_inside_tree():
		b.grab_focus()


## M50.7: " 2 more waiting." after the pack's line while more packs are stacked.
func waiting_text() -> String:
	if offer == null or not offer.pack or runner == null or not is_instance_valid(runner) or not runner.has_method(&"pack_stack"):
		return ""
	var more := int(runner.call(&"pack_stack")) - 1
	return "  %d more waiting." % more if more > 0 else ""


## M50.7: the fuse moment's faces: the two parents (first half, sliding together), then the fused
## card flipping in (second half).
func _build_fuse_faces() -> void:
	_fuse_faces.clear()
	if _fuse_parts.is_empty():
		return
	if not _fuse_second:
		for p: StringName in [_fuse_parts.a, _fuse_parts.b]:
			var w := WeaponDB.get_weapon(p)
			var f := CardFace.new()
			f.mini = &"hand"
			f.face = CardFace.hand_face({"id": p, "title": String(w.title) if w != null else String(p),
					"rank": int(_fuse_parts.get("rank_" + String(p), BoosterPack.FUSE_RANK))})
			f.custom_minimum_size = CardFace.MINI_HAND
			f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			f.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_cards.add_child(f)
			_frames.append(f)
			_fuse_faces.append(f)
		return
	var r := CardFace.new()
	r.face = CardFace.face_of({"id": _fuse_parts.id, "kind": &"new", "rarity": BoosterPack.EPIC,
			"rank": int(_fuse_parts.rank), "from": 0, "gain": "fused: the recipe goes in the book"})
	r.face["tag"] = "FUSED"
	r.custom_minimum_size = CardFace.SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.add_child(r)
	_frames.append(r)
	_fuse_faces.append(r)


## M50.7 (tests, captures): the fuse moment's faces now.
func fuse_faces() -> Array[CardFace]:
	return _fuse_faces.duplicate()


## M50.7: the hand preview's link: 0 none (not a built recipe), 1 dim (a half below
## BoosterPack.FUSE_RANK), 2 ready. The live PathRunner's link_state when there is one (it also
## waits for the `fusion` basic), else the hand's own (tests).
func hand_link() -> int:
	return _hand_link


static func hand_link_of(hand: Array) -> int:
	if hand.size() != 2:
		return 0
	var f := WeaponDB.recipe(hand[0].get("id", &""), hand[1].get("id", &""))
	if f == &"" or not WeaponDB.fusion_built(f):
		return 0
	return 2 if int(hand[0].get("rank", 0)) >= BoosterPack.FUSE_RANK and int(hand[1].get("rank", 0)) >= BoosterPack.FUSE_RANK else 1


## M50.2c: the faces' reveal (flip or fade), shine and focus for the time since the deal.
## M50.7: hidden under the pack's intro; the slot-in moves them.
func _update_reveal() -> void:
	var reduce := SaveGame.reduce_flashing()
	var n := _faces.size()
	for i in n:
		var f := _faces[i]
		if _intro > EPS:
			f.set_reveal({"sx": 1.0, "back": true, "alpha": 0.0, "flash": 0.0})
		elif _reveal_t >= 0.0:
			f.set_reveal(CardFace.reveal_at(_reveal_t, i, reduce))
		var rare: bool = f.face.get("style") in [&"card_rare", &"card_give", &"card_epic"]   # M50.6: epic shines too
		f.shine = CardFace.shine_at(_reveal_t, n, reduce) if rare and _reveal_t >= 0.0 and _outro <= EPS else -1.0
		var b := f.get_parent() as Button
		f.lit = b != null and not b.disabled and b.has_focus()   # review: the mouse moves the focus (_hover)
		f.offset = Vector2.ZERO
		f.shrink = 1.0
		if _outro > EPS and _outro_total > 0.0:
			_slot_in(f, i, 1.0 - _outro / _outro_total, reduce)
		f.queue_redraw()


## M50.7: the slot-in at progress k (0..1): the chosen card flies down-left to the hand and
## shrinks, the others flip back and drop (a fade only under reduce flashing).
func _slot_in(f: CardFace, i: int, k: float, reduce: bool) -> void:
	var e := k * k * (3.0 - 2.0 * k)
	if i == _outro_pick:
		f.lit = true
		var target := slot_target() - (f.global_position + f.size * 0.5)
		f.offset = target * e
		f.shrink = lerpf(1.0, 0.3, e)
		f.modulate = Color(1, 1, 1, 1.0 - 0.6 * e if not reduce else 1.0 - e)
		return
	if reduce:
		f.modulate = Color(1, 1, 1, 1.0 - e)
		return
	f.back = k > 0.25
	f.flip_sx = maxf(0.04, absf(cos(clampf(k / 0.5, 0.0, 1.0) * PI)))
	f.offset = Vector2(0, 260.0 * e * e)
	f.modulate = Color(1, 1, 1, 1.0 - e)


## M50.7 review: where the slot-in ends: hand_target (the rail's HAND module, below the game view,
## or the flat hand widget), else the flat hand's corner.
func slot_target() -> Vector2:
	if hand_target.is_valid():
		var at: Variant = hand_target.call()
		if at is Vector2:
			return at
	var view := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	return Vector2(80.0, view.y - 60.0)


## M50.2c: the faces are still turning over (tests, captures).
func revealing() -> bool:
	return _root.visible and _reveal_t >= 0.0 and _reveal_t < CardFace.reveal_end(_faces.size())


func _add_button(text: String, on_press: Callable, rare: bool, fuse := false, small := false) -> void:
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	var edge := Palette.CARD_LIT if fuse else Palette.color(&"card_rare")
	box.bg_color = Color(edge, 0.0)
	box.border_color = Color(edge, 1.0 if rare or fuse else 0.0)
	box.set_border_width_all(4 if rare or fuse else 0)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(4 if rare or fuse else 0)
	frame.add_theme_stylebox_override(&"panel", box)
	var b := Button.new()
	b.custom_minimum_size = Vector2(280, 76) if small else Vector2(300, 150)   # M50.2c: under a card face
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override(&"font_size", 18)
	b.text = text
	b.disabled = true
	b.pressed.connect(on_press)
	Skins.dress_button(b)   # M48a: the look's UI panel (no look: today's theme)
	frame.add_child(b)
	_cards.add_child(frame)
	_frames.append(frame)
	_buttons.append(b)


## M50.4b: this offer shows the dressed level-up cards (a level-up offer, not a pack).
func dressed() -> bool:
	return offer != null and not offer.pack and offer.level > 0


## M50.4b: the dressed cards: the banner, then one LevelCard per card inside its Button.
func _build_dressed(hints: bool) -> void:
	var pixel := Skins.is_on(&"ui_panel")
	_banner.level = offer.level
	_banner.count = offer.cards.size() + (1 if has_evolve() else 0)   # EVOLVE is one of the choices
	_banner.pixel = pixel
	_banner.visible = true
	_banner.queue_redraw()
	_line.visible = false
	for i in offer.cards.size():
		var key := InputSetup.expand_keys("{key:choose_%d}" % (i + 1)) if hints else ""
		var frame := Control.new()
		frame.custom_minimum_size = LevelCard.SIZE
		var b := Button.new()
		b.custom_minimum_size = LevelCard.SIZE
		b.flat = true
		b.disabled = true
		# M50.7: no tooltip over the art (the card is its own text); the mouse takes the focus.
		for style: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
			b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		b.pressed.connect(choose.bind(i))
		b.focus_entered.connect(_on_focus_moved)
		b.mouse_entered.connect(_hover.bind(b))
		var card := LevelCard.new()
		card.set_card(LevelCard.data_for(offer.cards[i], offer.cap, key, offer.evolve, card_ctx()), pixel)
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(card)
		frame.add_child(b)
		_cards.add_child(frame)
		_frames.append(frame)
		_buttons.append(b)
		_cards_dressed.append(card)
	if has_evolve():
		_add_evolve_card(hints)
	if not pixel and runner != null and is_instance_valid(runner):   # M50.4f: the flat slot bar
		_slot_bar = SlotBar.new()
		_slot_bar.set(&"panel", self)
		_hand_row.add_child(_slot_bar)
		_gap.custom_minimum_size.y = 12.0


## M50.4c1: the dressed EVOLVE card, the choice after the cards.
func _add_evolve_card(hints: bool) -> void:
	var n := offer.cards.size()
	var key := InputSetup.expand_keys("{key:choose_%d}" % (n + 1)) if hints else ""
	var frame := Control.new()
	frame.custom_minimum_size = LevelCard.SIZE_EVO
	var b := Button.new()
	b.custom_minimum_size = LevelCard.SIZE_EVO
	b.flat = true
	b.disabled = true
	for style: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
		b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	b.pressed.connect(choose.bind(n))
	b.focus_entered.connect(_on_focus_moved)
	b.mouse_entered.connect(_hover.bind(b))
	var card := LevelCard.new()
	var nerf_s := 0.0   # M50.7: the session's launch window after this evolution (its card says it)
	if runner != null and is_instance_valid(runner) and runner.has_method(&"nerf_window"):
		nerf_s = float(runner.call(&"nerf_window"))
	card.set_card(LevelCard.data_for_evolve(offer.evolve, key, nerf_s), Skins.is_on(&"ui_panel"))
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(card)
	frame.add_child(b)
	_cards.add_child(frame)
	_frames.append(frame)
	_buttons.append(b)
	_cards_dressed.append(card)


## M50.1a: the hand under a pack's cards, at HAND_SCALE.
func _add_hand_preview() -> void:
	var label := Label.new()
	label.text = "Hand (%d/%d):" % [offer.hand.size(), offer.max_slots]
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", Palette.INFO)
	label.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	label.add_theme_constant_override(&"outline_size", 4)
	_hand_row.add_child(label)
	# M50.7: the link socket between the two hand cards (dim, or gold "fuse ready").
	_hand_link = hand_link_of(offer.hand)
	if runner != null and is_instance_valid(runner) and runner.has_method(&"link_state"):
		_hand_link = mini(_hand_link, int(runner.call(&"link_state")))
	for k in offer.hand.size():   # M50.2c: the small card faces
		var h: Dictionary = offer.hand[k]
		var p := CardFace.new()
		p.mini = &"hand"
		p.face = CardFace.hand_face(h)
		p.custom_minimum_size = CardFace.MINI_HAND
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hand_row.add_child(p)
		if k == 0 and offer.hand.size() == 2 and _hand_link > 0:
			var sock := CardFace.new()
			sock.mini = &"socket"
			sock.face = {"link": _hand_link}
			sock.custom_minimum_size = CardFace.MINI_SOCKET
			sock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hand_row.add_child(sock)


## M50.1a: a pack card's text: "[1]  Laser 6 -> 7   RARE" then its gain.
static func pack_card_text(p_offer: PickOffer, i: int, to_label := Callable(), hints := true) -> String:
	var c: Dictionary = p_offer.cards[i]
	var head := String(c.get("title", c.get("id", "")))
	var tags := BoosterPack.tags(c)
	if tags != "":
		head += "   " + tags
	if hints:
		head = "[%s]  %s" % [InputSetup.expand_keys("{key:choose_%d}" % (i + 1), to_label), head]
	return "%s\n%s" % [head, c.get("gain", c.get("text", ""))]


## M50.1b: the pack offers FUSE (the choice after its cards).
func has_fuse() -> bool:
	return offer != null and offer.pack and not offer.fuse.is_empty()


## M50.1b: the FUSE choice's text: "[4]  FUSE: Shotgun 5 + Laser 4 -> Prism 5", the kept
## mechanics, then "loses: ..." (BoosterPack.fuse_option's text).
static func fuse_text(p_offer: PickOffer, to_label := Callable(), hints := true) -> String:
	var text := String(p_offer.fuse.get("text", ""))
	if not hints:
		return text
	var key := InputSetup.expand_keys("{key:choose_%d}" % (p_offer.cards.size() + 1), to_label)
	return "[%s]  %s" % [key, text]


## M50.4c1: a level-up offer with an EVOLVE choice (the choice after its cards).
func has_evolve() -> bool:
	return offer != null and not offer.pack and not offer.evolve.is_empty()


## M50.4c1: the EVOLVE choice's text: "[4]  EVOLVE: Pistol 6 + Haste -> MINIGUN: ...".
static func evolve_text(p_offer: PickOffer, to_label := Callable(), hints := true) -> String:
	var text := String(p_offer.evolve.get("text", ""))
	if not hints:
		return text
	var key := InputSetup.expand_keys("{key:choose_%d}" % (p_offer.cards.size() + 1), to_label)
	return "[%s]  %s" % [key, text]


## M50.1b: the PathRunner fused: `next` is the same pack for the new hand. The cards hide for
## FUSE_TIME (the fused card's title on the line), then come back with the input delay.
func after_fuse(next: PickOffer, title: String) -> void:
	if not _root.visible:
		return
	var f: Dictionary = offer.fuse if offer != null else {}
	_fuse_parts = {}
	if not f.is_empty():   # M50.7: the parents (their ranks from the hand before the fuse)
		_fuse_parts = {"a": StringName(f.a), "b": StringName(f.b), "id": StringName(f.id), "rank": int(f.get("rank", 4))}
		for h: Dictionary in offer.hand:
			_fuse_parts["rank_" + String(h.id)] = int(h.rank)
	_fuse_second = false
	var before: Array = offer.hand.duplicate(true) if offer != null else []
	offer = next
	_replacing = -1
	_fused_title = title
	_fuse_total = fuse_time()
	_fusing = _fuse_total
	if staged() and not f.is_empty():   # M48.6d: the stage's fuse moment
		stage.fusing(f, before, _fuse_total)
	_build()


## M50.7 review: the fuse's length: FUSE_BEAT in a real window (the result card reads), else
## FUSE_TIME (headless bots and tests keep theirs; reduce flashing keeps it short).
func fuse_time() -> float:
	if beats and staged():   # M48.6d: the stage's moment (the cards fly up, meet, the stamp, the note)
		return stage.fuse_time()
	return FUSE_BEAT if beats and not SaveGame.reduce_flashing() else FUSE_TIME


## M50.7 review: while the fuse shows its two parents, [{id, title, rank}] of them (the rail's hand
## shows them, not the result), else [].
func fuse_hand() -> Array:
	if not fusing() or _fuse_second or _fuse_parts.is_empty() or staged():   # M48.6d: the stage has its own
		return []
	var out := []
	for p: StringName in [_fuse_parts.a, _fuse_parts.b]:
		var w := WeaponDB.get_weapon(p)
		out.append({"id": p, "title": String(w.title) if w != null else String(p),
				"rank": int(_fuse_parts.get("rank_" + String(p), BoosterPack.FUSE_RANK))})
	return out


## M50.1b: the fuse animation is playing.
func fusing() -> bool:
	return _root.visible and _fusing > 0.0


## M50.1a: the replace step's choice j: "Replace Pistol 7" per hand card, then "Back".
## M50.1b review: `keep` (the waiting card's `keep`, BoosterPack.mark_keeps) is the hand card
## the new one links with: "Keep Shotgun 5: it links with the Laser", not a choice.
static func replace_text(p_offer: PickOffer, j: int, to_label := Callable(), hints := true, keep := -1,
		new_title := "") -> String:
	var text := "Back to the pack"
	if j < p_offer.hand.size() and j == keep:
		text = "Keep %s %d: it links with the %s" % [p_offer.hand[j].title, int(p_offer.hand[j].rank), new_title]
	elif j < p_offer.hand.size():
		text = "Replace %s %d" % [p_offer.hand[j].title, int(p_offer.hand[j].rank)]
	if not hints:
		return text
	return "[%s]  %s" % [InputSetup.expand_keys("{key:choose_%d}" % (j + 1), to_label), text]


## M50.2b: the give step's choice j: "Replace Pistol 12" per hand card (the given card's
## recipe partner adds "  (it links with the Laser)", ": Prism" once the `fusion` basic is
## live), then "Keep your hand".
static func give_text(p_offer: PickOffer, j: int, to_label := Callable(), hints := true) -> String:
	var c: Dictionary = p_offer.cards[0]
	var text := "Keep your hand"
	if j < p_offer.hand.size():
		text = "Replace %s %d" % [p_offer.hand[j].title, int(p_offer.hand[j].rank)]
		if j == int(c.get("links", -1)):
			var w := WeaponDB.get_weapon(c.id)
			text += "\n(it links with the %s%s)" % [w.title if w != null else String(c.id),
					": " + String(c.recipe) if String(c.get("recipe", "")) != "" else ""]
	if not hints:
		return text
	return "[%s]  %s" % [InputSetup.expand_keys("{key:choose_%d}" % (j + 1), to_label), text]


## M50.1a: the replace step is showing (the pack card waiting, else -1).
func replacing() -> int:
	return _replacing if _root.visible else -1


## M50.1b review: on the replace step, the hand card the waiting card keeps (-1 none).
func kept_slot() -> int:
	if offer == null or _replacing < 0 or _replacing >= offer.cards.size():
		return -1
	return int(offer.cards[_replacing].get("keep", -1))


func replace_count() -> int:
	return offer.hand.size() if offer != null else 0


## M50.1a: Back from the replace step to the same pack (no draw, no `picked`).
func back() -> void:
	if not can_choose() or _replacing < 0 or offer.give_step:
		return
	_replacing = -1
	_deal_fresh = false   # M48.6d: the same row again, face-up
	_build()
	_relock()
	went_back.emit(offer)


func _relock() -> void:
	for b in _buttons:
		b.disabled = true
	_locked_for = input_delay
	if _locked_for <= 0.0:
		_unlock()


## Card i's text: its key on the player's layout ({key:choose_n}, never a literal number),
## then the card's line. M47.3: `hints` false (the key_hints setting off) drops the key.
static func card_text(p_offer: PickOffer, i: int, to_label := Callable(), hints := true) -> String:
	if not hints:
		return p_offer.cards[i].text
	var key := InputSetup.expand_keys("{key:choose_%d}" % (i + 1), to_label)
	return "[%s]  %s" % [key, p_offer.cards[i].text]


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta / maxf(Engine.time_scale, 0.001)   # real time
		_toast.modulate = Color(1, 1, 1, clampf(_toast_left / TOAST_FADE, 0.0, 1.0))
		if _toast_left <= 0.0:
			_toast_left = 0.0
			_toast.visible = false
	if not _root.visible:
		return
	if RunState.is_paused_for(RunState.MENU):   # M47.3: the pause menu holds the lock
		return
	var real := delta / maxf(Engine.time_scale, 0.001)
	_pack_art.queue_redraw()
	if offer != null and offer.pack and _staged_built != staged():   # M48.6d: the cabinet came or went
		_build()
		if _locked_for <= 0.0 and _intro <= EPS and _outro <= EPS and _fusing <= 0.0:
			_unlock()
	if _staged_built:
		_place_hits()
	if _intro > EPS:   # M50.7: the pack drops and tears; the deal and the lock wait for it
		var was := beat_phase()
		_intro -= real
		if beat_phase() == &"tear" and was == &"drop" and (not _staged_built or stage.packs_intro()):
			_play(&"pack_tear")
		if _intro <= EPS:
			_intro = 0.0
			_reveal_t = 0.0
			_locked_for = input_delay
			_play(&"card_flip")
			if _locked_for <= 0.0:
				_unlock()
		_update_reveal()
		return
	if _outro > EPS:   # M50.7: the slot-in, then the pick lands
		_outro -= real
		_update_reveal()
		if _outro <= EPS:
			_outro = 0.0
			_play(&"card_slot")
			_land_pick(_outro_pick)
		return
	if _reveal_t >= 0.0:   # M50.2c: the deal (presentation only; the lock below is unchanged)
		_reveal_t += real
	if not _faces.is_empty():
		_update_reveal()
	if _fusing > 0.0:
		_fusing -= real   # real time
		_fuse_step()
		if _fusing <= 0.0:
			_fusing = 0.0
			_fuse_faces.clear()
			_reveal_t = 0.0   # M50.2c: the new hand's pack is dealt again
			_build()
			_relock()
		return
	if _locked_for <= 0.0:
		return
	_locked_for -= delta / maxf(Engine.time_scale, 0.001)   # real time
	if _locked_for <= 0.0:
		_unlock()


## M50.7: the fuse moment: the parents slide together over the first half, then the fused card
## flips in (a fade under reduce flashing). Inside fuse_time().
func _fuse_step() -> void:
	var k := clampf(1.0 - _fusing / _fuse_total, 0.0, 1.0)
	if _staged_built:   # M48.6d: the stage draws the moment; the chime when the two cards meet
		if k >= 0.42 and not _fuse_second:
			_fuse_second = true
			_play(&"fuse_chime")
		return
	if k >= 0.5 and not _fuse_second and not _fuse_parts.is_empty():
		_fuse_second = true
		for f in _fuse_faces:
			f.queue_free()
			_frames.erase(f)
		_build_fuse_faces()
		_play(&"fuse_chime")
	var reduce := SaveGame.reduce_flashing()
	if not _fuse_second:
		var e := k / 0.5
		for i in _fuse_faces.size():
			var f := _fuse_faces[i]
			f.offset = Vector2((1.0 if i == 0 else -1.0) * 70.0 * e * e, 0.0) if not reduce else Vector2.ZERO
			f.modulate = Color(1, 1, 1, 1.0 - 0.5 * e)
			f.queue_redraw()
		return
	for f in _fuse_faces:
		f.set_reveal(CardFace.reveal_at((k - 0.5) * _fuse_total, 0, reduce))
		f.queue_redraw()


func can_choose() -> bool:
	return _root.visible and _locked_for <= 0.0 and _fusing <= 0.0 and _intro <= EPS and _outro <= EPS \
			and not RunState.is_paused_for(RunState.MENU)


## Closes without a pick, for good (the session ended); the pause reason goes with it.
func dismiss() -> void:
	_dismissed = true
	if _root.visible:
		_root.visible = false
	_intro = 0.0
	_outro = 0.0
	_park(false)
	_toast_left = 0.0
	if _toast != null:
		_toast.visible = false
	if stage != null and is_instance_valid(stage):
		stage.closed()
	RunState.set_pause(PAUSE, false)


func _unlock() -> void:
	_locked_for = 0.0
	for i in _buttons.size():
		_buttons[i].disabled = _replacing >= 0 and i == kept_slot()
	# M50.7 review: the card under the mouse takes the focus (else the first): one lit card.
	for b in _buttons:
		if not b.disabled and b.is_hovered():
			b.grab_focus()
			return
	for b in _buttons:
		if not b.disabled:
			b.grab_focus()
			break


func _unhandled_input(event: InputEvent) -> void:
	if not can_choose():
		return
	for i in CHOICES:
		if event.is_action_pressed(StringName("choose_%d" % (i + 1))):
			choose(i)
			get_viewport().set_input_as_handled()
			return


## Pick card i (0-based): closes, unpauses, reports. M50.1a: in a pack, a NEW card on a full
## hand opens the replace step instead; there, choice j < hand size replaces that slot and
## the next one is Back.
func choose(i: int) -> void:
	if not can_choose():
		return
	var direct := true   # M50.7: picked straight off the pack (not through the replace step)
	if offer.give_step:   # M50.2b: replace slot i, or keep the hand (the last choice)
		if i < 0 or i > replace_count():
			return
		var given := offer
		_root.visible = false
		_give_face.visible = false
		RunState.set_pause(PAUSE, false)
		_park(false)
		give_done.emit(given, i if i < replace_count() else -1)
		return
	if _replacing >= 0:
		if i == replace_count():
			back()
			return
		if i < 0 or i > replace_count() or i == kept_slot():
			return
		offer.cards[_replacing]["replace"] = i
		i = _replacing
		_replacing = -1
		direct = false
	elif has_fuse() and i == offer.cards.size():
		for b in _buttons:
			b.disabled = true
		fuse_requested.emit(offer)
		return
	elif has_evolve() and i == offer.cards.size():
		pass   # M50.4c1: EVOLVE, reported as the index after the cards
	elif i < 0 or i >= offer.cards.size():
		return
	elif offer.pack and offer.cards[i].get("kind") == &"new" and offer.hand.size() >= offer.max_slots \
			and offer.max_slots > 0:
		_replacing = i
		_build()
		_relock()
		return

	var on_stage := staged()
	if beats and offer.pack and direct and (i < _faces.size() or on_stage):   # M50.7: the slot-in first, still paused
		for b in _buttons:
			b.disabled = true
		_outro_pick = i
		_outro_total = stage.outro_time() if on_stage else outro_time()   # M48.6d: the stage's flight
		_outro = _outro_total
		if on_stage:
			stage.picking(self, i)
		_update_reveal()
		return
	_land_pick(i)


## The pick closes the panel, unpauses and reports (M50.7: after the slot-in when beats play).
func _land_pick(i: int) -> void:
	var from := offer
	_root.visible = false
	RunState.set_pause(PAUSE, false)
	_park(false)
	picked.emit(from, i)


## M50.7: what a dressed level card reads beyond its dictionary: the path's enemy HP, the
## loadout (real fire rates, item mods), the card the session gave. Presentation only.
func card_ctx() -> Dictionary:
	var ctx := {"given": offer.given if offer != null else &""}
	if RunState.rules != null:
		ctx["hp_mult"] = RunState.rules.enemy_hp_mult
	if runner != null and is_instance_valid(runner) and runner.has_method(&"loadout"):
		ctx["loadout"] = runner.call(&"loadout")
	return ctx


# --- M50.4f: the focused choice, for the rail's slot bar (the sheet's "the slot that changes lifts") ---

## The focused choice's index (0-based, the EVOLVE choice after the cards), -1 none.
func focused_choice() -> int:
	if not is_open():
		return -1
	for i in _buttons.size():
		if _buttons[i].has_focus() and not _buttons[i].disabled:
			return i
	return -1


## What the dressed level-up shows, for the rail's ITEMS module and the flat slot bar ({} when no
## dressed level-up is open): {focus, choices: [{kind, id, from, to}], keys}. kind: weapon, item,
## new_weapon, new_item, filler or evolve (id: the base weapon, with into and catalyst).
## Presentation only.
func preview() -> Dictionary:
	if not is_open() or not dressed() or _replacing >= 0 or _fusing > 0.0:
		return {}
	var choices: Array[Dictionary] = []
	for c: Dictionary in offer.cards:
		var kind := "weapon"
		var k: StringName = c.get("kind", &"")
		if k == PickOffer.HP or k == PickOffer.BOOST:
			kind = "filler"
		elif c.get("item", false):
			kind = "new_item" if k == &"new" else "item"
		elif k == &"new":
			kind = "new_weapon"
		choices.append({"kind": kind, "id": StringName(c.get("id", &"")), "to": int(c.get("rank", 0)),
				"from": 0 if k == &"new" else int(c.get("rank", 1)) - 1})
	if has_evolve():
		choices.append({"kind": "evolve", "id": StringName(offer.evolve.get("from", &"")),
				"into": StringName(offer.evolve.get("into", &"")), "catalyst": StringName(offer.evolve.get("catalyst", &""))})
	var keys: Array[String] = []
	for i in choices.size():
		keys.append(InputSetup.expand_keys("{key:choose_%d}" % (i + 1)) if Settings.key_hints() else str(i + 1))
	return {"focus": focused_choice(), "choices": choices, "keys": keys}


func _on_focus_moved() -> void:
	if _slot_bar != null and is_instance_valid(_slot_bar):
		_slot_bar.queue_redraw()


## M50.4f (the sheet's flat half, "Items 3 + 2"): the flat look's slot bar under the dressed
## cards, in Palette roles: one card per slot (LV, the flat gun or glyph, the name, the dots),
## the focused choice's slot lifted with a cyan ring and its next dot glowing, EVOLVE's base
## ringed in pink, then "LV n", the full bar, "Level up" and the per-key legend. Steady.
class SlotBar:
	extends Control
	var panel: Node

	const W := 600.0
	const H := 128.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(W, H)

	func _draw() -> void:
		var runner: Node = panel.get(&"runner") if panel != null else null
		if runner == null or not is_instance_valid(runner):
			return
		var d := RailState.items_for(runner)
		if d.is_empty():
			return
		var font := ThemeDB.fallback_font
		var text := Palette.color(&"ui_text")
		var dim := Palette.color(&"ui_dim")
		var info := Palette.color(&"info")
		var back := StyleBoxFlat.new()
		back.bg_color = Color(Palette.color(&"shadow"), 0.55)
		back.set_corner_radius_all(14)
		draw_style_box(back, Rect2(Vector2.ZERO, size))
		var weapons: Array = d.weapons
		var passives: Array = d.passives
		var n_w := int(d.slots)
		var n_p := int(d.passive_slots)
		draw_string(font, Vector2(16, 24), "Items", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, text)
		draw_string(font, Vector2(62, 24), "%d + %d" % [weapons.size(), passives.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, info)
		draw_string(font, Vector2(130, 23), "%d weapons · cap lv %d" % [n_w, int(d.cap)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
		var slot_w := floorf((size.x - 32.0 - (14.0 if n_p > 0 else 0.0)) / float(maxi(1, n_w + n_p))) - 8.0
		var x := 16.0
		for i in n_w:
			_slot(Rect2(Vector2(x, 32), Vector2(slot_w, 62)), weapons[i] if i < weapons.size() else {}, int(d.cap), false,
					int(d.get("new_slot", -1)) == i)
			x += slot_w + 8.0
		if n_p > 0:
			draw_string(font, Vector2(x + 6, 23), "%d passives" % n_p, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
			draw_rect(Rect2(Vector2(x + 2, 36), Vector2(2, 54)), Color(dim, 0.3))
			x += 14.0
			for i in n_p:
				_slot(Rect2(Vector2(x, 32), Vector2(slot_w, 62)), passives[i] if i < passives.size() else {}, int(d.cap), true,
						int(d.get("new_passive", -1)) == i)
				x += slot_w + 8.0
		var picking := bool(d.get("picking", false))
		var lv := "LV %d" % int(d.level)
		draw_string(font, Vector2(16, 112), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, info)
		var bx := 16.0 + font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 12.0
		var bar := Rect2(Vector2(bx, 102), Vector2(size.x - bx - 96.0, 6))
		var bb := StyleBoxFlat.new()
		bb.bg_color = Color(dim, 0.2)
		bb.set_corner_radius_all(3)
		draw_style_box(bb, bar)
		var xp := 1.0 if picking else float(d.xp)
		if xp > 0.0:
			var fb := StyleBoxFlat.new()
			fb.bg_color = info
			fb.set_corner_radius_all(3)
			draw_style_box(fb, Rect2(bar.position, Vector2(bar.size.x * xp, bar.size.y)))
		draw_string(font, Vector2(bar.end.x + 12, 110), "Level up" if picking else "%d%%" % roundi(100.0 * xp),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text)
		var legend := String(d.get("legend", ""))
		if legend != "":
			draw_string(font, Vector2(bx, 124), legend, HORIZONTAL_ALIGNMENT_LEFT, size.x - bx - 12.0, 11, dim)

	func _slot(r: Rect2, item: Dictionary, cap: int, passive: bool, new_well: bool) -> void:
		var font := ThemeDB.fallback_font
		var info := Palette.color(&"info")
		var edge := Palette.color(&"card_item") if passive else info
		var dim := Palette.color(&"ui_dim")
		var lift := bool(item.get("lift", false)) or new_well
		if lift:
			r.position.y -= 6.0
		var box := StyleBoxFlat.new()
		box.bg_color = Color(Palette.color(&"shadow"), 0.4)
		box.set_corner_radius_all(10)
		if item.is_empty():
			box.border_color = info if new_well else Color(dim, 0.25)
			box.set_border_width_all(3 if new_well else 1)
			draw_style_box(box, r)
			draw_string(font, Vector2(r.position.x, r.get_center().y + 8), "+", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22,
					info if new_well else Color(dim, 0.5))
			if new_well:
				draw_string(font, Vector2(r.position.x, r.position.y + 16), "NEW", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, info)
			return
		var rank := int(item.rank)
		var evo := bool(item.get("evo", false))
		var maxed := rank >= cap and not evo and not passive
		box.border_color = Palette.color(&"card_evolve") if maxed or evo else Color(edge, 0.5)
		box.set_border_width_all(2)
		if lift:
			box.border_color = info
			box.set_border_width_all(3)
		draw_style_box(box, r)
		if bool(item.get("evo_ring", false)):   # EVOLVE would take this weapon
			var ring := StyleBoxFlat.new()
			ring.bg_color = Color(info, 0.0)
			ring.border_color = Palette.color(&"hit")
			ring.set_border_width_all(3)
			ring.set_corner_radius_all(13)
			draw_style_box(ring, r.grow(4))
		draw_string(font, r.position + Vector2(8, 15), "EVO" if evo else "LV %d" % rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				info if lift else dim)
		if maxed:
			var mp := StyleBoxFlat.new()
			mp.bg_color = Palette.color(&"card_evolve")
			mp.set_corner_radius_all(6)
			var mr := Rect2(Vector2(r.end.x - 38, r.position.y + 5), Vector2(32, 14))
			draw_style_box(mp, mr)
			draw_string(font, mr.position + Vector2(0, 11), "MAX", HORIZONTAL_ALIGNMENT_CENTER, mr.size.x, 10, Palette.color(&"shadow"))
		var gun := StringName(item.icon) in WeaponGlyph.FLAT_GUNS
		WeaponGlyph.draw_card_flat(self, item.icon, r.position + Vector2(r.size.x * 0.5, 28), 46.0 if gun else 20.0, edge)
		draw_string(font, Vector2(r.position.x, r.position.y + 48), String(item.title), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12,
				Palette.color(&"ui_text"))
		if evo:
			return
		var step := minf(11.0, (r.size.x - 12.0) / maxf(1.0, cap))
		var x0 := r.position.x + (r.size.x - (cap - 1) * step) * 0.5
		for k in cap:
			var c := Vector2(x0 + k * step, r.position.y + 55)
			var lit := k < rank
			if bool(item.get("next", false)) and k == rank:   # the dot this pick lights
				draw_circle(c, 5.5, Color(info, 0.35))
				draw_circle(c, 3.5, info)
				continue
			draw_circle(c, 3.0, edge if lit else Color(dim, 0.25))


## M50.7 (the Arcade_Pack mockup's P8): the booster pack over the dimmed game during the intro: it
## drops in from above (DROP_TIME, eased), then its top strip tears off and the pack fades as the
## cards are dealt (TEAR_TIME), a small shake and a white rim on the tear. Reduce flashing: a fade
## in, then out, in place: no shake, no flash. RailArt's PACK grid, drawn big; nothing baked.
## Review: printed "BOOSTER" and "3 CARDS" in the rail's block capitals, the top strip (the grid's
## first two rows) peeling off with "RRRIP", three light shafts and six sparks out of the tear (none
## under reduce flashing); it sits lower, clear of the title.
class PackArt:
	extends Control
	var panel: Node

	const CELL := 18.0
	const TEXT_CELL := 2.0
	const STRIP_ROWS := 2

	func _draw() -> void:
		if panel == null or not is_instance_valid(panel):
			return
		var pr: Array = panel.call(&"intro_progress")
		if int(pr[0]) < 0:
			return
		var k := float(pr[1])
		var tearing := int(pr[0]) == 1
		var reduce := SaveGame.reduce_flashing()
		var grid_w := float((RailArt.PACK[0] as String).length()) * CELL
		var grid_h := float(RailArt.PACK.size()) * CELL
		var centre := Vector2(size.x * 0.5, size.y * 0.6)
		var at := centre - Vector2(grid_w, grid_h) * 0.5
		var alpha := 1.0
		if not tearing:
			if reduce:
				alpha = k
			else:
				var e := 1.0 - pow(1.0 - k, 3.0)
				at.y = lerpf(-grid_h - 20.0, at.y, e)
		else:
			alpha = 1.0 - k * k
			if not reduce:
				at.x += sin(k * 40.0) * 6.0 * (1.0 - k)
		at = at.round()
		modulate = Color(1, 1, 1, alpha)
		var ink := RailArt.c(&"ink")
		var body: Array = RailArt.PACK.slice(STRIP_ROWS)
		var top: Array = RailArt.PACK.slice(0, STRIP_ROWS)
		var body_at := at + Vector2(0, STRIP_ROWS * CELL)
		if tearing and not reduce:   # the light out of the tear, behind the pack
			var mouth := body_at + Vector2(grid_w * 0.5, 0)
			for i in 3:
				var ang := -PI * 0.5 + (float(i) - 1.0) * 0.45
				var dir := Vector2(cos(ang), sin(ang))
				var side := Vector2(-dir.y, dir.x)
				var reach := 120.0 + 140.0 * k
				draw_colored_polygon(PackedVector2Array([mouth - side * 10.0, mouth + side * 10.0,
						mouth + dir * reach + side * 34.0, mouth + dir * reach - side * 34.0]),
						Color(RailArt.c(&"gold_hi"), 0.28 * (1.0 - k)))
		RailArt.draw_grid(self, body, RailArt.PACK_LEGEND, body_at, CELL, true)
		# The print: "BOOSTER" over the emblem, "3 CARDS" under the lower band.
		_print("BOOSTER", body_at + Vector2(grid_w * 0.5, CELL * 2.0 + 2.0), ink)
		_print("3 CARDS", body_at + Vector2(grid_w * 0.5, CELL * 9.0 + 2.0), ink)
		if not tearing:
			RailArt.draw_grid(self, top, RailArt.PACK_LEGEND, at, CELL, true)
			return
		# The strip peels up and away, "RRRIP" on it.
		var lift := Vector2(30.0 * k, -90.0 * k) if not reduce else Vector2.ZERO
		var strip_at := (at + lift).round()
		draw_set_transform(strip_at + Vector2(0, STRIP_ROWS * CELL), -0.35 * k if not reduce else 0.0, Vector2.ONE)
		RailArt.draw_grid(self, top, RailArt.PACK_LEGEND, Vector2(0, -STRIP_ROWS * CELL), CELL, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rip := "RRRIP"
		var rw := RailArt.digits_width(rip, TEXT_CELL)
		var rip_at := (strip_at + Vector2(grid_w * 0.5 - rw * 0.5, -7.0 * TEXT_CELL - 10.0)).round()
		draw_rect(Rect2(rip_at - Vector2(4, 3), Vector2(rw + 8, 7 * TEXT_CELL + 6)), ink)
		RailArt.draw_digits(self, rip_at, rip, TEXT_CELL, RailArt.c(&"gold_hi"))
		if reduce:
			return
		if k < 0.35:   # the white rim on the tear
			draw_rect(Rect2(at, Vector2(grid_w, grid_h)).grow(6.0), Color(1, 1, 1, 0.5 * (1.0 - k / 0.35)), false, 4.0)
		var mouth2 := body_at + Vector2(grid_w * 0.5, 0)
		for i in 6:   # sparks
			var ang := -PI * 0.5 + (float(i) - 2.5) * 0.38
			var p := mouth2 + Vector2(cos(ang), sin(ang)) * (24.0 + 150.0 * k)
			var sz := roundf(6.0 * (1.0 - k)) + 2.0
			draw_rect(Rect2((p - Vector2(sz, sz) * 0.5).round(), Vector2(sz, sz)), RailArt.c(&"gold_hi"))

	func _print(t: String, mid_top: Vector2, col: Color) -> void:
		var w := RailArt.digits_width(t, TEXT_CELL)
		RailArt.draw_digits(self, (mid_top - Vector2(w * 0.5, 0)).round(), t, TEXT_CELL, col)

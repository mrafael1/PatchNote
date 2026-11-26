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
## faces (CardFace: a frame by rarity, the weapon's picture, rank badge and pips, the NEW / RARE
## +2 / FUSE marks), each the visible part of a frameless Button (same keys, focus, click). They
## are dealt face-down and flip in sequence inside the INPUT_DELAY (CardFace.reveal_at; a fade
## only under reduce_flashing), so no choice opens earlier or later. The give step and the
## replace step show their card's face over the choices; the hand under a pack and the 1-card
## toast use the small faces. Tier 0 before S9's `skin ui`, CardFaceArt's Pixel frames after it.
## A level-up offer (not a pack: Auto, S7) is M50.4b's dressed LevelCard panel above (M50.5:
## Arcade's CardArt is CardFaceArt, Auto's level-up art kept the CardArt name).

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
const TOAST_TIME := 1.6  ## M50.2a: the 1-card pack's toast (real time)
const TOAST_FADE := 0.4  ## its fade-out at the end

var offer: PickOffer
var input_delay := INPUT_DELAY   ## tests set 0

var _root: Control
var _line: Label
var _cards: HBoxContainer
var _buttons: Array[Button] = []
var _frames: Array[Control] = []
var _hand_row: HBoxContainer
var _replacing := -1        ## M50.1a: the pack card waiting for a slot (-1: the pack itself)
var _locked_for := 0.0
var _fusing := 0.0          ## M50.1b: seconds left of the fuse animation
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


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(Palette.SCRIM_PICK, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
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
	_toast_face.queue_redraw()
	_toast.modulate = Color(1, 1, 1, 1)
	_toast.visible = true
	_toast_left = TOAST_TIME


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
	RunState.set_pause(PAUSE, true)
	_reveal_t = 0.0
	_build()
	_locked_for = input_delay
	_root.visible = true
	if _locked_for <= 0.0:
		_unlock()
	return true


## M50.2b: opens the give step (PickOffer.give_step: one given card, a full hand). The caller
## defers, as for open().
func open_give(p_offer: PickOffer) -> bool:
	if _dismissed or p_offer == null or not p_offer.give_step or p_offer.cards.is_empty():
		return false
	offer = p_offer
	_replacing = 0
	_fusing = 0.0
	RunState.set_pause(PAUSE, true)
	_reveal_t = 0.0
	_build()
	_locked_for = input_delay
	_root.visible = true
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
	var hints := Settings.key_hints()
	_give_face.visible = offer.give_step or _replacing >= 0
	if offer.give_step:
		var c: Dictionary = offer.cards[0]
		_line.text = offer.line
		_give_face.face = CardFace.face_of(c, "", c.get("rarity") == BoosterPack.RARE)   # M50.2c: the gold card
		_faces.append(_give_face)
		for j in replace_count() + 1:
			_add_button(give_text(offer, j, Callable(), hints), choose.bind(j), false, j == int(c.get("links", -1)), true)
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
			_add_button(replace_text(offer, j, Callable(), hints, kept_slot(), new_name), choose.bind(j), false,
					j == kept_slot(), true)
		return
	if _fusing > 0.0:
		_line.text = "Fusing... %s" % _fused_title
		return
	_line.text = offer.line
	if dressed():
		_build_dressed(hints)
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
	var f := CardFace.new()
	f.face = face
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(f)
	_cards.add_child(b)
	_frames.append(b)
	_buttons.append(b)
	_faces.append(f)


## M50.2c: the faces' reveal (flip or fade), shine and focus for the time since the deal.
func _update_reveal() -> void:
	var reduce := SaveGame.reduce_flashing()
	var n := _faces.size()
	for i in n:
		var f := _faces[i]
		if _reveal_t >= 0.0:
			f.set_reveal(CardFace.reveal_at(_reveal_t, i, reduce))
		var rare: bool = f.face.get("style") in [&"card_rare", &"card_give", &"card_epic"]   # M50.6: epic shines too
		f.shine = CardFace.shine_at(_reveal_t, n, reduce) if rare and _reveal_t >= 0.0 else -1.0
		var b := f.get_parent() as Button
		f.lit = b != null and not b.disabled and (b.has_focus() or b.is_hovered())
		f.queue_redraw()


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
		b.tooltip_text = card_text(offer, i, Callable(), false)
		for style: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
			b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		b.pressed.connect(choose.bind(i))
		b.focus_entered.connect(_on_focus_moved)
		var card := LevelCard.new()
		card.set_card(LevelCard.data_for(offer.cards[i], offer.cap, key, offer.evolve), pixel)
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
	b.tooltip_text = evolve_text(offer, Callable(), false)
	for style: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
		b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	b.pressed.connect(choose.bind(n))
	b.focus_entered.connect(_on_focus_moved)
	var card := LevelCard.new()
	card.set_card(LevelCard.data_for_evolve(offer.evolve, key), Skins.is_on(&"ui_panel"))
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
	for h: Dictionary in offer.hand:   # M50.2c: the small card faces
		var p := CardFace.new()
		p.mini = &"hand"
		p.face = CardFace.hand_face(h)
		p.custom_minimum_size = CardFace.MINI_HAND
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hand_row.add_child(p)


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
	offer = next
	_replacing = -1
	_fused_title = title
	_fusing = FUSE_TIME
	_build()


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
	if _reveal_t >= 0.0:   # M50.2c: the deal (presentation only; the lock below is unchanged)
		_reveal_t += delta / maxf(Engine.time_scale, 0.001)
	if not _faces.is_empty():
		_update_reveal()
	if _fusing > 0.0:
		_fusing -= delta / maxf(Engine.time_scale, 0.001)   # real time
		if _fusing <= 0.0:
			_fusing = 0.0
			_reveal_t = 0.0   # M50.2c: the new hand's pack is dealt again
			_build()
			_relock()
		return
	if _locked_for <= 0.0:
		return
	_locked_for -= delta / maxf(Engine.time_scale, 0.001)   # real time
	if _locked_for <= 0.0:
		_unlock()


func can_choose() -> bool:
	return _root.visible and _locked_for <= 0.0 and _fusing <= 0.0 and not RunState.is_paused_for(RunState.MENU)


## Closes without a pick, for good (the session ended); the pause reason goes with it.
func dismiss() -> void:
	_dismissed = true
	if _root.visible:
		_root.visible = false
	_toast_left = 0.0
	if _toast != null:
		_toast.visible = false
	RunState.set_pause(PAUSE, false)


func _unlock() -> void:
	_locked_for = 0.0
	for i in _buttons.size():
		_buttons[i].disabled = _replacing >= 0 and i == kept_slot()
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
	if offer.give_step:   # M50.2b: replace slot i, or keep the hand (the last choice)
		if i < 0 or i > replace_count():
			return
		var given := offer
		_root.visible = false
		_give_face.visible = false
		RunState.set_pause(PAUSE, false)
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

	var from := offer
	_root.visible = false
	RunState.set_pause(PAUSE, false)
	picked.emit(from, i)


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

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
## arrow, its tags (NEW, RARE +2) and its gain; a rare card sits in a frame of the look's
## card_rare role. Under the cards the hand at 60% size. A NEW card on a full hand opens the
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
## M50.2a (pack tuning, D3): a 1-card pack has no choice, so it never opens the panel: toast()
## shows a short line at the game's bottom right, next to the rail's PACK module ("Pack:
## Pistol +1", gold when rare) for TOAST_TIME of real time, fading out at the end (a fade only,
## no shine, whatever reduce_flashing says). No pause, no input. A plain label until M50.2c
## dresses it as a small card face.

signal picked(offer: PickOffer, index: int)
## M50.1a: the replace step's Back (the pack stays open).
signal went_back(offer: PickOffer)
## M50.1b: the pack's FUSE was chosen (the PathRunner answers with after_fuse).
signal fuse_requested(offer: PickOffer)

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
var _toast: Label         ## M50.2a: the 1-card pack's line
var _toast_left := 0.0


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
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_font_size_override(&"font_size", 28)
	_line.add_theme_color_override(&"font_color", Palette.INFO)
	_line.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	_line.add_theme_constant_override(&"outline_size", 6)
	column.add_child(_line)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override(&"separation", 20)
	column.add_child(_cards)
	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override(&"separation", 12)
	column.add_child(_hand_row)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 60)
	column.add_child(gap)
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


func is_open() -> bool:
	return _root.visible


## M50.2a: a 1-card pack, applied by the PathRunner without a pause: its line shows for
## TOAST_TIME (a new toast replaces the one showing).
func toast(p_offer: PickOffer) -> void:
	if _dismissed or p_offer == null or p_offer.cards.is_empty():
		return
	var c: Dictionary = p_offer.cards[0]
	_toast.text = toast_text(c)
	_toast.add_theme_color_override(&"font_color",
			Palette.color(&"card_rare") if c.get("rarity") == BoosterPack.RARE else Palette.INFO)
	_toast.modulate = Color(1, 1, 1, 1)
	_toast.visible = true
	_toast_left = TOAST_TIME


## M50.2a: the toast is showing (tests, captures).
func toasting() -> bool:
	return _toast != null and _toast.visible


## M50.2a: "Pack: Pistol +1", "Pack: Pistol +2  RARE", "Pack: Laser 1 joins".
static func toast_text(c: Dictionary) -> String:
	var w := WeaponDB.get_weapon(c.get("id", &""))
	var title := String(w.title) if w != null else String(c.get("id", ""))
	var rare: bool = c.get("rarity") == BoosterPack.RARE
	var text := ""
	if c.get("kind") == &"upgrade":
		text = "Pack: %s +%d" % [title, int(c.get("rank", 0)) - int(c.get("from", 0))]
	else:
		text = "Pack: %s %d joins" % [title, int(c.get("rank", 1))]
	return text + ("  RARE" if rare else "")


## Opens now (the caller defers: never pause the tree inside a physics callback). Refused
## once dismissed.
func open(p_offer: PickOffer) -> bool:
	if _dismissed or p_offer == null or p_offer.cards.is_empty():
		return false
	offer = p_offer
	_replacing = -1
	_fusing = 0.0
	RunState.set_pause(PAUSE, true)
	_build()
	_locked_for = input_delay
	_root.visible = true
	if _locked_for <= 0.0:
		_unlock()
	return true


## The buttons for the offer (a pack's cards, or its replace step).
func _build() -> void:
	for b in _frames:
		b.queue_free()
	_frames.clear()
	_buttons.clear()
	for c in _hand_row.get_children():
		c.queue_free()
	var hints := Settings.key_hints()
	if _replacing >= 0:
		_line.text = "Your hand is full. %s replaces:" % offer.cards[_replacing].get("title", "")
		var new_name := String(WeaponDB.get_weapon(offer.cards[_replacing].id).title)
		for j in replace_count() + 1:
			_add_button(replace_text(offer, j, Callable(), hints, kept_slot(), new_name), choose.bind(j), false,
					j == kept_slot())
		return
	if _fusing > 0.0:
		_line.text = "Fusing... %s" % _fused_title
		return
	_line.text = offer.line
	for i in offer.cards.size():
		var text := pack_card_text(offer, i, Callable(), hints) if offer.pack else card_text(offer, i, Callable(), hints)
		_add_button(text, choose.bind(i), offer.pack and offer.cards[i].get("rarity") == BoosterPack.RARE)
	if has_fuse():
		_add_button(fuse_text(offer, Callable(), hints), choose.bind(offer.cards.size()), false, true)
	if offer.pack:
		_add_hand_preview()


func _add_button(text: String, on_press: Callable, rare: bool, fuse := false) -> void:
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
	b.custom_minimum_size = Vector2(300, 150)
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


## M50.1a: the hand under a pack's cards, at HAND_SCALE.
func _add_hand_preview() -> void:
	var label := Label.new()
	label.text = "Hand (%d/%d):" % [offer.hand.size(), offer.max_slots]
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", Palette.INFO)
	label.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	label.add_theme_constant_override(&"outline_size", 4)
	_hand_row.add_child(label)
	for h: Dictionary in offer.hand:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(300, 150) * HAND_SCALE * Vector2(1.0, 0.5)
		Skins.dress_panel(p)
		var l := Label.new()
		l.text = "%s %d" % [h.title, int(h.rank)]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override(&"font_size", roundi(18 * HAND_SCALE) + 2)
		p.add_child(l)
		_hand_row.add_child(p)


## M50.1a: a pack card's text: "[1]  Pistol 6 -> 7  RARE +2" then its gain.
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
	if not can_choose() or _replacing < 0:
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
	if _fusing > 0.0:
		_fusing -= delta / maxf(Engine.time_scale, 0.001)   # real time
		if _fusing <= 0.0:
			_fusing = 0.0
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

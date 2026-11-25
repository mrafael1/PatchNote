class_name PickPanel
extends CanvasLayer
## The in-run pick (PLAN v9 2): up to three weapon cards over the paused game, for Auto's
## level-ups now (Arsenal's cards in M46). Its own panel, not a PromptPanel (whose signal
## and open() take an Offer and whose pause reason is &"prompt"): it pauses with &"pick" on
## open, choose and dismiss, so a panel closed at the session's end never leaves the tree
## paused. A different frame from the debrief's cards: no mascot portrait, no "ship".
## Keys 1-3 (choose_1..3, named on the player's layout), click, pad focus; 0.4 s of input
## delay after opening (the debrief's, M42.1).

signal picked(offer: PickOffer, index: int)

const PAUSE := &"pick"
const INPUT_DELAY := 0.4
const LAYER := 72   ## over the HUD (50) and the mascot (60), under the debrief (95)

var offer: PickOffer
var input_delay := INPUT_DELAY   ## tests set 0

var _root: Control
var _line: Label
var _cards: HBoxContainer
var _buttons: Array[Button] = []
var _locked_for := 0.0
var _dismissed := false   ## the run is over: never open again


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
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 60)
	column.add_child(gap)


func is_open() -> bool:
	return _root.visible


## Opens now (the caller defers: never pause the tree inside a physics callback). Refused
## once dismissed.
func open(p_offer: PickOffer) -> bool:
	if _dismissed or p_offer == null or p_offer.cards.is_empty():
		return false
	offer = p_offer
	RunState.set_pause(PAUSE, true)
	_line.text = p_offer.line
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	for i in p_offer.cards.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 150)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override(&"font_size", 18)
		b.text = card_text(p_offer, i, Callable(), Settings.key_hints())
		b.disabled = true
		b.pressed.connect(choose.bind(i))
		Skins.dress_button(b)   # M48a: the look's UI panel (no look: today's theme)
		_cards.add_child(b)
		_buttons.append(b)
	_locked_for = input_delay
	_root.visible = true
	if _locked_for <= 0.0:
		_unlock()
	return true


## Card i's text: its key on the player's layout ({key:choose_n}, never a literal number),
## then the card's line. M47.3: `hints` false (the key_hints setting off) drops the key.
static func card_text(p_offer: PickOffer, i: int, to_label := Callable(), hints := true) -> String:
	if not hints:
		return p_offer.cards[i].text
	var key := InputSetup.expand_keys("{key:choose_%d}" % (i + 1), to_label)
	return "[%s]  %s" % [key, p_offer.cards[i].text]


func _process(delta: float) -> void:
	if not _root.visible or _locked_for <= 0.0:
		return
	if RunState.is_paused_for(RunState.MENU):   # M47.3: the pause menu holds the lock
		return
	_locked_for -= delta / maxf(Engine.time_scale, 0.001)   # real time
	if _locked_for <= 0.0:
		_unlock()


func can_choose() -> bool:
	return _root.visible and _locked_for <= 0.0 and not RunState.is_paused_for(RunState.MENU)


## Closes without a pick, for good (the session ended); the pause reason goes with it.
func dismiss() -> void:
	_dismissed = true
	if _root.visible:
		_root.visible = false
	RunState.set_pause(PAUSE, false)


func _unlock() -> void:
	_locked_for = 0.0
	for b in _buttons:
		b.disabled = false
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not can_choose():
		return
	for i in 3:
		if event.is_action_pressed(StringName("choose_%d" % (i + 1))):
			choose(i)
			get_viewport().set_input_as_handled()
			return


## Pick card i (0-based): closes, unpauses, reports.
func choose(i: int) -> void:
	if not can_choose() or i < 0 or i >= offer.cards.size():
		return
	var from := offer
	_root.visible = false
	RunState.set_pause(PAUSE, false)
	picked.emit(from, i)

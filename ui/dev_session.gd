class_name DevSessionScreen
extends CanvasLayer
## The dev session (PLAN v5 4.1 step 2): the AI's opening line, then its cards, then the
## pick. A mockup session's cards show each take's still (letterboxed); hovering or
## focusing a card enlarges it. The agenda card is labelled and tinted. A session with
## nothing to ship shows its line and "Play". Pick with 1/2/3, the mouse, or focus +
## accept; like the prompt, it ignores input for a moment after opening.

signal picked(index: int)
signal play_requested

const STILL := Vector2(320, 180)
const STILL_BIG := Vector2(400, 225)

var session: DevSession

var _root: Control
var _title: Label
var _line: Label
var _cards: HBoxContainer
var _play: Button
var _buttons: Array[Button] = []
var _stills: Array[TextureRect] = []
var _locked_for := 0.0


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.98)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 26)
	_root.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 34)
	column.add_child(_title)

	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(900, 0)
	_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_line.add_theme_font_size_override(&"font_size", 22)
	_line.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	column.add_child(_line)

	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override(&"separation", 24)
	column.add_child(_cards)

	_play = Button.new()
	_play.custom_minimum_size = Vector2(240, 52)
	_play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play.add_theme_font_size_override(&"font_size", 22)
	_play.pressed.connect(play)
	column.add_child(_play)


func is_open() -> bool:
	return _root.visible


func open(p_session: DevSession) -> void:
	session = p_session
	_title.text = "DEV SESSION  ·  %s" % session.version_before.label()
	_line.text = "AI: " + session.opening
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_stills.clear()
	for i in session.cards.size():
		_add_card(i)
	_play.visible = session.cards.is_empty()
	_play.text = "Play %s" % session.version_before.label()
	_locked_for = Tuning.prompt_input_delay
	for b in _buttons:
		b.disabled = _locked_for > 0.0
	_root.visible = true
	if _locked_for <= 0.0:
		_unlock()


func _add_card(i: int) -> void:
	var card := session.cards[i]
	var b := Button.new()
	# The content sits in a box over the button, so the button sets the card's size.
	b.custom_minimum_size = Vector2(440, 380) if card.take else Vector2(340, 250)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(pick.bind(i))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override(&"separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	if card.agenda:
		b.self_modulate = Color(1.0, 0.75, 0.55)
		box.add_child(_label(DevSession.AGENDA_LABEL.to_upper(), 15, Color(1.0, 0.75, 0.55)))
	var take: MockupTake = card.take
	if take:
		var still := TextureRect.new()
		still.texture = take.image
		still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # letterboxed
		still.custom_minimum_size = STILL
		still.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		still.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(still)
		_stills.append(still)
		b.mouse_entered.connect(_enlarge.bind(still, true))
		b.mouse_exited.connect(_enlarge.bind(still, false))
		b.focus_entered.connect(_enlarge.bind(still, true))
		b.focus_exited.connect(_enlarge.bind(still, false))
	box.add_child(_label("[%d]  %s" % [i + 1, DevSession.card_title(card)], 22, Color.WHITE))
	box.add_child(_label("\"%s\"" % DevSession.card_line(card), 16, Color(1, 1, 1, 0.8)))
	_cards.add_child(b)
	_buttons.append(b)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _enlarge(still: TextureRect, big: bool) -> void:
	if is_instance_valid(still):
		still.custom_minimum_size = STILL_BIG if big else STILL


## The size a card's still shows at (tests).
func still_size(i: int) -> Vector2:
	return _stills[i].custom_minimum_size if i < _stills.size() else Vector2.ZERO


func card_button(i: int) -> Button:
	return _buttons[i] if i < _buttons.size() else null


func _process(delta: float) -> void:
	if not _root.visible or _locked_for <= 0.0:
		return
	_locked_for -= delta
	if _locked_for <= 0.0:
		_unlock()


func _unlock() -> void:
	for b in _buttons:
		b.disabled = false
	_focus_first.call_deferred()


## Deferred: the screen may be gone by then (a pick in the same frame).
func _focus_first() -> void:
	if not is_inside_tree() or not _root.visible:
		return
	if not _buttons.is_empty() and is_instance_valid(_buttons[0]):
		_buttons[0].grab_focus()
	elif _play.visible:
		_play.grab_focus()


## True once the screen is open with cards and accepts a pick.
func can_pick() -> bool:
	return _root.visible and _locked_for <= 0.0 and session != null and session.can_pick()


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or _locked_for > 0.0:
		return
	for i in 3:
		if event.is_action_pressed(StringName("choose_%d" % (i + 1))):
			pick(i)
			get_viewport().set_input_as_handled()
			return


## Pick card i (0-based). Closes the screen and reports it; the flow ships it.
func pick(i: int) -> void:
	if not can_pick() or i < 0 or i >= session.cards.size():
		return
	_root.visible = false
	picked.emit(i)


## "Play" on a session with nothing to pick.
func play() -> void:
	if not _root.visible or not session.cards.is_empty():
		return
	_root.visible = false
	play_requested.emit()


func close() -> void:
	_root.visible = false

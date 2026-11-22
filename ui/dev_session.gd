class_name DevSessionScreen
extends CanvasLayer
## The dev session (PLAN v5 4.1 step 2, v6 2): the AI's opening line, the fork's
## question as a title, its cards, then the pick. A mockup fork's cards show each take's
## still (letterboxed); hovering or focusing a card enlarges it. The agenda card is
## labelled and tinted. Once the session offers Rework, a last card of its own style
## opens the rework list: one row per answered fork with a shelf, a button per shelved
## option, and "Back" (a fork session) or "Keep it as it is" (a REWORK-only session,
## which opens on the list). A session with nothing to ship shows its line and "Play".
## Pick with 1/2/3, 4 for Rework, the mouse, or focus + accept; like the prompt, it
## ignores input for a moment after opening and after switching view.

signal picked(index: int)
signal rework_requested(fork_id: StringName, to_id: StringName)
signal keep_requested
signal play_requested

const STILL := Vector2(320, 180)
const STILL_BIG := Vector2(400, 225)
const ROW_STILL := Vector2(192, 108)
const CARD_GAP := 24
const SIDE_MARGIN := 24
const REWORK_CARD_WIDTH := 240
const REWORK_TINT := Color(0.55, 0.85, 1.0)

var session: DevSession

var _root: Control
var _title: Label
var _line: Label
var _question: Label
var _cards: HBoxContainer
var _list: ScrollContainer
var _rows: VBoxContainer
var _list_button: Button      ## "Back" or "Keep it as it is"
var _play: Button
var _buttons: Array[Button] = []
var _rework_card: Button
var _row_buttons: Array[Button] = []
var _row_targets: Array[Array] = []   ## [fork id, to id] per row button
var _stills: Array[TextureRect] = []
var _locked_for := 0.0
## The still sizes of this session's cards: STILL and STILL_BIG, or smaller when the
## cards must shrink to fit the screen (fit_cards).
var _still_size := STILL
var _still_big := STILL_BIG


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
	column.add_theme_constant_override(&"separation", 22)
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

	_question = Label.new()
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.custom_minimum_size = Vector2(900, 0)
	_question.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_question.add_theme_font_size_override(&"font_size", 28)
	column.add_child(_question)

	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override(&"separation", CARD_GAP)
	column.add_child(_cards)

	_list = ScrollContainer.new()
	_list.custom_minimum_size = Vector2(1000, 460)
	_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_list)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 16)
	_list.add_child(_rows)

	_list_button = Button.new()
	_list_button.custom_minimum_size = Vector2(280, 52)
	_list_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list_button.add_theme_font_size_override(&"font_size", 22)
	_list_button.pressed.connect(_on_list_button)
	column.add_child(_list_button)

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
	_question.text = session.fork.question if session.fork else ""
	_question.visible = session.fork != null
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_stills.clear()
	_rework_card = null
	var with_rework := session.shape == DevSession.FORK and session.can_rework()
	var mockup := session.fork != null and session.fork.mockup
	var width := card_width(session.cards.size(), mockup, with_rework, _screen_width())
	_still_size = STILL
	_still_big = STILL_BIG
	if width - 24.0 < STILL.x:
		_still_size = STILL * ((width - 24.0) / STILL.x)
	if width - 12.0 < STILL_BIG.x:
		_still_big = STILL_BIG * ((width - 12.0) / STILL_BIG.x)
	for i in session.cards.size():
		_add_card(i, width)
	if with_rework:
		_add_rework_card()
	_play.text = "Play %s" % session.version_before.label()
	_root.visible = true
	if session.shape == DevSession.REWORK:
		_show_list()
	else:
		_show_cards()


func _screen_width() -> float:
	return get_viewport().get_visible_rect().size.x if is_inside_tree() else 1280.0


## The width of each option card, so that n of them (and the Rework card) fit the
## screen: the full 440 (mockup) or 340 when there is room, less when not (found in
## M32: three mockup cards were 1368 px on the 1280 px screen since M29).
static func card_width(n: int, mockup: bool, with_rework: bool, screen: float) -> float:
	var full := 440.0 if mockup else 340.0
	if n <= 0:
		return full
	var room := screen - 2.0 * SIDE_MARGIN - CARD_GAP * (n - 1)
	if with_rework:
		room -= REWORK_CARD_WIDTH + CARD_GAP
	return minf(full, floorf(room / n))


func _show_cards() -> void:
	_cards.visible = true
	_list.visible = false
	_list_button.visible = false
	_question.visible = session.fork != null
	_question.text = session.fork.question if session.fork else ""
	_play.visible = session.cards.is_empty() and session.shape != DevSession.REWORK
	_lock()


func _show_list() -> void:
	_build_rows()
	_cards.visible = false
	_question.visible = true
	_question.text = "Rework: swap one answer for one on the shelf"
	_list.visible = true
	_list_button.visible = true
	_list_button.text = DevSession.KEEP_LABEL if session.shape == DevSession.REWORK else "Back"
	_play.visible = false
	_lock()


## True while the rework list shows.
func list_open() -> bool:
	return _root.visible and _list.visible


func _lock() -> void:
	_locked_for = Tuning.prompt_input_delay
	for b in _all_buttons():
		b.disabled = _locked_for > 0.0
	if _locked_for <= 0.0:
		_unlock()


func _all_buttons() -> Array[Button]:
	var out: Array[Button] = []
	out.append_array(_buttons)
	out.append_array(_row_buttons)
	out.append(_list_button)
	return out


func _add_card(i: int, width: float) -> void:
	var card := session.cards[i]
	var b := _card_button(card.take != null)
	b.custom_minimum_size.x = width
	b.pressed.connect(pick.bind(i))
	var box: VBoxContainer = b.get_child(0)
	if card.agenda:
		b.self_modulate = Color(1.0, 0.75, 0.55)
		box.add_child(_label(DevSession.AGENDA_LABEL.to_upper(), 15, Color(1.0, 0.75, 0.55)))
	var take: MockupTake = card.take
	if take:
		var still := _still(take.image, _still_size)
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


## The Rework card: last, outlined in its own colour, key 4.
func _add_rework_card() -> void:
	var b := _card_button(session.fork.mockup)
	b.custom_minimum_size.x = REWORK_CARD_WIDTH
	b.self_modulate = REWORK_TINT
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0.06, 0.1, 0.14)
	outline.border_color = REWORK_TINT
	outline.set_border_width_all(3)
	outline.set_corner_radius_all(6)
	b.add_theme_stylebox_override(&"normal", outline)
	b.pressed.connect(open_rework)
	var box: VBoxContainer = b.get_child(0)
	box.add_child(_label("[4]  %s" % DevSession.REWORK_TITLE, 22, REWORK_TINT))
	box.add_child(_label(DevSession.REWORK_PITCH, 16, Color(1, 1, 1, 0.8)))
	_cards.add_child(b)
	_buttons.append(b)
	_rework_card = b


## A card-sized button with a content box over it (the button sets the card's size).
func _card_button(tall: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(440, 380) if tall else Vector2(340, 250)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override(&"separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	return b


## One row per answered fork with a shelf: its question, "now: Tank", then "→ Bomber"
## per shelved option (with its still on a mockup fork).
func _build_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_row_buttons.clear()
	_row_targets.clear()
	for row in DevSession.rework_rows():
		var f: Fork = row.fork
		var from: Change = row.from
		var panel := VBoxContainer.new()
		panel.add_theme_constant_override(&"separation", 6)
		var head := _label("%s   now: %s" % [f.question, from.short_name()], 20, Color.WHITE)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.add_child(head)
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 14)
		panel.add_child(line)
		for to: Change in row.to:
			var b := Button.new()
			b.text = "→ %s" % to.short_name()
			b.add_theme_font_size_override(&"font_size", 20)
			b.custom_minimum_size = Vector2(220, 52)
			if to.take != null and to.take.image != null:
				b.icon = to.take.image
				b.expand_icon = true
				b.custom_minimum_size = Vector2(ROW_STILL.x + 160, ROW_STILL.y + 12)
			b.pressed.connect(rework.bind(f.id, to.id))
			line.add_child(b)
			_row_buttons.append(b)
			_row_targets.append([f.id, to.id])
		_rows.add_child(panel)


func _still(texture: Texture2D, size: Vector2) -> TextureRect:
	var still := TextureRect.new()
	still.texture = texture
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # letterboxed
	still.custom_minimum_size = size
	still.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return still


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(220, 0)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _enlarge(still: TextureRect, big: bool) -> void:
	if is_instance_valid(still):
		still.custom_minimum_size = _still_big if big else _still_size


## The still sizes this session uses, resting and enlarged (tests).
func still_sizes() -> Array[Vector2]:
	return [_still_size, _still_big]


## The size a card's still shows at (tests).
func still_size(i: int) -> Vector2:
	return _stills[i].custom_minimum_size if i < _stills.size() else Vector2.ZERO


func card_button(i: int) -> Button:
	return _buttons[i] if i < _buttons.size() else null


func has_rework_card() -> bool:
	return _rework_card != null


## The rework list's swap buttons, as [fork id, to id] (tests).
func rework_targets() -> Array[Array]:
	return _row_targets


func row_button(i: int) -> Button:
	return _row_buttons[i] if i < _row_buttons.size() else null


func list_button() -> Button:
	return _list_button


func _process(delta: float) -> void:
	if not _root.visible or _locked_for <= 0.0:
		return
	_locked_for -= delta
	if _locked_for <= 0.0:
		_unlock()


func _unlock() -> void:
	for b in _all_buttons():
		if is_instance_valid(b):
			b.disabled = false
	_focus_first.call_deferred()


## Deferred: the screen may be gone by then (a pick in the same frame).
func _focus_first() -> void:
	if not is_inside_tree() or not _root.visible:
		return
	if _list.visible:
		var first: Button = _row_buttons[0] if not _row_buttons.is_empty() else _list_button
		if is_instance_valid(first):
			first.grab_focus()
	elif not _buttons.is_empty() and is_instance_valid(_buttons[0]):
		_buttons[0].grab_focus()
	elif _play.visible:
		_play.grab_focus()


func _ready_for_input() -> bool:
	return _root.visible and _locked_for <= 0.0 and session != null and not session.done


## True while the rework list shows and accepts a swap or its bottom button.
func list_ready() -> bool:
	return _ready_for_input() and _list.visible


## True once the screen is open with cards and accepts a pick.
func can_pick() -> bool:
	return _ready_for_input() and not _list.visible and session.can_pick()


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or _locked_for > 0.0 or _list.visible:
		return
	for i in 3:
		if event.is_action_pressed(StringName("choose_%d" % (i + 1))):
			pick(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"choose_4") and _rework_card != null:
		open_rework()
		get_viewport().set_input_as_handled()


## Pick card i (0-based). Closes the screen and reports it; the flow ships it.
func pick(i: int) -> void:
	if not can_pick() or i < 0 or i >= session.cards.size():
		return
	_root.visible = false
	picked.emit(i)


## The Rework card: switches to the rework list.
func open_rework() -> void:
	if not _ready_for_input() or _list.visible or _rework_card == null:
		return
	_show_list()


## A row's swap button: closes the screen and reports it; the flow ships it.
func rework(fork_id: StringName, to_id: StringName) -> void:
	if not _ready_for_input() or not _list.visible:
		return
	_root.visible = false
	rework_requested.emit(fork_id, to_id)


## "Back" returns to the cards; "Keep it as it is" ends a REWORK-only session.
func _on_list_button() -> void:
	if not _ready_for_input() or not _list.visible:
		return
	if session.shape == DevSession.REWORK:
		_root.visible = false
		keep_requested.emit()
	else:
		_show_cards()


## "Back" or "Keep it as it is" (tests).
func press_list_button() -> void:
	_on_list_button()


## "Play" on a session with nothing to pick.
func play() -> void:
	if not _root.visible or not session.cards.is_empty() or session.shape == DevSession.REWORK:
		return
	_root.visible = false
	play_requested.emit()


func close() -> void:
	_root.visible = false

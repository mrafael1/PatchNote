class_name PromptPanel
extends CanvasLayer
## The AI's proposal: up to three cards over the paused game (PLAN 6).
## Pick with 1/2/3, the mouse, or focus + accept on a gamepad. For a short moment
## after opening it ignores input, so a key held during play cannot pick a card.

signal chosen(offer: Offer, mutation: Mutation)

const BIG_COLOR := Color(1.0, 0.8, 0.45)

var offer: Offer

var _root: Control
var _line: Label
var _cards: HBoxContainer
var _buttons: Array[Button] = []
var _locked_for := 0.0
var _major: HBoxContainer       ## "MAJOR UPDATE" header with a lock, BIG prompts only
var _frame: PanelContainer      ## around the cards; a gold border on BIG prompts
var _footer: Label              ## "This one stays..." under BIG prompts
var _frame_big: StyleBoxFlat
var _frame_small: StyleBoxEmpty
var _dismissed := false   ## the run is over: never open again


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 28)
	_root.add_child(column)

	_major = HBoxContainer.new()
	_major.alignment = BoxContainer.ALIGNMENT_CENTER
	_major.add_theme_constant_override(&"separation", 12)
	_major.add_child(LockIcon.new(30.0, BIG_COLOR))
	var major_label := Label.new()
	major_label.text = Dialogue.MAJOR_LABEL
	major_label.add_theme_font_size_override(&"font_size", 32)
	major_label.add_theme_color_override(&"font_color", BIG_COLOR)
	_major.add_child(major_label)
	_major.add_child(LockIcon.new(30.0, BIG_COLOR))
	_major.visible = false
	column.add_child(_major)

	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_font_size_override(&"font_size", 26)
	_line.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	column.add_child(_line)

	_frame_small = StyleBoxEmpty.new()
	_frame_big = StyleBoxFlat.new()
	_frame_big.bg_color = Color(0.12, 0.08, 0.02, 0.6)
	_frame_big.border_color = BIG_COLOR
	_frame_big.set_border_width_all(3)
	_frame_big.set_corner_radius_all(6)
	_frame_big.set_content_margin_all(18)
	_frame = PanelContainer.new()
	_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_frame.add_theme_stylebox_override(&"panel", _frame_small)
	column.add_child(_frame)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override(&"separation", 24)
	_frame.add_child(_cards)

	_footer = Label.new()
	_footer.text = Dialogue.BIG_FOOTER
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.add_theme_font_size_override(&"font_size", 20)
	_footer.add_theme_color_override(&"font_color", BIG_COLOR)
	_footer.visible = false
	column.add_child(_footer)


func is_open() -> bool:
	return _root.visible


## Opens at the end of the frame, so it never pauses the tree in the middle of a
## physics callback.
func open(p_offer: Offer) -> void:
	_open.call_deferred(p_offer)


func _open(p_offer: Offer) -> void:
	if _dismissed:
		return
	offer = p_offer
	RunState.set_pause(&"prompt", true)
	_line.text = "AI: " + offer.line
	_major.visible = offer.big
	_footer.visible = offer.big
	_frame.add_theme_stylebox_override(&"panel", _frame_big if offer.big else _frame_small)
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	for i in offer.cards.size():
		var m := offer.cards[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(330, 230)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override(&"font_size", 18)
		b.text = card_text(offer, i)
		if offer.agenda.has(m):
			# The AI's own pick, against the player's taste: labelled and tinted.
			b.self_modulate = Color(1.0, 0.75, 0.55)
		elif offer.big and m != offer.keep:
			b.self_modulate = Color(1.0, 0.92, 0.75)
		b.disabled = true
		b.pressed.connect(choose.bind(i))
		_cards.add_child(b)
		_buttons.append(b)
	_locked_for = Tuning.prompt_input_delay
	_root.visible = true
	if _locked_for <= 0.0:
		_unlock()


## The text on card i: number, title, effect and the AI's line. The AI's own pick is
## labelled; on a BIG prompt the genre is named and the Keep card says what it keeps.
static func card_text(offer: Offer, i: int) -> String:
	var m := offer.cards[i]
	if offer.big and m == offer.keep:
		return "[%d]  %s: %s\n\nNo change. The current engine stays." % [i + 1,
				Dialogue.KEEP_LABEL, m.genre_label]
	var title := m.title
	if offer.big:
		title = "%s\n(%s)" % [m.title, m.genre_label]
	if offer.agenda.has(m):
		return "%s\n[%d]  %s\n\n%s\n\n\"%s\"" % [Dialogue.AGENDA_LABEL.to_upper(), i + 1,
				title, m.description, Dialogue.agenda_line(offer.prompt_index)]
	return "[%d]  %s\n\n%s\n\n\"%s\"" % [i + 1, title, m.description, m.line_proposal]


func _process(delta: float) -> void:
	if not _root.visible or _locked_for <= 0.0:
		return
	_locked_for -= delta
	if _locked_for <= 0.0:
		_unlock()


## True once the panel is open and accepts a pick.
func can_choose() -> bool:
	return _root.visible and _locked_for <= 0.0


## Closes the panel without a pick, for good (the run ended).
func dismiss() -> void:
	_dismissed = true
	if _root.visible:
		_root.visible = false
		RunState.set_pause(&"prompt", false)


func _unlock() -> void:
	for b in _buttons:
		b.disabled = false
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or _locked_for > 0.0:
		return
	# is_action_pressed ignores key repeat, so only a fresh press counts.
	for i in 3:
		if event.is_action_pressed(StringName("choose_%d" % (i + 1))):
			choose(i)
			get_viewport().set_input_as_handled()
			return


## Pick card i (0-based). Closes the panel and reports the choice.
func choose(i: int) -> void:
	if not _root.visible or _locked_for > 0.0 or i < 0 or i >= offer.cards.size():
		return
	var picked := offer.cards[i]
	var from := offer
	_root.visible = false
	RunState.set_pause(&"prompt", false)
	chosen.emit(from, picked)

class_name PromptPanel
extends CanvasLayer
## The AI's proposal: up to three cards over the paused game (PLAN 6).
## Pick with 1/2/3, the mouse, or focus + accept on a gamepad. For a short moment
## after opening it ignores input, so a key held during play cannot pick a card.

signal chosen(offer: Offer, mutation: Mutation)

var offer: Offer

var _root: Control
var _line: Label
var _cards: HBoxContainer
var _buttons: Array[Button] = []
var _locked_for := 0.0
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

	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_font_size_override(&"font_size", 26)
	_line.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	column.add_child(_line)

	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override(&"separation", 24)
	column.add_child(_cards)


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
		b.disabled = true
		b.pressed.connect(choose.bind(i))
		_cards.add_child(b)
		_buttons.append(b)
	_locked_for = Tuning.prompt_input_delay
	_root.visible = true
	if _locked_for <= 0.0:
		_unlock()


## The text on card i: number, title, effect and the AI's line. The AI's own pick is
## labelled.
static func card_text(offer: Offer, i: int) -> String:
	var m := offer.cards[i]
	var title := m.title
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

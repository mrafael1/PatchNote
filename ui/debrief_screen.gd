class_name DebriefScreen
extends CanvasLayer
## After a campaign session (PLAN v8 1.2 step 5, section 2): the AI's debrief lines for
## how it went, then the patch notes of the version the session ships, then the way on.
## M37's form is plain text; M38 brings the mascot, its expressions and the fork cards.
##
## Won or stopped: "Next session" (or "To be continued" after the campaign's last
## session). Died: "Retry" (same session, a new seed) and "Move on" (the session counts
## as done, the AI owns it). Enter presses the first button; 1 and 2 pick by order.
## The game stays paused while it is open.

signal next_requested
signal retry_requested
signal move_on_requested

const NEXT := "Next session"
const LAST := "To be continued"
const RETRY := "Retry"
const MOVE_ON := "Move on"
const INPUT_DELAY := 0.4   ## real seconds before a button works (no carried-over clicks)

var session: SessionDef
var outcome: StringName = &""   ## won, died or stopped
var lines: Array[Line] = []
## The seed the next scene plays; -1 = random. Tools set it for a repeatable chain.
var next_seed := -1

var _root: Control
var _title: Label
var _body: VBoxContainer
var _notes: Label
var _buttons: HBoxContainer
var _opened_msec := 0


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(760, 0)
	column.add_theme_constant_override(&"separation", 18)
	center.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 20)
	_title.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	column.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 10)
	column.add_child(_body)
	_notes = Label.new()
	_notes.add_theme_font_size_override(&"font_size", 20)
	_notes.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	column.add_child(_notes)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 16)
	column.add_child(_buttons)


## Outcome names a debrief reads (Line conditions) from the run loop's.
static func outcome_name(run_outcome: StringName) -> StringName:
	match run_outcome:
		&"win":
			return &"won"
		&"lose":
			return &"died"
	return &"stopped"


func open(p_session: SessionDef, run_outcome: StringName, hits: int) -> void:
	session = p_session
	outcome = outcome_name(run_outcome)
	lines = Line.passing(session.debrief_lines(), CampaignDB.line_context(session, outcome, hits))
	var index := CampaignDB.index_of(session.id)
	_title.text = "SESSION %d · %s" % [index, session.title.to_upper()]   # S0 is the first
	for child in _body.get_children():
		child.queue_free()
	for line in lines:
		var l := Label.new()
		l.text = line.text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override(&"font_size", 26)
		_body.add_child(l)
	for child in _buttons.get_children():
		child.queue_free()
	if outcome == &"died":
		_notes.text = ""
		_add_button(RETRY, func() -> void: retry_requested.emit())
		_add_button(MOVE_ON, func() -> void: move_on_requested.emit())
	else:
		_notes.text = notes_text(session)
		_add_button(LAST if index + 1 >= CampaignDB.size() else NEXT, func() -> void: next_requested.emit())
	_opened_msec = Time.get_ticks_msec()
	RunState.set_pause(&"debrief", true)
	_root.visible = true
	_focus_first.call_deferred()


## "v0.2.0 · what changed" and a bullet per note.
static func notes_text(s: SessionDef) -> String:
	var text := "%s · what changed" % CampaignDB.version_after(s).label()
	for n in s.notes:
		text += "\n  • " + n
	return text


func _add_button(label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(220, 52)
	b.add_theme_font_size_override(&"font_size", 22)
	b.pressed.connect(func() -> void:
		if can_choose():
			action.call())
	_buttons.add_child(b)


func _focus_first() -> void:
	if is_inside_tree() and _root.visible and _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Button).grab_focus()


func is_open() -> bool:
	return _root.visible


func can_choose() -> bool:
	return is_open() and Time.get_ticks_msec() - _opened_msec >= int(INPUT_DELAY * 1000.0)


## The labels of the buttons on offer, in order (tests, the bot).
func choices() -> Array[String]:
	var out: Array[String] = []
	for b in _buttons.get_children():
		if not b.is_queued_for_deletion():
			out.append((b as Button).text)
	return out


## Presses the button labelled `label` (the bot, tests). False if it is not on offer.
func choose(label: String) -> bool:
	if not can_choose():
		return false
	match label:
		NEXT, LAST:
			if outcome == &"died":
				return false
			next_requested.emit()
		RETRY:
			if outcome != &"died":
				return false
			retry_requested.emit()
		MOVE_ON:
			if outcome != &"died":
				return false
			move_on_requested.emit()
		_:
			return false
	return true


func close() -> void:
	_root.visible = false
	RunState.set_pause(&"debrief", false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not can_choose():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var options := choices()
	var pick := -1
	match key.keycode:
		KEY_1, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			pick = 0
		KEY_2:
			pick = 1
	if pick >= 0 and pick < options.size():
		get_viewport().set_input_as_handled()
		choose(options[pick])

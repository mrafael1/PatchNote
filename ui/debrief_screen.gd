class_name DebriefScreen
extends CanvasLayer
## After a campaign session (PLAN v8 1.2 step 5, section 2). The game dims and the
## mascot sits large in the left third (the caret before it has a face). Its lines come
## one by one, typed (Space, Enter or a click finishes a line or moves on; a line can't
## be skipped in its first MIN_LINE seconds; a read line moves on by itself). Then the
## session's fork, if it has one: the question, and the options as cards (keys 1-3; a
## mascot option shows the live body). Then the patch notes and the way on.
##
## Won or stopped: "Next session" (or "To be continued" after the campaign's last
## session). Died: "Retry" (same session, a new seed) and "Move on" (the session counts
## as done, the AI owns it; its `ended` lines play and its fork is asked then), except in an overrun session, where
## going down is the end and the way on is Next session. Enter presses the first button;
## 1 and 2 pick by order. The game stays paused while it is open.

signal next_requested
signal retry_requested
signal move_on_requested

const NEXT := "Next session"
const LAST := "To be continued"
const RETRY := "Retry"
const MOVE_ON := "Move on"
const INPUT_DELAY := 0.4   ## real seconds before a button works (no carried-over clicks)
const MIN_LINE := 0.3      ## real seconds before a line can be skipped
const TYPE_CPS := 45.0
const LINE_FONT := 24
const LINE_MAX_W := 620.0
const BIG := 3.0           ## the mascot's scale here (the corner's is 1.12)

const LINES := &"lines"
const FORK := &"fork"
const DONE := &"done"

var session: SessionDef
var outcome: StringName = &""   ## won, died or stopped
var lines: Array[Line] = []     ## the debrief lines that passed their conditions
var phase: StringName = &""
var picks: Array[Change] = []   ## the fork options chosen here, in the order asked (M42.1)
## The first pick (the mascot at S3, the enemy at S4), or null. Read-only.
var picked: Change:
	get:
		return picks.front() if not picks.is_empty() else null
var moved_on := false           ## Move on was pressed (the fork, if any, comes after)
var big_body: MascotBody
## The seed the next scene plays; -1 = random. Tools set it for a repeatable chain.
var next_seed := -1
var input_delay := INPUT_DELAY  ## tests set 0
var said: Array[String] = []    ## every line shown, in order (tests)

var _root: Control
var _stage: Control
var _title: Label
var _body: VBoxContainer
var _cards: HBoxContainer
var _notes: Label
var _buttons: HBoxContainer
var _hint: Label
var _pending: Array[Line] = []
var _typing: Label
var _line: Line
var _chars := 0.0
var _line_t := 0.0
var _asked: StringName = &""    ## the fork whose question is queued
var _buttons_msec := 0
var _cards_msec := 0


var events: Array = []   ## the events played this attempt (open())
var hits_seen := 0       ## the hits taken this attempt (open()), for the `ended` lines

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
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 32
	row.offset_right = -48
	row.add_theme_constant_override(&"separation", 24)
	_root.add_child(row)
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(380, 0)
	_stage.size_flags_stretch_ratio = 0.5
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.resized.connect(_place_body)
	row.add_child(_stage)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(700, 0)
	column.add_theme_constant_override(&"separation", 16)
	center.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 20)
	_title.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	column.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 10)
	column.add_child(_body)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override(&"separation", 16)
	column.add_child(_cards)
	_notes = Label.new()
	_notes.add_theme_font_size_override(&"font_size", 20)
	_notes.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	column.add_child(_notes)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 16)
	column.add_child(_buttons)
	_hint = Label.new()
	_hint.text = "Space · click: next"
	_hint.add_theme_font_size_override(&"font_size", 14)
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.3))
	column.add_child(_hint)


## Outcome names a debrief reads (Line conditions) from the run loop's.
static func outcome_name(run_outcome: StringName) -> StringName:
	match run_outcome:
		&"win":
			return &"won"
		&"lose":
			return &"died"
	return &"stopped"


## The body the debrief shows for `s`: the save's mascot once the session has a face,
## the caret before.
static func body_for(s: SessionDef) -> StringName:
	if s == null or not s.face:
		return MascotBody.CARET
	var m := SaveGame.mascot()
	return m if MascotBody.is_body(m) else MascotBody.DEFAULT


## events: the scripted events played this attempt (their event:<id> lines pass).
func open(p_session: SessionDef, run_outcome: StringName, hits: int, p_events: Array = []) -> void:
	session = p_session
	outcome = outcome_name(run_outcome)
	events = p_events
	hits_seen = hits
	lines = Line.passing(session.debrief_lines(), CampaignDB.line_context(session, outcome, hits, events))
	picks.clear()
	moved_on = false
	_asked = &""
	said.clear()
	_title.text = "SESSION %d · %s" % [CampaignDB.index_of(session.id), session.title.to_upper()]   # S0 is the first
	_clear(_body)
	_clear(_cards)
	_clear(_buttons)
	_notes.text = ""
	_set_body(body_for(session))
	_pending = lines.duplicate()
	phase = LINES
	_line = null
	RunState.set_pause(&"debrief", true)
	_root.visible = true
	_next_line()


func _set_body(body_id: StringName) -> void:
	if big_body != null:
		big_body.queue_free()
	big_body = MascotBody.make(body_id)
	big_body.gentle = SaveGame.reduce_flashing()
	big_body.scale = Vector2.ONE * BIG
	_stage.add_child(big_body)
	_place_body()


func _place_body() -> void:
	if big_body != null:
		big_body.position = Vector2(_stage.size.x * 0.5, _stage.size.y * 0.45)


## An overrun session ends when you go down: that death is the way on, not a retry.
func death_expected() -> bool:
	return session != null and session.goal == SessionDef.OVERRUN


## The session's next fork still to ask here, in asked_forks() order: not answered in
## the save nor picked in this debrief (null when none is left).
func fork() -> Fork:
	if session == null:
		return null
	if outcome == &"died" and not death_expected() and not moved_on:
		return null
	for id in session.asked_forks():
		var f := ChangeDB.get_fork(id)
		if f == null or f.is_answered():
			continue
		if picks.any(func(c: Change) -> bool: return c.fork == id):
			continue
		return f
	return null


## The picks after the first (S3's dash and its direction, M42.1/M42.2).
func more_picks() -> Array[Change]:
	return picks.slice(1)


func fork_options() -> Array[Change]:
	var f := fork()
	return f.changes() if f != null else [] as Array[Change]


# --- Lines ------------------------------------------------------------------------

func _next_line() -> void:
	if _line != null and big_body != null:
		big_body.say_end()
	if _pending.is_empty():
		_line = null
		_typing = null
		_after_lines()
		return
	_line = _pending.pop_front()
	_chars = 0.0
	_line_t = 0.0
	said.append(_line.text)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override(&"panel", Mascot.bubble_style())
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_typing = Label.new()
	_typing.text = _line.text
	_typing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_typing.custom_minimum_size.x = Mascot.bubble_width(_line.text, LINE_FONT, LINE_MAX_W)
	_typing.add_theme_font_size_override(&"font_size", LINE_FONT)
	_typing.add_theme_color_override(&"font_color", MascotBody.INK)
	_typing.visible_characters = 0
	bubble.add_child(_typing)
	_body.add_child(bubble)
	big_body.set_expression(_line.expression)
	big_body.say_start()
	_hint.visible = true


func _typed() -> bool:
	return _line == null or _chars >= _line.text.length()


func _finish_typing() -> void:
	if _line == null:
		return
	_chars = _line.text.length()
	_typing.visible_characters = -1
	big_body.say_end()


## Space / Enter / click while the lines play: finish the line, or move on from it.
func advance() -> void:
	if phase != LINES or _line == null or _line_t < MIN_LINE:
		return
	if not _typed():
		_finish_typing()
	else:
		_next_line()


## Every line still to come, at once (the bot, tests): stops at the fork's cards or the
## buttons.
func finish_lines() -> void:
	var guard := 64
	while phase == LINES and guard > 0:
		guard -= 1
		_finish_typing()
		_next_line()


func _process(delta: float) -> void:
	if not is_open() or phase != LINES or _line == null:
		return
	_line_t += delta
	if not _typed():
		_chars = minf(_line.text.length(), _chars + TYPE_CPS * delta)
		_typing.visible_characters = int(_chars)
		if _typed():
			big_body.say_end()
	elif _line_t >= _line.text.length() / TYPE_CPS + SessionRunner.read_seconds(_line.text):
		_next_line()


## The lines ran out: ask the fork (its question is one more line, then the cards), or
## show the notes and the way on.
func _after_lines() -> void:
	var f := fork()
	if f != null and _asked != f.id:
		_asked = f.id
		_pending.append(Line.make(f.question, &"thinking"))
		_next_line()
		return
	if f != null:
		_show_cards(f)
		return
	_finish()


# --- The fork ---------------------------------------------------------------------

func _show_cards(f: Fork) -> void:
	phase = FORK
	_hint.visible = false
	_clear(_cards)
	var options := f.changes()
	for i in options.size():
		_cards.add_child(_card(options[i], i))
	big_body.set_expression(&"thinking")
	_cards_msec = Time.get_ticks_msec()
	_focus_card.call_deferred()


func _card(c: Change, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(210, 290)
	b.focus_mode = Control.FOCUS_ALL
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_right = -12
	box.offset_top = 10
	box.offset_bottom = -10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	b.add_child(box)
	var key := Label.new()
	key.text = str(index + 1)
	key.add_theme_font_size_override(&"font_size", 14)
	key.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.45))
	box.add_child(key)
	if c.kind == &"mascot":
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0, 130)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(holder)
		var preview := MascotBody.make(c.take.id)
		preview.gentle = SaveGame.reduce_flashing()
		preview.scale = Vector2.ONE * 1.1
		preview.position = Vector2(93, 65)
		preview.t = 0.4 * index   # out of step with each other
		holder.add_child(preview)
		b.mouse_entered.connect(func() -> void: preview.set_expression(&"happy"))
		b.mouse_exited.connect(func() -> void: preview.set_expression(&"idle"))
		b.focus_entered.connect(func() -> void: preview.set_expression(&"happy"))
		b.focus_exited.connect(func() -> void: preview.set_expression(&"idle"))
	elif c.take != null and c.take.image != null:
		var still := TextureRect.new()
		still.texture = c.take.image
		still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		still.custom_minimum_size = Vector2(0, 110)
		still.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(still)
	var title := Label.new()
	title.text = c.short_name()
	title.add_theme_font_size_override(&"font_size", 22)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var pitch := Label.new()
	pitch.text = c.pitch
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.add_theme_font_size_override(&"font_size", 15)
	pitch.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))
	pitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pitch)
	b.pressed.connect(func() -> void:
		if cards_ready():
			pick(index))
	return b


## The cards take player input input_delay after they show: a Space tap meant for the
## line before cannot pick the focused card (M42.1 review). pick() itself is ungated.
func cards_ready() -> bool:
	return phase == FORK and Time.get_ticks_msec() - _cards_msec >= int(input_delay * 1000.0)


func _focus_card() -> void:
	if phase == FORK and _cards.get_child_count() > 0 and _cards.get_child(0).is_inside_tree():
		(_cards.get_child(0) as Button).grab_focus()


## Picks option `index` of the fork on screen. A mascot option swaps the body in at once
## and it says its first line; the save ships it when the debrief is left.
func pick(index: int) -> bool:
	if phase != FORK:
		return false
	var options := fork_options()
	if index < 0 or index >= options.size():
		return false
	var c: Change = options[index]
	picks.append(c)
	_clear(_cards)
	phase = LINES
	if c.kind == &"mascot":
		_set_body(c.take.id)
		big_body.set_expression(&"surprised")
		big_body.glitch(0.35)
	elif c.kind in [&"dash", &"dash_aim"]:
		big_body.set_expression(&"happy")
	if c.take != null and c.take.line != "":
		_pending.append(Line.make(c.take.line, &"happy"))
	_next_line()
	return true


# --- The way on -------------------------------------------------------------------

func _finish() -> void:
	phase = DONE
	_hint.visible = false
	if big_body != null:
		big_body.say_end()
	_clear(_buttons)
	if outcome == &"died" and not death_expected() and not moved_on:
		_notes.text = ""
		_add_button(RETRY, func() -> void: choose(RETRY))
		_add_button(MOVE_ON, func() -> void: choose(MOVE_ON))
	else:
		_notes.text = notes_text(session, picked, more_picks())
		var last := CampaignDB.index_of(session.id) + 1 >= CampaignDB.size()
		var label := LAST if last else NEXT
		_add_button(label, func() -> void: choose(label))
	_buttons_msec = Time.get_ticks_msec()
	_focus_first.call_deferred()


## "v0.2.0 · what changed" and a bullet per note, then one per fork pick, in order.
static func notes_text(s: SessionDef, pick: Change = null, more: Array[Change] = []) -> String:
	var text := "%s · what changed" % CampaignDB.version_after(s).label()
	for n in s.notes:
		text += "\n  • " + n
	if pick != null:
		text += "\n  • " + pick.title
	for c in more:
		if c != null:
			text += "\n  • " + c.title
	return text


func _add_button(label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(220, 52)
	b.add_theme_font_size_override(&"font_size", 22)
	b.pressed.connect(action)
	_buttons.add_child(b)


func _focus_first() -> void:
	if is_inside_tree() and _root.visible and _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Button).grab_focus()


func is_open() -> bool:
	return _root.visible


func can_choose() -> bool:
	return is_open() and phase == DONE \
			and Time.get_ticks_msec() - _buttons_msec >= int(input_delay * 1000.0)


## The labels of the buttons on offer, in order (empty until the lines and the fork are
## through).
func choices() -> Array[String]:
	var out: Array[String] = []
	if phase != DONE:
		return out
	for b in _buttons.get_children():
		if not b.is_queued_for_deletion():
			out.append((b as Button).text)
	return out


## Presses the button labelled `label` (the bot, tests). False if it is not on offer.
## Move on with a fork still to ask asks it first; its Next then moves on.
func choose(label: String) -> bool:
	if not can_choose() or not label in choices():
		return false
	match label:
		NEXT, LAST:
			if moved_on:
				move_on_requested.emit()
			else:
				next_requested.emit()
		RETRY:
			retry_requested.emit()
		MOVE_ON:
			moved_on = true
			var late := _ended_lines()   # the lines that wait for "over for good" (M42)
			if fork() != null or not late.is_empty():
				_clear(_buttons)
				phase = LINES
				_pending = late
				if _pending.is_empty():
					_after_lines()
				else:
					_next_line()
			else:
				move_on_requested.emit()
	return true


## The `ended` debrief lines that pass now that the player moved on after a death: the
## session is over for good, so its ending plays (then the fork, the notes, the way on).
func _ended_lines() -> Array[Line]:
	var ended := session.debrief_lines().filter(func(l: Line) -> bool: return l.when == &"ended")
	var typed: Array[Line] = []
	typed.assign(ended)
	return Line.passing(typed, CampaignDB.line_context(session, outcome, hits_seen, events, true))


func close() -> void:
	_root.visible = false
	RunState.set_pause(&"debrief", false)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and phase == LINES:
		get_viewport().set_input_as_handled()
		advance()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match phase:
		LINES:
			if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
				get_viewport().set_input_as_handled()
				advance()
		FORK:
			var i := key.keycode - KEY_1
			if i >= 0 and i < 3:
				get_viewport().set_input_as_handled()
				if cards_ready():
					pick(i)
		DONE:
			if not can_choose():
				return
			var options := choices()
			var choice := -1
			match key.keycode:
				KEY_1, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					choice = 0
				KEY_2:
					choice = 1
			if choice >= 0 and choice < options.size():
				get_viewport().set_input_as_handled()
				choose(options[choice])

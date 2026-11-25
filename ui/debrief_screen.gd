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
##
## M47.4 (PLAN 1.16, v9.1): from Stage 2 the polished dev chat (`style` &"polished"): the column
## sits in a framed chat window titled "patchnotes · dev chat · v0.8.x"; the first bubble has
## the mascot's avatar and its name; typing dots while a line types; the fork cards are framed
## panels that lift on focus with a key chip; the patch notes are a changelog (Added / Changed
## / Fixed); the way-on buttons carry their key. Stage 1 keeps today's debrief (&"plain": the
## window is an empty box with no margin, so nothing moves). `_notes.text` stays notes_text().

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
const PREVIEW := 1.1       ## a mascot card's preview body: its scale and centre in the card
const PREVIEW_AT := Vector2(93, 65)

const LINES := &"lines"
const FORK := &"fork"
const DONE := &"done"
## M47.4: the debrief's two styles.
const PLAIN := &"plain"
const POLISHED := &"polished"
const AVATAR := 40.0        ## the polished first bubble's avatar box
const AVATAR_SCALE := 0.35
const LIFT := 6.0           ## a focused card's lift (px)
const DOTS: Array[String] = ["•", "••", "•••"]
const SECTIONS: Array[String] = ["Added", "Changed", "Fixed"]

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
var _big_view: PixelBodyView   ## M48a: big_body's pixel body style, null with no look
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
## M47.4: the chat window (plain: an empty box), its title bar, the changelog, the dots.
var style: StringName = PLAIN
var _window: PanelContainer
var _bar: Label
var _inner: MarginContainer
var _changelog: VBoxContainer
var _dots: Label
var _avatar_shown := false


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
	dim.color = Color(Palette.SCRIM, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	UiTheme.apply(_root)   # M47.4: neutral (fallback font and size): nothing moves
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
	_window = PanelContainer.new()
	_window.name = "ChatWindow"
	center.add_child(_window)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override(&"separation", 0)
	_window.add_child(frame)
	_bar = Label.new()
	_bar.name = "Bar"
	_bar.theme_type_variation = UiTheme.CHAT_BAR
	_bar.visible = false
	frame.add_child(_bar)
	_inner = MarginContainer.new()
	frame.add_child(_inner)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(700, 0)
	column.add_theme_constant_override(&"separation", 16)
	_inner.add_child(column)
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
	_notes.add_theme_color_override(&"font_color", Palette.ACCENT)
	column.add_child(_notes)
	_changelog = VBoxContainer.new()
	_changelog.name = "Changelog"
	_changelog.add_theme_constant_override(&"separation", 4)
	_changelog.visible = false
	column.add_child(_changelog)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 16)
	column.add_child(_buttons)
	_hint = Label.new()
	_hint.text = "Space · click: next"
	_hint.add_theme_font_size_override(&"font_size", 14)
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.3))
	column.add_child(_hint)
	_apply_style()
	Skins.hub.skin_changed.connect(_on_skin_changed)


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)


## M48a (review): a live look swap (F10 works while the debrief is open) re-dresses the
## whole screen: the big body in the new body style (keeping what it was doing), the cards
## (a mascot card's preview too) and the buttons.
func _on_skin_changed(_skin: ArtSkin) -> void:
	if big_body != null:
		var old := big_body
		_set_body(old.id)
		Mascot.carry_state(old, big_body)
	_apply_window()   # M47.4: the chat window follows the look too
	for b in _buttons.get_children():
		if b is Button and not b.is_queued_for_deletion():
			Skins.redress_button(b)
	if phase == FORK and fork() != null:
		var focused := -1
		for i in _cards.get_child_count():
			if (_cards.get_child(i) as Control).has_focus():
				focused = i
		var at := _cards_msec   # the swap does not restart the cards' input delay
		_show_cards(fork())
		_cards_msec = at
		if focused >= 0 and focused < _cards.get_child_count():
			(_cards.get_child(focused) as Button).grab_focus.call_deferred()


## M47.4: the window for `style`: plain = an empty box with no margin and no bar (the
## Stage 1 layout does not move); polished = the chat window's frame (or the look's UI
## panel), the title bar and a margin.
func _apply_style() -> void:
	var polished := style == POLISHED
	_apply_window()
	_bar.visible = polished
	for side: StringName in [&"margin_left", &"margin_right", &"margin_bottom"]:
		_inner.add_theme_constant_override(side, 22 if polished else 0)
	_inner.add_theme_constant_override(&"margin_top", 12 if polished else 0)
	if polished:
		_bar.text = "  patchnotes · dev chat · %s" % (CampaignDB.version_after(session).label() if session != null else "")
	_notes.visible = not polished
	_changelog.visible = false


func _apply_window() -> void:
	_window.remove_theme_stylebox_override(&"panel")
	_window.add_theme_stylebox_override(&"panel", UiTheme.window_style() if style == POLISHED else StyleBoxEmpty.new())


## The style for session `s`: polished from Stage 2.
static func style_for(s: SessionDef) -> StringName:
	return POLISHED if s != null and s.stage >= 2 else PLAIN


## The chat window's title bar text ("" in the plain style).
func bar_text() -> String:
	return _bar.text.strip_edges() if style == POLISHED else ""


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
	_clear(_changelog)
	_notes.text = ""
	style = style_for(session)
	_avatar_shown = false
	_apply_style()
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
	if _big_view != null:
		_big_view.queue_free()
		_big_view = null
	big_body = MascotBody.make(body_id)
	big_body.gentle = SaveGame.reduce_flashing()
	if Skins.is_on(&"mascot"):   # M48a: the look's body style (Pixel: 3x nearest; M48b: once revealed)
		_big_view = PixelBodyView.wrap(big_body, BIG)
		_stage.add_child(_big_view)
		_place_body()
		return
	big_body.scale = Vector2.ONE * BIG
	_stage.add_child(big_body)
	_place_body()


func _place_body() -> void:
	if _big_view != null:
		_big_view.position = Vector2(_stage.size.x * 0.5, _stage.size.y * 0.45)
	elif big_body != null:
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
	_typing.add_theme_color_override(&"font_color", Palette.MASCOT_INK)
	_typing.visible_characters = 0
	bubble.add_child(_typing)
	_dots = null
	if style == POLISHED:
		_body.add_child(_chat_row(bubble))
	else:
		_body.add_child(bubble)
	big_body.set_expression(_line.expression)
	big_body.say_start()
	_hint.visible = Settings.key_hints()   # M47.3: the key hints setting


func _typed() -> bool:
	return _line == null or _chars >= _line.text.length()


# --- M47.4: the polished chat ------------------------------------------------------

## A polished line: [avatar, bubble]; the first one shows the mascot's small body and its
## name above the bubble, the rest keep the avatar's width empty (aligned). Typing dots sit
## in the bubble's corner while the line types ("…", still, under reduce flashing).
func _chat_row(bubble: PanelContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var holder := Control.new()
	holder.name = "Avatar"
	holder.custom_minimum_size = Vector2(AVATAR, AVATAR)
	holder.size_flags_vertical = Control.SIZE_SHRINK_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 2)
	row.add_child(right)
	if not _avatar_shown:
		_avatar_shown = true
		var body_id := body_for(session)
		var small := MascotBody.make(body_id)
		small.gentle = true
		small.process_mode = Node.PROCESS_MODE_DISABLED   # a still portrait
		if Skins.is_on(&"mascot"):
			var view := PixelBodyView.wrap(small, AVATAR_SCALE)
			view.position = Vector2(AVATAR, AVATAR) * 0.5
			holder.add_child(view)
		else:
			small.scale = Vector2.ONE * AVATAR_SCALE
			small.position = Vector2(AVATAR, AVATAR) * 0.5
			holder.add_child(small)
		var tag := Label.new()
		tag.name = "Speaker"
		tag.text = speaker_name(body_id)
		tag.add_theme_font_size_override(&"font_size", 14)
		tag.add_theme_color_override(&"font_color", Palette.ACCENT)
		right.add_child(tag)
	right.add_child(bubble)
	_dots = Label.new()
	_dots.name = "Dots"
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dots.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_dots.add_theme_font_size_override(&"font_size", 16)
	_dots.add_theme_color_override(&"font_color", Color(Palette.MASCOT_INK, 0.45))
	_dots.text = dots_text(0.0)
	bubble.add_child(_dots)
	return row


## The typing dots at line time `t`: "•" "••" "•••" cycling, or a still "…" under reduce
## flashing; "" once typed.
func dots_text(t: float) -> String:
	if _typed():
		return ""
	if SaveGame.reduce_flashing():
		return "…"
	return DOTS[posmod(floori(t * 3.0), DOTS.size())]


## The mascot's name on the chat (its body's change, e.g. "Window"; "AI" for the caret).
static func speaker_name(body_id: StringName) -> String:
	var f := ChangeDB.get_fork(&"fork_mascot")
	if f != null:
		for c in f.changes():
			if c.take != null and c.take.id == body_id:
				return c.short_name()
	return "AI"


## The patch notes as a changelog: a note starting "Added " / "Changed " / "Fixed " goes
## to that section (the verb dropped, the next letter capitalised); any other note and every
## fork pick go to Added.
static func changelog(s: SessionDef, pick: Change = null, more: Array[Change] = []) -> Dictionary:
	var out := {}
	for k in SECTIONS:
		out[k] = [] as Array[String]
	for n in s.notes:
		var section := "Added"
		var text := n
		for k in SECTIONS:
			if n.begins_with(k + " "):
				section = k
				text = n.substr(k.length() + 1)
				break
		if text != "":
			text = text.left(1).to_upper() + text.substr(1)
		(out[section] as Array[String]).append(text)
	var picks: Array[Change] = [pick]
	picks.append_array(more)
	for c in picks:
		if c != null:
			(out["Added"] as Array[String]).append(c.title)
	return out


func _show_changelog(s: SessionDef, pick: Change, more: Array[Change]) -> void:
	_clear(_changelog)
	var head := Label.new()
	head.text = "%s · changelog" % CampaignDB.version_after(s).label()
	head.add_theme_font_size_override(&"font_size", 20)
	head.add_theme_color_override(&"font_color", Palette.ACCENT)
	_changelog.add_child(head)
	var entries := changelog(s, pick, more)
	for k in SECTIONS:
		var items: Array[String] = entries[k]
		if items.is_empty():
			continue
		var section := Label.new()
		section.text = k.to_upper()
		section.add_theme_font_size_override(&"font_size", 14)
		section.add_theme_color_override(&"font_color", Palette.UI_DIM)
		_changelog.add_child(section)
		for item in items:
			var l := Label.new()
			l.text = "  + " + item
			l.add_theme_font_size_override(&"font_size", 18)
			l.add_theme_color_override(&"font_color", Palette.UI_TEXT)
			_changelog.add_child(l)
	_changelog.visible = true


func _finish_typing() -> void:
	if _line == null:
		return
	_chars = _line.text.length()
	_typing.visible_characters = -1
	big_body.say_end()
	if _dots != null:
		_dots.text = ""


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
	# M47.3 (PLAN 1.16): the text speed setting (TYPE_CPS by default; 0 = instant).
	var cps := Settings.type_cps()
	if not _typed():
		_chars = _line.text.length() if cps <= 0.0 else minf(_line.text.length(), _chars + cps * delta)
		_typing.visible_characters = int(_chars)
		if _typed():
			big_body.say_end()
		if _dots != null:
			_dots.text = dots_text(_line_t)
	elif _line_t >= (0.0 if cps <= 0.0 else _line.text.length() / cps) + SessionRunner.read_seconds(_line.text):
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
	if style == POLISHED:   # M47.4: the key chip, the card's frame and its focus lift
		key.name = "KeyChip"
		key.text = InputSetup.key_label(StringName("choose_%d" % (index + 1)))
		key.theme_type_variation = UiTheme.KEY_CHIP
		key.remove_theme_color_override(&"font_color")
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(key)
	if c.kind == &"mascot":
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0, 130)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(holder)
		var preview := MascotBody.make(c.take.id)
		preview.gentle = SaveGame.reduce_flashing()
		preview.t = 0.4 * index   # out of step with each other
		if Skins.is_on(&"mascot"):   # M48a (review): the preview wears the look's body style too
			var view := PixelBodyView.wrap(preview, PREVIEW)
			view.position = PREVIEW_AT
			holder.add_child(view)
		else:
			preview.scale = Vector2.ONE * PREVIEW
			preview.position = PREVIEW_AT
			holder.add_child(preview)
		b.mouse_entered.connect(func() -> void: preview.set_expression(&"happy"))
		b.mouse_exited.connect(func() -> void: preview.set_expression(&"idle"))
		b.focus_entered.connect(func() -> void: preview.set_expression(&"happy"))
		b.focus_exited.connect(func() -> void: preview.set_expression(&"idle"))
	elif _still_for(c) != null:
		var still := TextureRect.new()
		still.texture = _still_for(c)
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
	if style == POLISHED:
		_frame_card(b, box)
	Skins.dress_button(b)   # M48a: the look's UI panel (no look: today's theme)
	return b


## M47.4: a polished card is a framed panel; focused, its content lifts LIFT px (a
## real-time tween: the tree is paused and Engine.time_scale is the game's).
func _frame_card(b: Button, box: Control) -> void:
	var plain := StyleBoxFlat.new()
	plain.bg_color = Palette.UI_PANEL
	plain.border_color = Color(Palette.ACCENT, 0.3)
	plain.set_border_width_all(1)
	plain.set_corner_radius_all(6)
	var lit := plain.duplicate() as StyleBoxFlat
	lit.border_color = Palette.ACCENT
	lit.set_border_width_all(2)
	b.add_theme_stylebox_override(&"normal", plain)
	b.add_theme_stylebox_override(&"disabled", plain)
	for state: StringName in [&"hover", &"pressed", &"focus", &"hover_pressed"]:
		b.add_theme_stylebox_override(state, lit)
	b.focus_entered.connect(_lift.bind(b, box, true))
	b.focus_exited.connect(_lift.bind(b, box, false))


func _lift(b: Button, box: Control, up: bool) -> void:
	if not b.is_inside_tree():
		return
	var tw := b.create_tween().set_ignore_time_scale(true).set_parallel(true)
	tw.tween_property(box, ^"offset_top", 10.0 - (LIFT if up else 0.0), 0.12)
	tw.tween_property(box, ^"offset_bottom", -10.0 - (LIFT if up else 0.0), 0.12)


## A card's still (M47, 1.12): a path option shows the player's own taste of it when S7
## captured one (PathRunner.taste_stills), else its take's image; null = text only.
static func _still_for(c: Change) -> Texture2D:
	if c.kind == &"path" and c.take != null and PathRunner.taste_stills.has(String(c.take.id)):
		return PathRunner.taste_stills[String(c.take.id)]
	return c.take.image if c.take != null else null


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
	if fork() == null:   # M47 (D16): the session's after_pick lines follow its last fork's take
		_pending.append_array(Line.passing(session.after_pick_lines(), CampaignDB.line_context(session,
				outcome, hits_seen, events, moved_on)))
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
		if style == POLISHED:   # M47.4: the notes as a changelog (the text stays for tests)
			_show_changelog(session, picked, more_picks())
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
	# M50.1b: the run's own patch-note lines (Arsenal's misfuse fix, a new recipe), in order.
	for e: Dictionary in RunState.run_log:
		if e.get("event") == &"patch_note":
			text += "\n  • " + String(e.get("text", ""))
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
	Skins.dress_button(b)
	if style == POLISHED:   # M47.4: its key (and the pad's A on the first) at the right
		var keys := InputSetup.key_label(StringName("choose_%d" % (_buttons.get_child_count() + 1)))
		if _buttons.get_child_count() == 0 and not Input.get_connected_joypads().is_empty():
			keys += " / A"
		var chip := UiTheme.key_chip(keys)
		chip.name = "KeyChip"
		chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		chip.grow_vertical = Control.GROW_DIRECTION_BOTH
		chip.offset_right = -10
		b.add_child(chip)
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
	# M47.3 (PLAN 1.16): actions, not raw keycodes: choose_N is bound by physical position
	# (1 / 2 work on AZERTY), ui_accept is Enter, keypad Enter, Space and the pad's A.
	if event.is_echo() or not event.is_pressed():
		return
	match phase:
		LINES:
			if event.is_action_pressed(&"ui_accept"):
				get_viewport().set_input_as_handled()
				advance()
		FORK:
			for i in 3:
				if event.is_action_pressed(StringName("choose_%d" % (i + 1))):
					get_viewport().set_input_as_handled()
					if cards_ready():
						pick(i)
					return
		DONE:
			if not can_choose():
				return
			var options := choices()
			var choice := -1
			if event.is_action_pressed(&"choose_1") or event.is_action_pressed(&"ui_accept"):
				choice = 0
			elif event.is_action_pressed(&"choose_2"):
				choice = 1
			if choice >= 0 and choice < options.size():
				get_viewport().set_input_as_handled()
				choose(options[choice])

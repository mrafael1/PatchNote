class_name TerminalPanel
extends PanelContainer
## M47.5a (PLAN v9.3, 0.7): the raw, pre-UI dev terminal docked right of the running game.
## Black, monospace, no frame: the AI's lines (`[14:02] ai@patchnotes`, then the text on the
## next row), cyan `$` commands, the changelog, a "thinking" spinner, numbered yellow choices
## and a `you>` prompt.
##
## Two ways rows arrive:
## - During play, from Mascot.line_started / line_cut (live_say / live_cut): a new line first
##   completes the row typing now (with " —" when the mascot cut it), then types itself. The
##   terminal never queues behind the mascot.
## - Inside a beat (the debrief's terminal view, the host's hot-reload): say_row() hands the
##   caller the text label to type (the debrief keeps its own timing); cmd / notes / sys /
##   think / ask rows queue and appear in order (think holds the queue for its seconds).
##
## Real time only (Time.get_ticks_usec): it never reads or steps game time, and it reads no
## keys (DebriefScreen and GameHost own them); a click on a choice row emits `chosen`.
##
## M47.6a (PLAN v9.4 2.4-2.5): during play the corner's lines come in the game's bubble and
## log here at once, dim (log_say); between sessions lines type here (type_line rows queue
## and type one after another). The `you>` input (ChatInput) sits under the rows; GameHost
## opens it at the play gate.

signal idle
signal chosen(index: int)

enum Row { SAY, CMD, NOTE, THINK, CHOICE, YOU, SYS, HEAD, TYPE }

const THINK_S := 1.2
const THINK_S_INSTANT := 0.4
const MAX_ROWS := 300
const SAME_HEADER_S := 10.0
const STEP_S := 0.06          ## a queued row's delay after the one before
const BASE_FONT := 16
const LINE_SPACING := 4
const SPINNER: Array[String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
const SPINNER_ASCII: Array[String] = ["|", "/", "-", "\\"]
const MARKER := "▌"
const CUT := " —"

## &"raw" now; M48.5's polished panel plugs in here.
var style: StringName = &"raw"
## M47.5b (PLAN v9.3 2.9, D15): &"raw" or &"pixel" (S9's `ui` reveal on: colours only; the
## font, the layout and the frame stay raw until M48.5).
var palette_name: StringName = &"raw"
var colors := raw_colors()
var speaker := "ai"           ## the prompt's name: "ai" until the body pick, then the body's
var has_face := false         ## false while the AI is a caret: no expression tag
var session_index := 0        ## CampaignDB.current_index(): the clock's 3 min per session
var gentle := false           ## a steady caret whatever the setting (tests)

var _font_size := BASE_FONT
var _title: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _queue: Array[Dictionary] = []
var _wait_until := 0          ## usec: the queue waits until then (a step or a think)
var _think: Label             ## the spinner row while a think runs
var _think_text := ""
var _you: Label               ## the open `you> _` row, or null
var _live: Label              ## the play-mode row typing itself
var _live_line: Line
var _live_cut := false
var _live_chars := 0.0
var _cue_marker: Label        ## the newest cue row's gutter marker
var _last_head := {}          ## {speaker, expression, usec} of the last header, while rows follow it
var _start_usec := 0
var _last_usec := 0
var _was_busy := false
var _snap := false
var _snap_frames := 0
var _open_cmd: Label
## M47.6a: the input row (`you> ` + ChatInput), the queued line typing now, the last logged line.
var chat_input: ChatInput
var _input_row: HBoxContainer
var _input_label: Label
var _typing: Label
var _typing_chars := 0.0
var _log: Label
var _log_line: Line


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "Terminal" if name == "" else name
	_start_usec = Time.get_ticks_usec()
	_last_usec = _start_usec
	_style_back()
	clip_contents = true
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_title = Label.new()
	_title.name = "Title"
	column.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS   # the wheel scrolls
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	_list.add_theme_constant_override(&"margin_right", 0)
	_scroll.get_v_scroll_bar().modulate.a = 0.35   # a quiet bar
	_scroll.add_child(_list)
	_input_row = HBoxContainer.new()
	_input_row.name = "InputRow"
	_input_row.add_theme_constant_override(&"separation", 0)
	column.add_child(_input_row)
	_input_label = Label.new()
	_input_label.name = "You"
	_input_label.text = "you> "
	_input_row.add_child(_input_label)
	chat_input = ChatInput.new()
	_input_row.add_child(chat_input)
	_dress_input()
	set_font_size(_font_size)
	set_version("")
	_tint(_title, &"dim")
	Skins.hub.skin_changed.connect(_on_skin_changed)


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)


# --- Colours (M47.5b: S9's `ui` reveal recolours the terminal) -------------------------------

## The raw terminal's tokens (Palette's tier-0 TERM_* constants).
static func raw_colors() -> Dictionary:
	return {&"bg": Palette.TERM_BG, &"rule": Palette.TERM_RULE, &"text": Palette.TERM_TEXT,
			&"dim": Palette.TERM_DIM, &"cmd": Palette.TERM_CMD, &"note": Palette.TERM_NOTE,
			&"choice": Palette.TERM_CHOICE, &"you": Palette.TERM_YOU, &"err": Palette.TERM_ERR}


## The same tokens in the Pixel look: its own roles where it has one (ui_text, accent,
## pickup, danger), else colours from its sprites' ramps (outline, wall, the cursor's shade).
static func pixel_colors() -> Dictionary:
	var out := {&"bg": Color("#1e1424"), &"rule": Color("#5c3452"), &"text": Color("#fff8ec"),
			&"dim": Color("#a08cc8"), &"cmd": Color("#3ff2d2"), &"note": Color("#ddd0ee"),
			&"choice": Color("#ffc83a"), &"you": Color("#fff8ec"), &"err": Color("#f2402e")}
	var skin := Skins.current
	if skin != null:
		for pair: Array in [[&"text", &"ui_text"], [&"you", &"ui_text"], [&"cmd", &"accent"],
				[&"choice", &"pickup"], [&"err", &"danger"]]:
			var c: Variant = skin.role(pair[1])
			if c is Color:
				out[pair[0]] = c
	return out


## Raw, or the Pixel colours once the look's `ui` group is on (the pause menu's rule).
## Every row already shown takes the new colours too.
func dress() -> void:
	var want: StringName = &"pixel" if Skins.is_on(&"ui_panel") else &"raw"
	if want == palette_name:
		return
	palette_name = want
	colors = pixel_colors() if want == &"pixel" else raw_colors()
	_style_back()
	if _title != null:
		_tint(_title, &"dim")
	_dress_input()
	if _list == null:
		return
	for row in _list.get_children():
		if row is Label:
			_retint(row as Label)
		else:
			for l in row.get_children():
				if l is Label:
					_retint(l as Label)


func _on_skin_changed(_skin: ArtSkin) -> void:
	dress()


## M47.6a: the input row in the terminal's colours.
func _dress_input() -> void:
	if _input_label == null or chat_input == null:
		return
	_tint(_input_label, &"you")
	chat_input.dim = col(&"dim")
	chat_input.bright = col(&"you")
	chat_input.add_theme_color_override(&"font_color", col(&"you"))
	chat_input.add_theme_color_override(&"font_uneditable_color", col(&"dim"))
	chat_input.add_theme_color_override(&"caret_color", col(&"you"))
	chat_input._tint_ghost(0.0)


func col(tone: StringName) -> Color:
	return colors.get(tone, Palette.TERM_TEXT)


func _style_back() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = col(&"bg")
	box.border_color = col(&"rule")
	box.border_width_left = 1
	box.content_margin_left = 14
	box.content_margin_right = 10
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	add_theme_stylebox_override(&"panel", box)


## A label's colour by token (kept as meta, so dress() can recolour it).
func _tint(l: Label, tone: StringName, alpha := 1.0) -> void:
	l.set_meta(&"tone", tone)
	l.set_meta(&"alpha", alpha)
	l.add_theme_color_override(&"font_color", Color(col(tone), alpha))


func _retint(l: Label) -> void:
	if l.has_meta(&"tone"):
		_tint(l, l.get_meta(&"tone"), float(l.get_meta(&"alpha", 1.0)))


## The font size (GameHost: 16 x clamp(k, 1, 2)).
func set_font_size(px: int) -> void:
	_font_size = px
	var t := Theme.new()
	t.default_font = UiTheme.mono_font()
	t.default_font_size = px
	t.set_constant(&"line_spacing", &"Label", LINE_SPACING)
	theme = t


func font_size() -> int:
	return _font_size


## The first line: "patchnotes  dev console  v0.1.0".
func set_version(label: String) -> void:
	_title.text = "patchnotes  dev console" + ("  " + label if label != "" else "")


func title_text() -> String:
	return _title.text


## The prompt's name and whether the expression tag shows (S3's body pick renames it live).
func set_speaker(p_name: String, p_face: bool) -> void:
	speaker = p_name if p_name != "" else "ai"
	has_face = p_face
	_last_head = {}


## The braille spinner when the font has it, else | / - \.
func spinner_frames() -> Array[String]:
	var f := UiTheme.mono_font()
	if f != null and f.has_char(0x280B):
		return SPINNER
	return SPINNER_ASCII


## "[14:02]": 14:00 + 3 min per session + whole real minutes since this terminal started.
func clock_text() -> String:
	var minutes := 14 * 60 + 3 * session_index + int((Time.get_ticks_usec() - _start_usec) / 60000000)
	return "[%02d:%02d]" % [posmod(minutes / 60, 24), minutes % 60]


# --- Play mode (Mascot.line_started / line_cut) -------------------------------------------

## A line the corner mascot starts now: the row typing now completes (cut: " —"), this one types.
func live_say(line: Line, priority := 2) -> void:
	if line == null:
		return
	_complete_live()
	_live_line = line
	_live_cut = false
	_live_chars = 0.0
	_live = say_row(line.text, line.expression, priority)
	if Settings.type_cps() <= 0.0:
		_live.visible_characters = -1


func live_cut(line: Line) -> void:
	if line != null and line == _live_line:
		_live_cut = true
	elif line != null and line == _log_line and _log != null and is_instance_valid(_log):
		_log.text += CUT   # M47.6a: a logged line the bubble cut short
		_log_line = null


## M47.6a (PLAN v9.4 2.4): a line the corner says in the game's bubble: logged now, whole and
## dim, no typing (history, not a second reading task).
func log_say(line: Line, priority := 2) -> void:
	if line == null:
		return
	_complete_live()
	var l := say_row(line.text, line.expression, priority)
	l.visible_characters = -1
	_tint(l, &"dim")
	_log = l
	_log_line = line


## M47.6a: a line typed in the chat between sessions (before_play, a canned reply): queued
## after the rows before it, typed at the text speed; the queue waits until it is typed.
func type_line(line: Line) -> void:
	if line != null:
		queue({"kind": Row.TYPE, "text": line.text, "expression": line.expression})


## M47.6a: a `you>` row with what the player said ("you> play").
func you_said(text: String) -> void:
	_flush_queue()
	_close_you()
	_last_head = {}
	_label_row(Row.YOU, "you> " + text, &"you")


func _complete_live() -> void:
	if _live == null:
		return
	if is_instance_valid(_live):
		_live.visible_characters = -1
		if _live_cut:
			_live.text += CUT
	_live = null
	_live_line = null
	_live_cut = false


# --- Rows -----------------------------------------------------------------------------------

## A said line: its header row (shared with the row before when the same speaker and
## expression spoke within SAME_HEADER_S), then the text, indented. Returns the text label at
## visible_characters 0: the caller types it. Queued rows go out first, so the order holds.
## priority < 2 (reactions' chatter): dim and clipped to one row.
func say_row(text: String, expression: StringName = &"idle", priority := 2) -> Label:
	_flush_queue()
	return _say_row_now(text, expression, priority)


func _say_row_now(text: String, expression: StringName = &"idle", priority := 2) -> Label:
	_close_you()
	var expr := expression if has_face else &""
	var now := Time.get_ticks_usec()
	var shared: bool = not _last_head.is_empty() and _last_head.speaker == speaker \
			and _last_head.expression == expr and now - int(_last_head.usec) <= int(SAME_HEADER_S * 1000000.0)
	if not shared:
		var head := clock_text() + " " + speaker + "@patchnotes"
		if expr != &"":
			head += " (%s)" % expr
		_label_row(Row.HEAD, head, &"dim")
	_last_head = {"speaker": speaker, "expression": expr, "usec": now}
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 0)
	row.set_meta(&"kind", Row.SAY)
	var marker := Label.new()
	marker.name = "Marker"
	marker.text = MARKER + " "
	_tint(marker, &"cmd", 0.0)
	row.add_child(marker)
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 1
	if priority < SessionRunner.PRIORITY:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_tint(l, &"dim")
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tint(l, &"text")
		# The newest cue line carries the gutter marker until the next one.
		if _cue_marker != null and is_instance_valid(_cue_marker):
			_tint(_cue_marker, &"cmd", 0.0)
		_tint(marker, &"cmd")
		_cue_marker = marker
	l.visible_characters = 0
	row.add_child(l)
	_add(row)
	return l


## "$ text" (+ " ... result"). Queued.
func cmd(text: String, result := "") -> void:
	queue({"kind": Row.CMD, "text": "$ " + text + (" ... " + result if result != "" else "")})


## "$ text ..." now; close_cmd() adds its result later ("$ hot-reload game ... ok").
func cmd_open(text: String) -> void:
	queue({"kind": Row.CMD, "text": "$ " + text + " ...", "open": true})


func close_cmd(result: String) -> void:
	_flush_queue()
	if _open_cmd != null and is_instance_valid(_open_cmd):
		_open_cmd.text += " " + result
	_open_cmd = null


## The changelog (DebriefScreen.changelog()): "  + Added ...", "  ~ Changed ...", "  - Fixed ...".
func notes(changelog: Dictionary) -> void:
	for section: String in DebriefScreen.SECTIONS:
		for item: String in changelog.get(section, []):
			queue({"kind": Row.NOTE, "text": note_text(section, item)})


static func note_text(section: String, item: String) -> String:
	var sigil := "+"
	match section:
		"Changed":
			sigil = "~"
		"Fixed":
			sigil = "-"
	var low := item.left(1).to_lower() + item.substr(1) if item.length() > 1 and item.substr(1, 1) == item.substr(1, 1).to_lower() else item
	return "  %s %s %s" % [sigil, section, low]


func sys(text: String) -> void:
	queue({"kind": Row.SYS, "text": text})


## M47.5b: a dim row shown now (after the queue), its label handed back to be rewritten (the
## death countdown's "restarting in 3 . 2 . 1").
func sys_now(text: String) -> Label:
	_flush_queue()
	_last_head = {}
	return _label_row(Row.SYS, text, &"dim")


## "<speaker> is thinking ⠋ . . ." for `seconds` (THINK_S; THINK_S_INSTANT at instant text).
func think(seconds := -1.0) -> void:
	if seconds < 0.0:
		seconds = THINK_S_INSTANT if Settings.type_cps() <= 0.0 else THINK_S
	queue({"kind": Row.THINK, "text": speaker + " is thinking", "seconds": seconds})


## Numbered choices, then `you> _`.
func ask(options: Array[String]) -> void:
	for i in options.size():
		queue({"kind": Row.CHOICE, "text": "[%d] %s" % [i + 1, options[i]], "index": i})
	queue({"kind": Row.YOU})


## `you> _` with no choices (the ready moment).
func prompt() -> void:
	queue({"kind": Row.YOU})


## The open `you>` row gets its answer ("you> 2").
func answer(text: String) -> void:
	_flush_queue()
	if _you != null and is_instance_valid(_you):
		_you.text = "you> " + text
	_you = null
	_sync_input_row()


## M47.6a review: one prompt at a time. While an ask's `you> _` row waits (the installer's
## question, the death ask), the input row under the rows is hidden (its space kept, so
## nothing jumps): no second `you>` reading "the AI is watching...". A play gate always shows it.
func input_row_shown() -> bool:
	var asking := _you != null and is_instance_valid(_you)
	return not asking or (chat_input != null and chat_input.gate)


func _sync_input_row() -> void:
	if _input_row != null and is_instance_valid(_input_row):
		_input_row.modulate.a = 1.0 if input_row_shown() else 0.0


func queue(row: Dictionary) -> void:
	_queue.append(row)


## Everything at once: the queue, the think, the row typing (the bot, a key in a beat).
func finish() -> void:
	_flush_queue()
	_complete_live()


func is_busy() -> bool:
	return not _queue.is_empty() or _think != null or _typing_now() or (_live != null and is_instance_valid(_live)
			and _live.visible_characters >= 0 and _live.visible_characters < _live.text.length())


## M47.6a: a type_line row is still typing.
func _typing_now() -> bool:
	return _typing != null and is_instance_valid(_typing) and _typing.visible_characters >= 0 \
			and _typing.visible_characters < _typing.text.length()


func _complete_typing() -> void:
	if _typing != null and is_instance_valid(_typing):
		_typing.visible_characters = -1
	_typing = null


func has_prompt() -> bool:
	return _you != null


## Every row's text, in order (tests, captures).
func rows() -> Array[String]:
	var out: Array[String] = []
	for r in _list.get_children():
		if r.is_queued_for_deletion():
			continue
		if r is Label:
			out.append((r as Label).text)
		else:
			var t := r.get_node_or_null(^"Text") as Label
			out.append("  " + (t.text if t != null else ""))
	return out


## A row grew (the debrief typing its label): snap back to the bottom.
func touch() -> void:
	_snap = true


func row_count() -> int:
	return _list.get_child_count()


# --- Inside ----------------------------------------------------------------------------------

func _label_row(kind: Row, text: String, tone: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tint(l, tone)
	l.set_meta(&"kind", kind)
	_add(l)
	return l


func _add(row: Control) -> void:
	_list.add_child(row)
	while _list.get_child_count() > MAX_ROWS:
		var first := _list.get_child(0)
		_list.remove_child(first)
		first.queue_free()
	_snap = true


func _close_you() -> void:
	if _you != null and is_instance_valid(_you):
		_you.text = "you>"
	_you = null
	_sync_input_row()


func _show(item: Dictionary) -> void:
	var kind: Row = item.kind
	if kind != Row.SAY and kind != Row.TYPE:
		_last_head = {}   # a header is shared only by rows that follow it
	match kind:
		Row.CMD:
			var c := _label_row(kind, item.text, &"cmd")
			if item.get("open", false):
				_open_cmd = c
		Row.NOTE:
			_label_row(kind, item.text, &"note")
		Row.SYS:
			_label_row(kind, item.text, &"dim")
		Row.CHOICE:
			var l := _label_row(kind, item.text, &"choice")
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var index: int = item.index
			l.gui_input.connect(func(e: InputEvent) -> void:
				var m := e as InputEventMouseButton
				if m != null and m.pressed and m.button_index == MOUSE_BUTTON_LEFT:
					chosen.emit(index))
		Row.YOU:
			_close_you()
			_you = _label_row(kind, "you> _", &"you")
			_sync_input_row()
		Row.THINK:
			_think_text = item.text
			_think = _label_row(kind, _think_text + " " + spinner_frames()[0] + " . . .", &"dim")
		Row.TYPE:
			_complete_typing()
			_typing = _say_row_now(item.text, item.get("expression", &"idle"))
			_typing_chars = 0.0
			if Settings.type_cps() <= 0.0:
				_complete_typing()


func _end_think() -> void:
	if _think != null and is_instance_valid(_think):
		_think.text = _think_text + " . . ."
	_think = null


## Shows every queued row now (a think ends at once).
func _flush_queue() -> void:
	_end_think()
	_complete_typing()
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		_show(item)
		if item.kind == Row.THINK:
			_end_think()
		elif item.kind == Row.TYPE:
			_complete_typing()
	_wait_until = 0


## The prompt's caret at `now` (usec): 1 Hz, steady under reduce flashing (read live: the
## host and its terminal outlive an Options change, M47.5a review).
func caret_on(now: int) -> bool:
	return gentle or SaveGame.reduce_flashing() or int((now - _start_usec) / 500000) % 2 == 0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_usec) / 1000000.0
	_last_usec = now
	# M47.6a: a queued line types itself; the queue waits for it.
	if _typing != null:
		if not is_instance_valid(_typing):
			_typing = null
		else:
			var tcps := Settings.type_cps()
			var tt := _typing.text.length()
			_typing_chars = float(tt) if tcps <= 0.0 else minf(tt, _typing_chars + tcps * dt)
			_typing.visible_characters = int(_typing_chars)
			_snap = true
			if int(_typing_chars) >= tt:
				_typing.visible_characters = -1
				_typing = null
				_wait_until = now + int(STEP_S * 4.0 * 1000000.0)   # a breath between lines
	# The queue: a row per step; a think holds it for its seconds.
	if _typing == null and now >= _wait_until:
		if _think != null:
			_end_think()
		if not _queue.is_empty():
			var item: Dictionary = _queue.pop_front()
			_show(item)
			var step := 0.0 if Settings.type_cps() <= 0.0 else STEP_S
			if item.kind == Row.THINK:
				step = float(item.seconds)
			_wait_until = now + int(step * 1000000.0)
	if _think != null:
		var frames := spinner_frames()
		var i := int((now - _start_usec) / 100000) % frames.size()   # 10 Hz
		_think.text = _think_text + " " + frames[i] + " . . ."
	# Play mode: the live row types itself at the text speed.
	if _live != null and is_instance_valid(_live) and _live.visible_characters >= 0:
		var cps := Settings.type_cps()
		var total := _live.text.length()
		_live_chars = float(total) if cps <= 0.0 else minf(total, _live_chars + cps * dt)
		_live.visible_characters = -1 if int(_live_chars) >= total else int(_live_chars)
		_snap = true
	_sync_input_row()   # a gate opening under an open ask shows the input again
	# The prompt's caret (steady under reduce flashing).
	if _you != null and is_instance_valid(_you):
		_you.text = "you> _" if caret_on(now) else "you>  "
	# A new row lands a frame before the list re-sorts: snap for a few frames.
	if _snap:
		_snap = false
		_snap_frames = 3
	if _snap_frames > 0:
		_snap_frames -= 1
		_scroll_to_end()
	var busy := is_busy()
	if _was_busy and not busy:
		idle.emit()
	_was_busy = busy


func _scroll_to_end() -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

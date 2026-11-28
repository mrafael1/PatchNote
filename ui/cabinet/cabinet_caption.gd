extends Control
## M48.6b: the host's caption in the cabinet's deck (PLAN 0.9.2; the mockup's `.cap`): right of
## the camera box, a cream bubble with its tail on the camera and, on its top edge, the mood
## plate (the AI's name on gold, the line's mood on ink). It shows EVERY line the AI says, from
## the terminal's `said` signal (the corner's lines during play, also under a pick panel; the
## gate's and the beat's lines between sessions; canned replies), so the floating bubble in the
## view is not needed in the cabinet (Mascot.set_captioned).
##
## The line types itself at the text speed, stays lit for its read time, then dims (idle) until
## the next one. A line longer than the bubble scrolls: the last rows typed are the ones shown
## (the chat keeps it whole). Presentation only: real time, no RNG, nothing written to the game.

const MAX_ROWS := 3
const TOP := 21.0     ## design px from the bubble top to the first row (under the mood plate)

var frame: Node               ## the CabinetFrame
var text := ""                ## the line in the bubble ("" before the first)
var mood: StringName = &""    ## its expression ("" while the AI has no face)
var shown: Array[String] = [] ## every line it showed, in order (tests)

var _chars := 0.0
var _hold := 0.0
var _last_usec := 0
var _wrap_key := ""
var _wrapped := PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_last_usec = Time.get_ticks_usec()


## The terminal's `said`: a new line replaces the one in the bubble.
func say(t: String, expression: StringName = &"", _priority := 2) -> void:
	text = t
	mood = expression
	shown.append(t)
	_chars = 0.0 if Settings.type_cps() > 0.0 else float(t.length())
	_hold = SessionRunner.read_seconds(t)
	_wrap_key = ""
	queue_redraw()


## The line is still typing.
func talking() -> bool:
	return text != "" and _chars < text.length()


## Nothing to read now: no line yet, or the line's read time is over (the bubble dims).
func idle() -> bool:
	return text == "" or (not talking() and _hold <= 0.0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_usec) / 1000000.0
	_last_usec = now
	if is_visible_in_tree():
		step(dt)


## One tick of the typing and the read time (tests call it with a chosen delta).
func step(dt: float) -> void:
	if idle():
		return
	if talking():
		var cps := Settings.type_cps()
		_chars = float(text.length()) if cps <= 0.0 else minf(text.length(), _chars + cps * dt)
	else:
		_hold -= dt
	queue_redraw()


## The text size and the row step in screen px, and the rows the bubble holds.
func text_size() -> int:
	return CabinetLayout.text_px(2, frame.s())


func row_step() -> float:
	return maxf(roundf(7.0 * frame.art()), roundf(text_size() * 21.0 / 22.0))


func max_rows() -> int:
	var bub: Rect2 = frame.layout.get("cap", Rect2())
	return clampi(int((bub.size.y - (TOP + 6.0) * frame.s() - text_size() * 0.86) / row_step()) + 1, 1, MAX_ROWS)


func text_width() -> float:
	var bub: Rect2 = frame.layout.get("cap", Rect2())
	return bub.size.x - 15.0 * frame.s()


## `t` in rows no wider than `width` at `size` (greedy, on spaces; a "\n" breaks too).
static func wrap_rows(t: String, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	for para in t.split("\n"):
		var row := ""
		for word in para.split(" ", false):
			var want := word if row == "" else row + " " + word
			if row != "" and RailFrame.text_w(want, size) > width:
				out.append(row)
				row = word
			else:
				row = want
		out.append(row)
	return out


## The rows on screen now: the line's rows cut at the typed characters, the last max_rows()
## of them.
func rows() -> PackedStringArray:
	var key := "%s|%d|%d" % [text, text_size(), int(text_width())]
	if key != _wrap_key:
		_wrap_key = key
		_wrapped = wrap_rows(text, text_size(), text_width())
	var out := PackedStringArray()
	var left := int(_chars)
	for row in _wrapped:
		if left <= 0:
			break
		out.append(row.left(left))
		left -= row.length() + 1   # the space (or the break) the wrap took
	var most := max_rows()
	return out.slice(out.size() - most) if out.size() > most else out


## The plate's name: the body's ("BLOB"), "AI" while a caret.
func host_name() -> String:
	var t: Node = frame.host.get(&"terminal") if frame != null and frame.host != null else null
	return String(t.call(&"header_name")).to_upper() if t != null else "AI"


func _draw() -> void:
	if frame == null or not frame.layout.has("cap"):
		return
	var a: float = frame.art()
	var sc: float = frame.s()
	var bub: Rect2 = frame.layout.cap
	CabinetArt.draw9_rect(self, &"bubble", bub, a)
	CabinetArt.orn(self, &"bub_tail_l", bub.position + Vector2(-6, 7) * a, a)
	# The mood plate on the bubble's top edge: the name on gold, the mood on ink.
	var size := text_size()
	var font := UiTheme.pixel_font()
	var at: Vector2 = frame.layout.mood
	var who := host_name()
	var who_w := ceili((RailFrame.text_w(who, size) + 4.0 * a) / a)
	var text_y := roundf(at.y + (9.0 * a - font.get_height(size)) * 0.5)
	CabinetArt.draw9(self, &"cap_gold", at, who_w, 9, a)
	RailFrame.text(self, Vector2(at.x, text_y), who, size, CabinetArt.c(&"ink"), false, HORIZONTAL_ALIGNMENT_CENTER, who_w * a)
	if mood != &"":
		var m := String(mood)
		var mood_w := ceili((RailFrame.text_w(m, size) + 4.0 * a) / a)
		var mood_at := at + Vector2(who_w - 1, 0) * a
		CabinetArt.draw9(self, &"cap_ink", mood_at, mood_w, 9, a)
		RailFrame.text(self, Vector2(mood_at.x, text_y), m, size, CabinetArt.c(&"mint_hi"), false, HORIZONTAL_ALIGNMENT_CENTER, mood_w * a)
	# The line: lit while it is read, dim after.
	var color := CabinetArt.c(&"cap_idle") if idle() else CabinetArt.c(&"plum_d")
	var step := row_step()
	var x := roundf(bub.position.x + 6.0 * sc)
	var y := roundf(bub.position.y + TOP * sc - (font.get_ascent(size) - size * 7.0 / 11.0))
	var list := rows()
	for i in list.size():
		RailFrame.text(self, Vector2(x, y + i * step), list[i], size, color)
	if talking() and frame.blink(1.25) and not list.is_empty():
		var last := list[list.size() - 1]
		var cx := x + RailFrame.text_w(last, size) + a
		var cy := y + (list.size() - 1) * step + font.get_ascent(size) - 5.0 * a
		draw_rect(Rect2(Vector2(cx, cy), Vector2(2, 5) * a), CabinetArt.c(&"rust"))

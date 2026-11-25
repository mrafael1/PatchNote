class_name Mascot
extends CanvasLayer
## The AI in the corner (PLAN v8 1.3): a body (or, before the face, a blinking caret) in
## the top-right corner and a speech bubble that grows to its left. It never covers the
## centre of the screen.
##
## Speech: a typewriter at TYPE_CPS, then the line stays for SessionRunner.read_seconds().
## One bubble at a time. A queue with priorities: a higher priority cuts the line on
## screen short (once it has been up MIN_SHOWN), an equal or lower one waits its turn.
## Holding Tab keeps the bubble open. Real time drives it, so it talks through pauses.

const SIZE := 112.0
const MARGIN := 16.0
## Below the HUD's top-right band (Hud.BAND_BOTTOM 68: two corner lines at font 20 are
## 59 px from y 8). M47.2 (owner G14a, measured): at 64 the cursor's resting tilt reached
## y 61-63 under the dash line; at 76 every resting pose clears it (top >= 71) and
## top_limit stops the hops, pops and pointing leans at the band's bottom.
const TOP := 76.0
const TYPE_CPS := 45.0
const MIN_SHOWN := 0.4
const BUBBLE_MAX_W := 360.0
const FONT_SIZE := 18

var body: MascotBody
var face := false
var body_id: StringName = MascotBody.DEFAULT
## Every line put in the bubble, in order (tests, F1).
var shown: Array[String] = []

var _corner: Control
var _bubble: PanelContainer
var _label: Label
var _queue: Array[Dictionary] = []   ## {line: Line, priority: int}, highest priority first
var _current: Line
var _current_priority := 0
var _chars := 0.0
var _hold := 0.0
var _shown_for := 0.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_corner = Control.new()
	_corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_corner.offset_left = -(MARGIN + SIZE)
	_corner.offset_right = -MARGIN
	_corner.offset_top = TOP
	_corner.offset_bottom = TOP + SIZE
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_corner)
	_bubble = PanelContainer.new()
	_bubble.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_bubble.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bubble.offset_right = -(MARGIN + SIZE + 10.0)
	_bubble.offset_top = TOP + 14.0
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_theme_stylebox_override(&"panel", bubble_style())
	_bubble.visible = false
	add_child(_bubble)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_label.add_theme_color_override(&"font_color", MascotBody.INK)
	_bubble.add_child(_label)
	_rebuild_body()


## The bubble's look, shared with the debrief.
static func bubble_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.97, 0.97, 1.0, 0.96)
	box.border_color = MascotBody.INK
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## The width a bubble needs for `text` (up to BUBBLE_MAX_W, then it wraps).
static func bubble_width(text: String, font_size := FONT_SIZE, max_w := BUBBLE_MAX_W) -> float:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return clampf(w + 4.0, 24.0, max_w)


## Body or caret: face false (before fork_mascot) shows the caret whatever the id.
func setup(p_face: bool, p_body_id: StringName) -> void:
	face = p_face
	body_id = p_body_id if MascotBody.is_body(p_body_id) else MascotBody.DEFAULT
	if is_inside_tree():
		_rebuild_body()


func _rebuild_body() -> void:
	if body != null:
		body.queue_free()
	body = MascotBody.make(body_id if face else MascotBody.CARET)
	body.gentle = SaveGame.reduce_flashing()
	body.position = Vector2(SIZE, SIZE) * 0.5
	body.scale = Vector2.ONE * (SIZE / 100.0)
	body.top_limit = corner_top_limit()
	_corner.add_child(body)


## M47.2: the body's top_limit in the corner (its own space): never above Hud.BAND_BOTTOM
## (+1). Only while the layer sits unshifted in the corner: the stage card's centred AI
## keeps its whole pose.
func corner_top_limit() -> float:
	if offset != Vector2.ZERO:
		return -INF
	return (Hud.BAND_BOTTOM + 1.0 - (TOP + SIZE * 0.5)) / (SIZE / 100.0)


## M47.2: the screen rect the corner body can ever draw in on a canvas of size `view`
## (MascotBody.worst_bounds() through the corner's place and scale).
func keep_out(view: Vector2) -> Rect2:
	var r := body.worst_bounds()
	var s := SIZE / 100.0
	var origin := Vector2(view.x - MARGIN - SIZE, TOP) + Vector2(SIZE, SIZE) * 0.5 + offset
	return Rect2(origin + r.position * s, r.size * s)


## M47.2: the bubble's screen rect for `text` on a canvas of size `view` (it grows left
## from W - MARGIN - SIZE - 10 and down from TOP + 14).
static func bubble_rect(text: String, view: Vector2) -> Rect2:
	var w := bubble_width(text)
	var h := ThemeDB.fallback_font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w,
			FONT_SIZE, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	var size := Vector2(w + 28.0, h + 16.0)
	return Rect2(Vector2(view.x - (MARGIN + SIZE + 10.0) - size.x, TOP + 14.0), size)


## Queues `line`. priority: 1 chatter, 2 notable, 3 important (PLAN v8 1.7); the session's
## script speaks at 2. cut: replace the line on screen now if it is not of a higher
## priority (a scripted event's beat, PLAN v8 1.5).
func say(line: Line, priority := 2, cut := false) -> void:
	if line == null:
		return
	if _current != null and ((cut and priority >= _current_priority)
			or (priority > _current_priority and _shown_for >= MIN_SHOWN)):
		_end_line()
		_start(line, priority)
		return
	var at := _queue.size()
	for i in _queue.size():
		if int(_queue[i].priority) < priority:
			at = i
			break
	_queue.insert(at, {"line": line, "priority": priority})
	if _current == null:
		_next()


## Glitches the body (an event's "shake or glitch the mascot", PLAN v8 1.5). Gentle with
## reduce_flashing: the body only wobbles.
func glitch(seconds: float) -> void:
	if body != null:
		body.glitch(seconds)


## Sets the face with no line; the next line (or its end) sets it again.
func show_expression(e: StringName) -> void:
	if body != null:
		body.set_expression(e)


## Points the body at a spot on the screen for `seconds` (a rule edit's warning).
func point_at_screen(screen_pos: Vector2, seconds := 1.5) -> void:
	if body != null and _corner != null:
		body.point_at(screen_pos - _corner.global_position, seconds)


func is_speaking() -> bool:
	return _current != null


func current_text() -> String:
	return _current.text if _current != null else ""


func queued() -> int:
	return _queue.size()


## Drops the lines still waiting (the one on screen stays): a scene that jumps to its end.
func drop_queued() -> void:
	_queue.clear()


## Hides the corner (the debrief draws its own, larger mascot) and drops what is queued.
func silence() -> void:
	_queue.clear()
	_end_line()
	visible = false


func _process(delta: float) -> void:
	if body != null:
		body.top_limit = corner_top_limit()
	step(delta)


## One tick of speech; tests call it with a chosen delta.
func step(delta: float) -> void:
	if _current == null:
		if not _queue.is_empty():
			_next()
		return
	_shown_for += delta
	if _shown_for >= MIN_SHOWN and not _queue.is_empty() \
			and int(_queue[0].priority) > _current_priority:
		_end_line()   # a higher priority cuts in, typed or not
		_next()
		return
	var total := _current.text.length()
	if _chars < total:
		_chars = minf(total, _chars + TYPE_CPS * delta)
		_label.visible_characters = int(_chars)
		if _chars >= total:
			body.say_end()
		return
	if not Input.is_key_pressed(KEY_TAB):
		_hold -= delta
	if _hold <= 0.0:
		_end_line()
		_next()


func _next() -> void:
	if _queue.is_empty():
		_current_priority = 0
		return
	var item: Dictionary = _queue.pop_front()
	_start(item.line, item.priority)


func _start(line: Line, priority: int) -> void:
	_current = line
	_current_priority = priority
	_chars = 0.0
	_shown_for = 0.0
	_hold = SessionRunner.read_seconds(line.text)
	shown.append(line.text)
	_label.text = line.text
	_label.visible_characters = 0
	_label.custom_minimum_size.x = bubble_width(line.text)
	# Grows left from the corner and down; the container's minimum size sets the height.
	var w := _bubble.get_combined_minimum_size().x
	_bubble.offset_left = _bubble.offset_right - w
	_bubble.offset_bottom = _bubble.offset_top
	_bubble.visible = true
	body.set_expression(line.expression)
	body.say_start()


func _end_line() -> void:
	if _current == null:
		return
	_current = null
	_bubble.visible = false
	body.say_end()
	body.set_expression(&"idle")

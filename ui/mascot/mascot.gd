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

## M47.5a (always on): a line starts in the corner (the terminal types it) / is cut short.
signal line_started(line: Line, priority: int)
signal line_cut(line: Line)

## M47.5a: false while hosted (GameHost): the terminal carries the voice, the corner keeps
## its body, its queue and its timing. M47.6a (PLAN v9.4 2.4): hosted, Main turns it on
## while a session plays and off for the beat (the chat logs every line either way).
var bubble_enabled := true
## M50.7: a pick panel is open: the bubble hides (the line still types and times out as usual)
## and shows again when the panel closes, if the line is still up.
var _parked := false
var body: MascotBody
var face := false
var body_id: StringName = MascotBody.DEFAULT
## Every line put in the bubble, in order (tests, F1).
var shown: Array[String] = []

var _corner: Control
## M48a: the `pixel` body style (PixelBodyView) while a look is on; null draws the body as is.
var _pixel_view: PixelBodyView
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
	Skins.hub.skin_changed.connect(_on_skin_changed)
	Settings.hub.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)
	if Settings.hub.changed.is_connected(_on_setting_changed):
		Settings.hub.changed.disconnect(_on_setting_changed)


## M47.3 (PLAN 1.16): the body re-reads reduce flashing when it changes (the options).
func _on_setting_changed(key: String) -> void:
	if key == "reduce_flashing" and body != null:
		body.gentle = SaveGame.reduce_flashing()


## M47.3: the pause menu freezes the typing and the line's clock (the body keeps idling).
var _held := false


func hold(on: bool) -> void:
	_held = on


## M48a: a look swap rebuilds the body in the new look's body style, keeping what it was
## doing (expression, talking, a pointing lean, a glitch).
func _on_skin_changed(_skin: ArtSkin) -> void:
	var old := body
	_rebuild_body()
	carry_state(old, body)


## M48a: copies a body's live state onto its rebuilt twin (a look swap): the expression and
## its clock, talking, the point_at lean and the glitch. Reads MascotBody's own fields: M47.2's
## body code stays as it is.
static func carry_state(from: MascotBody, to: MascotBody) -> void:
	if from == null or to == null:
		return
	to.set_expression(from.expression)
	to.t = from.t
	to.expr_t = from.expr_t
	to.talking = from.talking
	to._glitch_left = from._glitch_left
	to._point_dir = from._point_dir
	to._point_left = from._point_left


## The bubble's look, shared with the debrief.
static func bubble_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.BUBBLE
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


## M48.5a: the version rail docks the corner body while it shows (the AI sits on the rail in
## the chat instead, ui/rail/rail_blob.gd mirrors this body): only the corner hides; the queue,
## the timing and the signals run on.
func set_docked(on: bool) -> void:
	if _corner != null:
		_corner.visible = not on


func docked() -> bool:
	return _corner != null and not _corner.visible


## M48.6b: the cabinet's caption (the deck, beside the host's camera) shows every line, so the
## floating bubble stays hidden while it is on. Only the bubble: the queue, the typing, the
## read time and the signals run on unchanged.
var _captioned := false


func set_captioned(on: bool) -> void:
	_captioned = on
	if _bubble != null:
		_bubble.visible = bubble_enabled and not _parked and not on and _current != null


func captioned() -> bool:
	return _captioned


## M47.6a (PLAN v9.4 2.3): how many rows `text` takes in the bubble (its width rule, its
## font). SessionDef.problems() keeps authored lines to SessionDef.BUBBLE_ROWS.
static func bubble_rows(text: String) -> int:
	var f := ThemeDB.fallback_font
	var w := bubble_width(text)
	var h := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, FONT_SIZE, -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	return maxi(1, roundi(h / f.get_height(FONT_SIZE)))


## M47.6a: the bubble's text for `text`: whole when it fits 2 rows, else its first words
## that fit, then "..." (a runtime net for name substitutions; the chat keeps it whole).
static func clamp_text(text: String, rows := 2) -> String:
	if bubble_rows(text) <= rows:
		return text
	var words := text.split(" ", false)
	var n := words.size()
	while n > 1:
		n -= 1
		var t := " ".join(words.slice(0, n)) + "..."
		if bubble_rows(t) <= rows:
			return t
	return text.left(24) + "..."


## Body or caret: face false (before fork_mascot) shows the caret whatever the id.
func setup(p_face: bool, p_body_id: StringName) -> void:
	face = p_face
	body_id = p_body_id if MascotBody.is_body(p_body_id) else MascotBody.DEFAULT
	if is_inside_tree():
		_rebuild_body()


func _rebuild_body() -> void:
	if body != null:
		body.queue_free()
	if _pixel_view != null:
		_pixel_view.queue_free()
		_pixel_view = null
	body = MascotBody.make(body_id if face else MascotBody.CARET)
	body.gentle = SaveGame.reduce_flashing()
	if Skins.is_on(&"mascot"):
		# M48a: the look's body style (Pixel: the body rendered small, shown at 3x nearest).
		body.top_limit = corner_top_limit()
		_pixel_view = PixelBodyView.wrap(body, SIZE / 100.0)
		_pixel_view.position = Vector2(SIZE, SIZE) * 0.5
		_corner.add_child(_pixel_view)
		return
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


## M50.7: parks (hides) the bubble while a pick panel is open; unparking shows the line still up.
func park_bubble(on: bool) -> void:
	_parked = on
	if _bubble != null:
		_bubble.visible = bubble_enabled and not on and not _captioned and _current != null


## M50.7: the bubble is on screen (tests).
func bubble_shown() -> bool:
	return _bubble != null and _bubble.visible


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
	# M47.3: "Mascot chatter" off keeps the script's lines and drops the reactions below it.
	if priority < SessionRunner.PRIORITY and not Settings.chatter():
		return
	if _current != null and ((cut and priority >= _current_priority)
			or (priority > _current_priority and _shown_for >= MIN_SHOWN)):
		_end_line(true)
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
		var at := screen_pos - _corner.global_position
		if _pixel_view != null:
			at = _pixel_view.to_body_parent(at)   # the body sits in the pixel view's viewport
		body.point_at(at, seconds)


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
## M47.5a: `hide` false keeps the body in the corner (the terminal beat talks through it).
func silence(hide := true) -> void:
	_queue.clear()
	_end_line(true)
	if hide:
		visible = false


func _process(delta: float) -> void:
	if body != null:
		body.top_limit = corner_top_limit()
	if _held:
		return
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
		_end_line(true)   # a higher priority cuts in, typed or not
		_next()
		return
	var total := _current.text.length()   # M47.6a: the full line paces it (a clamped bubble just shows all)
	if _chars < total:
		# M47.3: the text speed setting (45 by default; 0 = the whole line at once).
		var cps := Settings.type_cps()
		_chars = total if cps <= 0.0 else minf(total, _chars + cps * delta)
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
	_label.text = clamp_text(line.text)
	_label.visible_characters = 0
	_label.custom_minimum_size.x = bubble_width(_label.text)
	# Grows left from the corner and down; the container's minimum size sets the height.
	var w := _bubble.get_combined_minimum_size().x
	_bubble.offset_left = _bubble.offset_right - w
	_bubble.offset_bottom = _bubble.offset_top
	_bubble.visible = bubble_enabled and not _parked and not _captioned
	body.set_expression(line.expression)
	body.say_start()
	line_started.emit(line, priority)


## cut: the line leaves before its read time ran out (M47.5a: the terminal marks it).
func _end_line(cut := false) -> void:
	if _current == null:
		return
	var was := _current
	_current = null
	if cut and (_chars < was.text.length() or _hold > 0.0):
		line_cut.emit(was)
	_bubble.visible = false
	body.say_end()
	body.set_expression(&"idle")

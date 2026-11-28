extends Control
## M48.6b: the corner plate at the view's top left (PLAN 0.9.2; the mockup's `.kp`): a skull and
## the bugs left to the session's goal, counting down, or a clock and the time left (m:ss). It
## reads RailState's `count` (the frame's snap) and hides when the session has no count. The
## number bumps up for a moment when it changes (never under reduce flashing) and turns mint at
## zero. A child of the host over the view's glass; presentation only.

const BUMP_MS := 240
const H := 20   ## art px

var frame: Node   ## the CabinetFrame
var _text := ""
var _kind: StringName = &""
var _bump_at := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reading() -> Dictionary:
	return frame.snap.get("count", {}) if frame != null else {}


## The plate is on screen: the cabinet shows and the session has a count.
func shown() -> bool:
	return frame != null and frame.on and bool(reading().get("on", false))


func icon() -> StringName:
	return &"clock" if reading().get("kind", &"bugs") == &"clock" else &"skull"


func text() -> String:
	return RailState.count_text(reading()) if shown() else ""


func zero() -> bool:
	return shown() and int(reading().get("n", 0)) <= 0


## The number is in its bump (the first half of BUMP_MS after a change).
func bumping() -> bool:
	return Time.get_ticks_msec() - _bump_at < BUMP_MS / 2.0


## The frame's refresh: a changed number bumps (not the first one of a count, not a change of
## kind, never under reduce flashing).
func note() -> void:
	var t := text()
	var k := icon() if shown() else &""
	if t != _text or k != _kind:
		if k != _kind:
			_bump_at = -100000   # another count: its first number never bumps
		elif t != "" and _text != "" and not SaveGame.reduce_flashing():
			_bump_at = Time.get_ticks_msec()
		_text = t
		_kind = k
		queue_redraw()
	visible = shown()


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _bump_at < BUMP_MS:
		queue_redraw()


## The number's size and the plate's width in art px.
func number_size() -> int:
	return CabinetLayout.text_px(4, frame.s())


func width_art() -> int:
	var a: float = frame.art()
	var num_w := maxf(16.0 * a, RailFrame.text_w(_text, number_size(), true))
	return 1 + 8 + 3 + ceili(num_w / a) + 2


func _draw() -> void:
	if not shown() or not frame.layout.has("plate"):
		return
	var a: float = frame.art()
	var at: Vector2 = Vector2(frame.layout.plate) - position
	CabinetArt.draw9(self, &"kill_plate", at, width_art(), H, a)
	if icon() == &"clock":
		CabinetArt.hud(self, &"clock", at + Vector2(1, 6) * a, a)
	else:
		CabinetArt.orn(self, &"skull", at + Vector2(1, 5) * a, a)
	var size := number_size()
	var font := UiTheme.pixel_font(true)
	var cap_h := size * 7.0 / 11.0
	var y := roundf(at.y + (H * a - cap_h) * 0.5 - (font.get_ascent(size) - cap_h))
	if bumping():
		y -= 2.0 * a
	var x := at.x + 12.0 * a
	var color := CabinetArt.c(&"mint") if zero() else (CabinetArt.c(&"orange") if icon() == &"clock" else CabinetArt.c(&"gold"))
	RailFrame.text(self, Vector2(x + a, y + a), _text, size, CabinetArt.c(&"ink"), true)
	RailFrame.text(self, Vector2(x, y), _text, size, color, true)

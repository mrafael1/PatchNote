extends Control
# path:auto
## Auto's path widget (PLAN v9 1.5, 2): "LV n" with a thin bar to the next level beside it,
## then the held weapons ("Pistol II  Shotgun I") on one line. PathRunner hands it to the
## HUD while Auto and `levelups` are live. M47.2 (owner G14a): the HUD places it in the
## top-right band, left of the corner text, out from under the mascot (its minimum size is
## its content, at most Hud.PATH_MAX_W wide: a longer held list ends "... +n"; F1 and
## text() keep the whole list).

const BAR := Vector2(120, 6)
const MAX_W := 300.0

var meter: RefCounted        ## paths/auto/level_meter.gd
var loadout: Loadout

var _label: Label
var _held: Label
var _back: ColorRect
var _fill: ColorRect
var _all := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = _make_label(18)
	_held = _make_label(15)
	_held.position = Vector2(0, 27)
	_back = ColorRect.new()
	_back.color = Color(1, 1, 1, 0.15)
	_back.size = BAR
	_back.position = Vector2(62, 10)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	_fill = ColorRect.new()
	_fill.color = Palette.GEM
	_fill.size = Vector2(0, BAR.y)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(_fill)
	_refresh()


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	l.add_theme_constant_override(&"outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(_delta: float) -> void:
	_refresh()


## "LV n" and the whole held list (tests, F1).
func text() -> String:
	return "%s\n%s" % [_label.text, _all] if _label != null else ""


func bar() -> float:
	return _fill.size.x / BAR.x if _fill != null else 0.0


## The held list that fits MAX_W at the held line's font: "A  B  ... +n" past it.
func shown_held() -> String:
	return _held.text if _held != null else ""


func _refresh() -> void:
	if meter == null or _label == null:
		return
	var held: Array[String] = []
	if is_instance_valid(loadout):
		for w in loadout.slots + loadout.passives:
			held.append(w.label())
	_all = "  ".join(held)
	_label.text = "LV %d" % int(meter.get(&"level"))
	var font := ThemeDB.fallback_font
	var shown := held.size()
	var line := _all
	while shown > 0 and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 10.0 > MAX_W:
		shown -= 1
		line = "  ".join(held.slice(0, shown)) + "  ... +%d" % (held.size() - shown)
	_held.text = line
	_fill.size = Vector2(BAR.x * float(meter.call(&"progress")), BAR.y)
	custom_minimum_size = Vector2(minf(MAX_W, maxf(_back.position.x + BAR.x, _held.get_combined_minimum_size().x)),
			_held.position.y + _held.get_combined_minimum_size().y)

extends Control
# path:auto
## Auto's path widget (PLAN v9 1.5, 2): "LV n" with a thin bar to the next level beside it,
## then the held weapons ("Pistol II  Shotgun I") on one line. PathRunner hands it to the
## HUD while Auto and `levelups` are live. M47.2 (owner G14a): the HUD places it in the
## top-right band, left of the corner text, out from under the mascot (its minimum size is
## its content, at most Hud.PATH_MAX_W wide: a longer held list ends "... +n"; F1 and
## text() keep the whole list).
## M50.4a (Auto depth design 7): with shared slots, row 2 is every held weapon (aimed and
## passive-mode, "Pistol 6*" where * = the top rank) and the passive item slots ("+" each free
## one; M50.4b: each held item, "Haste 2  Area 1") sit dim right of the bar, so the widget keeps
## the band's 60 px.
## M50.4c1: an evolution reads "MINIGUN" in row 2, and once the `evolve` basic is live a dim
## row 3 shows PathRunner.evolve_hint() ("EVOLVE next level: pistol lv 6 + haste -> MINIGUN").

const BAR := Vector2(120, 6)
const MAX_W := 300.0
const _ITEMS_X := 192.0   ## M50.4a: the item slots, right of the bar (62 + 120 + 10)

var meter: RefCounted        ## paths/auto/level_meter.gd
var loadout: Loadout
var runner: Node             ## M50.4c1: the PathRunner (evolve_hint); null in tests that skip it

var _label: Label
var _held: Label
var _items: Label
var _hint: Label
var _back: ColorRect
var _fill: ColorRect
var _all := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = _make_label(18)
	_held = _make_label(15)
	_held.position = Vector2(0, 27)
	_items = _make_label(13)
	_items.position = Vector2(_ITEMS_X, 3)
	_items.modulate = Color(1, 1, 1, 0.7)
	_items.visible = false
	_hint = _make_label(10)
	_hint.position = Vector2(0, 45)
	_hint.modulate = Color(1, 1, 1, 0.7)
	_hint.visible = false
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


## "LV n" and the whole held list (tests, F1); M50.4a: then the item row when it shows.
func text() -> String:
	if _label == null:
		return ""
	return "%s\n%s" % [_label.text, _all] + ("\n" + _items.text if _items.visible else "") \
			+ ("\n" + _hint.text if _hint.visible else "")


func bar() -> float:
	return _fill.size.x / BAR.x if _fill != null else 0.0


## The held list that fits MAX_W at the held line's font: "A  B  ... +n" past it.
func shown_held() -> String:
	return _held.text if _held != null else ""


func _refresh() -> void:
	if meter == null or _label == null:
		return
	var held: Array[String] = []
	var shared := is_instance_valid(loadout) and loadout.shared_slots
	if is_instance_valid(loadout):
		for w in loadout.slots + loadout.passives:
			var top := shared and w.deep() and loadout.rank_cap > 0 and w.rank >= loadout.rank_cap
			held.append(w.label() + ("*" if top else ""))
	_all = "  ".join(held)
	_label.text = "LV %d" % int(meter.get(&"level"))
	var font := ThemeDB.fallback_font
	var shown := held.size()
	var line := _all
	while shown > 0 and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 10.0 > MAX_W:
		shown -= 1
		line = "  ".join(held.slice(0, shown)) + "  ... +%d" % (held.size() - shown)
	_held.text = line
	var items_def := meter.get(&"def") as PathDef
	_items.visible = shared and items_def != null and items_def.max_items > 0
	if _items.visible:
		# M50.4b: each held item ("Haste 2"), then a "+" per free slot.
		var held_items: Array[String] = []
		for it in loadout.items:
			held_items.append(it.label())
		var free: Array[String] = []
		for i in maxi(0, items_def.max_items - loadout.items.size()):
			free.append("+")
		if held_items.is_empty():
			_items.text = "Passives  " + " ".join(free)
		else:
			_items.text = "  ".join(held_items) + ("  " + " ".join(free) if not free.is_empty() else "")
	var hint := String(runner.call(&"evolve_hint")) if is_instance_valid(runner) else ""
	_hint.visible = hint != ""
	_hint.text = hint
	_fill.size = Vector2(BAR.x * float(meter.call(&"progress")), BAR.y)
	var top_w := _back.position.x + BAR.x
	if _items.visible:
		top_w = _items.position.x + _items.get_combined_minimum_size().x
	custom_minimum_size = Vector2(minf(MAX_W, maxf(top_w, _held.get_combined_minimum_size().x)),
			_held.position.y + _held.get_combined_minimum_size().y)
	if _hint.visible:
		custom_minimum_size.y = _hint.position.y + _hint.get_combined_minimum_size().y

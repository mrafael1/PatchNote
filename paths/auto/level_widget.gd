extends Control
# path:auto
## Auto's path widget (PLAN v9 1.5, 2): "LV n", a thin bar to the next level and the held
## weapons ("Pistol II  Shotgun I"), under the corner HP text (M39.2's corner style; HUD
## styles are M51). PathRunner hands it to the HUD while Auto and `levelups` are live.

const BAR := Vector2(150, 6)

var meter: RefCounted        ## paths/auto/level_meter.gd
var loadout: Loadout

var _label: Label
var _back: ColorRect
var _fill: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	position += Vector2(-14 - BAR.x, 64)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_back = ColorRect.new()
	_back.color = Color(1, 1, 1, 0.15)
	_back.size = BAR
	_back.position = Vector2(0, 26)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	_fill = ColorRect.new()
	_fill.color = Color(0.45, 0.95, 1.0)
	_fill.size = Vector2(0, BAR.y)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(_fill)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func text() -> String:
	return _label.text if _label != null else ""


func bar() -> float:
	return _fill.size.x / BAR.x if _fill != null else 0.0


func _refresh() -> void:
	if meter == null or _label == null:
		return
	var held: Array[String] = []
	if is_instance_valid(loadout):
		for w in loadout.slots + loadout.passives:
			held.append(w.label())
	_label.text = "LV %d\n%s" % [int(meter.get(&"level")), "  ".join(held)]
	_back.position.y = 50
	_fill.size = Vector2(BAR.x * float(meter.call(&"progress")), BAR.y)

extends Control
# path:survival
## Survival's path widget (PLAN v9 1.5, 2, M47): the held gun with its rank pips and ammo
## ("Shotgun II ●●○ 18/24", one ammo pip per 10 rounds), then the sidearm ("+ Pistol ∞"),
## in the corner style of Auto's LevelWidget. PathRunner hands it to the HUD. M47.2: the HUD
## places it in the top-right band, left of the corner text (its minimum size is its text).

var loadout: Loadout

var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 17)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_process(0.0)


func _process(_delta: float) -> void:
	if _label != null and is_instance_valid(loadout):
		_label.text = line_for(loadout)
		custom_minimum_size = _label.get_combined_minimum_size()


func text() -> String:
	return _label.text if _label != null else ""


static func line_for(lo: Loadout) -> String:
	if lo == null or lo.current() == null:
		return ""
	var w := lo.current()
	var pips := "●".repeat(w.rank) + "○".repeat(maxi(0, Loadout.MAX_RANK - w.rank))
	var top := "%s %s" % [w.label(), pips]
	if w.def.ammo > 0 and not lo.on_sidearm():
		top += " %d/%d %s" % [w.ammo_left, w.def.ammo, "▮".repeat(ceili(w.ammo_left / 10.0))]
	var side := lo.sidearm.label() if lo.sidearm != null else "Pistol"
	return "%s\n+ %s ∞" % [top, side] if not lo.on_sidearm() else "%s ∞" % top

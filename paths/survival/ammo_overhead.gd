class_name AmmoOverhead
extends Node2D
# path:survival
## M47.6d1 (PLAN v9.4 0.8, owner: "the ammo count shown above the player"): Survival's rounds
## over the player's head, OFFSET px above its centre. The revolver (a magazine) shows the
## rounds in its load ("4") and, while it reloads, a small arc filling over the reload; a
## scavenged gun shows its ammo left ("18"). PathRunner adds it to the player while Survival
## is live (the corner's ammo widget keeps the full readout).
##
## Presentation only: it reads the Loadout, writes nothing, reads no RNG.

const OFFSET := Vector2(0, -38)
const FONT_SIZE := 18
const ARC_R := 9.0
const ARC_W := 2.5

var loadout: Loadout
var _font: Font


func _ready() -> void:
	z_index = 50
	_font = ThemeDB.fallback_font


## What it shows now: the rounds as text ("" when nothing), and the reload 0..1 (-1: none).
func readout() -> Array:
	if not is_instance_valid(loadout) or loadout.current() == null:
		return ["", -1.0]
	var w := loadout.current()
	if w.has_magazine():
		if w.reloading():
			var full := maxf(0.001, float(w.value(&"reload_s")))
			return ["", clampf(1.0 - w.reload_left / full, 0.0, 1.0)]
		return [str(w.mag_left), -1.0]
	if w.def.ammo > 0 and not loadout.on_sidearm():
		return [str(w.ammo_left), -1.0]
	return ["", -1.0]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := readout()
	var text: String = r[0]
	var reload: float = r[1]
	if reload >= 0.0:
		draw_arc(OFFSET, ARC_R, 0.0, TAU, 24, Color(Palette.SHADOW, 0.6), ARC_W + 2.0, true)
		draw_arc(OFFSET, ARC_R, -PI / 2.0, -PI / 2.0 + TAU * reload, 24, Palette.PICKUP, ARC_W, true)
		return
	if text == "":
		return
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var at := OFFSET + Vector2(-sz.x * 0.5, sz.y * 0.3)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 5, Palette.OUTLINE)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.UI_TEXT)

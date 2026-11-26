class_name PathTitle
extends Label
## M47.6d1 (PLAN v9.4 0.8, owner: "a title for each path"): the path's display name (PathDef.title:
## ARCADE, SURVIVAL, AUTO) centred on the game window when a `path` cue lands, over its swap's
## 1.5 s warning: IN_S in (a fade, and a small scale settle unless reduce flashing), HOLD_S
## held, OUT_S out, then it frees itself. PathRunner adds it to the HUD layer.
##
## Presentation only: it reads no RNG and no sim state, and it runs on frame time (the pause
## stops it with the game).

const IN_S := 0.2
const HOLD_S := 0.8
const OUT_S := 0.2
const FONT_SIZE := 72
const POP := 0.18        ## the scale it settles from (1.18 -> 1.0); none under reduce flashing

var gentle := false      ## reduce flashing whatever the setting (tests)
var t := 0.0


static func make(title_text: String) -> PathTitle:
	var l := PathTitle.new()
	l.text = title_text
	l.name = "PathTitle"
	return l


func _ready() -> void:
	gentle = gentle or SaveGame.reduce_flashing()
	process_mode = Node.PROCESS_MODE_PAUSABLE   # the HUD runs ALWAYS; the card waits with the game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_color_override(&"font_color", Palette.UI_TEXT)
	add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	add_theme_constant_override(&"outline_size", 14)
	_apply()


func total() -> float:
	return IN_S + HOLD_S + OUT_S


## 0..1: how visible the card is now.
func alpha_at(time: float) -> float:
	if time < IN_S:
		return time / IN_S
	if time < IN_S + HOLD_S:
		return 1.0
	return clampf(1.0 - (time - IN_S - HOLD_S) / OUT_S, 0.0, 1.0)


func _process(delta: float) -> void:
	t += delta
	if t >= total():
		queue_free()
		return
	_apply()


func _apply() -> void:
	modulate.a = alpha_at(t)
	pivot_offset = size * 0.5
	var s := 1.0 if gentle else 1.0 + POP * (1.0 - clampf(t / IN_S, 0.0, 1.0))
	scale = Vector2(s, s)

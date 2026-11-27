class_name SniperLine
extends Line2D
## The sniper's aim line (M50.3c, PLAN v9 1.9): from the sniper along the direction it locked
## when the windup began, to the first wall. Its colour is the `danger` role and it thickens
## as the shot nears. While it shows it is in the `danger_zone` group with `from` / `to` in
## world space (what a bot may read). Presentation only: the sniper owns the timing.

const GROUP := &"danger_zone"

var from := Vector2.ZERO
var to := Vector2.ZERO
var strength := 0.0:
	set(v):
		strength = v
		width = 2.0 + 3.0 * v
		default_color = Color(Palette.color(&"danger"), 0.35 + 0.55 * v)


func _ready() -> void:
	top_level = true
	z_index = 4
	visible = false
	strength = 0.0


func show_line(p_from: Vector2, p_to: Vector2) -> void:
	from = p_from
	to = p_to
	points = PackedVector2Array([p_from, p_to])
	visible = true
	if not is_in_group(GROUP):
		add_to_group(GROUP)


func hide_line() -> void:
	visible = false
	if is_in_group(GROUP):
		remove_from_group(GROUP)

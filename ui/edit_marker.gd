class_name EditMarker
extends CanvasLayer
## The rule edit warning marker (PLAN v8 1.4): what is about to change (the target's
## icon) on a pulsing ring at the screen edge, towards what the AI points at. Shown by
## RuleBook during an edit's warning. Presentation only; it pulses on real time, so slow
## motion does not slow it. Gentle (reduce_flashing): a slow scale pulse, no flicker.

const INSET := 56.0
const RADIUS := 26.0
const TOP_FREE := 190.0   ## below the HUD line and the mascot's corner
const COLOR := Palette.MARKER

var target: StringName = &""
var gentle := false
var _icon: Control


func _ready() -> void:
	layer = 55
	_icon = Control.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.size = Vector2.ONE * RADIUS * 2.0
	_icon.pivot_offset = _icon.size * 0.5
	_icon.draw.connect(_draw_icon)
	add_child(_icon)
	_icon.visible = false


func show_for(p_target: StringName, screen_pos: Vector2, p_gentle: bool) -> void:
	target = p_target
	gentle = p_gentle
	_icon.position = edge_position(screen_pos, _view_size()) - _icon.size * 0.5
	_icon.visible = true
	_icon.queue_redraw()


func hide_marker() -> void:
	_icon.visible = false


func is_showing() -> bool:
	return _icon.visible


func _view_size() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp else Vector2(1280, 720)


## Where the marker sits: on the screen's edge (inset), in the direction of screen_pos
## from the centre; at the top under the HUD when it points at the centre.
static func edge_position(screen_pos: Vector2, view: Vector2) -> Vector2:
	var centre := view * 0.5
	var d := screen_pos - centre
	if d.length() < 1.0:
		return Vector2(centre.x, TOP_FREE * 0.5 + INSET * 0.5)
	var half := centre - Vector2.ONE * INSET
	var k := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	var p := centre + d * k
	p.y = maxf(p.y, TOP_FREE)   # never on the HUD lines or the mascot's corner
	return p


func _process(_delta: float) -> void:
	if not _icon.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	if gentle:
		_icon.scale = Vector2.ONE * (1.0 + 0.06 * sin(t * 2.5))
		_icon.modulate.a = 1.0
	else:
		_icon.scale = Vector2.ONE * (1.0 + 0.15 * sin(t * 9.0))
		_icon.modulate.a = 0.65 + 0.35 * sin(t * 9.0)


func _draw_icon() -> void:
	var c := _icon.size * 0.5
	_icon.draw_circle(c, RADIUS, Color(Palette.SHADOW, 0.55))
	_icon.draw_arc(c, RADIUS, 0.0, TAU, 40, COLOR, 3.0, true)
	draw_target(_icon, c, target, COLOR)


## The target's icon at c (about 24 px), on any CanvasItem.
static func draw_target(ci: CanvasItem, c: Vector2, p_target: StringName, color: Color) -> void:
	match p_target:
		&"walls":   # bricks
			for row in 3:
				var y := c.y - 9.0 + row * 6.0
				var shift := 4.0 if row % 2 == 1 else 0.0
				for col in 2:
					ci.draw_rect(Rect2(c.x - 11.0 + shift + col * 11.0, y, 9.0, 4.5), color)
		&"enemies":   # a square with two eyes
			ci.draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), color)
			ci.draw_rect(Rect2(c + Vector2(-5, -3), Vector2(3, 3)), Palette.OUTLINE)
			ci.draw_rect(Rect2(c + Vector2(2, -3), Vector2(3, 3)), Palette.OUTLINE)
		&"player":   # the player's square and its barrel
			ci.draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), color, false, 2.5)
			ci.draw_line(c, c + Vector2(12, 0), color, 2.5)
		&"world":   # a globe
			ci.draw_arc(c, 10.0, 0.0, TAU, 24, color, 2.0, true)
			ci.draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), color, 1.5)
			ci.draw_arc(c, 5.0, -PI * 0.5, PI * 0.5, 12, color, 1.5, true)
		_:   # the game: a cog
			ci.draw_arc(c, 7.0, 0.0, TAU, 20, color, 3.0, true)
			for k in 8:
				var a := k * TAU / 8.0
				ci.draw_line(c + Vector2.from_angle(a) * 8.0, c + Vector2.from_angle(a) * 12.0, color, 3.0)

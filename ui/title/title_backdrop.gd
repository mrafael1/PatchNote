class_name TitleBackdrop
extends Control
## M47.4 (PLAN 1.16): the title's backdrop, the arena's grid scrolling slowly behind the
## menu (frame time, presentation only). The look's `bg` and `grid` roles when it is on.

const CELL := 48.0
const SPEED := Vector2(12, 6)   ## px per second
const LIGHT := 0.07             ## the grid's alpha here (the arena's is fainter)

var scroll := Vector2.ZERO
var running := true             ## false: the owner sets `scroll` (the door beat)
## M51b: the odometer title's plum backdrop (ODO_BG, a 2 px ODO_GRID every CELL px) whatever
## look is on; false: the arena's grid (the door beat).
var plum := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Skins.hub.skin_changed.connect(_on_skin_changed)


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)


func _on_skin_changed(_skin: ArtSkin) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if running and is_visible_in_tree():
		scroll += SPEED * delta
		queue_redraw()


func _draw() -> void:
	if plum:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.ODO_BG)
		var o := Vector2(fposmod(scroll.x, CELL), fposmod(scroll.y, CELL)).round()
		var gx := o.x - CELL
		while gx < size.x:
			draw_rect(Rect2(gx, 0, 2, size.y), Palette.ODO_GRID)
			gx += CELL
		var gy := o.y - CELL
		while gy < size.y:
			draw_rect(Rect2(0, gy, size.x, 2), Palette.ODO_GRID)
			gy += CELL
		return
	var pixel := Skins.is_on(&"ui_panel")
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color(&"bg").darkened(0.6) if pixel else Palette.TITLE_BG)
	var line := Color(Palette.color(&"grid") if pixel else Palette.GRID, LIGHT)
	var off := Vector2(fposmod(scroll.x, CELL), fposmod(scroll.y, CELL))
	var x := off.x - CELL
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
		x += CELL
	var y := off.y - CELL
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y += CELL
	# A soft floor fade: the grid sinks into the background at the bottom.
	var fade := Palette.color(&"bg").darkened(0.6) if pixel else Palette.TITLE_BG
	for i in 8:
		var h := size.y * 0.25 / 8.0
		draw_rect(Rect2(0, size.y - h * (8 - i), size.x, h), Color(fade, 0.1 * float(i + 1)))

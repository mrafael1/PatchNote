class_name TitleLogo
extends Control
## M47.4 (PLAN 1.16): "PATCH NOTES" drawn in code from a 5x7 block font. Accent cells over a
## shadow. With the look's UI on (`Skins.is_on(&"ui_panel")`) the cells snap to a 3 px grid
## (no rounding gap: chunkier) and take the look's `accent` role.
##
## `assembled` (0..1) drops the cells in, column by column (a fixed order, no RNG): the door
## beat animates it; the title shows it at 1.

const TEXT := "PATCH NOTES"
const GLYPHS := {
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
}
const CELL := 9.0
const GAP := 2.0
const PIXEL_GAP := 3.0
const SHADOW_AT := Vector2(4, 4)
const DROP := 26.0     ## a cell falls this far as it lands
const LAND := 0.18     ## the part of `assembled` one cell takes to land

var assembled := 1.0:
	set(v):
		assembled = clampf(v, 0.0, 1.0)
		queue_redraw()

var _cells: Array[Vector2i] = []   ## (column, row) on the logo's grid, in drop order


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cells = cells()
	custom_minimum_size = logo_size()
	Skins.hub.skin_changed.connect(_on_skin_changed)


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)


func _on_skin_changed(_skin: ArtSkin) -> void:
	custom_minimum_size = logo_size()
	queue_redraw()


## Every lit cell as (column, row) over the whole text (6 columns per letter: 5 + a space),
## column-major: the drop order.
static func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in TEXT.length():
		var g: Array = GLYPHS.get(TEXT[i], [])
		for x in 5:
			for y in g.size():
				if String(g[y])[x] == "#":
					out.append(Vector2i(i * 6 + x, y))
	return out


static func pitch() -> float:
	return CELL + (PIXEL_GAP if Skins.is_on(&"ui_panel") else GAP)


static func logo_size() -> Vector2:
	return Vector2((TEXT.length() * 6 - 1) * pitch(), 7 * pitch()) + SHADOW_AT


func _draw() -> void:
	var p := pitch()
	var pixel := Skins.is_on(&"ui_panel")
	var size_px := p if pixel else CELL   # the pixel logo has no gap: solid blocks
	var accent := Palette.color(&"accent") if pixel else Palette.ACCENT
	var n := _cells.size()
	for i in n:
		var t := clampf((assembled - (1.0 - LAND) * float(i) / float(maxi(n - 1, 1))) / LAND, 0.0, 1.0)
		if t <= 0.0:
			continue
		var c := _cells[i]
		var at := Vector2(c.x * p, c.y * p - DROP * (1.0 - t) * (1.0 - t))
		if pixel:
			at = at.snapped(Vector2(3, 3))
		draw_rect(Rect2(at + SHADOW_AT, Vector2(size_px, size_px)), Color(Palette.SHADOW, 0.55 * t))
		draw_rect(Rect2(at, Vector2(size_px, size_px)), Color(accent, t))

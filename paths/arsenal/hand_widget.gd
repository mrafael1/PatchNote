extends Control
# path:arsenal
## Arsenal's path widget (PLAN v9 1.5, 2; M46): the hand, one row per aimed card,
## "[1] Pistol ●●○" (its key on the player's layout, its rank pips out of Loadout.MAX_RANK),
## the active card raised and brighter, then a thin bar to the next card and "cards n/6".
## Under the corner HP text (M39.2's corner style, as LevelWidget; HUD styles are M51). No
## passive row yet: nothing offers Arsenal a passive before S11 (M51 adds the row).

const BAR := Vector2(150, 6)
const ROWS := 3               ## Arsenal's hand (PathDef.max_slots)
const ROW_H := 24.0
const RAISE := 6.0
const DIM := Color(0.75, 0.75, 0.8)
const LIT := Color(1.0, 0.95, 0.5)

var meter: RefCounted        ## paths/arsenal/card_meter.gd
var loadout: Loadout
var max_cards := 6

var _rows: Array[Label] = []
var _count: Label
var _back: ColorRect
var _fill: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	position += Vector2(-14 - BAR.x, 64)
	for i in ROWS:
		_rows.append(_label())
	_count = _label()
	_back = ColorRect.new()
	_back.color = Color(1, 1, 1, 0.15)
	_back.size = BAR
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	_fill = ColorRect.new()
	_fill.color = Color(1.0, 0.85, 0.35)
	_fill.size = Vector2(0, BAR.y)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(_fill)
	EventBus.weapon_changed.connect(_on_weapon_changed)
	_refresh()


func _exit_tree() -> void:
	if EventBus.weapon_changed.is_connected(_on_weapon_changed):
		EventBus.weapon_changed.disconnect(_on_weapon_changed)


func _process(_delta: float) -> void:
	_refresh()


## Every visible row's text, then the count line (tests).
func text() -> String:
	var out: Array[String] = []
	for r in _rows:
		if r.visible:
			out.append(r.text)
	if _count != null:
		out.append(_count.text)
	return "\n".join(out)


func bar() -> float:
	return _fill.size.x / BAR.x if _fill != null else 0.0


## The raised row's index (-1: none).
func active_row() -> int:
	for i in _rows.size():
		if _rows[i].visible and _rows[i].position.y < i * ROW_H:
			return i
	return -1


func _on_weapon_changed(_id: StringName, _rank: int) -> void:
	_refresh()


func _label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", 18)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _refresh() -> void:
	if _count == null:
		return
	var slots: Array[Weapon] = loadout.slots if is_instance_valid(loadout) else ([] as Array[Weapon])
	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < slots.size()
		if not row.visible:
			continue
		var w := slots[i]
		var lit := is_instance_valid(loadout) and i == loadout.active
		row.text = "[%s] %s %s" % [InputSetup.expand_keys("{key:weapon_%d}" % (i + 1)), w.def.title, pips(w.rank)]
		row.position = Vector2(0, i * ROW_H - (RAISE if lit else 0.0))
		row.add_theme_color_override(&"font_color", LIT if lit else DIM)
	var y := maxi(slots.size(), 1) * ROW_H + 4.0
	var cards := int(meter.get(&"cards")) if meter != null else 0
	_count.text = "cards %d/%d" % [cards, max_cards]
	_count.position = Vector2(0, y)
	_back.position = Vector2(0, y + ROW_H + 2.0)
	_fill.size = Vector2(BAR.x * (float(meter.call(&"progress")) if meter != null else 0.0), BAR.y)


## "●●○": rank filled of Loadout.MAX_RANK.
static func pips(rank: int) -> String:
	return "●".repeat(clampi(rank, 0, Loadout.MAX_RANK)) + "○".repeat(maxi(0, Loadout.MAX_RANK - rank))

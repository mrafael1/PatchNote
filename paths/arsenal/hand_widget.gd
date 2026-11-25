extends Control
# path:arsenal
## Arsenal's path widget (PLAN v9 1.5, 2; M46): the hand. M47.2 (owner G14a: "cards should
## have a card hand on bottom left and you see current weapons and which is equipped (real
## cards)"): one drawn card per aimed weapon in the bottom-left corner, out from under the
## mascot: a key badge (the player's layout), the title, rank pips of Loadout.MAX_RANK and
## the weapon's glyph (WeaponGlyph, its WeaponDef.icon). The equipped card is raised and lit,
## the others lowered and dimmed. A switch raises the new card in about 0.12 s; a new card
## slides up and fades in over 0.25 s (no brightness flash with reduce_flashing; the lit
## card never pulses). The card meter ("cards n/6" over a bar) sits right of the 3 slots.
## Hud places it with hand_rect(). Plain shapes and colours only (the look is M48). No
## passive row yet (M51). It runs while the pick panel pauses the tree (Hud's ALWAYS): a
## card given by a pick slides in behind the panel.

const CARD := Vector2(64, 92)
const GAP := 8.0
const MARGIN := 8.0
const RAISE := 8.0
const SLIDE := 40.0
const ROWS := 3               ## Arsenal's hand (PathDef.max_slots): 3 slots kept free
const BAR := Vector2(110, 6)
const METER_GAP := 10.0
const RAISE_TIME := 0.12
const JOIN_TIME := 0.25
const DIM := Color(0.75, 0.75, 0.8)
const LIT := Color(1.0, 0.95, 0.5)
const FACE := Color(0.1, 0.11, 0.16, 0.94)
const BAR_FILL := Color(1.0, 0.85, 0.35)

var meter: RefCounted        ## paths/arsenal/card_meter.gd
var loadout: Loadout
var max_cards := 6
## Tests: the tween moves only through step().
var manual := false

var _lift: Array[float] = []
var _join: Array[float] = []
var _ids: Array[StringName] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.weapon_changed.connect(_on_weapon_changed)
	_sync()
	for i in _lift.size():
		_lift[i] = 1.0 if i == equipped() else 0.0
		_join[i] = 0.0


func _exit_tree() -> void:
	if EventBus.weapon_changed.is_connected(_on_weapon_changed):
		EventBus.weapon_changed.disconnect(_on_weapon_changed)


func _process(delta: float) -> void:
	if not manual:
		step(delta)


## One tick of the switch and join tweens (tests call it with a chosen delta).
func step(delta: float) -> void:
	_sync()
	for i in _lift.size():
		_lift[i] = move_toward(_lift[i], 1.0 if i == equipped() else 0.0, delta / RAISE_TIME)
		_join[i] = move_toward(_join[i], 0.0, delta / JOIN_TIME)
	queue_redraw()


## A new or replaced card starts its join; a dropped one goes.
func _sync() -> void:
	var slots := _slots()
	while _ids.size() > slots.size():
		_ids.pop_back()
		_lift.pop_back()
		_join.pop_back()
	for i in slots.size():
		var id := slots[i].def.id
		if i >= _ids.size():
			_ids.append(id)
			_lift.append(0.0)
			_join.append(1.0)
		elif _ids[i] != id:
			_ids[i] = id
			_join[i] = 1.0


func _slots() -> Array[Weapon]:
	return loadout.slots if is_instance_valid(loadout) else ([] as Array[Weapon])


func _on_weapon_changed(_id: StringName, _rank: int) -> void:
	_sync()
	queue_redraw()


func card_count() -> int:
	return _slots().size()


## The equipped card's index (-1: none).
func equipped() -> int:
	return loadout.active if is_instance_valid(loadout) and loadout.active < card_count() else -1


## M46's name for it (F1, tests).
func active_row() -> int:
	return equipped()


## Card i's switch key on the player's layout (to_label: tests' layout seam).
func key_label(i: int, to_label := Callable()) -> String:
	return InputSetup.expand_keys("{key:weapon_%d}" % (i + 1), to_label)


func card_title(i: int) -> String:
	return _slots()[i].def.title


func card_rank(i: int) -> int:
	return _slots()[i].rank


## The join's brightness flash on card i, 0..0.6 (none with reduce_flashing).
func join_flash(i: int) -> float:
	return 0.0 if SaveGame.reduce_flashing() else 0.6 * joining(i)


func lift(i: int) -> float:
	return _lift[i] if i < _lift.size() else 0.0


func joining(i: int) -> float:
	return _join[i] if i < _join.size() else 0.0


## Every card's row ("[1] Pistol ●○○"), then "cards n/6" (tests, F1).
func text() -> String:
	var out: Array[String] = []
	for i in card_count():
		out.append("[%s] %s %s" % [key_label(i), card_title(i), pips(card_rank(i))])
	out.append("cards %d/%d" % [_cards(), max_cards])
	return "\n".join(out)


func bar() -> float:
	return float(meter.call(&"progress")) if meter != null else 0.0


func _cards() -> int:
	return int(meter.get(&"cards")) if meter != null else 0


## The whole hand (3 slots, raised room and the meter) on a canvas of size `view`.
static func hand_rect(view: Vector2) -> Rect2:
	var w := ROWS * CARD.x + (ROWS - 1) * GAP + METER_GAP + BAR.x
	return Rect2(MARGIN, view.y - MARGIN - CARD.y - RAISE, w, CARD.y + RAISE)


## Card i's screen rect now (its lift and join slide in).
func card_rect(i: int, view: Vector2) -> Rect2:
	var y := view.y - MARGIN - CARD.y - RAISE * lift(i) + SLIDE * joining(i)
	return Rect2(MARGIN + i * (CARD.x + GAP), y, CARD.x, CARD.y)


func title_rect(i: int, view: Vector2) -> Rect2:
	var c := card_rect(i, view)
	return Rect2(c.position + Vector2(4, 28), Vector2(CARD.x - 8, 16))


func pips_rect(i: int, view: Vector2) -> Rect2:
	var c := card_rect(i, view)
	return Rect2(c.position + Vector2(8, 46), Vector2(CARD.x - 16, 10))


func meter_rect(view: Vector2) -> Rect2:
	var r := hand_rect(view)
	var x := MARGIN + ROWS * CARD.x + (ROWS - 1) * GAP + METER_GAP
	return Rect2(x, r.end.y - 30, BAR.x, 30)


func _draw() -> void:
	var view := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	for i in card_count():
		var w := _slots()[i]
		var lit := i == equipped()
		var r := card_rect(i, view)
		r.position -= position
		var edge := LIT if lit else DIM
		var a := 1.0 - joining(i)
		var fill := FACE.lerp(Color(0.5, 0.5, 0.6, 0.94), join_flash(i))
		var box := StyleBoxFlat.new()
		box.bg_color = Color(fill, fill.a * a)
		box.border_color = Color(edge, a * (1.0 if lit else 0.8))
		box.set_border_width_all(3 if lit else 2)
		box.set_corner_radius_all(6)
		draw_style_box(box, r)
		var ink := Color(edge, a * (1.0 if lit else 0.8))
		var badge := Rect2(r.position + Vector2(5, 5), Vector2(20, 20))
		draw_rect(badge, Color(edge, 0.25 * a))
		draw_rect(badge, ink, false, 1.5)
		draw_string(font, badge.position + Vector2(0, 15), key_label(i), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 13, ink)
		var t := title_rect(i, view)
		t.position -= position
		var fs := 13
		while fs > 8 and font.get_string_size(w.def.title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > t.size.x:
			fs -= 1
		draw_string(font, t.position + Vector2(0, 12), w.def.title, HORIZONTAL_ALIGNMENT_CENTER, t.size.x, fs, ink)
		var pr := pips_rect(i, view)
		pr.position -= position
		for k in Loadout.MAX_RANK:
			var c := pr.position + Vector2(pr.size.x * (k + 0.5) / Loadout.MAX_RANK, pr.size.y * 0.5)
			if k < w.rank:
				draw_circle(c, 3.5, ink)
			else:
				draw_arc(c, 3.5, 0.0, TAU, 12, ink, 1.2, true)
		WeaponGlyph.draw(self, w.def.icon, r.position + Vector2(CARD.x * 0.5, 74), 26.0, ink)
	var m := meter_rect(view)
	m.position -= position
	draw_string(font, m.position + Vector2(0, 14), "cards %d/%d" % [_cards(), max_cards],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
	var bar_at := Rect2(m.position + Vector2(0, m.size.y - BAR.y), BAR)
	draw_rect(bar_at, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(bar_at.position, Vector2(BAR.x * clampf(bar(), 0.0, 1.0), BAR.y)), BAR_FILL)


## "●●○": rank filled of Loadout.MAX_RANK.
static func pips(rank: int) -> String:
	return "●".repeat(clampi(rank, 0, Loadout.MAX_RANK)) + "○".repeat(maxi(0, Loadout.MAX_RANK - rank))

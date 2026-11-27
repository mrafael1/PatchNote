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
##
## M50.1a (Arsenal depth): a hand of 2 (ROWS). On the deep curve each card has a rank number
## badge (top right, any size: "7", "12") and, under the title, one dot per mechanic (lit once
## unlocked) with up to 3 tick marks under it for its strengthen level ("+" past 3); the pips
## stay for the classic curve only. On a pack path the meter reads "pack in n" over a bar of
## the pack's kills.
##
## M50.1b (fusion): the link on the seam between the two cards, hidden until the `fusion` basic
## is live and for any pair that is not a recipe (PathRunner.link_state): dim with a small "4"
## while a half is below rank 4, lit and slowly pulsing once FUSE is available (steady under
## reduce_flashing). A fused card has a two-tone frame, its parents under the title ("Shotgun
## + Laser") and 4 mechanic dots. The misfuse draws both cards as one wobbling card ("Pistgun?",
## both glyphs overlapped, a glitch frame; no wobble under reduce_flashing) that glitches out
## when the AI patches it.
##
## M50.7 (polish): a rank-up (a pack's +1, a give) bursts on its card for RANK_TIME: a gold ring
## and a "RANK n!" tag over it, fading (a steady highlight under reduce flashing); a landed pack
## pulses the stack chip once (STACK_PULSE; steady under reduce flashing), and the "[F] open"
## prompt reads larger on tier 0.

const CARD := Vector2(64, 92)
const GAP := 8.0
const MARGIN := 8.0
const RAISE := 8.0
const SLIDE := 40.0
const ROWS := 2               ## Arsenal's hand (PathDef.max_slots, M50.1a): 2 slots kept free
const BAR := Vector2(110, 6)
const METER_GAP := 10.0
const RAISE_TIME := 0.12
const JOIN_TIME := 0.25
const DIM := Palette.UI_DIM
const LIT := Palette.CARD_LIT
const FACE := Palette.UI_PANEL
const BAR_FILL := Palette.CARD_BAR

var meter: RefCounted        ## paths/arsenal/card_meter.gd
var loadout: Loadout
var runner: Node             ## M50.1b: the PathRunner (link_state); null in tests without one
var max_cards := 6
## Tests: the tween moves only through step().
var manual := false

var _lift: Array[float] = []
var _join: Array[float] = []
var _ids: Array[StringName] = []
var _panels := {}            ## M48a: lit -> this widget's copy of the look's UI panel
var _panel_version := -1
var _clock := 0.0            ## M50.1b: real seconds (the link's pulse, the misfuse's wobble)
var _misfuse := false
var _glitch_out := 0.0       ## M50.1b: seconds left of the misfuse's glitch-out

const GLITCH_OUT := 0.3
const RANK_TIME := 0.6      ## M50.7: the rank-up burst
const STACK_PULSE := 0.5    ## M50.7: the stack chip's pulse on a landed pack
var _ranks: Array[int] = []
var _rank_up: Array[float] = []
var _stack_seen := -1        ## -1: not read yet (a session's carried packs do not pulse)
var _stack_pulse := 0.0
const WOBBLE_HZ := 2.0
const WOBBLE_DEG := 5.0
const PULSE_HZ := 0.8


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(Skins.SKINNED)   # M48a: the look's live swap redraws it
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
	_clock += delta
	_glitch_out = maxf(0.0, _glitch_out - delta)
	for i in _rank_up.size():
		_rank_up[i] = maxf(0.0, _rank_up[i] - delta)
	_stack_pulse = maxf(0.0, _stack_pulse - delta)
	_sync()
	var stack := stack_count()
	if _stack_seen >= 0 and stack > _stack_seen:
		_stack_pulse = STACK_PULSE
	_stack_seen = stack
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
		_ranks.pop_back()
		_rank_up.pop_back()
	for i in slots.size():
		var id := slots[i].def.id
		if i >= _ids.size():
			_ids.append(id)
			_lift.append(0.0)
			_join.append(1.0)
			_ranks.append(slots[i].rank)
			_rank_up.append(0.0)
		elif _ids[i] != id:
			_ids[i] = id
			_join[i] = 1.0
			_ranks[i] = slots[i].rank
			_rank_up[i] = 0.0
		elif slots[i].rank > _ranks[i]:   # M50.7: the same card ranked up
			_ranks[i] = slots[i].rank
			_rank_up[i] = RANK_TIME
		else:
			_ranks[i] = slots[i].rank


## M50.7: seconds left of card i's rank-up burst (0 none).
func rank_up_left(i: int) -> float:
	return _rank_up[i] if i < _rank_up.size() else 0.0


## M50.7: the burst's tag ("RANK 5!"; "" with none).
func rank_tag(i: int) -> String:
	return "RANK %d!" % card_rank(i) if rank_up_left(i) > 0.0 and i < card_count() else ""


## M50.7: the burst's strength 0..1 now: a quick swell then a fade; a steady 0.8 under reduce
## flashing (no pulse).
func rank_glow(i: int) -> float:
	var left := rank_up_left(i)
	if left <= 0.0:
		return 0.0
	if SaveGame.reduce_flashing():
		return 0.8
	var k := 1.0 - left / RANK_TIME
	return minf(1.0, k * 6.0) * (1.0 - k)


## M50.7: seconds left of the stack chip's pulse.
func stack_pulse() -> float:
	return _stack_pulse


## M50.7: the stack chip's brightness 0..1 (1 at rest): the pulse dips and swells once; under
## reduce flashing it stays 1.
func stack_glow() -> float:
	if SaveGame.reduce_flashing() or _stack_pulse <= 0.0:
		return 1.0
	var k := 1.0 - _stack_pulse / STACK_PULSE
	return 0.55 + 0.45 * absf(cos(k * PI * 1.5))


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


## Every card's row ("[1] Pistol ●○○"; deep: "[1] Pistol 7 ●''●○"), then "cards n/6" (a pack
## path: "pack in n") (tests, F1).
func text() -> String:
	var out: Array[String] = []
	if _misfuse:
		out.append("[%s+%s] %s" % [key_label(0), key_label(1), misfuse_title()])
		out.append(meter_text())
		return "\n".join(out)
	for i in card_count():
		var w := _slots()[i]
		if w.deep():
			out.append("[%s] %s %d %s" % [key_label(i), card_title(i), card_rank(i), dots_text(card_levels(i))])
		else:
			out.append("[%s] %s %s" % [key_label(i), card_title(i), pips(card_rank(i))])
	out.append(meter_text())
	if waiting_count() > 0:
		out.append("%s %s" % [stack_text(), stack_hint()])
	return "\n".join(out)


## M50.6: the packs stacked ("2 packs", "" with none) and the key line under it ("[F] open",
## "open one" with key hints off). A pack opens only when the player asks.
func stack_count() -> int:
	return int(runner.call(&"pack_stack")) if runner != null and is_instance_valid(runner) and runner.has_method(&"pack_stack") else 0


## M50.7 review: the packs still waiting (the stack less the pack whose panel is open), what the
## "n packs [F] open" line counts.
func waiting_count() -> int:
	var showing := int(runner.call(&"pack_on_screen")) if runner != null and is_instance_valid(runner) 			and runner.has_method(&"pack_on_screen") else 0
	return maxi(0, stack_count() - showing)


func stack_text() -> String:
	var n := waiting_count()
	return "" if n <= 0 else "%d pack%s" % [n, "" if n == 1 else "s"]


func stack_hint() -> String:
	if waiting_count() <= 0:
		return ""
	return "[%s] open" % PathRunner.open_key() if Settings.key_hints() else "open one"


## "cards n/6", or on a pack path "pack in n" (the kills left).
func meter_text() -> String:
	if meter != null and meter.has_method(&"kills_left"):
		var left := int(meter.call(&"kills_left"))
		return "pack in %d" % left if left >= 0 else "no packs"
	return "cards %d/%d" % [_cards(), max_cards]


## M50.1a: card i's mechanic levels on the deep curve ([] on the classic curve). M50.1b: a
## fused card's 4.
func card_levels(i: int) -> Array[int]:
	var w := _slots()[i]
	if not w.deep():
		return [] as Array[int]
	return WeaponCurve.levels_of(w.def, w.rank)


## M50.1b: the link between the two cards (0 hidden, 1 dim, 2 lit; PathRunner.link_state).
func link_state() -> int:
	if card_count() != 2 or runner == null or not runner.has_method(&"link_state"):
		return 0
	return int(runner.call(&"link_state"))


## M50.1b: the lit link's brightness now, 0.6..1 (1, steady, under reduce_flashing).
func link_glow() -> float:
	if SaveGame.reduce_flashing():
		return 1.0
	return 0.8 + 0.2 * sin(_clock * TAU * PULSE_HZ)


## M50.1b: the misfuse overlay on / off (off starts the glitch-out).
func set_misfuse(on: bool) -> void:
	if _misfuse and not on:
		_glitch_out = GLITCH_OUT
	_misfuse = on
	queue_redraw()


func misfusing() -> bool:
	return _misfuse


## M50.1b: the misfuse card's title: "Pistgun?" (the first card's first 4 letters, the second
## card's last 3).
func misfuse_title() -> String:
	if card_count() < 2:
		return "?"
	return "%s%s?" % [card_title(0).left(4), card_title(1).right(3).to_lower()]


## M50.1b: the misfuse card's tilt now, degrees (0 under reduce_flashing).
func wobble() -> float:
	if SaveGame.reduce_flashing():
		return 0.0
	return WOBBLE_DEG * sin(_clock * TAU * WOBBLE_HZ)


## M50.1b: the seam's rect between card 0 and card 1.
func link_rect(view: Vector2) -> Rect2:
	var a := card_rect(0, view)
	return Rect2(Vector2(a.end.x - 4.0, a.position.y + CARD.y * 0.5 - 8.0), Vector2(GAP + 8.0, 16.0))


## "●''○○": one dot per mechanic (○ locked, ● unlocked), a ' per strengthen (up to 3), "+"
## past that.
static func dots_text(levels: Array[int]) -> String:
	var out := ""
	for lv in levels:
		if lv <= 0:
			out += "○"
			continue
		out += "●" + "'".repeat(mini(lv - 1, WeaponCurve.STEPS))
		if lv - 1 > WeaponCurve.STEPS:
			out += "+"
	return out


func rank_badge_rect(i: int, view: Vector2) -> Rect2:
	var c := card_rect(i, view)
	return Rect2(c.position + Vector2(CARD.x - 25, 5), Vector2(20, 20))


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
	if _misfuse and card_count() >= 2:
		_draw_misfuse(view, font)
	for i in card_count():
		if _misfuse and card_count() >= 2:
			break
		var w := _slots()[i]
		var lit := i == equipped()
		var r := card_rect(i, view)
		r.position -= position
		var edge := LIT if lit else DIM
		var a := 1.0 - joining(i)
		var fill := FACE.lerp(Palette.CARD_FLASH, join_flash(i))
		var panel := _skin_panel(lit)
		if panel != null:
			# M48a: the look's UI panel (Pixel: the 9-slice, gold-rimmed when equipped);
			# a joining card fades in, a dimmed one is greyed.
			panel.modulate_color = panel_modulate(lit, a, join_flash(i))
			draw_style_box(panel, r)
		else:
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
		if w.deep():
			_draw_deep(i, w, r, pr, ink, font, a)
		else:
			for k in Loadout.MAX_RANK:
				var c := pr.position + Vector2(pr.size.x * (k + 0.5) / Loadout.MAX_RANK, pr.size.y * 0.5)
				if k < w.rank:
					draw_circle(c, 3.5, ink)
				else:
					draw_arc(c, 3.5, 0.0, TAU, 12, ink, 1.2, true)
		WeaponGlyph.draw(self, w.def.icon, r.position + Vector2(CARD.x * 0.5, 74), 26.0, ink)
		if w.def.is_fusion():
			_draw_fused(w, r, ink, font, a)
		var rg := rank_glow(i)
		if rg > 0.0:   # M50.7: the rank-up burst and its tag
			draw_rect(r.grow(3.0), Color(Palette.color(&"card_rare"), rg), false, 3.0)
			var tag := rank_tag(i)
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0
			var tr := Rect2(Vector2(r.get_center().x - tw * 0.5, r.position.y - 22.0), Vector2(tw, 18.0))
			draw_rect(tr, Color(Palette.color(&"card_rare"), maxf(rg, 0.6)))
			draw_string(font, tr.position + Vector2(5, 14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.color(&"shadow"))
		if _glitch_out > 0.0 and not SaveGame.reduce_flashing():
			var k := _glitch_out / GLITCH_OUT
			draw_rect(Rect2(r.position + Vector2(6.0 * k, 10.0), Vector2(r.size.x, 6.0)), Color(Palette.color(&"danger"), 0.5 * k))
	if not _misfuse:
		_draw_link(view, font)
	var m := meter_rect(view)
	m.position -= position
	draw_string(font, m.position + Vector2(0, 14), meter_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
	if waiting_count() > 0:   # M50.6: the stack, over the meter (M50.7: larger, pulsing once per pack)
		var sg := stack_glow()
		var big := not Skins.is_on(&"ui_panel")
		draw_string(font, m.position + Vector2(0, -30 if big else -24), stack_text(), HORIZONTAL_ALIGNMENT_LEFT, -1,
				20 if big else 16, Color(LIT, sg))
		draw_string(font, m.position + Vector2(0, -8 if big else -6), stack_hint(), HORIZONTAL_ALIGNMENT_LEFT, -1,
				19 if big else 14, Color(LIT, sg))
	var bar_at := Rect2(m.position + Vector2(0, m.size.y - BAR.y), BAR)
	draw_rect(bar_at, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(bar_at.position, Vector2(BAR.x * clampf(bar(), 0.0, 1.0), BAR.y)), BAR_FILL)


## M50.1a: the deep curve's rank badge (top right) and mechanic dots with their ticks.
func _draw_deep(i: int, w: Weapon, r: Rect2, pr: Rect2, ink: Color, font: Font, a: float) -> void:
	var badge := Rect2(r.position + Vector2(CARD.x - 25, 5), Vector2(20, 20))
	draw_rect(badge, Color(ink, 0.25 * a))
	draw_rect(badge, ink, false, 1.5)
	var digits := str(w.rank)
	var fs := 13 if digits.length() <= 1 else (11 if digits.length() == 2 else 8)
	draw_string(font, badge.position + Vector2(0, 15), digits, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, fs, ink)
	var lv := card_levels(i)
	var n := maxi(1, lv.size())
	for k in lv.size():
		var c := pr.position + Vector2(pr.size.x * (k + 0.5) / n, pr.size.y * 0.5 - 2.0)
		if lv[k] > 0:
			draw_circle(c, 3.5, ink)
		else:
			draw_arc(c, 3.5, 0.0, TAU, 12, ink, 1.2, true)
		var ticks := mini(maxi(0, lv[k] - 1), WeaponCurve.STEPS)
		for t in ticks:
			var x := c.x - 4.0 + t * 4.0
			draw_line(Vector2(x, c.y + 6.0), Vector2(x, c.y + 9.0), ink, 1.5)
		if lv[k] - 1 > WeaponCurve.STEPS:
			draw_string(font, Vector2(c.x + 6.0, c.y + 11.0), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ink)


## M50.1b: the link on the seam (hidden: nothing; dim: an outline and a "4"; lit: filled).
func _draw_link(view: Vector2, font: Font) -> void:
	var state := link_state()
	if state <= 0:
		return
	var r := link_rect(view)
	r.position -= position
	var c := r.get_center()
	if state == 1:
		draw_circle(c, 7.0, Color(DIM, 0.35))
		draw_arc(c, 7.0, 0.0, TAU, 16, DIM, 1.5, true)
		draw_string(font, c + Vector2(-4, 4), "4", HORIZONTAL_ALIGNMENT_CENTER, 8, 10, DIM)
		return
	var g := link_glow()
	draw_circle(c, 9.0, Color(LIT, 0.35 * g))
	draw_circle(c, 6.0, Color(LIT, g))
	draw_line(c - Vector2(9, 0), c + Vector2(9, 0), Color(LIT, g), 2.0, true)


## M50.1b: a fused card: a second-tone frame on its lower-right half and its parents' titles.
func _draw_fused(w: Weapon, r: Rect2, ink: Color, font: Font, a: float) -> void:
	var tone := Color(Palette.color(&"card_rare"), a)
	draw_polyline(PackedVector2Array([r.position + Vector2(r.size.x, 2), r.end,
			r.position + Vector2(2, r.size.y)]), tone, 3.0, true)
	var names: Array[String] = []
	for p in w.def.parents:
		var pd := WeaponDB.get_weapon(p)
		names.append(pd.title if pd != null else String(p))
	var sub := " + ".join(names)
	var fs := 9
	while fs > 6 and font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > CARD.x - 6:
		fs -= 1
	draw_string(font, r.position + Vector2(3, 66), sub, HORIZONTAL_ALIGNMENT_CENTER, CARD.x - 6, fs, Color(ink, 0.8))


## M50.1b: the misfuse: both cards as one wobbling card between their slots, both glyphs
## overlapped, a glitch frame, "Pistgun?".
func _draw_misfuse(view: Vector2, font: Font) -> void:
	var r0 := card_rect(0, view)
	var r := Rect2(r0.position + Vector2((CARD.x + GAP) * 0.5, -RAISE), CARD)
	r.position -= position
	var centre := r.get_center()
	draw_set_transform(centre, deg_to_rad(wobble()), Vector2.ONE)
	var box := Rect2(-CARD * 0.5, CARD)
	var sb := StyleBoxFlat.new()
	sb.bg_color = FACE
	sb.border_color = LIT
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	draw_style_box(sb, box)
	if not SaveGame.reduce_flashing():
		var k := int(_clock * 12.0) % 3
		draw_rect(Rect2(box.position + Vector2(-3 + k * 2, 12 + k * 9), Vector2(box.size.x + 6, 4)), Color(Palette.color(&"danger"), 0.6))
		draw_rect(Rect2(box.position + Vector2(2 - k, 60 - k * 7), Vector2(box.size.x - 4, 3)), Color(Palette.color(&"player_shot"), 0.6))
	var title := misfuse_title()
	var fs := 13
	while fs > 8 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > CARD.x - 8:
		fs -= 1
	draw_string(font, box.position + Vector2(4, 40), title, HORIZONTAL_ALIGNMENT_CENTER, CARD.x - 8, fs, LIT)
	WeaponGlyph.draw(self, _slots()[0].def.icon, Vector2(-5, 22), 26.0, Color(LIT, 0.85))
	WeaponGlyph.draw(self, _slots()[1].def.icon, Vector2(5, 26), 26.0, Color(Palette.color(&"danger"), 0.85))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## M48a: a card's pixel panel tint: white (equipped) or UI_DIM, faded in by `a`, brightened

## by the join flash (`flash`, join_flash(): 0 under reduce flashing) as tier 0's fill is.
static func panel_modulate(lit: bool, a: float, flash: float) -> Color:
	var base := Color.WHITE if lit else Palette.UI_DIM
	return Color(base * (1.0 + flash), a)


## M48a: this widget's own copy of the look's UI panel (it sets the copy's modulate per
## card); null with no look.
func _skin_panel(lit: bool) -> StyleBoxTexture:
	if not Skins.is_on(&"ui_panel") or Skins.current.ui_panel(lit) == null:
		return null
	if _panel_version != Skins.version:
		_panel_version = Skins.version
		_panels.clear()
	if not _panels.has(lit):
		_panels[lit] = Skins.current.ui_panel(lit).duplicate()
	return _panels[lit]


## "●●○": rank filled of Loadout.MAX_RANK.
static func pips(rank: int) -> String:
	return "●".repeat(clampi(rank, 0, Loadout.MAX_RANK)) + "○".repeat(maxi(0, Loadout.MAX_RANK - rank))

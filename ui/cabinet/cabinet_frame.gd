class_name CabinetFrame
extends RailFrame
## M48.6a: the cabinet, the Pixel look's UI (PLAN 0.9.2; the owner-approved pixel mockup). It
## takes the version rail's place whenever the look's `ui` group is on and no stage card is up
## (RailFrame.wanted: S9's `skin ui` reveal, or --look=pixel / F10): one arcade cabinet holds
## the game, with a marquee over the screen (stage, session and title on the left, the path's
## name in the centre, the version plate on the right), the screen's bezel and CRT glass, and
## a deck under it; the dev-chat stands beside it. No bulbs, no game name.
##
## M48.6a is the frame only, and the game stays fully playable in it: the rail's own pieces
## live on inside (RailFrame's modules, chat, reply box and body, which this class inherits
## and lays out through CabinetLayout): the HUD modules dock in the deck, the AI's body sits in
## the deck's camera box, the chat log and the reply box fill the chat column. They are
## restyled one by one in M48.6b-f. The rail's version track is gone: the marquee's plate
## shows the version.
##
## Drawn from CabinetArt (the mockup's frames kit, grid for grid) on one pixel grid: 3 screen
## px per art px at 1600x900, a whole number at every window (CabinetLayout.scale_for).
## Presentation only: it reads the game through RailState and never writes it, draws no RNG,
## reads no Tuning and no rules. Nothing here moves by itself but the REC dot's blink, steady
## under reduce flashing (RailFrame.blink).

## The CRT glass over the game view: scanlines, the glare streak, the dithered corners. A
## child of the host right over the view (the frame itself sits under the game).
var glass: Control


func _exit_tree() -> void:
	if glass != null and is_instance_valid(glass):
		glass.queue_free()


func set_on(want: bool) -> void:
	super(want)
	if on:
		_ensure_glass()
	if glass != null and is_instance_valid(glass):
		glass.visible = on
		glass.queue_redraw()


func _ensure_glass() -> void:
	if glass != null and is_instance_valid(glass):
		return
	glass = Control.new()
	glass.name = "CabinetGlass"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.process_mode = Node.PROCESS_MODE_ALWAYS
	glass.draw.connect(_draw_glass)
	host.add_child(glass)
	var v: Node = host.get(&"view")
	if v != null:
		host.move_child(glass, v.get_index() + 1)   # over the game, under the glitch and the fade
	_place_glass()


func _place_glass() -> void:
	if glass == null or not is_instance_valid(glass) or not layout.has("view"):
		return
	var v: Rect2 = layout.view
	glass.position = v.position
	glass.size = v.size
	glass.queue_redraw()


func layout_for(window: Vector2) -> Dictionary:
	return CabinetLayout.layout_for(window)


func apply_layout(l: Dictionary) -> void:
	super(l)
	reply.clip_contents = true   # the narrower column: a long question never runs off the box
	_place_glass()


## One art pixel in screen px.
func art() -> float:
	return float(layout.get("art", 3.0))


# --- The marquee's texts ------------------------------------------------------------------------

## The marquee's left text: ["STAGE 2 · ", "S9 · FRESH PAINT"] (the dim part, then the lit one;
## a level in parts adds " · PART 2/3" and " · DOOR OPEN"). Empty outside a campaign session.
func marquee_session() -> Array[String]:
	var out: Array[String] = ["", ""]
	if int(snap.get("stage", 0)) <= 0:
		return out
	out[0] = "STAGE %d · " % int(snap.stage)
	var s := RunState.session
	var lit := String(snap.get("title", "")).to_upper()
	if s != null and CampaignDB.index_of(s.id) >= 0:
		lit = "S%d · %s" % [CampaignDB.index_of(s.id), lit]
	var level: Dictionary = snap.get("parts", {})
	if int(level.get("of", 0)) > 1:
		lit += " · PART %d/%d" % [int(level.part), int(level.of)]
		if level.get("door", false):
			lit += " · DOOR OPEN"
	out[1] = lit
	return out


## The marquee's centre: the path's title as the player reads it (ARCADE), "" with no path.
func marquee_path() -> String:
	var path: Dictionary = snap.get("path", {})
	if path.get("id", &"") == &"":
		return ""
	return String(path.get("title", path.id)).to_upper()


## The version plate's text.
func marquee_version() -> String:
	return String(snap.get("version", SaveGame.version().label()))


# --- Drawing ------------------------------------------------------------------------------------

## The static cabinet: the backdrop, the body with its grain, the side trims, the rivets, the
## screen's bezel, the deck and its camera box, the chat column's paper cells.
func _draw_chrome(ci: Control) -> void:
	if not layout.get("cabinet", false):
		return
	var a := art()
	ci.draw_texture_rect(CabinetArt.backdrop(a), Rect2(Vector2.ZERO, ci.size), true)
	var cab: Rect2 = layout.frame
	CabinetArt.draw9_rect(ci, &"cab", cab, a)
	# The grain over the body's fill, inside its bevel.
	var grain := Rect2(cab.position + Vector2(2, 5) * a, cab.size - Vector2(4, 8) * a)
	ci.draw_texture_rect(CabinetArt.orn_tile(&"cab_grain", a), grain, true)
	# The gold side trims, 3 art px outside each edge (the mockup's), top and bottom inset.
	var trim_h := roundi(cab.size.y / a) - 28
	for tx: float in [cab.position.x - 3 * a, cab.end.x - 3 * a]:
		CabinetArt.draw9(ci, &"trim", Vector2(tx, cab.position.y + 18 * a), 6, trim_h, a)
	var rv := Vector2(CabinetArt.orn_size(&"rivet")) * a
	for corner: Vector2 in [cab.position + Vector2(4, 3) * a, Vector2(cab.end.x - 4 * a - rv.x, cab.position.y + 3 * a),
			Vector2(cab.position.x + 4 * a, cab.end.y - 3 * a - rv.y), cab.end - Vector2(4, 3) * a - rv]:
		CabinetArt.orn(ci, &"rivet", corner, a)
	# The screen's bezel: 5 art px around the view, the glass itself behind the game.
	var view: Rect2 = layout.view
	ci.draw_rect(view, CabinetArt.c(&"base"))
	CabinetArt.draw9_rect(ci, &"scr", view.grow(5 * a), a)
	# The deck and the camera box.
	CabinetArt.draw9_rect(ci, &"deck", layout.deck, a)
	var hb: Rect2 = layout.host
	CabinetArt.draw9_rect(ci, &"host", hb, a)
	var floor_w := CabinetArt.orn_size(&"host_floor").x
	CabinetArt.orn(ci, &"host_floor", hb.position + Vector2(floorf((hb.size.x / a - floor_w) * 0.5), 28) * a, a)
	CabinetArt.orn(ci, &"bracket_tl", hb.position + Vector2(3, 3) * a, a)
	CabinetArt.orn(ci, &"bracket_tr", Vector2(hb.end.x - 9 * a, hb.position.y + 3 * a), a)
	# The chat column: the rail's paper log and reply box (M48.6c restyles them).
	var p := px()
	for r: Rect2 in [layout.log, layout.reply]:
		ci.draw_rect(r.grow(p), RailArt.c(&"ink"))
		RailArt.bevel(ci, r, RailArt.c(&"paper"), RailArt.c(&"paper_hi"), RailArt.c(&"paper_lo"), p)
	var lg: Rect2 = layout.log
	var head := Rect2(lg.position, Vector2(lg.size.x, roundf(RailLayout.HEADER_H * s())))
	RailArt.bevel(ci, head, RailArt.c(&"cell"), RailArt.c(&"hi"), RailArt.c(&"cell"), p)
	ci.draw_rect(Rect2(Vector2(head.position.x, head.end.y - p), Vector2(head.size.x, p)), RailArt.c(&"ink"))


## The live layer (the rail's track layer, redrawn every frame): the marquee and its texts,
## the camera's REC dot, the chat's header.
func _draw_track(ci: Control) -> void:
	if not layout.get("cabinet", false):
		return
	var a := art()
	var m: Rect2 = layout.marquee
	CabinetArt.draw9_rect(ci, &"marq", m, a)
	CabinetArt.orn(ci, &"marq_cap_l", m.position - Vector2(2 * a, 0), a)
	CabinetArt.orn(ci, &"marq_cap_r", Vector2(m.end.x - 3 * a, m.position.y), a)
	var sc := s()
	var small := CabinetLayout.text_px(2, sc)
	var font := UiTheme.pixel_font()
	var small_y := roundf(m.position.y + (m.size.y - font.get_height(small)) * 0.5)
	# Right: the version plate (gold, ink text).
	var ver := marquee_version()
	var plate_w := maxi(36, ceili((text_w(ver, small) + 6 * a) / a))
	var plate := Rect2(Vector2(m.end.x - (4 + plate_w) * a, m.position.y + a), Vector2(plate_w, 12) * a)
	CabinetArt.draw9_rect(ci, &"plate_gold", plate, a)
	text(ci, Vector2(plate.position.x, small_y), ver, small, CabinetArt.c(&"ink"), false, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	# Left: stage (dim), then the session's number and title (mint).
	var ses := marquee_session()
	var x := m.position.x + 9 * a
	var left_end := x
	if ses[1] != "":
		text(ci, Vector2(x, small_y), ses[0], small, RailArt.c(&"dim"))
		x += text_w(ses[0], small)
		text(ci, Vector2(x, small_y), ses[1], small, CabinetArt.c(&"mint"))
		left_end = x + text_w(ses[1], small)
	# Centre: ">> ARCADE <<", gold on a coral drop, when a path is set and the room is there.
	var cap := marquee_path()
	if cap != "":
		var big := CabinetLayout.text_px(3, sc)
		var chev := Vector2(CabinetArt.orn_size(&"marq_chev_r")) * a
		var cw := text_w(cap, big, true)
		var total := cw + 2 * (chev.x + 3 * a)
		var cx := roundf(m.get_center().x - total * 0.5)
		if cx < left_end + 4 * a:   # a long title: after it, never over it
			cx = left_end + 4 * a
		if cx + total <= plate.position.x - 2 * a:
			var chev_y := roundf(m.position.y + (m.size.y - chev.y) * 0.5)
			CabinetArt.orn(ci, &"marq_chev_r", Vector2(cx, chev_y), a)
			var ty := roundf(m.position.y + (m.size.y - font.get_height(big)) * 0.5)
			var tx := cx + chev.x + 3 * a
			text(ci, Vector2(tx + a, ty + a), cap, big, RailArt.c(&"who"), true)
			text(ci, Vector2(tx, ty), cap, big, CabinetArt.c(&"gold"), true)
			CabinetArt.orn(ci, &"marq_chev_l", Vector2(tx + cw + 3 * a, chev_y), a)
	# The camera's REC: the dot blinks (steady under reduce flashing), the letters stay.
	var hb: Rect2 = layout.host
	CabinetArt.orn(ci, &"rec_dot" if blink(1.0) else &"rec_off", hb.position + Vector2(3, 28) * a, a)
	CabinetArt.draw_digits(ci, "REC", Vector2(hb.end.x - 14 * a, hb.position.y + 28 * a), a, CabinetArt.c(&"pink_hi"))
	chat.draw_header(ci)


## The CRT glass over the game: scanlines (every third art row), the glare streak top-left,
## the dithered vignette in each corner. Static: nothing here moves.
func _draw_glass() -> void:
	if not on or not layout.get("cabinet", false):
		return
	var a := art()
	var size := glass.size
	glass.draw_texture_rect(CabinetArt.orn_tile(&"crt_scan", a), Rect2(Vector2.ZERO, size), true)
	CabinetArt.orn(glass, &"scr_glare", Vector2(2, 2) * a, a)
	var v: Dictionary = CabinetArt.ORN[&"vignette"]
	var vs := Vector2(CabinetArt.grid_size(v.grid)) * a
	CabinetArt.draw(glass, v.grid, v.ramp, Vector2.ZERO, a)
	CabinetArt.draw(glass, CabinetArt.mirror(v.grid), v.ramp, Vector2(size.x - vs.x, 0), a)
	CabinetArt.draw(glass, CabinetArt.flip_v(v.grid), v.ramp, Vector2(0, size.y - vs.y), a)
	CabinetArt.draw(glass, CabinetArt.flip_v(CabinetArt.mirror(v.grid)), v.ramp, size - vs, a)

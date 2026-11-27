class_name RailFrame
extends Control
## M48.5a: the version rail, the Pixel look's UI style (owner pick 3A, Pixel_A / Pixel_A_hud
## mockups). One plum machine holds the game, the chat and the HUD: a rail of version ticks
## runs from v0.1 under the game and on to the chat, every HUD module hangs from the version
## that shipped it (RailModel), and at the current version the rail turns up into the chat as
## its message spine. Game, rail, modules and chat share 4 px plum outlines; no game name,
## the version only.
##
## When: the look's `ui` group is on (S9's `skin ui` reveal at 55 s, or --look=pixel / F10)
## and no stage card is up (GameHost.chapter). Otherwise the raw terminal, the HUD corner and
## the corner mascot stay exactly as before. sync() is the host's only call: it builds the
## frame once, binds the live game, dresses the terminal (RailChat), docks the HUD corner and
## the corner body, and puts all of it back when the rail goes off.
##
## Presentation only: it reads the game (RailState) and never writes it, draws no RNG and
## uses real time (Time.get_ticks_usec) for its blinks, steady under reduce flashing.

const Modules := preload("res://ui/rail/rail_modules.gd")
const Chat := preload("res://ui/rail/rail_chat.gd")
const Reply := preload("res://ui/rail/rail_reply.gd")
const Blob := preload("res://ui/rail/rail_blob.gd")
const FADE_S := 0.25

var host: Node                 ## the GameHost
var game: Node                 ## the bound Main (null between sessions)
var on := false
var layout := {}
var snap := {}                 ## the last RailState.read()
var peak := {}                 ## the dash fill's peak (RailState)
var chrome: Control
var track: Control
var modules: Control
var chat: RefCounted           ## rail_chat.gd: the terminal's dresser
var chat_layer: Control        ## the chat's drawing, behind the terminal's rows
var reply: Control
var blob: Control
var hotfix := {}               ## {module, version, n} of the last live edit naming a module
var hotfixes := 0              ## live edits landed this session
var _rule_book: Node
var _snap_hash := 0
var _start_usec := 0
var _fade: Tween


## True when the host should show the rail now.
static func wanted(p_host: Node) -> bool:
	return Skins.is_on(&"ui_panel") and not bool(p_host.get(&"chapter"))


## The host's one call (skin change, attach, chapter in / out): returns the frame (built on
## first need) with its state matching wanted().
static func sync(p_host: Node, frame: RailFrame) -> RailFrame:
	var want := wanted(p_host)
	if frame == null:
		if not want:
			return null
		frame = RailFrame.new()
		frame.host = p_host
		frame.name = "Rail"
		p_host.add_child(frame)
		# Over Back and the dev desktop (M48.5b: hidden under the rail), under the game, the
		# glitch, the fade and the terminal.
		var desk: Node = p_host.get(&"desktop")
		p_host.move_child(frame, desk.get_index() + 1 if desk != null else 1)
	p_host.set(&"rail", frame)   # before set_on: its relayout reads host.rail
	frame.set_on(want)
	return frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_usec = Time.get_ticks_usec()
	chrome = _layer("Chrome", _draw_chrome)
	track = _layer("Track", _draw_track)
	modules = Modules.new()
	modules.name = "Modules"
	modules.frame = self
	add_child(modules)
	chat = Chat.new(self)
	chat_layer = _layer("ChatLayer", chat.draw_layer)
	reply = Reply.new()
	reply.name = "Reply"
	reply.frame = self
	add_child(reply)
	visible = false


func _exit_tree() -> void:
	if blob != null and is_instance_valid(blob):
		blob.queue_free()
	_unhook_rules()


func _layer(n: String, draw: Callable) -> Control:
	var c := Control.new()
	c.name = n
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(draw.bind(c))
	add_child(c)
	return c


## On: binds the game, dresses the terminal, docks the HUD corner and the corner body, sets
## the window's base (live and windowed only) and lays out. Off: all of it back.
func set_on(want: bool) -> void:
	var t: TerminalPanel = host.get(&"terminal")
	if want == on:
		if on and host.get(&"game") != game:
			bind(host.get(&"game"))
		return
	on = want
	if on:
		_ensure_blob()
		bind(host.get(&"game"))
	else:
		_dock(false)
		t.set_dresser(null)
		visible = false
		if blob != null:
			blob.visible = false
	host.call(&"rail_window", on)
	host.call(&"relayout")
	if on:
		t.set_dresser(chat)
		_show_fade()


func _show_fade() -> void:
	visible = true
	if blob != null:
		blob.visible = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if SaveGame.reduce_flashing() or not is_inside_tree():
		modulate.a = 1.0
		return
	modulate.a = 0.0   # the reveal: a short crossfade, never a flash
	_fade = create_tween().set_ignore_time_scale(true)
	_fade.tween_property(self, ^"modulate:a", 1.0, FADE_S)
	if blob != null:
		blob.modulate.a = 0.0
		_fade.parallel().tween_property(blob, ^"modulate:a", 1.0, FADE_S)


func _ensure_blob() -> void:
	if blob != null and is_instance_valid(blob):
		return
	blob = Blob.new()
	blob.name = "RailBlob"
	blob.frame = self
	host.add_child(blob)   # over the terminal: it sits on the log's bottom edge


## The live game (the host's _attach); null-safe for the v6 loop and tests.
func bind(g: Node) -> void:
	if g == game and g != null:
		_dock(on)
		return
	unbind()
	game = g
	hotfix = {}
	hotfixes = 0
	peak = {}
	if game == null:
		return
	_dock(on)
	_hook_rules()
	refresh()


## Before the host frees the old session: drop every reference to its nodes.
func unbind() -> void:
	if game != null and is_instance_valid(game):
		_dock(false)
	_unhook_rules()
	game = null
	snap = {}


func _dock(docked: bool) -> void:
	if game == null or not is_instance_valid(game):
		return
	var hud: Node = game.get(&"hud")
	if hud != null and hud.has_method(&"set_docked"):
		hud.call(&"set_docked", docked)
	var mascot: Node = game.get(&"mascot")
	if mascot != null and mascot.has_method(&"set_docked"):
		mascot.call(&"set_docked", docked)


func _hook_rules() -> void:
	var rb: Node = game.get(&"rule_book")
	if rb != null and rb.has_signal(&"edit_landed"):
		_rule_book = rb
		rb.connect(&"edit_landed", _on_edit_landed)


func _unhook_rules() -> void:
	if _rule_book != null and is_instance_valid(_rule_book) and _rule_book.is_connected(&"edit_landed", _on_edit_landed):
		_rule_book.disconnect(&"edit_landed", _on_edit_landed)
	_rule_book = null


## A live rule edit landed (the terminal prints its `$ <cmd>` row the same frame): a hotfix.
## One that names a module tags it (the hotfix chip, the solder trace back to its tick).
func _on_edit_landed(edit: RuleEdit) -> void:
	if _rule_book == null or not bool(_rule_book.get(&"last_warned")) or _rule_book.get(&"last_by") == &"event":
		return
	hotfixes += 1
	var text := Main.edit_row_text(edit)
	var label := hotfix_label(snap.get("version", SaveGame.version().label()), hotfixes)
	chat.call(&"mark_hotfix", "$ " + text, label)
	var m := module_named(text + " " + edit.title)
	if m != &"":
		hotfix = {"module": m, "version": label, "n": hotfixes}


## M50.7: a live nerf (main's _on_nerf_row): a hotfix like a rule edit's, its slip carrying the
## patch note ("Balance: Minigun ..."), tagged on the path module.
func mark_nerf(prefix: String, note: String) -> void:
	hotfixes += 1
	var label := hotfix_label(snap.get("version", SaveGame.version().label()), hotfixes)
	chat.call(&"mark_hotfix", prefix, label, note)
	hotfix = {"module": &"path", "version": label, "n": hotfixes}


## "v0.8.1+2": the session's version and its n-th live hotfix.
static func hotfix_label(version: String, n: int) -> String:
	return "%s+%d" % [version, n]


## The module a hotfix's text names (&"" none).
static func module_named(text: String) -> StringName:
	var low := text.to_lower()
	for pair: Array in [[&"dash", ["dash", "grapple", "teleport", "hook"]], [&"hp", ["health", "hp ", "heal"]],
			[&"kills", ["kill"]], [&"path", ["card", "hand", "ammo", "level", "weapon", "gem"]], [&"pack", ["pack"]]]:
		for w: String in pair[1]:
			if low.contains(w):
				return pair[0]
	return &""


func layout_for(window: Vector2) -> Dictionary:
	return RailLayout.layout_for(window)


## The host's relayout() hands over the rail's layout (the game rect is already placed).
func apply_layout(l: Dictionary) -> void:
	layout = l
	if not l.get("rail", false):
		return
	reply.position = l.reply.position
	reply.size = l.reply.size
	reply.call(&"layout_input")
	var lg: Rect2 = l.log
	var head := roundf(RailLayout.HEADER_H * float(l.s))
	chat_layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chat_layer.position = lg.position + Vector2(0, head)
	chat_layer.size = Vector2(lg.size.x, lg.size.y - head - px())
	chat_layer.clip_contents = true
	if blob != null:
		blob.call(&"place", l.blob)
	var t: TerminalPanel = host.get(&"terminal")
	if t != null and t.dresser == chat:
		t.call(&"_style_back")   # the insets follow the scale
	chrome.queue_redraw()
	track.queue_redraw()
	modules.queue_redraw()


## Reads the game now and redraws what changed (tests call it directly).
func refresh() -> void:
	snap = RailState.read(game, peak) if game != null and is_instance_valid(game) else RailState.read(null, peak)
	var h := hash(snap) ^ hash(hotfix)
	if h != _snap_hash:
		_snap_hash = h
		modules.queue_redraw()


func _process(_delta: float) -> void:
	if not on:
		return
	if game != null and not is_instance_valid(game):
		game = null
	refresh()
	chat.step()
	track.queue_redraw()
	chat_layer.queue_redraw()
	if bool(snap.get("dash", {}).get("on", false)) and not bool(snap.dash.ready):
		modules.queue_redraw()


## A blink at `hz` (1 = steady under reduce flashing).
func blink(hz := 1.0) -> bool:
	if SaveGame.reduce_flashing():
		return true
	return int((Time.get_ticks_usec() - _start_usec) * hz / 500000.0) % 2 == 0


# --- Helpers shared by the rail's drawing -----------------------------------------------------

func s() -> float:
	return float(layout.get("s", 1.0))


func px() -> float:
	return float(layout.get("px", 2.0))


## A design point (the mockup's px) in window px.
func at(d: Vector2) -> Vector2:
	return (Vector2(layout.get("origin", Vector2.ZERO)) + d * s()).round()


## A design rect in window px.
func rect(d: Rect2) -> Rect2:
	return RailLayout.map(d, s(), layout.get("origin", Vector2.ZERO))


## Text with its top-left at `top_left` (window px), at design size `size`.
static func text(ci: CanvasItem, top_left: Vector2, t: String, size: int, color: Color, bold := false,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := UiTheme.pixel_font(bold)
	# M48.5b: the font draws 0-9 from the rail's own pixel digits (UiTheme.pixel_digits).
	ci.draw_string(f, Vector2(top_left.x, top_left.y + f.get_ascent(size)), t, align, width, size, color)


static func text_w(t: String, size: int, bold := false) -> float:
	return UiTheme.pixel_font(bold).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The largest size <= `size` at which `t` fits `width`.
static func fit(t: String, size: int, width: float, bold := false, least := 8) -> int:
	var fs := size
	while fs > least and text_w(t, fs, bold) > width:
		fs -= 1
	return fs


# --- Chrome: the one plum machine ---------------------------------------------------------------

static var _checker: ImageTexture


## The 8 px plum checker (two tones), made in code once.
static func checker() -> ImageTexture:
	if _checker == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(RailArt.c(&"base"))
		for y in 8:
			for x in 8:
				if (x < 4) == (y < 4):
					img.set_pixel(x, y, RailArt.c(&"check"))
		_checker = ImageTexture.create_from_image(img)
	return _checker


func _draw_chrome(ci: Control) -> void:
	if not layout.get("rail", false):
		return
	var p := px()
	ci.draw_texture_rect(checker(), Rect2(Vector2.ZERO, ci.size), true)
	var shape: Rect2 = layout.shape
	ci.draw_rect(Rect2(shape.position, shape.size + Vector2(0, 3 * p)), RailArt.c(&"ink"))   # the lip
	# The game bezel.
	RailArt.bevel(ci, layout.bezel, RailArt.c(&"sunk"), RailArt.c(&"cell"), RailArt.c(&"ink"), p)
	var g: Rect2 = layout.game
	ci.draw_rect(g.grow(2 * p), RailArt.c(&"hi"))
	ci.draw_rect(g.grow(p), RailArt.c(&"ink"))
	# The chat log and the reply box: paper cells.
	for r: Rect2 in [layout.log, layout.reply]:
		RailArt.bevel(ci, r, RailArt.c(&"paper"), RailArt.c(&"paper_hi"), RailArt.c(&"paper_lo"), p)
	var lg: Rect2 = layout.log
	var head := Rect2(lg.position, Vector2(lg.size.x, roundf(RailLayout.HEADER_H * s())))
	RailArt.bevel(ci, head, RailArt.c(&"cell"), RailArt.c(&"hi"), RailArt.c(&"cell"), p)
	ci.draw_rect(Rect2(Vector2(head.position.x, head.end.y - p), Vector2(head.size.x, p)), RailArt.c(&"ink"))


# --- The track: the version rail ----------------------------------------------------------------

## The rail's ticks now: [{minor, label, x, module, dim}], plus the current tick's x. Module
## ticks sit at their module's hanger (its cell's centre); the others between their neighbours.
func ticks() -> Dictionary:
	var current := SaveGame.version()
	var cur_x := float(layout.get("spine_x", 0.0))
	var anchors := {}   # minor -> {x, module}
	var shown: Array = modules.call(&"shown_modules")
	for m: StringName in shown:
		var v := RailModel.ship_version(m)
		if v.major != current.major or v.minor > current.minor or anchors.has(v.minor):
			continue
		var cell: Rect2 = modules.call(&"cell_rect", m)
		anchors[v.minor] = {"x": roundf(cell.get_center().x), "module": m}
	var list: Array[Dictionary] = []
	for t in RailModel.minors(current):
		var a: Variant = anchors.get(t.minor)
		list.append({"minor": t.minor, "label": t.label, "x": a.x if a != null else -1.0,
				"module": a.module if a != null else &"", "dim": a == null})
	# Interpolate the free ticks between the anchors (the rail's start, the modules, the current tick).
	var track_r: Rect2 = layout.track
	var known: Array = [[0, track_r.position.x]]
	for t in list:
		if t.x >= 0.0:
			known.append([t.minor, t.x])
	known.append([current.minor + 1, cur_x])
	for t in list:
		if t.x >= 0.0:
			continue
		var lo: Array = known[0]
		var hi: Array = known[known.size() - 1]
		for k: Array in known:
			if k[0] < t.minor:
				lo = k
			elif k[0] > t.minor:
				hi = k
				break
		var f := float(t.minor - lo[0]) / float(maxi(1, hi[0] - lo[0]))
		t.x = roundf(lerpf(lo[1], hi[1], f))
	return {"ticks": list, "current_x": cur_x, "current": current.label()}


func _draw_track(ci: Control) -> void:
	if not layout.get("rail", false):
		return
	var p := px()
	var sc := s()
	var tr: Rect2 = layout.track
	RailArt.bevel(ci, tr, RailArt.c(&"sunk"), RailArt.c(&"base"), RailArt.c(&"ink"), p)
	# The ruler marks above and below the line.
	var step := 16.0 * sc
	var x := tr.position.x
	while x < tr.end.x:
		for y in [tr.position.y + 2 * sc, tr.position.y + 24 * sc]:
			ci.draw_rect(Rect2(Vector2(roundf(x), roundf(y)), Vector2(p, roundf(6 * sc))), RailArt.c(&"hi"))
		x += step
	var info := ticks()
	var cur_x: float = info.current_x
	var line_y := roundf(tr.position.y + 14 * sc)
	var lw := roundf(4 * sc)
	# The shipped track (gold) up to the current tick; the future track (dashed) after its label.
	ci.draw_rect(Rect2(Vector2(tr.position.x, line_y + lw), Vector2(cur_x - tr.position.x, p)), RailArt.c(&"gold_lo"))
	ci.draw_rect(Rect2(Vector2(tr.position.x, line_y), Vector2(cur_x - tr.position.x, lw)), RailArt.c(&"gold"))
	var cur_label: String = info.current
	var lab_x := cur_x + 18 * sc
	var lab_w := text_w(cur_label, RailLayout.text_px(16, sc), true) + 8 * sc
	var next_x := lab_x + lab_w + 12 * sc
	var dash_x := next_x + text_w("next ?", RailLayout.text_px(12, sc)) + 16 * sc
	while dash_x < tr.end.x - 2 * p:
		ci.draw_rect(Rect2(Vector2(roundf(dash_x), line_y), Vector2(minf(8 * sc, tr.end.x - 2 * p - dash_x), lw)), RailArt.c(&"hi"))
		dash_x += 16 * sc
	# The solder trace: a hotfix runs back from the current tick to its module's tick.
	if not hotfix.is_empty():
		var hx := _module_x(info, hotfix.module)
		if hx >= 0.0:
			var sx := hx
			while sx < cur_x:
				ci.draw_rect(Rect2(Vector2(roundf(sx), roundf(tr.position.y + 26 * sc)), Vector2(roundf(4 * sc), p)), RailArt.c(&"gold_hi"))
				sx += 8 * sc
	# The ticks and their labels; the hangers down to the modules.
	var ticks_list: Array = info.ticks
	for i in ticks_list.size():
		var t: Dictionary = ticks_list[i]
		var tx: float = t.x
		var next_tick: float = ticks_list[i + 1].x if i + 1 < ticks_list.size() else cur_x
		if t.dim:
			var d := roundf(8 * sc)
			RailArt.block(ci, Rect2(Vector2(tx - d * 0.5, line_y - 2 * sc), Vector2(d, d)), RailArt.c(&"mute"), p)
			var fs := RailLayout.text_px(12, sc)
			var w := text_w(t.label, fs) + 4 * sc
			if next_tick - tx - d > w + 10 * sc:
				ci.draw_rect(Rect2(Vector2(tx + d * 0.5 + 4 * sc, line_y - 2 * sc), Vector2(w, roundf(12 * sc))), RailArt.c(&"sunk"))
				text(ci, Vector2(tx + d * 0.5 + 6 * sc, line_y - 2 * sc), t.label, fs, RailArt.c(&"mute"))
			continue
		var hot: bool = not hotfix.is_empty() and hotfix.module == t.module
		var pc := roundf(12 * sc)
		var fill := RailArt.c(&"gold_hi") if hot and blink(1.0) else RailArt.c(&"gold")
		var pr := Rect2(Vector2(tx - pc * 0.5, line_y - 4 * sc), Vector2(pc, pc))
		RailArt.block(ci, pr, fill, p, p, RailArt.c(&"gold_lo"))
		var fs2 := RailLayout.text_px(16, sc)
		var w2 := text_w(t.label, fs2) + 8 * sc
		if next_tick - tx > w2 + pc:
			ci.draw_rect(Rect2(Vector2(tx + pc * 0.5 + 4 * sc, tr.position.y + 8 * sc), Vector2(w2, roundf(16 * sc))), RailArt.c(&"sunk"))
			text(ci, Vector2(tx + pc * 0.5 + 8 * sc, tr.position.y + 8 * sc), t.label, fs2,
					RailArt.c(&"gold") if hot else RailArt.c(&"text"))
		# The hanger: a 4 px stub from the tick into the module's tab.
		var stub := Rect2(Vector2(tx - 2 * sc, tr.position.y + 22 * sc), Vector2(roundf(4 * sc), roundf(18 * sc)))
		RailArt.block(ci, stub, RailArt.c(&"gold_hi") if hot else RailArt.c(&"gold"), p)
	# The current build: where the rail turns up into the chat (the spine joint above it).
	var lg: Rect2 = layout.log
	var joint := Rect2(Vector2(cur_x - 2 * sc, lg.end.y - 4 * sc), Vector2(roundf(4 * sc), tr.position.y + 12 * sc - lg.end.y + 4 * sc))
	ci.draw_rect(joint, RailArt.c(&"gold_lo"))
	var cs := roundf(16 * sc)
	var cr := Rect2(Vector2(cur_x - cs * 0.5, tr.position.y + 8 * sc), Vector2(cs, cs))
	ci.draw_rect(cr.grow(2 * p), RailArt.c(&"gold_hi") if blink(1.0) else RailArt.c(&"gold_lo"))
	RailArt.block(ci, cr, RailArt.c(&"gold"), p, roundf(3 * sc), RailArt.c(&"gold_lo"))
	ci.draw_rect(Rect2(Vector2(lab_x, tr.position.y + 8 * sc), Vector2(lab_w, roundf(16 * sc))), RailArt.c(&"sunk"))
	text(ci, Vector2(lab_x + 4 * sc, tr.position.y + 8 * sc), cur_label, RailLayout.text_px(16, sc), RailArt.c(&"gold"), true)
	text(ci, Vector2(next_x, tr.position.y + 9 * sc), "next ?", RailLayout.text_px(12, sc), RailArt.c(&"mute"))
	chat.draw_header(ci)


func _module_x(info: Dictionary, m: StringName) -> float:
	for t: Dictionary in info.ticks:
		if t.module == m:
			return t.x
	return -1.0


## The caption under the game: "stage 2 · fresh paint · arcade" (the version is on the rail).
## M50.7: the path's title as the player reads it (ARCADE), not its id (arsenal).
func caption() -> String:
	var parts: Array[String] = []
	if int(snap.get("stage", 0)) > 0:
		parts.append("stage %d" % int(snap.stage))
		parts.append(String(snap.title).to_lower())
	var path: Dictionary = snap.get("path", {})
	if path.get("id", &"") != &"":
		parts.append(String(path.get("title", path.id)).to_lower())
	# M50.3c: a level in parts names the part, and the door once it is open.
	var level: Dictionary = snap.get("parts", {})
	if int(level.get("of", 0)) > 1:
		parts.append("part %d/%d" % [int(level.part), int(level.of)])
		if level.get("door", false):
			parts.append("door open")
	return " · ".join(parts)

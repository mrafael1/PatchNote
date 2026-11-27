class_name TitleOdometer
extends Control
## M51b (title mockup v2, concept B, owner pick): the title's hero, a mechanical odometer that
## shows the game's version (v + three wheels: major, minor, patch) in the plum / paper / gold
## pixel style, 5x7 block digits, drawn in code. No game name.
##
## The boot: the wheels rewind to v0.0.0, then tick through every version the save shipped (the
## campaign's sessions in order, folded from v0.0.0 over SessionDef.bump, as RailModel folds
## them), naming the module each one shipped (the session's first patch note, else its title),
## and land on the save's version with a thunk and sparks. With reduce flashing there is no boot,
## no sparks and no spin: the wheels sit on the version and snap between targets.
##
## The menu row then picks a version: focus(kind) rolls the wheels to where a card leads
## (Continue: the patch wheel spins as "?", New game: back to v0.0.0 in red, Replay: the old
## build the chosen session started on, Options: a gear, Quit: a lock; both keep the version).
## Presentation only: it reads the campaign and the save's version and settings, never the run
## and no RNG. TitleScreen drives it (step) and reads where its wheels are (the mascot walks there).

signal landed   ## the boot roll's last tick (the mascot drops in)
signal booted   ## the boot is over (the focused card takes the wheels)

const CONTINUE := &"continue"
const NEW := &"new"
const REPLAY := &"replay"
const OPTIONS := &"options"
const QUIT := &"quit"
const KINDS: Array[StringName] = [CONTINUE, NEW, REPLAY, OPTIONS, QUIT]
const SPIN := -1   ## a target digit: the wheel spins as "?"

## The housing, in design px (the mockup's 1600 x 900 board at 0.8: a 1280 x 720 view).
const HOUSING := Vector2(732, 240)
const HOUSING_Y := 152.0
const EDGE := 4.0
const DROP := 11.0
const GLYPH_X := 56.0           ## the "v"
const WHEEL_X := 168.0          ## the major wheel's left edge in the housing
const WHEEL_Y := 28.0
const WHEEL := Vector2(136, 184)
const WHEEL_GAP := 50.0
const CELL := 18.0
const DIGIT_Y := 30.0           ## a digit's top in its window
const READ_Y := 410.0           ## the readout's first line
const READ_SIZE := 32
const READ2_Y := 456.0
const READ2_SIZE := 16
const HINT := "left / right choose · Enter ok · Esc back"
const HINT_SIZE := 14
const HINT_Y := 658.0
const SCRIM := 0.62             ## the dim under a sub menu

## The boot (s): the rewind, then one tick per shipped version, the landing's thunk and sparks.
const REWIND := 0.5
const TICK := 0.34
const TICKS_MAX := 3.0           ## all the ticks fit in this, however long the history grows
const JOLT := 0.12
const JOLT_PX := 5.0
const SPARKS := 16
const SPARK_TIME := 0.7
const HOLD := 1.4                ## the landed line's time before the focused card takes over
const SPIN_SPEED := 7.0          ## digits per second (Continue's "?")

## 5x7 block glyphs (the mockup's block font).
const GLYPHS := {
	"0": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
	"1": ["..X..", ".XX..", "..X..", "..X..", "..X..", "..X..", ".XXX."],
	"2": [".XXX.", "X...X", "....X", "...X.", "..X..", ".X...", "XXXXX"],
	"3": ["XXXX.", "....X", "....X", ".XXX.", "....X", "....X", "XXXX."],
	"4": ["...X.", "..XX.", ".X.X.", "X..X.", "XXXXX", "...X.", "...X."],
	"5": ["XXXXX", "X....", "XXXX.", "....X", "....X", "X...X", ".XXX."],
	"6": ["..XX.", ".X...", "X....", "XXXX.", "X...X", "X...X", ".XXX."],
	"7": ["XXXXX", "....X", "...X.", "..X..", ".X...", ".X...", ".X..."],
	"8": [".XXX.", "X...X", "X...X", ".XXX.", "X...X", "X...X", ".XXX."],
	"9": [".XXX.", "X...X", "X...X", ".XXXX", "....X", "...X.", ".XX.."],
	"v": [".....", ".....", "X...X", "X...X", "X...X", ".X.X.", "..X.."],
	".": [".", ".", ".", ".", ".", ".", "X"],
	"?": [".XXX.", "X...X", "....X", "...X.", "..X..", ".....", "..X.."],
}
const GEAR := ["...KK...", ".KKGGKK.", ".KGGGGK.", "KGGKKGGK", "KGGKKGGK", ".KGGGGK.", ".KKGGKK.", "...KK..."]
const LOCK := ["..KKKK..", ".K....K.", ".K....K.", "KKKKKKKK", "KGGGGGGK", "KGGKKGGK", "KGGKKGGK", "KGGGGGGK", "KKKKKKKK"]

## What each card reads under the odometer: [first line, second line]; {cur} {next} {old} {play}.
const READ := {
	CONTINUE: ["next: {next}", "play {play} to decide what ships"],
	NEW: ["roll back to v0.0.0", "your progress goes, your settings stay"],
	REPLAY: ["check out {old}", "session, path, seed · your save is not touched"],
	OPTIONS: ["tune this build", "audio · video · controls · accessibility"],
	QUIT: ["saved at {cur}", "quit; the version waits for you"],
}
const REWINDING := "rewinding ..."
const SHIPPED := "shipped: %s"
const THIS_BUILD := "this build"

var history: Array[Dictionary] = []   ## [{v: [M, m, p], module: String, session: StringName}]
var current: Array = [0, 0, 0]        ## the save's version
var replay_to: Array = [0, 0, 0]      ## the version the chosen replay session started on
var play_line := ""                   ## "Stage 2 · Session 9" (Continue's readout)
var kind: StringName = &""            ## the focused card's kind ("" in the boot)
var gentle := false                   ## reduce flashing
var t := 0.0                          ## boot clock
var wheels: Array[float] = [0.0, 0.0, 0.0]
var readout_on := true                ## false while a sub menu is up (the odometer dims)
var spark_frames := 0                 ## frames drawn with sparks (tests)
var max_speed := 0.0                  ## the fastest wheel step so far, digits per second (tests)

var _booting := false
var _landed := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- The campaign's versions ----------------------------------------------------------

## The versions the save shipped, from v0.0.0: one entry per done session in campaign order
## (the version it reached and the module it shipped), never past `cur`; a last entry for `cur`
## itself when the walk does not end on it (a dev-session pick's patch step).
static func version_history(done: Array, cur: GameVersion) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"v": [0, 0, 0], "module": "", "session": &""}]
	var v := GameVersion.make(0, 0, 0)
	for s: SessionDef in CampaignDB.campaign.sessions:
		if s == null or not String(s.id) in done:
			continue
		var next := GameVersion.from_array(v.to_array())
		next.bump(s.bump)
		if _after(next, cur):
			break
		v = next
		out.append({"v": v.to_array(), "module": module_of(s), "session": s.id})
	if out.back().v != cur.to_array():
		out.append({"v": cur.to_array(), "module": THIS_BUILD, "session": &""})
	return out


## The module a session shipped: its first patch note (no trailing full stop), else its title.
static func module_of(s: SessionDef) -> String:
	var m := String(s.notes[0]) if not s.notes.is_empty() else s.title
	return m.trim_suffix(".")


## The version session `id` started on (the campaign's bumps before it, from v0.0.0).
static func start_version(id: StringName) -> GameVersion:
	var v := GameVersion.make(0, 0, 0)
	for s: SessionDef in CampaignDB.campaign.sessions:
		if s == null or s.id == id:
			break
		v.bump(s.bump)
	return v


static func _after(a: GameVersion, b: GameVersion) -> bool:
	return a.to_array() > b.to_array()


static func label_of(v: Array) -> String:
	return "v" + ".".join(v.map(func(d: Variant) -> String: return "?" if int(d) == SPIN else str(int(d))))


# --- Setup and driving -----------------------------------------------------------------

## Reads the save: its version, its history and Continue's session. Keeps the wheels where they are.
func load_save() -> void:
	var cur := SaveGame.version()
	current = cur.to_array()
	history = version_history(SaveGame.campaign().done as Array, cur)
	play_line = ""
	if not CampaignDB.is_done():
		var s := CampaignDB.current()
		if s != null:
			play_line = "Stage %d · Session %d" % [s.stage, CampaignDB.current_index()]
	queue_redraw()


## Starts the boot roll (no roll with reduce flashing: the wheels sit on the version).
func boot() -> void:
	gentle = SaveGame.reduce_flashing()
	t = 0.0
	_landed = false
	for i in 3:
		wheels[i] = float(current[i])
	_booting = not gentle and history.size() > 1
	if not _booting:
		_landed = true
	queue_redraw()


## Skips to the end of the boot (the version shown, no line of its own).
func finish_boot() -> void:
	if not _booting:
		return
	t = boot_end()
	_booting = false
	if not _landed:
		_landed = true
	queue_redraw()


func booting() -> bool:
	return _booting


func has_landed() -> bool:
	return _landed


func land_at() -> float:
	return REWIND + float(history.size() - 1) * tick()


func boot_end() -> float:
	return land_at() + HOLD


func tick() -> float:
	return minf(TICK, TICKS_MAX / float(maxi(history.size() - 1, 1)))


## The history entry the boot shows now (0 = v0.0.0 while it rewinds).
func boot_index() -> int:
	if t < REWIND:
		return 0
	return mini(history.size() - 1, 1 + int((t - REWIND) / tick()))


## The card `k` leads to (the wheels' target and the readout).
func focus(k: StringName) -> void:
	kind = k
	queue_redraw()


## Where the wheels head now: [major, minor, patch], SPIN for a "?".
func target() -> Array:
	if _booting:
		return history[boot_index()].v
	match kind:
		CONTINUE:
			return [current[0], current[1], SPIN]
		NEW:
			return [0, 0, 0]
		REPLAY:
			return replay_to
	return current


## The wheels roll back (New game, Replay, the boot's rewind) or forward.
func _down() -> bool:
	if _booting:
		return t < REWIND
	return kind == NEW or kind == REPLAY


func step(delta: float) -> void:
	if not is_visible_in_tree() and not _booting:
		return
	if SaveGame.reduce_flashing() != gentle:
		gentle = not gentle
		if gentle:
			finish_boot()
	if _booting:
		t += delta
		if not _landed and t >= land_at():
			_landed = true
			landed.emit()
		if t >= boot_end():
			_booting = false
			booted.emit()
	elif t < boot_end():
		t += delta
	var to := target()
	var down := _down()
	for i in 3:
		var before := wheels[i]
		if int(to[i]) == SPIN:
			if not gentle:
				wheels[i] += delta * SPIN_SPEED
		elif gentle:
			wheels[i] = float(to[i])   # reduce flashing: a snap, never a roll
		else:
			var v := wheels[i]
			var diff := -fposmod(v - float(to[i]), 10.0) if down else fposmod(float(to[i]) - v, 10.0)
			if absf(diff) < 0.02 or absf(diff) > 9.98:
				wheels[i] = float(posmod(roundi(v), 10))
			else:
				wheels[i] = v + signf(diff) * minf(absf(diff), delta * maxf(5.0, absf(diff) * 6.0))
		if delta > 0.0 and int(to[i]) != SPIN and not gentle:
			var moved := fposmod(absf(wheels[i] - before), 10.0)
			max_speed = maxf(max_speed, minf(moved, 10.0 - moved) / delta)
	queue_redraw()


## The version the wheels show when at rest ("v0.8.1"; "?" on a spinning wheel; "" mid-roll).
func shown() -> String:
	var to := target()
	for i in 3:
		if int(to[i]) != SPIN and absf(wheels[i] - float(to[i])) > 0.001:
			return ""
	return label_of(to)


func sparks_on() -> bool:
	return not gentle and _landed and t >= land_at() and t < land_at() + SPARK_TIME


## The readout's two lines now.
func readout() -> PackedStringArray:
	if _booting or kind == &"":
		var i := boot_index() if _booting else history.size() - 1
		var e: Dictionary = history[i]
		var r2 := REWINDING if i == 0 else SHIPPED % e.module
		return PackedStringArray([label_of(e.v), r2])
	var lines: Array = READ[kind]
	var out := PackedStringArray()
	for l: String in lines:
		out.append(l.format({"cur": label_of(current), "next": label_of([current[0], current[1], SPIN]),
				"old": label_of(replay_to), "play": play_line if play_line != "" else "the next session"}))
	return out


## The colour the readout's first line and a card's lit face take for `k`.
static func accent(k: StringName) -> Color:
	match k:
		NEW:
			return Palette.ODO_RED
		REPLAY:
			return Palette.ODO_TEAL
		OPTIONS, QUIT:
			return Palette.ODO_LAV
	return Palette.ODO_GOLD


# --- Layout ---------------------------------------------------------------------------

func housing_rect() -> Rect2:
	var y := HOUSING_Y
	if not gentle and _landed and t >= land_at() and t < land_at() + JOLT:
		y += JOLT_PX
	return Rect2(Vector2(roundf((size.x - HOUSING.x) * 0.5), y), HOUSING)


## Wheel i's window in this control's px (0 major, 1 minor, 2 patch).
func wheel_rect(i: int) -> Rect2:
	var h := housing_rect()
	return Rect2(h.position + Vector2(WHEEL_X + i * (WHEEL.x + WHEEL_GAP), WHEEL_Y), WHEEL)


## Where the mascot stands for `k` (x: the wheel that will change), on the housing's top.
func mascot_x(k: StringName) -> float:
	var h := housing_rect()
	match k:
		NEW, REPLAY:
			return wheel_rect(1).get_center().x
		OPTIONS:
			return h.get_center().x
		QUIT:
			return h.position.x + GLYPH_X + 2.5 * CELL
	return wheel_rect(2).get_center().x


# --- Drawing --------------------------------------------------------------------------

func _panel(r: Rect2, fill: Color, edge := EDGE, drop := 0.0) -> void:
	if drop > 0.0:
		draw_rect(Rect2(r.position + Vector2(0, drop), r.size), Palette.ODO_INK)
	draw_rect(r, Palette.ODO_INK)
	draw_rect(r.grow(-edge), fill)


## Outlined block text at `at` (top-left); returns its width. clip: draw only inside it.
func _big(s: String, at: Vector2, cell: float, fill: Color, shade: Color, outline: float, hi: Color,
		clip := Rect2()) -> float:
	var x := at.x
	var cells: Array[Array] = []
	for ch in s:
		var g: Array = GLYPHS.get(ch, [])
		if g.is_empty():
			x += 4.0 * cell
			continue
		var w := String(g[0]).length()
		for r in 7:
			for k in w:
				if String(g[r])[k] == "X":
					var below := r < 6 and String(g[r + 1])[k] == "X"
					var above := r > 0 and String(g[r - 1])[k] == "X"
					cells.append([Vector2(x + k * cell, at.y + r * cell), below, above])
		x += (w + 1) * cell
	if outline > 0.0:
		for q in cells:
			_cell(Rect2(q[0] - Vector2(outline, outline), Vector2(cell + 2.0 * outline, cell + 3.0 * outline)),
					Palette.ODO_INK, clip)
	var band := maxf(4.0, outline)
	for q in cells:
		_cell(Rect2(q[0], Vector2(cell, cell)), fill, clip)
		if not q[1] and shade.a > 0.0:
			_cell(Rect2(q[0] + Vector2(0, cell - band), Vector2(cell, band)), shade, clip)
		if not q[2] and hi.a > 0.0:
			_cell(Rect2(q[0], Vector2(cell, band)), hi, clip)
	return x - at.x - cell


func _cell(r: Rect2, c: Color, clip: Rect2) -> void:
	if clip.has_area():
		r = r.intersection(clip)
		if not r.has_area():
			return
	draw_rect(r, c)


func _grid(grid: Array, at: Vector2, s: float, fill: Color) -> void:
	for y in grid.size():
		var row := String(grid[y])
		for x in row.length():
			if row[x] == "K":
				draw_rect(Rect2(at + Vector2(x, y) * s, Vector2(s, s)), Palette.ODO_INK)
			elif row[x] == "G":
				draw_rect(Rect2(at + Vector2(x, y) * s, Vector2(s, s)), fill)


func _text(t_: String, y: float, px: int, c: Color, bold := false) -> void:
	var f := UiTheme.pixel_font(bold)
	draw_string(f, Vector2(0, y + f.get_ascent(px)), t_, HORIZONTAL_ALIGNMENT_CENTER, size.x, px, c)


func _draw() -> void:
	var h := housing_rect()
	_panel(h, Palette.ODO_HOUSING, EDGE, DROP)
	draw_rect(Rect2(h.position + Vector2(4, 4), Vector2(h.size.x - 8, 6)), Palette.ODO_HOUSING_HI)
	draw_rect(Rect2(h.position + Vector2(4, h.size.y - 10), Vector2(h.size.x - 8, 6)), Palette.ODO_HOUSING_LO)
	for q: Vector2 in [Vector2(13, 16), Vector2(h.size.x - 23, 16), Vector2(13, h.size.y - 26),
			Vector2(h.size.x - 23, h.size.y - 26)]:
		_panel(Rect2(h.position + q, Vector2(10, 10)), Palette.ODO_GOLD, 3.0)
	var glyph_y := h.position.y + WHEEL_Y + DIGIT_Y
	_big("v", Vector2(h.position.x + GLYPH_X, glyph_y), CELL, Palette.ODO_GOLD, Palette.ODO_GOLD_DARK, 4.0, Palette.ODO_GOLD_HI)
	for i in 2:
		var r := wheel_rect(i)
		_big(".", Vector2(r.end.x + 16.0, glyph_y), CELL, Palette.ODO_GOLD, Palette.ODO_GOLD_DARK, 4.0, Palette.ODO_GOLD_HI)
	var to := target()
	var lit := Palette.ODO_RED_DARK if kind == NEW and not _booting else \
			(Palette.ODO_TEAL_DARK if kind == REPLAY and not _booting else Palette.ODO_DIGIT)
	for i in 3:
		var r := wheel_rect(i)
		_panel(r, Palette.ODO_PAPER)
		var win := r.grow(-EDGE)
		var spin := int(to[i]) == SPIN
		var v := wheels[i]
		var moving := absf(v - roundf(v)) > 0.02 or (spin and not gentle)
		var col := lit if moving or (int(to[i]) != SPIN and int(to[i]) != int(current[i])) else Palette.ODO_DIGIT
		var dx := r.position.x + (WHEEL.x - 5.0 * CELL) * 0.5
		if spin and gentle:
			_big("?", Vector2(dx, r.position.y + DIGIT_Y), CELL, Palette.ODO_DIGIT, Palette.ODO_INK, 0.0, Color(1, 1, 1, 0), win)
		else:
			var base := floorf(v)
			var fr := v - base
			var y0 := r.position.y + DIGIT_Y - fr * WHEEL.y
			_big(str(posmod(int(base), 10)), Vector2(dx, y0), CELL, col, Palette.ODO_INK, 0.0, Color(1, 1, 1, 0), win)
			_big(str(posmod(int(base) + 1, 10)), Vector2(dx, y0 + WHEEL.y), CELL, col, Palette.ODO_INK, 0.0, Color(1, 1, 1, 0), win)
		# the drum's curve: shade at the window's top and bottom
		draw_rect(Rect2(win.position, Vector2(win.size.x, 21)), Color(Palette.ODO_INK, 0.38))
		draw_rect(Rect2(Vector2(win.position.x, win.end.y - 21), Vector2(win.size.x, 21)), Color(Palette.ODO_INK, 0.38))
		draw_rect(Rect2(win.position, Vector2(win.size.x, 8)), Color(Palette.ODO_INK, 0.3))
		draw_rect(Rect2(Vector2(win.position.x, win.end.y - 8), Vector2(win.size.x, 8)), Color(Palette.ODO_INK, 0.3))
		if spin and not _booting:
			var badge := Rect2(Vector2(r.get_center().x - 21, r.end.y + 11), Vector2(42, 32))
			_panel(badge, Palette.ODO_GOLD, 3.0, 3.0)
			var f := UiTheme.pixel_font(true)
			draw_string(f, Vector2(badge.position.x, badge.position.y + 4 + f.get_ascent(24)), "?",
					HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 24, Palette.ODO_INK)
	if not _booting and kind == OPTIONS:
		_grid(GEAR, h.position + Vector2(h.size.x - 56, -24), 6.0, Palette.ODO_LAV)
	elif not _booting and kind == QUIT:
		_grid(LOCK, h.position + Vector2(h.size.x - 56, -29), 6.0, Palette.ODO_GOLD)
	if sparks_on():
		spark_frames += 1
		var p := (t - land_at()) / SPARK_TIME
		for k in SPARKS:
			var sx := h.position.x + 32.0 + k * (h.size.x - 64.0) / float(SPARKS - 1)
			var up := sin(p * PI) * (32.0 + (k % 3) * 24.0)
			draw_rect(Rect2(Vector2(sx, h.position.y - 13.0 - up), Vector2(8, 8)),
					Palette.ODO_GOLD if k % 2 else Palette.ODO_GOLD_HI)
	if readout_on:
		var lines := readout()
		var c1 := Palette.ODO_GOLD if _booting or kind == &"" else accent(kind)
		_text(lines[0], READ_Y, READ_SIZE, c1, true)
		_text(lines[1], READ2_Y, READ2_SIZE, Palette.ODO_LAV)
		_text(HINT, HINT_Y, HINT_SIZE, Palette.ODO_LAV_DIM)
	else:   # a sub menu (the confirm, Replay) is up: dim the odometer under it
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.ODO_INK, SCRIM))

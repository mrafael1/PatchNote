extends Node2D
## The flip's visual help (M43.2, G13b): for the first seconds of edit_inverted, four
## arrows around the player, one per move input, each placed where that input used to go
## and pointing where it goes now (read from RunState.rules.input_rotation_deg, as the
## player turns its movement), labelled with the input's first key from the InputMap.
##
## Presentation only, campaign only (edit_inverted.landed_hint). It counts physics ticks
## like the rule book (the pause stops it), pulses gently, and fades out at the end; with
## reduce flashing on (gentle) it does not pulse, it only fades. No RNG, no groups.

const HINT_TICKS := 210         ## 3.5 s at 60 ticks
const FADE_TICKS := 30          ## the last 0.5 s fade out
const PULSE_HZ := 1.5
const RADIUS := 48.0
const ARROW := 14.0
const COLOR := Color(1.0, 0.85, 0.3)
const ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
const DIRS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

var gentle := false
var ticks := 0
var _labels: Array[String] = []


func _ready() -> void:
	name = "InvertedHint"
	z_index = 50
	for a in ACTIONS:
		_labels.append(key_label(a))
	queue_redraw()


func _physics_process(_delta: float) -> void:
	ticks += 1
	global_rotation = 0.0
	if ticks >= HINT_TICKS:
		queue_free()
		return
	modulate.a = alpha()
	queue_redraw()


## The hint's opacity now: a pulse (or steady when gentle), then the fade.
func alpha() -> float:
	var base := 0.85
	if not gentle:
		var t := float(ticks) / Engine.physics_ticks_per_second
		base = 0.6 + 0.35 * (0.5 + 0.5 * cos(TAU * PULSE_HZ * t))
	var left := HINT_TICKS - ticks
	if left < FADE_TICKS:
		base *= float(left) / FADE_TICKS
	return base


## Where input `dir` moves the player now (the player's own turn of its input).
static func moved(dir: Vector2) -> Vector2:
	var turn := fposmod(RunState.rules.input_rotation_deg, 360.0)
	return dir.rotated(deg_to_rad(turn)) if turn != 0.0 else dir


## The first keyboard key bound to `action` ("" if none), for the arrow's label. The move
## keys are bound by physical position (InputSetup), so the label is the letter printed on
## the player's keyboard at that spot (Z, not W, on AZERTY). `to_label` maps a physical
## code to the layout's key (tests pass their own layout); by default the DisplayServer's.
static func key_label(action: StringName, to_label := Callable()) -> String:
	if not InputMap.has_action(action):
		return ""
	if not to_label.is_valid():
		to_label = layout_label
	for ev in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k == null:
			continue
		var code := k.keycode
		if k.physical_keycode != KEY_NONE:
			code = to_label.call(k.physical_keycode)
			if code == KEY_NONE:
				code = k.physical_keycode
		if code != KEY_NONE:
			return OS.get_keycode_string(code)
	return ""


## The key printed at physical position `physical` on the current layout (headless has no
## layout: the position's own name).
static func layout_label(physical: Key) -> Key:
	if DisplayServer.get_name() == "headless":
		return physical
	return DisplayServer.keyboard_get_label_from_physical(physical)


## The arrows: {from, dir, label} per input (tests read it).
func arrows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in DIRS.size():
		out.append({"from": DIRS[i] * RADIUS, "dir": moved(DIRS[i]).normalized(),
				"label": _labels[i] if i < _labels.size() else ""})
	return out


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for a: Dictionary in arrows():
		var from: Vector2 = a.from
		var dir: Vector2 = a.dir
		var tip := from + dir * ARROW
		var tail := from - dir * ARROW * 0.6
		var side := dir.orthogonal() * ARROW * 0.6
		draw_line(tail, tip - dir * ARROW * 0.4, COLOR, 3.0)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * ARROW * 0.8 + side,
				tip - dir * ARROW * 0.8 - side]), COLOR)
		var label: String = a.label
		if label != "" and font != null:
			var at := from + from.normalized() * 22.0 + Vector2(-5.0, 5.0)
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR)

class_name Transition
extends CanvasLayer
## Applies and reverts patches with their presentation (PLAN 4).
##
## If the change alters gravity (on, off or direction) the full sequence runs: pause,
## terminal text over the frozen world, the actual apply/revert, unpause, then a
## grace period in which enemies deal no damage, and held inputs need a fresh press.
## Any other change is applied at once and only shows the AI line.
##
## A duration of 0 (Tuning.transition_long / transition_short) makes the whole thing
## synchronous, which is what the tests use.

signal finished

var busy := false
var sound: Sound                 ## optional

const GLITCH_SHADER := preload("res://systems/glitch.gdshader")
const PROGRESS_CELLS := 24

var _band: ColorRect
var _terminal: Label
var _toast: Label
var _timer: Timer
var _toast_left := 0.0
var _hint := ""
var _type_time := 0.0
var _type_total := 0.0
var _glitch: ColorRect
var _glitch_strength := 0.0
var _glitch_floor := 0.0          ## held while the terminal band is up
var _progress: Label
var _progress_time := 0.0
var _progress_total := 0.0


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Drawn first, so the terminal band sits crisp on top of the glitched world.
	_glitch = ColorRect.new()
	_glitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLITCH_SHADER
	_glitch.material = mat
	_glitch.visible = false
	add_child(_glitch)

	_band = ColorRect.new()
	_band.color = Color(0.0, 0.03, 0.02, 0.72)
	_band.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	_band.offset_top = -70
	_band.offset_bottom = 70
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.visible = false
	add_child(_band)

	_terminal = _make_label(24)
	_terminal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_terminal.offset_left = 80
	_terminal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_band.add_child(_terminal)

	_progress = _make_label(18)
	_progress.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_progress.offset_left = 80
	_progress.offset_top = -30
	_progress.offset_bottom = -6
	_progress.modulate = Color(1, 1, 1, 0.7)
	_band.add_child(_progress)

	_toast = _make_label(20)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -120
	_toast.offset_bottom = -50
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast.visible = false
	add_child(_toast)

	# A child Timer, not a SceneTreeTimer: it goes away with this node, so a scene
	# reload in the middle of a transition cannot resume a freed coroutine.
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.ignore_time_scale = true
	add_child(_timer)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Starts applying m. Returns false if it was refused (busy, already applied, not
## legal). force skips requires/conflicts, for the debug console.
func request_apply(m: Mutation, force := false) -> bool:
	if busy or m == null or RunState.has_patch(m.id):
		return false
	if not force and not RunState.can_apply(m):
		return false
	var after: Array[Mutation] = RunState.stack.duplicate()
	after.append(m)
	var text := "> merging patch: %s" % m.title
	if m.is_mode_switch:
		text += "\n> compiling..."
	var duration := Tuning.transition_long if m.is_mode_switch else Tuning.transition_short
	_run(func() -> void: RunState.apply(m, force), after, text, m.line_applied, duration)
	return true


## Starts putting big patch m in the big slot (PLAN v3 1.2). Always the full, long
## sequence: a genre change pauses the world whatever it does to gravity. M10 gives it
## its own look ("migrating engine"); M9 reuses the mode-switch one.
func request_swap_big(m: Mutation) -> bool:
	if busy or m == null or not m.is_big or m == RunState.big:
		return false
	var after: Array[Mutation] = []
	if RunState.big != null:
		var dropped := RunState.dependents_of(RunState.big)
		for x in RunState.stack:
			if not dropped.has(x):
				after.append(x)
	else:
		after = RunState.stack.duplicate()
	var text := "> merging major update: %s\n> compiling..." % m.title
	_run(func() -> void: RunState.swap_big(m), after, text, m.line_applied, Tuning.transition_long, m)
	return true


## Starts reverting m and its dependents: one action, one transition.
func request_revert(m: Mutation) -> bool:
	if busy or m == null or not RunState.stack.has(m):
		return false
	var going := RunState.dependents_of(m)
	going.append(m)
	var after: Array[Mutation] = []
	var long := false
	for x in RunState.stack:
		if going.has(x):
			long = long or x.is_mode_switch
		else:
			after.append(x)
	var text := "> rolling back %s: %s" % [RunState.version_label(), m.title]
	if going.size() > 1:
		text += "\n> and %d dependent patch(es)" % (going.size() - 1)
	var duration := Tuning.transition_long if long else Tuning.transition_short
	_run(func() -> void: RunState.revert(m), after, text, m.line_reverted, duration)
	return true


## next_big: the big patch the operation puts in the slot (null: the slot does not
## change). A big swap always plays the full sequence.
func _run(operation: Callable, after: Array[Mutation], text: String, line: String, duration: float,
		next_big: Mutation = null) -> void:
	var old := RunState.rules
	var new := RunState.preview_rules(after, next_big if next_big != null else RunState.big)
	var gravity_changes := old.gravity_enabled != new.gravity_enabled \
			or (new.gravity_enabled and not old.gravity_dir.is_equal_approx(new.gravity_dir))
	if not gravity_changes and next_big == null:
		operation.call()
		glitch(0.45)
		_play(&"glitch")
		_show_toast(line)
		finished.emit()
		return
	busy = true
	RunState.set_pause(&"transition", true)
	if duration > 0.0:
		_terminal.text = text
		_terminal.visible_ratio = 0.0
		_type_time = 0.0
		_type_total = duration * 0.7
		_band.visible = true
		_progress_time = 0.0
		_progress_total = duration
		_progress.text = ""
		glitch(1.0)
		_glitch_floor = 0.22
		_play(&"compile")
		_timer.start(duration)
		await _timer.timeout
		_band.visible = false
		_glitch_floor = 0.0
	operation.call()
	glitch(0.9)
	_play(&"glitch")
	RunState.set_pause(&"transition", false)
	RunState.start_grace(Tuning.grace_time)
	for p in get_tree().get_nodes_in_group(&"player"):
		var provider := p.get(&"input") as PlayerInput
		if provider:
			provider.require_fresh_press()
	_show_toast(line)
	busy = false
	finished.emit()


## Hides any AI line still on screen (the report covers the game).
func clear_toast() -> void:
	_toast_left = 0.0
	_toast.visible = false


## Show an AI line on its own.
func say(line: String) -> void:
	_show_toast(line)


## An extra line shown under the next AI line (used once, for the rollback hint).
func queue_hint(line: String) -> void:
	_hint = line


func _show_toast(line: String) -> void:
	if line == "" and _hint == "":
		return
	_toast.text = "AI: " + line
	_toast_left = Tuning.toast_time
	if _hint != "":
		_toast.text += "\nAI: " + _hint
		_toast_left *= 2.0
		_hint = ""
	_toast.visible = true


## Kicks the full-screen glitch to at least `amount`; it then fades out.
func glitch(amount: float) -> void:
	_glitch_strength = maxf(_glitch_strength, amount)
	(_glitch.material as ShaderMaterial).set_shader_parameter(&"seed", randf() * 100.0)


func glitch_strength() -> float:
	return _glitch_strength


func _play(key: StringName) -> void:
	if sound:
		sound.play(key, 0.0)


func _process(delta: float) -> void:
	# Real time: the glitch must fade the same during a pause and at any time scale.
	var real := delta / maxf(Engine.time_scale, 0.001)
	if _glitch_strength > _glitch_floor:
		_glitch_strength = maxf(_glitch_floor, _glitch_strength - real * 2.5)
	else:
		_glitch_strength = _glitch_floor
	_glitch.visible = _glitch_strength > 0.01
	if _glitch.visible:
		(_glitch.material as ShaderMaterial).set_shader_parameter(&"strength", _glitch_strength)
	if _band.visible and _progress_total > 0.0:
		_progress_time += real
		var u := clampf(_progress_time / _progress_total, 0.0, 1.0)
		var cells := int(u * PROGRESS_CELLS)
		_progress.text = "[%s%s] %d%%" % ["#".repeat(cells), ".".repeat(PROGRESS_CELLS - cells), int(u * 100)]
	if _band.visible and _type_total > 0.0:
		_type_time += delta
		_terminal.visible_ratio = clampf(_type_time / _type_total, 0.0, 1.0)
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false

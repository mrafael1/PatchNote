class_name Hud
extends CanvasLayer
## Minimal HUD: HP, kills, build version, rollbacks, the final-wave countdown, the
## next-patch gauge (G11 feedback: "nothing shows when it'll come"), and the "Next patch
## incoming" banner (PLAN v5 2.1): it pulses once the Director's kill gate is met,
## until the prompt opens.

var player: Node
var director: AiDirector
var run_loop: RunLoop
var turn_clock: TurnClock

const INCOMING := "Next patch incoming"
const PULSE_SPEED := 6.0
const GAUGE_SIZE := Vector2(260, 10)
const GAUGE_BACK := Color(1, 1, 1, 0.15)
const GAUGE_FILL := Color(0.55, 1.0, 0.7)

var _label: Label
var _banner: Label
var _gauge: Control
var _gauge_label: Label
var _gauge_fill: ColorRect
var _kill_pulse := 0.0
const KILL_PULSE_TIME := 0.15
var _pulse := 0.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS   # the banner hides as the prompt pauses the game
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.position += Vector2(-14, 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)
	_banner = Label.new()
	_banner.text = INCOMING
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y += 64   # under the gauge
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override(&"font_size", 28)
	_banner.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.7))
	_banner.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override(&"outline_size", 6)
	_banner.visible = false
	add_child(_banner)
	_build_gauge()
	if director:
		director.kill_counted.connect(_on_kill_counted)


## The game's version and the in-run build (PLAN v5 1.6): "v0.1.2 · build 5", or with
## a parked big patch in the slot, "v0.1.2 · build 5 · Turn-based".
static func version_text() -> String:
	var text := "%s · build %d" % [SaveGame.version().label(), RunState.build_number]
	if RunState.big != null:
		text += " · " + RunState.big.genre_label
	return text


## "PATCH 2/3" over a bar that fills as the next prompt nears.
func _build_gauge() -> void:
	_gauge = VBoxContainer.new()
	_gauge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_gauge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gauge.position.y += 10
	_gauge.add_theme_constant_override(&"separation", 3)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_label = Label.new()
	_gauge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gauge_label.add_theme_font_size_override(&"font_size", 15)
	_gauge_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_gauge_label.add_theme_constant_override(&"outline_size", 4)
	_gauge.add_child(_gauge_label)
	var back := ColorRect.new()
	back.color = GAUGE_BACK
	back.custom_minimum_size = GAUGE_SIZE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.add_child(back)
	_gauge_fill = ColorRect.new()
	_gauge_fill.color = GAUGE_FILL
	_gauge_fill.size = Vector2(0, GAUGE_SIZE.y)
	_gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(_gauge_fill)
	_gauge.visible = false
	add_child(_gauge)


## The gauge's fill, 0..1, or -1 while it is hidden (tests).
func gauge_value() -> float:
	return _gauge_fill.size.x / GAUGE_SIZE.x if _gauge.visible else -1.0


func gauge_text() -> String:
	return _gauge_label.text


## A counted kill: the bar flashes bright, so the kill reads as filling it.
func _on_kill_counted() -> void:
	_kill_pulse = KILL_PULSE_TIME


func _update_gauge(delta := 0.0) -> void:
	var progress := director.prompt_progress() if director else -1.0
	_gauge.visible = progress >= 0.0
	_kill_pulse = maxf(0.0, _kill_pulse - delta)
	_gauge_fill.color = GAUGE_FILL.lerp(Color.WHITE, 0.7 * _kill_pulse / KILL_PULSE_TIME)
	if not _gauge.visible:
		return
	_gauge_label.text = "PATCH %d/%d" % [director.prompt_index + 1, Tuning.prompts_per_run]
	_gauge_fill.size = Vector2(GAUGE_SIZE.x * progress, GAUGE_SIZE.y)


func banner_shown() -> bool:
	return _banner.visible


func _process(delta: float) -> void:
	var incoming := director != null and director.patch_incoming()
	_banner.visible = incoming
	if incoming:
		_pulse += delta * PULSE_SPEED
		_banner.modulate.a = 0.55 + 0.45 * sin(_pulse)
	else:
		_pulse = 0.0
	_update_gauge(delta)
	var hp := 0
	if is_instance_valid(player):
		var health := Component.find(player, Health) as Health
		if health:
			hp = ceili(health.hp() - 0.001)
	var dash := ""
	if is_instance_valid(player):
		var dasher := Component.find(player, Dasher) as Dasher
		dash = "dash ready" if dasher and dasher.is_ready() else "dash ..."
	_label.text = "HP %d   Kills %d   %s\n%s" % [hp, RunState.kills, version_text(), dash]
	# Rollbacks are parked (PLAN v5 1.3): the line shows only while a test grants charges.
	if director and director.charges > 0:
		_label.text += "\nRollbacks: %d [Tab]" % director.charges
	if turn_clock and turn_clock.active:
		_label.text += "\nTurn %d%s" % [turn_clock.turns, "   [E] wait" if turn_clock.is_waiting() else ""]
	if run_loop and run_loop.stages and run_loop.stages.size() > 1:
		_label.text += "\nStage %d/%d" % [run_loop.stage_index + 1, run_loop.stages.size()]
	if run_loop and run_loop.smoke_time_left() >= 0.0:
		_label.text += "\nSMOKE TEST  %d s" % ceili(run_loop.smoke_time_left())
	if run_loop and run_loop.rc_time_left() >= 0.0:
		_label.text += "\nRELEASE CANDIDATE  %d s" % ceili(run_loop.rc_time_left())

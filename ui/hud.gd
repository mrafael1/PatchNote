class_name Hud
extends CanvasLayer
## Minimal HUD: HP, kills, build version, rollbacks, the final-wave countdown, and
## the "Next patch incoming" banner (PLAN v5 2.1): it pulses once the Director's kill
## gate is met, until the prompt opens.

var player: Node
var director: AiDirector
var run_loop: RunLoop
var turn_clock: TurnClock

const INCOMING := "Next patch incoming"
const PULSE_SPEED := 6.0

var _label: Label
var _banner: Label
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
	_banner.position.y += 54
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override(&"font_size", 28)
	_banner.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.7))
	_banner.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override(&"outline_size", 6)
	_banner.visible = false
	add_child(_banner)


## The game's version and the in-run build (PLAN v5 1.6): "v0.1.2 · build 5", or with
## a parked big patch in the slot, "v0.1.2 · build 5 · Turn-based".
static func version_text() -> String:
	var text := "%s · build %d" % [SaveGame.version().label(), RunState.build_number]
	if RunState.big != null:
		text += " · " + RunState.big.genre_label
	return text


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
	if run_loop and run_loop.smoke_time_left() >= 0.0:
		_label.text += "\nSMOKE TEST  %d s" % ceili(run_loop.smoke_time_left())
	if run_loop and run_loop.rc_time_left() >= 0.0:
		_label.text += "\nRELEASE CANDIDATE  %d s" % ceili(run_loop.rc_time_left())

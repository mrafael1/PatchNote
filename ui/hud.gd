class_name Hud
extends CanvasLayer
## Minimal HUD: HP, kills, build version, rollbacks, and the final-wave countdown.

var player: Node
var director: AiDirector
var run_loop: RunLoop
var turn_clock: TurnClock

var _label: Label


func _ready() -> void:
	layer = 50
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.position += Vector2(-14, 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)


## The game's version and the in-run build (PLAN v5 1.6): "v0.1.2 · build 5", or with
## a parked big patch in the slot, "v0.1.2 · build 5 · Turn-based".
static func version_text() -> String:
	var text := "%s · build %d" % [SaveGame.version().label(), RunState.build_number]
	if RunState.big != null:
		text += " · " + RunState.big.genre_label
	return text


func _process(_delta: float) -> void:
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
	if run_loop and run_loop.rc_time_left() >= 0.0:
		_label.text += "\nRELEASE CANDIDATE  %d s" % ceili(run_loop.rc_time_left())

class_name Hud
extends CanvasLayer
## Minimal HUD: HP, kills, build version, rollbacks, and the final-wave countdown.

var player: Node
var director: AiDirector
var run_loop: RunLoop

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


## "v0.9" or, with a big patch in the slot, "v0.9 · Motion time".
static func version_text() -> String:
	if RunState.big != null:
		return "%s · %s" % [RunState.version_label(), RunState.big.genre_label]
	return RunState.version_label()


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
	var rollbacks := "Rollbacks: %d [Tab]" % director.reverts_left if director else ""
	_label.text = "HP %d   Kills %d   %s\n%s\n%s" % [hp, RunState.kills, version_text(), rollbacks, dash]
	if run_loop and run_loop.rc_time_left() >= 0.0:
		_label.text += "\nRELEASE CANDIDATE  %d s" % ceili(run_loop.rc_time_left())

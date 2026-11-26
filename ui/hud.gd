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
const GAUGE_FILL := Palette.GAUGE

var _label: Label
var _banner: Label
var _gauge: Control
var _gauge_label: Label
var _gauge_fill: ColorRect
var _kill_pulse := 0.0
const KILL_PULSE_TIME := 0.15
var _pulse := 0.0
var _goal: Label   ## a campaign session's goal at the top centre (PLAN v8 2)

## M47.2 (owner G14a: "mascot on the right hide UI => put UI to the top right"): in a
## campaign session the top right is one band, y BAND_TOP..BAND_BOTTOM: the corner text
## (HP, version, dash: at most two lines at font 20, 59 px) at the right edge, and the path
## widget left of it (Auto's level, Survival's ammo). The mascot sits under the band
## (Mascot.TOP) and never rises into it (MascotBody.top_limit). Arsenal's hand is bottom
## left (it has hand_rect()). The legacy loop's HUD is untouched.
const BAND_TOP := 8.0
const BAND_BOTTOM := 68.0
const BAND_GAP := 18.0
const PATH_MAX_W := 300.0
const CORNER_RIGHT := 14.0
## The widest corner text the band is placed against (not the live text, so the widget
## never jitters as HP or the dash line change): HP and the version, and the dash line.
const CORNER_WIDEST: Array[String] = ["HP 999   v9.99.99", "teleport ready", "teleport ..."]
const GOAL_WIDEST: Array[String] = ["Survive 9:59", "Kills 999/999"]


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS   # the banner hides as the prompt pauses the game
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.position += Vector2(-14, 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)
	_banner = Label.new()
	_banner.text = INCOMING
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y += 64   # under the gauge
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override(&"font_size", 28)
	_banner.add_theme_color_override(&"font_color", Palette.GAUGE)
	_banner.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	_banner.add_theme_constant_override(&"outline_size", 6)
	_banner.visible = false
	add_child(_banner)
	_build_gauge()
	_goal = Label.new()
	_goal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_goal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_goal.position.y += 10
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.add_theme_font_size_override(&"font_size", 24)
	_goal.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	_goal.add_theme_constant_override(&"outline_size", 5)
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_goal)
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
	_gauge_label.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
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


## M47.2: the corner text's reserved rect on a canvas of size `view` (right-aligned at
## W - CORNER_RIGHT, the widest corner text plus its outline).
static func corner_rect(view: Vector2) -> Rect2:
	var w := 0.0
	for t in CORNER_WIDEST:
		w = maxf(w, ThemeDB.fallback_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 10.0)
	return Rect2(view.x - CORNER_RIGHT - w, BAND_TOP, w, BAND_BOTTOM - BAND_TOP)


## M47.2: the goal's rect (top centre, the widest goal text at font 24 plus its outline).
static func goal_rect(view: Vector2) -> Rect2:
	var w := 0.0
	for t in GOAL_WIDEST:
		w = maxf(w, ThemeDB.fallback_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 10.0)
	var h := ThemeDB.fallback_font.get_height(24) + 10.0
	return Rect2(view.x * 0.5 - w * 0.5, 5.0, w, h)


## M47.2: where a band widget may sit: right of the goal, left of the corner text.
static func band_rect(view: Vector2) -> Rect2:
	var right := corner_rect(view).position.x - BAND_GAP
	return Rect2(right - PATH_MAX_W, BAND_TOP, PATH_MAX_W, BAND_BOTTOM - BAND_TOP)


## M47.2: places the path widget for a canvas of size `view`: a hand (hand_rect()) where
## it says, anything else right-aligned in the band at its minimum size.
func layout_path_widget(view: Vector2) -> void:
	if not is_instance_valid(path_widget):
		return
	if path_widget.has_method(&"hand_rect"):
		var r: Rect2 = path_widget.call(&"hand_rect", view)
		path_widget.position = r.position
		path_widget.size = r.size
		return
	var band := band_rect(view)
	var min_size := path_widget.get_combined_minimum_size()
	path_widget.position = Vector2(band.end.x - minf(min_size.x, PATH_MAX_W), BAND_TOP)


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


## The corner in a campaign session (owner, M39.2): only what the AI has added. HP comes
## with `health`; no kill count (the goal text counts); the version stamp waits for a
## `version` basic (S5): the version only, no "build N" (dev jargon, and it would tick
## through the rule edits; M42). Empty in the first sessions.
static func session_text(hp: int, dash: String) -> String:
	var top: Array[String] = []
	if Unlocks.has_basic(&"health"):
		top.append("HP %d" % hp)
	if Unlocks.has_basic(&"version"):
		top.append(SaveGame.version().label())
	var lines: Array[String] = []
	if not top.is_empty():
		lines.append("   ".join(top))
	if dash != "":
		lines.append(dash)
	return "\n".join(lines)


func goal_shown() -> String:
	return _goal.text


## PLAN v9 1.5 (M45a): the live path's widget (Auto's LV bar) under the corner text; null
## takes it away. Nothing else in the HUD changes.
var path_widget: Control


## M48.5a: the version rail docks the HUD while it shows: its modules carry HP, the version,
## the dash and the path widget, so the corner text and the widget hide (the widget keeps
## running: the rail reads the hand's misfuse). The goal, the gauge and the banner stay.
var docked := false


func set_docked(on: bool) -> void:
	docked = on
	_label.visible = not on
	if is_instance_valid(path_widget):
		path_widget.visible = not on


func set_path_widget(widget: Control) -> void:
	if is_instance_valid(path_widget) and path_widget != widget:
		path_widget.queue_free()
	path_widget = widget
	if widget != null and widget.get_parent() != self:
		if widget.get_parent() != null:
			widget.get_parent().remove_child(widget)
		add_child(widget)
	if widget != null and docked:
		widget.visible = false
	if widget != null and is_inside_tree():
		layout_path_widget(get_viewport().get_visible_rect().size)


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
	_goal.text = run_loop.goal_text() if run_loop else ""
	_goal.modulate.a = 0.5 if run_loop and run_loop.clock_held() else 1.0   # held by an event: paused
	var hp := 0
	if is_instance_valid(player):
		var health := Component.find(player, Health) as Health
		if health:
			hp = ceili(health.hp() - 0.001)
	var dash := ""
	if is_instance_valid(player):
		var dasher := Component.find(player, Dasher) as Dasher
		if dasher and not player.get(&"dash_locked"):
			dash = "%s ready" % dasher.label() if dasher.is_ready() else "%s ..." % dasher.label()
	if RunState.session != null:
		_label.text = session_text(hp, dash)
		layout_path_widget(get_viewport().get_visible_rect().size)
		return
	_label.text = "HP %d   Kills %d   %s\n%s" % [hp, RunState.kills, version_text(), dash]
	# Rollbacks are parked (PLAN v5 1.3): the line shows only while a test grants charges.
	if director and director.charges > 0:
		_label.text += "\nRollbacks: %d [Tab]" % director.charges
	if turn_clock and turn_clock.active:
		_label.text += "\nTurn %d%s" % [turn_clock.turns, "   [E] wait" if turn_clock.is_waiting() else ""]
	if run_loop and run_loop.stages and run_loop.stages.size() > 1:
		_label.text += "\nStage %d/%d" % [run_loop.stage_index + 1, run_loop.stages.size()]
		if run_loop.exit_open and not run_loop.exit_reached:
			_label.text += "   EXIT OPEN: reach it"
	if run_loop and run_loop.smoke_time_left() >= 0.0:
		_label.text += "\nSMOKE TEST  %d s" % ceili(run_loop.smoke_time_left())
	if run_loop and run_loop.rc_time_left() >= 0.0:
		_label.text += "\nRELEASE CANDIDATE  %d s" % ceili(run_loop.rc_time_left())

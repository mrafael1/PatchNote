class_name PauseMenu
extends CanvasLayer
## PLAN v9.1 1.16 (M47.3): the pause menu. Opened by the `pause` action (Esc / pad Start)
## when can_open() says so; pause reason &"menu". Menus never step the simulation: while it
## is open the bot's policy, a pick panel's lock, a hit stop, the fingerprint's pick clock,
## the speech queue and the mascot's typing are all held (_freeze), so a replay with the
## menu opened and closed hashes the same as one without it, and RunState.real_time()
## leaves its frames out.
##
## Full (Stage 2 on): Resume / Options / Restart session (confirm: "Counts as a try.") /
## Quit to title, in the Pixel UI panel once the look's `ui` group is on, neutral before.
## Raw (Stage 1 and the v6 loop): one grey monospace line, "PAUSED   [Esc] resume   [Q]
## quit to start" (Q by position: AZERTY prints A; the pad's Y quits too).

const LAYER := 98
const RAW_LINE := "PAUSED   [{key:pause}] resume   [%s] quit to start"
const CONFIRM_LINE := "Restart this session?\nCounts as a try."
const FADE := 0.12

signal resumed
signal quit_requested
signal restart_requested

var game: Main
var raw := false
var options: OptionsScreen

var _root: Control
var _scrim: ColorRect
var _panel: PanelContainer
var _menu: VBoxContainer
var _confirm: VBoxContainer
var _raw_label: Label
var _buttons: Array[Button] = []
var _confirm_buttons: Array[Button] = []
var _open := false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "PauseRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	UiTheme.apply(_root)   # M47.4 (PLAN 1.16): neutral until a look is picked
	_scrim = ColorRect.new()
	_scrim.color = Color(Palette.SCRIM, 0.72)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_raw_label = Label.new()
	_raw_label.name = "RawLine"
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	_raw_label.add_theme_font_override(&"font", mono)
	_raw_label.add_theme_font_size_override(&"font_size", 20)
	_raw_label.add_theme_color_override(&"font_color", Palette.UI_DIM)
	center.add_child(_raw_label)

	_panel = PanelContainer.new()
	_panel.name = "PausePanel"
	_panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 30)
	title.add_theme_color_override(&"font_color", Palette.UI_TEXT)
	column.add_child(title)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override(&"separation", 10)
	column.add_child(_menu)
	_buttons.append(_button(_menu, "Resume", close))
	_buttons.append(_button(_menu, "Options", open_options))
	_buttons.append(_button(_menu, "Restart session", ask_restart))
	_buttons.append(_button(_menu, "Quit to title", quit))
	_wrap_focus(_buttons)

	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override(&"separation", 10)
	_confirm.visible = false
	column.add_child(_confirm)
	var ask := Label.new()
	ask.text = CONFIRM_LINE
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.add_theme_font_size_override(&"font_size", 20)
	ask.add_theme_color_override(&"font_color", Palette.UI_SOFT)
	_confirm.add_child(ask)
	_confirm_buttons.append(_button(_confirm, "Yes, restart", restart))
	_confirm_buttons.append(_button(_confirm, "No", cancel_restart))
	_wrap_focus(_confirm_buttons)

	options = OptionsScreen.new()
	options.name = "Options"
	options.visible = false
	options.closed.connect(_on_options_closed)
	_root.add_child(options)
	_dress()
	Skins.hub.skin_changed.connect(_on_skin_changed)


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)
	if _open:
		_freeze(false)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override(&"font_size", 20)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func _wrap_focus(list: Array[Button]) -> void:
	for i in list.size():
		var up := list[(i - 1 + list.size()) % list.size()]
		var down := list[(i + 1) % list.size()]
		list[i].focus_neighbor_top = list[i].get_path_to(up)
		list[i].focus_neighbor_bottom = list[i].get_path_to(down)
		list[i].focus_previous = list[i].focus_neighbor_top
		list[i].focus_next = list[i].focus_neighbor_bottom


## The panel and buttons in the look's UI panel when its `ui` group is on (S9, later
## sessions, F10), neutral Godot controls with Palette colours otherwise.
func _dress() -> void:
	_panel.remove_theme_stylebox_override(&"panel")
	if Skins.is_on(&"ui_panel"):
		Skins.dress_panel(_panel)
	else:
		var box := StyleBoxFlat.new()
		box.bg_color = Palette.UI_PANEL
		box.border_color = Color(1, 1, 1, 0.18)
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		_panel.add_theme_stylebox_override(&"panel", box)
	for b in _buttons + _confirm_buttons:
		Skins.redress_button(b)


func _on_skin_changed(_skin: ArtSkin) -> void:
	_dress()


func dressed() -> bool:
	return _panel.get_theme_stylebox(&"panel") != null and Skins.is_on(&"ui_panel") \
			and _panel.get_theme_stylebox(&"panel") == Skins.current.ui_panel(false)


# --- The one rule --------------------------------------------------------------

## True when the menu may open now (PLAN 1.16): a session (or the v6 loop) whose genre is
## not over, with no debrief, stage card, report, dev session, prompt or build log up, no
## transition running, no scripted event holding the clock and B2 not resolving a turn.
## Over a pick panel and during B2's turn wait it may open.
static func allowed(g: Main) -> bool:
	if g == null or not g.is_inside_tree() or g.genre == null or g.genre.is_over():
		return false
	if g.debrief != null and g.debrief.is_open():
		return false
	if g.stage_card != null and g.stage_card.is_open():
		return false
	if g.transition != null and g.transition.busy:
		return false
	if g.event_player != null and g.event_player.clock_held():
		return false
	if RunState.is_paused_for(&"event") or RunState.is_paused_for(&"history") \
			or RunState.is_paused_for(&"dev_session") or RunState.is_paused_for(&"report"):
		return false
	var clock := TurnClock.current()
	if clock != null and clock.in_turn():
		return false
	if g.prompt_panel != null and g.prompt_panel.is_open():
		return false
	if g.report != null and g.report.is_open():
		return false
	if g.dev_flow != null and g.dev_flow.is_open():
		return false
	return true


func can_open() -> bool:
	return not _open and allowed(game)


## The raw variant: Stage 1 and the v6 loop.
static func raw_for(session: SessionDef) -> bool:
	return session == null or session.stage <= 1


func is_open() -> bool:
	return _open


# --- Open / close --------------------------------------------------------------

func open() -> bool:
	if not can_open():
		return false
	_open = true
	raw = raw_for(RunState.session)
	RunState.set_pause(RunState.MENU, true)
	_freeze(true)
	_raw_label.visible = raw
	_panel.visible = not raw
	_scrim.color = Color(Palette.SCRIM, 0.55 if raw else 0.72)
	_raw_label.text = raw_line()
	_menu.visible = true
	_confirm.visible = false
	options.visible = false
	_dress()
	_root.visible = true
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_root, ^"modulate:a", 1.0, FADE)
	if not raw:
		_buttons[0].grab_focus()
	return true


## Resume.
func close() -> void:
	if not _open:
		return
	if options.visible:
		options.close()
	_open = false
	_root.visible = false
	_confirm.visible = false
	RunState.set_pause(RunState.MENU, false)
	_freeze(false)
	var human: HumanInput = null
	if game != null and game.player != null:
		human = game.player.get(&"input") as HumanInput
	if human != null:
		human.require_fresh_press()   # a click on Resume never fires a shot
	if game != null and game.pick_panel != null and game.pick_panel.is_open():
		var first := game.pick_panel.find_children("*", "Button", true, false)
		if not first.is_empty():
			(first[0] as Button).grab_focus()
	else:
		var focus := _root.get_viewport().gui_get_focus_owner() if _root.is_inside_tree() else null
		if focus != null:
			focus.release_focus()
	resumed.emit()


static func raw_line(to_label := Callable()) -> String:
	var q: Key = InputSetup.layout_label(KEY_Q) if not to_label.is_valid() else to_label.call(KEY_Q)
	if q == KEY_NONE:
		q = KEY_Q
	return InputSetup.expand_keys(RAW_LINE % OS.get_keycode_string(q), to_label)


## Everything the menu holds while it is open (and lets go on close).
func _freeze(on: bool) -> void:
	if game == null:
		return
	if game.feedback != null:
		game.feedback.hold(on)
	if game.path_runner != null and game.path_runner.fp != null:
		game.path_runner.fp.hold(on)
	if game.session_runner != null:
		game.session_runner.hold_speech(on)
	if game.mascot != null:
		game.mascot.hold(on)


func open_options() -> void:
	if raw or not _open:
		return
	_panel.visible = false
	options.open()


func _on_options_closed() -> void:
	if not _open:
		return
	_panel.visible = true
	_buttons[1].grab_focus()


func ask_restart() -> void:
	if raw or not _open:
		return
	_menu.visible = false
	_confirm.visible = true
	_confirm_buttons[1].grab_focus()


func cancel_restart() -> void:
	_confirm.visible = false
	_menu.visible = true
	_buttons[2].grab_focus()


## "Yes, restart": the debrief's Retry from here (one attempt, one telemetry line, a reload).
func restart() -> void:
	if not _open or raw:
		return
	_leave()
	restart_requested.emit()
	if game != null:
		game.menu_restart()


## Quit to title (raw: quit to start). The save is untouched: Continue replays the session.
func quit() -> void:
	if not _open:
		return
	_leave()
	quit_requested.emit()
	if game != null:
		game.menu_quit()


func _leave() -> void:
	if options.visible:
		options.close()
	_open = false
	_root.visible = false
	_freeze(false)
	RunState.set_pause(RunState.MENU, false)


# --- Input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _open:
		get_viewport().set_input_as_handled()   # nothing under the menu hears a key
		return
	if event.is_action_pressed(&"pause") and can_open():
		open()
		get_viewport().set_input_as_handled()
	# Refused: not consumed, so the build log still closes on Esc.


func _input(event: InputEvent) -> void:
	if not _open or event is InputEventMouseMotion:
		return
	var back := event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")
	if raw:
		if back:
			close()
		elif _raw_quit(event):
			quit()
		get_viewport().set_input_as_handled()
		return
	if options.visible:
		return   # OptionsScreen takes its own keys (it is under this node: it hears them first)
	if back:
		if _confirm.visible:
			cancel_restart()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if _gui_event(event):
		return   # the buttons' navigation and clicks
	get_viewport().set_input_as_handled()


static func _raw_quit(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_Q:
		return true
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == JOY_BUTTON_Y


const GUI_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept",
		&"ui_select", &"ui_focus_next", &"ui_focus_prev"]


static func _gui_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return true
	for a in GUI_ACTIONS:
		if event.is_action(a):
			return true
	return false

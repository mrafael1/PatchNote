extends Node
## Autoload "InputSetup" (first autoload). Declares every input action in code so the
## bindings live in one readable place. Each action keeps one meaning in every rule state.

const DEADZONE := 0.25

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"aim_left", &"aim_right", &"aim_up", &"aim_down",
	&"shoot", &"dash", &"jump", &"wait", &"weapon_prev", &"weapon_next",
	&"weapon_1", &"weapon_2", &"weapon_3",
	&"patch_history", &"pause",
	&"choose_1", &"choose_2", &"choose_3", &"choose_4",
	&"debug_overlay", &"debug_console", &"debug_invincible", &"debug_spawn",
	&"debug_restart", &"debug_prompt", &"debug_bot", &"debug_session",
]


func _init() -> void:
	_bind(&"move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind(&"move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind(&"move_up", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind(&"move_down", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_bind(&"aim_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_bind(&"aim_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_bind(&"aim_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_bind(&"aim_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_bind(&"shoot", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_bind(&"dash", [_key(KEY_SHIFT), _mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_bind(&"jump", [_key(KEY_SPACE), _pad(JOY_BUTTON_A)])
	_bind(&"wait", [_key(KEY_E), _pad(JOY_BUTTON_Y)])   # pass a turn (B2); no-op otherwise
	# M44 (PLAN v9 9): switch weapons. E is wait too (B2 only). The bumpers are free: the
	# dash is on the left trigger.
	_bind(&"weapon_prev", [_key(KEY_Q), _mouse(MOUSE_BUTTON_WHEEL_UP), _pad(JOY_BUTTON_LEFT_SHOULDER)])
	_bind(&"weapon_next", [_key(KEY_E), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _pad(JOY_BUTTON_RIGHT_SHOULDER)])
	# M46 (PLAN v9 1.5, 9): Arsenal's hand by number, the number-row keys by position (the
	# same physical keys as choose_1..3, which keep them inside a panel; HumanInput reads
	# these only while nothing is paused). No pad bind: the bumpers already cycle.
	_bind(&"weapon_1", [_key(KEY_1)])
	_bind(&"weapon_2", [_key(KEY_2)])
	_bind(&"weapon_3", [_key(KEY_3)])
	_bind(&"patch_history", [_key(KEY_TAB), _pad(JOY_BUTTON_BACK)])
	_bind(&"pause", [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)])
	_bind(&"choose_1", [_key(KEY_1)])
	_bind(&"choose_2", [_key(KEY_2)])
	_bind(&"choose_3", [_key(KEY_3)])
	_bind(&"choose_4", [_key(KEY_4)])   # the Rework card (PLAN v6 2)
	_bind(&"debug_overlay", [_key(KEY_F1)])
	_bind(&"debug_console", [_key(KEY_F2)])
	_bind(&"debug_invincible", [_key(KEY_F3)])
	_bind(&"debug_spawn", [_key(KEY_F4)])
	_bind(&"debug_restart", [_key(KEY_F5)])
	_bind(&"debug_prompt", [_key(KEY_F6)])
	_bind(&"debug_bot", [_key(KEY_F7)])
	_bind(&"debug_session", [_key(KEY_F9)])   # Shift+F9 ships without the screen


## M47.3 (PLAN 1.16): the settings reach the engine at boot (buses, volumes; the window
## only outside tools and --fixed-fps). Deferred: the later autoloads (GenreDB, which a
## new save reads) are not in the tree yet. StartScreen applies again once the real save
## is read.
func _ready() -> void:
	_apply_settings.call_deferred()


func _apply_settings() -> void:
	Settings.apply()


## M47.3: "Mute when unfocused" mutes Master while the window has no focus.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT and what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	var i := AudioServer.get_bus_index(&"Master")
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and bool(Settings.get_value("mute_unfocused")):
		AudioServer.set_bus_mute(i, true)
	else:
		AudioServer.set_bus_mute(i, float(Settings.get_value("vol_master")) <= 0.0)


## The first keyboard key bound to `action` ("" if none), as printed on the player's
## keyboard. Keys are bound by physical position (_key), so the label is the letter at that
## spot on the player's layout (Z, not W, on AZERTY; A, not Q, for weapon_prev). `to_label`
## maps a physical code to the layout's key (tests pass their own layout); by default the
## DisplayServer's. (M43.2 for the flip arrows; moved here in the M44 review for lines.)
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
			code = number_row_label(k.physical_keycode, code)
		if code != KEY_NONE:
			return OS.get_keycode_string(code)
	return ""


## M46 (D2): a number-row key (physical KEY_0..KEY_9) whose layout label is not a letter or
## a digit (AZERTY: "&", "é", '"') is named by its digit, which every Latin layout prints on
## that key too ("[1]", never "[Ampersand]").
static func number_row_label(physical: Key, label: Key) -> Key:
	if physical < KEY_0 or physical > KEY_9:
		return label
	if (label >= KEY_A and label <= KEY_Z) or (label >= KEY_0 and label <= KEY_9):
		return label
	return physical


## The key printed at physical position `physical` on the current layout (headless has no
## layout: the position's own name).
static func layout_label(physical: Key) -> Key:
	if DisplayServer.get_name() == "headless":
		return physical
	return DisplayServer.keyboard_get_label_from_physical(physical)


## `text` with each "{key:<action>}" replaced by that action's key label (key_label). An
## action with no key keeps the token's action name; an unclosed token stays as written.
static func expand_keys(text: String, to_label := Callable()) -> String:
	var out := text
	var at := out.find("{key:")
	while at >= 0:
		var close := out.find("}", at)
		if close < 0:
			break
		var action := out.substr(at + 5, close - at - 5)
		var label := key_label(StringName(action), to_label)
		if label == "":
			label = action
		out = out.left(at) + label + out.substr(close + 1)
		at = out.find("{key:", at + label.length())
	return out


## Why the "{key:...}" tokens in `text` are wrong ("" = fine): each names a known action.
static func keys_problem(text: String) -> String:
	var at := text.find("{key:")
	while at >= 0:
		var close := text.find("}", at)
		if close < 0:
			return "unclosed {key:...} in '%s'" % text
		var action := StringName(text.substr(at + 5, close - at - 5))
		if not action in ACTIONS:
			return "unknown action {key:%s} in '%s'" % [action, text]
		at = text.find("{key:", close)
	return ""


func _bind(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e

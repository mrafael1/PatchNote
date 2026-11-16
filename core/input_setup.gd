extends Node
## Autoload "InputSetup" (first autoload). Declares every input action in code so the
## bindings live in one readable place. Each action keeps one meaning in every rule state.

const DEADZONE := 0.25

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"aim_left", &"aim_right", &"aim_up", &"aim_down",
	&"shoot", &"dash", &"jump",
	&"patch_history", &"pause",
	&"choose_1", &"choose_2", &"choose_3",
	&"debug_overlay", &"debug_console", &"debug_invincible", &"debug_spawn",
	&"debug_restart", &"debug_prompt", &"debug_bot",
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
	_bind(&"patch_history", [_key(KEY_TAB), _pad(JOY_BUTTON_BACK)])
	_bind(&"pause", [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)])
	_bind(&"choose_1", [_key(KEY_1)])
	_bind(&"choose_2", [_key(KEY_2)])
	_bind(&"choose_3", [_key(KEY_3)])
	_bind(&"debug_overlay", [_key(KEY_F1)])
	_bind(&"debug_console", [_key(KEY_F2)])
	_bind(&"debug_invincible", [_key(KEY_F3)])
	_bind(&"debug_spawn", [_key(KEY_F4)])
	_bind(&"debug_restart", [_key(KEY_F5)])
	_bind(&"debug_prompt", [_key(KEY_F6)])
	_bind(&"debug_bot", [_key(KEY_F7)])


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

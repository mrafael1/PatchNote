class_name HumanInput
extends PlayerInput
## Keyboard/mouse and gamepad.

var _stick_aim_active := false
var _wait_release := false
var _pending_step := 0   ## a mouse wheel notch (pressed and released in one event pair)


func _physics_process(_delta: float) -> void:
	move = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	fire = Input.is_action_pressed(&"shoot")
	dash_pressed = Input.is_action_just_pressed(&"dash")
	jump_pressed = Input.is_action_just_pressed(&"jump")
	jump_held = Input.is_action_pressed(&"jump")
	wait_pressed = Input.is_action_just_pressed(&"wait")
	var step := int(Input.is_action_just_pressed(&"weapon_next")) - int(Input.is_action_just_pressed(&"weapon_prev"))
	switch_step = _pending_step if _pending_step != 0 else step
	_pending_step = 0
	if _wait_release:
		if fire or jump_held or Input.is_action_pressed(&"dash"):
			fire = false
			jump_held = false
			jump_pressed = false
			dash_pressed = false
			wait_pressed = false
			switch_step = 0
		else:
			_wait_release = false

	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	if stick.length() > 0.3:
		_stick_aim_active = true
		aim_dir = stick.normalized()
	elif not _stick_aim_active:
		var parent := get_parent() as Node2D
		if parent:
			var to_mouse := parent.get_global_mouse_position() - parent.global_position
			if to_mouse.length() > 1.0:
				aim_dir = to_mouse.normalized()


func require_fresh_press() -> void:
	_wait_release = true


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_stick_aim_active = false
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# The wheel presses and releases in one frame: a physics-tick read can miss it.
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				_pending_step = 1
			MOUSE_BUTTON_WHEEL_UP:
				_pending_step = -1

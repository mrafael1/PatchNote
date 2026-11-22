class_name TimeTint
extends CanvasLayer
## B1 readability (PLAN v3 section 2): desaturation and a vignette over the world
## that fade in as time slows. Presentation only: reads RunState.felt_time_scale() (the
## time scale without hit stop), writes nothing.
## Sits under the HUD and every panel, so only the world is tinted.

const SHADER := preload("res://systems/time_tint.gdshader")
const FULL_AT := 0.08   ## time scale at which the tint is at full strength

var _rect: ColorRect


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_rect.material = mat
	_rect.visible = false
	add_child(_rect)


## 0 at normal speed, 1 at FULL_AT and below.
static func amount_for(time_scale: float) -> float:
	return clampf((1.0 - time_scale) / (1.0 - FULL_AT), 0.0, 1.0)


func amount() -> float:
	return amount_for(RunState.felt_time_scale()) if _rect.visible else 0.0


func _process(_delta: float) -> void:
	var a := amount_for(RunState.felt_time_scale())
	_rect.visible = a > 0.01
	if _rect.visible:
		(_rect.material as ShaderMaterial).set_shader_parameter(&"amount", a)

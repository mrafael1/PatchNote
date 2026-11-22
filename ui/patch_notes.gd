class_name PatchNotesScreen
extends CanvasLayer
## The patch notes of the new version (PLAN v5 4.1 step 3): "Version 0.1.0", a bullet
## per shipped change with the AI's pitch, what it unlocked, the AI's own ship if any,
## and "Play v0.1.0".

signal play_requested

var session: DevSession

var _root: Control
var _title: Label
var _body: Label
var _play: Button


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.98)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(820, 0)
	column.add_theme_constant_override(&"separation", 18)
	center.add_child(column)

	var head := Label.new()
	head.text = "PATCH NOTES"
	head.add_theme_font_size_override(&"font_size", 20)
	head.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	column.add_child(head)

	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 40)
	_title.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	column.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override(&"font_size", 20)
	column.add_child(_body)

	_play = Button.new()
	_play.custom_minimum_size = Vector2(240, 52)
	_play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_play.add_theme_font_size_override(&"font_size", 22)
	_play.pressed.connect(play)
	column.add_child(_play)


func is_open() -> bool:
	return _root.visible


func open(p_session: DevSession) -> void:
	session = p_session
	var lines := session.notes_lines()
	_title.text = lines[0] if not lines.is_empty() else "Version %s" % session.version_after().short()
	_body.text = "\n".join(lines.slice(1))
	_play.text = "Play %s" % session.version_after().label()
	_root.visible = true
	_focus_play.call_deferred()


## Deferred: the screen may be gone by then (Play pressed in the same frame).
func _focus_play() -> void:
	if is_inside_tree() and _root.visible:
		_play.grab_focus()


func text() -> String:
	return _title.text + "\n" + _body.text


func play_label() -> String:
	return _play.text


func play() -> void:
	if not _root.visible:
		return
	_root.visible = false
	play_requested.emit()

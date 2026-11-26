extends Control
## M48.5a: the AI sitting on the rail in the chat (Pixel_A: Blob at the log's bottom-right,
## its legs over the edge). The player's real body pick (SaveGame.mascot via the corner
## mascot's own body_id, or the caret before the face), in the Pixel body style once the look's
## `mascot` group is on (S9's 70 s), else the plain body. It mirrors the corner body's
## expression and talking each frame; the corner body itself is hidden while the rail shows
## (Mascot.set_docked). A child of the host over the terminal.

var frame: Node   ## the RailFrame
var body: MascotBody
var _view: PixelBodyView
var _key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func place(r: Rect2) -> void:
	position = r.position
	size = r.size
	_key = ""   # rebuild at the new scale


## The corner mascot of the bound game (null between sessions or in the v6 loop).
func source() -> Mascot:
	var g: Node = frame.game if frame != null else null
	if g == null or not is_instance_valid(g):
		return null
	var m: Variant = g.get(&"mascot")
	return m as Mascot if m != null and is_instance_valid(m) else null


func body_id() -> StringName:
	var m := source()
	if m == null:
		return body.id if body != null else MascotBody.CARET
	return m.body_id if m.face else MascotBody.CARET


func _process(_delta: float) -> void:
	if not visible:
		return
	var want := "%s|%s|%s" % [body_id(), Skins.is_on(&"mascot"), size]
	if want != _key:
		_rebuild()
		_key = want
	var src := source()
	if src != null and src.body != null and body != null:
		if body.expression != src.body.expression:
			body.set_expression(src.body.expression)
		body.talking = src.body.talking
	if body != null:
		body.gentle = SaveGame.reduce_flashing()


func _rebuild() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	elif body != null:
		body.queue_free()
	body = MascotBody.make(body_id())
	body.gentle = SaveGame.reduce_flashing()
	var scale_k := minf(size.x, size.y) / 100.0 * 0.85
	var centre := size * 0.5
	if Skins.is_on(&"mascot"):
		_view = PixelBodyView.wrap(body, scale_k)
		_view.position = centre
		add_child(_view)
		return
	body.position = centre
	body.scale = Vector2.ONE * scale_k
	add_child(body)

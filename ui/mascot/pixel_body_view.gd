class_name PixelBodyView
extends Node2D
## The mascot's `pixel` body style (PLAN 1.7, M48a): the same MascotBody (M47.2's body
## code, not edited) drawn into a SubViewport at a third of its size, then shown at PIXEL x
## with nearest filtering, so the AI wears the Pixel look's chunky pixels. Only the body is
## in the viewport: the bubble (a separate Control) keeps crisp text.
##
## The viewport re-renders when the expression changes and, while the body moves (its
## bounce, a talking mouth, a glitch), at STEP_HZ: a stepped pixel-art cadence, never every
## frame. This node sits where the body would sit (the body's centre at its origin) and
## covers REACH body units around it, more than MascotBody.worst_bounds() ever reaches, so
## Mascot.keep_out() (computed from the body's own bounds) still holds.

const PIXEL := 3          ## screen px per viewport px
const STEP_HZ := 8.0      ## re-renders per second while the body animates
const REACH := 100.0      ## body units covered each side of the centre

var body: MascotBody
var renders := 0          ## viewport renders asked for (tests)

var _body_scale := 1.0
var _vp: SubViewport
var _sprite: Sprite2D
var _key := ""


## Wraps `p_body`, shown at `body_scale` (what the holder would set as the body's scale).
static func wrap(p_body: MascotBody, body_scale: float) -> PixelBodyView:
	var v := PixelBodyView.new()
	v.body = p_body
	v._body_scale = body_scale
	return v


func _ready() -> void:
	var half := ceili(REACH * _body_scale / PIXEL)
	_vp = SubViewport.new()
	_vp.size = Vector2i(half * 2, half * 2)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	body.position = Vector2(half, half)
	body.scale = Vector2.ONE * (_body_scale / PIXEL)
	_vp.add_child(body)
	_sprite = Sprite2D.new()
	_sprite.texture = _vp.get_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * PIXEL
	add_child(_sprite)
	_render()


func _process(_delta: float) -> void:
	var key := "%s|%d" % [body.expression, int(floor(body.t * STEP_HZ))]
	if key != _key:
		_render()


## The screen rect (this node's parent's space) the viewport is shown over.
func shown_rect() -> Rect2:
	var s := Vector2(_vp.size) * PIXEL
	return Rect2(position - s * 0.5, s)


## A point in this node's parent's space, in the body's parent's (the viewport's) space:
## body.point_at() takes the latter.
func to_body_parent(p: Vector2) -> Vector2:
	return (p - position) / PIXEL + body.position


func _render() -> void:
	_key = "%s|%d" % [body.expression, int(floor(body.t * STEP_HZ))]
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1

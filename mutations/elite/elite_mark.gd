extends Component
## Marks an elite (PLAN v6 3) and owns its shield: on entering it sets the host's
## Health.shield_hits (what was left, if the elite had one before a revert, else the
## full shield_max); on leaving (a revert) it takes the shield back off and remembers
## what was left. Draws the shield as a ring, one segment per hit left.

const COLOR := Palette.ELITE
const IS_ELITE := &"elite_marked"      ## meta on the enemy: bool, decided once
const LEFT := &"elite_shield_left"     ## meta on the enemy: hits left at a revert

var shield_max := 3
var _ring: Node2D


func _ready() -> void:
	var hp := Component.find(get_parent(), Health) as Health
	if hp:
		hp.shield_hits = int(get_parent().get_meta(LEFT, shield_max))
	_ring = Node2D.new()
	_ring.draw.connect(_draw_ring)
	_ring.z_index = 1
	_ring.add_to_group(Skins.SKINNED)   # M48a: the look's live swap redraws it
	add_child(_ring)


func _exit_tree() -> void:
	var host := get_parent()
	var hp := Component.find(host, Health) as Health if host else null
	if hp and not host.is_queued_for_deletion():
		host.set_meta(LEFT, hp.shield_hits)
		hp.shield_hits = 0


func _physics_process(_delta: float) -> void:
	var host := get_parent() as Node2D
	if host:
		_ring.global_position = host.global_position
		_ring.queue_redraw()


## Hits the shield has left (tests).
func shield_left() -> int:
	var hp := Component.find(get_parent(), Health) as Health
	return hp.shield_hits if hp else 0


func _draw_ring() -> void:
	var left := shield_left()
	var host := get_parent()
	var r: float = (host.get(&"half_width") if host.get(&"half_width") != null else 15.0) + 9.0
	if Skins.current != null and _draw_ring_skin(left, r):
		return
	if left <= 0:
		_ring.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(COLOR, 0.35), 2.0)   # still an elite
		return
	var seg := TAU / maxf(shield_max, 1.0)
	for i in left:
		_ring.draw_arc(Vector2.ZERO, r, i * seg + 0.12, (i + 1) * seg - 0.12, 12, COLOR, 4.0)


## The Pixel preview (PLAN 1.7): the gold halo sprite sized to the ring, faded once the
## shield is gone, and one gold pip per hit left above it.
func _draw_ring_skin(left: int, r: float) -> bool:
	var skin := Skins.current
	if not skin.has(&"elite"):
		return false
	var cells := maxf(skin.size_of(&"elite").x, 1.0)
	var s := maxf(1.0, roundf(2.0 * r / cells))
	var frame := skin.idle_frame(&"elite", RunState.real_time())
	skin.draw(_ring, &"elite", Vector2.ZERO, s, frame, Color(1, 1, 1, 1.0 if left > 0 else 0.35))
	var pip := 6.0
	var y := -cells * s * 0.5 - pip - 3.0
	for i in left:
		var x := (i - (left - 1) * 0.5) * (pip + 3.0) - pip * 0.5
		_ring.draw_rect(Rect2(x - 1.0, y - 1.0, pip + 2.0, pip + 2.0), Palette.color(&"pip_back"))
		_ring.draw_rect(Rect2(x, y, pip, pip), Palette.color(&"elite"))
	return true

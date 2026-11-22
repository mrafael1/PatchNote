extends Component
## Marks an elite (PLAN v6 3) and owns its shield: on entering it sets the host's
## Health.shield_hits (what was left, if the elite had one before a revert, else the
## full shield_max); on leaving (a revert) it takes the shield back off and remembers
## what was left. Draws the shield as a ring, one segment per hit left.

const COLOR := Color(1.0, 0.85, 0.3)
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
	if left <= 0:
		_ring.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(COLOR, 0.35), 2.0)   # still an elite
		return
	var seg := TAU / maxf(shield_max, 1.0)
	for i in left:
		_ring.draw_arc(Vector2.ZERO, r, i * seg + 0.12, (i + 1) * seg - 0.12, 12, COLOR, 4.0)

extends ProjectileMod
## Burn line (laser rank 2): when the shot goes, a burning line along the path it flew:
## from the muzzle, through each wall it bounced off (and each turn, if gravity bends it),
## to where it ended. Never the straight chord muzzle -> end (M44 review).

const BurnLineZone := preload("res://weapons/traits/burn_line_zone.gd")
## Two steps whose directions differ by less than this (radians) are one straight segment.
const STRAIGHT := 0.005

var points := PackedVector2Array()   ## the path so far (tests)


## Each tick: where the shot is now (a straight flight keeps one segment).
func steer(p: Node2D, _delta: float) -> void:
	_add(p, p.global_position)


## A wall contact: the path turns here (bounce) or ends here.
func hit_wall(p: Node2D, pos: Vector2, _normal: Vector2) -> bool:
	_add(p, pos)
	return false


func despawned(p: Node2D) -> void:
	_add(p, p.global_position)
	if not is_instance_valid(RunState.world):
		return
	var zone := BurnLineZone.new()
	zone.points = points.duplicate()
	zone.source = p.source_patch
	RunState.world.add_child.call_deferred(zone)


func _add(p: Node2D, at: Vector2) -> void:
	if points.is_empty():
		points.append(p.origin)
	var last := points[points.size() - 1]
	if at.distance_squared_to(last) < 0.01:
		return
	if points.size() >= 2:
		var before := points[points.size() - 2]
		var a := last - before
		var b := at - last
		if a.length_squared() > 0.0 and absf(a.angle_to(b)) < STRAIGHT:
			points[points.size() - 1] = at   # the same straight segment, longer
			return
	points.append(at)

extends ProjectileMod
## Point blank (shotgun rank 3): x2 damage on a hit within RANGE of the muzzle. M50.1a: range
## and multiplier per instance (level 1 = RANGE, x2).

const RANGE := 2.0 * Tuning.TILE

var range_px := RANGE
var mult := 2.0
var _done := false


func hit_entity(p: Node2D, _target: Node, pos: Vector2) -> bool:
	if not _done and (p.origin as Vector2).distance_to(pos) <= range_px:
		_done = true
		p.damage = float(p.damage) * mult
	return false

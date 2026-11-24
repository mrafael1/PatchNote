extends ProjectileMod
## Point blank (shotgun rank 3): x2 damage on a hit within RANGE of the muzzle.

const RANGE := 2.0 * Tuning.TILE

var _done := false


func hit_entity(p: Node2D, _target: Node, pos: Vector2) -> bool:
	if not _done and (p.origin as Vector2).distance_to(pos) <= RANGE:
		_done = true
		p.damage = float(p.damage) * 2.0
	return false

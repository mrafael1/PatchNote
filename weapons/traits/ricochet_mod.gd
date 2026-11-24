extends ProjectileMod
## Ricochet (laser rank 3): on the weapon's own bounce the shot's pierce is back to full.

var pierce := 0
var bounced := 0   ## tests


func hit_wall(p: Node2D, _pos: Vector2, normal: Vector2) -> bool:
	if p.will_weapon_bounce(normal):
		bounced += 1
		p.pierce_left = pierce
		p.clear_pierced()
	return false

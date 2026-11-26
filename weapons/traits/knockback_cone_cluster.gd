extends "res://weapons/traits/knockback_cone.gd"
## Cluster's knockback cone (M50.3b, Arcade through S10 design 4.1): the shotgun's push, on the
## shell's blast instead of a pellet's hit (Projectile.blast_knockback, outward from the blast).
## The same steps: 420 x 1 -> 1.3 -> 1.6 -> 1.8. The bomblets do not push.


func describe(at_level: int) -> String:
	if at_level <= 1:
		return "knockback: the blast shoves enemies out"
	return "blast knockback x%s" % WeaponCurve.num(float(value_at(at_level, &"knockback", KNOCKBACK)) / KNOCKBACK)


func shot(_weapon: Weapon, _index: int, params: Dictionary) -> void:
	params[&"blast_knockback"] = float(step_value(&"knockback", KNOCKBACK))

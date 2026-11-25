extends WeaponTrait
## Pistol rank 3: the shot turns toward the nearest enemy within 4 tiles, at most
## 60 degrees a second (re-picked each tick; ties: distance, then tree order). M50.1a (deep
## curve): turn 60 -> 90 -> 120 -> 180 deg/s, range 4 -> 4.5 -> 5 -> 6 T.

const SeekerMod := preload("res://weapons/traits/seeker_mod.gd")


func steps() -> Array:
	return [{&"turn": 60.0, &"range": 4.0}, {&"turn": 90.0, &"range": 4.5},
			{&"turn": 120.0, &"range": 5.0}, {&"turn": 180.0, &"range": 6.0}]


func overflow_keys() -> Array:
	return [&"turn", &"range"]


func describe(at_level: int) -> String:
	return "shots seek (%d deg/s, %s T)" % [roundi(float(value_at(at_level, &"turn", 60.0))),
			WeaponCurve.num(float(value_at(at_level, &"range", 4.0)))]


func spawned(_weapon: Weapon, projectile: Node) -> void:
	var mod := SeekerMod.new()
	mod.range_px = float(step_value(&"range", 4.0)) * Tuning.TILE
	mod.turn_deg = float(step_value(&"turn", SeekerMod.TURN_DEG))
	projectile.add_mod(mod)

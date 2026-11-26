extends WeaponTrait
## M50.4c1 (Auto depth design 5): the Minigun's signature. Its stream sweeps a fixed pattern
## by shot count (-6, -2, +2, +6, +2, -2 degrees off the aim, then again), so a burst fans over
## a crowd. A pure function of Weapon.shots: no random stream.

const OFFSETS: Array[float] = [-6.0, -2.0, 2.0, 6.0, 2.0, -2.0]


func describe(_at_level: int) -> String:
	return "a sweeping stream of bullets"


## The sweep's offset in degrees for shot number `n` (0-based).
static func offset(n: int) -> float:
	return OFFSETS[posmod(n, OFFSETS.size())]


func shot(weapon: Weapon, _index: int, params: Dictionary) -> void:
	params[&"velocity"] = (params[&"velocity"] as Vector2).rotated(deg_to_rad(offset(weapon.shots)))

extends WeaponTrait
## M50.4c2 (Auto depth design 5): the Thunderclap's signature. Each volley pops ONE blast
## AHEAD_TILES (2.5 T) ahead along the aim (short of a wall in the way), of the weapon's
## `blast_radius` (1.0 T: 2 T across; Area grows it), its `damage` and KNOCKBACK, through
## Explosion.blast (kind `blast`, the player never pushed). The pellets themselves never blast:
## the field is the clap's. Not a projectile (never in the shot budgets). No random stream.

const AHEAD_TILES := 2.5
const KNOCKBACK := 420.0   ## knockback_cone's base push (~0.5 T on a chaser)

var claps := 0   ## tests: blasts popped


func describe(_at_level: int) -> String:
	return "each volley claps a blast ahead"


func shot(weapon: Weapon, index: int, params: Dictionary) -> void:
	var radius := float(params.get(&"blast_radius", 0.0))
	params[&"blast_radius"] = 0.0
	if index != 0 or radius <= 0.0:
		return
	var n := int(weapon.value(&"pellets"))
	var aim := (params[&"velocity"] as Vector2).normalized()
	if n > 1:
		aim = aim.rotated(deg_to_rad(float(weapon.value(&"spread_deg")) / 2.0))
	var from: Vector2 = params.get(&"origin", Vector2.ZERO)
	var at := from + aim * AHEAD_TILES * Tuning.TILE
	if is_instance_valid(RunState.world):
		var query := PhysicsRayQueryParameters2D.create(from, at, Tuning.LAYER_WORLD)
		var hit: Dictionary = RunState.world.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			at = hit.position
	Explosion.blast(at, radius, float(weapon.value(&"damage")), KNOCKBACK, &"blast",
			StringName("weapon:%s" % weapon.id()), false)
	claps += 1

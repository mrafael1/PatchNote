class_name Shooter
extends Component
## Fires projectiles on a cooldown. One Shooter per entity: anything that wants to
## fire (manual input, later auto-attack) goes through try_fire, so the fire rate
## never stacks.

const PROJECTILE := preload("res://entities/projectile.tscn")

var cooldown := 0.18
var projectile_speed := 900.0
var damage := 1.0
var faction: StringName = &"player"
var muzzle_offset := 26.0

var _ready_in := 0.0


func _physics_process(delta: float) -> void:
	_ready_in = maxf(0.0, _ready_in - delta)


func can_fire() -> bool:
	return _ready_in <= 0.0


## Returns the projectile, or null if on cooldown or at the projectile cap. auto marks
## a shot the weapon fired by itself (auto_attack).
func try_fire(dir: Vector2, auto := false) -> Node:
	if _ready_in > 0.0 or dir == Vector2.ZERO:
		return null
	var shooter := get_parent() as Node2D
	var from := shooter.global_position
	var aim := dir.normalized()
	var muzzle := from + aim * muzzle_offset
	# Never start a projectile inside or behind a wall.
	var query := PhysicsRayQueryParameters2D.create(from, muzzle, Tuning.LAYER_WORLD)
	if not shooter.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		muzzle = from
	var projectile := RunState.spawn(PROJECTILE, muzzle, {
		&"kind": &"player_projectile" if faction == &"player" else &"enemy_projectile",
		&"faction": faction,
		&"velocity": aim * projectile_speed,
		&"damage": damage,
		&"auto_fired": auto,
	})
	if projectile == null:
		return null
	_ready_in = cooldown
	EventBus.projectile_fired.emit(projectile)
	return projectile


## A weapon's shot (PLAN v9 1.4, M44): `pellets` projectiles in an even fan of
## `spread_deg` (no randomness), each with the weapon's pierce, bounces, size, lifetime,
## blast and knockback, credited to "weapon:<id>". Traits edit each pellet's params and
## attach to it. Returns the pellets spawned (empty at the cap). The Loadout owns the
## weapon's cooldown: this never touches _ready_in, and try_fire above is unchanged.
## `damage_mult` (M46, Arsenal's quick-draw) goes into each pellet's params before the
## traits and projectile_fired see them; 1.0 (x * 1.0 is exact) is today's shot.
func fire(weapon: Weapon, dir: Vector2, auto := false, damage_mult := 1.0) -> Array[Node]:
	var out: Array[Node] = []
	if dir == Vector2.ZERO or weapon == null:
		return out
	var shooter := get_parent() as Node2D
	var from := shooter.global_position
	var aim := dir.normalized()
	var muzzle := from + aim * muzzle_offset
	var query := PhysicsRayQueryParameters2D.create(from, muzzle, Tuning.LAYER_WORLD)
	if not shooter.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		muzzle = from
	var n := int(weapon.value(&"pellets"))
	var spread := float(weapon.value(&"spread_deg"))
	var source := StringName("weapon:%s" % weapon.id())
	for i in n:
		var a := 0.0 if n <= 1 else deg_to_rad(-spread / 2.0 + spread * i / (n - 1))
		var params := {
			&"kind": &"player_projectile" if faction == &"player" else &"enemy_projectile",
			&"faction": faction,
			&"velocity": aim.rotated(a) * float(weapon.value(&"speed")),
			&"damage": float(weapon.value(&"damage")) * damage_mult,
			&"auto_fired": auto,
			&"pierce_left": int(weapon.value(&"pierce")),
			&"bounces_left": int(weapon.value(&"bounces")),
			&"size": float(weapon.value(&"size")),
			&"lifetime": float(weapon.value(&"lifetime")),
			&"blast_radius": float(weapon.value(&"blast_radius")) * Tuning.TILE,
			&"knockback": -1.0,
			&"weapon_id": weapon.id(),
			&"source_patch": source,
			&"origin": muzzle,
		}
		for t in weapon.traits:
			t.shot(weapon, i, params)
		var projectile := RunState.spawn(PROJECTILE, muzzle, params)
		if projectile == null:
			continue
		for t in weapon.traits:
			t.spawned(weapon, projectile)
		out.append(projectile)
		EventBus.projectile_fired.emit(projectile)
	return out

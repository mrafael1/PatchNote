extends RuleEdit
## Explosive shots (PLAN v8 1.4): Every shot of yours explodes where it lands.


## The explode-on-hit patch as an edit ("try this"): its own listeners, the same numbers
## (a rule edit never shares a patch's take).
const RADIUS := 70.0
const DAMAGE := 1.0
const KNOCKBACK := 260.0


func enable() -> void:
	_listen(EventBus.projectile_hit, _on_hit)
	_listen(EventBus.projectile_hit_wall, _on_hit_wall)


func _on_hit(projectile: Node, _target: Node, pos: Vector2) -> void:
	_explode(projectile, pos)


func _on_hit_wall(projectile: Node, pos: Vector2, _normal: Vector2) -> void:
	_explode(projectile, pos)


func _explode(projectile: Node, pos: Vector2) -> void:
	if not is_instance_valid(projectile) or projectile.get(&"faction") != &"player":
		return
	Explosion.blast(pos, RADIUS, DAMAGE, KNOCKBACK, &"explosion", id)

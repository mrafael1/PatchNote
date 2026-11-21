extends PatchTake
## Top-down take (PLAN v5 1.2).
## Every player-projectile contact (wall or enemy) sets off a small explosion.

@export var radius := 70.0
@export var damage := 1.0
@export var knockback := 260.0


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
	Explosion.blast(pos, radius, damage, knockback, &"explosion", id)

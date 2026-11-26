extends ProjectileMod
## Cluster's point blank (M50.3b): just before the shell blows (Projectile.explode ->
## blasting), a blast point within `range_px` of the player multiplies the shell's damage by
## `mult`, once. ClusterMod reads the shell's damage after that, so the bomblets carry it too.

var range_px := 2.0 * Tuning.TILE
var mult := 2.0
var applied := false   ## tests


func blasting(p: Node2D, pos: Vector2) -> void:
	if applied:
		return
	var player := p.get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null and player.global_position.distance_to(pos) <= range_px:
		applied = true
		p.damage = float(p.damage) * mult

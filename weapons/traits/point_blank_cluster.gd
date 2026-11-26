extends "res://weapons/traits/point_blank.gd"
## Cluster's point blank (M50.3b, design 4.1, default D10 "a burst near you"): a blast within
## `range` T of the player deals x `mult`, on the shell and (through the shell's damage) on its
## bomblets. The shotgun's steps: x2 / 2 T -> x2.25 / 2.25 T -> x2.5 / 2.5 T -> x3 / 2.5 T.

const PointBlankClusterMod := preload("res://weapons/traits/point_blank_cluster_mod.gd")


func describe(at_level: int) -> String:
	return "point blank: a burst within %s T of you x%s" % [
			WeaponCurve.num(float(value_at(at_level, &"range", 2.0))),
			WeaponCurve.num(float(value_at(at_level, &"mult", 2.0)))]


func spawned(_weapon: Weapon, projectile: Node) -> void:
	var mod := PointBlankClusterMod.new()
	mod.range_px = float(step_value(&"range", 2.0)) * Tuning.TILE
	mod.mult = float(step_value(&"mult", 2.0))
	projectile.add_mod(mod)

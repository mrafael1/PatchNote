class_name VariantDeath
extends RefCounted
## What a variant does when it dies (PLAN v9 1.9, M47), static, called by EnemyWalker only
## when its `variant` is set. `split`: split_count minis of the base scene at half size and
## 1 HP (the HP clamped to at least 1 after every overlay: Auto's x0.7 would round it to 0),
## generation 1 (minis never split), scattered like the v6 enemies_split (that mutation is
## untouched), through RunState.spawn under hard_max_enemies; a refused mini is logged.

const SCATTER := 220.0
const MINI_SCALE := 0.5


static func on_died(enemy: Node2D, variant_id: StringName) -> void:
	var v := EnemyDB.variant(variant_id)
	if v == null or v.on_death != &"split" or int(enemy.get(&"generation")) >= 1:
		return
	var scene := load(EnemyDB.scene_path(v.base)) as PackedScene
	var base_hp := float(Tuning.get("%s_hp" % v.base))
	for i in v.split_count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var mini := RunState.spawn(scene, enemy.global_position + Vector2(side * 4.0, 0), {
			&"generation": 1,
			&"size_mult": float(enemy.get(&"size_mult")) * MINI_SCALE,
			&"hp_mult": 1.0 / maxf(base_hp, 0.001),
			&"min_hp": 1.0,
			&"velocity": Vector2(side, 0) * SCATTER,
		})
		if mini == null:
			RunState.log_event(&"split_refused", {"variant": String(variant_id)})

extends PatchTake
## Top-down take (PLAN v5 1.2).
## More, weaker enemies and a wider view. Rules only.

@export var spawn_rate_factor := 3.0
@export var max_enemies_factor := 3
@export var zoom_factor := 0.75
@export var enemy_hp_factor := 0.6


func apply_rules(rules: WorldRules) -> void:
	rules.spawn_rate_mult *= spawn_rate_factor
	rules.max_enemies *= max_enemies_factor
	rules.camera_zoom *= zoom_factor
	rules.enemy_hp_mult *= enemy_hp_factor

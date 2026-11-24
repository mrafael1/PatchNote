class_name PathOverlay
extends Mutation
## A path's density numbers as a WorldRules overlay (PLAN v9 1.5): the AI layer, owner
## &"path", added by PathRunner when the path's crowd basic is live and removed on a path
## swap. It is not a MutationDB id (built in code, like a loaded RuleEdit) and keeps no
## per-run data. Counts are added ("add to counts", WorldRules), multipliers multiplied.

var def: PathDef


static func make(p_def: PathDef) -> PathOverlay:
	var o := PathOverlay.new()
	o.def = p_def
	o.id = StringName("path_%s_crowd" % p_def.id)
	o.title = "%s crowd" % String(p_def.id).capitalize()
	o.description = "spawns x%.1f, cap x%.1f, enemy HP x%.1f" % [p_def.spawn_rate_mult,
			p_def.max_enemies_mult, p_def.enemy_hp_mult]
	return o


## AI tier: it lives in RunState.ai, never in the stack.
func is_ai_tier() -> bool:
	return true


func apply_rules(r: WorldRules) -> void:
	r.spawn_rate_mult *= def.spawn_rate_mult
	r.max_enemies += roundi(r.max_enemies * (def.max_enemies_mult - 1.0))
	r.enemy_hp_mult *= def.enemy_hp_mult


func on_entity_spawned(_entity: Node) -> void:
	pass


func enable() -> void:
	pass

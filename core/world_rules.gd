class_name WorldRules
extends Resource
## The rules of the world (PLAN 2.1). Plain data, recomputed from base + patch stack.
## Every field must be @export and a value type, or duplicate() will silently drop it.
## Composition convention for Mutation.apply_rules: multiply *_mult and zoom, add to
## counts, only turn bools on, flip gravity_dir. Never assign over another patch's work.

@export var gravity_enabled := false
@export var gravity_dir := Vector2(0, 1)
@export var gravity_strength := 1800.0
@export var jumps := 0
@export var auto_attack := false
@export var spawn_rate_mult := 1.0
@export var max_enemies := 25
@export var enemy_hp_mult := 1.0
@export var camera_zoom := 1.0
@export var projectile_max_bounces := 0      ## player projectiles
@export var projectile_gravity_scale := 0.0  ## player projectiles
@export var time_scale := 1.0
# Big patch rules (PLAN v3 1.3). turn_duration is assigned, not composed: only the
# one big patch in the slot owns it.
@export var time_follows_motion := false
@export var idle_time_scale := 1.0           ## multiplied; time scale while standing still
@export var turn_based := false
@export var turn_duration := 0.25            ## game seconds the world runs per player action


func to_dict() -> Dictionary:
	var d := {}
	for p: Dictionary in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			d[p.name] = get(p.name)
	return d

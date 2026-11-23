class_name WorldRules
extends Resource
## The rules of the world (PLAN 2.1). Plain data, recomputed from base + patch stack.
## Every field must be @export and a value type, or duplicate() will silently drop it.
## Composition convention for Mutation.apply_rules: multiply *_mult and zoom, add to
## counts, *_add and *_deg, only turn bools on, flip gravity_dir. Never assign over another
## patch's work. The one assignment allowed: a gravity rule edit (PLAN v8 1.4) sets
## gravity_dir; the three gravity edits conflict pairwise, so one is live at a time.

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
# Rule edits (PLAN v8 1.4). Each is an exact no-op at its default.
@export var input_rotation_deg := 0.0        ## added; the player's movement input turns (180 = inverted)
@export var player_speed_mult := 1.0
@export var enemy_speed_mult := 1.0
@export var enemy_scale_mult := 1.0          ## enemies' size, live (collision and visual)
@export var enemy_hp_add := 0.0              ## added to an enemy's max HP (after enemy_hp_mult)
@export var enemy_hp_one := false            ## caps an enemy's max HP at 1
@export var wall_bounce := false             ## bodies bounce off walls with a short kick
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

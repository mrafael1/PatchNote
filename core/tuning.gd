extends Node
## Autoload "Tuning". Every non-rule constant lives here (PLAN 12).
## Rule defaults live in core/base_rules.tres; per-mutation numbers on each mutation resource.

# --- World units ---
const TILE := 48.0

# --- Collision layers (bit values; names are set in project.godot) ---
const LAYER_WORLD := 1 << 0
const LAYER_PLAYER_BODY := 1 << 1
const LAYER_ENEMY_BODY := 1 << 2
const LAYER_PLAYER_HURTBOX := 1 << 3
const LAYER_ENEMY_HURTBOX := 1 << 4

# --- Player ---
var player_speed := 330.0
var player_accel := 3200.0
var player_friction := 3600.0
var player_max_hp := 5
var player_hit_invuln := 0.8
var shoot_cooldown := 0.18
var dash_distance := 3.5 * TILE
var dash_time := 0.15
var dash_cooldown := 0.8

# --- Enemies ---
var chaser_speed := 190.0
var chaser_hp := 3.0
var chaser_contact_damage := 1.0
var contact_range := 40.0
var enemy_separation_radius := 36.0
var chaser_hop_cooldown := 0.5
var chaser_headroom := 3.7 * TILE  # free space a chaser needs above it to hop up
var stuck_time := 2.0
var wander_time := 1.5

# --- Gravity / jump (starting values, tuned at the gravity gate) ---
var jump_velocity := 790.0        # apex about 3.6 tiles; ledges are 3 tiles apart
var air_jump_factor := 0.85
var landing_min_speed := 250.0   # slower touchdowns do not count as a landing event
var fall_gravity_mult := 1.4
var terminal_fall_speed := 900.0
var jump_cut_factor := 0.4
var coyote_time := 0.10
var jump_buffer := 0.10

# --- Projectiles ---
var projectile_speed := 900.0
var projectile_lifetime := 3.0
var bounce_restitution := 0.8

# --- Hard caps (enforced by RunState.spawn) ---
var hard_max_enemies := 150
var hard_max_projectiles := 200

# --- Transition ---
var grace_time := 1.5

# --- Director ---
var first_prompt_kills := 15
var prompt_kills_step := 10
var prompt_min_gap := 60.0
var prompt_max_gap := 150.0
var force_gravity_at_prompt := 2  # 0 disables the mandatory gravity card
var reverts_per_run := 2

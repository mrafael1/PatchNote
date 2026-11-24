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
# The campaign's other dashes (PLAN v8 6.8, fork_dash; owner G13). Classic is the three above.
var grapple_range := 7.0 * TILE       ## the hook's box cast reaches a wall this far
var grapple_cone_deg := 12.0          ## tried at 0, +-1x, +-2x this angle off the move direction
var grapple_speed := 1400.0           ## the pull, px/s; it lands 2 px short of the wall, at rest
var grapple_cooldown := 1.1
var grapple_miss_cooldown := 0.4
var grapple_latch := 0.3              ## under gravity, hangs this long on a side wall
var grapple_aims := false             ## true: the hook follows the aim, not the move direction
var teleport_distance := 4.0 * TILE   ## steps back by 8 px down to one tile to find a free spot
var teleport_cooldown := 1.3
var teleport_iframes := 0.25

# --- Enemies ---
# Walkers read "<archetype>_<name>": chaser_* and tank_*.
var chaser_speed := 190.0
var chaser_hp := 3.0
var chaser_contact_damage := 1.0
var chaser_hop_cooldown := 0.5
var chaser_knockback_scale := 1.0
var tank_speed := 105.0
var tank_hp := 12.0
var tank_contact_damage := 1.0
var tank_hop_cooldown := 2.0
var tank_knockback_scale := 0.2
# Bomber (PLAN v5 3): walks in, stops near the player, telegraphs, blows up (hurts
# everyone in range, enemies too) and dies. Shipped by the enemy_bomber change.
var bomber_speed := 165.0
var bomber_hp := 2.0
var bomber_contact_damage := 0.0  # it hurts by its blast only
var bomber_hop_cooldown := 0.6
var bomber_knockback_scale := 0.8
# Centre distance at which it stops and lights its fuse. Inside the blast's reach (radius
# plus the 12 px body margin), so standing still gets hit; 0.6 s is time to step away.
var bomber_trigger_range := 1.3 * TILE
var bomber_windup := 0.6
var bomber_blast_radius := 1.6 * TILE
var bomber_campaign_blast_radius := 2.0 * TILE   # (campaign, owner G13: a bit bigger)
var bomber_death_fuse := 0.3   # (campaign: a killed bomber blinks this long, then blows)
var bomber_blast_damage := 1.0
var bomber_blast_knockback := 360.0
# The lancer (PLAN v6 3): walks in, stops, telegraphs a line, then charges along it
# through everyone on it (enemies take its hit too, enemy faction, like the bomber).
var lancer_speed := 140.0
var lancer_hp := 3.0
var lancer_contact_damage := 1.0
var lancer_hop_cooldown := 0.6
var lancer_knockback_scale := 0.6
var lancer_trigger_range := 5.5 * TILE
var lancer_windup := 0.7
var lancer_charge_speed := 720.0
var lancer_charge_distance := 8.0 * TILE
var lancer_recover := 1.0
var lancer_charge_damage := 1.0
var shooter_speed := 150.0
var shooter_hp := 2.0
var shooter_fire_interval := 1.8
var shooter_windup := 0.35        # the telegraph before each shot (PLAN v5 2.2); inside the interval
var contact_warn_range := 1.5     # tiles beyond contact reach at which a walker shows its red rim
var shooter_projectile_speed := 320.0
var shooter_near := 5.0 * TILE    # closer than this: back off
var shooter_far := 8.0 * TILE     # farther than this: approach
var shooter_range := 13.0 * TILE
var enemy_accel := 1400.0         # low enough that knockback is visible
var contact_range := 40.0
var player_hit_knockback := 320.0
var enemy_separation_radius := 36.0
var avoid_probe := 1.5 * TILE     # how far ahead walkers look for walls without gravity

# --- Spawner ---
var spawn_interval_start := 1.6
var spawn_interval_end := 1.0
var spawn_ramp_time := 120.0
var spawn_min_distance := 8.0 * TILE
var spawn_shooter_chance := 0.25
var spawn_tank_chance := 0.08   # M30: 0.15 cut the all-shipped mortal median by 27% (PLAN v5 4.9)
var spawn_tank_delay := 30.0
var spawn_bomber_chance := 0.12
var spawn_bomber_delay := 40.0
var spawn_lancer_chance := 0.1
var spawn_lancer_delay := 35.0
## A new save spawns only these (PLAN v5 2.3, read through Unlocks.enemies from M28).
var starter_enemies: Array[StringName] = [&"chaser", &"shooter"]
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

# --- Hop (jump on the height axis, used when there is no gravity) ---
var hop_time := 0.35
var hop_height := 44.0            # visual only: how far the sprite lifts at the apex
var hop_impact_speed := 400.0     # impact reported by player_landed after a hop

# --- Auto attack ---
var auto_attack_range := 12.0 * TILE

# --- Camera (presentation) ---
var camera_lookahead := 0.12      # share of the view the camera leads toward the aim
var camera_lookahead_lerp := 4.0

# --- Projectiles ---
var projectile_speed := 900.0
var projectile_lifetime := 3.0
var bounce_restitution := 0.8
var projectile_knockback := 240.0

# --- Hard caps (enforced by RunState.spawn) ---
var hard_max_enemies := 150
var hard_max_projectiles := 200
var max_split_generation := 1   # enemies at this generation never split again
var hard_max_pickups := 60       # PLAN v9 1.6 (M45a): pickups' own cap (gems merge first)

# --- Pickups (PLAN v9 1.6, M45a) ---
var pickup_pull_gem := 3.0 * TILE      # gems fly to the player from this close
var pickup_pull_other := 0.6 * TILE    # other pickups only from this close
var pickup_fly_speed := 600.0          # px/s while pulled
var pickup_take_radius := 0.5 * TILE   # the player takes it within this
var pickup_lifetime := 14.0            # seconds (gems never expire)
var pickup_blink := 3.0                # blinks for its last seconds

# --- Transition ---
var wall_bounce_kick := 240.0       # rule edit wall_bounce (PLAN v8 1.4): px/s pushed off the wall
var wall_bounce_restitution := 0.6  # share of the speed into the wall that comes back
var wall_bounce_cooldown := 0.3     # game seconds between two bounces of one body
var edit_gravity_grace := 1.5       # no contact damage this long after a gravity edit flips (M42 E2: 0.5 -> 1.5)
var health_added_grace := 2.5    # campaign: no bite this long after the AI adds `health` (M39.2)
var grace_time := 1.5             # enemies deal no damage for this long after a gravity change
var transition_long := 0.8        # mode switch; 0 applies instantly (tests)
var transition_short := 0.3
var toast_time := 2.2             # how long the AI line stays up after a patch

# --- Director ---
# Pacing for the ~3 min v0.0 run (PLAN v5 2.1), retuned at M28 from bot sweeps (16 seeds,
# --fresh): 3 small prompts, then the 45 s release-candidate wave.
# One meter since the owner's feedback after M34 (2026-11-22): time fills it in
# prompt_max_gap, each counted kill adds prompt_kill_seconds, and a prompt never opens
# sooner than the minimum gap. Bot sweeps (16 seeds): prompts at 37/83/129 s (the old
# schedule was 40/88/136), invincible runs 174 s, mortal fresh 104.5 s (was 108.9; a 65 s
# first meter gave 88 s: the first prompt's heal came too late). A player who kills
# faster than the bot gets the patches sooner.
var first_prompt_min_gap := 20.0  # game seconds before the first prompt may open
var prompt_min_gap := 20.0
var first_prompt_max_gap := 55.0  # the first meter: few enemies yet, so a shorter one
var prompt_max_gap := 80.0        # time alone fills the meter in this long
var prompt_kill_seconds := 1.0    # each counted kill is worth this much waiting
var prompt_incoming_at := 0.85    # the HUD announces the patch from this much meter
var prompts_per_run := 3
var offer_size := 3
var hotfix_heal := 1.0            # HP restored by every applied patch
var prompt_input_delay := 0.5     # the prompt ignores input for this long after opening
# Rollbacks (PLAN v4 1.3, option D): AI patches only. Parked in v5 (PLAN v5 1.3): the
# run starts with no charge; only tests grant charges.
var rollback_charges_start := 0
var rollback_charges_per_stage := 1

# --- Run loop ---
var stage_clear_time := 2.5       # PLAN v6 4: the beat between two stages (field cleared)
var stage_start_grace := 1.5      # enemies deal no damage this long into the next stage
var rc_duration := 45.0           # the "release candidate" wave after the last prompt
var rc_spawn_rate := 1.6          # spawner phase multipliers during that wave
var rc_spawn_cap := 1.5
var report_delay := 1.0           # game time between the end of the run and the report
# The first builds miss a basic (PLAN v5 4.8): their run is a short smoke test with no
# prompts, survived when this much game time has passed.
var smoke_test_duration := 20.0
# Without movement the AI gives up early (owner, 2026-11-22): it says so at this much
# game time, with most of the countdown still on the clock, and the run ends once the
# line has had smoke_stop_read seconds on screen.
var smoke_stop_time := 5.0
var smoke_stop_read := 2.0

# --- Dev session (PLAN v5 4) ---
var session_cards := 3            # cards in a 3-changes session
var agenda_min_available := 2     # a session showing at least this many cards has one agenda card
# 0 since the owner feedback after M34: questions are the player's (big features only);
# the AI builds the in-run patches itself (DevSession IMPLEMENT).
var ai_own_ship_every := 0        # every Nth session the AI also answers a fork; 0 = never
# The AI answers a fork only when this many ready non-mockup forks are left after the
# pick, so it never takes the player's last question (PLAN v6 1.2, M31).
var ai_fork_min_ready := 2
# The Rework card shows once this many forks are answered and the shelf is not empty
# (PLAN v6 1.2).
var rework_after_forks := 2

# --- Taste (adaptive offers) ---
var agenda_cards := 1             # cards per offer the AI picks against the player's taste
var agenda_cards_unrated := 2     # after a run whose report was not rated: the AI takes free rein

# --- Big patches (PLAN v3) ---
var motion_smoothing := 0.1       # B1: real seconds for the motion factor to follow the player
var motion_pulse := 0.15          # B1: real seconds of full-speed time after a shot or dash
var grid_shot_tiles := 2          # B2: tiles an enemy shot moves per turn
var grid_shot_turns := 8          # B2: turns an enemy shot lives
# B2: turns a grid shooter waits after firing before it may aim again. It fires, waits
# these turns, aims for one: a shot every 7 turns, 1.75 s of game time at a 0.25 s turn,
# close to shooter_fire_interval (1.8 s) / turn_duration.
var grid_shooter_cooldown := 6

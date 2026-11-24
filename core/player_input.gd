class_name PlayerInput
extends Node
## The only thing the player entity reads for control (PLAN 3). Gameplay never calls Input.
## HumanInput fills it from the InputMap; BotInput fills it from a simple policy.

var move := Vector2.ZERO        ## desired movement, length 0..1
var aim_dir := Vector2.RIGHT    ## unit vector; a direction, never a screen position
var fire := false               ## held
var dash_pressed := false       ## true for one physics tick
var jump_pressed := false       ## true for one physics tick
var jump_held := false
var wait_pressed := false       ## true for one physics tick; passes a turn under B2
var switch_step := 0            ## -1 / +1 for one physics tick: the previous / next weapon (M44)


func _init() -> void:
	# Fill the values before the entity that reads them runs its own physics tick.
	process_physics_priority = -10
	# Read even while the tree is paused: under B2 the world waits paused for the
	# player's next action (PLAN v3 section 3). The player itself stays paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Called after a transition: anything held must be released and pressed again.
func require_fresh_press() -> void:
	pass


## Position the aim is measured from: the entity this provider is attached to.
func origin() -> Vector2:
	var p := get_parent() as Node2D
	return p.global_position if p else Vector2.ZERO

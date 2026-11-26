extends Node
## The well weapon (PLAN v9 1.4, M45b): a passive on the player. Every enemy the player kills
## (DamageInfo faction `player`, the gems' filter: a bomber's fuse blast leaves nothing, a
## bomber the player killed blasts as the player, so its blast kills do) leaves a pull field
## (well_weapon_field.gd, the v6 well patch's field) at its position for `life` seconds
## (1.5). Rank 2 `gem_magnet`: the fields pull gems too. Rank 3 `teeth`: they bite, `dps`
## damage a second (1), credited "weapon:well". Deterministic: no random stream.
## At most MAX_FIELDS live at once (PLAN v9 R6's fallback, M45b D8): a kill over the cap leaves
## none. Without it the Auto bench ran away: each kill's hit stop slows game time, teeth kills
## leave more fields, and 1852 live fields on average held it at 1 fps.

const Field := preload("res://weapons/well_weapon_field.gd")
const MAX_FIELDS := 12

var weapon_id: StringName = &"well"
var life := 1.5
var dps := 1.0
var gem_magnet := false
var teeth := false
var fields := 0          ## tests: fields left
var capped := 0          ## tests: kills over the cap (no field)
## The live list is kept on RunState.world (meta LIVE_META), not on this node: a rank-up
## (Loadout._rank_to -> _attach) frees this node and builds a new one while the old fields keep
## running, so a per-node list would let 24 live (M45b review). It dies with the world.
const LIVE_META := &"well_weapon_fields"


## Takes the weapon's numbers at its rank (Loadout._attach, before the traits).
func configure(w: Weapon) -> void:
	weapon_id = w.def.id
	life = float(w.value(&"cooldown"))
	dps = float(w.value(&"damage"))


## M50.4a review: the `boost` filler (Loadout._apply_mods) re-reads the numbers in place, the
## node kept. Fields already on the ground keep the bite they were made with.
func reconfigure(w: Weapon) -> void:
	life = float(w.value(&"cooldown"))
	dps = float(w.value(&"damage"))


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _exit_tree() -> void:
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)


func _on_enemy_killed(enemy: Node, info: RefCounted) -> void:
	if (info as DamageInfo).faction != &"player" or not enemy is Node2D:
		return
	if not is_instance_valid(RunState.world):
		return
	var world: Node = RunState.world
	## untyped: it may hold freed fields until pruned
	var live: Array = (world.get_meta(LIVE_META, []) as Array).filter(
			func(n: Variant) -> bool: return is_instance_valid(n) and not (n as Node).is_queued_for_deletion())
	world.set_meta(LIVE_META, live)
	if live.size() >= MAX_FIELDS:
		capped += 1
		return
	var f: Node2D = Field.new()
	f.life = life
	f.gem_pull = gem_magnet
	f.teeth = teeth
	f.bite = dps * Field.BITE_EVERY
	f.source = StringName("weapon:%s" % weapon_id)
	f.position = (enemy as Node2D).global_position
	RunState.world.add_child.call_deferred(f)
	live.append(f)
	fields += 1

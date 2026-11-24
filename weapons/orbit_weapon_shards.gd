extends "res://mutations/orbit/orbit_shards.gd"
## The orbit weapon (PLAN v9 1.4): the v6 patch's shards, as a passive weapon. Radius 2
## tiles (the patch keeps 1.5), shard count from the weapon's `pellets`, credited to
## "weapon:orbit". Its Component.source_patch stays empty, so RunState.snapshot() never
## lists it. Rank 2 `flare`: a dash doubles the radius for FLARE_SECONDS. Rank 3 `guard`:
## a shard that touches an enemy shot eats it and is gone GUARD_SECONDS.

const WEAPON_RADIUS := 2.0 * Tuning.TILE
const FLARE_SECONDS := 0.6
const GUARD_SECONDS := 1.0
const GUARD_REACH := 4.0   ## an enemy shot's half size, added to the shard's

var weapon_id: StringName = &""
var flare := false
var guard := false
var eaten := 0                 ## tests: enemy shots eaten
var _flare_until := -1.0
var _gone_until: Array[float] = []


func _init() -> void:
	radius = WEAPON_RADIUS


func _ready() -> void:
	super()
	_gone_until.resize(shard_count)
	_gone_until.fill(-1.0)
	EventBus.player_dashed.connect(_on_dashed)


func _exit_tree() -> void:
	if EventBus.player_dashed.is_connected(_on_dashed):
		EventBus.player_dashed.disconnect(_on_dashed)


func _on_dashed() -> void:
	if flare:
		_flare_until = RunState.game_time + FLARE_SECONDS


func flared() -> bool:
	return RunState.game_time < _flare_until


func _physics_process(delta: float) -> void:
	radius = WEAPON_RADIUS * (2.0 if flared() else 1.0)
	super(delta)
	if not guard or RunState.rules.turn_based:
		return
	for i in _shards.size():
		_shards[i].visible = shard_active(i)
		if not shard_active(i):
			continue
		var pos := shard_position(i)
		for s in get_tree().get_nodes_in_group(&"enemy_projectile"):
			var shot := s as Node2D
			if shot == null or shot.is_queued_for_deletion():
				continue
			if pos.distance_to(shot.global_position) > SHARD_HALF + GUARD_REACH:
				continue
			shot.call(&"despawn")
			eaten += 1
			_gone_until[i] = RunState.game_time + GUARD_SECONDS
			_shards[i].visible = false
			break


func shard_active(i: int) -> bool:
	return i >= _gone_until.size() or RunState.game_time >= _gone_until[i]


func damage_source() -> StringName:
	return StringName("weapon:%s" % weapon_id)

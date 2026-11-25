class_name Pickup
extends Node2D
## Something on the floor the player takes by walking over it (PLAN v9 1.6, M45a): Auto's
## gems now; Survival's weapons, ammo, heal and battery reuse it (M47). Registered as the
## RunState kind `pickup` (its own cap, Tuning.hard_max_pickups). Gems never expire and fly
## to the player within 3 T; the others live 14 s, blink for their last 3 s and are pulled
## only from 0.6 T. Only the player takes one (no physics layers: a distance check).
## M47 (Survival): a weapon pickup carries its rank and ammo; a crate never expires; an
## `untouchable` one (the weapon swapped out at the player's feet) ignores the player until
## it is UNTOUCHABLE_FOR old and the player has once been farther than the take radius.

signal taken(pickup: Pickup)

const KINDS: Array[StringName] = [&"gem", &"weapon", &"ammo", &"heal", &"battery"]
const GEM_GROUP := &"gem"
const GEM_COLOR := Color(0.45, 0.95, 1.0)
const OTHER_COLOR := Color(1.0, 0.85, 0.35)
const CRATE_COLOR := Color(0.75, 0.55, 0.3)
const UNTOUCHABLE_FOR := 0.5

var kind: StringName = &"pickup"
var pickup_kind: StringName = &"gem"
var value := 1                    ## a gem's worth (Auto's level meter)
var weapon_id: StringName = &""   ## a weapon pickup's weapon (M47)
var serial := 0                   ## spawn order (the gem merge takes the oldest; no instance ids)
var age := 0.0
var crate := false                ## M47: a Survival crate (never expires, drawn as a box)
var rank := 1                     ## M47: a weapon pickup's rank
var ammo_left := -1               ## M47: a dropped weapon keeps its ammo (-1: full)
var untouchable := false          ## M47: see the header

var _player: Node2D
var _skin_frame := -1   ## the Pixel preview's last idle frame (presentation only)


func _ready() -> void:
	if is_gem():
		add_to_group(GEM_GROUP)
	RunState.register_entity(self, kind)
	queue_redraw()


func is_gem() -> bool:
	return pickup_kind == &"gem"


func pull_radius() -> float:
	return Tuning.pickup_pull_gem if is_gem() else Tuning.pickup_pull_other


func _physics_process(delta: float) -> void:
	age += delta
	if not is_gem() and not crate:
		if age >= Tuning.pickup_lifetime:
			queue_free()
			return
		var left := Tuning.pickup_lifetime - age
		modulate.a = 0.3 if left <= Tuning.pickup_blink and fmod(age * 8.0, 2.0) < 1.0 else 1.0
	var p := _find_player()
	if p == null:
		return
	var d := global_position.distance_to(p.global_position)
	if untouchable:
		if age >= UNTOUCHABLE_FOR and d > Tuning.pickup_take_radius:
			untouchable = false
		return
	if d > Tuning.pickup_take_radius and d <= pull_radius():
		global_position = global_position.move_toward(p.global_position, Tuning.pickup_fly_speed * delta)
		d = global_position.distance_to(p.global_position)
	if d <= Tuning.pickup_take_radius:
		take()


## The player takes it: the signals, then it is gone.
func take() -> void:
	if is_queued_for_deletion():
		return
	taken.emit(self)
	EventBus.pickup_taken.emit(pickup_kind, weapon_id)
	queue_free()


func _find_player() -> Node2D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _player == null:
		return null
	var health: Variant = _player.get(&"health")
	if health is Health and (health as Health).dead:
		return null
	return _player


## The Pixel preview's idle (PLAN 1.7): a redraw when the 2-frame idle flips.
func _process(_delta: float) -> void:
	if Skins.current != null:
		var f := Skins.current.idle_frame(_skin_id(), RunState.real_time())
		if f != _skin_frame:
			_skin_frame = f
			queue_redraw()


func _skin_id() -> StringName:
	return &"crate" if crate else pickup_kind


func _draw() -> void:
	if Skins.current != null and Skins.current.has(_skin_id()):
		var id := _skin_id()
		Skins.current.draw(self, id, Vector2.ZERO, ArtSkin.BODY_SCALE, Skins.current.idle_frame(id, RunState.real_time()))
		return
	if crate:
		draw_rect(Rect2(-11, -11, 22, 22), CRATE_COLOR)
		draw_rect(Rect2(-11, -11, 22, 22), Color.BLACK, false, 2.0)
		return
	var r := 7.0 if is_gem() else 10.0
	var c := GEM_COLOR if is_gem() else OTHER_COLOR
	draw_colored_polygon(PackedVector2Array([Vector2(0, -r), Vector2(r * 0.7, 0), Vector2(0, r),
			Vector2(-r * 0.7, 0)]), c)

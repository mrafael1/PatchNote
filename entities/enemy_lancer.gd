extends EnemyWalker
## The lancer (PLAN v6 3): a walker with a charge. Within Tuning.lancer_trigger_range and with a
## clear line it stops and telegraphs the line it will take for Tuning.lancer_windup
## (it grows and flashes, and the line shows), then charges along it at
## Tuning.lancer_charge_speed for up to Tuning.lancer_charge_distance or until a wall.
## Everyone it meets on the way takes Tuning.lancer_charge_damage once per charge: the
## player and other enemies alike (enemy faction, as the bomber's blast). Then it stands
## for Tuning.lancer_recover and walks again. Its walking contact hurts as a chaser's.

enum Lance { WALK, WINDUP, CHARGE, RECOVER }
var lance: Lance = Lance.WALK   ## lancer: where it is in its attack
var charges := 0                ## lancer: charges started (tests)
var _lance_left := 0.0
var _lance_dir := Vector2.ZERO
var _lance_hit := {}            ## nodes hit this charge
var _lance_line: LanceLine


## The line a lancer telegraphs or charges along (tests): unit vector, zero when walking.
func lance_dir() -> Vector2:
	return _lance_dir if lance != Lance.WALK else Vector2.ZERO


## Lancer: telegraph, charge, recover. Returns true while it handles the tick (the walk
## logic is skipped).
func _attack_step(delta: float, to_player: Vector2, distance: float) -> bool:
	match lance:
		Lance.WALK:
			if distance > Tuning.lancer_trigger_range:
				return false
			var player := EnemyCommon.find_player(self)
			if player and EnemyCommon.ray_hits_world(self, global_position, player.global_position):
				return false
			lance = Lance.WINDUP
			_lance_left = Tuning.lancer_windup
			_lance_dir = to_player.normalized()
			_show_line(true)
		Lance.WINDUP:
			_lance_left -= delta
			var u := clampf(1.0 - _lance_left / maxf(Tuning.lancer_windup, 0.001), 0.0, 1.0)
			visual.telegraph = u
			_lance_line.strength = u
			if _lance_left <= 0.0:
				lance = Lance.CHARGE
				charges += 1
				_lance_hit.clear()
				visual.telegraph = 0.0
				_show_line(false)
				var speed := Tuning.lancer_charge_speed
				mover.dash(_lance_dir * speed, Tuning.lancer_charge_distance / speed)
		Lance.CHARGE:
			_charge_hits()
			if not mover.is_dashing() or is_on_wall():
				mover.stop()
				lance = Lance.RECOVER
				_lance_left = Tuning.lancer_recover
		Lance.RECOVER:
			_lance_left -= delta
			if _lance_left <= 0.0:
				lance = Lance.WALK
	if lance != Lance.CHARGE:
		mover.wish = Vector2.ZERO
	visual.rim = 0.0
	return true


func _show_line(on: bool) -> void:
	if _lance_line == null:
		_lance_line = LanceLine.new()
		_lance_line.width = 8.0
		_lance_line.z_index = -1
		add_child(_lance_line)
	_lance_line.visible = on
	_lance_line.points = PackedVector2Array([Vector2.ZERO, _lance_dir * Tuning.lancer_charge_distance])
	_lance_line.strength = 0.0


## Everyone within reach of the charging lancer takes its hit, once per charge.
func _charge_hits() -> void:
	for group: StringName in [&"player", &"enemy"]:
		for n in get_tree().get_nodes_in_group(group):
			var other := n as Node2D
			if other == self or other == null or _lance_hit.has(other):
				continue
			var other_half := 15.0
			if other.has_method(&"body_half"):
				other_half = other.call(&"body_half")
			elif other.get(&"half_width") != null:
				other_half = other.get(&"half_width")
			if global_position.distance_to(other.global_position) > body_half() + other_half + 6.0:
				continue
			var other_mover := Component.find(other, Mover) as Mover
			if other_mover and other_mover.is_airborne():
				continue
			_lance_hit[other] = true
			var hp := Component.find(other, Health) as Health
			if hp and hp.take(DamageInfo.make(Tuning.lancer_charge_damage, &"charge", &"enemy", global_position)):
				if other_mover:
					other_mover.knockback(_lance_dir.orthogonal() * signf(_lance_dir.orthogonal().dot(
							other.global_position - global_position) + 0.001) * Tuning.player_hit_knockback)

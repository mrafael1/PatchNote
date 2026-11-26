extends ProjectileMod
## Sticky (launcher rank 2) and implode (rank 3: `implode` set): the shell stops on its
## first contact, follows an enemy it hit, and blasts FUSE seconds (game time) later at
## RADIUS_MULT x its radius. With implode, IMPLODE_LEAD before the blast every enemy in
## range is pulled in (~0.6 tile). M50.3a: the radius multiplier and the pull are per instance
## (sticky's and implode's levels on the deep curve; the consts are level 1, the classic curve),
## and the blast goes through Projectile.explode (its mods' blasted() run before the despawn).

const FUSE := 0.6
const RADIUS_MULT := 1.2
const IMPLODE_LEAD := 0.15
const IMPLODE_PULL := 455.0   ## the impulse that moves a chaser ~0.6 tile (test_weapons)

var implode := false
var radius_mult := RADIUS_MULT  ## M50.3a: sticky's level (1.2 -> 1.5)
var pull := IMPLODE_PULL        ## M50.3a: implode's level (455 -> 910)
var stuck := false
var pulled := 0                 ## tests: enemies pulled in
var _target: Node2D
var _offset := Vector2.ZERO
var _blast_at := -1.0
var _pulled_once := false


func steer(p: Node2D, _delta: float) -> void:
	if not stuck:
		return
	if is_instance_valid(_target) and not _target.is_queued_for_deletion():
		p.global_position = _target.global_position + _offset
	var radius: float = p.blast_radius * radius_mult
	if implode and not _pulled_once and RunState.game_time >= _blast_at - IMPLODE_LEAD:
		_pulled_once = true
		for e in p.get_tree().get_nodes_in_group(&"enemy"):
			var enemy := e as Node2D
			if enemy == null or enemy.is_queued_for_deletion():
				continue
			var inward := p.global_position - enemy.global_position
			if inward.length() > radius + Explosion.BODY_MARGIN or inward.length() < 1.0:
				continue
			var mover := Component.find(enemy, Mover) as Mover
			if mover:
				mover.knockback(inward.normalized() * pull)
				pulled += 1
	if RunState.game_time >= _blast_at:
		p.explode(p.global_position, radius)


func hit_entity(p: Node2D, target: Node, pos: Vector2) -> bool:
	if not stuck:
		_stick(p, pos)
		_target = target as Node2D
		if _target:
			_offset = pos - _target.global_position
	return true


func hit_wall(p: Node2D, pos: Vector2, _normal: Vector2) -> bool:
	if not stuck:
		_stick(p, pos)
	return true


func _stick(p: Node2D, pos: Vector2) -> void:
	stuck = true
	p.hold()
	p.global_position = pos
	_blast_at = RunState.game_time + FUSE

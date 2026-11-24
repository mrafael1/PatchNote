extends EnemyWalker
## The bomber (PLAN v5 3): a walker with no contact damage and no rim. Within
## Tuning.bomber_trigger_range it stops and telegraphs for Tuning.bomber_windup (it grows
## and flashes), then blows up: everyone in Tuning.bomber_blast_radius takes the blast,
## the player and other enemies alike, and the bomber is gone. A lit fuse always ends in
## its blast. Outside a session, blowing itself up is not a kill and shooting it first
## is a kill with no blast. In a campaign session (owner G13) a bomber blows up however
## it dies: it blinks for Tuning.bomber_death_fuse, then blasts at
## Tuning.bomber_campaign_blast_radius (its fuse blast too). What a blast it set off by
## being shot kills is the player's; a fuse blast's victims are not (enemy faction: no
## kill count, no prompt pacing). A blast that kills a hurt bomber sets it off in turn
## (each bomber blows once), and no blast hurts the player once the run is over.

var _fuse_left := -1.0   ## bomber: < 0 while the fuse is not lit
var _blown := false
var _dying := false      ## bomber, campaign: killed, its death fuse is burning
var _death_faction: StringName = &"enemy"   ## who its death blast's victims belong to
var fuses := 0           ## bomber: telegraphs started (tests)


func is_fuse_lit() -> bool:
	return _fuse_left >= 0.0


func _before_tick(delta: float) -> bool:
	if _dying:
		_tick_death_fuse(delta)
		return true
	return false


func _shows_rim() -> bool:
	return false


## Bomber: lights the fuse in range (and with a clear line), then stands still until it
## blows. Returns true while it handles the tick (the walk logic is skipped).
func _attack_step(delta: float, _to_player: Vector2, distance: float) -> bool:
	if _fuse_left < 0.0:
		if distance > Tuning.bomber_trigger_range:
			return false
		var player := EnemyCommon.find_player(self)
		if player and EnemyCommon.ray_hits_world(self, global_position, player.global_position):
			return false
		_fuse_left = Tuning.bomber_windup
		fuses += 1
	mover.wish = Vector2.ZERO
	visual.rim = 0.0
	_fuse_left -= delta
	visual.telegraph = clampf(1.0 - _fuse_left / maxf(Tuning.bomber_windup, 0.001), 0.0, 1.0)
	if _fuse_left <= 0.0:
		blow_up()
	return true


## The bomber's blast radius: bigger in a campaign session (owner G13), the v6 one outside.
static func blast_radius() -> float:
	return Tuning.bomber_campaign_blast_radius if RunState.session != null else Tuning.bomber_blast_radius


## The bomber's blast: the player and every other enemy in range. It leaves the enemy
## group first, so the blast never counts it and it dies without a kill. faction is who
## its victims belong to: the enemy for a fuse blast, the killer for a death blast.
func blow_up(faction: StringName = &"enemy") -> void:
	if _blown or is_queued_for_deletion():
		return
	_blown = true
	_fuse_left = -1.0
	remove_from_group(&"enemy")
	var pos := global_position
	var radius := blast_radius()
	Explosion.blast(pos, radius, Tuning.bomber_blast_damage, Tuning.bomber_blast_knockback,
			&"explosion", &"", true, faction)
	var spare_player := RunState.session != null and _run_over()
	for p in get_tree().get_nodes_in_group(&"player"):
		var target := p as Node2D
		if spare_player:
			break   # campaign: a blast set off by the winning kill cannot hurt after the win
		if target.global_position.distance_to(pos) <= radius + Explosion.BODY_MARGIN:
			var hp := Component.find(target, Health) as Health
			if hp:
				hp.take(DamageInfo.make(Tuning.bomber_blast_damage, &"explosion", &"enemy", pos))
	queue_free()


## True once the run loop this bomber plays in has left PLAY (won, died, stopped).
## Untyped on purpose: naming RunLoop here makes a load cycle (it preloads the enemies).
func _run_over() -> bool:
	var n := get_parent()
	while n != null:
		var loop: Variant = n.get(&"run_loop")
		if loop is Node:
			return (loop as Node).get(&"phase") != &"play"   # RunLoop.PLAY
		n = n.get_parent()
	return false


func _on_died(info: DamageInfo) -> void:
	if RunState.session != null and not _blown and not _dying:
		# Campaign (owner G13): a killed bomber blinks briefly, then blows.
		_dying = true
		_death_faction = &"player" if info != null and info.faction == &"player" else &"enemy"
		remove_from_group(&"enemy")   # no second kill, no blast hit, no lancer hit
		set_deferred(&"collision_layer", 0)   # shots pass through a dead bomber
		_fuse_left = minf(_fuse_left, Tuning.bomber_death_fuse) if _fuse_left >= 0.0 \
				else Tuning.bomber_death_fuse
		mover.wish = Vector2.ZERO
		visual.rim = 0.0
		return
	super(info)


## Campaign: a killed bomber's death fuse. It stands, blinks as a lit fuse does, then
## its blast goes off with the killer's faction.
func _tick_death_fuse(delta: float) -> void:
	mover.wish = Vector2.ZERO
	_fuse_left -= delta
	visual.telegraph = clampf(1.0 - _fuse_left / maxf(Tuning.bomber_windup, 0.001), 0.0, 1.0)
	if _fuse_left <= 0.0:
		blow_up(_death_faction)

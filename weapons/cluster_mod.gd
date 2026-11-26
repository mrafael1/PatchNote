extends ProjectileMod
## Cluster's burst (M50.3b, Arcade through S10 design 4.1): on each blast of the shell
## (Projectile.explode -> blasted, after its blast and contact event, before its despawn) it
## throws `count` bomblets from the blast point at the flight angle + k x 360 / count degrees
## (k = 0.., no RNG). A bomblet is a small player shot (BOMBLET_SPEED for BOMBLET_LIFE s, then
## it pops: Projectile.pop_at_end) with a BOMBLET_BLAST blast of BOMBLET_MULT x the shell's
## damage (point blank already applied), credited to the same weapon. A bomblet that starts
## inside the body the shell stuck to blows on it at once (the engine's ray from inside): on a
## lone target the burst lands on it, in a pack it spreads. Bomblets go through
## RunState.spawn as player shots, so the player budget (140) refuses them and never the
## enemies' 60; they carry no mods. Attached by Weapon.attach (player weapons with a burst),
## never by Shooter.fire. Each burst logs `cluster_burst` {bomblets, refused} (telemetry only).

const PROJECTILE := preload("res://entities/projectile.tscn")
## M50.3b bench (test_cluster): 0.5 in the design; 0.2 with the shell's base damage 3.9 puts
## Cluster at 0.74-0.81 x Prism on one tank and 1.26-1.44 x on a pack of 8 (ranks 5, 9, 13).
const BOMBLET_MULT := 0.2
const BOMBLET_SPEED := 1.5 * Tuning.TILE / 0.2
const BOMBLET_LIFE := 0.2
const BOMBLET_BLAST := 0.6 * Tuning.TILE
const BOMBLET_SIZE := 0.5
const BOMBLET_SKIN := &"shot_ball_player"

var count := 5
var angle := 0.0                 ## the shell's flight angle (kept while it is stuck)
var bomblets: Array[Node] = []   ## tests: the burst's bomblets
var refused := 0
var _burst := false


func steer(p: Node2D, _delta: float) -> void:
	var v: Vector2 = p.velocity
	if v != Vector2.ZERO:
		angle = v.angle()


func blasted(p: Node2D, pos: Vector2) -> void:
	if _burst:
		return
	_burst = true
	for k in count:
		var b := RunState.spawn(PROJECTILE, pos, {
			&"kind": &"player_projectile",
			&"faction": p.faction,
			&"velocity": Vector2.from_angle(angle + TAU * k / count) * BOMBLET_SPEED,
			&"damage": float(p.damage) * BOMBLET_MULT,
			&"auto_fired": p.auto_fired,
			&"size": BOMBLET_SIZE,
			&"lifetime": BOMBLET_LIFE,
			&"blast_radius": BOMBLET_BLAST,
			&"pop_at_end": true,
			&"weapon_id": p.weapon_id,
			&"source_patch": p.source_patch,
			&"origin": pos,
		})
		if b == null:
			refused += 1
			continue
		var visual := b.get_node_or_null(^"Visual")
		if visual != null:
			visual.set(&"skin_id", BOMBLET_SKIN)
		bomblets.append(b)
	RunState.log_event(&"cluster_burst", {"bomblets": bomblets.size(), "refused": refused})

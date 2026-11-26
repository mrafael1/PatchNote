extends Node2D
## A mine (the launcher's mine_layer, M50.3a; the caltrop pattern): dropped where a shell left
## the muzzle, it arms after ARM seconds of game time; then the first enemy whose body comes
## within TRIGGER of it sets it off: a blast of BLAST_TILES (no knockback, never the player),
## credited to the launcher. It fizzles after LIFE seconds. Not an entity and not a projectile
## (RunState's budgets never see it); at most `cap` alive (the oldest goes). No RNG.
## Looks: the player_shot role on tier 0, the `mine` / `mine_armed` sprites with a look; the
## armed light blinks, steady under reduce flashing.

const ARM := 0.5
const LIFE := 12.0
const TRIGGER := 0.5 * Tuning.TILE
const BLAST_TILES := 1.6
const RADIUS := 10.0
const SKIN_SCALE := 3.0  ## the look's 7x7 mine at 3 px a cell (21 px, about RADIUS)
const BLINK := 0.4      ## s of game time per blink phase (presentation only)
const GROUP := &"mine"

var damage := 2.0
var source: StringName = &"weapon:launcher"
var blown := false      ## tests
var _born := -1.0
var _armed := false
var _lit := true
var _skin_version := -1


## Drops one at `pos` (deferred into the world), making room under `cap` first.
static func drop(pos: Vector2, p_damage: float, cap: int, p_source: StringName) -> Node2D:
	make_room(cap)
	var m: Node2D = (load("res://weapons/traits/mine.gd") as GDScript).new()
	m.position = pos
	m.damage = p_damage
	m.source = p_source
	m.add_to_group(GROUP)
	RunState.world.add_child.call_deferred(m)
	RunState.log_event(&"mine_laid")
	return m


## Frees the oldest (tree order) until fewer than `cap` are alive.
static func make_room(cap: int) -> void:
	var alive_now: Array[Node] = []
	for z in RunState.get_tree().get_nodes_in_group(GROUP):
		if not z.is_queued_for_deletion():
			alive_now.append(z)
	var i := 0
	while alive_now.size() - i >= cap and i < alive_now.size():
		alive_now[i].remove_from_group(GROUP)
		alive_now[i].queue_free()
		i += 1


## Mines alive now (tests, the cap check).
static func alive() -> int:
	var n := 0
	for z in RunState.get_tree().get_nodes_in_group(GROUP):
		if not z.is_queued_for_deletion():
			n += 1
	return n


func is_armed() -> bool:
	return _armed


func _physics_process(_delta: float) -> void:
	if _born < 0.0:
		_born = RunState.game_time
	var age := RunState.game_time - _born
	if age >= LIFE:
		_gone()
		return
	if not _armed:
		if age < ARM:
			return
		_armed = true
		queue_redraw()
	var lit := SaveGame.reduce_flashing() or int(age / BLINK) % 2 == 0
	if lit != _lit:
		_lit = lit
		queue_redraw()
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var half: float = enemy.get(&"half_width") if enemy.get(&"half_width") != null else 15.0
		if enemy.global_position.distance_to(global_position) > half + TRIGGER:
			continue
		blown = true
		RunState.log_event(&"mine_blown")
		Explosion.blast(global_position, BLAST_TILES * Tuning.TILE, damage, 0.0, &"blast", source, false)
		_gone()
		return


func _process(_delta: float) -> void:
	if Skins.version != _skin_version:
		_skin_version = Skins.version
		queue_redraw()


func _gone() -> void:
	remove_from_group(GROUP)
	queue_free()


func _draw() -> void:
	var id := &"mine_armed" if _armed and _lit else &"mine"
	var skin := Skins.on(id)
	if skin != null and skin.has(id):
		skin.draw(self, id, Vector2.ZERO, SKIN_SCALE, 0, Color.WHITE)
		return
	var c := Palette.color(&"player_shot")
	draw_circle(Vector2.ZERO, RADIUS, Palette.color(&"outline"))
	draw_arc(Vector2.ZERO, RADIUS - 2.0, 0.0, TAU, 16, c, 2.0)
	draw_circle(Vector2.ZERO, 3.5, Color(c, 1.0 if _armed and _lit else 0.35))

class_name Reactions
extends Node
## The AI's live reactions in a campaign session (PLAN v8 1.7). It watches the game,
## checks the reactions' triggers at TICK_HZ, and says one line when a trigger happens
## and the speaking rules allow it:
##
## - Priority 3 (important) is always said; the mascot lets it cut in.
## - Below that, nothing while a line is still being spoken (a cue, an intro line or
##   another reaction): the moment has passed, the reaction is dropped, not queued.
## - Priority 1 (chatter) also waits GAP seconds after the last reaction.
## - Each reaction has its own cooldown, maybe once per session, and the sessions it fits
##   (after / until by session id, PLAN v9 1.13; a discovery line retires once it is not
##   new, M42), and maybe a `when` (a Line condition on the save, checked at start: a
##   gated reaction never takes a cooldown slot).
##
## Everything runs on game time and the run's seed, and "still being spoken" is
## estimated from the line's length (typing + reading), so the same seed says the same
## reactions at the same moments, whatever the frame rate. Lines go out through
## `line_said`; the shell hands them to the mascot.

signal line_said(line: Line, priority: int)

const TICK_HZ := 4.0
const GAP := 8.0
const NEAR_MISS_CONFIRM := 0.3   ## a close shot counts once the player is still unhit this long after
## A new enemy or the first dash is still worth a line until the AI has had this long
## FREE since it happened: time spent speaking does not count, so a long intro (S4
## talks through its first spawns) cannot use the window up (M39.1 review).
const PENDING := 6.0

var session: SessionDef
var genre: Genre
var player: Node2D
var session_id: StringName = &""  ## the session's id (ReactionDef.fits)
var muted := false               ## --mute-ai: nothing is checked, nothing is said
## Every reaction said, in order: {id, at, priority, text}.
var fired: Array[Dictionary] = []

var _defs: Array[ReactionDef] = []
var _last_at := {}               ## reaction id -> game time it last fired
var _count := {}                 ## reaction id -> times fired (picks the line)
var _armed := {}                 ## reaction id -> false while its edge condition holds
var _last_slot := -1             ## the game-time slot (1 / TICK_HZ) last checked
var _holds := {}   ## owner -> true: reactions below priority 3 are held (hold())
var _busy_until := -1.0          ## game time the line being spoken ends
var _busy_priority := 0
var _last_reaction_at := -1000.0

# What the game did since the last tick, or so far.
var _kill_times: Array[float] = []
var _kills_total := 0
var _hits := 0                   ## hits since the last tick
var _last_hit_at := 0.0
var _hit_gap := 0.0              ## seconds without a hit before the latest one
var _last_shot_at := 0.0
var _free_time := 0.0            ## game seconds the AI has been free (not speaking) this session
var _last_tick_at := -1.0        ## game time of the previous tick (-1: none yet)
var _dashed_at := -1.0           ## _free_time at the latest dash (-1: none yet)
var _seen := {}                  ## enemy archetype -> _free_time when first seen this session
var _camp_anchor := Vector2.INF
var _camp_since := 0.0
var _enemy_peak := 0             ## most enemies alive since the arena was last empty
var _close_shots := {}           ## projectile node -> game time it came close
var _near_misses := 0


## Sessions up to this one say nothing before their first kill (see _physics_process).
const QUIET_UNTIL_KILL_THROUGH := &"s1_03_shooting"


## True for a Stage 1 session up to S3, and for a session the campaign does not list (a
## test's own, as `face = false` was).
func _quiet_until_kill() -> bool:
	var at := CampaignDB.index_of(session.id)
	return at == -1 or at <= CampaignDB.index_of(QUIET_UNTIL_KILL_THROUGH)


func _ready() -> void:
	muted = muted or "--mute-ai" in OS.get_cmdline_user_args()
	if session_id == &"" and session != null:
		session_id = session.id
	var ctx := CampaignDB.line_context(session) if session != null else {}
	for d in CampaignDB.reactions:
		if d.fits(session_id) and Line.condition_holds(d.when, ctx):
			_defs.append(d)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.projectile_fired.connect(_on_projectile_fired)
	EventBus.player_dashed.connect(func() -> void: _dashed_at = _free_time)
	EventBus.entity_spawned.connect(_on_entity_spawned)
	EventBus.projectile_hit.connect(_on_projectile_hit)


func active_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d in _defs:
		out.append(d.id)
	return out


func fired_ids() -> Array[String]:
	var out: Array[String] = []
	for f in fired:
		out.append(String(f.id))
	return out


static func now() -> float:
	return RunState.game_time


## Holds every reaction below priority 3 while any owner holds (M41: a scripted event
## runs). Priority 3 still speaks. Edges that happen meanwhile are consumed as usual.
func hold(owner_id: StringName, on: bool) -> void:
	if on:
		_holds[owner_id] = true
	else:
		_holds.erase(owner_id)


func held() -> bool:
	return not _holds.is_empty()


## A line someone else will say (the session's script), noted when it is queued: it is
## spoken after whatever is being spoken now, and nothing below priority 3 talks over it.
func note_spoken(line: Line, priority: int, cut := false) -> void:
	var t := now()
	if cut:
		_busy_until = t   # the line on screen was cut: it is not spoken any more
	var ends := maxf(t, _busy_until) + speak_seconds(line.text)
	if ends > _busy_until:
		_busy_until = ends
		_busy_priority = priority


## How long the mascot holds a line on screen: typed, then read.
static func speak_seconds(text: String) -> float:
	return text.length() / Mascot.TYPE_CPS + SessionRunner.read_seconds(text)


func speaking() -> bool:
	return now() < _busy_until


# --- What happened ----------------------------------------------------------------

func _on_enemy_killed(_enemy: Node, _info: RefCounted) -> void:
	_kill_times.append(now())
	_kills_total += 1


func _on_player_hit(_info: RefCounted) -> void:
	var t := now()
	_hit_gap = t - _last_hit_at
	_last_hit_at = t
	_hits += 1
	_close_shots.clear()   # whatever was close may be what hit


func _on_projectile_fired(projectile: Node) -> void:
	if projectile.get(&"faction") == &"player":
		_last_shot_at = now()


func _on_entity_spawned(entity: Node) -> void:
	if not entity.is_in_group(&"enemy"):
		return
	var arch := entity.scene_file_path.get_file().get_basename().trim_prefix("enemy_")
	if arch != "" and not _seen.has(arch):
		# Seen during a hold (an event): never announced, so no stale "X seen" after it.
		_seen[arch] = -INF if held() else _free_time


## A shot that reached the player was not a miss, even when the hit did no damage
## (i-frames, a dash, the start grace, invincible bots): Health then sends no player_hit.
func _on_projectile_hit(projectile: Node, target: Node, _pos: Vector2) -> void:
	if target == player:
		_close_shots.erase(projectile)


func _physics_process(_delta: float) -> void:
	if muted or genre == null or genre.is_over() or not is_instance_valid(player):
		return
	_watch_shots()
	# Ticks fall on game time (every 1 / TICK_HZ s from 0), not on when this node
	# started: the same seed checks at the same moments.
	var slot := floori(now() * TICK_HZ)
	if slot == _last_slot:
		return
	_last_slot = slot
	# Through S3 the AI's first full sentence is the script's "Oh. That works." on the first
	# kill: until then reactions follow what happens but say nothing, so no stale one (low HP)
	# is left to go off at the kill (M39.2 review). M47.6b: S3 has its face now (the body is
	# S2's pick), so this keys on the session's place, not on `face`.
	tick(session != null and _quiet_until_kill() and RunState.kills == 0)


## Enemy shots that pass close: marked every frame (a shot crosses 12 px in a frame or
## two), confirmed as a near miss once the player is still unhit a moment later.
func _watch_shots() -> void:
	var reach := near_miss_reach()
	for p in get_tree().get_nodes_in_group(&"enemy_projectile"):
		var shot := p as Node2D
		if shot == null or shot.is_queued_for_deletion():
			continue
		if shot.global_position.distance_to(player.global_position) <= reach:
			if not _close_shots.has(shot):
				_close_shots[shot] = now()
	var t := now()
	for key in _close_shots.keys():
		if t - float(_close_shots[key]) >= NEAR_MISS_CONFIRM:
			_close_shots.erase(key)
			_near_misses += 1


## The player's half size plus NEAR_MISS: a shot this close to the centre was close.
static func near_miss_reach() -> float:
	return 17.0 + ReactionDef.NEAR_MISS


# --- Checking the triggers ----------------------------------------------------------

## One check of every trigger (TICK_HZ; tests call it directly). Says at most one line.
## quiet: follow what happens (edges, consumed events) but say nothing.
func tick(quiet := false) -> void:
	var t := now()
	# The free part of the time since the last tick: after whatever was being spoken.
	if _last_tick_at >= 0.0:
		_free_time += maxf(0.0, t - maxf(_last_tick_at, _busy_until))
	_last_tick_at = t
	var pos := player.global_position
	if _camp_anchor == Vector2.INF or pos.distance_to(_camp_anchor) > ReactionDef.CAMP_RADIUS:
		_camp_anchor = pos
		_camp_since = t
	var enemies := RunState.count(&"enemy")
	_enemy_peak = maxi(_enemy_peak, enemies)
	var best: ReactionDef = null
	for d in _defs:
		var happened := _happened(d, t, enemies)
		if not happened:
			continue
		if not _allowed(d, t):
			continue
		if best == null or d.priority > best.priority:
			best = d
	# Consumed whatever was said or not: events belong to this tick only (a new enemy
	# and the first dash wait up to PENDING seconds for the AI to be free).
	_hits = 0
	_near_misses = 0
	while not _kill_times.is_empty() and t - _kill_times[0] > ReactionDef.STREAK_WINDOW:
		_kill_times.pop_front()
	if enemies == 0:
		_enemy_peak = 0
	if best != null and not quiet:
		_say(best, t)


## Did d's trigger happen this tick? Edge triggers fire once each time their condition
## starts to hold (_armed), not on every tick while it holds.
func _happened(d: ReactionDef, t: float, enemies: int) -> bool:
	var n := d.trigger_value()
	match d.trigger_name():
		&"first_kill":
			return _edge(d, _kills_total >= 1)
		&"kill_streak":
			var streak := _kill_times.filter(func(k: float) -> bool: return t - k <= ReactionDef.STREAK_WINDOW).size()
			return _edge(d, streak >= int(n))
		&"kills_at_least":
			return _edge(d, _kills_total >= int(n))
		&"enemy_count_at_least":
			return _edge(d, enemies >= int(n))
		&"enemy_seen":
			var seen_at := float(_seen.get(d.trigger_word(), -INF))
			return not _count.has(d.id) and _free_time - seen_at <= PENDING
		&"player_hp_at_most":
			var hp := _player_hp()
			return _edge(d, hp > 0.0 and hp <= n)
		&"player_hit":
			return _hits > 0
		&"streak_broken":
			return _hits > 0 and _hit_gap >= n
		&"near_miss":
			return _near_misses > 0
		&"camping":
			return _edge(d, t - _camp_since >= ReactionDef.CAMP_SECONDS)
		&"not_shooting":
			var can_shoot := not bool(player.get(&"shooting_locked"))
			# M45a (PLAN 5: "never on Auto"): Auto fires by itself, silent with no enemy in reach.
			var lo := Component.find(player, Loadout) as Loadout
			can_shoot = can_shoot and not (lo != null and lo.fire_mode == &"auto_all")
			return _edge(d, can_shoot and enemies > 0 and t - _last_shot_at >= ReactionDef.IDLE_GUN_SECONDS)
		&"no_hit_for":
			return _edge(d, t - _last_hit_at >= n)
		&"wave_cleared":
			return _edge(d, enemies == 0 and _enemy_peak >= ReactionDef.WAVE_MIN and _kills_total > 0)
		&"session_half":
			return _edge(d, _progress() >= 0.5)
		&"last_seconds":
			var left := _survive_left()
			return _edge(d, left > 0.0 and left <= ReactionDef.LAST_SECONDS)
		&"first_dash":
			return _dashed_at >= 0.0 and not _count.has(d.id) and _free_time - _dashed_at <= PENDING
		&"quiet":
			return _edge(d, t - maxf(_busy_until, 0.0) >= n)
		# M47.6c1 (design 2.6): a clear session's set is all out (RunState.wave_closed, never
		# set elsewhere): more than 2 left, or exactly n left.
		&"wave_done":
			return _edge(d, RunState.wave_closed and enemies > 2)
		&"last_few":
			return _edge(d, RunState.wave_closed and enemies == int(n))
	return false


## True on the tick an edge condition starts to hold; re-armed once it stops holding.
func _edge(d: ReactionDef, holds: bool) -> bool:
	if not holds:
		_armed[d.id] = true
		return false
	if _armed.get(d.id, true):
		_armed[d.id] = false
		return true
	return false


func _allowed(d: ReactionDef, t: float) -> bool:
	if d.once_per_session and _count.has(d.id):
		return false
	if not live_path_holds(d.when):
		return false
	if _last_at.has(d.id) and t - float(_last_at[d.id]) < d.cooldown:
		return false
	if d.priority >= 3:
		return true
	if held():
		return false
	if speaking():
		return false
	if d.priority <= 1 and t - _last_reaction_at < GAP:
		return false
	return true


func _say(d: ReactionDef, t: float) -> void:
	var line := pick_line(d, int(_count.get(d.id, 0)))
	_last_at[d.id] = t
	_count[d.id] = int(_count.get(d.id, 0)) + 1
	if line == null:
		return
	_last_reaction_at = t
	fired.append({"id": d.id, "at": snappedf(t, 0.01), "priority": d.priority, "text": line.text})
	RunState.log_event(&"reaction", {"id": String(d.id)})
	note_spoken(line, d.priority)
	line_said.emit(line, d.priority)


## M47 (C1.3): a `when` naming answer:path_<p> reads the live path while one is live (S7's
## tastes: "My bad" never fights "That's the point!"), else the save's answer as at start.
func live_path_holds(when: String) -> bool:
	if not when.contains("answer:path_") or RunState.live_path() == &"":
		return true
	var ctx := CampaignDB.line_context(session) if session != null else {}
	var shipped: Array = []
	for c: Variant in ctx.get("shipped", []):
		if not String(c).begins_with("path_"):
			shipped.append(c)
	shipped.append(StringName("path_%s" % RunState.live_path()))
	ctx["shipped"] = shipped
	return Line.condition_holds(when, ctx)


## The line d says the nth time it fires this session: from the lines for the save's
## mascot if it has any, else the shared ones; picked by the run's seed.
func pick_line(d: ReactionDef, nth: int) -> Line:
	var ctx := CampaignDB.line_context(session) if session != null else {}
	var passing := Line.passing(d.line_list(), ctx)
	var own := passing.filter(func(l: Line) -> bool: return String(l.when).begins_with("mascot:"))
	var pool: Array = own if not own.is_empty() else passing
	if pool.is_empty():
		return null
	return pool[absi(hash([RunState.run_seed, String(d.id), nth])) % pool.size()]


func _player_hp() -> float:
	var health := Component.find(player, Health) as Health
	return health.hp() if health != null and not health.dead else 0.0


## 0..1 of the session's goal: survive time or kills; 0 for the others.
func _progress() -> float:
	if session == null or genre == null:
		return 0.0
	match session.goal:
		SessionDef.SURVIVE:
			return maxf(0.0, genre.session_progress()) / 100.0
		SessionDef.KILLS:
			return float(RunState.kills) / maxf(1.0, _kill_goal())
		SessionDef.CLEAR:   # M47.6c1: kills against the fixed set (budget + cue spawns)
			return float(RunState.kills) / maxf(1.0, maxf(session.enemy_total, 0) + session.cue_spawn_total())
	return 0.0


## The kills goal the run plays (M45a: a path's kill_goal_mult scales it in the genre).
func _kill_goal() -> float:
	var loop: Variant = genre.get(&"run_loop") if genre != null else null
	return float(loop.goal_value) if loop != null else session.goal_value


## M47.2: against the goal the run plays (goal_by_path: S8 Survival 90 s), as _kill_goal().
func _survive_left() -> float:
	if session == null or genre == null or session.goal != SessionDef.SURVIVE:
		return -1.0
	return _kill_goal() - genre.session_clock()

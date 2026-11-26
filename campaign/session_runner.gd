class_name SessionRunner
extends Node
## Plays a campaign session's script in the game scene (PLAN v8 1.2, 1.5): the intro
## lines, then each cue once, on the genre's goal clock. It speaks through `line_said`
## (a toast in M37, the mascot from M38) and counts what the debrief reads: hits taken.
##
## Speech is paced in real time (a line stays 1.2 s + 0.05 s a character), so reading
## never depends on slow motion; cues run on physics frames, so the same seed plays
## the same session (spawns use RunState.gameplay_rng).

signal line_said(line: Line)
## A line joins the queue (intro, or a cue firing on the goal clock). It comes on game
## time, so Reactions estimates "being spoken" from here, not from line_said, which
## waits on the wall clock (PLAN v8 M39 review).
signal line_queued(line: Line)
## M47.5b (PLAN v9.3 2.9): a `skin` cue fired (the always-on terminal's "$ skin reveal <group>").
signal skin_cued(target: StringName)

const READ_BASE := 1.2
## The script's lines (intro and cues) speak at this priority: reactions below 3 never
## talk over them (Reactions, Mascot).
const PRIORITY := 2
const READ_PER_CHAR := 0.05

var session: SessionDef
var genre: Genre
var hits := 0
var rule_book: RuleBook   ## set by main.gd: where "edit" cues go
var event_player: EventPlayer   ## set by main.gd: where "event" cues go
## Set by main.gd (M45a) in a session with a path or a tryout: where "path" cues go, the
## live pool (give / tagged say) and the level / picks the whens read. Null in Stage 1.
var path_runner: PathRunner
var touched := false   ## something tried to hurt the player before `health` (cue "touch")
## --mute-ai (PLAN v8 4): nothing is said; cues that act still fire. The fun-before-
## meta check.
var muted := false
var said: Array[String] = []   ## every line said, in order (tests, F1)

var _cues: Array[Cue] = []
var _fired: Array[bool] = []
## M47: `picked n` cues bound to the path that started after the session reached them.
var _bound := {}   ## cue index -> true
var _queue: Array[Line] = []
var _free_at_msec := 0
## M48b (PLAN 1.7.1): the transformation's bookkeeping. Sim-side and the same with skins on
## or off (Skins.reveal is a no-op without a look), so the lines never depend on the look.
var _morphs := 0                ## `skin ... morph` cues fired (the first one morphs 3 s)
var _enemies_armed := false     ## `skin enemies` fired: each new enemy id gets drawn in
var _met := {}                  ## enemy ids named by a skin cue or met since (said once)
var reveal_said := 0            ## reveal_lines said so far (tests)
const FIRST_MORPH := 3.0
const LATER_MORPH := 1.0
const ARENA_MORPH := 3.0
## M50.1b: a `fused` / `fuse_ready` cue fires at least this long after the previous say cue.
const SAY_GAP := 4.0
var _last_say := -1.0
## M47.6a (PLAN v9.4, S0): direction presses while the build cannot move (`tried N` cues):
## each new direction the player's input enters counts one (physics, the input it reads).
var tried := 0
var _tried_dir := Vector2i.ZERO


func _ready() -> void:
	muted = muted or "--mute-ai" in OS.get_cmdline_user_args()
	var ctx := CampaignDB.line_context(session)
	# The parse is cached and shared: never change it. PLAN v9 1.3: a cue whose condition
	# fails is dropped here, before anything fires, so it is never half-fired.
	_cues.clear()
	for c in session.cue_list():
		if Line.condition_holds(c.cond, ctx):
			_cues.append(c)
	_fired.resize(_cues.size())
	_fired.fill(false)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_touched.connect(func() -> void: touched = true)
	for line in Line.passing(session.intro_lines(), ctx):
		say(line)


## Queues a line (dropped when muted). The next one comes once this one has been read.
## A "{key:<action>}" in its text becomes the key printed on the player's keyboard
## (with_keys; M44 review: AZERTY prints A where weapon_prev's Q sits).
func say(line: Line) -> void:
	if muted or line == null:
		return
	line = with_keys(line)
	_queue.append(line)
	line_queued.emit(line)


## The lines waiting their turn, oldest first (the intro, queued before anyone listens).
func queued_lines() -> Array[Line]:
	return _queue.duplicate()


## `line`, or a copy with its {key:...} tokens named for this keyboard (the parse is
## cached and shared: never changed in place).
static func with_keys(line: Line, to_label := Callable()) -> Line:
	if not line.text.contains("{key:"):
		return line
	return Line.make(InputSetup.expand_keys(line.text, to_label), line.expression, line.when)


static func read_seconds(text: String) -> float:
	return READ_BASE + READ_PER_CHAR * text.length()


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now < _free_at_msec:
		return
	var line: Line = _queue.pop_front()
	_free_at_msec = now + int(read_seconds(line.text) * 1000.0)
	said.append(line.text)
	line_said.emit(line)


## M47.3 (PLAN 1.16): the pause menu holds the speech queue's wall clock. On: the moment is
## kept; off: the next line's slot moves on by the time the menu was open.
var _held_at := -1


func hold_speech(on: bool) -> void:
	if on:
		if _held_at < 0:
			_held_at = Time.get_ticks_msec()
	elif _held_at >= 0:
		_free_at_msec += Time.get_ticks_msec() - _held_at
		_held_at = -1


func _physics_process(_delta: float) -> void:
	if genre == null or genre.is_over():
		return
	_count_tried()
	var ctx := {"clock": genre.session_clock(), "kills": RunState.kills, "tried": tried,
			"pct": genre.session_progress(), "hit": hits > 0, "touched": touched,
			"hp": _player_hp(),
			"level": path_runner.level() if path_runner != null else -1,
			"picks": path_runner.picks_on_path if path_runner != null else 0,
			"fused": path_runner.fusions.size() if path_runner != null else 0,
			"fuse_ready": path_runner.fuse_ready_count if path_runner != null else 0,
			"items": _held_items(),
			"evolve_ready": path_runner.evolve_ready_count if path_runner != null else 0,
			"evolved": path_runner.evolutions.size() if path_runner != null else 0,
			"nerfed": path_runner.nerfs_landed if path_runner != null else 0,
			"give_choices": path_runner.give_steps() if path_runner != null else 0}
	for i in _cues.size():
		if _fired[i]:
			continue
		if _cues[i].when == &"picked" and not _bound.has(i):
			continue   # M47: not bound to a path yet
		if _cues[i].when in [&"fuse_ready", &"evolve_ready"] and _cues[i].expired(ctx):
			_fired[i] = true   # M50.1b review: fused already; "the link's glowing" is stale
			continue
		if _cues[i].due(ctx) and not _waits(_cues[i]):
			_fired[i] = true
			_fire(_cues[i], i)
		elif _cues[i].expired(ctx):
			_fired[i] = true   # dropped, not said


## M47.6a: a press counts when the input's direction (rounded per axis) changes to a new
## non-zero one while the player's movement is locked. Reads the input only, never moves it.
func _count_tried() -> void:
	var p := genre.player
	if p == null or not is_instance_valid(p) or not bool(p.get(&"movement_locked")):
		_tried_dir = Vector2i.ZERO
		return
	var input: Variant = p.get(&"input")
	var m: Vector2 = input.get(&"move") if input is Object and input != null else Vector2.ZERO
	var d := Vector2i(signi(roundi(m.x * 1.4)), signi(roundi(m.y * 1.4)))
	if d != Vector2i.ZERO and d != _tried_dir:
		tried += 1
	_tried_dir = d


## M47 (C1.7): a path started. Each unfired `picked` cue binds to it, or, bound to the
## previous one, expires unfired (logged cue_expired): "Better gun, same card" never plays
## on Auto's level-up.
func on_path_started(_path_id: StringName) -> void:
	for i in _cues.size():
		if _fired[i] or _cues[i].when != &"picked":
			continue
		if _bound.has(i):
			_fired[i] = true
			RunState.log_event(&"cue_expired", {"index": i})
		else:
			_bound[i] = true


## An "hp N:" cue holds while the rule book is busy (another edit's warning, a timed
## edit live) and fires on the first tick after, if the HP is still that low (M42 D23).
## Any other edit cue holds while another edit's warning is pending: two warnings are
## both priority 3, so the second would queue on the mascot and its edit land before
## its line is read.
func _waits(cue: Cue) -> bool:
	# M50.1b: a fusion cue's line waits SAY_GAP after the previous say cue (M50.2b: give_choice too).
	# M50.4c1: an evolution cue's say too (its `nerf` lands at once).
	if (cue.when in [&"fused", &"fuse_ready", &"give_choice"] or (cue.when in [&"evolve_ready", &"evolved", &"nerfed"]
			and cue.action == &"say")) and genre != null and _last_say >= 0.0 \
			and genre.session_clock() < _last_say + SAY_GAP:
		return true
	if rule_book == null:
		return false
	if cue.when == &"hp":
		return rule_book.busy()
	return cue.action == &"edit" and rule_book.warning_pending()


## M50.4b review: the item ids the player holds, for "holds <item>:" cues ([] off Auto).
func _held_items() -> Array:
	var out := []
	var lo := path_runner.loadout() if path_runner != null else null
	if lo != null:
		for it in lo.items:
			out.append(it.id())
	return out


## The player's HP for "hp N:" cues; -1 without the health basic (nothing can hurt yet).
func _player_hp() -> float:
	if not Unlocks.has_basic(&"health") or genre == null or not is_instance_valid(genre.player):
		return -1.0
	var h := Component.find(genre.player, Health) as Health
	return h.hp() if h != null and not h.dead else 0.0


## A spawn cue's archetype; "fork:<id>" is the enemy that fork's answer unlocks (the
## same reading as SessionDef.enemy_types), "" while it is unanswered (M42).
static func _resolve_archetype(archetype: StringName) -> StringName:
	var fork_id := SessionDef.fork_of(archetype)
	if fork_id == &"":
		return archetype
	var answer := Unlocks.answer(fork_id)
	if answer != null:
		for u in answer.unlocks:
			if u in Unlocks.ARCHETYPES:
				return u
	return &""


func _fire(cue: Cue, index: int) -> void:
	RunState.log_event(&"cue", {"index": index, "action": String(cue.action)})
	match cue.action:
		&"say":
			if cue.tag != &"" and path_runner != null:
				path_runner.announce(cue.tag)   # M45a, the pool rule: said, so it may be offered
			if cue.line.passes(cue_context()):
				# M50.2b: only a line actually said starts the SAY_GAP (a give_choice n has three
				# lines, one per branch: the two silent ones must not hold the third back).
				if genre != null:
					_last_say = genre.session_clock()
				say(cue.line)
		&"path":
			if path_runner == null or not path_runner.request_swap(cue.target, cue.line):
				push_warning("Session %s: path %s refused" % [session.id, cue.target])
		&"drop":
			# M47 (D9): Survival only; anything else warns.
			if path_runner == null or not path_runner.drop(cue.target, cue.count):
				push_warning("Session %s: drop %s refused" % [session.id, cue.target])
		&"spawn":
			var archetype := _resolve_archetype(cue.archetype)
			if archetype == &"":
				push_warning("Session %s: %s has no answer yet, nothing spawned" % [session.id, cue.archetype])
			elif cue.specimen and not genre.has_method(&"spawn_specimens"):
				push_warning("Session %s: the genre has no specimens" % session.id)
			elif cue.specimen and not genre.call(&"spawn_specimens", archetype, cue.count):
				push_warning("Session %s: the genre cannot spawn %s" % [session.id, archetype])
			elif not cue.specimen and not genre.spawn_archetype(archetype, cue.count):
				push_warning("Session %s: the genre cannot spawn %s" % [session.id, archetype])
		&"release":
			if genre.has_method(&"release_specimens"):
				genre.call(&"release_specimens")
		&"nerf":
			# M50.4c1: the evolution just made starts too strong; the AI patches it later.
			if path_runner == null or not path_runner.arm_nerf(cue.seconds):
				push_warning("Session %s: nerf refused" % session.id)
		&"fuse":
			# M50.1b: the misfuse; skipped (logged by the runner) with fewer than 2 cards.
			if path_runner != null:
				path_runner.fuse_fail()
		&"skin":
			_fire_skin(cue)
		&"add":
			RunState.add_basic(cue.target)
		&"edit":
			if rule_book == null or not rule_book.request(cue.target, &"cue", cue.seconds, not cue.quiet):
				push_warning("Session %s: edit %s refused" % [session.id, cue.target])
		&"event":
			if event_player == null:
				push_warning("Session %s: no event player for %s" % [session.id, cue.target])
			else:
				event_player.play(cue.target, &"cue")   # false: seen (skipped) or busy
		&"give":
			# M44: with no path, a free slot (or a rank up). M45a: the weapon joins the live
			# pool, and under Auto the next level-up offers it first instead (no slot filled).
			# M50.4b: a passive item only means something on a level-ups path (Auto): anywhere
			# else it is skipped and logged.
			if WeaponDB.has_item(cue.target):
				if path_runner == null or path_runner.def == null or path_runner.def.growth != &"levelups" 						or not path_runner.give(cue.target, cue.rank):
					RunState.log_event(&"give_skipped", {"item": String(cue.target)})
				return
			if path_runner != null and path_runner.give(cue.target, cue.rank):
				return
			var loadout: Loadout = null
			if genre != null and is_instance_valid(genre.player):
				loadout = Component.find(genre.player, Loadout) as Loadout
			if loadout == null or not loadout.give(cue.target, cue.rank):
				push_warning("Session %s: give %s %d refused" % [session.id, cue.target, cue.rank])
		_:
			push_warning("Session %s: cue action %s is not built yet" % [session.id, cue.action])


## A say cue's line context: CampaignDB.line_context plus M50.2b's live hand fact `paired`
## (the hand is a built recipe pair, whatever the `fusion` basic; never in the debrief's).
func cue_context() -> Dictionary:
	var ctx := CampaignDB.line_context(session)
	if path_runner != null and path_runner.pack_path():
		ctx.paired = path_runner.paired()
	return ctx


## M48b (PLAN 1.7.1): a `skin` cue. A morph lasts FIRST_MORPH on the session's first morph
## cue and LATER_MORPH after (the arena paints over ARENA_MORPH); shots, ui, mascot and all
## are instant. `skin enemies` arms the per-spawn reveal and draws in the enemies already
## on screen (tree order).
func _fire_skin(cue: Cue) -> void:
	skin_cued.emit(cue.target)
	if cue.target == &"bug":
		Skins.glitch(cue.bug, cue.seconds)
		return
	if cue.target == &"all":
		# M48b review: the transformation is over: no more reveal lines or morphs (decided
		# from the cue, not from Skins, so the lines are the same with skins on or off).
		_disarm_enemies()
		Skins.reveal_all()
		return
	var length := 0.0
	if cue.morph:
		_morphs += 1
		length = ARENA_MORPH if cue.target == &"arena" else (FIRST_MORPH if _morphs == 1 else LATER_MORPH)
	for id in Skins.target_ids(cue.target):
		if id in Skins.ENEMY_IDS:
			_met[id] = true
	Skins.reveal(cue.target, length)
	if cue.target == &"enemies" and not _enemies_armed:
		_enemies_armed = true
		EventBus.entity_spawned.connect(_on_entity_spawned)
		for e in get_tree().get_nodes_in_group(&"enemy"):
			if is_instance_valid(e) and not e.is_queued_for_deletion():
				_meet(e)


func _on_entity_spawned(entity: Node) -> void:
	if genre == null or genre.is_over() or not entity.is_in_group(&"enemy"):
		return
	_meet(entity)


## An enemy id met for the first time after `skin enemies`: the next reveal line, and
## its sprite morphs in over LATER_MORPH.
func _meet(entity: Node) -> void:
	var visual := entity.get_node_or_null(^"Visual")
	if visual == null:
		return
	var id := Skins.id_for(visual)
	if id == &"" or _met.has(id) or not id in Skins.ENEMY_IDS:
		return
	_met[id] = true
	var pool := session.reveal_line_list()
	if not pool.is_empty():
		say(pool[reveal_said % pool.size()])
		reveal_said += 1
	Skins.reveal(id, LATER_MORPH)


func _disarm_enemies() -> void:
	_enemies_armed = true   # a later `skin enemies` does not re-arm either
	if EventBus.entity_spawned.is_connected(_on_entity_spawned):
		EventBus.entity_spawned.disconnect(_on_entity_spawned)


func _exit_tree() -> void:
	if EventBus.entity_spawned.is_connected(_on_entity_spawned):
		EventBus.entity_spawned.disconnect(_on_entity_spawned)


## The bot and tests (PLAN v8 M40): drop every cue of one action (the session's own
## edits), or add one (a forced edit at 12 s). Only this runner's copy changes.
func drop_cues(action: StringName) -> void:
	for i in range(_cues.size() - 1, -1, -1):
		if _cues[i].action == action:
			_cues.remove_at(i)
			_fired.remove_at(i)


func has_cue(action: StringName) -> bool:
	return _cues.any(func(c: Cue) -> bool: return c.action == action)


func inject(text: String) -> Cue:
	var c := Cue.parse(text)
	if c.problem == "":
		_cues.append(c)
		_fired.append(false)
		if c.when == &"picked" and path_runner != null and path_runner.path_id != &"":
			_bound[_cues.size() - 1] = true
	return c


## M47.6c1 (design 2.6): enemies the unfired `at` / `kills` spawn cues will still add (both
## always fire: time runs and kills only grow). A cue keyed on anything else never holds a
## clear ending, nor does a specimen.
func pending_spawns() -> int:
	var n := 0
	for i in _cues.size():
		var c := _cues[i]
		if not _fired[i] and c.action == &"spawn" and not c.specimen and c.when in [&"at", &"kills"]:
			n += c.count
	return n


## M47.6c1: the script part a `script` ending waits for: every `at` cue fired (or expired), and
## the rule book has no edit in its warning or timed-live. Condition cues never hold it.
func script_cues_done() -> bool:
	for i in _cues.size():
		if not _fired[i] and _cues[i].when == &"at":
			return false
	if rule_book != null and rule_book.busy():
		return false
	return event_player == null or not event_player.is_playing()


## Lines said or waiting their turn: what the session gave the AI to say, whatever the
## wall clock (a bot plays faster than speech is paced).
func line_count() -> int:
	return said.size() + _queue.size()


func fired_count() -> int:
	return _fired.count(true)


func _on_player_hit(_info: RefCounted) -> void:
	if genre != null and not genre.is_over():
		hits += 1

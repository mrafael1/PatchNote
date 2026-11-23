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

const READ_BASE := 1.2
## The script's lines (intro and cues) speak at this priority: reactions below 3 never
## talk over them (Reactions, Mascot).
const PRIORITY := 2
const READ_PER_CHAR := 0.05

var session: SessionDef
var genre: Genre
var hits := 0
var rule_book: RuleBook   ## set by main.gd: where "edit" cues go
var touched := false   ## something tried to hurt the player before `health` (cue "touch")
## --mute-ai (PLAN v8 4): nothing is said; cues that act still fire. The fun-before-
## meta check.
var muted := false
var said: Array[String] = []   ## every line said, in order (tests, F1)

var _cues: Array[Cue] = []
var _fired: Array[bool] = []
var _queue: Array[Line] = []
var _free_at_msec := 0


func _ready() -> void:
	muted = muted or "--mute-ai" in OS.get_cmdline_user_args()
	_cues = session.cue_list().duplicate()   # the parse is cached and shared: never change it
	_fired.resize(_cues.size())
	_fired.fill(false)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_touched.connect(func() -> void: touched = true)
	var ctx := CampaignDB.line_context(session)
	for line in Line.passing(session.intro_lines(), ctx):
		say(line)


## Queues a line (dropped when muted). The next one comes once this one has been read.
func say(line: Line) -> void:
	if muted or line == null:
		return
	_queue.append(line)
	line_queued.emit(line)


## The lines waiting their turn, oldest first (the intro, queued before anyone listens).
func queued_lines() -> Array[Line]:
	return _queue.duplicate()


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


func _physics_process(_delta: float) -> void:
	if genre == null or genre.is_over():
		return
	var ctx := {"clock": genre.session_clock(), "kills": RunState.kills,
			"pct": genre.session_progress(), "hit": hits > 0, "touched": touched}
	for i in _cues.size():
		if _fired[i]:
			continue
		if _cues[i].due(ctx):
			_fired[i] = true
			_fire(_cues[i], i)
		elif _cues[i].expired(ctx):
			_fired[i] = true   # dropped, not said


func _fire(cue: Cue, index: int) -> void:
	RunState.log_event(&"cue", {"index": index, "action": String(cue.action)})
	match cue.action:
		&"say":
			if cue.line.passes(CampaignDB.line_context(session)):
				say(cue.line)
		&"spawn":
			if not genre.spawn_archetype(cue.archetype, cue.count):
				push_warning("Session %s: the genre cannot spawn %s" % [session.id, cue.archetype])
		&"add":
			RunState.add_basic(cue.target)
		&"edit":
			if rule_book == null or not rule_book.request(cue.target, &"cue", cue.seconds):
				push_warning("Session %s: edit %s refused" % [session.id, cue.target])
		_:
			push_warning("Session %s: cue action %s is not built yet" % [session.id, cue.action])


## The bot and tests (PLAN v8 M40): drop every cue of one action (the session's own
## edits), or add one (a forced edit at 12 s). Only this runner's copy changes.
func drop_cues(action: StringName) -> void:
	for i in range(_cues.size() - 1, -1, -1):
		if _cues[i].action == action:
			_cues.remove_at(i)
			_fired.remove_at(i)


func inject(text: String) -> Cue:
	var c := Cue.parse(text)
	if c.problem == "":
		_cues.append(c)
		_fired.append(false)
	return c


## Lines said or waiting their turn: what the session gave the AI to say, whatever the
## wall clock (a bot plays faster than speech is paced).
func line_count() -> int:
	return said.size() + _queue.size()


func fired_count() -> int:
	return _fired.count(true)


func _on_player_hit(_info: RefCounted) -> void:
	if genre != null and not genre.is_over():
		hits += 1

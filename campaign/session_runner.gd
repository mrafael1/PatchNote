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

const READ_BASE := 1.2
const READ_PER_CHAR := 0.05

var session: SessionDef
var genre: Genre
var hits := 0
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
	_cues = session.cue_list()
	_fired.resize(_cues.size())
	_fired.fill(false)
	EventBus.player_hit.connect(_on_player_hit)
	var ctx := CampaignDB.line_context(session)
	for line in Line.passing(session.intro_lines(), ctx):
		say(line)


## Queues a line (dropped when muted). The next one comes once this one has been read.
func say(line: Line) -> void:
	if muted or line == null:
		return
	_queue.append(line)


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
			"pct": genre.session_progress(), "hit": hits > 0}
	for i in _cues.size():
		if not _fired[i] and _cues[i].due(ctx):
			_fired[i] = true
			_fire(_cues[i], i)


func _fire(cue: Cue, index: int) -> void:
	RunState.log_event(&"cue", {"index": index, "action": String(cue.action)})
	match cue.action:
		&"say":
			if cue.line.passes(CampaignDB.line_context(session)):
				say(cue.line)
		&"spawn":
			if not genre.spawn_archetype(cue.archetype, cue.count):
				push_warning("Session %s: the genre cannot spawn %s" % [session.id, cue.archetype])
		_:
			push_warning("Session %s: cue action %s is not built yet" % [session.id, cue.action])


## Lines said or waiting their turn: what the session gave the AI to say, whatever the
## wall clock (a bot plays faster than speech is paced).
func line_count() -> int:
	return said.size() + _queue.size()


func fired_count() -> int:
	return _fired.count(true)


func _on_player_hit(_info: RefCounted) -> void:
	if genre != null and not genre.is_over():
		hits += 1

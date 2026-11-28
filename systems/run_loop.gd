class_name RunLoop
extends Node
## The run from start to report (PLAN 8).
##
## play -> (last prompt answered) -> release_candidate for Tuning.rc_duration of game
## time -> win. HP reaching 0 at any point -> lose.
##
## Stages (PLAN v6 4): a run plays a StageSet. Each stage is play until its prompts
## are done and its duration has passed; then stage_clear for Tuning.stage_clear_time
## (the field is cleared, stage_cleared fires), then stage_starting asks the genre to
## build the next stage, and play goes on with the same stack. The last stage's end is
## the release candidate. The one-stage set (StageSet.single) is the v0.0 run exactly. Once the run is over the spawner
## and the Director stop, the telemetry record is built, run_ended fires once, and
## after a short beat report_ready asks for the report. Writing the record to disk is
## the game scene's job, so tests that instance the scene never touch the real file.
##
## A campaign session (PLAN v8 1.2) sets a goal instead (set_goal): survive (won once
## the goal clock reaches the value), kills (won at that many kills; a time limit ends
## it "stopped") or stop (the AI ends it at that time, "stopped", after a read beat).
## The goal clock is game time that can be held (hold_clock), so a scripted event can
## pause the countdown without pausing play. No prompts and no release candidate.
## M43.2 (G13b): a goal can also be held (hold_goal): while anyone holds it, no goal
## ends the session (a kills goal reached waits, logged once as goal_waited), so a
## scripted event always plays to its end; a death still ends it at once.

signal phase_changed(phase: StringName)
signal report_ready(outcome: StringName)
signal stage_cleared(index: int)                       ## stage `index` is over (not the last)
signal stage_starting(index: int, stage: StageDef)     ## build stage `index` now
signal exit_opened(index: int)                         ## an EXIT stage's gate: place it now
## M47.6c1 (design 2.6): a `script` ending's window opened (the script is done; end_after to go).
signal script_window_opened

const PLAY := &"play"
const RELEASE_CANDIDATE := &"release_candidate"
const STAGE_CLEAR := &"stage_clear"
const OVER := &"over"
## A campaign session's ending that is neither a win nor a death (PLAN v8 1.2).
const STOPPED := &"stopped"

var director: AiDirector
var spawner: Spawner
var transition: Transition
## M47.6c2 (design 2.7): where the player started (a carried spot or player_start).
var start_point := Vector2.ZERO
## M47.7b (PLAN 0.9.1): the tried direction the start carried (ZERO: none). Tools print it
## with the start; the telemetry record does not have it.
var start_tried := Vector2.ZERO
var build := ""              ## game build name written to telemetry

var phase: StringName = PLAY
var outcome: StringName = &""
var rc_started_at := -1.0
## > 0: this build misses a basic and its run is a smoke test (PLAN v5 4.8): no prompts,
## survived once this much game time has passed.
var smoke_duration := 0.0
## >= 0: the AI stops the smoke test at this game time with smoke_stop_line, and the
## run ends Tuning.smoke_stop_read later (the build that cannot move, PLAN v5 4.8).
var smoke_stop_at := -1.0
var smoke_stop_line := ""
var smoke_stopped := false
var record: Dictionary = {}  ## telemetry record of the finished run
var stages: StageSet         ## the run's stages; set by the genre before begin()
var stage_index := 0
var stage_started_at := 0.0
var stage_starts: Array[float] = []   ## game time each stage began (telemetry, tests)
var exit_open := false                ## an EXIT stage's gate is open (reach_exit() ends it)
var exit_reached := false

## The campaign session's goal (PLAN v8 1.2); &"" = the run loop's own pacing.
var goal: StringName = &""
var goal_value := 0.0
var time_limit := 0.0
var goal_clock := 0.0        ## game seconds counted toward the goal (held while clock_holds)
var stop_said := false       ## a stop goal reached its time (the AI's line is a cue)
var _clock_holds := {}
var _clock_last := 0.0
var _goal_holds: Array[StringName] = []   ## M43.2: no goal ends while non-empty
var _goal_waited := false
## M47.6c1 (PLAN v9.4 0.8, design 2.6): the session's endings (set_endings). ends: the kinds
## that end it (clear / script, or the goal alone); enemy_total: the spawner's budget (-1 none);
## end_after: a script ending's quiet tail (game seconds); script_done_at: game time the script
## was done (-1: not yet). end_reason: why the run ended (cleared / script / died / limit /
## stopped / won; "" while it plays). session_runner: the cues the endings read (pending spawn
## cues, `at` cues fired, edits); null outside a session.
var ends: Array[StringName] = []
var enemy_total := -1
var end_after := 5.0
var script_done_at := -1.0
var end_reason: StringName = &""
var session_runner: Node

## M50.3c (PLAN v9 1.8): a clear session played in parts (a stage set of more than one stage).
## The set's total splits evenly over the parts (part_budget); the session's own spawn
## multipliers ride on each stage's preset.
var rate_mult := 1.0
var cap_mult := 1.0
## M51: the session's per-part spawn-rate factor (SessionDef.part_rate; empty = 1.0 each).
var part_rate := PackedFloat32Array()

var _report_at := -1.0
var _clear_until := -1.0
var _spawner_on := true


func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)


func _physics_process(_delta: float) -> void:
	match phase:
		PLAY:
			if goal != &"":
				_update_goal()
			elif smoke_duration > 0.0:
				if smoke_stop_at >= 0.0 and not smoke_stopped and RunState.game_time >= smoke_stop_at:
					smoke_stopped = true
					RunState.log_event(&"smoke_stopped")
					if transition:
						transition.say(smoke_stop_line)
				var ends_at := smoke_stop_at + Tuning.smoke_stop_read if smoke_stopped else smoke_duration
				if RunState.game_time >= ends_at:
					end(&"win")
			elif _stage_done():
				if is_last_stage():
					_start_release_candidate()
				else:
					_clear_stage()
		STAGE_CLEAR:
			if RunState.game_time >= _clear_until:
				_start_stage(stage_index + 1)
		RELEASE_CANDIDATE:
			if rc_time_left() <= 0.0:
				end(&"win")
		OVER:
			if _report_at >= 0.0 and RunState.game_time >= _report_at:
				_report_at = -1.0
				report_ready.emit(outcome)


## A campaign session's goal for this run (PLAN v8 1.2). Call before begin().
func set_goal(kind: StringName, value: float, limit := 0.0) -> void:
	goal = kind
	goal_value = value
	time_limit = limit
	goal_clock = 0.0
	_clock_last = RunState.game_time
	_goal_waited = false


## M47.6c1: a session's endings (after set_goal). Empty kinds = the goal alone.
func set_endings(kinds: Array[StringName], total := -1, after := 5.0) -> void:
	ends = kinds.duplicate()
	enemy_total = total
	end_after = after
	script_done_at = -1.0


func has_end(kind: StringName) -> bool:
	return kind in ends or (ends.is_empty() and goal == kind)


## M47.6c1: a clear session's set is all out: its budget (>= 0) is spent and no `at` / `kills`
## spawn cue is still to fire. False for every session that does not clear (S7-S9 today).
func wave_closed() -> bool:
	if not has_end(SessionDef.CLEAR) or enemy_total < 0 or spawner == null or not spawner.budget_spent():
		return false
	return session_runner == null or int(session_runner.call(&"pending_spawns")) == 0


## M47.6c1: enemies alive or entering the tree (splitter children count).
static func enemies_left() -> int:
	return RunState.count(&"enemy") + RunState.pending_count(&"enemy")


## M47.6c1: the set is dead.
func cleared() -> bool:
	return wave_closed() and enemies_left() == 0


## M47.6c1: the script is done: every `at` cue fired, no event holds the goal, no edit pending
## or timed-live. Condition cues never hold it.
func script_done() -> bool:
	if not _goal_holds.is_empty():
		return false
	return session_runner == null or bool(session_runner.call(&"script_cues_done"))


## M47.6c1: the spawner goes quiet once a script ending's window is open, on a session with a
## budget (S5); S7 (no budget) keeps spawning through its tail.
func quiet_tail() -> bool:
	return script_done_at >= 0.0 and has_end(SessionDef.SCRIPT) and enemy_total >= 0


## Holds (true) or releases the goal clock for `owner_id`; it counts while no one holds it.
func hold_clock(owner_id: StringName, on: bool) -> void:
	if on:
		_clock_holds[owner_id] = true
	else:
		_clock_holds.erase(owner_id)


func clock_held() -> bool:
	return not _clock_holds.is_empty()


## Holds (true) or releases the goal's ending for `owner_id` (M43.2: a scripted event,
## from its cue to its end). The goal clock still counts unless hold_clock holds it.
func hold_goal(owner_id: StringName, on: bool) -> void:
	if on and not owner_id in _goal_holds:
		_goal_holds.append(owner_id)
	elif not on:
		_goal_holds.erase(owner_id)


func goal_held() -> bool:
	return not _goal_holds.is_empty()


func _update_goal() -> void:
	var now := RunState.game_time
	if _clock_holds.is_empty():
		goal_clock += now - _clock_last
	_clock_last = now
	if not _goal_holds.is_empty():
		var reached := (goal == SessionDef.KILLS and RunState.kills >= int(goal_value)) or cleared()
		if reached and not _goal_waited:   # M47.6c1: a set cleared mid-event waits the same way
			_goal_waited = true
			RunState.log_event(&"goal_waited")
		return
	if goal in SessionDef.ENDINGS:
		_update_endings(now)
		return
	match goal:
		SessionDef.SURVIVE:
			if goal_clock >= goal_value:
				end(&"win")
		SessionDef.KILLS:
			if RunState.kills >= int(goal_value):
				end(&"win")
			elif time_limit > 0.0 and goal_clock >= time_limit:
				end(STOPPED)
		SessionDef.OVERRUN:
			if goal_clock >= goal_value:
				end(STOPPED)
		SessionDef.STOP:
			if not stop_said and goal_clock >= goal_value:
				stop_said = true
				RunState.log_event(&"session_stopped")
			if goal_clock >= goal_value + Tuning.smoke_stop_read:
				end(STOPPED)
		SessionDef.STAGES, SessionDef.BOSS:
			pass   # PLAN v9 1.2 stubs: never on the clock; won by later systems (M49, M50)


## M47.6c1 (design 2.6): whichever ending comes first. A script window opens on the tick the
## script is done (the spawner goes quiet, the bubble says end_line) and closes end_after game
## seconds later; a clear set ends won; a clear session's time_limit is a hidden cap.
func _update_endings(now: float) -> void:
	if in_parts() and not is_last_stage():
		_update_part()
		return
	if has_end(SessionDef.CLEAR) and enemy_total >= 0:
		var closed := wave_closed()
		RunState.wave_closed = closed
		if closed and not RunState.survivors_chase and enemies_left() <= CHASE_AT:
			RunState.survivors_chase = true   # the last few come to you (latched)
			RunState.log_event(&"survivors_chase")
		if closed and enemies_left() == 0:
			if not (_goal_waited and has_end(SessionDef.SCRIPT)):
				end_reason = &"cleared"
				end(&"win")
				return
			# M47.6c1 review: a set cleared while an event held the goal (S5 under the gravity)
			# does not end on the release tick: the script window opens there instead, so the
			# event's last line and end_line are said and the quiet tail runs; it ends cleared.
			if script_done_at < 0.0:
				_open_script_window(now)
	if has_end(SessionDef.SCRIPT):
		if script_done_at < 0.0 and script_done():
			_open_script_window(now)
		if script_done_at >= 0.0 and now >= script_done_at + end_after:
			if has_end(SessionDef.CLEAR) and cleared():
				end_reason = &"cleared"
				end(&"win")
			else:
				end_reason = &"script"
				end(STOPPED)
			return
	if has_end(SessionDef.CLEAR) and time_limit > 0.0 and goal_clock >= time_limit:
		# A set already cleared (its tail still running) is won, never cut as the cap.
		if cleared():
			end_reason = &"cleared"
			end(&"win")
		else:
			end_reason = &"limit"
			end(STOPPED)


## M47.6c1: the survivors chase you once this few are left of a closed set.
const CHASE_AT := 3


## M50.3c: a clear session whose stage set has several parts.
func in_parts() -> bool:
	return goal != &"" and stages != null and stages.size() > 1 and has_end(SessionDef.CLEAR) and enemy_total >= 0


## M50.3c: the spawner's budget up to the end of part `index` (cumulative; the last is the total).
func part_budget(index: int) -> int:
	if stages == null or stages.size() <= 1:
		return enemy_total
	return int(roundf(float(enemy_total) * float(index + 1) / float(stages.size())))


## M50.3c: this part's share is out: its budget is spent and no spawn cue of this part (or
## an `at` / `kills` one) is still to fire.
func part_closed() -> bool:
	if spawner == null or not spawner.budget_spent():
		return false
	return session_runner == null or int(session_runner.call(&"pending_spawns")) == 0


## M50.3c: a part before the last. Its share dead: an EXIT stage opens its gate and waits
## for the player; any other moves on at once (the stage-clear beat, then the next arena).
## The last part ends the session as any clear session does. The hidden cap still holds.
func _update_part() -> void:
	var closed := part_closed()
	RunState.wave_closed = closed
	if closed and not RunState.survivors_chase and enemies_left() <= CHASE_AT:
		RunState.survivors_chase = true
		RunState.log_event(&"survivors_chase")
	if closed and enemies_left() == 0:
		var stage := current_stage()
		if stage != null and stage.goal == StageDef.EXIT and not exit_reached:
			if not exit_open:
				_open_exit()
		else:
			_clear_stage()
			return
	if time_limit > 0.0 and goal_clock >= time_limit:
		end_reason = &"limit"
		end(STOPPED)


func _apply_part_budget() -> void:
	if in_parts() and spawner:
		spawner.budget = part_budget(stage_index)


func _open_script_window(now: float) -> void:
	script_done_at = now
	RunState.log_event(&"script_done")
	script_window_opened.emit()


## 0..100 of a survive goal's time; -1 for other goals.
func goal_pct() -> float:
	if goal != SessionDef.SURVIVE or goal_value <= 0.0:
		return -1.0
	return clampf(100.0 * goal_clock / goal_value, 0.0, 100.0)


## "Survive 0:45" (time left), "Kills 12/40", or "" (no goal, a stop or overrun goal,
## or over).
func goal_text() -> String:
	if phase != PLAY:
		return ""
	match goal:
		SessionDef.SURVIVE:
			var left := ceili(maxf(0.0, goal_value - goal_clock))
			return "Survive %d:%02d" % [left / 60, left % 60]
		SessionDef.KILLS:
			return "Kills %d/%d" % [mini(RunState.kills, int(goal_value)), int(goal_value)]
	return ""


## Every small and BIG prompt of the run has been opened and answered (or skipped),
## and its patch has finished applying.
func _prompts_done() -> bool:
	if director == null:
		return false
	return director.prompts_done() and not (transition and transition.busy)


## Starts the first stage: its prompt count and spawn preset. The genre calls it from
## begin_run, once the director and spawner are wired.
func begin() -> void:
	if stages == null:
		stages = StageSet.single()
	stage_index = 0
	stage_started_at = RunState.game_time
	stage_starts = [stage_started_at]
	if stages.size() > 1 and director and goal == &"":
		director.begin_stage(current_stage().prompt_count(), true)
	_apply_spawn_preset()
	_apply_part_budget()


func current_stage() -> StageDef:
	return stages.stage(stage_index) if stages else null


func is_last_stage() -> bool:
	return stages == null or stage_index >= stages.size() - 1


## The stage's prompts are done and its time has passed (and, for an EXIT stage, the
## player reached the gate that then opens).
func _stage_done() -> bool:
	if not _prompts_done():
		return false
	var stage := current_stage()
	if stage == null:
		return true
	if RunState.game_time - stage_started_at < stage.duration:
		return false
	if stage.goal == StageDef.EXIT and not exit_reached:
		if not exit_open:
			_open_exit()
		return false
	return true


func _open_exit() -> void:
	exit_open = true
	RunState.log_event(&"exit_open", {"stage": stage_index})
	if transition and goal == &"":   # M50.3c: in a session the AI speaks, not the banner
		transition.say(Dialogue.EXIT_OPEN)
	exit_opened.emit(stage_index)


## The player reached the open gate: the stage ends on the next tick.
func reach_exit() -> void:
	if not exit_open or exit_reached:
		return
	exit_reached = true
	RunState.log_event(&"exit_reached", {"stage": stage_index})


func _clear_stage() -> void:
	phase = STAGE_CLEAR
	_clear_until = RunState.game_time + Tuning.stage_clear_time
	if spawner:
		_spawner_on = spawner.enabled
		spawner.enabled = false
	RunState.start_grace(Tuning.stage_clear_time + Tuning.stage_start_grace)
	RunState.log_event(&"stage_clear", {"stage": stage_index})
	if transition and goal == &"":
		transition.say(Dialogue.STAGE_CLEAR % [stage_index + 1, stages.size()])
	stage_cleared.emit(stage_index)
	phase_changed.emit(phase)


func _start_stage(index: int) -> void:
	stage_index = index
	stage_started_at = RunState.game_time
	stage_starts.append(stage_started_at)
	exit_open = false
	exit_reached = false
	phase = PLAY
	stage_starting.emit(index, current_stage())
	if director and goal == &"":
		director.begin_stage(current_stage().prompt_count(), false)
	if spawner:
		spawner.enabled = _spawner_on
	_apply_spawn_preset()
	if in_parts():
		_apply_part_budget()
		RunState.wave_closed = false
		RunState.survivors_chase = false
		_clock_last = RunState.game_time   # the beat between two parts is not on the session clock
	RunState.log_event(&"stage_start", {"stage": index})
	phase_changed.emit(phase)


func _apply_spawn_preset() -> void:
	var stage := current_stage()
	if spawner and stage:
		spawner.phase_rate = stage.spawn_rate * rate_mult
		if stage_index < part_rate.size():
			spawner.phase_rate *= part_rate[stage_index]
		spawner.phase_cap = stage.spawn_cap * cap_mult


func _start_release_candidate() -> void:
	phase = RELEASE_CANDIDATE
	rc_started_at = RunState.game_time
	if spawner:
		spawner.phase_rate = Tuning.rc_spawn_rate
		spawner.phase_cap = Tuning.rc_spawn_cap
	RunState.log_event(&"release_candidate")
	if transition:
		transition.say(Dialogue.RELEASE_CANDIDATE)
	phase_changed.emit(phase)


## Seconds of the smoke test still to go; -1 when the run is not one, or once the AI
## has stopped it (the countdown never gets to finish).
func smoke_time_left() -> float:
	if smoke_duration <= 0.0 or phase != PLAY or smoke_stopped:
		return -1.0
	return maxf(0.0, smoke_duration - RunState.game_time)


## Seconds of the final wave still to survive; -1 outside it.
func rc_time_left() -> float:
	if phase != RELEASE_CANDIDATE:
		return -1.0
	return maxf(0.0, rc_started_at + Tuning.rc_duration - RunState.game_time)


func is_over() -> bool:
	return phase == OVER


## Ends the run once. Later calls are ignored.
func end(result: StringName) -> void:
	if phase == OVER:
		return
	phase = OVER
	outcome = result
	if end_reason == &"":
		end_reason = &"died" if result == &"lose" else (&"won" if result == &"win" else &"stopped")
	if spawner:
		spawner.enabled = false
	if director:
		director.enabled = false
	RunState.log_event(&"run_end", {"outcome": String(result)})
	var player := get_tree().get_first_node_in_group(&"player")
	record = Telemetry.build_record(result, {
		"type": "run",
		"build": build,
		"taste": director.taste.to_dict() if director and director.taste else {},
		"agenda_cards": director.agenda_cards() if director else 0,
		"charges": {"start": Tuning.rollback_charges_start,
				"earned": director.charges_earned if director else 0,
				"used": director.charges_earned - director.charges if director else 0},
		"reached_release_candidate": rc_started_at >= 0.0,
		"smoke_test": smoke_duration > 0.0,
		"smoke_stopped": smoke_stopped,
		"session": String(RunState.session.id) if RunState.session else "",
		"goal": {"kind": String(goal), "value": goal_value, "clock": snappedf(goal_clock, 0.01)} if goal != &"" else {},
		# M47.6c1 (design 2.10, additive): why it ended and the fixed set.
		"end": String(end_reason),
		"enemy_total": enemy_total,
		"spawned": spawner.spawned if spawner else 0,
		# M47.6c2 (design 2.10, additive): the start point, so a carried session replays.
		"start": [snappedf(start_point.x, 0.01), snappedf(start_point.y, 0.01)],
		"missing_basics": Unlocks.missing_basics().map(func(b: StringName) -> String: return String(b)),
		"bot": player != null and player.has_method(&"is_bot") and player.is_bot(),
		"invincible": RunState.invincible,
		"stages": {"set": String(stages.id) if stages else "single",
				"total": stages.size() if stages else 1,
				"reached": stage_index + 1,
				"starts": stage_starts.map(func(t: float) -> float: return snappedf(t, 0.01))},
	})
	EventBus.run_ended.emit(result)
	phase_changed.emit(phase)
	_report_at = RunState.game_time + Tuning.report_delay
	if Tuning.report_delay <= 0.0:
		_report_at = -1.0
		report_ready.emit(outcome)


func _on_player_died() -> void:
	end(&"lose")

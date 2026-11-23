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

signal phase_changed(phase: StringName)
signal report_ready(outcome: StringName)
signal stage_cleared(index: int)                       ## stage `index` is over (not the last)
signal stage_starting(index: int, stage: StageDef)     ## build stage `index` now
signal exit_opened(index: int)                         ## an EXIT stage's gate: place it now

const PLAY := &"play"
const RELEASE_CANDIDATE := &"release_candidate"
const STAGE_CLEAR := &"stage_clear"
const OVER := &"over"
## A campaign session's ending that is neither a win nor a death (PLAN v8 1.2).
const STOPPED := &"stopped"

var director: AiDirector
var spawner: Spawner
var transition: Transition
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


## Holds (true) or releases the goal clock for `owner_id`; it counts while no one holds it.
func hold_clock(owner_id: StringName, on: bool) -> void:
	if on:
		_clock_holds[owner_id] = true
	else:
		_clock_holds.erase(owner_id)


func clock_held() -> bool:
	return not _clock_holds.is_empty()


func _update_goal() -> void:
	var now := RunState.game_time
	if _clock_holds.is_empty():
		goal_clock += now - _clock_last
	_clock_last = now
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
	if stages.size() > 1 and director:
		director.begin_stage(current_stage().prompt_count(), true)
	_apply_spawn_preset()


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
	if transition:
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
	if transition:
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
	if director:
		director.begin_stage(current_stage().prompt_count(), false)
	if spawner:
		spawner.enabled = _spawner_on
	_apply_spawn_preset()
	RunState.log_event(&"stage_start", {"stage": index})
	phase_changed.emit(phase)


func _apply_spawn_preset() -> void:
	var stage := current_stage()
	if spawner and stage:
		spawner.phase_rate = stage.spawn_rate
		spawner.phase_cap = stage.spawn_cap


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

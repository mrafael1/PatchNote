class_name RunLoop
extends Node
## The run from start to report (PLAN 8).
##
## play -> (last prompt answered) -> release_candidate for Tuning.rc_duration of game
## time -> win. HP reaching 0 at any point -> lose. Once the run is over the spawner
## and the Director stop, the telemetry record is built, run_ended fires once, and
## after a short beat report_ready asks for the report. Writing the record to disk is
## the game scene's job, so tests that instance the scene never touch the real file.

signal phase_changed(phase: StringName)
signal report_ready(outcome: StringName)

const PLAY := &"play"
const RELEASE_CANDIDATE := &"release_candidate"
const OVER := &"over"

var director: AiDirector
var spawner: Spawner
var transition: Transition
var build := ""              ## game build name written to telemetry

var phase: StringName = PLAY
var outcome: StringName = &""
var rc_started_at := -1.0
var record: Dictionary = {}  ## telemetry record of the finished run

var _report_at := -1.0


func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)


func _physics_process(_delta: float) -> void:
	match phase:
		PLAY:
			if _prompts_done():
				_start_release_candidate()
		RELEASE_CANDIDATE:
			if rc_time_left() <= 0.0:
				end(&"win")
		OVER:
			if _report_at >= 0.0 and RunState.game_time >= _report_at:
				_report_at = -1.0
				report_ready.emit(outcome)


## Every prompt of the run has been opened and answered (or skipped), and its patch
## has finished applying.
func _prompts_done() -> bool:
	if director == null:
		return false
	return director.prompt_index >= Tuning.prompts_per_run and director.pending == null \
			and not (transition and transition.busy)


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
		"build": build,
		"reached_release_candidate": rc_started_at >= 0.0,
		"bot": player != null and player.has_method(&"is_bot") and player.is_bot(),
		"invincible": RunState.invincible,
	})
	EventBus.run_ended.emit(result)
	phase_changed.emit(phase)
	_report_at = RunState.game_time + Tuning.report_delay
	if Tuning.report_delay <= 0.0:
		_report_at = -1.0
		report_ready.emit(outcome)


func _on_player_died() -> void:
	end(&"lose")

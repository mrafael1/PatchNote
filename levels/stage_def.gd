class_name StageDef
extends Resource
## One stage of a run (PLAN v6 4): where it is played and when it ends. A StageSet
## lists them in order; the run loop plays them, the genre builds them.

const SURVIVE := &"survive"   ## ends once its prompts are done and `duration` has passed
## Breakout (M35): once its prompts are done and `duration` has passed an exit gate
## opens (ExitGate); the stage ends when the player reaches it.
const EXIT := &"exit"
const GOALS: Array[StringName] = [SURVIVE, EXIT]

@export var arena: ArenaDef
## Seconds of play before the stage can end (counted from its start). 0: it ends as
## soon as its prompts are done (the one-stage v0.0 run).
@export var duration := 0.0
## How the stage ends: SURVIVE or EXIT.
@export var goal: StringName = SURVIVE
## Small prompts opened during this stage. -1: Tuning.prompts_per_run (the v0.0 run).
@export var prompts := 1
## The spawn preset: multipliers on the spawner's rate and cap for this stage.
@export var spawn_rate := 1.0
@export var spawn_cap := 1.0


func prompt_count() -> int:
	return Tuning.prompts_per_run if prompts < 0 else prompts

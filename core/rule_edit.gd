class_name RuleEdit
extends Mutation
## A rule edit (PLAN v8 1.4): the AI changes one rule of the game in front of the
## player, says so first, and (usually) puts it back. It lives in RunState.ai with the
## owner &"edit", so add_ai / remove_ai / expire_ai recompute the rules, reach the live
## entities, log, and keep the reversibility invariant. RuleBook (a campaign shell node)
## requests it: the warning, the landing, the expiry.
##
## Data: rules/<id>/<id>.tres with its script rules/<id>/<id>.gd (extends RuleEdit,
## overrides apply_rules and the hooks itself). Loaded .tres files are shared for the
## process: an edit keeps no per-run data (RuleBook keeps the timers).

## What it changes, for the warning icon.
const TARGETS: Array[StringName] = [&"walls", &"enemies", &"player", &"world", &"game"]
## Where the mascot points during the warning.
const POINTS: Array[StringName] = [&"player", &"nearest_enemy", &"walls", &"centre"]

@export var target: StringName = &"game"
@export var warn_line := ""         ## Line syntax: what the AI says before it lands ("" = nothing)
@export var done_line := ""         ## Line syntax: what it says once it expires ("" = nothing)
@export var warn_seconds := 1.5     ## the warning lasts this long, then the edit lands
@export var duration := 0.0         ## seconds live; 0 = until the session ends
@export var point_at: StringName = &"centre"
## Flashes or shakes: with reduce_flashing on, the edit plays its gentle variant.
@export var photosensitive := false


## Always AI-tier: it lives in RunState.ai, never in the stack.
func is_ai_tier() -> bool:
	return true


## The gentle variant applies (a photosensitive edit, reduce_flashing on).
func gentle() -> bool:
	return photosensitive and SaveGame.reduce_flashing()


func warn() -> Line:
	return Line.parse(warn_line) if warn_line != "" else null


func done() -> Line:
	return Line.parse(done_line) if done_line != "" else null


## A visual help shown on the player while this edit is new (M43.2, G13b: the flip's
## arrows), or null. Presentation only, campaign only: RuleBook adds it under the
## player when the edit lands and frees it when the edit ends. Never gameplay state.
func landed_hint(_player: Node2D) -> Node2D:
	return null

class_name Genre
extends Node
## The base every genre extends (PLAN v5 1.1). A genre owns its run: its nodes (arena,
## world, player, camera, spawner, overlays), its pacing and its controls. The shell
## (main.gd) owns only what every genre shares, and never asks a genre how it runs.
##
## The contract, in order:
##   build(shell)    add the genre's own nodes under itself and place the player
##   begin_run()     the shell's nodes exist; wire to them and start the run
## and the genre tells the shell exactly two things, through its signals:
##   stage_ended(index)   a stage is over (no genre has stages yet)
##   run_ended(outcome)   the run is over and run_record() holds its telemetry record
## Patch prompts are still paced by the Director's rule (kills and gaps in game seconds),
## which suits the only genre so far; Phase 5 hands prompt points to the genres.

signal stage_ended(index: int)
signal run_ended(outcome: StringName)

var shell: Node               ## the game scene (Main)
var def: GenreDef             ## this genre's definition
var record: Dictionary = {}   ## telemetry record of the finished run (see run_record)

## Shared presentation the shell wires to the genre's nodes. Either may stay null in a
## genre that has no camera or no world (the shell copes).
var camera: Camera2D
var world: Node2D
var player: Node2D


func build(p_shell: Node) -> void:
	shell = p_shell


func begin_run() -> void:
	pass


## The finished run's telemetry record (empty until the run is over).
func run_record() -> Dictionary:
	return record


## True once the run is over (the shell saves notes and allows "New build" then).
func is_over() -> bool:
	return false

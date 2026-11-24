extends SceneTree
## The Stage 2 lines file (PLAN v9 0.4, M47): every line the owner reads in Stage 2, from the
## data, so a tone edit is a data edit plus a regenerate. GUT's test_lines_file_is_up_to_date
## regenerates it in memory and compares it with the committed file.
##
##   godot --headless --path . -s tools/lines_file.gd
##
## Writes campaign/lines_stage2.md (campaign/lines_render.gd builds the text): the stage
## card's line and S7's cook beat; per Stage 2 session its intro, every cue line with its
## time and condition (path warnings included), its debrief and after-pick lines;
## fork_path's question and cards (title, pitch, take line); each path's warn / full / pick
## line; PathRunner's pick lines.

const OUT := "res://campaign/lines_stage2.md"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var text: String = load("res://campaign/lines_render.gd").call(&"render")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("[lines_file] wrote %s" % OUT)
	quit(0)

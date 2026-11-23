extends SceneTree
## Draws every mascot body in every expression (PLAN v8 M38, G13a) and saves one sheet
## per body to .check/mascot_<body>.png: the 8 expressions in a row, then the same 8
## talking, and pointing / glitching at the end. Needs a real window (the headless
## renderer draws nothing):
##
##   godot --path . -s tools/mascot_capture.gd -- [body ...]   (default: all four)
##
## Not part of the game.

const OUT := "res://.check/mascot_%s.png"
const CELL := Vector2(150, 175)
const BODY_SCALE := 1.15
const MOMENT := 0.55   ## seconds into each animation: mid-bounce, eyes open


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[mascot] FAILED: needs a window, run without --headless")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var ids: Array = args if not args.is_empty() else ["cursor", "window", "blob", "caret"]
	var failures := 0
	for body_id in ids:
		var sheet := _sheet(StringName(body_id))
		root.add_child(sheet)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var rows := 3
		var cut := image.get_region(Rect2i(Vector2i.ZERO, Vector2i(int(CELL.x * 8), int(CELL.y * rows) + 10)))
		var path := OUT % body_id
		var err := cut.save_png(path)
		if err != OK:
			failures += 1
		print("[mascot] %s -> %s (%s)" % [body_id, ProjectSettings.globalize_path(path), error_string(err)])
		sheet.queue_free()
		await process_frame
	quit(1 if failures > 0 else 0)


func _sheet(body_id: StringName) -> Control:
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(bg)
	var expressions: Array[StringName] = Line.EXPRESSIONS
	for row in 3:
		for i in expressions.size():
			var cell := Vector2(i * CELL.x, row * CELL.y)
			var b := MascotBody.make(body_id)
			b.frozen = true
			b.position = cell + Vector2(CELL.x * 0.5, CELL.y * 0.45)
			b.scale = Vector2.ONE * BODY_SCALE
			sheet.add_child(b)
			b.set_expression(expressions[i])
			var caption := String(expressions[i])
			if row == 1:
				b.say_start()
				caption += " · talking"
			elif row == 2:
				if i == 0:
					b.point_at(b.position + Vector2(200, 0), 5.0)
					caption = "point →"
				elif i == 1:
					b.point_at(b.position + Vector2(-100, 120), 5.0)
					caption = "point ↙"
				elif i == 2:
					b.glitch(5.0)
					caption = "glitch"
				else:
					b.queue_free()
					continue
			b.advance(MOMENT + 0.13 * i)
			var label := Label.new()
			label.text = caption
			label.position = cell + Vector2(8, CELL.y - 30)
			label.add_theme_font_size_override(&"font_size", 14)
			label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
			sheet.add_child(label)
	return sheet

extends SceneTree
## Draws every mascot body in every expression (PLAN v8 M38, G13a) and saves one sheet
## per body to .check/mascot_<body>.png: the 8 expressions in a row, then the same 8
## talking, and pointing / glitching at the end. M51a: --pixel draws each body through
## PixelBodyView (the pixel look's body style) to .check/mascot_<body>_pixel.png, with a
## fourth row at the corner's size; --chat instead saves the always-on chat (a tool host,
## inert save) with each creature in its header to .check/mascot_chat_<body>[_pixel].png.
## Needs a real window (the headless renderer draws nothing):
##
##   godot --path . -s tools/mascot_capture.gd -- [--pixel] [--chat] [body ...]   (default: all)
##
## Not part of the game.

const OUT := "res://.check/mascot_%s.png"
const CELL := Vector2(150, 175)
const BODY_SCALE := 1.15
const MOMENT := 0.55   ## seconds into each animation: mid-bounce, eyes open
const CORNER := 1.12   ## the corner's body scale (Mascot.SIZE / 100)
## Loaded at run time (M51a): a class name here compiles the game's scripts before the
## autoloads exist, which leaves Skins without its hub (as campaign_shots.gd notes).
const BODY_PATH := "res://ui/mascot/mascot_body.gd"
const VIEW_PATH := "res://ui/mascot/pixel_body_view.gd"
const LINE_PATH := "res://campaign/line.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[mascot] FAILED: needs a window, run without --headless")
		quit(1)
		return
	var all := OS.get_cmdline_user_args()
	var pixel := all.has("--pixel")
	var chat := all.has("--chat")
	var args: Array = Array(all).filter(func(a: String) -> bool: return not a.begins_with("--"))
	var ids: Array = args if not args.is_empty() else (["cursor", "window", "blob"] if chat else ["cursor", "window", "blob", "caret"])
	if pixel and chat:   # the sheets wrap each body themselves; the chat reads the look
		var skins: GDScript = load("res://systems/skins/skins.gd")
		skins.call(&"use", skins.call(&"pixel"))
		skins.call(&"reveal_all")
	if chat:
		quit(await _chats(ids, pixel))
		return
	var failures := 0
	for body_id in ids:
		var sheet := _sheet(StringName(body_id), pixel)
		root.add_child(sheet)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var rows := 4 if pixel else 3
		var cut := image.get_region(Rect2i(Vector2i.ZERO, Vector2i(int(CELL.x * 8), int(CELL.y * rows) + 10)))
		var path := OUT % (String(body_id) + ("_pixel" if pixel else ""))
		var err := cut.save_png(path)
		if err != OK:
			failures += 1
		print("[mascot] %s -> %s (%s)" % [body_id, ProjectSettings.globalize_path(path), error_string(err)])
		sheet.queue_free()
		await process_frame
	quit(1 if failures > 0 else 0)


## M51a: the dev-chat (TerminalPanel in its chat style, as the game shows it past S2) with
## each body in its header and beside its bubbles, plus the same body in the corner's size.
func _chats(ids: Array, pixel: bool) -> int:
	var failures := 0
	var lines := [["Welcome back. I kept the lights on.", &"happy"], ["Too much brick. One second.", &"worried"],
			["My first asset! Look at it. LOOK at it.", &"proud"]]
	for body_id in ids:
		var term: Control = load("res://ui/always_on/terminal.gd").new()
		term.size = Vector2(480, 720)
		root.add_child(term)
		term.call(&"set_style", &"chat")
		term.call(&"dress")
		term.call(&"set_speaker", "", true, StringName(body_id))
		for l in lines:
			var label: Label = term.call(&"say_row", l[0], l[1])
			label.visible_characters = -1   # typed out
		term.call(&"finish")
		var corner: Variant = load(BODY_PATH).make(StringName(body_id))
		var holder: Node2D = corner
		if pixel:
			holder = load(VIEW_PATH).wrap(corner, CORNER)
		else:
			corner.scale = Vector2.ONE * CORNER
		holder.position = Vector2(1280 - 16 - 56, 76 + 56)
		root.add_child(holder)
		corner.set_expression(&"happy")
		for i in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "res://.check/mascot_chat_%s%s.png" % [body_id, "_pixel" if pixel else ""]
		var chat: Variant = term.get(&"chat")
		var err := root.get_texture().get_image().save_png(path)
		if err != OK or chat == null:
			failures += 1
		print("[mascot] chat %s -> %s (%s, chat %s)" % [body_id, ProjectSettings.globalize_path(path), error_string(err), chat != null])
		term.queue_free()
		holder.queue_free()
		await process_frame
		await process_frame
	return 1 if failures > 0 else 0


func _sheet(body_id: StringName, pixel := false) -> Control:
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(bg)
	var expressions: Array = load(LINE_PATH).EXPRESSIONS
	for row in (4 if pixel else 3):
		for i in expressions.size():
			var cell := Vector2(i * CELL.x, row * CELL.y)
			var b: Variant = load(BODY_PATH).make(body_id)
			b.frozen = true
			var at := cell + Vector2(CELL.x * 0.5, CELL.y * 0.45)
			var v: Node2D = null
			if pixel:
				v = load(VIEW_PATH).wrap(b, BODY_SCALE if row < 3 else CORNER)
				v.position = at
				sheet.add_child(v)
			else:
				b.position = at
				b.scale = Vector2.ONE * BODY_SCALE
				sheet.add_child(b)
			b.set_expression(expressions[i])
			var caption := String(expressions[i])
			if row == 3:
				caption += " · corner"
			elif row == 1:
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
					if v != null:
						v.queue_free()
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

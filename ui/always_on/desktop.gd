class_name DevDesktop
extends Control
## M47.6b (PLAN v9.4 0.8, design 2.1, mockup 1 "perfect"): the dev desktop behind the always-on
## host. Two raw OS-style windows on a dark desktop with a faint 32 px grid, top edges aligned,
## a gap between them, and a thin taskbar at the bottom:
## - the game window: a title bar ("Patch Notes - v0.1.0 (debug)", the version live), the game
##   column (GameHost's SubViewport sits in it), a status bar (FPS, nodes, the session and its
##   newest basic, 1280x720);
## - the chat window: a title bar ("dev-chat"), the TerminalPanel below it. After S2's chat
##   upgrade (TerminalPanel.style CHAT) its frame turns into the chat app's rounded one
##   ("dev-chat - Blob").
## Code-drawn (no image files), colours from Palette's DESK_* / CHAT_* constants, no real
## product names (the repo is public; inspirations are for mechanics only). Presentation only:
## it reads the host's layout and public counts, never the sim. Mouse: ignored (the game
## column and the chat take their own events).

const GRID := 32.0
const TITLE_FONT := 12
const STATUS_FONT := 11
const RADIUS := 12               ## the chat app's rounded frame
const REFRESH_S := 0.5           ## the status bar's FPS / nodes refresh (real time)

var layout := {}                 ## GameHost.layout_for(): game, game_window, chat_window, taskbar
var game_title := "Patch Notes"
var version := ""                ## "v0.1.0"
var stage_text := ""             ## "S1 movement: ON"
var chat_style: StringName = TerminalPanel.RAW
var chat_name := "AI"            ## the chat app's title ("dev-chat - Blob")
var chat_focus := true           ## the chat window is the active one (a gate, a beat)
var clock := "14:00"
var fps := 60
var nodes := 0
var _refresh := 0.0


func _ready() -> void:
	name = "Desktop" if name == "" else name
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS



func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_S
	fps = roundi(Engine.get_frames_per_second())
	nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	queue_redraw()


## The game window's title ("Patch Notes - v0.1.0 (debug)").
func title_text() -> String:
	return "%s - %s (debug)" % [game_title, version] if version != "" else game_title


## The chat window's title: "dev-chat" (raw), "dev-chat - Blob" (the chat app).
func chat_title() -> String:
	return "dev-chat - %s" % chat_name if chat_style == TerminalPanel.CHAT else "dev-chat"


## The status bar's left text.
func status_text() -> String:
	return "FPS %d | nodes %d | debug" % [fps, nodes]


func _draw() -> void:
	if layout.is_empty() or not layout.has("game_window"):
		return
	var font := UiTheme.sans_font()
	var mono := UiTheme.mono_font()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.DESK_BG)
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Palette.DESK_GRID, 1.0)
		x += GRID
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Palette.DESK_GRID, 1.0)
		y += GRID
	var gw: Rect2 = layout.game_window
	var cw: Rect2 = layout.chat_window
	for w: Rect2 in [gw, cw]:
		draw_rect(Rect2(w.position + Vector2(0, 10), w.size + Vector2(0, 8)).grow(4), Palette.DESK_SHADOW)
	# The game window: border, title bar, status bar.
	draw_rect(gw.grow(1), Palette.DESK_EDGE)
	draw_rect(gw, Palette.DESK_WIN)
	var bar := Rect2(gw.position, Vector2(gw.size.x, GameHost.TITLE_H))
	_title_bar(bar, title_text(), not chat_focus, font, &"game")
	var status := Rect2(Vector2(gw.position.x, gw.end.y - GameHost.STATUS_H), Vector2(gw.size.x, GameHost.STATUS_H))
	draw_rect(status, Palette.DESK_WIN)
	draw_line(status.position, Vector2(status.end.x, status.position.y), Palette.DESK_EDGE, 1.0)
	var sy := status.position.y + status.size.y * 0.5 + STATUS_FONT * 0.35
	draw_string(mono, Vector2(status.position.x + 10, sy), status_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, STATUS_FONT, Palette.DESK_STATUS)
	draw_string(mono, Vector2(status.position.x + 260, sy), stage_text, HORIZONTAL_ALIGNMENT_LEFT, -1, STATUS_FONT, Palette.DESK_STATUS)
	draw_string(mono, Vector2(status.position.x, sy), "1280x720", HORIZONTAL_ALIGNMENT_RIGHT, status.size.x - 10, STATUS_FONT, Palette.DESK_STATUS)
	# The chat window: a raw OS frame, or the chat app's rounded one.
	var cbar := Rect2(cw.position, Vector2(cw.size.x, GameHost.TITLE_H))
	if chat_style == TerminalPanel.CHAT:
		var frame := StyleBoxFlat.new()
		frame.bg_color = Palette.CHAT_BG
		frame.border_color = Palette.CHAT_EDGE
		frame.set_border_width_all(1)
		frame.set_corner_radius_all(RADIUS)
		frame.shadow_color = Color(Palette.CHAT_ACCENT, 0.18)
		frame.shadow_size = 14
		frame.draw(get_canvas_item(), cw.grow(1))
		var top := StyleBoxFlat.new()
		top.bg_color = Palette.CHAT_BAR
		top.corner_radius_top_left = RADIUS
		top.corner_radius_top_right = RADIUS
		top.draw(get_canvas_item(), cbar)
		draw_line(Vector2(cbar.position.x, cbar.end.y), Vector2(cbar.end.x, cbar.end.y), Palette.CHAT_RULE, 1.0)
		_icon(&"chat", Vector2(cbar.position.x + 12, cbar.position.y + 7), Palette.CHAT_ACCENT)
		var ty := cbar.position.y + cbar.size.y * 0.5 + TITLE_FONT * 0.35
		draw_string(UiTheme.sans_font(true), Vector2(cbar.position.x + 36, ty), "dev-chat", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT + 1, Palette.CHAT_TEXT)
		var w := UiTheme.sans_font(true).get_string_size("dev-chat", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT + 1).x
		draw_string(font, Vector2(cbar.position.x + 42 + w, ty), "- " + chat_name, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT, Palette.CHAT_DIM)
		_controls(cbar, Palette.CHAT_DIM)
	else:
		draw_rect(cw.grow(1), Palette.DESK_EDGE)
		draw_rect(cw, Palette.TERM_BG)
		_title_bar(cbar, chat_title(), chat_focus, font, &"terminal")
	_taskbar(font, mono)


func _title_bar(r: Rect2, text: String, active: bool, font: Font, icon: StringName) -> void:
	draw_rect(r, Palette.DESK_BAR if active else Palette.DESK_BAR_IDLE)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Palette.DESK_EDGE, 1.0)
	var ink := Palette.DESK_TITLE if active else Palette.DESK_TITLE_IDLE
	_icon(icon, Vector2(r.position.x + 10, r.position.y + 7), ink)
	draw_string(font, Vector2(r.position.x + 34, r.position.y + r.size.y * 0.5 + TITLE_FONT * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 34 - 140, TITLE_FONT, ink)
	_controls(r, ink)


## Minimise, maximise, close (drawn, not buttons: the windows are the game's set dressing).
func _controls(r: Rect2, ink: Color) -> void:
	var c := Vector2(r.end.x - 22 - 88, r.position.y + r.size.y * 0.5)
	draw_line(c + Vector2(-5, 0.5), c + Vector2(5, 0.5), ink, 1.0)
	c.x += 44
	draw_rect(Rect2(c - Vector2(4.5, 4.5), Vector2(9, 9)), ink, false, 1.0)
	c.x += 44
	draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), ink, 1.0)
	draw_line(c + Vector2(5, -5), c + Vector2(-5, 5), ink, 1.0)


## A 16 px glyph: the game (a square), the terminal (a prompt), the chat (a bubble), the grid.
func _icon(kind: StringName, at: Vector2, ink: Color) -> void:
	match kind:
		&"game":
			draw_rect(Rect2(at + Vector2(3, 3), Vector2(10, 10)), ink, false, 1.4)
		&"terminal":
			draw_rect(Rect2(at + Vector2(1.5, 2.5), Vector2(13, 11)), ink, false, 1.2)
			draw_polyline(PackedVector2Array([at + Vector2(4, 6), at + Vector2(6.5, 8), at + Vector2(4, 10)]), ink, 1.2)
			draw_line(at + Vector2(8, 10.5), at + Vector2(12, 10.5), ink, 1.2)
		&"chat":
			var box := StyleBoxFlat.new()
			box.bg_color = Color(ink, 0.0)
			box.border_color = ink
			box.set_border_width_all(1)
			box.set_corner_radius_all(4)
			box.draw(get_canvas_item(), Rect2(at + Vector2(1, 2), Vector2(14, 10)))
			draw_line(at + Vector2(4, 12), at + Vector2(3, 15), ink, 1.2)
		&"grid":
			for p: Vector2 in [Vector2(2, 2), Vector2(9, 2), Vector2(2, 9), Vector2(9, 9)]:
				draw_rect(Rect2(at + p, Vector2(5, 5)), ink, false, 1.2)


func _taskbar(font: Font, mono: Font) -> void:
	var t: Rect2 = layout.taskbar
	draw_rect(t, Palette.DESK_TASK)
	draw_line(t.position, Vector2(t.end.x, t.position.y), Palette.DESK_TASK_EDGE, 1.0)
	var cy := t.position.y + t.size.y * 0.5
	_icon(&"grid", Vector2(t.position.x + 14, cy - 8), Palette.DESK_TAB_LINE)
	var x := t.position.x + 44
	for tab: Array in [[&"game", "game", not chat_focus], [&"terminal" if chat_style != TerminalPanel.CHAT else &"chat", "dev-chat", chat_focus]]:
		var label: String = tab[1]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT).x + 44
		var r := Rect2(x, t.position.y + 4, w, t.size.y - 8)
		if tab[2]:
			draw_rect(r, Palette.DESK_TAB_ON)
			draw_rect(r, Palette.DESK_EDGE, false, 1.0)
			draw_line(Vector2(r.position.x, r.end.y - 1), Vector2(r.end.x, r.end.y - 1), Palette.DESK_TAB_LINE, 2.0)
		_icon(tab[0], Vector2(r.position.x + 10, cy - 8), Palette.DESK_TITLE)
		draw_string(font, Vector2(r.position.x + 32, cy + TITLE_FONT * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT, Palette.DESK_TITLE)
		x += w + 6
	var right := "build: %s    %s" % [version if version != "" else "v0.0.0", clock]
	draw_string(mono, Vector2(t.position.x, cy + TITLE_FONT * 0.35), right, HORIZONTAL_ALIGNMENT_RIGHT, t.size.x - 16, TITLE_FONT, Palette.DESK_TITLE)

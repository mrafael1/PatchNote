extends Control
## M48.6c: the cabinet's dev-chat (PLAN 0.9.2 "The chat"; the owner-approved pixel mockup's
## .chat block), filling the chat column beside the cabinet. Top to bottom, inside the kit's
## `chat` frame (CabinetLayout.chat_parts):
## - the header: the AI's small body in its box, its name, "your developer (AI)", a status dot
##   and "live · patching", the version on a gold plate;
## - the build log: the last two `$` rows;
## - the messages: the AI's rows (its name and mood over the first bubble of a run, a letter
##   box beside each bubble), the player's replies as right-aligned bubbles, dividers, PATCH
##   cards (ADD / CHANGE / FIX tags), HOTFIX slips, an open ask's options in full, the
##   thinking dots; the newest row at the bottom, the wheel scrolls back;
## - the reply pills: "[1] ..." per open choice (the first one lit), or `play` at a gate;
## - the input line: the terminal's own ChatInput (its ghost `play`, "Talk to <name>...",
##   what is typed) and a send key.
##
## It is a drawing of the terminal's rows, not a second chat: items() reads
## TerminalPanel.row_nodes() every frame (the rows the rail's chat dressed), so the debrief,
## the host, main's edit rows and the corner's lines keep their API, their Label handles and
## their timing (a row typing itself shows as many characters as its label does). A click on
## a pill or on an option emits terminal.chosen(index), the gate's pill gives play, as the
## rail's reply box did.
##
## One pixel grid (CabinetArt's 9-slices at the frame's art px), the pixel font at 2 screen px
## per font pixel. Presentation only, real time only. What moves by itself: the status dot,
## the thinking dots and a new row's hop, each still under reduce flashing.

const Chat := preload("res://ui/rail/rail_chat.gd")
const Reply := preload("res://ui/rail/rail_reply.gd")
const Blob := preload("res://ui/rail/rail_blob.gd")

const ROW := 7                  ## a text row's step, art px
const PAD := 3                  ## the messages' side pad, art px
const GAP := 3                  ## between two rows of the chat, art px
const AVATAR := 9               ## the letter box beside the AI's bubbles, art px
const BUBBLE_PAD := 4           ## a bubble's edge to its text, art px
const LOG_ROWS := 2
const POP_S := 0.12
const WHEEL_ROWS := 3.0
const ROLE := "your developer (AI)"
const LIVE := "live · patching"
## A changelog row's section -> [the tag's 9-slice, its text, its ink].
const TAGS := {"Added": [&"tag_add", "ADD", &"t_add_ink"], "Changed": [&"tag_chg", "CHANGE", &"t_chg_ink"],
		"Fixed": [&"tag_fix", "FIX", &"t_fix_ink"]}

var frame: Node                 ## the CabinetFrame
var avatar: Control             ## the AI's body in the header (the rail's body holder)
var messages: Control           ## the clipped messages area
var scroll := 0.0               ## px scrolled back from the newest row (0: at the end)
var gentle := false             ## nothing moves whatever the setting (tests)

var _wraps := {}
var _seen := {}                 ## row id -> usec first laid out (the hop)
var _primed := false            ## rows already there when the chat showed do not hop
var _laid: Array[Dictionary] = []
var _total := 0.0
var _drawn_total := 0.0         ## the content's height at the last draw (a change snaps to the end)
var _avatar_rect := Rect2()
var _start_usec := 0
var _next_id := 1               ## a row's own number (its `chat_id` meta), given when first read


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_start_usec = Time.get_ticks_usec()
	messages = Control.new()
	messages.name = "Messages"
	messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	messages.clip_contents = true
	messages.draw.connect(_draw_messages)
	add_child(messages)
	avatar = Blob.new()
	avatar.name = "Avatar"
	avatar.set(&"frame", frame)
	add_child(avatar)
	avatar.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_primed = false
		scroll = 0.0


func _process(_delta: float) -> void:
	if frame == null or not bool(frame.get(&"on")):
		return
	_place_parts()
	queue_redraw()
	messages.queue_redraw()


## The frame's layout: the chat column's rect.
func place(r: Rect2) -> void:
	position = r.position
	size = r.size
	if messages != null:
		_place_parts()


func terminal() -> TerminalPanel:
	return frame.host.get(&"terminal") if frame != null and frame.get(&"host") != null else null


func art() -> float:
	return float(frame.call(&"art")) if frame != null else CabinetLayout.ART


func text_size() -> int:
	return CabinetLayout.text_px(2, float(frame.call(&"s")) if frame != null else 1.0)


func name_size() -> int:
	return CabinetLayout.text_px(3, float(frame.call(&"s")) if frame != null else 1.0)


## The chat's parts in this control's own px (CabinetLayout.chat_parts, with the pills on show).
func parts() -> Dictionary:
	return CabinetLayout.chat_parts(Rect2(Vector2.ZERO, size), art(), pill_rows())


func _place_parts() -> void:
	var p := parts()
	var m: Rect2 = p.messages
	messages.position = m.position
	messages.size = m.size
	var box := avatar_rect().grow(-2.0 * art())
	if box != _avatar_rect:
		_avatar_rect = box
		avatar.call(&"place", box)
	layout_input()


# --- The reading: the terminal's rows as the chat's items ---------------------------------------

## The open question (the rail reply box's reading): {question, who, choices, prompt, gate}.
func state() -> Dictionary:
	return Reply.state_of(terminal())


## The build log's rows on show: the last LOG_ROWS `$` rows, without their "$ ".
func log_rows() -> Array[String]:
	var out: Array[String] = []
	var t := terminal()
	if t == null:
		return out
	var rows := t.row_nodes()
	for i in range(rows.size() - 1, -1, -1):
		if Chat.kind_of(rows[i]) == TerminalPanel.Row.CMD and not rows[i].is_queued_for_deletion():
			out.push_front(Chat.label_text(rows[i]).trim_prefix("$ "))
			if out.size() >= LOG_ROWS:
				break
	return out


## "[14:02] blob@patchnotes (happy)" -> ["blob", "happy"].
static func head_parts(text: String) -> Array[String]:
	var who := text
	var mood := ""
	var at := who.find(" ")
	if at >= 0:
		who = who.substr(at + 1)
	var open := who.find(" (")
	if open >= 0:
		mood = who.substr(open + 2).trim_suffix(")")
		who = who.substr(0, open)
	return [who.trim_suffix("@patchnotes"), mood]


## "  + Added shooting" -> ["Added", "Shooting"] (TerminalPanel.note_text, read back; the
## item's capital is back, as the changelog wrote it).
static func note_parts(text: String) -> Array[String]:
	var t := text.strip_edges()
	if t.length() > 2 and t[0] in ["+", "~", "-"] and t[1] == " ":
		t = t.substr(2)
	var section := "Added"
	for s: String in TAGS:
		if t.begins_with(s + " "):
			section = s
			t = t.substr(s.length() + 1)
			break
	return [section, t.left(1).to_upper() + t.substr(1)]


## The messages, oldest first. Each is {kind, id, ...}:
## - &"ai": text, chars (-1 all), dim (chatter), who, mood (both "" inside a run);
## - &"you": text (the answer as the player reads it: the choice's name, or what was typed);
## - &"divider": text;
## - &"patch": version, rows ([section, text] each);
## - &"hotfix": label ("v0.8.1+1"), text;
## - &"option": index, head ("[1] tank"), text (its description): an open ask's choice in full;
## - &"think": who (while the spinner runs).
## A `$` row is in the build log only; a header row names the bubbles after it; a closed
## prompt and an answered ask's choices are not shown.
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := terminal()
	if t == null:
		return out
	var rows := t.row_nodes()
	var think := t.thinking_row()
	# The open ask's choices: the CHOICE rows right before the open `you>` row.
	var open_from := rows.size()
	if t.has_prompt():
		var you := -1
		for i in range(rows.size() - 1, -1, -1):
			if Chat.kind_of(rows[i]) == TerminalPanel.Row.YOU:
				you = i
				break
		open_from = you
		while open_from > 0 and Chat.kind_of(rows[open_from - 1]) == TerminalPanel.Row.CHOICE:
			open_from -= 1
		if you < 0:
			open_from = rows.size()
	var who := ""
	var mood := ""
	var card := {}
	for i in rows.size():
		var r := rows[i] as Control
		if r == null or r.is_queued_for_deletion():
			continue
		var kind := Chat.kind_of(r)
		var text := Chat.label_text(r)
		if not r.has_meta(&"chat_id"):
			r.set_meta(&"chat_id", _next_id)
			_next_id += 1
		var id := int(r.get_meta(&"chat_id"))
		if kind != TerminalPanel.Row.NOTE:
			card = {}
		match kind:
			TerminalPanel.Row.HEAD:
				var hp := head_parts(text)
				who = hp[0]
				mood = hp[1]
			TerminalPanel.Row.SAY:
				var l := r.get_node_or_null(^"Text") as Label
				out.append({"kind": &"ai", "id": id, "text": text, "who": who, "mood": mood,
						"chars": l.visible_characters if l != null else -1,
						"dim": l != null and l.clip_text})
				who = ""
				mood = ""
			TerminalPanel.Row.CMD:
				if r.has_meta(&"hotfix"):
					var note := String(r.get_meta(&"hotfix_body", ""))
					out.append({"kind": &"hotfix", "id": id, "label": String(r.get_meta(&"hotfix")),
							"text": note if note != "" else text.trim_prefix("$ ").trim_suffix(" ... ok")})
				elif text.begins_with(Chat.PATCH):
					card = {"kind": &"patch", "id": id, "version": text.substr(Chat.PATCH.length()).get_slice(" ", 0),
							"rows": []}
					out.append(card)
			TerminalPanel.Row.NOTE:
				if card.is_empty():
					card = {"kind": &"patch", "id": id, "version": "", "rows": []}
					out.append(card)
				(card.rows as Array).append(note_parts(text))
			TerminalPanel.Row.THINK:
				if r == think:
					out.append({"kind": &"think", "id": id, "who": t.header_name()})
			TerminalPanel.Row.CHOICE:
				if i >= open_from and text.contains("  "):
					var head := text.get_slice("  ", 0)
					out.append({"kind": &"option", "id": id, "index": i - open_from, "head": head,
							"text": text.substr(head.length()).strip_edges()})
			TerminalPanel.Row.YOU:
				if Chat.answered(text):
					var said: String = frame.chat.call(&"_answer_text", rows, i)
					out.append({"kind": &"you", "id": id, "text": TerminalPanel.pill_label(said)})
			TerminalPanel.Row.SYS:
				out.append({"kind": &"divider", "id": id, "text": text.trim_prefix("--- ").trim_suffix(" ---")})
		if kind != TerminalPanel.Row.SAY and kind != TerminalPanel.Row.HEAD:
			who = ""
			mood = ""
	return out


## The item kinds on show, in order (tests, captures).
func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for it in items():
		out.append(it.kind)
	return out


# --- Text ---------------------------------------------------------------------------------------

func text_w(t: String, bold := false, size := -1) -> float:
	return RailFrame.text_w(t, size if size > 0 else text_size(), bold)


## `t` in rows no wider than `width` (greedy, on spaces; a word wider than the row breaks
## inside). Cached.
func wrap_text(t: String, width: float, bold := false) -> PackedStringArray:
	var size := text_size()
	var key := "%d|%d|%d|%s" % [size, int(width), int(bold), t]
	var hit: Variant = _wraps.get(key)
	if hit != null:
		return hit
	var out := PackedStringArray()
	for para in t.split("\n"):
		var row := ""
		for word in para.split(" ", false):
			var want := word if row == "" else row + " " + word
			if RailFrame.text_w(want, size, bold) <= width:
				row = want
				continue
			if row != "":
				out.append(row)
			row = word
			while RailFrame.text_w(row, size, bold) > width and row.length() > 1:
				var n := row.length() - 1
				while n > 1 and RailFrame.text_w(row.left(n), size, bold) > width:
					n -= 1
				out.append(row.left(n))
				row = row.substr(n)
		out.append(row)
	if _wraps.size() > 1200:
		_wraps.clear()
	_wraps[key] = out
	return out


## `t` cut to `width` (".." at the cut).
func clip(t: String, width: float, bold := false) -> String:
	if text_w(t, bold) <= width:
		return t
	var n := t.length()
	while n > 0 and text_w(t.left(n) + "..", bold) > width:
		n -= 1
	return t.left(n) + ".."


## The widest of `rows`, in px.
func rows_w(rows: PackedStringArray, bold := false) -> float:
	var w := 0.0
	for r in rows:
		w = maxf(w, text_w(r, bold))
	return w


## Text with its capitals' top at `cap_top` (the font's capitals are 7 of its 11 design px).
func cap(ci: CanvasItem, x: float, cap_top: float, t: String, color: Color, bold := false,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, size := -1) -> void:
	var fs := size if size > 0 else text_size()
	var f := UiTheme.pixel_font(bold)
	RailFrame.text(ci, Vector2(roundf(x), roundf(cap_top - (f.get_ascent(fs) - fs * 7.0 / 11.0))), t, fs, color, bold,
			align, width)


## A text row's step in screen px: ROW art px, never tighter than the font's own line (a
## small window keeps the text at 22 px while the art shrinks).
func row_px() -> float:
	return maxf(roundf(ROW * art()), roundf(text_size() * 21.0 / 22.0))


## A row slot's top -> its capitals' top (the text centred in the row).
func row_cap(y: float) -> float:
	return y + roundf((row_px() - text_size() * 7.0 / 11.0) * 0.5)


# --- The layout of the messages -----------------------------------------------------------------

## Art px rounded up to whole art px, in screen px.
func snap_up(w: float) -> float:
	var a := art()
	return ceilf(w / a - 0.001) * a


## Lays the items out for the messages area's width: each gets `rect` (its whole slot, y from
## the top of the content), and what its drawing needs (`box` the bubble or card, `lines`).
## Returns them; total_height() is the content's height.
func lay() -> Array[Dictionary]:
	var a := art()
	var w := messages.size.x if messages != null and messages.size.x > 1.0 else size.x - 2.0 * CabinetLayout.CHAT_RING * a
	var pad := PAD * a
	var row := row_px()
	var col_x := pad + (AVATAR + 2) * a            # the AI's bubbles start right of the letter box
	var right := w - pad - a                       # the drop shadow stays inside
	var list := items()
	var now := Time.get_ticks_usec()
	if _seen.size() > 900:
		_seen.clear()
		_primed = false
	var y := GAP * a
	for it in list:
		if not _seen.has(it.id):
			_seen[it.id] = now if _primed else 0
		var h := row
		match it.kind:
			&"ai", &"option", &"think":
				var top := y
				var lines := PackedStringArray()
				var inner_w := right - col_x - 2.0 * BUBBLE_PAD * a
				var bw := 0.0
				if it.kind == &"think":
					bw = 18.0 * a
					lines.append("")
				else:
					if it.kind == &"option":
						lines.append_array(wrap_text(it.head, inner_w, true))
						it["head_rows"] = lines.size()
						bw = rows_w(lines, true)
						if String(it.text) != "":
							lines.append_array(wrap_text(it.text, inner_w))
					else:
						lines = wrap_text(it.text, inner_w)
					bw = snap_up(maxf(bw, rows_w(lines))) + 2.0 * BUBBLE_PAD * a
				if it.kind == &"ai" and String(it.who) != "":
					it["meta_y"] = y
					top += row
				var bh := lines.size() * row + 4.0 * a
				it["lines"] = lines
				it["box"] = Rect2(col_x, top, bw, bh)
				h = top + bh - y
			&"you":
				var room := right - pad - 12.0 * a - 2.0 * BUBBLE_PAD * a
				var ylines := wrap_text(it.text, room)
				var yw := snap_up(rows_w(ylines)) + 2.0 * BUBBLE_PAD * a
				h = ylines.size() * row + 4.0 * a
				it["lines"] = ylines
				it["box"] = Rect2(right - yw, y, yw, h)
			&"divider":
				var dlines := wrap_text(it.text, w - 2.0 * pad)
				it["lines"] = dlines
				h = dlines.size() * row
			&"patch":
				var cx := pad + 6.0 * a
				var cw := right - cx
				var entries: Array = []
				var cy := 3.0 * a + row + a
				for pair: Array in it.rows:
					var tag: Array = TAGS.get(pair[0], TAGS["Added"])
					var tw := snap_up(text_w(tag[1])) + 4.0 * a
					var tx := 4.0 * a + tw + 2.0 * a
					var plines := wrap_text(pair[1], cw - tx - 4.0 * a)
					entries.append({"tag": tag, "tag_w": tw, "x": tx, "y": cy, "lines": plines})
					cy += maxi(1, plines.size()) * row + a
				h = cy + 2.0 * a
				it["entries"] = entries
				it["box"] = Rect2(cx, y, cw, h)
			&"hotfix":
				var hx := pad + 2.0 * a
				var hw := right - hx - 2.0 * a
				var hlines := wrap_text(it.text, hw - 8.0 * a)
				var hh := 6.0 * a + row + hlines.size() * row
				it["lines"] = hlines
				it["box"] = Rect2(hx, y + 3.0 * a, hw, hh)
				h = hh + 3.0 * a
		it["rect"] = Rect2(0, y, w, h)
		y += h + GAP * a
	_primed = true
	_laid = list
	_total = y + a   # the last row's tail clears the pills
	return list


func total_height() -> float:
	return _total


## The furthest the wheel scrolls back.
func max_scroll() -> float:
	return maxf(0.0, _total - (messages.size.y if messages != null else 0.0))


## The content's y (lay()'s) in the messages area: the newest row at its bottom, pushed down
## by `scroll`.
func content_y() -> float:
	return roundf(messages.size.y - _total + clampf(scroll, 0.0, max_scroll()))


## True while row `id` hops (it was first laid out under POP_S ago; never under reduce flashing).
func popping(id: int) -> bool:
	if gentle or SaveGame.reduce_flashing():
		return false
	var at := int(_seen.get(id, 0))
	return at > 0 and Time.get_ticks_usec() - at < int(POP_S * 1000000.0)


# --- The pills and the input --------------------------------------------------------------------

## The pills on show: "[n] name" per open choice, else `play` at a gate, else none.
func pill_labels() -> Array[String]:
	var st := state()
	var out: Array[String] = []
	var choices: Array = st.choices
	for i in choices.size():
		out.append("[%d] %s" % [i + 1, TerminalPanel.pill_label(String(choices[i]))])
	if out.is_empty() and bool(st.gate):
		out.append("play")
	return out


## The pills' rects from (0, 0), flowing left to right and wrapping in `room` px.
func _flow(labels: Array[String], room: float) -> Array[Rect2]:
	var a := art()
	var out: Array[Rect2] = []
	var x := 0.0
	var y := 0.0
	for l in labels:
		var w := minf(room, snap_up(text_w(l)) + 6.0 * a)
		if x > 0.0 and x + w > room:
			x = 0.0
			y += (CabinetLayout.CHAT_PILL + CabinetLayout.CHAT_PILL_GAP) * a
		out.append(Rect2(x, y, w, CabinetLayout.CHAT_PILL * a))
		x += w + CabinetLayout.CHAT_PILL_GAP * a
	return out


func _pill_room() -> float:
	return size.x - 2.0 * (CabinetLayout.CHAT_RING + CabinetLayout.CHAT_PAD) * art()


## How many rows the pills take (0: none on show).
func pill_rows() -> int:
	var rects := _flow(pill_labels(), _pill_room())
	if rects.is_empty():
		return 0
	return roundi(rects[rects.size() - 1].position.y / ((CabinetLayout.CHAT_PILL + CabinetLayout.CHAT_PILL_GAP) * art())) + 1


## The pills' rects (local), in order.
func pill_rects() -> Array[Rect2]:
	var rects := _flow(pill_labels(), _pill_room())
	var at: Vector2 = (parts().pills as Rect2).position
	for i in rects.size():
		rects[i].position += at
	return rects


func pill_at(local: Vector2) -> int:
	var rects := pill_rects()
	for i in rects.size():
		if rects[i].has_point(local):
			return i
	return -1


## A pill pressed: an open choice is chosen (terminal.chosen, as a click on its raw row), the
## gate's pill gives play.
func press_pill(i: int) -> void:
	var t := terminal()
	if t == null or i < 0:
		return
	var st := state()
	if (st.choices as Array).is_empty():
		if bool(st.gate) and t.chat_input != null:
			t.chat_input.play_given.emit()
	elif i < (st.choices as Array).size():
		t.chosen.emit(i)


## The open option under `local` (its index, -1 none).
func option_at(local: Vector2) -> int:
	if messages == null or not Rect2(messages.position, messages.size).has_point(local):
		return -1
	var p := local - messages.position - Vector2(0, content_y())
	for it in _laid:
		if it.kind == &"option" and (it.box as Rect2).has_point(p):
			return int(it.index)
	return -1


func avatar_rect() -> Rect2:
	var a := art()
	var h: Rect2 = CabinetLayout.chat_parts(Rect2(Vector2.ZERO, size), a, 0).header
	return Rect2(h.position + Vector2(3, 2) * a, Vector2(26, 26) * a)


## The send key (local), at the input line's right end.
func send_rect() -> Rect2:
	var a := art()
	var box: Rect2 = parts().input
	return Rect2(Vector2(box.end.x - 13.0 * a, box.position.y + 2.0 * a), Vector2(11, 10) * a)


## The terminal's input row (docked here by the dresser) in the input line, left of the send key.
func layout_input() -> void:
	var t := terminal()
	if t == null or t.input_row() == null or t.input_row().get_parent() != self:
		return
	var a := art()
	var box: Rect2 = parts().input
	var row := t.input_row()
	row.position = (box.position + Vector2(3, 1) * a).round()
	row.size = Vector2(send_rect().position.x - 2.0 * a - row.position.x, box.size.y - 2.0 * a).round()


func _gui_input(event: InputEvent) -> void:
	var m := event as InputEventMouseButton
	if m == null or not m.pressed:
		return
	match m.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			scroll_by(WHEEL_ROWS)
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			scroll_by(-WHEEL_ROWS)
			accept_event()
		MOUSE_BUTTON_LEFT:
			var t := terminal()
			if t == null:
				return
			var i := pill_at(m.position)
			if i >= 0:
				press_pill(i)
				accept_event()
			elif send_rect().has_point(m.position):
				if t.chat_input != null:
					t.chat_input.submit(true)
				accept_event()
			else:
				var o := option_at(m.position)
				if o >= 0:
					t.chosen.emit(o)
					accept_event()


## Scrolls back (rows > 0) or forward by text rows.
func scroll_by(rows: float) -> void:
	scroll = clampf(scroll + rows * row_px(), 0.0, max_scroll())


# --- Drawing ------------------------------------------------------------------------------------

func _blink(hz: float) -> bool:
	if gentle or SaveGame.reduce_flashing():
		return true
	return int((Time.get_ticks_usec() - _start_usec) * hz / 500000.0) % 2 == 0


## The column: the frame, the header, the build log, the pills, the input line.
func _draw() -> void:
	if frame == null or not bool(frame.get(&"on")) or not frame.layout.get("cabinet", false):
		return
	var t := terminal()
	if t == null:
		return
	var a := art()
	var p := parts()
	CabinetArt.draw9(self, &"chat", Vector2.ZERO, roundi(size.x / a), roundi(size.y / a), a)
	# The header.
	var head: Rect2 = p.header
	CabinetArt.draw9_rect(self, &"chat_head", head, a)
	var av := avatar_rect()
	CabinetArt.draw9_rect(self, &"chat_avatar", av, a)
	var ver := String(frame.call(&"marquee_version"))
	var plate_w := ceili((text_w(ver) + 6.0 * a) / a)
	var plate := Rect2(Vector2(head.end.x - (2 + plate_w) * a, head.position.y + a), Vector2(plate_w, 12) * a)
	CabinetArt.draw9_rect(self, &"plate_gold", plate, a)
	cap(self, plate.position.x, plate.position.y + roundf((12.0 * a - text_size() * 7.0 / 11.0) * 0.5) - a, ver,
			CabinetArt.c(&"ink"), false, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	var x := av.end.x + 3.0 * a
	var who := t.header_name()
	var big := name_size()
	if text_w(who, true, big) > plate.position.x - 2.0 * a - x:
		big = text_size()   # a long name: one size down, never under the plate
	cap(self, x, head.position.y + 3.0 * a, who, CabinetArt.c(&"slip"), true, HORIZONTAL_ALIGNMENT_LEFT, -1.0, big)
	cap(self, x, head.position.y + 13.0 * a, clip(ROLE, head.end.x - 2.0 * a - x), CabinetArt.c(&"c_you_hi"))
	var live_y := head.position.y + 21.0 * a
	draw_rect(Rect2(Vector2(x, live_y + a), Vector2(3, 3) * a), CabinetArt.c(&"c_live") if _blink(0.7) else CabinetArt.c(&"mint_lo"))
	cap(self, x + 5.0 * a, live_y, clip(LIVE, head.end.x - 2.0 * a - x - 5.0 * a), CabinetArt.c(&"c_live"))
	# The build log: the last `$` rows.
	var lg: Rect2 = p.log
	CabinetArt.draw9_rect(self, &"chat_log", lg, a)
	var sigil_w := text_w("$ ")
	var lrows := log_rows()
	for i in lrows.size():
		var ly := lg.position.y + roundf(a) + i * minf(row_px(), roundf((lg.size.y - 2.0 * a) * 0.5))
		cap(self, lg.position.x + 4.0 * a, row_cap(ly), "$", CabinetArt.c(&"c_log_sigil"))
		cap(self, lg.position.x + 4.0 * a + sigil_w, row_cap(ly), clip(lrows[i], lg.size.x - 8.0 * a - sigil_w),
				CabinetArt.c(&"c_log_text"))
	# The reply pills: the first one lit.
	var labels := pill_labels()
	var rects := pill_rects()
	for i in rects.size():
		var r := rects[i]
		CabinetArt.draw9_rect(self, &"pill_lit" if i == 0 else &"pill", r, a)
		cap(self, r.position.x + 3.0 * a, r.position.y + roundf((r.size.y - text_size() * 7.0 / 11.0) * 0.5),
				clip(labels[i], r.size.x - 6.0 * a), CabinetArt.c(&"c_white") if i == 0 else CabinetArt.c(&"c_text"))
	# The input line and its send key; while an ask is open with no gate the input hides and
	# the line names the keys.
	var box: Rect2 = p.input
	CabinetArt.draw9_rect(self, &"input", box, a)
	var send := send_rect()
	CabinetArt.draw9_rect(self, &"send", send, a)
	CabinetArt.orn(self, &"send_arrow", send.position + Vector2(3, 2) * a + Vector2(0, roundf(0.5 * a)), a)
	var hint := Reply.well_hint(state())
	if hint != "":
		cap(self, box.position.x + 3.0 * a, box.position.y + roundf((box.size.y - text_size() * 7.0 / 11.0) * 0.5), hint,
				CabinetArt.c(&"c_dim"))


## The messages (clipped to their area): the rows on show, the scroll thumb.
func _draw_messages() -> void:
	if frame == null or not bool(frame.get(&"on")) or terminal() == null:
		return
	var ci := messages
	var a := art()
	var list := lay()
	if not is_equal_approx(_drawn_total, _total):
		scroll = 0.0   # a new row, or one growing: back to the newest
		_drawn_total = _total
	var oy := content_y()
	var area_h := ci.size.y
	for it in list:
		var slot: Rect2 = it.rect
		if oy + slot.end.y + 4.0 * a < 0.0 or oy + slot.position.y - 4.0 * a > area_h:
			continue
		var off := Vector2(0, oy + (2.0 * a if popping(it.id) else 0.0))
		match it.kind:
			&"ai":
				_draw_ai(ci, it, off)
			&"think":
				_draw_think(ci, it, off)
			&"option":
				_draw_option(ci, it, off)
			&"you":
				_draw_you(ci, it, off)
			&"divider":
				_draw_divider(ci, it, off)
			&"patch":
				_draw_patch(ci, it, off)
			&"hotfix":
				_draw_hotfix(ci, it, off)
	var most := max_scroll()
	if most > 0.0:
		var th := maxf(6.0 * a, area_h * area_h / _total)
		var ty := (area_h - th) * (1.0 - clampf(scroll, 0.0, most) / most)
		ci.draw_rect(Rect2(Vector2(ci.size.x - 2.0 * a, roundf(ty)), Vector2(a, roundf(th))), CabinetArt.c(&"c_ring_lo"))


func _moved(r: Rect2, off: Vector2) -> Rect2:
	return Rect2((r.position + off).round(), r.size)


## `lines` from `at` (the first row slot's top-left), `chars` of them typed (-1: all).
func _draw_lines(ci: CanvasItem, lines: PackedStringArray, at: Vector2, color: Color, chars := -1, bold_rows := 0,
		bold_color := Color.WHITE) -> void:
	var left := chars
	for i in lines.size():
		var row := lines[i]
		if chars >= 0:
			if left <= 0:
				break
			row = row.left(left)
			left -= lines[i].length() + 1
		var bold := i < bold_rows
		cap(ci, at.x, row_cap(at.y + i * row_px()), row, bold_color if bold else color, bold)


## The letter box left of a bubble, its foot on the bubble's.
func _draw_letter(ci: CanvasItem, box: Rect2) -> void:
	var a := art()
	var r := Rect2(Vector2(PAD * a, box.end.y - AVATAR * a), Vector2(AVATAR, AVATAR) * a)
	CabinetArt.draw9_rect(ci, &"chat_avatar", r, a)
	var t := terminal()
	var letter := t.header_name().left(1).to_upper() if t != null else "?"
	cap(ci, r.position.x + a, r.position.y + roundf((r.size.y - text_size() * 7.0 / 11.0) * 0.5), letter,
			CabinetArt.c(&"c_you_hi"), true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - a)


func _draw_ai(ci: CanvasItem, it: Dictionary, off: Vector2) -> void:
	var a := art()
	var box := _moved(it.box, off)
	if it.has("meta_y"):
		var mx := box.position.x
		var my := row_cap(float(it.meta_y) + off.y)
		cap(ci, mx, my, it.who, CabinetArt.c(&"c_who"), true)
		if String(it.mood) != "":
			cap(ci, mx + text_w(it.who, true), my, " · " + String(it.mood), CabinetArt.c(&"c_dim"))
	_draw_letter(ci, box)
	CabinetArt.draw9_rect(ci, &"bub_ai", box, a)
	CabinetArt.orn(ci, &"tail_ai", Vector2(box.position.x + 2.0 * a, box.end.y - a), a)
	_draw_lines(ci, it.lines, box.position + Vector2(BUBBLE_PAD, 2) * a,
			CabinetArt.c(&"c_dim") if it.dim else CabinetArt.c(&"c_text"), int(it.chars))


## The thinking dots: one lit in turn, 3 a second; all lit and still under reduce flashing.
func _draw_think(ci: CanvasItem, it: Dictionary, off: Vector2) -> void:
	var a := art()
	var box := _moved(it.box, off)
	_draw_letter(ci, box)
	CabinetArt.draw9_rect(ci, &"bub_ai", box, a)
	CabinetArt.orn(ci, &"tail_ai", Vector2(box.position.x + 2.0 * a, box.end.y - a), a)
	var still := gentle or SaveGame.reduce_flashing()
	var lit := int((Time.get_ticks_usec() - _start_usec) / 333333.0) % 3
	for i in 3:
		var on := still or i == lit
		ci.draw_rect(Rect2(box.position + Vector2(BUBBLE_PAD + i * 4, 4) * a, Vector2(2, 2) * a),
				CabinetArt.c(&"c_you_hi") if on else CabinetArt.c(&"c_ring_lo"))
	var note := "%s is thinking..." % String(it.who)
	var nx := box.end.x + 3.0 * a
	if nx + text_w(note) <= ci.size.x - PAD * a:
		cap(ci, nx, row_cap(box.position.y + 2.0 * a), note, CabinetArt.c(&"c_dim"))


## An open ask's option in full: its "[n] name" in gold, its description under it.
func _draw_option(ci: CanvasItem, it: Dictionary, off: Vector2) -> void:
	var a := art()
	var box := _moved(it.box, off)
	CabinetArt.draw9_rect(ci, &"bub_ai", box, a)
	_draw_lines(ci, it.lines, box.position + Vector2(BUBBLE_PAD, 2) * a, CabinetArt.c(&"c_text"), -1,
			int(it.get("head_rows", 1)), CabinetArt.c(&"gold"))


func _draw_you(ci: CanvasItem, it: Dictionary, off: Vector2) -> void:
	var a := art()
	var box := _moved(it.box, off)
	CabinetArt.draw9_rect(ci, &"bub_you", box, a)
	CabinetArt.orn(ci, &"tail_you", Vector2(box.end.x - 9.0 * a, box.end.y - a), a)
	_draw_lines(ci, it.lines, box.position + Vector2(BUBBLE_PAD, 2) * a, CabinetArt.c(&"c_white"))


## A divider: its text centred, dim, a rule each side when it is one row.
func _draw_divider(ci: CanvasItem, it: Dictionary, off: Vector2) -> void:
	var a := art()
	var slot := _moved(it.rect, off)
	var lines: PackedStringArray = it.lines
	var pad := PAD * a
	for i in lines.size():
		cap(ci, pad, row_cap(slot.position.y + i * row_px()), lines[i], CabinetArt.c(&"c_dim"), false,
				HORIZONTAL_ALIGNMENT_CENTER, slot.size.x - 2.0 * pad)
	if lines.size() != 1:
		return
	var tw := text_w(lines[0])
	var side := roundf((slot.size.x - 2.0 * pad - tw) * 0.5 - 2.0 * a)
	if side < 2.0 * a:
		return
	var ry := roundf(slot.position.y + (row_px() - a) * 0.5)
	ci.draw_rect(Rect2(Vector2(pad, ry), Vector2(side, a)), CabinetArt.c(&"c_rule"))
	ci.draw_rect(Rect2(Vector2(slot.size.x - pad - side, ry), Vector2(side, a)), CabinetArt.c(&"c_rule"))


## A PATCH card: the gold bookmark on its left edge, "PATCH vX" in gold, a tagged row per change.
func _draw_patch(ci: CanvasItem, it: Dictionary, off: Vector2) -> void:
	var a := art()
	var box := _moved(it.box, off)
	CabinetArt.draw9_rect(ci, &"patch_card", box, a)
	CabinetArt.orn(ci, &"pc_tab", box.position + Vector2(-5, 2) * a, a)
	var title := "PATCH " + String(it.version) if String(it.version) != "" else "PATCH"
	cap(ci, box.position.x + 4.0 * a, row_cap(box.position.y + 3.0 * a), title, CabinetArt.c(&"gold"), true)
	for e: Dictionary in it.entries:
		var tag: Array = e.tag
		var at := box.position + Vector2(4.0 * a, float(e.y))
		CabinetArt.draw9(ci, tag[0], at + Vector2(0, roundf((row_px() - ROW * a) * 0.5)), roundi(float(e.tag_w) / a), ROW, a)
		cap(ci, at.x, row_cap(at.y), tag[1], CabinetArt.c(tag[2]), false, HORIZONTAL_ALIGNMENT_CENTER, float(e.tag_w))
		_draw_lines(ci, e.lines, box.position + Vector2(float(e.x), float(e.y)), CabinetArt.c(&"c_text"))


## A HOTFIX slip: a taped paper note, "HOTFIX vX+n" in rust, the fix in ink.
func _draw_hotfix(ci: CanvasItem, it: Dictionary, off: Vector2) -> void:
	var a := art()
	var box := _moved(it.box, off)
	CabinetArt.draw9_rect(ci, &"hotfix", box, a)
	var tape := CabinetArt.orn_size(&"tape")
	CabinetArt.orn(ci, &"tape", Vector2(roundf(box.get_center().x - tape.x * a * 0.5), box.position.y - 2.0 * a), a)
	cap(ci, box.position.x + 4.0 * a, row_cap(box.position.y + 3.0 * a), "HOTFIX " + String(it.label),
			CabinetArt.c(&"rust"), true)
	_draw_lines(ci, it.lines, box.position + Vector2(4.0 * a, 3.0 * a + row_px()), CabinetArt.c(&"plum_d"))

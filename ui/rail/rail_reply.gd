extends Control
## M48.5a: the chat's reply box, under the rail on the right (Pixel_A): the question, the
## open choices as bevelled pills (the first one gold, a [n] key chip each) and the input well
## ("> press 1 2 3", "> move to play" at the ready moment, a 1 Hz caret, steady under reduce
## flashing). It reads the dressed terminal's rows: the choices it shows are the CHOICE rows
## right before the open `you>` prompt (hidden in the log while the rail shows), so whoever
## asked keeps reading its own keys. A click on a pill emits terminal.chosen(index), as a click
## on the raw choice row does.

const Chat := preload("res://ui/rail/rail_chat.gd")

var frame: Node   ## the RailFrame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if frame != null and frame.on:
		queue_redraw()


## The open question now: {question, who, choices: Array[String], prompt: bool}.
func state() -> Dictionary:
	var out := {"question": "", "who": "", "choices": [] as Array[String], "prompt": false}
	var t: TerminalPanel = frame.host.get(&"terminal") if frame != null and frame.host != null else null
	if t == null:
		return out
	out.who = t.speaker
	var rows := t.row_nodes()
	var you := -1
	if t.has_prompt():
		for i in range(rows.size() - 1, -1, -1):
			if int(rows[i].get_meta(&"kind", -1)) == TerminalPanel.Row.YOU:
				you = i
				break
	out.prompt = you >= 0
	var j := (you if you >= 0 else rows.size()) - 1
	var choices: Array[String] = []
	while you >= 0 and j >= 0 and int(rows[j].get_meta(&"kind", -1)) == TerminalPanel.Row.CHOICE:
		var c := (rows[j] as Label).text
		choices.push_front(c.substr(c.find("] ") + 2) if c.find("] ") >= 0 else c)
		j -= 1
	out.choices = choices
	# The question (review): the AI often says a line or two more after asking, before the
	# choices land, so with choices open the nearest line said (or a system line) that asks
	# ('?') since the last exchange wins; with none (or no choices), the last line said.
	var pick := -1
	var last := -1
	while j >= 0:
		var k := int(rows[j].get_meta(&"kind", -1))
		if not choices.is_empty() and (k == TerminalPanel.Row.YOU or k == TerminalPanel.Row.CHOICE):
			break   # an earlier exchange: its question is not this one
		if k == TerminalPanel.Row.SAY or k == TerminalPanel.Row.SYS:
			if last < 0:
				last = j
			if choices.is_empty():
				break
			if asks(Chat.label_text(rows[j])):
				pick = j
				break
		j -= 1
	if pick < 0:
		pick = last
	if pick >= 0:
		out.question = Chat.label_text(rows[pick])
		if int(rows[pick].get_meta(&"kind", -1)) == TerminalPanel.Row.SYS:
			out.who = ""
	return out


## True when a line asks something: it ends with '?' (closing quotes and dots aside).
static func asks(line: String) -> bool:
	var t := line.strip_edges()
	while t != "" and t[t.length() - 1] in ["\"", "'", ")", ".", "”", "’"]:
		t = t.substr(0, t.length() - 1)
	return t.ends_with("?")


## The pills' rects (local) for `n` choices: up to 32 tall, 6 apart, from y 44 to the well.
func pill_rects(n: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if frame == null:
		return out
	var sc: float = frame.s()
	var gap := 6.0 * sc
	var ph := minf(32.0 * sc, (116.0 * sc - gap * maxf(0, n - 1)) / maxf(1, n))
	for i in n:
		out.append(Rect2(Vector2(16 * sc, 44 * sc + i * (ph + gap)).round(), Vector2(size.x - 32 * sc, ph).round()))
	return out


func _draw() -> void:
	if frame == null or not frame.on or not frame.layout.get("rail", false):
		return
	var sc: float = frame.s()
	var p: float = frame.px()
	var st := state()
	var choices: Array = st.choices
	var fs := RailLayout.text_px(16, sc)
	var w := size.x - 32 * sc
	if String(st.question) != "":
		var who: String = st.who
		var x := 16 * sc
		if who != "":
			RailFrame.text(self, Vector2(x, 12 * sc), who, fs, RailArt.c(&"who"), true)
			x += RailFrame.text_w(who, fs, true) + 8 * sc
		var q: String = st.question
		RailFrame.text(self, Vector2(x, 12 * sc), q, RailFrame.fit(q, fs, w - x + 16 * sc, false, 10), RailArt.c(&"body"))
	var n := choices.size()
	var rects := pill_rects(n)
	for i in n:
		var r := rects[i]
		var ph := r.size.y
		var first := i == 0
		RailArt.block(self, r, RailArt.c(&"gold") if first else RailArt.c(&"pill"), p, roundf(4 * sc),
				RailArt.c(&"gold_lo") if first else RailArt.c(&"pill_lo"))
		var key := str(i + 1)
		var kr := Rect2(r.position + Vector2(8 * sc, roundf((ph - 22 * sc) * 0.5) - 1 * sc), Vector2(24, 22) * sc).abs()
		kr = Rect2(kr.position.round(), kr.size.round())
		RailArt.block(self, kr, RailArt.c(&"ink") if first else RailArt.c(&"key"), p, roundf(4 * sc),
				RailArt.c(&"base") if first else RailArt.c(&"key_lo"))
		RailFrame.text(self, kr.position + Vector2(0, 3 * sc), key, RailLayout.text_px(12, sc),
				RailArt.c(&"gold") if first else RailArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)
		var t: String = choices[i]
		var tx := kr.end.x + 12 * sc
		RailFrame.text(self, Vector2(tx, r.position.y + (ph - UiTheme.pixel_font().get_height(fs)) * 0.5 - 1 * sc), t,
				RailFrame.fit(t, fs, r.end.x - tx - 8 * sc, false, 9), RailArt.c(&"ink"))
	# The input well.
	var well := Rect2(Vector2(16 * sc, 166 * sc).round(), Vector2(w, 34 * sc).round())
	RailArt.block(self, well, RailArt.c(&"sunk"), p)
	var hint := "watching you play"
	if n > 0:
		var keys: Array[String] = []
		for i in n:
			keys.append(str(i + 1))
		hint = "press " + " ".join(keys)
	elif st.prompt:
		hint = "move to play"
	var ty := well.position.y + (well.size.y - UiTheme.pixel_font().get_height(fs)) * 0.5
	RailFrame.text(self, Vector2(well.position.x + 12 * sc, ty), ">", fs, RailArt.c(&"gold"), true)
	var hx := well.position.x + 12 * sc + RailFrame.text_w(">", fs, true) + 8 * sc
	RailFrame.text(self, Vector2(hx, ty), hint, fs, RailArt.c(&"dim") if st.prompt else RailArt.c(&"mute"))
	if st.prompt and caret_on():
		draw_rect(Rect2(Vector2(hx + RailFrame.text_w(hint, fs) + 6 * sc, well.position.y + 9 * sc).round(), (Vector2(8, 16) * sc).round()), RailArt.c(&"gold"))


## The caret's blink (1 Hz; steady under reduce flashing, read live).
func caret_on() -> bool:
	var t: TerminalPanel = frame.host.get(&"terminal")
	return t.caret_on(Time.get_ticks_usec()) if t != null else true


## The pill under `local` (-1 none).
func pill_at(local: Vector2) -> int:
	var rects := pill_rects((state().choices as Array).size())
	for i in rects.size():
		if rects[i].has_point(local):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var m := event as InputEventMouseButton
	if m == null or not m.pressed or m.button_index != MOUSE_BUTTON_LEFT:
		return
	var i := pill_at(m.position)
	if i < 0:
		return
	var t: TerminalPanel = frame.host.get(&"terminal")
	if t != null:
		t.chosen.emit(i)
		accept_event()

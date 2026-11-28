extends RefCounted
## M48.5a: the version rail's chat. It dresses the host's TerminalPanel (set_dresser) instead
## of keeping a second message model: every caller (the debrief, the host, main's edit and
## skin rows, the mascot's live_say) keeps its API, its Label handles and its timing, and
## rows() reads the same text. While dressed:
## - the panel's back is empty (the rail draws the paper cell, the header and the spine), its
##   font the pixel font, its colours ink on paper (RailArt.chat_colors);
## - a header row ("[14:02] blob@patchnotes (happy)") is drawn as a version chip and the
##   speaker's name, ticked on the spine (gold for the current version);
## - `$ patch apply vX` and its changelog rows are one "patch" slip wired to the spine; a live
##   rule edit's `$ <cmd> ... ok` row is a "hotfix" slip;
## - the choices and the open `you>` prompt move to the reply box (rail_reply.gd); an answered
##   prompt is a "you" message with a mint tick.
## Undressing (detach) puts every row back exactly as it was.

const PATCH := "$ patch apply "

var frame: Node            ## the RailFrame
var terminal: TerminalPanel
var _pending := {}         ## "$ <cmd>" -> hotfix label, until its row shows


func _init(p_frame: Node) -> void:
	frame = p_frame


func chat_colors() -> Dictionary:
	return RailArt.chat_colors()


func font() -> Font:
	return UiTheme.pixel_font()


## The panel's back while dressed: nothing drawn, the rows inset past the spine and the header,
## and above the body sitting on the rail (bottom right).
func back_style() -> StyleBox:
	var sc: float = frame.s()
	var box := StyleBoxEmpty.new()
	box.content_margin_left = roundf(44 * sc)
	box.content_margin_right = roundf(14 * sc)
	box.content_margin_top = roundf((RailLayout.HEADER_H + 10) * sc)
	# Review: clear of the body. M48.6a: the cabinet's log has no body on it (its own pad).
	box.content_margin_bottom = roundf(float(frame.layout.get("log_bottom_pad", RailLayout.LOG_BOTTOM_PAD)) * sc)
	return box


func attach(t: TerminalPanel) -> void:
	terminal = t
	t.dock_input(frame.reply)   # M48.5b: the play gate is typed in the reply box's well
	frame.reply.call(&"layout_input")
	step()


func detach(t: TerminalPanel) -> void:
	for r in t.row_nodes():
		var c := r as Control
		if c == null:
			continue
		c.visible = true
		c.self_modulate = Color.WHITE
		var m := c.get_node_or_null(^"Marker") as CanvasItem
		if m != null:
			m.self_modulate = Color.WHITE
	if terminal == t:
		terminal = null


## A live edit's `$ <cmd>` row (queued now, shown on a later frame) becomes a hotfix slip.
## M50.7: `body` (a live nerf's patch note) is what the slip says instead of the command.
func mark_hotfix(prefix: String, label: String, body := "") -> void:
	_pending[prefix] = [label, body]


static func kind_of(r: Node) -> int:
	return int(r.get_meta(&"kind", -1))


static func label_text(r: Node) -> String:
	if r is Label:
		return (r as Label).text
	var t := r.get_node_or_null(^"Text") as Label
	return t.text if t != null else ""


## An answered prompt ("you> 2", "you> play"); the open one and a closed empty one are not.
static func answered(text: String) -> bool:
	return text.begins_with("you> ") and text != "you> _" and text.strip_edges() != "you>"


## Dresses the rows shown since the last frame (RailFrame._process; attach).
func step() -> void:
	if terminal == null or not is_instance_valid(terminal):
		return
	var version: String = frame.snap.get("version", SaveGame.version().label())
	for r in terminal.row_nodes():
		var c := r as Control
		if c == null or c.is_queued_for_deletion():
			continue
		match kind_of(c):
			TerminalPanel.Row.HEAD:
				if not c.has_meta(&"ver"):
					c.set_meta(&"ver", version)
				c.self_modulate = Color(1, 1, 1, 0)
			TerminalPanel.Row.SAY:
				var m := c.get_node_or_null(^"Marker") as CanvasItem
				if m != null:
					m.self_modulate = Color(1, 1, 1, 0)
			TerminalPanel.Row.CHOICE:
				c.visible = false
			TerminalPanel.Row.YOU:
				var on := answered(label_text(c))
				c.visible = on
				c.self_modulate = Color(1, 1, 1, 0)
			TerminalPanel.Row.CMD:
				var t := label_text(c)
				if not c.has_meta(&"hotfix"):
					for prefix: String in _pending:
						if t.begins_with(prefix):
							var pend: Array = _pending[prefix]
							c.set_meta(&"hotfix", pend[0])
							if String(pend[1]) != "":
								c.set_meta(&"hotfix_body", pend[1])
							_pending.erase(prefix)
							break
				if t.begins_with(PATCH) or c.has_meta(&"hotfix"):
					c.self_modulate = Color(1, 1, 1, 0)


# --- Drawing (the chat layer: behind the terminal's rows, clipped to the log under its header) ---

func draw_layer(ci: Control) -> void:
	var l: Dictionary = frame.layout
	if not l.get("rail", false) or terminal == null:
		return
	var sc: float = frame.s()
	var p: float = frame.px()
	var origin := ci.get_global_rect().position
	var spine_x: float = float(l.spine_x) - origin.x
	ci.draw_rect(Rect2(Vector2(spine_x, 0), Vector2(roundf(4 * sc), ci.size.y)), RailArt.c(&"gold_lo"))
	var current: String = frame.snap.get("version", "")
	var rows := terminal.row_nodes()
	var i := 0
	while i < rows.size():
		var c := rows[i] as Control
		i += 1
		if c == null or not c.visible or c.is_queued_for_deletion():
			continue
		var r := Rect2(c.get_global_rect().position - origin, c.size)
		if r.end.y < 0.0 or r.position.y > ci.size.y:
			continue
		match kind_of(c):
			TerminalPanel.Row.HEAD:
				var ver: String = c.get_meta(&"ver", current)
				_tick(ci, spine_x, r, RailArt.c(&"gold") if ver == current else RailArt.c(&"gold_lo"))
				_head(ci, r, ver, ver == current, label_text(c))
			TerminalPanel.Row.YOU:
				_tick(ci, spine_x, r, RailArt.c(&"mint"))
				var fs := terminal.font_size()
				RailFrame.text(ci, r.position, "you", fs, RailArt.c(&"you"), true)
				RailFrame.text(ci, r.position + Vector2(RailFrame.text_w("you", fs, true) + 10 * sc, 0),
						_answer_text(rows, i - 1), fs, RailArt.c(&"body"))
			TerminalPanel.Row.CMD:
				var t := label_text(c)
				if c.has_meta(&"hotfix"):
					_hotfix(ci, spine_x, r, String(c.get_meta(&"hotfix")), t, String(c.get_meta(&"hotfix_body", "")))
				elif t.begins_with(PATCH):
					var last := r
					var j := i
					while j < rows.size() and kind_of(rows[j]) == TerminalPanel.Row.NOTE:
						var n := rows[j] as Control
						last = Rect2(n.get_global_rect().position - origin, n.size)
						j += 1
					_patch(ci, spine_x, r, last, t.substr(PATCH.length()).strip_edges())


func _tick(ci: Control, spine_x: float, r: Rect2, color: Color) -> void:
	var sc: float = frame.s()
	var p: float = frame.px()
	var y := roundf(r.position.y + r.size.y * 0.5 - 4 * sc)
	RailArt.block(ci, Rect2(Vector2(spine_x - 2 * sc, y), Vector2.ONE * roundf(8 * sc)), color, p)
	ci.draw_rect(Rect2(Vector2(spine_x + 6 * sc + p, y + 3 * sc), Vector2(roundf(14 * sc), p)), RailArt.c(&"ink"))


## A message's head: the version chip, the speaker in caps-red, its expression dim.
func _head(ci: Control, r: Rect2, ver: String, current: bool, text: String) -> void:
	var sc: float = frame.s()
	var p: float = frame.px()
	var who := text
	var expr := ""
	var at := who.find(" ")
	if at >= 0:
		who = who.substr(at + 1)
	var open := who.find(" (")
	if open >= 0:
		expr = who.substr(open + 2).trim_suffix(")")
		who = who.substr(0, open)
	who = who.trim_suffix("@patchnotes")
	var fs := RailLayout.text_px(12, sc)
	var cw := RailFrame.text_w(ver, fs) + 8 * sc
	var chip := Rect2(Vector2(r.position.x, roundf(r.position.y + r.size.y * 0.5 - 7 * sc)), Vector2(roundf(cw), roundf(14 * sc)))
	RailArt.block(ci, chip, RailArt.c(&"gold") if current else RailArt.c(&"cell"), p)
	RailFrame.text(ci, chip.position + Vector2(4 * sc, 0), ver, fs, RailArt.c(&"ink") if current else RailArt.c(&"text"))
	var big := terminal.font_size()
	var x := chip.end.x + 8 * sc
	RailFrame.text(ci, Vector2(x, r.position.y), who, big, RailArt.c(&"who"), true)
	if expr != "":
		RailFrame.text(ci, Vector2(x + RailFrame.text_w(who, big, true) + 8 * sc, r.position.y + 3 * sc), expr, fs, RailArt.c(&"note_dim"))


## "you> 2" after "[2] move on": the choice's text ("move on"); else the answer as typed.
func _answer_text(rows: Array[Node], at: int) -> String:
	var t := label_text(rows[at]).substr(5)
	var j := at - 1
	while j >= 0 and kind_of(rows[j]) == TerminalPanel.Row.CHOICE:
		var c := label_text(rows[j])
		if c.begins_with("[%s] " % t):
			return c.substr(c.find("] ") + 2)
		j -= 1
	return t


## A patch slip: `head` is the `$ patch apply vX` row (its strip), `last` the last note row.
func _patch(ci: Control, spine_x: float, head: Rect2, last: Rect2, version: String) -> void:
	var sc: float = frame.s()
	var card := Rect2(head.position - Vector2(8, 2) * sc, Vector2(head.size.x + 12 * sc, last.end.y - head.position.y + 8 * sc))
	_slip(ci, spine_x, card, head, "patch", version + "  hot-reload")


func _hotfix(ci: Control, spine_x: float, r: Rect2, label: String, text: String, note := "") -> void:
	var sc: float = frame.s()
	var card := Rect2(r.position - Vector2(8, 2) * sc, Vector2(r.size.x + 12 * sc, r.size.y + 4 * sc))
	var body := note if note != "" else text.trim_prefix("$ ").trim_suffix(" ... ok")
	_slip(ci, spine_x, card, r, "hotfix", label, body)


## A slip: a cream card, a 3 px ink outline and an offset shadow, a gold header strip with its
## kind and version, wired to the spine by a gold link.
func _slip(ci: Control, spine_x: float, card: Rect2, strip_row: Rect2, kind: String, version: String, body := "") -> void:
	var sc: float = frame.s()
	var p: float = frame.px()
	card = Rect2(card.position.round(), card.size.round())
	ci.draw_rect(Rect2(card.position + Vector2(4, 4) * sc, card.size).grow(roundf(3 * sc)), RailArt.c(&"paper_lo"))
	ci.draw_rect(card.grow(roundf(3 * sc)), RailArt.c(&"ink"))
	ci.draw_rect(card, RailArt.c(&"slip"))
	var strip := Rect2(card.position, Vector2(card.size.x, strip_row.end.y - card.position.y + 1 * sc))
	if body != "":
		strip.size.x = minf(card.size.x, RailFrame.text_w(kind + " " + version, RailLayout.text_px(12, sc), true) + 16 * sc)
	ci.draw_rect(strip, RailArt.c(&"gold"))
	ci.draw_rect(Rect2(Vector2(strip.position.x, strip.end.y - roundf(2 * sc)), Vector2(strip.size.x, roundf(2 * sc))), RailArt.c(&"gold_lo"))
	var mid := strip.position.y + strip.size.y * 0.5
	var link := Rect2(Vector2(spine_x + 4 * sc, roundf(mid - 2 * sc)), Vector2(card.position.x - spine_x - 4 * sc - 3 * sc, roundf(4 * sc)))
	RailArt.block(ci, link, RailArt.c(&"gold"), p)
	var fs := RailLayout.text_px(12, sc)
	var ty := mid - UiTheme.pixel_font(true).get_height(fs) * 0.5
	if body == "":
		RailFrame.text(ci, Vector2(strip.position.x + 8 * sc, ty), kind, fs, RailArt.c(&"ink"), true)
		RailFrame.text(ci, Vector2(strip.position.x, ty), version + "  ", fs, RailArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_RIGHT, strip.size.x)
		return
	RailFrame.text(ci, Vector2(strip.position.x + 8 * sc, ty), kind + " " + version, fs, RailArt.c(&"ink"), true)
	var bx := strip.end.x + 8 * sc
	var big := terminal.font_size()
	# M50.7 review: never under the strip's own size (at 8 px "1.5" read "1 5"): the slip already says
	# hotfix, so "Balance: " goes, then whole ", " parts from the end until the rest fits.
	var least := RailLayout.text_px(12, sc)
	var room := card.end.x - bx - 4 * sc
	body = slip_body(body, room, least)
	RailFrame.text(ci, Vector2(bx, card.position.y + 2 * sc), body, maxi(least, RailFrame.fit(body, big, room, false, least)),
			RailArt.c(&"body"))


## M50.7 review: a hotfix slip's note for `room` px at `least` px: without its "Balance: " lead, then
## dropping whole ", " parts from the end until it fits (the first part always stays).
static func slip_body(body: String, room: float, least: int) -> String:
	body = body.trim_prefix("Balance: ")
	var parts := body.split(", ")
	while parts.size() > 1 and RailFrame.text_w(", ".join(parts), least) > room:
		parts.resize(parts.size() - 1)
	return ", ".join(parts)


## The log header's live text: the speaker in gold caps, the subtitle, the live dot.
func draw_header(ci: CanvasItem) -> void:
	var l: Dictionary = frame.layout
	if not l.get("rail", false) or terminal == null:
		return
	var sc: float = frame.s()
	var p: float = frame.px()
	var lg: Rect2 = l.log
	var who := terminal.speaker.to_upper()
	var fs := RailLayout.text_px(16, sc)
	RailFrame.text(ci, lg.position + Vector2(44, 12) * sc, who, fs, RailArt.c(&"gold"), true)
	RailFrame.text(ci, lg.position + Vector2(44 * sc + RailFrame.text_w(who, fs, true) + 14 * sc, 15 * sc), "dev chat · building live",
			RailLayout.text_px(12, sc), RailArt.c(&"dim"))
	var live_x := lg.end.x - 16 * sc - RailFrame.text_w("live", RailLayout.text_px(12, sc))
	RailFrame.text(ci, Vector2(live_x, lg.position.y + 14 * sc), "live", RailLayout.text_px(12, sc), RailArt.c(&"text"))
	var dot := Rect2(Vector2(live_x - 16 * sc, lg.position.y + 16 * sc).round(), Vector2.ONE * roundf(8 * sc))
	RailArt.block(ci, dot, RailArt.c(&"mint") if frame.blink(1.0) else RailArt.c(&"mint_lo"), p)

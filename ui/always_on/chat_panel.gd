class_name ChatPanel
extends VBoxContainer
## M47.6b (PLAN v9.4 0.8, design 2.8, mockup 2 "really good"): the dev-chat the AI ships itself
## at the end of S2's beat, in place of the raw terminal. TerminalPanel keeps every rule (the
## queue, the typing, the prompt, the ask) and draws its rows through this when its style is
## CHAT; the old terminal's rows stay, collapsed into the "terminal (legacy)" tab.
##
## Top to bottom: the tabs (chat, the collapsed terminal), the header (the AI's body small, its
## name, "YOUR DEVELOPER (AI)", "online - shipping live", the version tag), the build.log strip
## (the `$` rows, last BUILD_ROWS, dim monospace), the messages (the AI's bubbles on the left,
## the player's on the right, a patch card per patch, "<name> is thinking..." dots, dividers),
## the quick replies (pills: `play` at a gate, the options at an ask) and the input (the
## ChatInput moved into a rounded box, "Talk to <name>...").
##
## Presentation only, real time only (the tree is paused around it); colours by token (Palette
## CHAT_* constants, or the Pixel recolour after S9's `ui` reveal), kept as meta so recolor()
## re-dresses what is already shown.

signal pill_pressed(index: int)

const BUILD_ROWS := 4
const AVATAR := Vector2(84, 68)
const AVATAR_SCALE := 0.62
const MINI := 26.0
const BUBBLE_W := 0.76           ## a bubble's widest, of the panel's width
const MAX_ROWS := 300

var colors := raw_colors()
var px := 15                     ## the bubbles' font size
var speaker_name := "AI"
var body_id: StringName = MascotBody.CARET
var gentle := false              ## still dots whatever the setting (tests)
var pills: Array[String] = []    ## the quick replies on show (labels), in order

var _tabs: PanelContainer
var _header: PanelContainer
var _avatar: Control
var _name: Label
var _role: Label
var _online: Label
var _tag: Label
var _log: PanelContainer
var _log_rows: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _pills: VBoxContainer
var _input_box: PanelContainer
var input_slot: HBoxContainer
var _send: Button
var _card: VBoxContainer         ## the patch card rows go to, or null
var _dots: Array[Label] = []     ## the live thinking bubbles' dots
var _t := 0.0
var _snap_frames := 0


## The chat's tokens (Palette's tier-0 CHAT_* constants).
static func raw_colors() -> Dictionary:
	return {&"bg": Palette.CHAT_BG, &"top": Palette.CHAT_TOP, &"bar": Palette.CHAT_BAR,
			&"edge": Palette.CHAT_EDGE, &"rule": Palette.CHAT_RULE, &"text": Palette.CHAT_TEXT,
			&"dim": Palette.CHAT_DIM, &"soft": Palette.CHAT_SOFT, &"ai": Palette.CHAT_AI,
			&"ai_edge": Palette.CHAT_AI_EDGE, &"me": Palette.CHAT_ME, &"me_text": Palette.CHAT_ME_TEXT,
			&"pill": Palette.CHAT_PILL, &"pill_edge": Palette.CHAT_PILL_EDGE, &"pill_on": Palette.CHAT_PILL_ON,
			&"input": Palette.CHAT_INPUT, &"online": Palette.CHAT_ONLINE, &"card": Palette.CHAT_CARD,
			&"card_head": Palette.CHAT_CARD_HEAD, &"add": Palette.CHAT_TAG_ADD, &"add_bg": Palette.CHAT_TAG_ADD_BG,
			&"change": Palette.CHAT_TAG_CHANGE, &"change_bg": Palette.CHAT_TAG_CHANGE_BG,
			&"fix": Palette.CHAT_TAG_FIX, &"fix_bg": Palette.CHAT_TAG_FIX_BG, &"log": Palette.CHAT_LOG,
			&"log_bg": Palette.CHAT_LOG_BG, &"legacy": Palette.CHAT_LEGACY, &"accent": Palette.CHAT_ACCENT}


## The same tokens in the Pixel look (S9's `ui` reveal): from the terminal's Pixel colours,
## so the chat and the terminal it replaced recolour alike. Font and layout unchanged (M48.5).
static func pixel_colors() -> Dictionary:
	var t := TerminalPanel.pixel_colors()
	var out := raw_colors()
	out[&"bg"] = t.bg
	out[&"top"] = t.bg.lightened(0.06)
	out[&"bar"] = t.bg.darkened(0.25)
	out[&"edge"] = t.rule.lightened(0.15)
	out[&"rule"] = t.rule
	out[&"text"] = t.text
	out[&"dim"] = t.dim
	out[&"soft"] = t.note
	out[&"ai"] = t.rule.darkened(0.35)
	out[&"ai_edge"] = t.rule
	out[&"me"] = t.cmd.darkened(0.45)
	out[&"me_text"] = t.text
	out[&"pill"] = t.bg.lightened(0.08)
	out[&"pill_edge"] = t.rule
	out[&"pill_on"] = t.cmd.darkened(0.4)
	out[&"input"] = t.bg.darkened(0.3)
	out[&"online"] = t.cmd
	out[&"card"] = t.bg.lightened(0.05)
	out[&"card_head"] = t.rule.darkened(0.2)
	out[&"log"] = t.cmd
	out[&"log_bg"] = t.bg.darkened(0.35)
	out[&"legacy"] = t.bg.darkened(0.2)
	out[&"accent"] = t.choice
	return out


func _ready() -> void:
	name = "Chat" if name == "" else name
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override(&"separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_tabs()
	_build_header()
	_log = PanelContainer.new()
	_log.name = "BuildLog"
	_box(_log, &"log_bg", &"rule", 0, [0, 0, 0, 0], [14, 6, 14, 6])
	_log_rows = VBoxContainer.new()
	_log_rows.add_theme_constant_override(&"separation", 0)
	_log.add_child(_log_rows)
	add_child(_log)
	var head := Label.new()
	head.name = "LogTitle"
	head.text = "build.log - tail -f"
	_ink(head, &"dim", 0.7)
	head.add_theme_font_override(&"font", UiTheme.mono_font())
	head.add_theme_font_size_override(&"font_size", 10)
	_log_rows.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.name = "Messages"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.get_v_scroll_bar().modulate.a = 0.35
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: StringName in [&"margin_left", &"margin_right"]:
		pad.add_theme_constant_override(side, 14)
	pad.add_theme_constant_override(&"margin_top", 10)
	pad.add_theme_constant_override(&"margin_bottom", 6)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 9)
	pad.add_child(_list)
	add_child(_scroll)
	var pills_pad := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right"]:
		pills_pad.add_theme_constant_override(side, 14)
	pills_pad.add_theme_constant_override(&"margin_bottom", 8)
	add_child(pills_pad)
	_pills = VBoxContainer.new()
	_pills.name = "Pills"
	_pills.add_theme_constant_override(&"separation", 6)
	pills_pad.add_child(_pills)
	var input_pad := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_bottom"]:
		input_pad.add_theme_constant_override(side, 14)
	add_child(input_pad)
	_input_box = PanelContainer.new()
	_input_box.name = "InputBox"
	_box(_input_box, &"input", &"pill_edge", 1, [22, 22, 22, 22], [16, 6, 6, 6])
	input_pad.add_child(_input_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_input_box.add_child(row)
	input_slot = HBoxContainer.new()
	input_slot.name = "InputSlot"
	input_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(input_slot)
	_send = Button.new()
	_send.name = "Send"
	_send.text = ">"
	_send.focus_mode = Control.FOCUS_NONE
	_send.custom_minimum_size = Vector2(34, 34)
	_button_box(_send, &"pill_on", &"pill_on", 17)
	_ink(_send, &"me_text")
	row.add_child(_send)
	set_font_px(px)


func _build_tabs() -> void:
	_tabs = PanelContainer.new()
	_tabs.name = "Tabs"
	_box(_tabs, &"bar", &"rule", 0, [0, 0, 0, 0], [10, 6, 10, 0])
	add_child(_tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	_tabs.add_child(row)
	var chat := PanelContainer.new()
	chat.name = "ChatTab"
	_box(chat, &"top", &"rule", 1, [8, 8, 0, 0], [12, 4, 12, 4])
	var chat_l := Label.new()
	chat_l.text = "● chat"
	_ink(chat_l, &"text")
	chat.add_child(chat_l)
	row.add_child(chat)
	var legacy := PanelContainer.new()
	legacy.name = "LegacyTab"
	_box(legacy, &"legacy", &"pill_edge", 1, [8, 8, 0, 0], [10, 4, 10, 4])
	var legacy_l := Label.new()
	legacy_l.text = "terminal (legacy)"
	legacy_l.add_theme_font_override(&"font", UiTheme.mono_font())
	_ink(legacy_l, &"dim")
	legacy.add_child(legacy_l)
	row.add_child(legacy)
	var note := Label.new()
	note.name = "Collapsed"
	note.text = "collapsed, not deleted"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fit(note)
	_ink(note, &"dim")
	row.add_child(note)


func _build_header() -> void:
	_header = PanelContainer.new()
	_header.name = "Header"
	_box(_header, &"top", &"rule", 0, [0, 0, 0, 0], [16, 10, 16, 10])
	add_child(_header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	_header.add_child(row)
	_avatar = Control.new()
	_avatar.name = "Avatar"
	_avatar.custom_minimum_size = AVATAR
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.clip_contents = true
	row.add_child(_avatar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_name = Label.new()
	_name.name = "Name"
	_name.add_theme_font_override(&"font", UiTheme.sans_font(true))
	_ink(_name, &"me_text")
	_fit(_name)
	col.add_child(_name)
	_role = Label.new()
	_role.name = "Role"
	_role.text = "YOUR DEVELOPER (AI)"
	_role.add_theme_font_override(&"font", UiTheme.sans_font(true))
	_ink(_role, &"soft")
	_fit(_role)
	col.add_child(_role)
	_online = Label.new()
	_online.name = "Online"
	_online.text = "● online - shipping live"
	_ink(_online, &"soft")
	_fit(_online)
	col.add_child(_online)
	var tag_holder := VBoxContainer.new()
	tag_holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(tag_holder)
	var tag_box := PanelContainer.new()
	_box(tag_box, &"card_head", &"accent", 1, [10, 10, 10, 10], [9, 2, 9, 2])
	tag_holder.add_child(tag_box)
	_tag = Label.new()
	_tag.name = "Version"
	_tag.add_theme_font_override(&"font", UiTheme.mono_font())
	_ink(_tag, &"text")
	tag_box.add_child(_tag)


## The font sizes from the bubbles' (GameHost: 16 x clamp(k, 1, 2), less one).
func set_font_px(p: int) -> void:
	px = maxi(10, p)
	var t := Theme.new()
	t.default_font = UiTheme.sans_font()
	t.default_font_size = px
	theme = t
	if _name != null:
		_name.add_theme_font_size_override(&"font_size", px + 9)
		_role.add_theme_font_size_override(&"font_size", maxi(9, px - 4))
		_online.add_theme_font_size_override(&"font_size", px - 2)
		_tag.add_theme_font_size_override(&"font_size", maxi(9, px - 4))
		for l in _log_rows.get_children():
			if l is Label and l.name != "LogTitle":
				(l as Label).add_theme_font_size_override(&"font_size", px - 3)


## The header: the AI's name, its body (the caret before a face) and the version.
func set_identity(p_name: String, p_body: StringName, version: String) -> void:
	var body_changed := p_body != body_id or _avatar.get_child_count() == 0
	speaker_name = p_name
	body_id = p_body
	_name.text = p_name
	_tag.text = version
	_tag.get_parent().visible = version != ""
	if body_changed:
		for c in _avatar.get_children():
			_avatar.remove_child(c)
			c.queue_free()
		var body := MascotBody.make(p_body if MascotBody.is_body(p_body) else MascotBody.CARET)
		body.gentle = SaveGame.reduce_flashing()
		var at := AVATAR * 0.5 + Vector2(0, 4)
		if Skins.is_on(&"mascot"):
			var v := PixelBodyView.wrap(body, AVATAR_SCALE)
			v.position = at
			_avatar.add_child(v)
		else:
			body.scale = Vector2.ONE * AVATAR_SCALE
			body.position = at
			_avatar.add_child(body)
	for l in _dots:
		if is_instance_valid(l):
			var cap := l.get_parent().get_parent().get_node_or_null(^"Caption") as Label
			if cap != null:
				cap.text = "%s is thinking..." % speaker_name


## The header's name (tests).
func name_text() -> String:
	return _name.text


func avatar_body() -> MascotBody:
	for c in _avatar.get_children():
		if c is MascotBody:
			return c
		if c is PixelBodyView:
			return (c as PixelBodyView).body
	return null


# --- Rows ------------------------------------------------------------------------------

## A line the AI says: [mini avatar, bubble]; the label comes back at visible_characters 0
## (TerminalPanel types it). chatter (priority < 2): a smaller, dim bubble on one row.
func add_ai(text: String, chatter := false) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(_mini())
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	_box(bubble, &"ai", &"ai_edge", 1, [4, 16, 16, 16], [12, 8, 12, 8])
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _bubble_w(text, px)
	_ink(l, &"dim" if chatter else &"text")
	if chatter:
		l.add_theme_font_size_override(&"font_size", px - 2)
	l.visible_characters = 0
	bubble.add_child(l)
	row.add_child(bubble)
	_add(row)
	return l


## A line the player said ("play", a typed word): a bubble on the right.
func add_you(text: String) -> Label:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	_box(bubble, &"me", &"me", 0, [16, 16, 4, 16], [12, 8, 12, 8])
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _bubble_w(text, px)
	_ink(l, &"me_text")
	bubble.add_child(l)
	row.add_child(bubble)
	_add(row)
	return l


## A divider ("--- session 4 · Level · v0.4.0 ---", "[game frozen]", "(type play)").
func add_divider(text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(0, 1)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.set_meta(&"chat_fill", &"rule")
	left.color = col(&"rule")
	row.add_child(left)
	var l := Label.new()
	l.name = "Text"
	l.text = text.trim_prefix("--- ").trim_suffix(" ---")
	l.add_theme_font_size_override(&"font_size", px - 4)
	_ink(l, &"dim")
	row.add_child(l)
	var right := left.duplicate() as ColorRect
	right.set_meta(&"chat_fill", &"rule")
	row.add_child(right)
	_add(row)
	return l


## A `$` row in the build.log strip (the last BUILD_ROWS stay); its label comes back (an
## open command gets its result appended).
func add_log(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override(&"font", UiTheme.mono_font())
	l.add_theme_font_size_override(&"font_size", px - 3)
	_ink(l, &"log")
	_log_rows.add_child(l)
	var rows := _log_rows.get_children().filter(func(n: Node) -> bool: return n.name != "LogTitle" and not n.is_queued_for_deletion())
	for i in rows.size() - BUILD_ROWS:
		(rows[i] as Control).visible = false
	# the strip shows only the last rows; older ones stay hidden (rows() still lists them)
	for i in range(maxi(0, rows.size() - BUILD_ROWS), rows.size()):
		(rows[i] as Control).visible = true
	if rows.size() > MAX_ROWS:
		var first := rows[0] as Node
		_log_rows.remove_child(first)
		first.queue_free()
	if text.begins_with("$ patch apply "):
		_card = null
		_start_card(text.trim_prefix("$ patch apply ").get_slice(" ", 0))
	return l


## The build.log strip's rows on show (tests).
func log_rows() -> Array[String]:
	var out: Array[String] = []
	for l in _log_rows.get_children():
		if l is Label and l.name != "LogTitle" and (l as Label).visible:
			out.append((l as Label).text)
	return out


func _start_card(version: String) -> void:
	var card := PanelContainer.new()
	card.name = "PatchCard"
	_box(card, &"card", &"pill_edge", 1, [12, 12, 12, 12], [0, 0, 0, 0])
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	card.add_child(col)
	var head := PanelContainer.new()
	_box(head, &"card_head", &"card_head", 0, [12, 12, 0, 0], [12, 7, 12, 7])
	col.add_child(head)
	var hrow := HBoxContainer.new()
	head.add_child(hrow)
	var title := Label.new()
	title.name = "Title"
	title.text = "Patch %s" % version
	title.add_theme_font_override(&"font", UiTheme.sans_font(true))
	_ink(title, &"me_text")
	hrow.add_child(title)
	var applied := Label.new()
	applied.text = "applied - hot reload"
	applied.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	applied.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	applied.add_theme_font_size_override(&"font_size", px - 4)
	_ink(applied, &"soft")
	hrow.add_child(applied)
	var body_pad := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right"]:
		body_pad.add_theme_constant_override(side, 12)
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		body_pad.add_theme_constant_override(side, 8)
	col.add_child(body_pad)
	_card = VBoxContainer.new()
	_card.name = "Items"
	_card.add_theme_constant_override(&"separation", 5)
	body_pad.add_child(_card)
	var holder := MarginContainer.new()
	holder.add_theme_constant_override(&"margin_left", int(MINI) + 8)
	holder.add_child(card)
	_add(holder)


## A changelog row in the patch card ("ADDED  Shooting"); a card opens if none is.
func add_note(section: String, item: String) -> Label:
	if _card == null or not is_instance_valid(_card):
		_start_card("")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var tag := PanelContainer.new()
	var tone: StringName = &"add"
	match section:
		"Changed":
			tone = &"change"
		"Fixed":
			tone = &"fix"
	_box(tag, StringName(String(tone) + "_bg"), StringName(String(tone) + "_bg"), 0, [4, 4, 4, 4], [6, 1, 6, 1])
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tl := Label.new()
	tl.text = section.to_upper()
	tl.add_theme_font_override(&"font", UiTheme.mono_font())
	tl.add_theme_font_size_override(&"font_size", px - 5)
	_ink(tl, tone)
	tag.add_child(tl)
	row.add_child(tag)
	var l := Label.new()
	l.name = "Text"
	l.text = item
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 1
	l.add_theme_font_size_override(&"font_size", px - 1)
	_ink(l, &"text")
	row.add_child(l)
	_card.add_child(row)
	_snap()
	return l


## M47.6b review: an ask's option in full ("[1] tank  Something slow..."): a wrapped card the
## AI posts when the ask opens, so a pill (its short "[1] tank") is never the only place the
## description shows. A click picks it, as its pill would. Its name and description come back.
func add_option(text: String, index: int) -> Label:
	var card := PanelContainer.new()
	card.name = "Option%d" % (index + 1)
	_box(card, &"ai", &"pill_edge", 1, [10, 10, 10, 10], [12, 6, 12, 6])
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		var m := e as InputEventMouseButton
		if m != null and m.pressed and m.button_index == MOUSE_BUTTON_LEFT:
			pill_pressed.emit(index))
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override(&"separation", 2)
	col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := text.get_slice("  ", 0)
	var desc := text.substr(head.length()).strip_edges()
	var n := Label.new()
	n.name = "Name"
	n.text = head
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 1
	n.add_theme_font_override(&"font", UiTheme.sans_font(true))
	n.add_theme_font_size_override(&"font_size", px - 1)
	_ink(n, &"accent")
	col_box.add_child(n)
	var l := Label.new()
	l.name = "Text"
	l.text = desc
	l.visible = desc != ""
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1
	l.add_theme_font_size_override(&"font_size", px - 2)
	_ink(l, &"text")
	col_box.add_child(l)
	card.add_child(col_box)
	_add(card)
	return l


## The options' cards on show (tests): each card's name and description, in order.
func option_texts() -> Array[String]:
	var out: Array[String] = []
	for c in _list.get_children():
		if c.is_queued_for_deletion() or not String(c.name).begins_with("Option"):
			continue
		var n := c.find_child("Name", true, false) as Label
		var t := c.find_child("Text", true, false) as Label
		out.append((n.text + "  " + t.text).strip_edges())
	return out


## "<name> is thinking..." with three dots in a bubble (still under reduce flashing); the
## caption comes back. end_think() takes the row away (a chat shows typing only while it types).
func add_think() -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.add_child(_mini())
	var bubble := PanelContainer.new()
	_box(bubble, &"ai", &"ai_edge", 1, [4, 16, 16, 16], [12, 6, 12, 6])
	var dots := Label.new()
	dots.name = "Dots"
	dots.text = "● ● ●"
	dots.add_theme_font_size_override(&"font_size", px - 5)
	_ink(dots, &"accent")
	bubble.add_child(dots)
	row.add_child(bubble)
	var cap := Label.new()
	cap.name = "Caption"
	cap.text = "%s is thinking..." % speaker_name
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_theme_font_size_override(&"font_size", px - 3)
	_ink(cap, &"dim")
	row.add_child(cap)
	_dots.append(dots)
	_add(row)
	return cap


func end_think(caption: Label) -> void:
	if caption == null or not is_instance_valid(caption):
		return
	var row := caption.get_parent() as Control
	if row != null:
		row.visible = false


## Quick replies above the input. labels empty: none.
func set_pills(labels: Array[String]) -> void:
	if labels == pills:
		return
	pills = labels.duplicate()
	for c in _pills.get_children():
		_pills.remove_child(c)
		c.queue_free()
	for i in labels.size():
		var b := Button.new()
		b.name = "Pill%d" % (i + 1)
		b.text = labels[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if i == 0:
			_button_box(b, &"pill_on", &"accent", 16)
			_ink(b, &"me_text")
		else:
			_button_box(b, &"pill", &"pill_edge", 16)
			_ink(b, &"text")
		var index := i
		b.pressed.connect(func() -> void: pill_pressed.emit(index))
		_pills.add_child(b)


## A pill's brief brighten (the movement keys point at it); under reduce flashing nothing moves.
func pulse_pill() -> void:
	if _pills.get_child_count() == 0 or gentle or SaveGame.reduce_flashing():
		return
	var b := _pills.get_child(0) as Control
	var tw := b.create_tween().set_ignore_time_scale(true)
	b.modulate.a = 0.55
	tw.tween_property(b, ^"modulate:a", 1.0, 0.45)


func pill_button(index: int) -> Button:
	if index < 0 or index >= _pills.get_child_count():
		return null
	return _pills.get_child(index) as Button


func send_button() -> Button:
	return _send


func row_count() -> int:
	return _list.get_child_count()


func scroll_to_end() -> void:
	_snap()


# --- Inside ----------------------------------------------------------------------------------

func col(tone: StringName) -> Color:
	return colors.get(tone, Palette.CHAT_TEXT)


## Every node already shown takes the new colours.
func recolor(p_colors: Dictionary) -> void:
	colors = p_colors
	_recolor(self)


func _recolor(n: Node) -> void:
	if n.has_meta(&"chat_ink"):
		_ink(n as Control, n.get_meta(&"chat_ink"), float(n.get_meta(&"chat_alpha", 1.0)))
	if n.has_meta(&"chat_box"):
		var a: Array = n.get_meta(&"chat_box")
		if n is Button:
			_button_box(n as Button, a[0], a[1], a[2])
		else:
			_box(n as PanelContainer, a[0], a[1], a[2], a[3], a[4])
	if n.has_meta(&"chat_fill"):
		(n as ColorRect).color = col(n.get_meta(&"chat_fill"))
	for c in n.get_children():
		_recolor(c)


func _ink(c: Control, tone: StringName, alpha := 1.0) -> void:
	c.set_meta(&"chat_ink", tone)
	c.set_meta(&"chat_alpha", alpha)
	var ink := Color(col(tone), alpha)
	c.add_theme_color_override(&"font_color", ink)
	if c is Button:
		for state: StringName in [&"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
			c.add_theme_color_override(state, ink)


## A panel's rounded box: corners [tl, tr, br, bl], margins [l, t, r, b].
func _box(p: PanelContainer, bg: StringName, edge: StringName, width: int, corners: Array, margins: Array) -> void:
	p.set_meta(&"chat_box", [bg, edge, width, corners, margins])
	var box := StyleBoxFlat.new()
	box.bg_color = col(bg)
	box.border_color = col(edge)
	box.set_border_width_all(width)
	box.corner_radius_top_left = corners[0]
	box.corner_radius_top_right = corners[1]
	box.corner_radius_bottom_right = corners[2]
	box.corner_radius_bottom_left = corners[3]
	box.content_margin_left = margins[0]
	box.content_margin_top = margins[1]
	box.content_margin_right = margins[2]
	box.content_margin_bottom = margins[3]
	box.anti_aliasing = true
	p.add_theme_stylebox_override(&"panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_PASS


func _button_box(b: Button, bg: StringName, edge: StringName, radius: int) -> void:
	b.set_meta(&"chat_box", [bg, edge, radius])
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed", &"disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = col(bg).lightened(0.08) if state in [&"hover", &"hover_pressed"] else col(bg)
		box.border_color = col(edge)
		box.set_border_width_all(1)
		box.set_corner_radius_all(radius)
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.anti_aliasing = true
		b.add_theme_stylebox_override(state, box)


## The small round avatar left of the AI's bubbles: the name's first letter.
func _mini() -> Control:
	var holder := PanelContainer.new()
	holder.name = "Mini"
	holder.custom_minimum_size = Vector2(MINI, MINI)
	holder.size_flags_vertical = Control.SIZE_SHRINK_END
	_box(holder, &"ai", &"pill_edge", 1, [13, 13, 13, 13], [0, 0, 0, 0])
	var l := Label.new()
	l.text = speaker_name.left(1).to_upper() if speaker_name != "" else "?"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", UiTheme.sans_font(true))
	l.add_theme_font_size_override(&"font_size", px - 4)
	_ink(l, &"accent")
	holder.add_child(l)
	return holder


## A one-line label that gives way (ellipsis) instead of widening the chat past its window
## (the 360 px column at 1080p).
func _fit(l: Label) -> void:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _bubble_w(text: String, font_px: int) -> float:
	var room := size.x if size.x > 40.0 else 420.0
	var widest := maxf(120.0, (room - 28.0) * BUBBLE_W)
	var f := UiTheme.sans_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x + 4.0
	return minf(widest, w)


func _add(row: Control) -> void:
	_list.add_child(row)
	while _list.get_child_count() > MAX_ROWS:
		var first := _list.get_child(0)
		_list.remove_child(first)
		first.queue_free()
	_snap()


func _snap() -> void:
	_snap_frames = 3


func _process(delta: float) -> void:
	_t += delta
	var still := gentle or SaveGame.reduce_flashing()
	var live: Array[Label] = []
	for d in _dots:
		if is_instance_valid(d) and d.get_parent() != null and (d.get_parent().get_parent() as Control).visible:
			live.append(d)
			if not still:
				var i := int(_t * 3.0) % 3
				d.text = ["● ○ ○", "○ ● ○", "○ ○ ●"][i]
	_dots = live
	if _snap_frames > 0:
		_snap_frames -= 1
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

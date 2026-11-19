class_name PatchHistory
extends CanvasLayer
## Build log and rollback (PLAN 7). Tab opens it over the paused game. It lists
## every build so far and the patches currently applied; each of those can be rolled
## back while charges remain. A rollback asks for a second click and says first
## what else it would remove.

var director: AiDirector
var prompt_panel: PromptPanel
var transition: Transition

var _root: Control
var _log: Label
var _charges: Label
var _list: VBoxContainer
var _armed: StringName = &""   ## patch whose rollback is waiting for confirmation
var locked := false            ## set when the run is over


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.03, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 70)
	_root.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 60)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(_heading("BUILD LOG"))
	_log = Label.new()
	_log.add_theme_font_size_override(&"font_size", 18)
	_log.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	left.add_child(_log)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 10)
	columns.add_child(right)
	right.add_child(_heading("APPLIED PATCHES"))
	_charges = Label.new()
	_charges.add_theme_font_size_override(&"font_size", 18)
	right.add_child(_charges)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 8)
	right.add_child(_list)
	var close := Label.new()
	close.text = "[Tab] close"
	close.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.5))
	right.add_child(close)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 24)
	return label


func is_open() -> bool:
	return _root.visible


## Not available during a prompt, a transition or the report.
func can_open() -> bool:
	if locked:
		return false
	if prompt_panel and prompt_panel.is_open():
		return false
	if transition and transition.busy:
		return false
	return not (RunState.is_paused_for(&"prompt") or RunState.is_paused_for(&"transition")
			or RunState.is_paused_for(&"report"))


func open() -> bool:
	if is_open() or not can_open():
		return false
	RunState.log_event(&"history_open")
	RunState.set_pause(&"history", true)
	_armed = &""
	_root.visible = true
	_refresh()
	return true


func close() -> void:
	if not is_open():
		return
	_root.visible = false
	RunState.set_pause(&"history", false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"patch_history"):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


## One line per build, oldest first: "v0.2  Implement gravity", "v0.4  Revert: ...".
static func build_log_lines() -> Array[String]:
	var lines: Array[String] = ["v0.1  Initial build"]
	for entry: Dictionary in RunState.run_log:
		if entry.event == &"big_swap":
			# A big patch is permanent: marked MAJOR and locked. Small patches it took
			# with it are listed as dropped, not as rollbacks.
			var big := MutationDB.get_mutation(StringName(entry.to))
			var big_title: String = big.title if big else String(entry.to)
			lines.append("v0.%d  MAJOR: %s [locked]" % [entry.build, big_title])
			for id: String in entry.get("dropped", []):
				var d := MutationDB.get_mutation(StringName(id))
				lines.append("        %s dropped by %s" % [d.title if d else id, big_title])
			continue
		if entry.event != &"apply" and entry.event != &"revert":
			continue
		var m := MutationDB.get_mutation(entry.id)
		var title: String = m.title if m else String(entry.id)
		if entry.event == &"revert":
			title = "Revert: " + title
		lines.append("v0.%d  %s" % [entry.build, title])
	return lines


## First call arms the rollback and shows what it removes; the second does it.
func press_revert(id: StringName) -> void:
	var m := MutationDB.get_mutation(id)
	if director == null or not director.can_revert(m):
		return
	if _armed != id:
		_armed = id
		_refresh()
		return
	close()
	director.revert(m)


## The big slot's row: a lock, the genre and the title. Not a button: it cannot be
## rolled back (PLAN v3 1.2).
static func big_entry(m: Mutation) -> Control:
	var row := HBoxContainer.new()
	row.name = "BigEntry"
	row.add_theme_constant_override(&"separation", 10)
	row.add_child(LockIcon.new(22.0))
	var label := Label.new()
	label.text = "MAJOR  %s: %s  (permanent)" % [m.genre_label, m.title]
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.45))
	row.add_child(label)
	return row


func _refresh() -> void:
	_log.text = "\n".join(build_log_lines())
	var left := director.reverts_left if director else 0
	_charges.text = "Rollbacks left: %d" % left
	for child in _list.get_children():
		child.queue_free()
	if RunState.big != null:
		_list.add_child(big_entry(RunState.big))
	if RunState.stack.is_empty():
		var none := Label.new()
		none.text = "(none yet)"
		_list.add_child(none)
	var first: Button = null
	for m in RunState.stack:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override(&"font_size", 18)
		b.text = "Roll back: %s" % m.title
		if _armed == m.id:
			var also: Array[String] = []
			for d in RunState.dependents_of(m):
				also.append(d.title)
			b.text = "Confirm rollback of %s" % m.title
			if not also.is_empty():
				b.text += "\n  also removes: %s" % ", ".join(also)
		b.disabled = left <= 0
		b.pressed.connect(press_revert.bind(m.id))
		_list.add_child(b)
		if first == null or _armed == m.id:
			first = b
	if first and not first.disabled:
		first.grab_focus.call_deferred()

class_name ReportScreen
extends CanvasLayer
## Playtest Report (PLAN 8), shown for both outcomes over the paused game.
## "New build" starts a fresh run; "Copy report" puts the text on the clipboard.

signal new_build_requested(run_seed: int)

var _root: Control
var _title: Label
var _body: Label
var _ai: Label
var _new_build: Button
var _copy: Button
var _text := ""


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.03, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 90)
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 40)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	margin.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 34)
	column.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = Label.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	_body.add_theme_font_override(&"font", mono)
	_body.add_theme_font_size_override(&"font_size", 17)
	_body.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	scroll.add_child(_body)

	_ai = Label.new()
	_ai.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai.add_theme_font_size_override(&"font_size", 20)
	column.add_child(_ai)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 20)
	column.add_child(buttons)
	_new_build = Button.new()
	_new_build.text = "New build"
	_new_build.custom_minimum_size = Vector2(200, 48)
	_new_build.pressed.connect(new_build)
	buttons.add_child(_new_build)
	_copy = Button.new()
	_copy.text = "Copy report"
	_copy.custom_minimum_size = Vector2(200, 48)
	_copy.pressed.connect(copy_report)
	buttons.add_child(_copy)


func is_open() -> bool:
	return _root.visible


## Shows the report for the run that just ended. record is the telemetry record.
func open(outcome: StringName, record: Dictionary) -> void:
	_text = report_text(outcome, record)
	var lines := _text.split("\n")
	_title.text = lines[0]
	_title.add_theme_color_override(&"font_color",
			Color(0.55, 1.0, 0.65) if outcome == &"win" else Color(1.0, 0.45, 0.4))
	_ai.text = lines[lines.size() - 1]
	_body.text = "\n".join(lines.slice(1, lines.size() - 1)).strip_edges()
	RunState.set_pause(&"report", true)
	_root.visible = true
	_new_build.grab_focus.call_deferred()


func text() -> String:
	return _text


## Plain-text report. First line is the title, last line the AI comment.
static func report_text(outcome: StringName, record: Dictionary) -> String:
	var duration: float = record.get("duration", RunState.game_time)
	var version: String = record.get("version", RunState.version_label())
	var reverts: int = record.get("reverts_used", 0)
	var lines: Array[String] = []
	lines.append("PLAYTEST REPORT  -  %s" % ("v1.0 shipped" if outcome == &"win" else "Build crashed at " + version))
	lines.append("")
	lines.append("Time        %s" % _clock(duration))
	lines.append("Kills       %d" % int(record.get("kills", RunState.kills)))
	lines.append("Version     %s" % version)
	lines.append("Seed        %d" % int(record.get("seed", RunState.run_seed)))
	lines.append("Rollbacks   %d of %d" % [reverts, Tuning.reverts_per_run])
	lines.append("")
	lines.append("BUILD LOG")
	for line in PatchHistory.build_log_lines():
		lines.append("  " + line)
	lines.append("")
	lines.append("KILLS AND DAMAGE BY SOURCE")
	var kills: Dictionary = record.get("kills_by_source", {})
	var damage: Dictionary = record.get("damage_by_source", {})
	var sources: Array = kills.keys()
	for key: Variant in damage.keys():
		if not sources.has(key):
			sources.append(key)
	sources.sort()
	if sources.is_empty():
		lines.append("  (nothing)")
	for key: Variant in sources:
		lines.append("  %-22s %4d kills  %7.1f damage" % [_source_title(String(key)),
				int(kills.get(key, 0)), float(damage.get(key, 0.0))])
	lines.append("")
	var patches := (record.get("final_stack", []) as Array).size()
	lines.append("AI: " + Dialogue.report_line(outcome, duration, patches, reverts))
	return "\n".join(lines)


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


static func _source_title(key: String) -> String:
	if key == "base":
		return "Base weapon"
	var m := MutationDB.get_mutation(StringName(key))
	return m.title if m else key


func new_build(run_seed := -1) -> void:
	if not is_open():
		return
	new_build_requested.emit(run_seed)


func copy_report() -> void:
	DisplayServer.clipboard_set(_text)
	_copy.text = "Copied"

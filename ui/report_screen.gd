class_name ReportScreen
extends CanvasLayer
## Playtest Report (PLAN 8), shown for both outcomes over the paused game.
## Its main button is "Dev session" when the save is live (PLAN v5 4.1: the game scene
## opens the dev session) and "New build" otherwise (a fresh run, as before); "Copy
## report" puts the text on the clipboard.
## Optionally the player marks each patch of the run Keep or Cut; the AI reads those
## notes in the next run of the session (see Taste).

signal new_build_requested(run_seed: int)

const NEW_BUILD := "New build"
const DEV_SESSION := "Dev session"

var _root: Control
var _title: Label
var _body: Label
var _ai: Label
var _new_build: Button
var _copy: Button
var _text := ""
var _rate_box: VBoxContainer
var _rate_grid: GridContainer
var _rate_buttons := {}     ## id -> [keep: Button, cut: Button]
var ratings := {}           ## id -> +1 (keep) / -1 (cut); empty if the player skipped it


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

	_rate_box = VBoxContainer.new()
	_rate_box.add_theme_constant_override(&"separation", 6)
	column.add_child(_rate_box)
	var rate_title := Label.new()
	rate_title.text = "Notes for the AI (optional): keep or cut each patch of this build"
	rate_title.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))
	_rate_box.add_child(rate_title)
	_rate_grid = GridContainer.new()
	_rate_grid.columns = 2
	_rate_grid.add_theme_constant_override(&"h_separation", 40)
	_rate_box.add_child(_rate_grid)

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
	_build_ratings(record)
	_new_build.text = DEV_SESSION if SaveGame.is_live() else NEW_BUILD
	RunState.set_pause(&"report", true)
	_root.visible = true
	_new_build.grab_focus.call_deferred()


func text() -> String:
	return _text


func main_button_text() -> String:
	return _new_build.text


## Hides the report (the dev session takes over the screen); the game stays paused.
func close() -> void:
	_root.visible = false


## Plain-text report. First line is the title, last line the AI comment.
static func report_text(outcome: StringName, record: Dictionary) -> String:
	var duration: float = record.get("duration", RunState.game_time)
	var game_version: String = record.get("game_version", SaveGame.version().label())
	var build := int(record.get("build_number", RunState.build_number))
	var reverts: int = record.get("reverts_used", 0)
	var lines: Array[String] = []
	# PLAN v5 1.6: the run is a playtest of the game's version; the build is flavour.
	var smoke: bool = record.get("smoke_test", false)
	var result := "BUILD SURVIVED" if outcome == &"win" else "CRASHED AT BUILD %d" % build
	if record.get("smoke_stopped", false):
		result = "STOPPED BY THE AI"
	lines.append("%s OF %s  -  %s" % ["SMOKE TEST" if smoke else "PLAYTEST", game_version, result])
	lines.append("")
	lines.append("Time        %s" % _clock(duration))
	lines.append("Kills       %d" % int(record.get("kills", RunState.kills)))
	lines.append("Version     %s · build %d" % [game_version, build])
	lines.append("Seed        %d" % int(record.get("seed", RunState.run_seed)))
	var charges: Dictionary = record.get("charges", {})
	var earned := int(charges.get("earned", Tuning.rollback_charges_start))
	if earned > 0 or reverts > 0:   # rollbacks are parked (PLAN v5 1.3)
		lines.append("Rollbacks   used %d of %d earned" % [reverts, earned])
	var genres := genres_text(record.get("genre_seconds", {}))
	if genres != "":
		lines.append("Genres      " + genres)
	lines.append("")
	lines.append("BUILD LOG")
	for line in PatchHistory.build_log_lines(true):   # the run is over: stage patches are named
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
	if smoke:
		lines.append("AI: " + smoke_line(record.get("missing_basics", [])))
	else:
		lines.append("AI: " + Dialogue.report_line(outcome, duration, patches, reverts))
	return "\n".join(lines)


## The AI's comment on a smoke test (PLAN v5 4.8), about the first basic it missed.
static func smoke_line(missing: Array) -> String:
	match String(missing[0]) if not missing.is_empty() else "":
		"movement":
			return "You tried to move. I saw that. It is on my list."
		"enemies":
			return "Nothing to shoot, nowhere to hide. I know. Next build."
		_:
			return "Smoke test passed. Mostly because nothing happened."


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


static func _source_title(key: String) -> String:
	if key == "base":
		return "Base weapon"
	var m := MutationDB.get_mutation(StringName(key))
	return m.title if m else key


## "Base 1:20, Motion time 4:10" from genre_seconds; "" when the run never left base.
static func genres_text(seconds: Dictionary) -> String:
	if seconds.size() <= 1 and seconds.has("base"):
		return ""
	var parts: Array[String] = []
	for key: String in seconds:
		var m := MutationDB.get_mutation(StringName(key))
		var label := "Base" if key == "base" else (m.genre_label if m else key)
		parts.append("%s %s" % [label, _clock(float(seconds[key]))])
	return ", ".join(parts)


## Patches applied during the run, small and big, in the order they first came in,
## each once.
static func rateable_ids(record: Dictionary) -> Array[StringName]:
	var timed: Array = []
	for e: Dictionary in record.get("events", []):
		if e.event == "apply":
			timed.append([float(e.get("time", 0.0)), timed.size(), StringName(e.id)])
	for s: Dictionary in record.get("big_swaps", []):
		timed.append([float(s.get("time", 0.0)), timed.size(), StringName(s.to)])
	# By time, then by position in the record (sort_custom is not stable).
	timed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array[StringName] = []
	for pair: Array in timed:
		var id: StringName = pair[2]
		if not out.has(id) and MutationDB.get_mutation(id) != null:
			out.append(id)
	return out


func _build_ratings(record: Dictionary) -> void:
	ratings.clear()
	_rate_buttons.clear()
	for child in _rate_grid.get_children():
		child.queue_free()
	var ids := rateable_ids(record)
	_rate_box.visible = not ids.is_empty()
	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var name_label := Label.new()
		name_label.text = MutationDB.get_mutation(id).title
		name_label.custom_minimum_size = Vector2(250, 0)
		row.add_child(name_label)
		var keep := Button.new()
		keep.text = "Keep"
		keep.toggle_mode = true
		keep.toggled.connect(func(on: bool) -> void: rate(id, 1 if on else 0))
		row.add_child(keep)
		var cut := Button.new()
		cut.text = "Cut"
		cut.toggle_mode = true
		cut.toggled.connect(func(on: bool) -> void: rate(id, -1 if on else 0))
		row.add_child(cut)
		_rate_buttons[id] = [keep, cut]
		_style_choice(keep, false, Color.WHITE)
		_style_choice(cut, false, Color.WHITE)
		_rate_grid.add_child(row)


## +1 keep, -1 cut, 0 clears. Keep and Cut exclude each other.
func rate(id: StringName, value: int) -> void:
	if value == 0:
		ratings.erase(id)
	else:
		ratings[id] = value
	if _rate_buttons.has(id):
		var pair: Array = _rate_buttons[id]
		var value_now: int = ratings.get(id, 0)
		_style_choice(pair[0] as Button, value_now == 1, Color(0.45, 1.0, 0.55))
		_style_choice(pair[1] as Button, value_now == -1, Color(1.0, 0.45, 0.4))


func _style_choice(b: Button, on: bool, color: Color) -> void:
	b.set_pressed_no_signal(on)
	b.modulate = color if on else Color(1, 1, 1, 0.55)


func ratings_text() -> String:
	if ratings.is_empty():
		return "NOTES FOR THE AI
  (none)"
	var lines: Array[String] = ["NOTES FOR THE AI"]
	for id: StringName in ratings:
		var m := MutationDB.get_mutation(id)
		lines.append("  %-26s %s" % [m.title if m else String(id), "keep" if ratings[id] > 0 else "cut"])
	return "
".join(lines)


func new_build(run_seed := -1) -> void:
	if not is_open():
		return
	new_build_requested.emit(run_seed)


func copy_report() -> void:
	DisplayServer.clipboard_set(_text + "

" + ratings_text())
	_copy.text = "Copied"

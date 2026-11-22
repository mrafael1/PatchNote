class_name DebugOverlay
extends CanvasLayer
## Debug tools (PLAN 9).
## F1 info overlay · F2 mutation console · F3 invincibility · F4 spawn wave ·
## F5 restart with the same seed · F6 open a prompt now · F7 toggle bot · F9 dev
## session now (PLAN v5 5) · Shift+F9 ship the next change without the screen.

var game: Node  ## the main scene: provides player, spawn_wave(), restart()

var _info: Label
var _console: PanelContainer
var _buttons := {}
var _frame := 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_info = Label.new()
	_info.position = Vector2(10, 8)
	_info.add_theme_font_size_override(&"font_size", 13)
	_info.add_theme_color_override(&"font_color", Color(0.75, 1.0, 0.8))
	_info.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_info.add_theme_constant_override(&"outline_size", 4)
	_info.visible = false   # F1 shows it; it would sit on top of the prompt and build log
	add_child(_info)

	_console = PanelContainer.new()
	_console.position = Vector2(300, 40)
	_console.visible = false
	var box := VBoxContainer.new()
	_console.add_child(box)
	var title := Label.new()
	title.text = "Mutation console (click to apply / revert; BIG: swap in; MED, BOSS: add / remove AI)"
	box.add_child(title)
	# Parked patches (PLAN v5 1.3) under their own heading; they apply as before (5).
	for parked: bool in [false, true]:
		if parked:
			var heading := Label.new()
			heading.text = "PARKED"
			box.add_child(heading)
		for m in MutationDB.all:
			if m.parked != parked:
				continue
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(toggle_mutation.bind(m.id))
			box.add_child(b)
			_buttons[m.id] = b
	add_child(_console)
	_refresh_console()
	EventBus.patch_applied.connect(func(_m: Resource) -> void: _refresh_console())
	EventBus.patch_reverted.connect(func(_m: Resource) -> void: _refresh_console())
	EventBus.big_swapped.connect(func(_o: Resource, _n: Resource, _d: Array) -> void: _refresh_console())
	EventBus.ai_patch_added.connect(func(_m: Resource, _o: StringName) -> void: _refresh_console())
	EventBus.ai_patch_removed.connect(func(_m: Resource, _r: StringName) -> void: _refresh_console())


## Apply the mutation if it is not in the stack, otherwise revert it. Ignores
## requires/conflicts, like a developer console should. A big patch is swapped into
## the big slot; clicking the one already there does nothing (only reset empties it).
## An AI-tier patch is added to the AI layer as a stage patch, or removed from it with
## reason console (no charge spent, not a rollback).
func toggle_mutation(id: StringName) -> void:
	var m := MutationDB.get_mutation(id)
	if m == null:
		return
	var transition: Transition = game.transition if game else null
	if m.is_ai_tier():
		if RunState.ai.has(m):
			if transition:
				transition.request_ai_remove(m, &"console")
			else:
				RunState.remove_ai(m, &"console")
		elif transition:
			transition.request_ai_add(m, &"stage", "", true)
		else:
			RunState.add_ai(m, &"stage", true)
		return
	if m.is_big:
		if transition:
			transition.request_swap_big(m)
		else:
			RunState.swap_big(m)
		return
	if RunState.has_patch(id):
		if transition:
			transition.request_revert(m)
		else:
			RunState.revert(m)
	elif transition:
		transition.request_apply(m, true)
	else:
		RunState.apply(m, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		_info.visible = not _info.visible
	elif event.is_action_pressed(&"debug_console"):
		_console.visible = not _console.visible
	elif event.is_action_pressed(&"debug_invincible"):
		RunState.invincible = not RunState.invincible
	elif event.is_action_pressed(&"debug_spawn"):
		if game:
			game.spawn_wave()
	elif event.is_action_pressed(&"debug_restart"):
		if game:
			game.restart(true)
	elif event.is_action_pressed(&"debug_prompt"):
		if game and game.director and not RunState.is_paused_except(&"turn"):
			game.director.open_prompt()
	elif event.is_action_pressed(&"debug_session"):
		if game and game.has_method(&"open_dev_session"):
			var key := event as InputEventKey
			if key and key.shift_pressed:
				game.ship_next_change()
			else:
				game.open_dev_session()
	elif event.is_action_pressed(&"debug_bot"):
		if game and is_instance_valid(game.player):
			game.player.set_bot(not game.player.is_bot())


func _process(_delta: float) -> void:
	_frame += 1
	if _info.visible and _frame % 6 == 0:
		_info.text = _build_text()


func _refresh_console() -> void:
	for id: StringName in _buttons:
		var m := MutationDB.get_mutation(id)
		var mark := "[x]" if RunState.has_patch(id) else "[ ]"
		var big_tag := ""
		if m:
			big_tag = " BIG" if m.is_big else " MED" if m.is_medium else " BOSS" if m.boss_only else ""
		var parked := " (PARKED)" if m and m.parked else ""   # PLAN v5 5
		(_buttons[id] as Button).text = "%s%s %s%s — %s" % [mark, big_tag, id, parked, m.title if m else ""]


func _build_text() -> String:
	var lines: Array[String] = []
	lines.append("%s   seed %d   FPS %d   physics %.2f ms" % [
		Hud.version_text(), RunState.run_seed, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	lines.append("save %s   %s   showing look %s" % [_save_mode(), Unlocks.summary(), Look.label()])
	lines.append("entities %d   enemies %d   t %.1fs%s%s" % [
		RunState.live_entities().size(), RunState.count(&"enemy"), RunState.game_time,
		"   INVINCIBLE" if RunState.invincible else "",
		"   BOT" if game and is_instance_valid(game.player) and game.player.is_bot() else ""])
	var ids: Array[String] = []
	for m in RunState.stack:
		ids.append(String(m.id))
	lines.append("big: " + (String(RunState.big.id) if RunState.big else "(none)"))
	lines.append("stack: " + (", ".join(ids) if not ids.is_empty() else "(empty)"))
	var ai_ids: Array[String] = []
	for m in RunState.ai:
		ai_ids.append("%s (%s)" % [m.id, RunState.ai_owner.get(m.id, &"")])
	lines.append("ai: " + (", ".join(ai_ids) if not ai_ids.is_empty() else "(empty)"))
	var rules := RunState.rules.to_dict()
	var base := RunState.base_rules.to_dict()
	for key: String in rules:
		var changed := "  *" if rules[key] != base[key] else ""
		lines.append("  %s = %s%s" % [key, rules[key], changed])
	lines.append("kills by source: %s" % [RunState.kills_by_source])
	lines.append("F1 info  F2 console  F3 invincible  F4 wave  F5 restart  F6 prompt  F7 bot  F9 dev session  Shift+F9 ship next")
	return "\n".join(lines)


## F1: how the save is running (PLAN v5 5).
static func _save_mode() -> String:
	if SaveGame.read_only:
		return "read-only (newer build)"
	if SaveGame.persist:
		return "live"
	return "inert" if SaveGame.unlock_all else "snapshot"

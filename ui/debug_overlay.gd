class_name DebugOverlay
extends CanvasLayer
## Debug tools (PLAN 9).
## F1 info overlay · F2 mutation console (and rework buttons, PLAN v6 5) · F3 invincibility · F4 spawn wave ·
## F5 restart with the same seed · F6 open a prompt now · F7 toggle bot · F9 dev
## session now (PLAN v5 5) · Shift+F9 ship the next change without the screen.

var game: Node  ## the main scene: provides player, spawn_wave(), restart()

var _info: Label
var _console: PanelContainer
var _rework_box: VBoxContainer
var _buttons := {}
var _edit_buttons := {}   ## rule edit id -> Button (PLAN v8 1.4; a campaign session only)
var _event_buttons := {}  ## scripted event id -> Button (PLAN v8 1.5)
var _weapon_buttons := {}  ## weapon id -> Button (M44)
var _frame := 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_info = Label.new()
	_info.position = Vector2(10, 8)
	_info.add_theme_font_size_override(&"font_size", 13)
	_info.add_theme_color_override(&"font_color", Palette.DEBUG_TEXT)
	_info.add_theme_color_override(&"font_outline_color", Palette.OUTLINE)
	_info.add_theme_constant_override(&"outline_size", 4)
	_info.visible = false   # F1 shows it; it would sit on top of the prompt and build log
	add_child(_info)

	_console = PanelContainer.new()
	_console.position = Vector2(300, 40)
	_console.visible = false
	var scroll := ScrollContainer.new()   # 16 patches, 9 edits and the rework rows: more than a screen
	scroll.custom_minimum_size = Vector2(640, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_console.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	# Weapons first (M44): give one to the player, or rank it up (capped at 3).
	var weapons_heading := Label.new()
	weapons_heading.text = "WEAPONS (give / rank up; the player's loadout)"
	box.add_child(weapons_heading)
	for w in WeaponDB.all():
		var wb := Button.new()
		wb.focus_mode = Control.FOCUS_NONE
		wb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		wb.pressed.connect(give_weapon.bind(w.id))
		box.add_child(wb)
		_weapon_buttons[w.id] = wb
	var clear_button := Button.new()
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	clear_button.text = "clear (pistol only)"
	clear_button.pressed.connect(clear_weapons)
	box.add_child(clear_button)
	# PATH (M45a): switch the live path now, no warning (debug only; the v6 loop too).
	var path_heading := Label.new()
	path_heading.text = "PATH (switch live, debug only)"
	box.add_child(path_heading)
	var path_row := HBoxContainer.new()
	box.add_child(path_row)
	for pair: Array in [[&"off", ""], [&"auto", ""], [&"arsenal", ""], [&"survival", ""]]:
		var pb := Button.new()
		pb.focus_mode = Control.FOCUS_NONE
		pb.text = String(pair[0]) if pair[1] == "" else "%s (%s)" % [pair[0], pair[1]]
		pb.disabled = pair[1] != ""
		pb.pressed.connect(switch_path.bind(pair[0]))
		path_row.add_child(pb)
	var level_button := Button.new()
	level_button.focus_mode = Control.FOCUS_NONE
	level_button.text = "+1 level/card"
	level_button.pressed.connect(add_level)
	path_row.add_child(level_button)
	# LOOK (M48a, PLAN 1.7): the art the world wears, live (F10 toggles Pixel too).
	var look_heading := Label.new()
	look_heading.text = "LOOK (live; F10 toggles pixel)"
	box.add_child(look_heading)
	var look_row := HBoxContainer.new()
	box.add_child(look_row)
	for look: StringName in Skins.LOOKS:
		var lb := Button.new()
		lb.focus_mode = Control.FOCUS_NONE
		lb.text = String(look)
		lb.pressed.connect(func() -> void: Skins.use_named(look, get_tree().root))
		look_row.add_child(lb)
	# Rule edits (PLAN v8 1.4): through the rule book, warning included.
	var edits_heading := Label.new()
	edits_heading.text = "RULE EDITS (campaign session: click to request with its warning / take back)"
	box.add_child(edits_heading)
	for e in RuleDB.all():
		var eb := Button.new()
		eb.focus_mode = Control.FOCUS_NONE
		eb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		eb.pressed.connect(toggle_edit.bind(e.id))
		box.add_child(eb)
		_edit_buttons[e.id] = eb
	# Scripted events (PLAN v8 1.5): play one now, ignoring once per save.
	var events_heading := Label.new()
	events_heading.text = "EVENTS (campaign session: click to play now, even if seen; marks nothing)"
	box.add_child(events_heading)
	for ev in EventDB.all():
		var vb := Button.new()
		vb.focus_mode = Control.FOCUS_NONE
		vb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.pressed.connect(play_event.bind(ev.id))
		box.add_child(vb)
		_event_buttons[ev.id] = vb
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
	# Rework (PLAN v6 5): one button per shelved option, rebuilt as the shelf changes.
	var heading := Label.new()
	heading.text = "REWORK (live save; the next run plays it)"
	box.add_child(heading)
	_rework_box = VBoxContainer.new()
	box.add_child(_rework_box)
	add_child(_console)
	_refresh_console()
	EventBus.patch_applied.connect(func(_m: Resource) -> void: _refresh_console())
	EventBus.patch_reverted.connect(func(_m: Resource) -> void: _refresh_console())
	EventBus.big_swapped.connect(func(_o: Resource, _n: Resource, _d: Array) -> void: _refresh_console())
	EventBus.ai_patch_added.connect(func(_m: Resource, _o: StringName) -> void: _refresh_console())
	EventBus.ai_patch_removed.connect(func(_m: Resource, _r: StringName) -> void: _refresh_console())
	EventBus.weapon_changed.connect(func(_id: StringName, _rank: int) -> void: _refresh_weapons())
	_refresh_weapons()


## The player's loadout, or null (no game, no player).
func loadout() -> Loadout:
	if game == null or not is_instance_valid(game.player):
		return null
	return Component.find(game.player, Loadout) as Loadout


## F2's weapon row: give it (held: one rank up, capped at 3).
func give_weapon(id: StringName) -> bool:
	var lo := loadout()
	var ok := lo != null and lo.give(id)
	_refresh_weapons()
	return ok


## F2's PATH row (M45a): the path runner (made if missing) swaps now, no warning.
func switch_path(id: StringName) -> bool:
	if game == null or not game.has_method(&"ensure_path_runner"):
		return false
	if id != &"off" and not PathDB.has(id):
		return false
	game.ensure_path_runner().swap_now(id)
	_refresh_weapons()
	return true


## F2's "+1 level/card": the live meter jumps to its next level or card (a pick follows).
func add_level() -> void:
	var runner: PathRunner = game.get(&"path_runner") if game else null
	if runner != null:
		runner.force_level()


func clear_weapons() -> void:
	var lo := loadout()
	if lo != null:
		lo.clear()
	_refresh_weapons()


func _refresh_weapons() -> void:
	var lo := loadout()
	for id: StringName in _weapon_buttons:
		var rank := lo.rank_of(id) if lo != null else 0
		(_weapon_buttons[id] as Button).text = "%s %s — %s" % [
				"[r%d]" % rank if rank > 0 else "[ ]", id, WeaponDB.get_weapon(id).title]


## F2's rule edit row: live, take it back; pending, cancel it; otherwise request it
## (with its warning). Only in a campaign session (the rule book).
func toggle_edit(id: StringName) -> void:
	var book: RuleBook = game.get(&"rule_book") if game else null
	if book == null:
		return
	if book.is_live(id) or book.is_pending(id):
		book.remove(id, &"console")
	else:
		book.request(id, &"console")
	_refresh_edits()


## F2's event row: plays it now through the event player (forced: once per save does
## not apply, and the event is not marked seen).
func play_event(id: StringName) -> bool:
	var player: EventPlayer = game.get(&"event_player") if game else null
	if player == null:
		return false
	var ok := player.play(id, &"console", true)
	_refresh_edits()
	return ok


func _refresh_edits() -> void:
	var player: EventPlayer = game.get(&"event_player") if game else null
	for id: StringName in _event_buttons:
		var mark := "[-]"
		if player != null:
			mark = "[>]" if player.is_playing() and player.state_text().begins_with(String(id)) \
					else "[seen]" if SaveGame.event_seen(id) else "[ ]"
		(_event_buttons[id] as Button).text = "%s %s — %s" % [mark, id, EventDB.get_event(id).title]
	var book: RuleBook = game.get(&"rule_book") if game else null
	for id: StringName in _edit_buttons:
		var e := RuleDB.get_edit(id)
		var mark := "[-]"
		if book != null:
			mark = "[x]" if book.is_live(id) else "[~]" if book.is_pending(id) else "[ ]"
		(_edit_buttons[id] as Button).text = "%s %s (%s) — %s" % [mark, id, e.target, e.title]


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
	if Skins.is_toggle(event):   # the Pixel look preview, live (PLAN 1.7; F2 is the console)
		Skins.toggle(get_tree().root)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"debug_overlay"):
		_info.visible = not _info.visible
	elif event.is_action_pressed(&"debug_console"):
		_console.visible = not _console.visible
		if _console.visible:
			_refresh_rework()
			_refresh_weapons()
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
	if _console.visible and _frame % 6 == 0:
		_refresh_edits()   # pending -> live -> gone happens on its own


func _refresh_rework() -> void:
	for child in _rework_box.get_children():
		child.queue_free()
	for row in DevSession.rework_rows():
		for to: Change in row.to:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = "rework %s %s   (now %s)" % [row.fork.id, to.id, (row.from as Change).id]
			b.pressed.connect(func() -> void:
				if game and game.debug_rework(row.fork.id, to.id):
					_refresh_rework())
			_rework_box.add_child(b)


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
	lines.append(forks_line())
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
	var book: RuleBook = game.get(&"rule_book") if game else null
	if book != null:
		var live: Array[String] = []
		for id in book.live_ids():
			var left := book.seconds_left(id)
			live.append("%s (%s)" % [id, "%.1f s left" % left if left >= 0.0 else "session"])
		lines.append("rule book: " + (", ".join(live) if not live.is_empty() else "(nothing live)"))
	var events: EventPlayer = game.get(&"event_player") if game else null
	if events != null and RunState.session != null:
		var edits: Array[String] = []
		for id in book.live_ids():
			var left := book.seconds_left(id)
			edits.append("%s(%s)" % [id, "%.1fs" % left if left >= 0.0 else "session"])
		var played := events.played_ids()
		lines.append("session=%s attempt=%d edits=%s events=%s" % [RunState.session.id,
				CampaignDB.attempt(RunState.session.id), ",".join(edits) if not edits.is_empty() else "-",
				",".join(played) if not played.is_empty() else "-"])
		lines.append("event: " + events.state_text())
	var rules := RunState.rules.to_dict()
	var base := RunState.base_rules.to_dict()
	for key: String in rules:
		var changed := "  *" if rules[key] != base[key] else ""
		lines.append("  %s = %s%s" % [key, rules[key], changed])
	var lo := loadout()
	if lo != null:
		var w := lo.current()
		lines.append("weapon=%s:%d loadout=%s" % [w.def.id if w else &"-", w.rank if w else 0, lo.summary()])
	var runner: PathRunner = game.get(&"path_runner") if game else null
	lines.append(runner.state_text() if runner != null else "path=- level=- picks=0 pickups=0")
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


## "forks look_1=look_1_clean fork_enemy=? | shelf look_1_punchy,look_1_arcade" (PLAN v6 2).
static func forks_line() -> String:
	var parts: Array[String] = []
	var shelf: Array[String] = []
	for f in ChangeDB.forks:
		var a := f.answer()
		parts.append("%s=%s" % [f.id, a.id if a else "?"])
		for c in f.shelf():
			shelf.append(String(c.id))
	return "forks %s | shelf %s" % [" ".join(parts), ",".join(shelf) if not shelf.is_empty() else "-"]

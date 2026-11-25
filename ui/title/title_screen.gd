class_name TitleScreen
extends Control
## M47.4 (PLAN 1.16): the title screen, the front door from S7 on. StartScreen stays the main
## scene and builds this (instead of its raw column) when CampaignDB.front_door_open(); every
## action calls StartScreen's own methods (press_continue, _ask_then, press_replay, ...), and
## StartScreen's fields point at the controls here (continue_button, new_button, save_label,
## flash_panel, replay_session, replay_path), so its hooks and tests keep their meaning.
##
## The "PATCH NOTES" logo in code, the arena grid scrolling behind, a version chip and the
## campaign line under the logo; the menu on the left (Continue / New game with a confirm /
## Replay once S8 is done / Options / Quit) on a MenuStack (Back pops, focus wraps); the
## mascot idling on the right with one line per launch. The look's UI panel dresses the menus
## when its `ui` group is on (F10 here, a live look), neutral otherwise.
##
## The unveil: a save at S7 or later that has not seen the front door (the owner's) plays a
## 6 s cut of S7's door beat first, then the mascot owns up; front_door_seen is set and
## written once (the title's only write; the real save goes live for it, as Start would).

const LOGO_AT := Vector2(80, 78)
const CHIP_AT := Vector2(82, 178)
const SAVE_AT := Vector2(80, 206)
const MENU_AT := Vector2(80, 262)
const ITEM := Vector2(320, 50)
const SEP := 8.0
const PAD := 14.0
const MASCOT_AT := Vector2(0.8, 0.58)   ## the body's centre, as a fraction of the view
const MASCOT_SCALE := 1.3
const CONFIRM_LINE := "Start over? Your progress goes; your settings stay."
const REPLAY_LINE := "Play a session again as another path. Your save is not touched."
## One per launch, picked by the number of sessions done (no RNG). Drafts: the owner edits.
const TITLE_LINES: Array[String] = ["happy: Welcome back. I kept the lights on.",
		"proud: Look! A real menu.",
		"thinking: I fixed three bugs while you were gone. I made two.",
		"idle: Ready when you are."]
const UNVEIL_LINE := "guilty: You missed it. I made this while you were away."

var screen: StartScreen
var stack: MenuStack
var root_menu: PanelContainer
var confirm_menu: PanelContainer
var replay_menu: PanelContainer
var options: OptionsScreen
var continue_button: Button
var new_button: Button
var replay_button: Button
var options_button: Button
var quit_button: Button
var confirm_yes: Button
var confirm_no: Button
var replay_go: Button
var replay_back: Button
var replay_seed: LineEdit
var mascot: Mascot
var logo: TitleLogo
var backdrop: TitleBackdrop
var unveil: DoorBeat
var unveiled := false          ## the unveil played on this title (tests)

var _said := ""
var _menus: Array[PanelContainer] = []
var _buttons: Array[Button] = []


## The menu's rect with `n` items (the door beat's ghost panel).
static func menu_rect(n: int) -> Rect2:
	return Rect2(MENU_AT, Vector2(ITEM.x + 2.0 * PAD, n * ITEM.y + (n - 1) * SEP + 2.0 * PAD))


## Item `i`'s rect in the menu (all items shown: Continue, New game, Options, Quit in the
## beat; the door beat flies its buttons there).
static func item_rect(i: int) -> Rect2:
	return Rect2(MENU_AT + Vector2(PAD, PAD + i * (ITEM.y + SEP)), ITEM)


static func save_line_at() -> Vector2:
	return SAVE_AT


static func pause_chip_at(view: Vector2) -> Vector2:
	return Vector2(MENU_AT.x, view.y - 52.0)


## The line the title's mascot says this launch (Line syntax).
static func launch_line() -> String:
	return TITLE_LINES[(SaveGame.campaign().done as Array).size() % TITLE_LINES.size()]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	backdrop = TitleBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	logo = TitleLogo.new()
	logo.name = "Logo"
	logo.position = LOGO_AT
	logo.size = TitleLogo.logo_size()
	add_child(logo)
	var chip := UiTheme.key_chip(SaveGame.version().label())
	chip.name = "Version"
	chip.position = CHIP_AT
	add_child(chip)
	var save_label := Label.new()
	save_label.name = "CampaignLine"
	save_label.position = SAVE_AT
	save_label.add_theme_font_size_override(&"font_size", 20)
	save_label.add_theme_color_override(&"font_color", Palette.UI_SOFT)
	add_child(save_label)
	screen.save_label = save_label
	var pause_chip := UiTheme.key_chip(InputSetup.expand_keys("{key:pause} pause"))
	pause_chip.name = "PauseChip"
	add_child(pause_chip)
	var build := Label.new()
	build.name = "Build"
	build.text = "build %s" % Main.BUILD
	build.add_theme_font_size_override(&"font_size", 13)
	build.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.3))
	build.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	build.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	build.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build.offset_right = -16
	build.offset_bottom = -12
	add_child(build)

	stack = MenuStack.new()
	stack.name = "MenuStack"
	add_child(stack)
	_build_root()
	_build_confirm()
	_build_replay()
	options = OptionsScreen.new()
	options.name = "Options"
	options.visible = false
	add_child(options)
	stack.changed.connect(_on_stack_changed)

	mascot = Mascot.new()
	mascot.name = "TitleMascot"
	add_child(mascot)
	mascot.layer = 5
	mascot.setup(true, SaveGame.mascot())
	_place_mascot()
	_dress()
	Skins.hub.skin_changed.connect(_on_skin_changed)
	_place_footer.call_deferred()

	stack.push(root_menu)
	if not bool(Settings.get_value("front_door_seen")):
		_begin_unveil()
	else:
		_say(launch_line())


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)


func _place_footer() -> void:
	var chip := get_node_or_null("PauseChip") as Control
	if chip != null:
		chip.position = pause_chip_at(get_viewport_rect().size)


func _menu(name_: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = name_
	panel.theme_type_variation = UiTheme.MENU_PANEL
	panel.position = MENU_AT
	panel.visible = false
	add_child(panel)
	_menus.append(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", int(SEP))
	panel.add_child(box)
	return box


func _item(box: Container, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = UiTheme.TITLE_BUTTON
	b.custom_minimum_size = ITEM
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	box.add_child(b)
	_buttons.append(b)
	return b


func _note(box: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(ITEM.x, 0)
	l.add_theme_font_size_override(&"font_size", 18)
	l.add_theme_color_override(&"font_color", Palette.UI_SOFT)
	box.add_child(l)
	return l


func _build_root() -> void:
	var box := _menu("Menu")
	root_menu = box.get_parent() as PanelContainer
	# The first-launch question (PLAN v8 1.9) sits on top of the menu when it is asked.
	var flash := VBoxContainer.new()
	flash.name = "FlashQuestion"
	flash.add_theme_constant_override(&"separation", 8)
	flash.visible = false
	_note(flash, StartScreen.FLASH_QUESTION)
	_item(flash, "Yes, reduce them", func() -> void: screen.answer_flashing(true))
	_item(flash, "No, keep them", func() -> void: screen.answer_flashing(false))
	box.add_child(flash)
	flash.visibility_changed.connect(_on_flash_visibility)
	screen.flash_panel = flash
	continue_button = _item(box, StartScreen.CONTINUE, func() -> void: screen.press_continue())
	new_button = _item(box, StartScreen.NEW_GAME, confirm_new)
	replay_button = _item(box, "Replay", open_replay)
	options_button = _item(box, "Options", open_options)
	quit_button = _item(box, "Quit", func() -> void: get_tree().quit())
	screen.continue_button = continue_button
	screen.new_button = new_button


func _build_confirm() -> void:
	var box := _menu("Confirm")
	confirm_menu = box.get_parent() as PanelContainer
	_note(box, CONFIRM_LINE)
	confirm_yes = _item(box, "Yes, start over", _confirm_yes)
	confirm_no = _item(box, "No", func() -> void: stack.pop())
	MenuStack.wrap_focus([confirm_yes, confirm_no] as Array[Control])


func _build_replay() -> void:
	var box := _menu("Replay")
	replay_menu = box.get_parent() as PanelContainer
	_note(box, REPLAY_LINE)
	var session := OptionButton.new()
	session.custom_minimum_size = Vector2(ITEM.x, 40)
	box.add_child(session)
	var path := OptionButton.new()
	path.custom_minimum_size = Vector2(ITEM.x, 40)
	for c in StartScreen._replay_changes():
		path.add_item(String(c.take.title) if c.take != null else String(c.id))
		path.set_item_metadata(path.item_count - 1, c.id)
	box.add_child(path)
	replay_seed = LineEdit.new()
	replay_seed.placeholder_text = "Seed (empty = random)"
	replay_seed.custom_minimum_size = Vector2(ITEM.x, 40)
	replay_seed.text_submitted.connect(func(_t: String) -> void: press_replay())
	box.add_child(replay_seed)
	replay_go = _item(box, "Replay", press_replay)
	replay_back = _item(box, "Back", func() -> void: stack.pop())
	screen.replay_session = session
	screen.replay_path = path
	MenuStack.wrap_focus([session, path, replay_seed, replay_go, replay_back] as Array[Control])


# --- State --------------------------------------------------------------------------

## StartScreen.refresh_campaign() calls this: Replay shows once S8 is done (not read-only),
## its session list follows the save, and the focus wraps over what is visible.
func refresh() -> void:
	var sessions := StartScreen.replay_sessions()
	replay_button.visible = not sessions.is_empty() and not SaveGame.read_only
	var list := screen.replay_session
	list.clear()
	for s in sessions:
		list.add_item(s.title)
		list.set_item_metadata(list.item_count - 1, s.id)
	_wrap()


func _wrap() -> void:
	var items: Array[Control] = []
	for b in menu_items():
		items.append(b)
	MenuStack.wrap_focus(items)
	var flash := screen.flash_panel
	if flash != null and flash.visible:
		var answers: Array[Control] = []
		for c in flash.get_children():
			if c is Button:
				answers.append(c)
		answers.append_array(items)
		MenuStack.wrap_focus(answers)


## The root menu's buttons on show, top to bottom.
func menu_items() -> Array[Button]:
	var out: Array[Button] = []
	for b in [continue_button, new_button, replay_button, options_button, quit_button]:
		if b.visible:
			out.append(b)
	return out


func _on_flash_visibility() -> void:
	_wrap()
	if screen.flash_panel.visible and is_inside_tree():
		var first := MenuStack.first_focusable(screen.flash_panel)
		if first != null:
			first.grab_focus.call_deferred()
	elif stack.top() == root_menu:
		_focus_root.call_deferred()


func _focus_root() -> void:
	if not is_inside_tree() or unveiling():
		return
	var items := menu_items()
	if not items.is_empty():
		items[0].grab_focus()


## The seed the next session plays (StartScreen._start_campaign): Replay's field while its
## menu is up, else "" (random: Continue and New game take no seed on the title).
func seed_text() -> String:
	return replay_seed.text if stack.top() == replay_menu else ""


# --- Actions ------------------------------------------------------------------------

func confirm_new() -> void:
	if new_button.disabled:
		return
	if not CampaignDB.started():   # nothing to lose: no question
		screen._ask_then(screen._new_campaign)
		return
	stack.push(confirm_menu, confirm_no)


func _confirm_yes() -> void:
	stack.pop()
	screen._ask_then(screen._new_campaign)


func open_replay() -> void:
	if not replay_button.visible:
		return
	stack.push(replay_menu)


func press_replay() -> bool:
	return screen.press_replay(StartScreen._selected(screen.replay_session), StartScreen._selected(screen.replay_path))


func open_options() -> void:
	screen._go_live()   # its Back writes the settings
	options.open(0)
	stack.push(options, null)
	options.show_tab(0)


func _on_stack_changed() -> void:
	mascot.visible = stack.top() != options
	if stack.top() == root_menu:
		_wrap()


# --- The look -----------------------------------------------------------------------

func _on_skin_changed(_skin: ArtSkin) -> void:
	_dress()


## The look's UI panel on the menus and their buttons when its `ui` group is on; else the
## UiTheme's neutral MenuPanel / TitleButton.
func _dress() -> void:
	for panel in _menus:
		panel.remove_theme_stylebox_override(&"panel")
		if Skins.is_on(&"ui_panel"):
			Skins.dress_panel(panel)
	for b in _buttons:
		Skins.redress_button(b)
	logo.size = TitleLogo.logo_size()


## True when the menus wear the look's UI panel (tests).
func dressed() -> bool:
	return Skins.is_on(&"ui_panel") and Skins.current.ui_panel() != null \
			and root_menu.get_theme_stylebox(&"panel") == Skins.current.ui_panel(false)


# --- The mascot ---------------------------------------------------------------------

func _place_mascot() -> void:
	var view := get_viewport_rect().size
	mascot.scale = Vector2.ONE * MASCOT_SCALE
	var body := Vector2(view.x - Mascot.MARGIN - Mascot.SIZE * 0.5, Mascot.TOP + Mascot.SIZE * 0.5)
	mascot.offset = Vector2(view.x * MASCOT_AT.x, view.y * MASCOT_AT.y) - body * MASCOT_SCALE


func _say(source: String) -> void:
	var line := SessionRunner.with_keys(Line.parse(source))
	_said = line.text
	mascot.say(line, SessionRunner.PRIORITY, true)


## The line the mascot said on this title (tests, captures).
func mascot_text() -> String:
	return _said


# --- The unveil (PLAN 3.2) ----------------------------------------------------------

func unveiling() -> bool:
	return unveil != null and not unveil.is_done()


func _begin_unveil() -> void:
	screen._go_live()
	Settings.set_value("front_door_seen", true)
	Settings.commit()
	var s := CampaignDB.get_session(CampaignDB.FRONT_DOOR_SESSION)
	unveil = DoorBeat.new()
	unveil.name = "Unveil"
	unveil.setup(s.door_beat_lines() if s != null else ([] as Array[Line]), true, SaveGame.reduce_flashing())
	unveil.finished.connect(_end_unveil)
	add_child(unveil)
	move_child(unveil, stack.get_index())   # under the menus' input, over the logo
	for panel in _menus:
		panel.modulate.a = 0.0


func _process(delta: float) -> void:
	if unveiling():
		unveil.step(delta)


func skip_unveil() -> void:
	if unveiling():
		unveil.finish()


func _end_unveil() -> void:
	if unveil == null:
		return
	unveil.visible = false
	backdrop.scroll = unveil.backdrop_scroll()   # the grid carries on from the beat's pose
	backdrop.queue_redraw()
	unveil.queue_free()
	unveil = null
	unveiled = true
	for panel in _menus:
		panel.modulate.a = 1.0
	_say(UNVEIL_LINE)
	_focus_root.call_deferred()


func _input(event: InputEvent) -> void:
	if not unveiling():
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed)
	if not pressed or Skins.is_toggle(event):
		return
	get_viewport().set_input_as_handled()
	if unveil.elapsed - unveil.start_at() >= DoorBeat.SKIP_AFTER:
		skip_unveil()

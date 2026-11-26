class_name ChatInput
extends LineEdit
## M47.6a (PLAN v9.4 2.5): the chat's `you>` input, under the terminal's rows. It is enabled
## and focused only at a play gate (GameHost); everywhere else it is disabled and shows
## "the AI is watching...".
##
## At a gate:
## - `play` + Enter is play at any time; Enter on the empty input (the dim ghost "play") and a
##   bare `p` are play only once armed (the AI's before_play lines typed, plus ARM_S) and on a
##   fresh press (no echo, Enter not held when it armed), so Enter mashed through a beat
##   never starts a session unread.
## - While the text is empty a key bound to move_* / dash / shoot (InputMap, so ZQSD on AZERTY
##   and WASD on QWERTY) never types: it is swallowed (the square strains, the ghost pulses).
## - Anything else submitted is `typed` (the host answers with a canned reply; never logged).
## Real time only; it reads no game state.

signal play_given
signal typed(text: String)
signal move_pressed
## Esc (the pause action) while focused: the focused input sees keys before the game does, so
## it hands the key on (GameHost opens the pause menu).
signal pause_pressed

const GHOST := "play"
const IDLE_TEXT := "the AI is watching..."
const ARM_S := 0.4
const PULSE_GAP_MS := 1000
const PULSE_S := 0.45
const PLAY_WORDS: Array[String] = ["play"]
const SHORT_WORDS: Array[String] = ["", "p"]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down",
		&"dash", &"shoot"]

var gate := false            ## a play gate is up
var arm_at_msec := -1        ## when the empty Enter / `p` count (-1: not armed yet)
var dim := Palette.TERM_DIM
var bright := Palette.TERM_YOU
var gentle := false          ## reduce flashing whatever the setting (tests)
var pulses := 0              ## ghost pulses shown (tests)
## M47.6a review: the character of the last movement key swallowed at the empty prompt, and
## the one the last `typed` text came after. "again" on QWERTY loses its `a` (move_left), so
## GameHost also tries the reply for `typed_lead + text`.
var lead := ""
var typed_lead := ""
var _enter_held := false
var _last_pulse_msec := -100000
var _pulse_left := 0.0
var _underline := false      ## reduce flashing: the pulse is a steady underline


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "ChatInput" if name == "" else name
	flat = true
	context_menu_enabled = false
	keep_editing_on_text_submit = true
	caret_blink = true
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_closed()


## The gate is up: enabled, the ghost `play`, focused. Not armed until arm().
func open_gate() -> void:
	gate = true
	editable = true
	text = ""
	placeholder_text = GHOST
	arm_at_msec = -1
	lead = ""
	_underline = false
	_tint_ghost(0.0)
	take_focus()


## The AI's lines are typed: the empty Enter and `p` count from ARM_S on.
func arm() -> void:
	arm_at_msec = Time.get_ticks_msec() + int(ARM_S * 1000.0)
	_enter_held = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)


func armed() -> bool:
	return gate and arm_at_msec >= 0 and Time.get_ticks_msec() >= arm_at_msec


func close_gate() -> void:
	gate = false
	_set_closed()


func take_focus() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	grab_focus()
	edit()


func drop_focus() -> void:
	if has_focus():
		unedit()
		release_focus()


func _set_closed() -> void:
	text = ""
	editable = false
	placeholder_text = IDLE_TEXT
	arm_at_msec = -1
	_underline = false
	_tint_ghost(0.0)
	drop_focus()


## A key bound to a movement, the dash or the shot (by physical position).
static func is_move_key(e: InputEvent) -> bool:
	if not e is InputEventKey:
		return false
	for a in MOVE_ACTIONS:
		if InputMap.has_action(a) and InputMap.event_is_action(e, a, true):
			return true
	return false


static func is_enter(k: InputEventKey) -> bool:
	return k.keycode in [KEY_ENTER, KEY_KP_ENTER] or k.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]


func _gui_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not gate:
		return
	if k.is_action(&"pause"):
		accept_event()
		if k.pressed and not k.echo:
			pause_pressed.emit()
		return
	if not k.pressed:
		if is_enter(k):
			_enter_held = false
		if text == "" and is_move_key(k):
			accept_event()
		return
	if is_enter(k):
		accept_event()
		if not k.echo:
			submit(true)
		return
	if text == "" and is_move_key(k):
		accept_event()
		if not k.echo:
			lead = char(k.unicode) if k.unicode > 0 else ""
			move_pressed.emit()
			pulse()


## The input's text as said (Enter, or a test). fresh: a new press, not a held key.
func submit(fresh := true) -> void:
	if not gate:
		return
	var t := text.strip_edges().to_lower()
	if t in PLAY_WORDS:
		text = ""
		play_given.emit()
		return
	if t in SHORT_WORDS:
		if armed() and fresh and not _enter_held:
			text = ""
			play_given.emit()
		return
	var raw := text.strip_edges()
	text = ""
	typed_lead = lead
	lead = ""
	typed.emit(raw)


## The keys point at play: the ghost brightens once (at most once per PULSE_GAP_MS); under
## reduce flashing a steady underline instead.
func pulse() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_pulse_msec < PULSE_GAP_MS:
		return
	_last_pulse_msec = now
	pulses += 1
	if gentle or SaveGame.reduce_flashing():
		_underline = true
		queue_redraw()
		return
	_pulse_left = PULSE_S


func _tint_ghost(t: float) -> void:
	add_theme_color_override(&"font_placeholder_color", dim.lerp(bright, clampf(t, 0.0, 1.0)))


func _process(delta: float) -> void:
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - delta)
		_tint_ghost(sin(_pulse_left / PULSE_S * PI))


func _draw() -> void:
	if not (gate and _underline and text == ""):
		return
	var f := get_theme_font(&"font")
	var fs := get_theme_font_size(&"font_size")
	var w := f.get_string_size(GHOST, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else 32.0
	var y := size.y - 3.0
	var x := get_theme_stylebox(&"normal").get_margin(SIDE_LEFT) if has_theme_stylebox(&"normal") else 0.0
	draw_line(Vector2(x, y), Vector2(x + w, y), bright, 1.0)

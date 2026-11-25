class_name MenuStack
extends Control
## M47.4 (PLAN 1.16): a stack of menus (the title's root menu, its confirm, Replay and
## Options). push() shows a menu over the one below (which hides) and focuses it; Back
## (Esc / ui_cancel / pause, pad B) pops it and the focus returns to the item that opened it.
## At the root Back does nothing. A pushed menu with a `closed` signal (OptionsScreen)
## handles its own Back: the stack pops when it emits `closed`.
##
## PauseMenu keeps its own back and focus (M47.3; its gates stay as they are).

signal changed

var _menus: Array[Control] = []
var _openers: Array = []   ## per menu: the control focused when it opened (or null)
var _closers := {}         ## menu -> its `closed` callable (menus with their own Back)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


## Shows `menu` on top (hiding the one below) and focuses `focus`, else its first focusable
## item.
func push(menu: Control, focus: Control = null) -> void:
	if menu == null or menu in _menus:
		return
	var opener: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if not _menus.is_empty():
		_menus.back().visible = false
	_menus.append(menu)
	_openers.append(opener)
	menu.visible = true
	if menu.has_signal(&"closed"):
		var closer := _on_closed.bind(menu)
		_closers[menu] = closer
		menu.connect(&"closed", closer)
	_focus(focus if focus != null else first_focusable(menu))
	changed.emit()


## Hides the top menu and shows the one below, focusing the item that opened it. The root
## stays (false).
func pop() -> bool:
	if _menus.size() <= 1:
		return false
	var menu: Control = _menus.pop_back()
	var opener: Variant = _openers.pop_back()
	if _closers.has(menu):
		if menu.is_connected(&"closed", _closers[menu]):
			menu.disconnect(&"closed", _closers[menu])
		_closers.erase(menu)
	menu.visible = false
	var below: Control = _menus.back()
	below.visible = true
	var back_to: Control = opener as Control if is_instance_valid(opener) else null
	_focus(back_to if back_to != null and back_to.is_visible_in_tree() else first_focusable(below))
	changed.emit()
	return true


func top() -> Control:
	return _menus.back() if not _menus.is_empty() else null


func depth() -> int:
	return _menus.size()


func _on_closed(menu: Control) -> void:
	if top() == menu:
		pop()


func _focus(c: Control) -> void:
	if c != null and c.is_inside_tree():
		c.grab_focus()


func _input(event: InputEvent) -> void:
	if _menus.size() <= 1 or not is_visible_in_tree():
		return
	if top().has_signal(&"closed"):
		return   # it handles its own Back (OptionsScreen)
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		pop()


## The first visible, enabled, focusable control under `root` in tree order.
static func first_focusable(root: Node) -> Control:
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree() \
				and not (c is BaseButton and (c as BaseButton).disabled):
			return c
	return null


## Up / down neighbours over the visible, enabled items, wrapping top <-> bottom.
static func wrap_focus(items: Array[Control]) -> void:
	var live: Array[Control] = []
	for c in items:
		if c != null and c.visible and not (c is BaseButton and (c as BaseButton).disabled):
			live.append(c)
	for i in live.size():
		var up := live[(i - 1 + live.size()) % live.size()]
		var down := live[(i + 1) % live.size()]
		live[i].focus_neighbor_top = live[i].get_path_to(up)
		live[i].focus_neighbor_bottom = live[i].get_path_to(down)
		live[i].focus_previous = live[i].focus_neighbor_top
		live[i].focus_next = live[i].focus_neighbor_bottom

extends "res://ui/rail/rail_chat.gd"
## M48.6c: the cabinet's dev-chat, as the terminal's dresser (PLAN 0.9.2 "The chat"). It keeps
## the rail chat's contract (TerminalPanel.set_dresser: the rows, their Label handles, every
## caller and rows() stay as they are; step() marks the hotfix rows and the patch rows as the
## rail did) and changes who draws: the terminal's rows are not shown at all (draws_rows), the
## CabinetChatView reads them every frame and draws the whole chat column on the cabinet's
## pixel grid. The terminal itself is an empty, click-through panel over the messages area;
## its input row (ChatInput) sits in the chat's input line.
## Undressing (detach) puts the terminal back exactly as it was.


func chat_colors() -> Dictionary:
	return CabinetArt.chat_colors()


## The rows are the chat's model only: the view draws them, the terminal hides its list.
func draws_rows() -> bool:
	return true


## Nothing behind the rows: the chat view draws the column.
func back_style() -> StyleBox:
	return StyleBoxEmpty.new()


func view() -> Control:
	return frame.get(&"chat_view")


func attach(t: TerminalPanel) -> void:
	terminal = t
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks and the wheel reach the chat under it
	var v := view()
	if v != null:
		t.dock_input(v)
		v.call(&"layout_input")
	step()


func detach(t: TerminalPanel) -> void:
	super(t)
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	if t.chat == null and t.chat_input != null:   # before the chat upgrade: the terminal's own idle text
		t.chat_input.idle_text = ChatInput.IDLE_TEXT
		t.chat_input.refresh_idle()


## The rail's marking (hotfix rows, patch rows, hidden choices), and the input's idle text
## names the AI ("Talk to Blob...") whatever the terminal's style.
func step() -> void:
	super()
	if terminal == null or not is_instance_valid(terminal) or terminal.chat_input == null:
		return
	var want := "Talk to %s..." % terminal.header_name()
	if terminal.chat_input.idle_text != want:
		terminal.chat_input.idle_text = want
		terminal.chat_input.refresh_idle()


func draw_layer(_ci: Control) -> void:
	pass


func draw_header(_ci: CanvasItem) -> void:
	pass

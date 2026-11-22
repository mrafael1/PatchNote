class_name DevSessionFlow
extends Node
## Report -> dev session -> patch notes -> next run (PLAN v5 4.1), shared by the game
## scene (after the report, F9) and the start screen (a pending session). It owns both
## screens and ships through DevSession; whoever starts it decides what "Play" does.
##
## BASIC goes straight to the patch notes (the AI shipped a basic itself);
## NONE shows the line and "Play" with no bump; a pick ships, then shows the notes.

## The session is shipped and logged (the shell writes its telemetry line).
signal session_done(session: DevSession)
signal play_requested

var session: DevSession
var screen: DevSessionScreen
var notes: PatchNotesScreen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = DevSessionScreen.new()
	screen.name = "DevSessionScreen"
	add_child(screen)
	notes = PatchNotesScreen.new()
	notes.name = "PatchNotes"
	add_child(notes)
	screen.picked.connect(_on_picked)
	screen.play_requested.connect(_on_nothing_to_ship)
	screen.rework_requested.connect(_on_rework)
	screen.keep_requested.connect(_on_nothing_to_ship)
	notes.play_requested.connect(func() -> void: play_requested.emit())


func is_open() -> bool:
	return screen.is_open() or notes.is_open()


func start(p_session: DevSession) -> void:
	session = p_session
	if session.shape == DevSession.BASIC:
		session.finish()
		session_done.emit(session)
		notes.open(session)
	else:
		screen.open(session)


func _on_picked(index: int) -> void:
	if session.pick(index):
		session_done.emit(session)
	notes.open(session)


func _on_rework(fork_id: StringName, to_id: StringName) -> void:
	if session.rework(fork_id, to_id):
		session_done.emit(session)
	notes.open(session)


func _on_nothing_to_ship() -> void:
	if session.finish():
		session_done.emit(session)
	play_requested.emit()

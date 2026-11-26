class_name GameView
extends SubViewportContainer
## M47.6a (PLAN v9.4 2.5, rev. 2 critic 2.3): the host's container for the game viewport.
## While the chat input has focus no key reaches the game (the debrief's choose_N and
## ui_accept, the HUD, the player): what is typed in the chat stays in the chat. Esc: the
## focused input takes the press first and hands it on (ChatInput.pause_pressed, the host
## opens the pause menu); the pause key is let through here too. Mouse and pad events, and
## every key while the input is unfocused, flow as before.

var chat: ChatInput


func _propagate_input_event(event: InputEvent) -> bool:
	if event is InputEventKey and chat_has_focus() and not event.is_action(&"pause"):
		return false
	return true


func chat_has_focus() -> bool:
	return chat != null and is_instance_valid(chat) and chat.has_focus()

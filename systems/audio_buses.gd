class_name AudioBuses
extends RefCounted
## PLAN v9.1 1.16 (M47.3): the audio buses, made in code (no bus layout file). Master is
## bus 0; SFX, UI and Voice are added once, by name, all sending to Master. Sound routes
## each key here: the AI's own voice (its compile chatter, the glitch and a rule edit's
## warning) to Voice, the menu and prompt sounds to UI, everything else to SFX. No Music
## bus: there is no music.

const SFX := &"SFX"
const UI := &"UI"
const VOICE := &"Voice"
const VOICE_KEYS: Array[StringName] = [&"compile", &"glitch", &"edit_warn"]
const UI_KEYS: Array[StringName] = [&"click", &"prompt", &"release_candidate"]


## Adds SFX, UI and Voice when missing (idempotent).
static func ensure() -> void:
	for bus: StringName in [SFX, UI, VOICE]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, &"Master")


## The bus a Sound key plays on.
static func bus_for(key: StringName) -> StringName:
	if key in VOICE_KEYS:
		return VOICE
	if key in UI_KEYS:
		return UI
	return SFX


## A bus's volume, linear 0-1 (0 mutes it).
static func set_volume(bus: StringName, linear: float) -> void:
	ensure()
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.0)


static func volume(bus: StringName) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0 or AudioServer.is_bus_mute(i):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(i))

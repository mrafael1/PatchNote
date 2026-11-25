class_name Settings
extends RefCounted
## PLAN v9.1 1.16 (M47.3): the player's settings, a static wrapper over the save's
## `settings` block (SaveGame.setting / set_setting). Save schema stays 2, additive:
## `reduce_flashing` and `asked` keep SaveGame's strict check; every key below is SPARSE
## (absent until the player changes it, so a new save's block is unchanged) and a value
## that is missing, of the wrong type or out of range reads as its default and never
## quarantines the save. `apply()` pushes the audio, window and frame settings to the
## engine; window and frame settings are skipped headless, under --fixed-fps and in tools.

## key -> [type, default, min, max] (a range) or [type, default, [allowed...]] (a set).
const SPEC := {
	"vol_master": [TYPE_FLOAT, 1.0, 0.0, 1.0],
	"vol_sfx": [TYPE_FLOAT, 1.0, 0.0, 1.0],
	"vol_ui": [TYPE_FLOAT, 1.0, 0.0, 1.0],
	"vol_voice": [TYPE_FLOAT, 1.0, 0.0, 1.0],
	"mute_unfocused": [TYPE_BOOL, false],
	"window_mode": [TYPE_INT, 0, [0, 1, 2]],          ## windowed / fullscreen / borderless
	"vsync": [TYPE_BOOL, true],
	"fps_cap": [TYPE_INT, 0, [0, 30, 60, 120, 144]],  ## 0 = no cap
	"window_scale": [TYPE_FLOAT, 1.0, [1.0, 1.5, 2.0]],
	"shake": [TYPE_FLOAT, 1.0, 0.0, 1.0],
	"text_speed": [TYPE_INT, 45, [30, 45, 70, 0]],    ## characters per second, 0 = instant
	"key_hints": [TYPE_BOOL, true],
	"chatter": [TYPE_BOOL, true],
	"front_door_seen": [TYPE_BOOL, false],            ## read by the title (M47.4)
}
## Window keys: ignored when window_applies() is false.
const WINDOW_KEYS: Array[String] = ["window_mode", "vsync", "fps_cap", "window_scale"]
## The shake multiplier's cap under reduce flashing (today's half shake).
const REDUCED_SHAKE := 0.5


## Holds the changed signal (a static class has none; same pattern as Skins.hub).
class Hub:
	extends RefCounted
	signal changed(key: String)

static var hub := Hub.new()
static var _base_size := Vector2i.ZERO   ## the window's size at scale 1 (first apply)
## The scale last set on a windowed window (-1 = none yet). M47.3 review: apply() runs on every
## go-live (Start, the volume slider, the fullscreen toggle), so window_scale is applied only
## when it differs from this, never snapping a moved or resized window back to centre.
static var _scale_applied := -1.0
## Counts the window resizes window_scale issues (tests read it).
static var scale_applies := 0
## Tests only: the window mode _apply_window sees, in place of the display's (-1 = the display's).
static var test_window_mode := -1


## True when `v` is a valid value for `key` (whole JSON floats count as ints).
static func valid(key: String, v: Variant) -> bool:
	if not SPEC.has(key):
		return false
	var spec: Array = SPEC[key]
	var t: int = spec[0]
	match t:
		TYPE_BOOL:
			if not v is bool:
				return false
		TYPE_INT:
			if v is float:
				if float(v) != floorf(float(v)):
					return false
			elif not v is int:
				return false
		TYPE_FLOAT:
			if not (v is float or v is int):
				return false
	if spec.size() == 3 and spec[2] is Array:
		for a: Variant in spec[2]:
			if is_equal_approx(float(a), float(v)):
				return true
		return false
	if spec.size() == 4:
		return float(v) >= float(spec[2]) and float(v) <= float(spec[3])
	return true


## `v` in the key's own type (an int from JSON's float...).
static func _coerce(key: String, v: Variant) -> Variant:
	match int((SPEC[key] as Array)[0]):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return float(v)
	return v


## The valid SPEC keys of a parsed `settings` block, coerced (SaveGame.parse merges them).
## Missing, wrong-typed or out-of-range keys are left out: they read as their default.
static func parse(src: Dictionary) -> Dictionary:
	var out := {}
	for key: String in SPEC:
		if src.has(key) and valid(key, src[key]):
			out[key] = _coerce(key, src[key])
	return out


static func defaults() -> Dictionary:
	var out := {}
	for key: String in SPEC:
		out[key] = (SPEC[key] as Array)[1]
	return out


static func default_of(key: String) -> Variant:
	return (SPEC[key] as Array)[1]


## The stored value when valid, else the default.
static func get_value(key: String) -> Variant:
	var v: Variant = SaveGame.setting(key)
	if v != null and valid(key, v):
		return _coerce(key, v)
	return default_of(key)


## Changes `key` in memory, applies it and emits hub.changed. Never writes: commit() does
## (OptionsScreen on close), so a slider drag is not a write per tick. `reduce_flashing`
## goes through here too (its strict bool check is SaveGame's).
static func set_value(key: String, v: Variant) -> void:
	if key == "reduce_flashing" or key == "asked":
		(SaveGame.state().settings as Dictionary)[key] = bool(v)
	elif valid(key, v):
		(SaveGame.state().settings as Dictionary)[key] = _coerce(key, v)
	else:
		return
	_apply_key(key)
	hub.changed.emit(key)


## Writes the save once (inert: nothing; replay: kept by end_replay; live: the file).
static func commit() -> void:
	SaveGame.write()


## False headless and when a tool script (-s) runs: the window and the frame rate are left
## alone (tests, hashes and bots stay as they are). --fixed-fps is consumed by the engine and
## never reaches OS.get_cmdline_args(); every --fixed-fps run here is headless or a tool.
static func window_applies() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_args()
	for a: String in args:
		if a == "--fixed-fps" or a == "-s" or a == "--script":
			return false
	return true


## Pushes every setting to the engine. `force` applies the window keys even under a tool
## (the windowed fullscreen check only).
static func apply(force := false) -> void:
	AudioBuses.ensure()
	for key: String in ["vol_master", "vol_sfx", "vol_ui", "vol_voice"]:
		_apply_key(key)
	if force or window_applies():
		for key in WINDOW_KEYS:
			_apply_window(key)


static func _apply_key(key: String) -> void:
	match key:
		"vol_master":
			AudioBuses.set_volume(&"Master", float(get_value(key)))
		"vol_sfx":
			AudioBuses.set_volume(AudioBuses.SFX, float(get_value(key)))
		"vol_ui":
			AudioBuses.set_volume(AudioBuses.UI, float(get_value(key)))
		"vol_voice":
			AudioBuses.set_volume(AudioBuses.VOICE, float(get_value(key)))
		_:
			if key in WINDOW_KEYS and window_applies():
				_apply_window(key)


static func _apply_window(key: String) -> void:
	match key:
		"window_mode":
			var mode := DisplayServer.WINDOW_MODE_WINDOWED
			var borderless := false
			match int(get_value(key)):
				1:
					mode = DisplayServer.WINDOW_MODE_FULLSCREEN
				2:
					mode = DisplayServer.WINDOW_MODE_MAXIMIZED
					borderless = true
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, borderless)
			if DisplayServer.window_get_mode() != mode:
				DisplayServer.window_set_mode(mode)
			# M47.3 review: a scale chosen while fullscreen or borderless lands on the way back.
			if _window_mode_now() == DisplayServer.WINDOW_MODE_WINDOWED:
				_apply_window("window_scale")
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value(key))
					else DisplayServer.VSYNC_DISABLED)
		"fps_cap":
			Engine.max_fps = int(get_value(key))
		"window_scale":
			if _window_mode_now() != DisplayServer.WINDOW_MODE_WINDOWED:
				return
			var scale := float(get_value(key))
			if scale == _scale_applied:
				return
			_scale_applied = scale
			scale_applies += 1
			if _base_size == Vector2i.ZERO:
				_base_size = Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
						int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
			var screen := DisplayServer.screen_get_usable_rect()
			var size := clamped_size(Vector2(_base_size) * scale, Vector2(screen.size))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## M47.5a: the window's size at scale 1 (GameHost: 1760x720 while the game is hosted beside
## the terminal; back to the project's 1280x720 when it leaves). The next apply() re-sizes.
static func set_window_base(base: Vector2i) -> void:
	if base == _base_size:
		return
	_base_size = base
	_scale_applied = -1.0


## M47.5a: `size` shrunk by one uniform factor to fit `screen` (never grown), so a wide
## window keeps its shape on a small screen.
static func clamped_size(size: Vector2, screen: Vector2) -> Vector2i:
	var f := minf(1.0, minf(screen.x / maxf(size.x, 1.0), screen.y / maxf(size.y, 1.0)))
	return Vector2i((size * f).round())


static func _window_mode_now() -> int:
	if test_window_mode >= 0:
		return test_window_mode
	return DisplayServer.window_get_mode()


# --- What the game reads ---------------------------------------------------------------

## The typing speed in characters per second (0 = instant), for the mascot and the debrief.
static func type_cps() -> float:
	return float(get_value("text_speed"))


## The camera shake multiplier: `shake`, capped at REDUCED_SHAKE under reduce flashing (the
## defaults give today's 1.0 / 0.5 exactly).
static func shake_mult() -> float:
	var s := float(get_value("shake"))
	if SaveGame.reduce_flashing():
		s = minf(s, REDUCED_SHAKE)
	return s


static func key_hints() -> bool:
	return bool(get_value("key_hints"))


static func chatter() -> bool:
	return bool(get_value("chatter"))

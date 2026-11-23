class_name EventDB
extends RefCounted
## The scripted events (PLAN v8 1.5): every events/<id>/<id>.tres, loaded on first use
## and sorted by id. Not an autoload; CampaignDB checks them and the event cues at boot.

const DIR := "res://events/"

static var _by_id := {}
static var _all: Array[ScriptedEvent] = []
static var _loaded := false


static func all() -> Array[ScriptedEvent]:
	_load()
	return _all.duplicate()


static func get_event(id: StringName) -> ScriptedEvent:
	_load()
	return _by_id.get(id)


static func reload() -> void:
	_loaded = false
	_load()


## What is wrong with an event (an empty list: nothing).
static func problems(ev: ScriptedEvent) -> Array[String]:
	var out: Array[String] = []
	var where := "event %s" % ev.id
	if ev.steps < 1:
		out.append("%s: steps must be >= 1" % where)
	for key: StringName in ev.lines:
		var l := Line.parse(ev.lines[key])
		if l.problem != "":
			out.append("%s: line %s: %s" % [where, key, l.problem])
		elif l.when != &"":
			out.append("%s: line %s cannot have a condition (it is said live)" % [where, key])
	# Its own script must declare play() (the method list, not the source: an exported
	# build ships no source code).
	var script := ev.get_script() as Script
	var own := script != null and script.resource_path != "res://core/scripted_event.gd" \
			and script.get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "play")
	if not own:
		out.append("%s: no play()" % where)
	return out


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id.clear()
	_all.clear()
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for folder in ResourceLoader.list_directory(DIR):
		var id := folder.trim_suffix("/")
		var path := DIR + id + "/" + id + ".tres"
		if not ResourceLoader.exists(path):
			continue
		var ev := load(path) as ScriptedEvent
		if ev == null:
			push_error("%s is not a ScriptedEvent" % path)
			continue
		if String(ev.id) != id:
			push_error("%s: id %s is not its folder's name" % [path, ev.id])
			continue
		_by_id[ev.id] = ev
		_all.append(ev)
	_all.sort_custom(func(a: ScriptedEvent, b: ScriptedEvent) -> bool: return String(a.id) < String(b.id))

class_name RailModel
extends RefCounted
## M48.5a: what the version rail shows, from the campaign data: the version each HUD module
## shipped in (the version at the start of the first session that adds its basic, folded from
## v0.0.0 over SessionDef.bump), and the rail's ticks. With today's data: KILLS (`enemies`)
## v0.2, HP (`health`) v0.3, DASH (`dash`) v0.4, the version stamp (`version`) v0.6, the
## path's hand / items / ammo (the first path session, S7's tryout) v0.7, Arsenal's pack (the
## first session with a chosen path) v0.8. Presentation only: it reads the campaign and the
## save's version, nothing of the run.

## Module -> the basic that ships it (path / pack: the path sessions).
const BASICS := {&"kills": &"enemies", &"hp": &"health", &"dash": &"dash", &"version": &"version"}

static var _ships := {}


## The version (a GameVersion) that shipped `module` (kills, hp, dash, version, path, pack).
static func ship_version(module: StringName) -> GameVersion:
	if _ships.is_empty():
		_build()
	var v: Variant = _ships.get(module)
	return (v as GameVersion) if v != null else GameVersion.make(0, 1, 0)


## Its "v0.4" label (minor versions only: a module ships with a session).
static func ship_label(module: StringName) -> String:
	var v := ship_version(module)
	return "v%d.%d" % [v.major, v.minor]


static func _build() -> void:
	var v := GameVersion.make(0, 0, 0)
	for s: SessionDef in CampaignDB.campaign.sessions:
		for m: StringName in BASICS:
			if not _ships.has(m) and BASICS[m] in s.basics:
				_ships[m] = GameVersion.from_array(v.to_array())
		if not _ships.has(&"path") and (s.tryout or s.path != &""):
			_ships[&"path"] = GameVersion.from_array(v.to_array())
		if not _ships.has(&"pack") and s.path != &"":
			_ships[&"pack"] = GameVersion.from_array(v.to_array())
		v.bump(s.bump)


## The minor versions on the rail up to `current` (v0.1 .. v0.M), each {minor, label}.
static func minors(current: GameVersion) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in range(1, current.minor + 1):
		out.append({"minor": m, "label": "v%d.%d" % [current.major, m]})
	return out


## True when `module` shipped at or before `current`.
static func shipped(module: StringName, current: GameVersion) -> bool:
	var v := ship_version(module)
	return v.major < current.major or (v.major == current.major and v.minor <= current.minor)

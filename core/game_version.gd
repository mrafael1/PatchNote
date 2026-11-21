class_name GameVersion
extends RefCounted
## The game's own version (PLAN v5 1.6): the meta-progression. major.minor.patch, read
## from and written to the save. A new save is v0.0.0. A dev-session pick is a patch
## step; a look tier (or, later, a genre maturity step) is a minor step.

const PATCH := &"patch"
const MINOR := &"minor"

var major := 0
var minor := 0
var patch := 0


static func make(p_major := 0, p_minor := 0, p_patch := 0) -> GameVersion:
	var v := GameVersion.new()
	v.major = p_major
	v.minor = p_minor
	v.patch = p_patch
	return v


## From the save's [major, minor, patch]. Anything else is v0.0.0.
static func from_array(a: Variant) -> GameVersion:
	if not (a is Array and (a as Array).size() == 3):
		return GameVersion.new()
	var parts := a as Array
	for p: Variant in parts:
		if not (p is int or p is float) or float(p) < 0.0:
			return GameVersion.new()
	return make(int(parts[0]), int(parts[1]), int(parts[2]))


func to_array() -> Array:
	return [major, minor, patch]


## kind is PATCH (patch + 1) or MINOR (minor + 1, patch back to 0). Returns false and
## changes nothing on any other kind.
func bump(kind: StringName) -> bool:
	match kind:
		PATCH:
			patch += 1
		MINOR:
			minor += 1
			patch = 0
		_:
			return false
	return true


## "v0.1.2"
func label() -> String:
	return "v" + short()


## "0.1.2" (the dev-session log's form)
func short() -> String:
	return "%d.%d.%d" % [major, minor, patch]


func equals(other: GameVersion) -> bool:
	return other != null and to_array() == other.to_array()

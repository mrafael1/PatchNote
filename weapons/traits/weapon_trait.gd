class_name WeaponTrait
extends RefCounted
## A rank 2-3 behaviour of a weapon (PLAN v9 1.4): weapons/traits/<id>.gd. Every hook is a
## no-op by default. Deterministic: a trait never draws from any random stream.
##
## M50.1a (Arsenal depth): a trait has a `level` (1 = unlocked; 2-4 = strengthened; 5+ =
## overflow, WeaponCurve.levels). steps() lists its values per level in today's units, and
## steps()[0] is today's constant, so the classic curve (always level 1) does not move.
## Past the last step each overflow level adds OVERFLOW of the last step's value to the
## fields overflow_keys() names. describe(level) is the card line.

const OVERFLOW := 0.1

var id: StringName
var level := 1
## M50.1a: built for the deep curve (Arsenal). Caps that are new with the deep curve apply only
## then, so the classic curve stays byte-identical.
var deep := false


## Before pellet `index` of a shot is spawned: edit its spawn params.
func shot(_weapon: Weapon, _index: int, _params: Dictionary) -> void:
	pass


## After a pellet is spawned: attach per-shot behaviour (a ProjectileMod).
func spawned(_weapon: Weapon, _projectile: Node) -> void:
	pass


## A passive weapon's node is ready (or rebuilt at a new rank).
func passive_ready(_weapon: Weapon, _node: Node) -> void:
	pass


## The player dashed.
func dashed(_weapon: Weapon) -> void:
	pass


## M50.1a: the values per level (level 1 first), one Dictionary each. [] = no levels.
func steps() -> Array:
	return []


## M50.1a: the fields an overflow level (past the last step) keeps strengthening.
func overflow_keys() -> Array:
	return []


## M50.1a: field `key` at this trait's level (overflow included); `fallback` when unknown.
func step_value(key: StringName, fallback: Variant = 0.0) -> Variant:
	return value_at(level, key, fallback)


func value_at(at_level: int, key: StringName, fallback: Variant = 0.0) -> Variant:
	var list := steps()
	if list.is_empty():
		return fallback
	var i := clampi(at_level, 1, list.size()) - 1
	var d: Dictionary = list[i]
	if not d.has(key):
		return fallback
	var over := at_level - list.size()
	if over > 0 and key in overflow_keys():
		var last: Variant = list[list.size() - 1][key]
		if typeof(last) == TYPE_INT:
			return int(last) + int(floor(float(last) * OVERFLOW * over))
		return float(last) * (1.0 + OVERFLOW * over)
	return d[key]


## M50.1a: the card line at `at_level` ("heavy every 4th shot").
func describe(_at_level: int) -> String:
	return String(id).replace("_", " ")


## The trait script for `trait_id`, instantiated.
static func make(trait_id: StringName, p_level := 1, p_deep := false) -> WeaponTrait:
	var script: Script = load(WeaponDef.TRAITS_DIR + String(trait_id) + ".gd")
	var t: WeaponTrait = script.new()
	t.id = trait_id
	t.level = p_level
	t.deep = p_deep
	return t

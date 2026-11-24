class_name WeaponTrait
extends RefCounted
## A rank 2-3 behaviour of a weapon (PLAN v9 1.4): weapons/traits/<id>.gd. Every hook is a
## no-op by default. Deterministic: a trait never draws from any random stream.

var id: StringName


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


## The trait script for `trait_id`, instantiated.
static func make(trait_id: StringName) -> WeaponTrait:
	var script: Script = load(WeaponDef.TRAITS_DIR + String(trait_id) + ".gd")
	var t: WeaponTrait = script.new()
	t.id = trait_id
	return t

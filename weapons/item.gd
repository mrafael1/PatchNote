class_name Item
extends RefCounted
## A held passive item (M50.4b): its def at a level (1..the path's rank_cap). Runtime only,
## never saved, owns no node; Loadout turns the held items into every weapon's mods.

var def: ItemDef
var level := 1


func _init(p_def: ItemDef = null, p_level := 1) -> void:
	def = p_def
	level = p_level


func id() -> StringName:
	return def.id


## "Haste 2".
func label() -> String:
	return "%s %d" % [def.title, level]

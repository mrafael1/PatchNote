class_name DamageInfo
extends RefCounted
## Describes one instance of damage. All damage goes through Health.take(info).

var amount := 0.0
var kind: StringName = &"contact"    ## &"projectile", &"explosion", &"contact", &"slam"
var faction: StringName = &"enemy"   ## who dealt it: &"player" or &"enemy"
var source_patch: StringName = &""   ## empty = base game, otherwise the patch id
var pos := Vector2.ZERO


static func make(p_amount: float, p_kind: StringName, p_faction: StringName,
		p_pos := Vector2.ZERO, p_source_patch: StringName = &"") -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.kind = p_kind
	info.faction = p_faction
	info.pos = p_pos
	info.source_patch = p_source_patch
	return info

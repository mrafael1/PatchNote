class_name Component
extends Node
## Small behaviour node attached to an entity (PLAN 2.3).
## Components read RunState.rules live and do not write persistent fields on their host.

## Id of the patch that added this component. Empty = part of the base entity.
var source_patch: StringName = &""


## The only way a patch adds a component. Does nothing if this entity already has
## this component from this patch.
static func attach(entity: Node, script: Script, patch: StringName = &"") -> Component:
	for c in entity.get_children():
		if c is Component and c.get_script() == script and c.source_patch == patch \
				and not c.is_queued_for_deletion():
			return c
	var comp: Component = script.new()
	comp.source_patch = patch
	entity.add_child(comp)
	return comp


static func find(entity: Node, script: Script) -> Component:
	for c in entity.get_children():
		if c is Component and c.get_script() == script and not c.is_queued_for_deletion():
			return c
	return null

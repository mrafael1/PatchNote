class_name MockupTake
extends Resource
## One of a mockup change's 3 takes (PLAN v5 1.6, 4.3): a still captured from the game,
## a title, the AI's one line, and what picking it ships (for a look, a LookPreset).

@export var id: StringName
@export var title := ""
@export var line := ""
@export var image: Texture2D
@export var preset: Resource

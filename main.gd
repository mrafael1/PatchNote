extends Node2D
## Entry scene. For now it only prints the boot banner that tools/check.ps1 looks for.

const BUILD := "v0.0 (M0)"


func _ready() -> void:
	var v: Dictionary = Engine.get_version_info()
	print("[boot] Alone Alone Lab %s, Godot %s.%s.%s" % [BUILD, v.major, v.minor, v.patch])

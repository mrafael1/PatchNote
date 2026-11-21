class_name GenreDef
extends Resource
## One genre's definition (PLAN v5 1.1), in genres/<id>/genre.tres. Its id names the
## take files of every patch (mutations/<patch>/<id>.gd) and its run is the Genre
## script below.

@export var id: StringName
@export var title := ""
@export var blurb := ""
@export var pace_unit: StringName = &"seconds"   ## seconds, turns, rooms...
@export var genre_script: Script                 ## a Genre subclass
@export var playable := true                     ## a run can start in it (ROADMAP 1.3)

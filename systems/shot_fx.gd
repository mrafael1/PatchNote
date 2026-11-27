class_name ShotFx
extends Node2D
## M50.6b: a drawn one-shot effect of the Pixel look (PLAN 1.7): the muzzle flash and the hit
## spark, one sprite held for a few frames. Presentation only: Feedback makes one from a
## gameplay event, only while its sprite is on, and nothing reads it back.

const MUZZLE := &"muzzle_flash"
const SPARK := &"hit_spark"
const LIFE := {&"muzzle_flash": 0.08, &"hit_spark": 0.1}   ## seconds on screen
const MAX_LIVE := 48   ## beyond this, new ones are skipped (a piercing beam through a horde)

static var live := 0

var id: StringName = SPARK
var fade := 1.0   ## alpha (reduce flashing: a dim spark)

var _age := 0.0


func _enter_tree() -> void:
	live += 1


func _exit_tree() -> void:
	live -= 1


func _process(delta: float) -> void:
	_age += delta
	if _age >= float(LIFE.get(id, 0.1)):
		queue_free()


func _draw() -> void:
	var skin := Skins.on(id)
	if skin == null or not skin.has(id):
		return
	var s := float(ArtSkin.BODY_SCALE)
	skin.draw(self, id, offset(skin, id, s), s, 0, Color(1, 1, 1, fade))


## Where the sprite's centre sits: the flash's flat side is on the muzzle (it points along +x,
## the node's heading), the spark is centred on the hit.
static func offset(skin: ArtSkin, sprite: StringName, s: float) -> Vector2:
	return Vector2(skin.size_of(sprite).x * s * 0.5, 0.0) if sprite == MUZZLE else Vector2.ZERO

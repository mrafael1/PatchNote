extends Node2D
## M48.6b: the HUD on the player in the cabinet (PLAN 0.9.2; the mockup's hearts and dashPie):
## a row of hearts over the head and a pixel ring around the body that fills as the dash
## cools down (mint when ready). On the Survival path the hearts sit under the feet: the rounds
## are over the head (AmmoOverhead). It shows what the rail's HP and DASH modules showed, from
## the same reading (RailState, the frame's snap).
##
## The CabinetFrame adds it to the live player while the cabinet shows and frees it when it
## goes (no gameplay script knows it). Drawn on the view's art grid: one cell is CELL sim px
## (the 1280x720 sim is 384x216 art px). Presentation only: it reads the snap, writes nothing,
## draws no RNG; the low-HP beat is real time and still under reduce flashing.

const CELL := 720.0 / 216.0   ## one art px in sim px
const ABOVE := -20            ## the hearts' top, art px from the player's centre
const UNDER := 13             ## on the Survival path
const HEART_STEP := 8         ## a heart is 7 wide, 1 apart
const MAX_HEARTS := 10
const RING_R := 10

var frame: Node   ## the CabinetFrame


func _ready() -> void:
	z_index = 40   # over the arena's bodies, under the rounds (AmmoOverhead 50)


func reading() -> Dictionary:
	return frame.snap if frame != null and is_instance_valid(frame) else {}


## The hearts row: [full...] (true full, false empty); empty when HP is not live.
func hearts() -> Array[bool]:
	var out: Array[bool] = []
	var hp: Dictionary = reading().get("hp", {})
	if not hp.get("on", false):
		return out
	for i in mini(int(hp.max), MAX_HEARTS):
		out.append(i < int(hp.hp))
	return out


## The hearts go under the feet on the Survival path (its rounds are over the head).
func hearts_under() -> bool:
	return reading().get("path", {}).get("kind", &"") == &"ammo"


## The row's top-left in art px from the player's centre.
func hearts_at() -> Vector2i:
	var n := hearts().size()
	return Vector2i(-((n * HEART_STEP - 1) / 2), UNDER if hearts_under() else ABOVE)


## The dash ring: {on, ready, frac} (frac 0..1 of the cooldown done).
func ring() -> Dictionary:
	var d: Dictionary = reading().get("dash", {})
	return {"on": bool(d.get("on", false)), "ready": bool(d.get("ready", true)), "frac": float(d.get("frac", 1.0))}


func _process(_delta: float) -> void:
	if global_rotation != 0.0:
		global_rotation = 0.0
	queue_redraw()


func _draw() -> void:
	if frame == null or not is_instance_valid(frame) or not frame.on:
		return
	var half := Vector2(0.5, 0.5) * CELL
	var r := ring()
	if r.on:
		for rr: int in [RING_R - 1, RING_R, RING_R + 1]:
			CabinetArt.draw_ring(self, -half, rr, CELL, CabinetArt.c(&"ink"))
		var full: bool = r.ready or r.frac >= 1.0
		CabinetArt.draw_ring(self, -half, RING_R, CELL, CabinetArt.c(&"mint") if full else CabinetArt.c(&"orange"),
				1.0 if full else r.frac)
	var row := hearts()
	if row.is_empty():
		return
	var at := hearts_at()
	var left := row.count(true)
	var beat := left > 0 and left <= 2 and row.size() > 2 and not SaveGame.reduce_flashing() \
			and sin(Time.get_ticks_msec() / 110.0) > 0.0
	for i in row.size():
		var cell := Vector2(at.x + i * HEART_STEP, at.y - (1 if beat and row[i] else 0))
		CabinetArt.hud(self, &"heart" if row[i] else &"heart_empty", cell * CELL - half, CELL)

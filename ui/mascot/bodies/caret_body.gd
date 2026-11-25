extends MascotBody
## Before the face (PLAN v8 1.3, SessionDef.face = false): the AI is only a blinking
## text caret. It stays lit while it types; panic blinks it fast, surprise makes it
## jump, thinking adds three dots.

const COLOR := Color(0.55, 1.0, 0.65)
const SIZE := Vector2(16, 30)


## M47.2: the caret and its three thinking dots.
func outline() -> PackedVector2Array:
	return PackedVector2Array([-SIZE * 0.5, SIZE * 0.5, Vector2(SIZE.x * 0.5 + 27.0, SIZE.y * 0.5 - 5.0),
			Vector2(SIZE.x * 0.5 + 27.0, SIZE.y * 0.5 + 1.0)])


func _paint() -> void:
	var lit := talking or fmod(t, 1.06) < 0.62
	if expression == &"panic":
		lit = fmod(t, 0.18) < 0.1
	if lit:
		draw_rect(Rect2(-SIZE * 0.5, SIZE), col(COLOR))
	else:
		draw_rect(Rect2(Vector2(-SIZE.x * 0.5, SIZE.y * 0.5 - 3.0), Vector2(SIZE.x, 3.0)), col(Color(COLOR, 0.35)))
	if expression == &"thinking" and not talking:
		for i in 3:
			if fmod(t * 2.0, 4.0) > float(i):
				draw_circle(Vector2(SIZE.x * 0.5 + 8.0 + 8.0 * i, SIZE.y * 0.5 - 2.0), 2.2, col(COLOR))

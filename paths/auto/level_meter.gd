extends RefCounted
# path:auto
## Auto's levels (PLAN v9 1.5): gems taken fill it; each threshold crossed is a level-up
## (EventBus.level_up) and asks the PathRunner for a pick. A tryout levels on the path's
## taste list (S7: one level at 6 gems), then stops quietly. Elsewhere it stops after
## max_picks level-ups with one line. Runtime only, never saved.

var def: PathDef
var tryout := false
var gems := 0
var level := 1
var stopped := false
## Called with no argument on each level-up (PathRunner.want_pick) and once when the meter
## fills up (PathRunner.meter_full); either may be invalid in tests.
var on_level := Callable()
var on_full := Callable()


func add(value: int) -> void:
	if stopped:
		return
	gems += value
	while not stopped:
		var need := def.threshold(level, tryout)
		if need < 0:
			stopped = true   # past the taste: quiet
			break
		if gems < need:
			break
		level += 1
		EventBus.level_up.emit(level)
		if on_level.is_valid():
			on_level.call()
		if level - 1 >= def.max_picks:
			stopped = true
			if not tryout and on_full.is_valid():
				on_full.call()


## The gems needed for the next level (-1: no next level).
func next_need() -> int:
	return -1 if stopped else def.threshold(level, tryout)


## 0..1 toward the next level (1 once stopped).
func progress() -> float:
	var need := next_need()
	if need < 0:
		return 1.0
	var from := def.threshold(level - 1, tryout) if level > 1 else 0
	from = maxi(from, 0)
	return clampf(float(gems - from) / maxf(1.0, float(need - from)), 0.0, 1.0)

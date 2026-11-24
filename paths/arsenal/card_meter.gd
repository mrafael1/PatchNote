extends RefCounted
# path:arsenal
## Arsenal's card meter (PLAN v9 1.5, M46): player kills fill it (the gems' filter: a kill
## whose DamageInfo faction is the player's; a bomber's own fuse kill does not count). Each
## cumulative threshold of PathDef.level_thresholds (15, 36, 65, ...: 15 then x1.4) deals a
## card: a pick is owed (PathRunner.want_pick). A tryout deals on the taste list, then stops
## quietly; elsewhere it stops after max_picks cards with full_line. Runtime only, never
## saved. PathRunner feeds it from EventBus.enemy_killed (connected only while it exists).

var def: PathDef
var tryout := false
var kills := 0
var cards := 0
var stopped := false
## Called with no argument on each card (PathRunner.want_pick) and once when the meter fills
## up (PathRunner._on_meter_full); either may be invalid in tests.
var on_card := Callable()
var on_full := Callable()


func add(n: int) -> void:
	if stopped:
		return
	kills += n
	while not stopped:
		var need := def.threshold(cards + 1, tryout)
		if need < 0:
			stopped = true   # past the taste: quiet
			break
		if kills < need:
			break
		cards += 1
		if on_card.is_valid():
			on_card.call()
		if cards >= def.max_picks:
			stopped = true
			if not tryout and on_full.is_valid():
				on_full.call()


## The cumulative kills the next card needs (-1: no next card).
func next_need() -> int:
	return -1 if stopped else def.threshold(cards + 1, tryout)


## 0..1 toward the next card (1 once stopped).
func progress() -> float:
	var need := next_need()
	if need < 0:
		return 1.0
	var from := maxi(def.threshold(cards, tryout), 0) if cards > 0 else 0
	return clampf(float(kills - from) / maxf(1.0, float(need - from)), 0.0, 1.0)

extends RefCounted
# path:arsenal
## Arsenal's pack meter (M50.1a, Arsenal depth design 1): player kills fill it (the card
## meter's filter, PathRunner._on_enemy_killed), counted from the `cards` basic on. Every
## PathDef.pack_every kills deals a pack (`on_card`: PathRunner.want_pick). No session cap;
## a tryout deals PathDef.pack_taste packs, then stops quietly. The same reading API as
## CardMeter (kills, cards, stopped, next_need, progress), so the hand, F1 and the bot read
## either. Runtime only, never saved.

var def: PathDef
var tryout := false
var kills := 0
var cards := 0      ## packs dealt
var stopped := false
var on_card := Callable()
var on_full := Callable()   ## never called (no cap); kept for CardMeter's shape


func add(n: int) -> void:
	if stopped or def == null or def.pack_every <= 0:
		return
	if tryout and cards >= def.pack_taste:
		stopped = true
		return
	kills += n
	while not stopped and kills >= (cards + 1) * def.pack_every:
		cards += 1
		if on_card.is_valid():
			on_card.call()
		if tryout and cards >= def.pack_taste:
			stopped = true   # past the taste: quiet


## The cumulative kills the next pack needs (-1: none).
func next_need() -> int:
	if stopped or def == null or def.pack_every <= 0:
		return -1
	return (cards + 1) * def.pack_every


## Kills still needed for the next pack (-1: none).
func kills_left() -> int:
	var need := next_need()
	return maxi(0, need - kills) if need >= 0 else -1


## 0..1 toward the next pack (1 once stopped).
func progress() -> float:
	var need := next_need()
	if need < 0:
		return 1.0
	return clampf(float(kills - cards * def.pack_every) / float(def.pack_every), 0.0, 1.0)

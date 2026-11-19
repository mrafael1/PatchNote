class_name Taste
extends RefCounted
## What the AI has learned about the player's taste (the "adaptive path", first step).
##
## Scores per mutation id and per tag go up when the player picks or keeps something,
## and down when they pass it over, roll it back or cut it on the report. The Director
## leans its offers toward high scores, and saves one card per offer for its own
## agenda: the thing the player likes least so far.
##
## Nothing is saved to disk. The ratings from the report carry over to the next run
## of the same session only (static), and fade by half each run.

const PICK := 1.0
const PASS := -0.25          ## each card shown but not picked
const REVERT := -2.0
const RATE := 2.0            ## Keep = +RATE, Cut = -RATE
const TAG_SHARE := 0.5       ## a tag moves by this share of what the id moves
const CARRY_FADE := 0.5
const MIN_MULT := 0.2
const MAX_MULT := 3.0
const LEAN := 0.4            ## weight multiplier change per point of score

## Ratings carried from the last run of this session: id -> +1 / -1.
static var carried := {}
## Whether the previous run of this session was rated: -1 no previous run, 0 skipped, 1 rated.
static var last_run_rated := -1

var by_id := {}
var by_tag := {}


## Starts from what the session's previous runs taught.
static func from_session() -> Taste:
	var t := Taste.new()
	for id: StringName in carried:
		var m := MutationDB.get_mutation(id)
		if m:
			t._nudge(m, RATE * CARRY_FADE * float(carried[id]))
	return t


static func clear_session() -> void:
	carried.clear()
	last_run_rated = -1


func on_offer(cards: Array[Mutation], pick: Mutation) -> void:
	for m in cards:
		if m != pick:
			_nudge(m, PASS)
	if pick:
		_nudge(pick, PICK)


func on_revert(m: Mutation) -> void:
	_nudge(m, REVERT)


func on_rating(m: Mutation, value: int) -> void:
	_nudge(m, RATE * signf(value))


func score(m: Mutation) -> float:
	var s := float(by_id.get(m.id, 0.0))
	for tag in m.tags:
		s += float(by_tag.get(tag, 0.0))
	return s


## Multiplier on a mutation's base weight when the Director samples offers.
func weight_mult(m: Mutation) -> float:
	return clampf(1.0 + LEAN * score(m), MIN_MULT, MAX_MULT)


## The tag the player leans to most, if it clearly leads; &"" otherwise.
func favourite_tag(threshold := 1.5) -> StringName:
	var best: StringName = &""
	var best_score := threshold
	for tag: StringName in by_tag:
		if float(by_tag[tag]) >= best_score:
			best = tag
			best_score = by_tag[tag]
	return best


func to_dict() -> Dictionary:
	var ids := {}
	for k: StringName in by_id:
		ids[String(k)] = snappedf(by_id[k], 0.01)
	var tags := {}
	for k: StringName in by_tag:
		tags[String(k)] = snappedf(by_tag[k], 0.01)
	return {"ids": ids, "tags": tags}


func _nudge(m: Mutation, amount: float) -> void:
	by_id[m.id] = float(by_id.get(m.id, 0.0)) + amount
	for tag in m.tags:
		by_tag[tag] = float(by_tag.get(tag, 0.0)) + amount * TAG_SHARE

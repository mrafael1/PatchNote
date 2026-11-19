class_name AiDirector
extends Node
## The scripted "AI" (PLAN 6 and 7): decides when a prompt opens, what it offers,
## and owns the revert charges. It knows no mutation by name; it only reads the
## fields every Mutation has.
##
## Flow: poll() -> prompt_requested(offer) -> (UI) -> on_choice(offer, m).
## Tests drive it the same way, without any UI.

signal prompt_requested(offer: Offer)

var transition: Transition   ## optional: patches go through it when set
var enabled := true

var prompt_index := 0        ## small prompts opened so far
var big_index := 0           ## BIG prompts opened (or skipped) so far
var reverts_left := 0
var pending: Offer           ## an offer waiting for its choice
var reverted := {}           ## ids the player rolled back; never offered again
var taste: Taste             ## what the player seems to like; leans the offers

var _kills_since_prompt := 0
var _last_prompt_time := 0.0
var _kills_needed := 0
var _hint_given := false


func _ready() -> void:
	reverts_left = Tuning.reverts_per_run
	taste = Taste.from_session()
	_kills_needed = Tuning.first_prompt_kills
	_last_prompt_time = RunState.game_time
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _physics_process(_delta: float) -> void:
	poll()


func context() -> Dictionary:
	return {"time": RunState.game_time, "kills": _kills_since_prompt}


## Opens a prompt if the pacing rule says so. Called every physics tick. A BIG prompt
## that is due opens first, right after the small prompt it follows has been applied.
func poll() -> void:
	if not enabled or pending != null or (transition and transition.busy):
		return
	if big_prompt_due():
		open_big_prompt()
		return
	var ctx := context()
	if should_prompt(ctx):
		open_prompt(ctx)


## True when the small prompt a BIG prompt follows has been opened and the BIG one not yet.
func big_prompt_due() -> bool:
	var after := Tuning.big_prompt_after
	return big_index < after.size() and prompt_index >= after[big_index]


## How many BIG prompts this run has: those that follow a small prompt that exists.
func big_prompts_per_run() -> int:
	var n := 0
	for a in Tuning.big_prompt_after:
		if a <= Tuning.prompts_per_run:
			n += 1
	return n


## Every small and BIG prompt has been opened and answered (or skipped).
func prompts_done() -> bool:
	return prompt_index >= Tuning.prompts_per_run and big_index >= big_prompts_per_run() \
			and pending == null


## (enough counted kills AND the minimum gap) OR the maximum gap.
func should_prompt(ctx: Dictionary) -> bool:
	if prompt_index >= Tuning.prompts_per_run:
		return false
	var gap: float = ctx.time - _last_prompt_time
	if gap >= Tuning.prompt_max_gap:
		return true
	return ctx.kills >= _kills_needed and gap >= Tuning.prompt_min_gap


## Also used by the debug key, which ignores the pacing rule.
func open_prompt(ctx := context()) -> void:
	if pending != null:
		return
	var offer := get_offer(ctx)
	_last_prompt_time = ctx.time
	_kills_since_prompt = 0
	_kills_needed += Tuning.prompt_kills_step
	if offer.cards.is_empty():
		RunState.log_event(&"prompt_skipped", {"index": offer.prompt_index})
		if transition:
			transition.say(Dialogue.NOTHING_LEFT)
		return
	pending = offer
	prompt_requested.emit(offer)


## Up to offer_size patches, weighted, without repeats, all of them applicable now
## and none of them rolled back earlier in this run.
func get_offer(_ctx: Dictionary) -> Offer:
	prompt_index += 1
	var offer := Offer.new()
	offer.prompt_index = prompt_index
	offer.line = Dialogue.prompt_line(prompt_index)
	var pool: Array[Mutation] = []
	for m in MutationDB.all:
		if RunState.can_apply(m) and not reverted.has(m.id):
			pool.append(m)

	if prompt_index == Tuning.force_gravity_at_prompt and not _mode_switch_applied():
		for m in pool:
			if m.is_mode_switch:
				offer.cards = [m]
				offer.mandatory = true
				offer.line = Dialogue.MANDATORY
				return offer

	var rng := RunState.director_rng
	var agenda_count := mini(agenda_cards(), Tuning.offer_size - 1)
	# Cards that follow the player's taste...
	while offer.cards.size() < Tuning.offer_size - agenda_count and not pool.is_empty():
		var pick := _weighted_pick(pool, rng)
		offer.cards.append(pick)
		pool.erase(pick)
	# ...and the AI's own picks: what the player likes least so far.
	while offer.cards.size() < Tuning.offer_size and not pool.is_empty():
		var pick := _least_liked(pool, rng)
		offer.cards.append(pick)
		offer.agenda.append(pick)
		pool.erase(pick)
	var said := Dialogue.taste_line(taste, prompt_index, Taste.last_run_rated)
	if said != "":
		offer.line = said
	return offer


## Opens the next BIG prompt (PLAN v3 section 4), or logs it as skipped when there is
## no big patch to swap to.
func open_big_prompt() -> void:
	if pending != null:
		return
	var offer := get_big_offer(context())
	if offer.cards.is_empty():
		RunState.log_event(&"big_prompt_skipped", {"index": offer.prompt_index})
		return
	pending = offer
	prompt_requested.emit(offer)


## Up to big_offer_size big patches, never the one in the slot, leaned by taste. With
## two or more candidates the last of them is the AI's agenda (least liked). Every BIG
## prompt after the first ends with a Keep card for the patch in the slot. Nothing to
## swap to gives an empty offer (no prompt): a lone Keep card is not a choice.
func get_big_offer(_ctx: Dictionary) -> Offer:
	big_index += 1
	var offer := Offer.new()
	offer.big = true
	offer.prompt_index = big_index
	var pool: Array[Mutation] = []
	for m in MutationDB.all:
		if m.is_big and m != RunState.big:
			pool.append(m)
	if pool.is_empty():
		return offer
	var rng := RunState.director_rng
	var size := mini(Tuning.big_offer_size, pool.size())
	var agenda_count := 1 if size >= 2 else 0
	while offer.cards.size() < size - agenda_count:
		var pick := _weighted_pick(pool, rng)
		offer.cards.append(pick)
		pool.erase(pick)
	if agenda_count > 0:
		var pick := _least_liked(pool, rng)
		offer.cards.append(pick)
		offer.agenda.append(pick)
	offer.line = offer.cards[0].line_proposal
	if big_index > 1 and RunState.big != null:
		offer.keep = RunState.big
		offer.cards.append(RunState.big)
	return offer


func _weighted_pick(pool: Array[Mutation], rng: RandomNumberGenerator) -> Mutation:
	var total := 0.0
	for m in pool:
		total += _weight(m)
	var roll := rng.randf() * total
	for m in pool:
		roll -= _weight(m)
		if roll < 0.0:
			return m
	return pool[pool.size() - 1]


## What the player likes least so far; ties broken at random.
func _least_liked(pool: Array[Mutation], rng: RandomNumberGenerator) -> Mutation:
	var lowest: Array[Mutation] = []
	var low := INF
	for m in pool:
		var sc := taste.score(m)
		if sc < low - 0.001:
			low = sc
			lowest = [m]
		elif absf(sc - low) <= 0.001:
			lowest.append(m)
	return lowest[rng.randi_range(0, lowest.size() - 1)]


## How many cards per offer the AI keeps for its own agenda.
func agenda_cards() -> int:
	return Tuning.agenda_cards_unrated if Taste.last_run_rated == 0 else Tuning.agenda_cards


func _weight(m: Mutation) -> float:
	return maxf(m.weight, 0.0) * taste.weight_mult(m)


## The player picked a card: log, apply (with its transition), heal one HP.
func on_choice(offer: Offer, m: Mutation) -> void:
	if offer == null or not offer.cards.has(m):
		return
	if pending == offer:
		pending = null
	if offer.big:
		_on_big_choice(offer, m)
		return
	RunState.log_event(&"prompt", {"index": offer.prompt_index, "offers": _id_list(offer.cards),
			"pick": String(m.id), "mandatory": offer.mandatory, "agenda": _id_list(offer.agenda)})
	if not offer.mandatory:
		taste.on_offer(offer.cards, m)
	RunState.start_grace(Tuning.grace_time)
	if transition and not _hint_given:
		transition.queue_hint(Dialogue.ROLLBACK_HINT)
	_hint_given = true
	var accepted := transition.request_apply(m) if transition else RunState.apply(m)
	if not accepted:
		return
	_heal_player()


## A BIG prompt's choice: swap the slot (one permanent build; heals like a patch), or
## keep the patch already there (nothing changes).
func _on_big_choice(offer: Offer, m: Mutation) -> void:
	var kept := m == offer.keep
	RunState.log_event(&"big_prompt", {"index": offer.prompt_index, "offers": _id_list(offer.cards),
			"pick": String(m.id), "agenda": _id_list(offer.agenda),
			"keep": String(offer.keep.id) if offer.keep else "", "kept": kept})
	taste.on_offer(offer.cards, m)
	if kept:
		if transition:
			transition.say(Dialogue.BIG_KEPT)
		return
	RunState.start_grace(Tuning.grace_time)
	if transition:
		if not transition.request_swap_big(m):
			return
	else:
		RunState.swap_big(m)
		if RunState.big != m:
			return
	_heal_player()


func _id_list(cards: Array[Mutation]) -> Array[String]:
	var ids: Array[String] = []
	for card in cards:
		ids.append(String(card.id))
	return ids


func _heal_player() -> void:
	for p in get_tree().get_nodes_in_group(&"player"):
		var health := Component.find(p, Health) as Health
		if health:
			health.heal(Tuning.hotfix_heal)


func can_revert(m: Mutation) -> bool:
	return reverts_left > 0 and m != null and RunState.stack.has(m) \
			and not (transition and transition.busy)


## Spends one charge to roll m back, together with anything that depends on it.
func revert(m: Mutation) -> bool:
	if not can_revert(m):
		return false
	var going := RunState.dependents_of(m)
	going.append(m)
	var hp := -1.0
	for p in get_tree().get_nodes_in_group(&"player"):
		var health := Component.find(p, Health) as Health
		if health:
			hp = health.hp()
	var accepted := transition.request_revert(m) if transition else not RunState.revert(m).is_empty()
	if not accepted:
		return false
	reverts_left -= 1
	RunState.log_event(&"revert_used", {"id": String(m.id), "hp": hp,
			"removed": going.size(), "reverts_left": reverts_left})
	for x in going:
		on_revert(x)
	return true


func on_revert(m: Mutation) -> void:
	reverted[m.id] = true
	taste.on_revert(m)


func _mode_switch_applied() -> bool:
	for m in RunState.stack:
		if m.is_mode_switch:
			return true
	return false


func _on_enemy_killed(enemy: Node, _info: RefCounted) -> void:
	# Only enemies from the wave spawner count; copies and patch spawns do not.
	if is_instance_valid(enemy) and enemy.get(&"from_spawner") == true and enemy.get(&"generation") == 0:
		_kills_since_prompt += 1

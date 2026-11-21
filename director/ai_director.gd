class_name AiDirector
extends Node
## The scripted "AI" (PLAN 6 and 7): decides when a prompt opens and what it offers.
## It knows no mutation by name; it only reads the fields every Mutation has. BIG
## prompts are gone from play (PLAN v5 1.3). Rollbacks (PLAN v4 1.3, option D, AI
## patches only) are parked: the run starts with no charge, and only tests spend them.
##
## Flow: poll() -> prompt_requested(offer) -> (UI) -> on_choice(offer, m).
## Tests drive it the same way, without any UI.

signal prompt_requested(offer: Offer)

var transition: Transition   ## optional: patches go through it when set
var enabled := true

var prompt_index := 0        ## small prompts opened so far
var charges := 0             ## rollbacks left (PLAN v4 1.3)
var charges_earned := 0      ## charges this run has had in all, the starting one included
var pending: Offer           ## an offer waiting for its choice
var reverted := {}           ## small ids rolled back; never offered again. AI rollbacks never write it
var taste: Taste             ## what the player seems to like; leans the offers

var _kills_since_prompt := 0
var _last_prompt_time := 0.0
var _kills_needed := 0
var _hint_given := false


func _ready() -> void:
	charges = Tuning.rollback_charges_start
	charges_earned = charges
	taste = Taste.from_session()
	_kills_needed = Tuning.first_prompt_kills
	_last_prompt_time = RunState.game_time
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _physics_process(_delta: float) -> void:
	poll()


func context() -> Dictionary:
	return {"time": RunState.game_time, "kills": _kills_since_prompt}


## Opens a prompt if the pacing rule says so. Called every physics tick.
func poll() -> void:
	if not enabled or pending != null or (transition and transition.busy):
		return
	var ctx := context()
	if should_prompt(ctx):
		open_prompt(ctx)


## Every small prompt has been opened and answered (or skipped).
func prompts_done() -> bool:
	return prompt_index >= Tuning.prompts_per_run and pending == null


## (enough counted kills AND the minimum gap) OR the maximum gap.
func should_prompt(ctx: Dictionary) -> bool:
	if prompt_index >= Tuning.prompts_per_run:
		return false
	var gap: float = ctx.time - _last_prompt_time
	if gap >= Tuning.prompt_max_gap:
		return true
	return ctx.kills >= _kills_needed and gap >= min_gap()


## The minimum gap before the next small prompt. The first one comes sooner.
func min_gap() -> float:
	return Tuning.first_prompt_min_gap if prompt_index == 0 else Tuning.prompt_min_gap


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
	for m in MutationDB.offerable():
		# can_apply refuses mediums and boss-only patches: they never reach a small offer.
		if RunState.can_apply(m) and not reverted.has(m.id):
			pool.append(m)

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


## Option D (PLAN v4 1.3): only a live AI patch, never a stack patch.
func can_revert(m: Mutation) -> bool:
	return charges > 0 and m != null and RunState.ai.has(m) \
			and not (transition and transition.busy)


## Spends one charge to roll AI patch m back, together with its AI dependents. A stage
## patch rolled back lowers its taste; a boss patch does not. Never writes `reverted`.
func revert(m: Mutation) -> bool:
	if not can_revert(m):
		return false
	var going := RunState.ai_dependents_of(m)
	going.append(m)
	var owners := {}
	for x in going:
		owners[x.id] = RunState.ai_owner.get(x.id, &"")
	var hp := -1.0
	for p in get_tree().get_nodes_in_group(&"player"):
		var health := Component.find(p, Health) as Health
		if health:
			hp = health.hp()
	var accepted := transition.request_ai_remove(m, &"rollback") if transition \
			else not RunState.remove_ai(m, &"rollback").is_empty()
	if not accepted:
		return false
	charges -= 1
	RunState.log_event(&"revert_used", {"id": String(m.id), "owner": String(owners[m.id]), "hp": hp,
			"removed": going.size(), "charges": charges})
	for x in going:
		if owners[x.id] == &"stage":
			taste.on_revert(x)
	return true


## A stage clear's charge (PLAN v4 1.3). Parked with rollbacks: only the tests call it.
func add_stage_charge() -> void:
	charges += Tuning.rollback_charges_per_stage
	charges_earned += Tuning.rollback_charges_per_stage
	RunState.log_event(&"charge_earned", {"charges": charges})


## A small patch rolled back (v2 interface): never offered again this run, and its
## taste drops. No player-facing path reverts a small patch any more (option D).
func on_revert(m: Mutation) -> void:
	reverted[m.id] = true
	taste.on_revert(m)


func _on_enemy_killed(enemy: Node, _info: RefCounted) -> void:
	# Only enemies from the wave spawner count; copies and patch spawns do not.
	if is_instance_valid(enemy) and enemy.get(&"from_spawner") == true and enemy.get(&"generation") == 0:
		_kills_since_prompt += 1

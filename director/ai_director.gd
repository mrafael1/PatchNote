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

var prompt_index := 0        ## prompts opened so far
var reverts_left := 0
var pending: Offer           ## an offer waiting for its choice
var reverted := {}           ## ids the player rolled back; never offered again

var _kills_since_prompt := 0
var _last_prompt_time := 0.0
var _kills_needed := 0
var _hint_given := false


func _ready() -> void:
	reverts_left = Tuning.reverts_per_run
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
	while offer.cards.size() < Tuning.offer_size and not pool.is_empty():
		var total := 0.0
		for m in pool:
			total += maxf(m.weight, 0.0)
		var roll := rng.randf() * total
		var pick := pool[pool.size() - 1]
		for m in pool:
			roll -= maxf(m.weight, 0.0)
			if roll < 0.0:
				pick = m
				break
		offer.cards.append(pick)
		pool.erase(pick)
	return offer


## The player picked a card: log, apply (with its transition), heal one HP.
func on_choice(offer: Offer, m: Mutation) -> void:
	if offer == null or not offer.cards.has(m):
		return
	if pending == offer:
		pending = null
	var ids: Array[String] = []
	for card in offer.cards:
		ids.append(String(card.id))
	RunState.log_event(&"prompt", {"index": offer.prompt_index, "offers": ids,
			"pick": String(m.id), "mandatory": offer.mandatory})
	RunState.start_grace(Tuning.grace_time)
	if transition and not _hint_given:
		transition.queue_hint(Dialogue.ROLLBACK_HINT)
	_hint_given = true
	var accepted := transition.request_apply(m) if transition else RunState.apply(m)
	if not accepted:
		return
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


func _mode_switch_applied() -> bool:
	for m in RunState.stack:
		if m.is_mode_switch:
			return true
	return false


func _on_enemy_killed(enemy: Node, _info: RefCounted) -> void:
	# Only enemies from the wave spawner count; copies and patch spawns do not.
	if is_instance_valid(enemy) and enemy.get(&"from_spawner") == true and enemy.get(&"generation") == 0:
		_kills_since_prompt += 1

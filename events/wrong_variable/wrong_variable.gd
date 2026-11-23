extends ScriptedEvent
## wrong_variable (PLAN v8 1.5, S5): the AI means to speed the enemies up and flips
## gravity instead: left, up, down, then off, then the speed it meant. The session
## clock is held from the first flip to the clear, so the player keeps the full goal.

const GRAVITY: Array[StringName] = [&"edit_gravity_left", &"edit_gravity_up", &"edit_gravity_down"]
const BEAT := 0.8        ## the slide is seen before the mascot says what it sees
const LEFT_FOR := 4.0
const UP_FOR := 3.0
const DOWN_FOR := 3.0
const SORRY_HEAL := 1.0  ## HP given back at the clear (M42 E7, D15)


func play(ctx: EventContext) -> void:
	ctx.step(1)   # "Enemies feel slow. One sec, I'll bump their speed." (the posed warning)
	if not ctx.pose_warning(&"edit_gravity_left", &"edit_enemy_speed"):
		return   # a gravity edit is already live (F2): nothing happens
	ctx.step(2)
	if not await ctx.wait(ctx.warn_seconds(&"edit_enemy_speed")):
		return
	# Left has landed this frame (the rule book ticks first).
	ctx.hold_clock(true)
	ctx.step(3)
	ctx.expression(&"surprised")
	ctx.glitch(0.6, 0.5)
	if not await ctx.wait(BEAT):
		return
	ctx.say(&"not_speed", true)
	if not await ctx.wait(LEFT_FOR - BEAT):
		return
	ctx.step(4)
	ctx.say(&"wrong_one")
	ctx.swap_edit(&"edit_gravity_left", &"edit_gravity_up")
	ctx.glitch(0.4)
	if not await ctx.wait(UP_FOR):
		return
	ctx.step(5)
	ctx.say(&"nope")
	ctx.swap_edit(&"edit_gravity_up", &"edit_gravity_down")
	ctx.glitch(0.4)
	if not await ctx.wait(DOWN_FOR):
		return
	ctx.step(6)
	for id in GRAVITY:
		ctx.remove_edit(id)   # nothing for those not live
	ctx.apply_mutation(&"edit_enemy_speed")
	ctx.say(&"other_slider")
	ctx.heal(SORRY_HEAL)   # the AI's apology for the gravity (M42 E7)
	ctx.hold_clock(false)

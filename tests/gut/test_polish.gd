extends GutTest
## M7: generated sounds, particle bursts, the transition glitch. All presentation:
## these tests check they exist, stay bounded, and never get stuck on.

const TUNING_KEYS: Array[String] = ["transition_long", "transition_short"]

var _saved := {}
var _explosions: Array[float] = []


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	RunState.reset(3)
	_explosions.clear()


func after_each() -> void:
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	RunState.reset(0)
	RunState.world = null


func test_every_sound_is_synthesized_short_and_not_silent() -> void:
	var sound := Sound.new()
	add_child_autofree(sound)
	for key in [&"shoot", &"hit", &"kill", &"player_hit", &"jump", &"land", &"dash", &"explosion",
			&"patch_apply", &"patch_revert", &"prompt", &"compile", &"glitch", &"win", &"lose"]:
		assert_true(sound.streams.has(key), "has %s" % key)
		var wav := sound.streams[key] as AudioStreamWAV
		var seconds := wav.data.size() / 2.0 / Sound.RATE
		assert_between(seconds, 0.02, 2.0, "%s length" % key)
		var loud := 0
		for i in range(0, wav.data.size(), 2):
			loud = maxi(loud, absi(wav.data.decode_s16(i)))
		assert_gt(loud, 1000, "%s is audible" % key)
		assert_lt(loud, 32768, "%s does not clip past 16 bits" % key)
	sound.play(&"no_such_sound")   # ignored, no error


func test_particle_bursts_are_capped_and_freed() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var fb := Feedback.new()
	fb.effects_parent = world
	add_child_autofree(fb)
	for i in Feedback.MAX_LIVE_EFFECTS + 25:
		fb.burst(Vector2.ZERO, Color.WHITE, 4, 10.0, 20.0, 0.1, 2.0)
	assert_eq(fb.live_effects(), Feedback.MAX_LIVE_EFFECTS)
	assert_eq(world.get_child_count(), Feedback.MAX_LIVE_EFFECTS)
	await wait_seconds(0.5)
	assert_eq(fb.live_effects(), 0, "every burst finished and was released")


func test_explosions_announce_themselves_for_presentation() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	RunState.world = world
	EventBus.explosion.connect(_on_explosion)
	Explosion.blast(Vector2(10, 10), 75.0, 1.0, 100.0, &"explosion", &"")
	EventBus.explosion.disconnect(_on_explosion)
	assert_eq(_explosions, [75.0] as Array[float])
	await wait_physics_frames(2)   # the ring visual is added deferred; let it land before the world goes


func _on_explosion(_pos: Vector2, radius: float) -> void:
	_explosions.append(radius)


func test_patches_glitch_the_screen_briefly_then_it_clears() -> void:
	var transition := Transition.new()
	add_child_autofree(transition)
	assert_eq(transition.glitch_strength(), 0.0)
	assert_true(transition.request_apply(MutationDB.get_mutation(&"auto_attack")))
	assert_gt(transition.glitch_strength(), 0.3, "small patch: short glitch")
	assert_true(transition.request_ai_add(MutationDB.get_mutation(&"gravity_on"), &"stage"))
	assert_gt(transition.glitch_strength(), 0.8, "gravity change: strong glitch")
	assert_false(get_tree().paused)
	await wait_seconds(0.6)
	assert_eq(transition.glitch_strength(), 0.0, "fades out completely")

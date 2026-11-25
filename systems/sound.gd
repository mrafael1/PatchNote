class_name Sound
extends Node
## Generated placeholder sound effects (PLAN 1, "generated placeholder SFX").
## Every sound is synthesized once at startup into an AudioStreamWAV; there are no
## audio files. Presentation only: it listens to EventBus and never touches gameplay.
## Other systems may also call play() directly (UI, prompt, run loop).

const RATE := 22050
const MAX_VOICES := 4
## Minimum milliseconds between two plays of the same sound, so a burst of hits
## does not turn into noise.
const MIN_GAP_MS := {&"shoot": 45, &"enemy_shoot": 60, &"hit": 35, &"bounce": 40,
		&"kill": 30, &"land": 80, &"explosion": 50}

enum Wave { SQUARE, SAW, SINE, TRIANGLE, NOISE }

var muted := false
## name -> AudioStreamWAV, synthesized when the node enters the tree (about 85 ms).
var streams := {}

var _players := {}
var _last_ms := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1
	AudioBuses.ensure()
	_build_all()
	for key: StringName in streams:
		var p := AudioStreamPlayer.new()
		p.stream = streams[key]
		p.max_polyphony = MAX_VOICES
		p.volume_db = -6.0
		p.bus = AudioBuses.bus_for(key)   # M47.3 (PLAN 1.16): SFX / UI / Voice
		add_child(p)
		_players[key] = p
	EventBus.projectile_fired.connect(_on_projectile_fired)
	EventBus.projectile_hit_wall.connect(_on_hit_wall)
	EventBus.entity_damaged.connect(_on_damaged)
	EventBus.enemy_killed.connect(func(_e: Node, _i: RefCounted) -> void: play(&"kill"))
	EventBus.player_hit.connect(func(_i: RefCounted) -> void: play(&"player_hit"))
	EventBus.player_died.connect(func() -> void: play(&"player_died"))
	EventBus.player_jumped.connect(func() -> void: play(&"jump"))
	EventBus.player_landed.connect(func(_p: Vector2, _s: float) -> void: play(&"land"))
	# Classic plays `dash`; the hook and the teleport have their own sounds (M42.1).
	EventBus.player_dashed.connect(_on_player_dashed)
	EventBus.player_hooked.connect(func(_a: Vector2) -> void: play(&"hook"))
	EventBus.player_hook_missed.connect(func(_f: Vector2, _t: Vector2) -> void: play(&"hook_miss"))
	EventBus.player_teleported.connect(func(_f: Vector2, _t: Vector2) -> void: play(&"teleport"))
	EventBus.player_dash_fizzled.connect(func() -> void: play(&"teleport_fizzle"))
	EventBus.explosion.connect(func(_p: Vector2, _r: float) -> void: play(&"explosion"))
	EventBus.patch_applied.connect(func(_m: Resource) -> void: play(&"patch_apply"))
	EventBus.patch_reverted.connect(func(_m: Resource) -> void: play(&"patch_revert"))
	EventBus.run_ended.connect(_on_run_ended)


func _on_player_dashed() -> void:
	if Unlocks.dash_style() == &"classic":
		play(&"dash")


## A campaign session that simply stops (S0, S1) is no loss: no jingle (M39.2).
func _on_run_ended(outcome: StringName) -> void:
	if outcome == &"stopped":
		return
	play(&"win" if outcome == &"win" else &"lose")


## Plays a sound by name. Unknown names are ignored.
func play(key: StringName, pitch_jitter := 0.04) -> void:
	if muted or not _players.has(key):
		return
	var now := Time.get_ticks_msec()
	var gap: int = MIN_GAP_MS.get(key, 0)
	if gap > 0 and now - int(_last_ms.get(key, -100000)) < gap:
		return
	_last_ms[key] = now
	var p := _players[key] as AudioStreamPlayer
	p.pitch_scale = (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)) * pitch_for(RunState.felt_time_scale())
	p.play()


## SFX pitch follows the time scale (B1), down to an octave and a bit below normal.
static func pitch_for(time_scale: float) -> float:
	return clampf(lerpf(0.45, 1.0, time_scale), 0.45, 1.0)


func _on_projectile_fired(p: Node) -> void:
	play(&"shoot" if p.get(&"faction") == &"player" else &"enemy_shoot")


func _on_hit_wall(p: Node, _pos: Vector2, _normal: Vector2) -> void:
	if is_instance_valid(p) and p.get(&"faction") == &"player":
		play(&"bounce")


func _on_damaged(target: Node, _info: RefCounted) -> void:
	if is_instance_valid(target) and target.is_in_group(&"enemy"):
		play(&"hit")


# --- Synthesis -------------------------------------------------------------

func _build_all() -> void:
	streams[&"shoot"] = _wav(_tone(0.07, 950, 480, Wave.SQUARE, 0.22))
	streams[&"enemy_shoot"] = _wav(_tone(0.10, 320, 190, Wave.SQUARE, 0.14))
	streams[&"hit"] = _wav(_mix(_tone(0.06, 260, 110, Wave.SQUARE, 0.18), _tone(0.05, 0, 0, Wave.NOISE, 0.15)))
	streams[&"kill"] = _wav(_mix(_tone(0.20, 420, 70, Wave.SINE, 0.35), _tone(0.16, 0, 0, Wave.NOISE, 0.22, 2.5)))
	streams[&"player_hit"] = _wav(_mix(_tone(0.28, 230, 55, Wave.SAW, 0.42), _tone(0.12, 0, 0, Wave.NOISE, 0.2)))
	streams[&"player_died"] = _wav(_mix(_tone(0.9, 320, 35, Wave.SAW, 0.45, 1.2), _tone(0.5, 0, 0, Wave.NOISE, 0.25, 1.5)))
	streams[&"jump"] = _wav(_tone(0.11, 280, 720, Wave.SQUARE, 0.16))
	streams[&"land"] = _wav(_mix(_tone(0.09, 0, 0, Wave.NOISE, 0.22, 3.0), _tone(0.08, 140, 60, Wave.SINE, 0.3)))
	streams[&"dash"] = _wav(_tone(0.14, 0, 0, Wave.NOISE, 0.2, 1.5, 0.03))
	streams[&"explosion"] = _wav(_mix(_tone(0.38, 0, 0, Wave.NOISE, 0.4, 2.0), _tone(0.32, 130, 38, Wave.SINE, 0.45)))
	streams[&"bounce"] = _wav(_tone(0.045, 1300, 900, Wave.TRIANGLE, 0.14))
	streams[&"patch_apply"] = _wav(_seq([440, 660, 880, 1320], 0.06, Wave.SQUARE, 0.16))
	streams[&"patch_revert"] = _wav(_seq([1320, 880, 660, 440], 0.06, Wave.SQUARE, 0.16))
	streams[&"prompt"] = _wav(_seq([660, 990], 0.08, Wave.SINE, 0.3))
	streams[&"click"] = _wav(_tone(0.03, 1100, 1000, Wave.SINE, 0.25))
	streams[&"compile"] = _wav(_chatter(0.7, 0.18))
	streams[&"glitch"] = _wav(_mix(_chatter(0.18, 0.14), _tone(0.18, 0, 0, Wave.NOISE, 0.12, 1.0)))
	streams[&"release_candidate"] = _wav(_seq([620, 820, 620, 820, 620, 820], 0.11, Wave.SQUARE, 0.16))
	streams[&"win"] = _wav(_seq([523, 659, 784, 1046, 1046], 0.12, Wave.SQUARE, 0.2))
	streams[&"lose"] = _wav(_seq([392, 330, 262, 196], 0.18, Wave.SAW, 0.22))
	# Appended last: the shared generator is drawn in order, so earlier sounds keep their
	# bytes. A rule edit's warning (PLAN v8 1.4): short and rising.
	streams[&"edit_warn"] = _wav(_seq([440, 587, 784], 0.09, Wave.SQUARE, 0.16))
	# The campaign's other dashes (M42.1), appended after edit_warn for the same reason.
	streams[&"hook"] = _wav(_tone(0.08, 300, 900, Wave.SQUARE, 0.16))
	streams[&"hook_miss"] = _wav(_tone(0.04, 500, 400, Wave.TRIANGLE, 0.14))
	streams[&"teleport"] = _wav(_tone(0.1, 1200, 300, Wave.SINE, 0.22))
	streams[&"teleport_fizzle"] = _wav(_tone(0.05, 200, 160, Wave.SQUARE, 0.12))


## One voice: frequency sweeps exponentially from f0 to f1, the envelope rises over
## `attack` seconds and decays as (1 - t)^curve.
func _tone(duration: float, f0: float, f1: float, wave: Wave, volume: float,
		curve := 1.8, attack := 0.004) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var noise_hold := 0.0
	for i in n:
		var t := float(i) / n
		var freq := f0 * pow(f1 / f0, t) if f0 > 0.0 and f1 > 0.0 else f0
		phase = fmod(phase + freq / RATE, 1.0)
		var s := 0.0
		match wave:
			Wave.SQUARE:
				s = 1.0 if phase < 0.5 else -1.0
			Wave.SAW:
				s = phase * 2.0 - 1.0
			Wave.SINE:
				s = sin(phase * TAU)
			Wave.TRIANGLE:
				s = 1.0 - 4.0 * absf(phase - 0.5)
			Wave.NOISE:
				# Sample-and-hold at ~1/2 rate: a little darker than white noise.
				if i % 2 == 0:
					noise_hold = _rng.randf_range(-1.0, 1.0)
				s = noise_hold
		var env := minf(1.0, float(i) / maxf(1.0, attack * RATE)) * pow(1.0 - t, curve)
		out[i] = s * env * volume
	return out


## Notes one after another, each a short tone.
func _seq(freqs: Array, note: float, wave: Wave, volume: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f: float in freqs:
		out.append_array(_tone(note, f, f, wave, volume, 0.8))
	return out


## Terminal chatter: very short blips at random pitches.
func _chatter(duration: float, volume: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	while out.size() < int(duration * RATE):
		var f := _rng.randf_range(500.0, 2200.0)
		out.append_array(_tone(0.022, f, f, Wave.SQUARE, volume, 0.5))
		var gap := PackedFloat32Array()
		gap.resize(int(_rng.randf_range(0.004, 0.02) * RATE))
		out.append_array(gap)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

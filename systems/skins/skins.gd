class_name Skins
extends RefCounted
## Which code-drawn art the world wears (PLAN 1.7, M48a). `current` null is today's flat
## shapes: every draw hook reads `if Skins.current == null:` and then runs today's code
## unchanged, and Palette answers tier 0. Presentation only: nothing here reads or writes
## the simulation, an RNG, Tuning or WorldRules (a lint).
##
## On: `-- --look=pixel` on the command line, TOGGLE_KEY (F10) live in any scene, or the F2
## console's LOOK row. The choice is a static, so it survives an F5 restart.
##
## Live swap: every node that draws through a skin joins the SKINNED group; use() bumps
## `version`, redraws that group and emits hub.skin_changed (the mascot rebuilds its body).
## A RectVisual re-reads its id when it sees a new version.

const PIXEL_ART := "res://systems/skins/art/grids.gd"
const TOGGLE_KEY := KEY_F10
const ARG_PIXEL := "--look=pixel"
const SKINNED := &"skinned"
## The looks the F2 console offers (M48a: Pixel only; v9.2 parks the others).
const LOOKS: Array[StringName] = [&"off", &"pixel"]
## M48b: `--skins=off` keeps every look off for the process (the S9 hash gate: visuals
## never touch the simulation).
const ARG_OFF := "--skins=off"

## M48b (PLAN 1.7.1): the reveal groups a `skin` cue names. Every enemy id is a group of
## its own; `enemies` arms the per-spawn reveal (SessionRunner) and lights the elite ring;
## `all` reveals everything. `mascot` is a pseudo id (the corner body's style).
const GROUPS := {
	&"player": [&"player", &"aim_arrow", &"aim_arrow_diag"],
	&"shots": [&"shot_dot_player", &"shot_fan_player", &"shot_line_player", &"shot_ball_player",
			&"shot_ring_player", &"shot_burst_player", &"shot_hole_player", &"shot_dot_enemy",
			&"shot_fan_enemy", &"shot_line_enemy", &"shot_ball_enemy", &"shot_ring_enemy",
			&"shot_burst_enemy", &"shot_hole_enemy", &"gem", &"ammo", &"heal", &"battery", &"weapon",
			&"crate", &"blast", &"pop", &"particle", &"orbit_shard", &"shot_prism_player",
			&"shot_misfuse_player", &"shot_bomb_player", &"shot_cluster_player", &"mine", &"mine_armed"],
	&"arena": [&"floor_a", &"floor_b", &"wall", &"standable", &"gate"],
	&"ui": [&"ui_panel", &"ui_panel_lit"],
	&"mascot": [&"mascot"],
	&"enemies": [&"elite"],
}
## The enemy bodies (a `swap` bug dresses them as the player, `flip` turns them over):
## every EnemyDB id (the enemy list lives there only) plus the sprite-only bodies.
static var BODY_IDS: Array[StringName] = _body_ids()
static var ENEMY_IDS: Array[StringName] = _enemy_ids()


static func _body_ids() -> Array[StringName]:
	var out := EnemyDB.all()
	out.append_array([&"splitter_mini", &"hunter"] as Array[StringName])
	return out


static func _enemy_ids() -> Array[StringName]:
	var out := _body_ids()
	out.append(&"elite")
	return out
## A Palette role follows the reveal of this id (a role not listed: only once all is on).
const ROLE_ID := {
	&"bg": &"floor_a", &"grid": &"floor_a", &"wall": &"floor_a", &"standable": &"floor_a",
	&"depth": &"floor_a", &"vignette": &"floor_a", &"gate": &"floor_a",
	&"player": &"player", &"dash": &"player", &"accent": &"player",
	&"player_shot": &"particle", &"enemy_shot": &"particle", &"pickup": &"particle",
	&"gem": &"particle", &"crate": &"particle", &"blast": &"particle", &"dust": &"particle",
	&"hit": &"particle", &"muzzle": &"particle", &"spark": &"particle", &"burn": &"particle",
	&"well_field": &"particle", &"orbit_shard": &"particle",
	&"enemy": &"chaser", &"danger": &"chaser", &"hunter_body": &"hunter", &"elite": &"elite",
	&"lancer_line": &"lancer", &"pip_back": &"ui_panel", &"ui_text": &"ui_panel", &"ui_panel": &"ui_panel",
}
const BUGS: Array[StringName] = [&"swap", &"tiles", &"flip"]
const BUG_MAX := 3.0


## Holds the skin_changed signal (a static class has none; EventBus's signal list is
## pinned by tests).
class Hub:
	extends RefCounted
	signal skin_changed(skin: ArtSkin)

static var current: ArtSkin = null
static var version := 0          ## bumped on every swap (a node can cache per version)
static var hub := Hub.new()
static var bake_msec := -1.0     ## the Pixel bake's wall time (ms), -1 before it
static var _pixel: ArtSkin
static var _args_read := false
## M48b (PLAN 1.7.1): which ids are drawn by the skin. `_all` (the default, and every CLI /
## F10 / console swap) reveals everything; a manual session (S9) starts with nothing and
## reveals per id. The state is presentation only: nodes read it at draw time.
static var revealed := {}        ## id -> true
static var _all := true
static var _morph := {}          ## id -> [t0, length] in RunState.real_time() seconds
static var _glitch_kind: StringName = &""
static var _glitch_until := -1.0
static var disabled := false     ## `--skins=off`: no look for the whole process
static var _by_session := false  ## the current skin was put on by a session (apply_session)


## The Pixel skin, baked on first use.
static func pixel() -> ArtSkin:
	if _pixel == null:
		var t0 := Time.get_ticks_usec()
		_pixel = ArtSkin.bake(load(PIXEL_ART) as Script, &"pixel")
		bake_msec = (Time.get_ticks_usec() - t0) / 1000.0
		for p in _pixel.problems:
			push_warning("pixel art: " + p)
	return _pixel


## Swaps the skin: every SKINNED node redraws (and so re-reads its id), hub.skin_changed
## fires, and `root`, when given, redraws every canvas item under it too.
static func use(skin: ArtSkin, root: Node = null) -> void:
	if disabled:
		skin = null
	_by_session = false
	var was_all := _all and _morph.is_empty() and _glitch_kind == &""
	_all = true
	revealed.clear()
	_morph.clear()
	_glitch_kind = &""
	if skin == current:
		if not was_all:
			_redraw(root, true)
		return
	_swap(skin, root)


static func _swap(skin: ArtSkin, root: Node) -> void:
	current = skin
	version += 1
	var tree := Engine.get_main_loop() as SceneTree
	apply_motion(tree)
	if tree != null:
		tree.call_group(SKINNED, &"queue_redraw")
	if root != null:
		root.propagate_call(&"queue_redraw")
	hub.skin_changed.emit(skin)


## The look by name (`off` / `pixel`), for the console and the command line.
static func use_named(look: StringName, root: Node = null) -> void:
	use(pixel() if look == &"pixel" else null, root)


static func current_name() -> StringName:
	return &"off" if current == null else current.name


## M48a: Pixel's UI panel on a Button (normal; hover, focus and pressed lit) or on any
## Control's `panel` style. No look: nothing changes (today's theme).
static func dress_button(b: Button) -> void:
	if not is_on(&"ui_panel") or current.ui_panel() == null:
		return
	var plain := current.ui_panel(false)
	var lit := current.ui_panel(true)
	b.add_theme_stylebox_override(&"normal", plain)
	b.add_theme_stylebox_override(&"disabled", plain)
	for state: StringName in [&"hover", &"pressed", &"focus", &"hover_pressed"]:
		b.add_theme_stylebox_override(state, lit)


## A live look swap on a button dressed before it: drops the old look's panel (today's
## theme shows again), then dresses it in the current look, if any.
static func redress_button(b: Button) -> void:
	for state: StringName in [&"normal", &"disabled", &"hover", &"pressed", &"focus", &"hover_pressed"]:
		b.remove_theme_stylebox_override(state)
	dress_button(b)


static func dress_panel(c: Control, style := &"panel") -> void:
	if not is_on(&"ui_panel") or current.ui_panel() == null:
		return
	c.add_theme_stylebox_override(style, current.ui_panel(false))


## How the look moves on screen (owner 2026-11-25: "when moving the player sprite is
## 'ghosting' a bit"). Physics ticks at 60 Hz but a 240 Hz screen draws 4 frames a tick while
## the camera glides every frame: a body jumps a tick's distance, then slides back for three
## frames (2 to 4 px back and forth, a doubled image on detailed art). The Pixel look turns on
## the engine's physics interpolation (bodies drawn between their last two ticks: rendering
## only, the simulation never reads it) and whole-pixel canvas item origins (the snap runs
## after the interpolation, so nearest-filtered art keeps the same pixel columns frame to
## frame at any window scale). No look: the project's own settings, today's picture.
static func apply_motion(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	var on := current != null
	var interp := on or bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	if tree.physics_interpolation != interp:
		tree.physics_interpolation = interp
		if interp:
			tree.root.propagate_call(&"reset_physics_interpolation")   # no slide from stale ticks


static func toggle(root: Node = null) -> void:
	if disabled:
		return
	use(null if current != null else pixel(), root)


## Reads `--look=pixel` and `--skins=off` once per process (main calls it at every boot).
static func read_args(args: PackedStringArray) -> void:
	if _args_read:
		return
	_args_read = true
	if ARG_OFF in args:
		disabled = true
		print("[skins] off for this process (--skins=off)")
		return
	if ARG_PIXEL in args:
		use(pixel())
		print("[skins] look=pixel, %d sprites baked in %.1f ms" % [current.ids().size(), bake_msec])


## True for a key event that toggles the look.
static func is_toggle(event: InputEvent) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and \
			(k.physical_keycode == TOGGLE_KEY or k.keycode == TOGGLE_KEY)


## The sprite id a RectVisual stands for, read from the node that owns it; &"" draws the
## flat rect (the jump shadow, a dash ghost). The player's aim tip is the aim_arrow.
static func id_for(visual: Node) -> StringName:
	var own: Variant = visual.get(&"skin_id")
	if own is StringName and own != &"":
		return own
	var host := visual.get_parent()
	if host == null:
		return &""
	if host.get(&"shard_count") != null:
		return &"orbit_shard"
	var owner_body := host.get_parent()
	if visual.name == &"Tip" and host.name == &"Aim" and owner_body != null and owner_body.is_in_group(&"player"):
		return &"aim_arrow"
	if visual.name != &"Visual":
		return &""
	if host.is_in_group(&"player"):
		return &"player"
	if host.get(&"kind") == &"hunter":
		return &"hunter"
	var faction: Variant = host.get(&"faction")
	if faction is StringName and host.get(&"weapon_id") != null:
		return shot_id(host.get(&"weapon_id"), faction)
	var path := host.scene_file_path
	if path.begins_with("res://entities/enemy_"):
		if host.get(&"variant") == &"splitter":
			return &"splitter"
		var base := StringName(path.get_file().get_basename().trim_prefix("enemy_"))
		if base == &"chaser" and int(host.get(&"generation") if host.get(&"generation") != null else 0) >= 1:
			return &"splitter_mini"
		return base
	return &""


## A projectile's sprite: its weapon's icon x its faction (enemy shots carry no weapon: dot).
static func shot_id(weapon_id: Variant, faction: StringName) -> StringName:
	var icon := "dot"
	if weapon_id is StringName and weapon_id != &"" and WeaponDB.has(weapon_id):
		icon = String(WeaponDB.get_weapon(weapon_id).icon)
	var side := "player" if faction == &"player" else "enemy"
	var id := StringName("shot_%s_%s" % [icon, side])
	if current != null and not current.has(id):
		id = StringName("shot_dot_%s" % side)
	return id


## Bodies stay upright whatever their node's rotation (the shooter's 45 deg diamond, the
## spinning shards: the art already draws them); shots turn with their flight.
static func upright(id: StringName) -> bool:
	return not String(id).begins_with("shot_")


## The floor variant of a tile: a pure hash of its cell (no RNG).
static func cell_hash(cx: int, cy: int) -> int:
	return absi((cx * 73856093) ^ (cy * 19349663)) % 7


# --- M48b (PLAN 1.7.1): the transformation ---------------------------------------------

## True when `id` is drawn by the current skin (a look is on and the id is revealed). Every
## hook's tier-0 path runs when this is false.
static func is_on(id: StringName) -> bool:
	return current != null and (_all or revealed.has(id))


## The skin when `id` is on, else null (a hook's one-line test).
static func on(id: StringName) -> ArtSkin:
	return current if is_on(id) else null


## True when Palette should answer the look's colour for `role` (ROLE_ID's id revealed; a
## role it does not list follows `all`).
static func role_on(role: StringName) -> bool:
	if current == null:
		return false
	if _all:
		return true
	var id: StringName = ROLE_ID.get(role, &"")
	return id != &"" and revealed.has(id)


## True while every id is revealed (no manual reveal pending).
static func all_on() -> bool:
	return current != null and _all


## The ids a `skin` cue target names: a group, an enemy id or a sprite id of a group;
## [] for `all` and for an unknown name.
static func target_ids(target: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if GROUPS.has(target):
		for id: StringName in GROUPS[target]:
			out.append(id)
	elif target in ENEMY_IDS:
		out.append(target)
	else:
		for g: StringName in GROUPS:
			if target in GROUPS[g]:
				out.append(target)
				break
	return out


## Whether a `skin` cue may name `target` (`all` included).
static func is_target(target: StringName) -> bool:
	return target == &"all" or not target_ids(target).is_empty()


## Reveals a group, an id, or an array of ids; morph_s > 0 plays SkinMorph over that long
## from `now` (RunState.real_time() when negative). Ids already revealed are left alone.
static func reveal(target: Variant, morph_s := 0.0, now := -1.0) -> void:
	if target is StringName and target == &"all":
		reveal_all()
		return
	if _all:
		return   # M48b review: every id is already drawn (a CLI / F10 swap, `skin all`): no re-morph
	var ids: Array[StringName] = []
	if target is Array:
		for t: Variant in target:
			ids.append_array(target_ids(StringName(t)))
	else:
		ids = target_ids(StringName(target))
	if now < 0.0:
		now = RunState.real_time()
	var fresh := false
	var dressed := false
	for id in ids:
		if revealed.has(id):
			continue
		revealed[id] = true
		fresh = true
		dressed = dressed or id in [&"mascot", &"ui_panel", &"ui_panel_lit"]
		if morph_s > 0.0:
			_morph[id] = [now, morph_s]
	if fresh and current != null:
		_redraw(null, dressed)


## Every id on, no morph or bug left (the end of S9, a death, every CLI / F10 swap).
static func reveal_all() -> void:
	if _all and _morph.is_empty() and _glitch_kind == &"":
		return
	var dressed := not _all
	_all = true
	revealed.clear()
	_morph.clear()
	_glitch_kind = &""
	if current != null:
		_redraw(null, dressed)


## A fresh reveal state: nothing revealed (manual) or everything (not).
static func reset_reveal(manual: bool) -> void:
	_all = not manual
	revealed.clear()
	_morph.clear()
	_glitch_kind = &""
	_glitch_until = -1.0
	if current != null:
		_redraw(null, true)


## 0..1 through id's morph at `now`, or -1 when it has none (not started by a reveal, or
## over: then the plain sprite draws).
static func morph_of(id: StringName, now := -1.0) -> float:
	if not _morph.has(id):
		return -1.0
	if now < 0.0:
		now = RunState.real_time()
	var m: Array = _morph[id]
	var u := (now - float(m[0])) / maxf(float(m[1]), 0.001)
	if u >= 1.0:
		return -1.0
	return clampf(u, 0.0, 1.0)


## True while some id is mid-morph (a node keeps redrawing).
static func morphing(id: StringName, now := -1.0) -> bool:
	return morph_of(id, now) >= 0.0


## A scripted visual bug (PLAN 1.7.1): `swap` dresses every enemy body as the player,
## `tiles` swaps floor and wall tiles, `flip` turns enemy sprites upside down. A draw-time
## remap for `seconds` (at most BUG_MAX), so it reverts exactly. No look: nothing.
static func glitch(kind: StringName, seconds: float, now := -1.0) -> void:
	if not kind in BUGS or current == null:
		return
	if now < 0.0:
		now = RunState.real_time()
	_glitch_kind = kind
	_glitch_until = now + minf(seconds, BUG_MAX)
	_redraw(null, false)


## The live bug at `now`, &"" for none.
static func glitch_kind(now := -1.0) -> StringName:
	if _glitch_kind == &"":
		return &""
	if now < 0.0:
		now = RunState.real_time()
	return _glitch_kind if now < _glitch_until else &""


## The sprite `id` draws as under the live bug (swap: an enemy body draws the player).
static func drawn_id(id: StringName, now := -1.0) -> StringName:
	if id in BODY_IDS and glitch_kind(now) == &"swap":
		return &"player"
	return id


## True when `id`'s sprite is drawn upside down (the flip bug, enemy bodies only).
static func flipped(id: StringName, now := -1.0) -> bool:
	return id in BODY_IDS and glitch_kind(now) == &"flip"


## M48b: a session's skin (SessionDef.skin, look_reveal), at every boot after read_args.
## `pixel`: the look on, nothing revealed when manual (S9), everything when not. `""`: a
## skin a session put on comes off; a CLI / F10 / console choice stays. `--skins=off`:
## nothing. A retry of S9 replays the transformation (the state is reset here).
static func apply_session(session: Resource) -> void:
	if disabled:
		return
	var want: StringName = StringName(String(session.get(&"skin"))) if session != null and session.get(&"skin") != null else &""
	if want == &"pixel":
		var manual: bool = session.get(&"look_reveal") == &"manual"
		if current != pixel():
			_swap(pixel(), null)
			_by_session = true   # M48b review: a CLI / F10 Pixel stays the player's, not the session's
		reset_reveal(manual)
	elif _by_session:
		_by_session = false
		_all = true
		revealed.clear()
		_morph.clear()
		_glitch_kind = &""
		_swap(null, null)
	else:
		reveal_all()   # a kept CLI / F10 look: whole again after a manual session


## Bumps `version` (a RectVisual re-reads its id), redraws the SKINNED group (and `root`'s
## tree), and when the mascot or the UI changed emits hub.skin_changed (they rebuild).
static func _redraw(root: Node, dressed: bool) -> void:
	version += 1
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.call_group(SKINNED, &"queue_redraw")
	if root != null:
		root.propagate_call(&"queue_redraw")
	if dressed:
		hub.skin_changed.emit(current)

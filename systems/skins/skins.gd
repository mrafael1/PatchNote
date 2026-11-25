class_name Skins
extends RefCounted
## Which code-drawn art the world wears (PLAN 1.7; this is the quick Pixel preview, not the
## full M48a). `current` null is today's flat shapes: every draw hook reads
## `if Skins.current == null:` and then runs today's code unchanged. Presentation only:
## nothing here reads or writes the simulation, an RNG, Tuning or WorldRules.
##
## On: `-- --look=pixel` on the command line, or TOGGLE_KEY (F10; F2 is the debug console)
## live in any scene. The choice is a static, so it survives an F5 restart.

const PIXEL_ART := "res://systems/skins/art/grids.gd"
const TOGGLE_KEY := KEY_F10
const ARG_PIXEL := "--look=pixel"

static var current: ArtSkin = null
static var version := 0          ## bumped on every swap (a node can cache per version)
static var _pixel: ArtSkin
static var _args_read := false


## The Pixel skin, baked on first use.
static func pixel() -> ArtSkin:
	if _pixel == null:
		_pixel = ArtSkin.bake(load(PIXEL_ART) as Script, &"pixel")
		for p in _pixel.problems:
			push_warning("pixel art: " + p)
	return _pixel


## Swaps the skin and redraws every canvas item under `root` (null: no redraw).
static func use(skin: ArtSkin, root: Node = null) -> void:
	if skin == current:
		return
	current = skin
	version += 1
	apply_motion(Engine.get_main_loop() as SceneTree)
	if root != null:
		root.propagate_call(&"queue_redraw")


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
	use(null if current != null else pixel(), root)


## Reads `--look=pixel` once per process (main calls it at every boot).
static func read_args(args: PackedStringArray) -> void:
	if _args_read:
		return
	_args_read = true
	if ARG_PIXEL in args:
		use(pixel())
		print("[skins] look=pixel (preview), %d sprites baked" % current.ids().size())


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

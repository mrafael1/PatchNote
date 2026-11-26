class_name RailState
extends RefCounted
## M48.5a: one read of everything the rail's modules show, from the live game (presentation
## state only: no RNG, no writes, no Tuning edits). The rail reads it every frame and redraws a
## module only when its part changed. Every module exists only once its basic or path is live
## ("nothing exists by default"): a missing one is `on: false`.
##
## The dash fill: Dasher keeps its cooldown private and its total depends on the move (dash,
## grapple, grapple miss, teleport), so the rail tracks the peak of `_cooldown_left` since it
## last read zero (`peak`, kept by the caller) and fills by left / peak.

## The reading: {version, kills, hp, dash, path} (each a Dictionary).
static func read(game: Node, peak: Dictionary) -> Dictionary:
	var out := {"version": SaveGame.version().label(), "stage": 0, "title": ""}
	var s := RunState.session
	if s != null:
		out.stage = s.stage
		out.title = s.title
	var player: Node = game.get(&"player") if game != null else null
	if not is_instance_valid(player):
		player = null
	out.kills = {"on": Unlocks.has_basic(&"enemies"), "n": RunState.kills}
	out.hp = _hp(game, player)
	out.dash = _dash(player, peak)
	out.path = _path(game)
	return out


static func _hp(game: Node, player: Node) -> Dictionary:
	var d := {"on": Unlocks.has_basic(&"health"), "hp": 0, "max": 0, "hits": 0}
	var health := Component.find(player, Health) as Health if player != null else null
	if health == null:
		d.on = false
		return d
	d.hp = maxi(0, ceili(health.hp() - 0.001))
	d.max = maxi(1, ceili(health.max_hp() - 0.001))
	var runner: Node = game.get(&"session_runner") if game != null else null
	if is_instance_valid(runner):
		d.hits = int(runner.get(&"hits"))
	return d


static func _dash(player: Node, peak: Dictionary) -> Dictionary:
	var d := {"on": false, "label": "dash", "style": "classic", "ready": true, "frac": 1.0,
			"left": 0.0, "total": 0.0, "key": InputSetup.expand_keys("{key:dash}")}
	if player == null or not Unlocks.has_basic(&"dash") or bool(player.get(&"dash_locked")):
		return d
	var dasher := Component.find(player, Dasher) as Dasher
	if dasher == null:
		return d
	d.on = true
	d.label = dasher.label()
	d.style = String(dasher.style)
	var left := maxf(0.0, float(dasher.get(&"_cooldown_left")))
	var top := float(peak.get("top", 0.0))
	if left <= 0.0:
		top = 0.0
	elif left > top:
		top = left
	peak["top"] = top
	if top > 0.0:
		peak["last"] = top
	d.ready = dasher.is_ready()
	d.left = left
	d.total = float(peak.get("last", 0.0))
	d.frac = 1.0 if top <= 0.0 else clampf(1.0 - left / top, 0.0, 1.0)
	return d


static func _path(game: Node) -> Dictionary:
	var runner: Node = game.get(&"path_runner") if game != null else null
	var d := {"kind": &"", "id": &""}
	if not is_instance_valid(runner) or runner.get(&"def") == null:
		return d
	var def: PathDef = runner.get(&"def")
	d.id = runner.get(&"path_id")
	var lo: Loadout = runner.call(&"loadout")
	if lo == null:
		return d
	match def.growth:
		&"cards":
			d.kind = &"hand"
			d.hand = _hand(runner, lo)
			d.pack = _pack(runner, def)
		&"levelups":
			d.kind = &"items"
			d.items = _items(runner, lo, def)
		&"pickups":
			d.kind = &"ammo"
			d.ammo = _ammo(runner, lo)
	return d


static func _hand(runner: Node, lo: Loadout) -> Dictionary:
	var cards: Array[Dictionary] = []
	for i in lo.slots.size():
		var w := lo.slots[i]
		var parents: Array[String] = []
		for p in w.def.parents:
			var pd := WeaponDB.get_weapon(p)
			parents.append(pd.title if pd != null else String(p))
		cards.append({"title": w.def.title, "rank": w.rank, "active": i == lo.active, "deep": w.deep(),
				"levels": WeaponCurve.levels_of(w.def, w.rank) if w.deep() else ([] as Array[int]),
				"fused": w.def.is_fusion(), "parents": parents, "icon": w.def.icon,
				"key": InputSetup.expand_keys("{key:weapon_%d}" % (i + 1))})
	var link := int(runner.call(&"link_state")) if runner.has_method(&"link_state") else 0
	var widget: Node = runner.call(&"widget")
	var misfuse := is_instance_valid(widget) and widget.has_method(&"misfusing") and bool(widget.call(&"misfusing"))
	var d := {"cards": cards, "max": maxi(lo.max_slots, 1), "link": link, "misfuse": misfuse,
			"misfuse_title": String(widget.call(&"misfuse_title")) if misfuse else "", "recipe": "", "pair": ""}
	if link > 0:
		var pair := BoosterPack.recipe_pair(lo)
		if pair.size() == 3:
			var f := WeaponDB.get_weapon(pair[2])
			d.recipe = f.title if f != null else String(pair[2])
			d.pair = "%s + %s" % [lo.slots[0].def.title.to_lower(), lo.slots[1].def.title.to_lower()]
	return d


static func _pack(runner: Node, def: PathDef) -> Dictionary:
	var meter: RefCounted = runner.call(&"meter")
	var every := maxi(1, def.pack_every)
	var d := {"on": def.pack_every > 0 and meter != null and meter.has_method(&"kills_left"),
			"x": 0, "every": every, "left": -1, "next": 1}
	if not d.on:
		return d
	var kills := int(meter.get(&"kills"))
	var cards := int(meter.get(&"cards"))
	d.x = clampi(kills - cards * every, 0, every)
	d.left = int(meter.call(&"kills_left"))
	d.next = cards + 1
	return d


static func _items(runner: Node, lo: Loadout, def: PathDef) -> Dictionary:
	var cap := lo.rank_cap if lo.rank_cap > 0 else Loadout.MAX_RANK
	var weapons: Array[Dictionary] = []
	var passives: Array[Dictionary] = []
	var passive_slots := def.max_passives
	if def.shared_slots:
		# M50.4a (Auto depth T7): every weapon (passive-mode ones too) in the shared weapon
		# slots; the passive slots are the items' (M50.4b).
		for w in lo.weapons():
			weapons.append({"title": w.def.title, "rank": w.rank, "icon": w.def.icon, "evo": false})
		for it in lo.items:   # M50.4b: the passive items, rank = their level
			passives.append({"title": it.def.title, "rank": it.level, "icon": it.def.icon})
		passive_slots = def.max_items
	else:
		for w in lo.slots:
			weapons.append({"title": w.def.title, "rank": w.rank, "icon": w.def.icon})
		for w in lo.passives:
			passives.append({"title": w.def.title, "rank": w.rank, "icon": w.def.icon})
	var meter: RefCounted = runner.call(&"meter")
	return {"weapons": weapons, "passives": passives, "slots": maxi(1, def.max_slots),
			"passive_slots": passive_slots, "cap": cap,
			"level": int(meter.get(&"level")) if meter != null else 1,
			"xp": float(meter.call(&"progress")) if meter != null and meter.has_method(&"progress") else 0.0}


static func _ammo(runner: Node, lo: Loadout) -> Dictionary:
	var w := lo.current()
	var side := lo.sidearm.def.title if lo.sidearm != null else "Pistol"
	var d := {"title": "", "rank": 1, "cap": Loadout.MAX_RANK, "left": -1, "total": -1, "icon": &"",
			"sidearm": side, "on_sidearm": lo.on_sidearm(), "crates": 0}
	if runner.has_method(&"crates_taken"):
		d.crates = int(runner.call(&"crates_taken"))
	if w == null:
		return d
	d.title = w.label()
	d.rank = w.rank
	d.icon = w.def.icon
	if w.def.ammo > 0 and not lo.on_sidearm():
		d.left = w.ammo_left
		d.total = w.def.ammo
	return d

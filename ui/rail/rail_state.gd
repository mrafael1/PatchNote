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
			"x": 0, "every": every, "left": -1, "next": 1, "stack": 0, "key": ""}
	if not d.on:
		return d
	# M50.6: the packs waiting on the stack and the key that opens the top one.
	d.stack = int(runner.call(&"pack_stack")) if runner.has_method(&"pack_stack") else 0
	d.key = PathRunner.open_key() if Settings.key_hints() else ""
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
			weapons.append({"title": w.def.title, "rank": w.rank, "icon": w.def.icon, "evo": w.def.is_evolution()})
		for it in lo.items:   # M50.4b: the passive items, rank = their level
			passives.append({"title": it.def.title, "rank": it.level, "icon": it.def.icon})
		passive_slots = def.max_items
	else:
		for w in lo.slots:
			weapons.append({"title": w.def.title, "rank": w.rank, "icon": w.def.icon})
		for w in lo.passives:
			passives.append({"title": w.def.title, "rank": w.rank, "icon": w.def.icon})
	var meter: RefCounted = runner.call(&"meter")
	# M50.4c1: the bottom line's evolve hint ("" none: the rail's own "next level" line).
	var hint := String(runner.call(&"evolve_hint")) if runner.has_method(&"evolve_hint") else ""
	var d := {"weapons": weapons, "passives": passives, "slots": maxi(1, def.max_slots),
			"passive_slots": passive_slots, "cap": cap, "hint": hint,
			"level": int(meter.get(&"level")) if meter != null else 1,
			"xp": float(meter.call(&"progress")) if meter != null and meter.has_method(&"progress") else 0.0}
	if def.shared_slots:
		_preview(d, runner, lo)   # M50.4f: the open level-up's focused choice
	return d



## M50.4f: Auto's ITEMS for `runner` ({} off a levelups path): the flat look's slot bar reads it.
static func items_for(runner: Node) -> Dictionary:
	if runner == null or not is_instance_valid(runner) or runner.get(&"def") == null:
		return {}
	var def: PathDef = runner.get(&"def")
	var lo: Loadout = runner.call(&"loadout")
	if lo == null or def.growth != &"levelups":
		return {}
	return _items(runner, lo, def)


## M50.4f (the sheet's slot bar, "the slot that changes lifts"): while the dressed level-up is
## open, `picking` (the bar full, "UP!"), the per-key `legend`, and on the slot the focused
## choice changes `lift` and `next` (its next pip), or the free well (`new_slot`, `new_passive`);
## a focused EVOLVE rings its base weapon (`evo_ring`) and ticks its catalyst (`cat_tick`).
static func _preview(d: Dictionary, runner: Node, lo: Loadout) -> void:
	var panel: Variant = runner.get(&"panel")
	if panel == null or not is_instance_valid(panel) or not (panel as Object).has_method(&"preview"):
		return
	var pv: Dictionary = (panel as Object).call(&"preview")
	if pv.is_empty():
		return
	d.picking = true
	var parts: Array[String] = []
	var choices: Array = pv.choices
	var keys: Array = pv.keys
	for i in choices.size():
		var c: Dictionary = choices[i]
		var key := String(keys[i]) if i < keys.size() else str(i + 1)
		var what := ""
		match String(c.kind):
			"evolve":
				var into := WeaponDB.get_weapon(c.into)
				what = "%s -> %s" % [String(c.id), (into.title if into != null else String(c.into)).to_lower()]
			"new_weapon", "new_item":
				what = "%s new" % String(c.id)
			"filler":
				what = String(c.id)
			_:
				what = "%s %d > %d" % [String(c.id), int(c.from), int(c.to)]
		parts.append("[%s] %s" % [key, what])
	d.legend = " . ".join(parts)
	var focus := int(pv.focus)
	if focus < 0 or focus >= choices.size():
		return
	var f: Dictionary = choices[focus]
	var ws := lo.weapons()
	var wd: Array = d.weapons
	var pd: Array = d.passives
	match String(f.kind):
		"weapon":
			for i in mini(ws.size(), wd.size()):
				if ws[i].def.id == f.id:
					wd[i].lift = true
					wd[i].next = true
		"item":
			for i in mini(lo.items.size(), pd.size()):
				if lo.items[i].def.id == f.id:
					pd[i].lift = true
					pd[i].next = true
		"new_weapon":
			d.new_slot = wd.size()
		"new_item":
			d.new_passive = pd.size()
		"evolve":
			for i in mini(ws.size(), wd.size()):
				if ws[i].def.id == f.id:
					wd[i].evo_ring = true
			for i in mini(lo.items.size(), pd.size()):
				if lo.items[i].def.id == f.catalyst:
					pd[i].cat_tick = true

static func _ammo(runner: Node, lo: Loadout) -> Dictionary:
	var w := lo.current()
	var side := lo.sidearm.def.title if lo.sidearm != null else "Pistol"
	var d := {"title": "", "rank": 1, "cap": Loadout.MAX_RANK, "left": -1, "total": -1, "icon": &"",
			"sidearm": side, "on_sidearm": lo.on_sidearm(), "crates": 0, "magazine": 0, "mag": 0, "reload": -1.0}
	if runner.has_method(&"crates_taken"):
		d.crates = int(runner.call(&"crates_taken"))
	if w == null:
		return d
	d.title = w.label()
	d.rank = w.rank
	d.icon = w.def.icon
	# M48.5b (M47.6d1): the revolver's load ("4/6") and its reload's fill (-1: not reloading).
	d.magazine = w.def.magazine if w.has_magazine() else 0
	d.mag = w.mag_left if w.has_magazine() else 0
	d.reload = -1.0
	if w.reloading():
		d.reload = clampf(1.0 - w.reload_left / maxf(0.001, float(w.value(&"reload_s"))), 0.0, 1.0)
	if w.def.ammo > 0 and not lo.on_sidearm():
		d.left = w.ammo_left
		d.total = w.def.ammo
	return d

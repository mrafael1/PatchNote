class_name Fingerprint
extends RefCounted
## The play fingerprint (PLAN v9 1.15, M46): how a session was played, per path, report-only
## (it informs, it never blocks). Shared path code (not path-only), owned by PathRunner and
## sampled on its physics tick; no RNG, nothing saved. For bots these values are mostly the
## policy's own constants: a regression signal between milestones, never an R1 measure.
##
## menu_s is timed in wall time (the tree is paused while a pick panel is open, so no physics
## tick runs then): from the offer to the pick, through `clock` (msec; tests pass their own).

const DIST_EVERY := 6   ## mean_enemy_dist: one sample every 6 ticks

var clock := Callable()   ## () -> int msec; Time.get_ticks_msec by default
var ticks := 0
var fire_ticks := 0
var travel_px := 0.0
var dist_sum := 0.0
var dist_n := 0
var menu_ms := 0
## M47 (Survival, D19): ticks on Survival, and those with only the sidearm in hand while
## `pickups` is live (ammo_dry_share; ammo_dry_s in seconds).
var survival_ticks := 0
var dry_ticks := 0

var _last := Vector2.ZERO
var _has_last := false
var _menu_from := -1


## One physics tick of `player` (its input's fire held, its travel, the nearest enemy).
func sample(player: Node2D) -> void:
	if player == null:
		return
	ticks += 1
	var input: PlayerInput = player.get(&"input")
	if input != null and input.fire:
		fire_ticks += 1
	var at := player.global_position
	if _has_last:
		travel_px += at.distance_to(_last)
	_last = at
	_has_last = true
	if ticks % DIST_EVERY == 0:
		var best := INF
		for e in player.get_tree().get_nodes_in_group(&"enemy"):
			var n := e as Node2D
			if n != null and not n.is_queued_for_deletion():
				best = minf(best, at.distance_to(n.global_position))
		if best < INF:
			dist_sum += best / Tuning.TILE
			dist_n += 1


## One Survival tick (PathRunner): `dry` = on the sidearm with `pickups` live.
func survival_tick(dry: bool) -> void:
	survival_ticks += 1
	if dry:
		dry_ticks += 1


## A pick panel opened / closed (menu_s).
func menu_open() -> void:
	if _menu_from < 0:
		_menu_from = _now()


func menu_close() -> void:
	if _menu_from >= 0:
		menu_ms += maxi(0, _now() - _menu_from)
		_menu_from = -1


## The 8 values of 1.15. `picks`, `switches`, `pickups`: counts over the sampled time.
func values(picks: int, switches: int, pickups: int) -> Dictionary:
	var seconds := ticks / float(Engine.physics_ticks_per_second)
	var minutes := maxf(seconds / 60.0, 1.0 / 60.0)
	var out := {
		"fire_share": float(fire_ticks) / maxf(1.0, float(ticks)),
		"menu_s": menu_ms / 1000.0,
		"picks_per_min": picks / minutes,
		"switches_per_min": switches / minutes,
		"pickups_per_min": pickups / minutes,
		"travel_tps": travel_px / Tuning.TILE / maxf(seconds, 1.0 / 60.0),
		"mean_enemy_dist": dist_sum / dist_n if dist_n > 0 else 0.0,
		"ammo_dry_share": float(dry_ticks) / survival_ticks if survival_ticks > 0 else 0.0,
	}
	if survival_ticks > 0:
		out["ammo_dry_s"] = dry_ticks / float(Engine.physics_ticks_per_second)   # 1.15's Survival key
	return out


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()

class_name QuickDraw
extends RefCounted
# path:arsenal
## Arsenal's quick-draw (PLAN v9 1.5, M46): the first shot after a real switch of the active
## card does PathDef.quick_draw_mult damage (x2), so switching is a skill. Live only once the
## `quick_draw` basic is (PathRunner sets Loadout.quick_draw_mult); armed by Loadout's own
## switch / select_slot, spent by the next shot of any card, no timeout (D4). The multiplier
## goes into Shooter.fire's pellet params, so traits and projectile_fired see it. No RNG.


## The damage multiplier for `loadout`'s next shot (1.0 = none). Pure: a shot refused at the
## projectile cap asks again next tick, so the event is logged by spent(), not here.
static func mult(loadout: Loadout) -> float:
	if loadout == null or not loadout.drawn() or loadout.quick_draw_mult <= 1.0:
		return 1.0
	return loadout.quick_draw_mult


## A shot with multiplier `m` has spawned: logs `quick_draw` once when it was boosted.
static func spent(loadout: Loadout, m: float) -> void:
	if m <= 1.0:
		return
	var w := loadout.current()
	RunState.log_event(&"quick_draw", {"weapon": String(w.def.id) if w != null else ""})

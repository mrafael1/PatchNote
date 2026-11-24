extends Node
## Autoload "EventBus". Signals only, no logic (PLAN 2.2).
## Hit signals fire on every contact, before the despawn decision.

@warning_ignore_start("unused_signal")
signal entity_spawned(entity: Node)
signal entity_damaged(target: Node, info: RefCounted)
signal enemy_killed(enemy: Node, info: RefCounted)
signal player_hit(info: RefCounted)
signal player_died
signal projectile_fired(projectile: Node)
signal projectile_hit(projectile: Node, target: Node, pos: Vector2)
signal projectile_hit_wall(projectile: Node, pos: Vector2, normal: Vector2)
signal player_jumped
signal player_landed(pos: Vector2, impact_speed: float)
signal player_dashed
## The campaign's other dashes (M42.1, fork_dash): the hook caught a wall at anchor, or
## flew out and caught nothing; a teleport blinked; a teleport found no free spot.
signal player_hooked(anchor: Vector2)
signal player_hook_missed(from: Vector2, to: Vector2)
signal player_teleported(from: Vector2, to: Vector2)
signal player_dash_fizzled
## Campaign (PLAN v8 M39.2): a basic was added during the session ("add health").
signal basic_added(id: StringName)
## Something tried to hurt the player before the session has `health`: nothing happens.
signal player_touched
signal turn_started(number: int)   ## B2: the player's action is fixed (TurnClock.player_tile); enemies plan
signal turn_ended(number: int)     ## B2: the turn's time is over; hits resolve on tiles
signal explosion(pos: Vector2, radius: float)   ## presentation hook; carries no damage
signal weapon_changed(id: StringName, rank: int)   ## PLAN v9 1.6 (M44): given, ranked up, switched to
signal patch_applied(mutation: Resource)
signal patch_reverted(mutation: Resource)
signal big_swapped(old: Resource, new: Resource, dropped: Array)   ## old may be null
signal ai_patch_added(mutation: Resource, owner_id: StringName)     ## &"stage" or &"boss"
signal ai_patch_removed(mutation: Resource, reason: StringName)     ## &"rollback", &"expired", &"dropped", &"console" (F2)
signal rules_changed(rules: Resource)
signal milestone_reached(id: int)
signal run_started(run_seed: int)
signal run_ended(outcome: StringName)
signal stage_ended(index: int)   ## the shell relays the genre's stage end (PLAN v6 4)
@warning_ignore_restore("unused_signal")

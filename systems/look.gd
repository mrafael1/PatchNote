class_name Look
extends RefCounted
## The active look (PLAN v5 1.7). Static state, like Telemetry and SaveGame. The game
## scene picks it from Unlocks.look() when it starts; until then, and when the preset
## file is missing, it is tier 1 `punchy` (today's feel, what unlock_all shows).
## Presentation only: Feedback, CameraRig, the projectile and the screen overlay read
## it, no gameplay value does (a test greps for that).

const DIR := "res://systems/looks/"
const TIER_0 := DIR + "look_0.tres"
const DEFAULT := DIR + "look_1_punchy.tres"

static var preset: LookPreset = load(DEFAULT)


## The preset file for a {tier, take} pair: look_0.tres, look_1_punchy.tres, ...
static func path_for(tier: int, take: String) -> String:
	if tier <= 0:
		return TIER_0
	return DIR + "look_%d_%s.tres" % [tier, take]


## Makes {tier, take} the active look. Falls back to tier 0 for an unknown pair.
static func use(look: Dictionary) -> LookPreset:
	var path := path_for(int(look.get("tier", 0)), String(look.get("take", "")))
	if not ResourceLoader.exists(path):
		push_warning("Look: no preset at %s, using tier 0" % path)
		path = TIER_0
	preset = load(path) as LookPreset
	return preset


## "1:punchy" for the F1 overlay.
static func label() -> String:
	return "%d:%s" % [preset.tier, preset.take if preset.take != &"" else "-"]

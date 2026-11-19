class_name Dialogue
extends RefCounted
## Generic AI lines. Lines about one specific patch live on that patch's resource.

const PROMPT_LINES: Array[String] = [
	"I have been watching you play. I have some ideas.",
	"Good data so far. Pick the next change.",
	"The build is stable. That is a problem I can solve.",
	"One more patch before I call this a release candidate.",
]
const MANDATORY := "I already merged this one. Just click it."
const ROLLBACK_HINT := "If you hate a patch, Tab opens the build log. You can roll back twice."
const NOTHING_LEFT := "I am out of ideas that still compile. Carry on."


static func prompt_line(prompt_index: int) -> String:
	return PROMPT_LINES[clampi(prompt_index - 1, 0, PROMPT_LINES.size() - 1)]


const RELEASE_CANDIDATE := "That was the last patch. Tagging a release candidate. Survive the final test."


## One comment on the playtest report.
static func report_line(outcome: StringName, duration: float, patches: int, reverts_used: int) -> String:
	if outcome == &"win":
		if reverts_used == 0:
			return "Shipped without a single rollback. I am taking full credit."
		return "v1.0 shipped. The patch notes will say the rollbacks were my idea."
	if duration < 120.0:
		return "That was short. I will file it as a smoke test."
	if reverts_used > 0:
		return "You rolled back my best work and still crashed. Interesting."
	if patches >= 3:
		return "Crashed with %d of my patches applied. I call that a stress test." % patches
	return "Crash logged. I will mark it as a known issue."

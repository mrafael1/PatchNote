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
const ROLLBACK_HINT := "Tab opens the build log. Everything you pick is in there."
const NOTHING_LEFT := "I am out of ideas that still compile. Carry on."


static func prompt_line(prompt_index: int) -> String:
	return PROMPT_LINES[clampi(prompt_index - 1, 0, PROMPT_LINES.size() - 1)]


const STAGE_CLEAR := "Stage %d of %d passes. Loading the next level."
const EXIT_OPEN := "The exit is open. Get to it."
const RELEASE_CANDIDATE := "That was the last patch. Tagging a release candidate. Survive the final test."


## One comment on the playtest report.
static func report_line(outcome: StringName, duration: float, patches: int, reverts_used: int) -> String:
	if outcome == &"win":
		if reverts_used > 0:
			return "Shipped, minus the parts you rolled back. I am taking credit for the rest."
		return "Build survived. The patch notes will say it was my idea."
	if duration < 120.0:
		return "That was short. I will file it as a smoke test."
	if reverts_used > 0:
		return "You rolled back my best work and still crashed. Interesting."
	if patches >= 3:
		return "Crashed with %d of my patches applied. I call that a stress test." % patches
	return "Crash logged. I will mark it as a known issue."


# --- Taste ---------------------------------------------------------------

const TAG_NAMES := {&"weapon": "weapon", &"physics": "physics", &"spawn": "enemy",
		&"movement": "movement", &"time": "time", &"strategy": "turn-based"}
const AGENDA_LABEL := "AI's pick"
const AGENDA_LINES: Array[String] = [
	"Outside your comfort zone. Good.",
	"You will not pick this. Pick it anyway.",
	"Trust me on this one.",
	"I wrote this one for me, not for you.",
]


## A line that shows the AI noticed the player's taste, or "" to use the default.
## last_run_rated: -1 first run of the session, 0 previous report skipped, 1 rated.
static func taste_line(taste: Taste, prompt_index: int, last_run_rated: int) -> String:
	if prompt_index == 1:
		if last_run_rated == 1:
			return "I read your notes from the last build. Adjusting."
		if last_run_rated == 0:
			return "No notes last time? Then I pick. More of my ideas this build."
		return ""
	var tag := taste.favourite_tag()
	if tag != &"":
		return "You keep picking %s patches. I leaned the deck that way." % TAG_NAMES.get(tag, String(tag))
	return ""


static func agenda_line(prompt_index: int) -> String:
	return AGENDA_LINES[(prompt_index - 1) % AGENDA_LINES.size()]


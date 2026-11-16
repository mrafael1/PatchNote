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

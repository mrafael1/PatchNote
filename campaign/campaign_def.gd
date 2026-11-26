class_name CampaignDef
extends Resource
## The campaign (PLAN v8 1.1): its sessions in play order, in campaign/campaign.tres.
## Branching on fork answers is done inside sessions (Line conditions, "fork:" enemy
## values), never with separate session lists, so content stays a sum.

@export var sessions: Array[SessionDef] = []
## Each stage's title, for its stage card (PLAN v9 1.2, 2): stage -> "The shooter".
## CampaignDB.problems() wants one for every stage a session names.
@export var stage_titles: Dictionary[int, String] = {}
## M47.6a (PLAN v9.4 2.3): what the chat types at a play gate whose session has no
## before_play of its own (Line syntax), so no gate is ever silent.
@export var before_play_default: PackedStringArray = ["thinking: type play."]
## M47.6a (PLAN v9.4 2.5): canned replies to anything typed at a gate that is not play:
## "kw1|kw2" -> a Line (a whole word, any case); the key "*" is everything else. No model,
## and the typed text is never logged.
@export var chat_replies: Dictionary[String, String] = {}


## The canned reply to `typed` (lower-cased, trimmed): the first key with a matching word,
## else "*" ("" when none).
func chat_reply(typed: String) -> String:
	var words := typed.to_lower().strip_edges().replace("?", " ? ").split(" ", false)
	for key: String in chat_replies:
		if key == "*":
			continue
		for kw in key.split("|", false):
			if kw in words:
				return chat_replies[key]
	return chat_replies.get("*", "")

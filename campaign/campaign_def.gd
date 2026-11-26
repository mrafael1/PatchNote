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
## M47.6b (PLAN v9.4 2.3, D6): the same two once the chat is up (the AI writes in capitals
## from the chat upgrade on). Empty: the terminal's.
@export var before_play_default_chat: PackedStringArray = ["thinking: Type play."]
@export var chat_replies_chat: Dictionary[String, String] = {}
## M47.6b (design 2.8): S2's beat, after its patch rows: the line before the build rows and
## the first line in the new chat.
@export var chat_upgrade_before: PackedStringArray = ["happy: one sec."]
@export var chat_upgrade_after: PackedStringArray = ["proud: New window. Round corners. Proud of them."]


## The canned reply to `typed` (lower-cased, trimmed): the first key with a matching word,
## else "*" ("" when none). chat: the chat's replies (M47.6b), when it has any.
func chat_reply(typed: String, chat := false) -> String:
	var replies := chat_replies_chat if chat and not chat_replies_chat.is_empty() else chat_replies
	var words := typed.to_lower().strip_edges().replace("?", " ? ").split(" ", false)
	for key: String in replies:
		if key == "*":
			continue
		for kw in key.split("|", false):
			if kw in words:
				return replies[key]
	return replies.get("*", "")


## The gate's default lines for the chat style in use (M47.6b).
func before_play_default_for(chat: bool) -> PackedStringArray:
	return before_play_default_chat if chat and not before_play_default_chat.is_empty() else before_play_default

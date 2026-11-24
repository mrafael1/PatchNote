class_name CookingScreen
extends Node
## The cooking screen (M43.2, G13b): where the campaign stands when nothing playable is
## left. The next session is still cooking (SessionDef.cooking, CampaignDB.cooking()):
## its stage card shows the AI building it (StageCard's cooking mode), then "To be
## continued", and a key goes back to the title.
##
## It is not a session: no telemetry, no version bump, no save write. It always shows
## the card (CampaignDB.stage_card_due() is false for a save that played the old S7
## stub). The real session's milestone clears `cooking` (M47 for S7), and the flow plays
## it instead.

const SCENE := "res://ui/cooking_screen.tscn"

var session: SessionDef
var card: StageCard


## Where the game goes once the last playable session is done: the cooking screen when a
## session is cooking, else the title.
static func after_campaign_scene() -> String:
	return SCENE if CampaignDB.cooking() != null else StartScreen.TITLE_SCENE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session = CampaignDB.cooking()
	if session == null:
		_leave.call_deferred()
		return
	card = StageCard.new()
	card.name = "StageCard"
	card.setup(session.stage, String(CampaignDB.campaign.stage_titles.get(session.stage, "")),
			session.cooking, CampaignDB.version_after(session).label())
	card.closed.connect(_leave)
	add_child(card)


func _leave() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().change_scene_to_file(StartScreen.TITLE_SCENE)

class_name CampaignDef
extends Resource
## The campaign (PLAN v8 1.1): its sessions in play order, in campaign/campaign.tres.
## Branching on fork answers is done inside sessions (Line conditions, "fork:" enemy
## values), never with separate session lists, so content stays a sum.

@export var sessions: Array[SessionDef] = []
## Each stage's title, for its stage card (PLAN v9 1.2, 2): stage -> "The shooter".
## CampaignDB.problems() wants one for every stage a session names.
@export var stage_titles: Dictionary[int, String] = {}

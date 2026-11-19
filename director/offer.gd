class_name Offer
extends RefCounted
## What the AI puts on the table at one prompt.

var cards: Array[Mutation] = []
var line := ""            ## what the AI says above the cards
var prompt_index := 0     ## 1 for the first prompt of the run
var mandatory := false    ## a single card with no real choice
var agenda: Array[Mutation] = []   ## cards the AI chose for itself, against the player's taste
var big := false          ## a BIG prompt: big patches, permanent (PLAN v3 section 4)
var keep: Mutation        ## BIG prompts: the patch already in the slot, offered as "keep it"

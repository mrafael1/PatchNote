class_name Offer
extends RefCounted
## What the AI puts on the table at one prompt.

var cards: Array[Mutation] = []
var line := ""            ## what the AI says above the cards
var prompt_index := 0     ## 1 for the first prompt of the run
var mandatory := false    ## a single card with no real choice

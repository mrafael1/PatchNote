class_name Cue
extends RefCounted
## Something a session does at a moment (PLAN v8 1.5), written as plain text:
##
##   "at 15: spawn chaser 1"          at 15 s of the session's goal clock, one chaser
##   "at 20: say happy: Oh. That works."
##   "kills 10: say proud: Ten!"      once the session has 10 kills
##   "pct 50: say Halfway."           at 50% of a survive goal's time
##   "hit: say worried: Ouch."        on the player's first hit (on_signal player_hit)
##   "touch: say surprised: ...?"     the first time something tries to hurt the player
##                                    while the session has no `health` yet (nothing happens)
##   "touch 5: say surprised: ...?"   the same, only before 5 s; dropped after (the AI has
##                                    moved on by then)
##   "at 11: add health"              the AI adds a basic, live (M39.2)
##   "at 50: edit edit_bouncy_walls"  a rule edit (M40)
##   "at 40: event wrong_variable"    a scripted event (M41)
##
## Every cue fires once. The text after "say" is a Line (Line.parse).

const WHENS: Array[StringName] = [&"at", &"kills", &"pct", &"hit", &"touch"]
const ACTIONS: Array[StringName] = [&"say", &"spawn", &"add", &"edit", &"event"]
## The cue times that take no number (touch takes one or none: a deadline).
const BARE_WHENS: Array[StringName] = [&"hit"]
const ARCHETYPES: Array[StringName] = [&"chaser", &"shooter", &"tank", &"bomber", &"lancer"]

var when: StringName = &""
var value := 0.0
var action: StringName = &""
var line: Line                 ## say
var archetype: StringName      ## spawn
var count := 1                 ## spawn
var target: StringName         ## add: the basic; edit / event: the id
var problem := ""
var source := ""


static func parse(p_source: String) -> Cue:
	var c := Cue.new()
	c.source = p_source
	var s := p_source.strip_edges()
	var colon := s.find(":")
	if colon < 0:
		c.problem = "no ':' in cue '%s'" % p_source
		return c
	var head := s.left(colon).strip_edges().split(" ", false)
	var body := s.substr(colon + 1).strip_edges()
	if head.is_empty() or not StringName(head[0]) in WHENS:
		c.problem = "unknown cue time in '%s'" % p_source
		return c
	c.when = StringName(head[0])
	if c.when == &"touch":
		if head.size() > 2 or (head.size() == 2 and not head[1].is_valid_float()):
			c.problem = "cue '%s': 'touch' takes a deadline in seconds or nothing" % p_source
			return c
		c.value = head[1].to_float() if head.size() == 2 else 0.0
	elif not c.when in BARE_WHENS:
		if head.size() != 2 or not head[1].is_valid_float():
			c.problem = "cue '%s' needs a number" % p_source
			return c
		c.value = head[1].to_float()
	elif head.size() != 1:
		c.problem = "cue '%s': '%s' takes no number" % [p_source, c.when]
		return c
	var words := body.split(" ", false)
	if words.is_empty() or not StringName(words[0]) in ACTIONS:
		c.problem = "unknown cue action in '%s'" % p_source
		return c
	c.action = StringName(words[0])
	match c.action:
		&"say":
			c.line = Line.parse(body.substr(3))
			c.problem = c.line.problem
		&"spawn":
			if words.size() < 2 or not StringName(words[1]) in ARCHETYPES:
				c.problem = "cue '%s': spawn what?" % p_source
			else:
				c.archetype = StringName(words[1])
				if words.size() >= 3:
					if not words[2].is_valid_int() or words[2].to_int() < 1:
						c.problem = "cue '%s': bad count" % p_source
					else:
						c.count = words[2].to_int()
		&"add", &"edit", &"event":
			if words.size() != 2:
				c.problem = "cue '%s': %s needs one id" % [p_source, c.action]
			else:
				c.target = StringName(words[1])
	return c


static func parse_all(sources: PackedStringArray) -> Array[Cue]:
	var out: Array[Cue] = []
	for s in sources:
		if s.strip_edges() != "":
			out.append(parse(s))
	return out


## Whether this cue is due. ctx: clock (goal seconds), kills, pct (0..100, -1 when the
## goal has no length), hit (bool, the player was hit since the session began), touched
## (bool, something tried to hurt the player while the session had no health).
func due(ctx: Dictionary) -> bool:
	match when:
		&"at":
			return float(ctx.get("clock", 0.0)) >= value
		&"kills":
			return int(ctx.get("kills", 0)) >= int(value)
		&"pct":
			return float(ctx.get("pct", -1.0)) >= value
		&"hit":
			return bool(ctx.get("hit", false))
		&"touch":
			return bool(ctx.get("touched", false)) and not expired(ctx)
	return false


## A touch cue past its deadline never fires (the moment has passed).
func expired(ctx: Dictionary) -> bool:
	return when == &"touch" and value > 0.0 and float(ctx.get("clock", 0.0)) >= value

class_name Cue
extends RefCounted
## Something a session does at a moment (PLAN v8 1.5), written as plain text:
##
##   "at 15: spawn chaser 1"          at 15 s of the session's goal clock, one chaser
##   "at 6: spawn fork:fork_enemy 1"  one of the enemy that fork's answer unlocks (M42;
##                                    nothing, with a warning, while it is unanswered)
##   "at 20: say happy: Oh. That works."
##   "kills 10: say proud: Ten!"      once the session has 10 kills
##   "pct 50: say Halfway."           at 50% of a survive goal's time
##   "hit: say worried: Ouch."        on the player's first hit (on_signal player_hit)
##   "touch: say surprised: ...?"     the first time something tries to hurt the player
##                                    while the session has no `health` yet (nothing happens)
##   "touch 5: say surprised: ...?"   the same, only before 5 s; dropped after (the AI has
##                                    moved on by then)
##   "at 11: add health"              the AI adds a basic, live (M39.2)
##   "at 12: edit edit_bouncy_walls"  a rule edit (M40), for the edit's own duration
##   "at 12: edit edit_bouncy_walls 10"  the same, live for 10 s
##   "kills 27: edit edit_slowmo 10 quiet"  no warning of its own: it lands on the next
##                                    tick (M43.2); it must share its time with an earlier
##                                    warned edit cue, whose line announces both
##   "at 40: event wrong_variable"    a scripted event (M41)
##   "hp 2: edit edit_slowmo"         the first time the player's HP is 2 or less (needs
##                                    health; a death never fires it) (M42)
##
## Every cue fires once. The text after "say" is a Line (Line.parse).
##
## PLAN v9 1.3 (M43: the grammar; the new whens and actions have no runtime yet, and
## CampaignDB.problems() refuses them in the campaign's data, UNBUILT):
##   "[cond] <when> [N] [at s] [[tag]]: <action>"
##   "answer:path_auto at 12: add levelups"   a Line condition first: the cue is dropped at
##                                            session start when it fails (never half-fired)
##   "room 2 at 5: ..."  "boss_hp 50: ..."  "level 3: ..."  "picked 1: ..."
##   "at 25 [laser]: say ..."                 the weapon a say cue announces (the pool rule)
##   actions: path <arsenal|auto|survival|off>, give <weapon> [rank 1-4],
##   drop <weapon|ammo|heal> [n], look <take|fork:fork_look[@tier]> [seconds],
##   boss <id|fork:fork_boss> [dummy]
## The head ends at the first word that ends with ":" (a condition such as
## "answer:path_auto" has its colon inside).

const WHENS: Array[StringName] = [&"at", &"kills", &"pct", &"hit", &"touch", &"hp", &"room", &"boss_hp",
		&"level", &"picked"]
const ACTIONS: Array[StringName] = [&"say", &"spawn", &"add", &"edit", &"event", &"path", &"give",
		&"drop", &"look", &"boss"]
## The cue times that take no number (touch takes one or none: a deadline).
const BARE_WHENS: Array[StringName] = [&"hit"]
const PATH_TARGETS: Array[StringName] = [&"arsenal", &"auto", &"survival", &"off"]
## Parsed and validated, but nothing runs them yet: CampaignDB.problems() refuses each in
## the campaign's data ("not built yet"). Each later milestone shrinks these lists.
const UNBUILT_ACTIONS: Array[StringName] = [&"path", &"give", &"drop", &"look", &"boss"]
const UNBUILT_WHENS: Array[StringName] = [&"room", &"boss_hp", &"level", &"picked"]
const UNBUILT_TAG := true   ## a "[tag]" cue: the pool rule that reads it comes with weapons (M44)

var when: StringName = &""
var value := 0.0
var action: StringName = &""
var line: Line                 ## say
var archetype: StringName      ## spawn
var count := 1                 ## spawn; drop: how many
var target: StringName         ## add: the basic; edit / event / path / give / drop / look / boss: the id
var seconds := -1.0            ## edit / look: how long it stays (-1: its own duration / for good)
var quiet := false             ## edit: no warning of its own (M43.2; another edit's line announced it)
var cond := ""                 ## a Line condition ("" = always); failing at start drops the cue
var at_seconds := -1.0         ## room N at s: s seconds after part N starts (-1: at its start)
var tag: StringName = &""      ## [tag]: the weapon a say cue announces
var rank := 1                  ## give: the rank (1-4)
var dummy := false             ## boss: the harmless one
var problem := ""
var source := ""


static func parse(p_source: String) -> Cue:
	var c := Cue.new()
	c.source = p_source
	var s := p_source.strip_edges()
	var colon := -1
	for i in s.length():
		if s[i] == ":" and (i + 1 == s.length() or s[i + 1] == " " or s[i + 1] == "\t"):
			colon = i
			break
	if colon < 0:
		c.problem = "no ':' in cue '%s'" % p_source
		return c
	var head := s.left(colon).strip_edges().split(" ", false)
	var body := s.substr(colon + 1).strip_edges()
	if not head.is_empty() and not StringName(head[0]) in WHENS and Line.condition_known(StringName(head[0])):
		c.cond = head[0]
		c.problem = Line.condition_problem(c.cond, p_source)
		if c.problem != "":
			return c
		head.remove_at(0)
	if not head.is_empty() and head[head.size() - 1].begins_with("[") and head[head.size() - 1].ends_with("]"):
		c.tag = StringName(head[head.size() - 1].substr(1, head[head.size() - 1].length() - 2))
		head.remove_at(head.size() - 1)
		if c.tag == &"":
			c.problem = "cue '%s': an empty [tag]" % p_source
			return c
	if head.is_empty() or not StringName(head[0]) in WHENS:
		c.problem = "unknown cue time in '%s'" % p_source
		return c
	c.when = StringName(head[0])
	if c.when == &"room":
		if not (head.size() == 2 or (head.size() == 4 and head[2] == "at")) or not head[1].is_valid_int() \
				or head[1].to_int() < 1 or (head.size() == 4 and (not head[3].is_valid_float() or head[3].to_float() < 0.0)):
			c.problem = "cue '%s': room takes a part number >= 1 and optionally 'at <seconds>'" % p_source
			return c
		c.value = head[1].to_int()
		c.at_seconds = head[3].to_float() if head.size() == 4 else -1.0
	elif c.when in [&"level", &"picked", &"boss_hp"]:
		var low := 0 if c.when == &"boss_hp" else 1
		var high := 100 if c.when == &"boss_hp" else 1000000
		if head.size() != 2 or not head[1].is_valid_int() or head[1].to_int() < low or head[1].to_int() > high:
			c.problem = "cue '%s': %s takes a whole number %s" % [p_source, c.when,
					"0-100" if c.when == &"boss_hp" else ">= 1"]
			return c
		c.value = head[1].to_int()
	elif c.when == &"touch":
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
			if words.size() < 2 or not (EnemyDB.has(StringName(words[1]))
					or (words[1].begins_with("fork:") and words[1].length() > 5)):
				c.problem = "cue '%s': spawn what?" % p_source
			else:
				c.archetype = StringName(words[1])
				if words.size() >= 3:
					if not words[2].is_valid_int() or words[2].to_int() < 1:
						c.problem = "cue '%s': bad count" % p_source
					else:
						c.count = words[2].to_int()
		&"edit":
			if words.size() >= 3 and words[words.size() - 1] == "quiet":
				c.quiet = true
				words.remove_at(words.size() - 1)
			if words.size() == 3 and words[2].is_valid_float() and words[2].to_float() > 0.0:
				c.target = StringName(words[1])
				c.seconds = words[2].to_float()
			elif words.size() != 2:
				c.problem = "cue '%s': edit takes an id, optional seconds and optional 'quiet'" % p_source
			else:
				c.target = StringName(words[1])
		&"add", &"event":
			if words.size() != 2:
				c.problem = "cue '%s': %s needs one id" % [p_source, c.action]
			else:
				c.target = StringName(words[1])
		&"path":
			if words.size() != 2 or not StringName(words[1]) in PATH_TARGETS:
				c.problem = "cue '%s': path takes one of %s" % [p_source, PATH_TARGETS]
			else:
				c.target = StringName(words[1])
		&"give":
			if words.size() < 2 or words.size() > 3 or (words.size() == 3 and (not words[2].is_valid_int()
					or words[2].to_int() < 1 or words[2].to_int() > 4)):
				c.problem = "cue '%s': give takes a weapon and optionally a rank 1-4" % p_source
			else:
				c.target = StringName(words[1])
				c.rank = words[2].to_int() if words.size() == 3 else 1
		&"drop":
			if words.size() < 2 or words.size() > 3 or (words.size() == 3 and (not words[2].is_valid_int()
					or words[2].to_int() < 1)):
				c.problem = "cue '%s': drop takes a weapon, ammo or heal and optionally a count" % p_source
			else:
				c.target = StringName(words[1])
				c.count = words[2].to_int() if words.size() == 3 else 1
		&"look":
			if words.size() < 2 or words.size() > 3 or (words.size() == 3 and (not words[2].is_valid_float()
					or words[2].to_float() <= 0.0)) or (words[1].begins_with("fork:") and words[1].length() <= 5):
				c.problem = "cue '%s': look takes a take or fork:<id>[@tier] and optionally seconds" % p_source
			else:
				c.target = StringName(words[1])
				c.seconds = words[2].to_float() if words.size() == 3 else -1.0
		&"boss":
			if words.size() < 2 or words.size() > 3 or (words.size() == 3 and words[2] != "dummy") \
					or (words[1].begins_with("fork:") and words[1].length() <= 5):
				c.problem = "cue '%s': boss takes an id or fork:<id> and optionally 'dummy'" % p_source
			else:
				c.target = StringName(words[1])
				c.dummy = words.size() == 3
	return c


## Why this cue cannot run yet, or "" (PLAN v9 1.3's new whens, actions and tags parse,
## but nothing runs them before their milestone).
func unbuilt() -> String:
	if action in UNBUILT_ACTIONS:
		return "%s is not built yet" % action
	if when in UNBUILT_WHENS:
		return "%s is not built yet" % when
	if UNBUILT_TAG and tag != &"":
		return "[tag] is not built yet"
	return ""


static func parse_all(sources: PackedStringArray) -> Array[Cue]:
	var out: Array[Cue] = []
	for s in sources:
		if s.strip_edges() != "":
			out.append(parse(s))
	return out


## Whether this cue is due. ctx: clock (goal seconds), kills, pct (0..100, -1 when the
## goal has no length), hit (bool, the player was hit since the session began), touched
## (bool, something tried to hurt the player while the session had no health), hp (the
## player's HP; -1 without health or player, never due then).
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
		&"hp":
			var hp := float(ctx.get("hp", -1.0))
			return hp > 0.0 and hp <= value
		# PLAN v9 1.3: nothing supplies these keys in M43, so they are never due yet.
		&"room":
			return int(ctx.get("room", -1)) == int(value) and float(ctx.get("room_clock", -1.0)) >= maxf(at_seconds, 0.0)
		&"boss_hp":
			var boss_hp := float(ctx.get("boss_hp", -1.0))
			return boss_hp >= 0.0 and boss_hp <= value
		&"level":
			return int(ctx.get("level", 0)) >= int(value)
		&"picked":
			return int(ctx.get("picks", 0)) >= int(value)
	return false


## A touch cue past its deadline never fires (the moment has passed).
func expired(ctx: Dictionary) -> bool:
	return when == &"touch" and value > 0.0 and float(ctx.get("clock", 0.0)) >= value

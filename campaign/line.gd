class_name Line
extends RefCounted
## One thing the AI says (PLAN v8 1.1). Sessions write lines as plain text, so the
## owner can edit them for tone without touching a resource's sub-resources:
##
##   "happy: Oh. That works."                 an expression, then the text
##   "died guilty: Too many at once. My bad."  a condition first: said only if it holds
##   "mascot:blob happy: I'm squishy?"         a mascot's signature line
##   "Just the text."                          idle, always said
##
## Conditions (`when`): won, died, stopped (the session's outcome), hit_none, hit_lots
## (the player's hits taken), first_try, retry (the attempt), mascot:<id> (the save's
## mascot), answer:<change id> (a shipped fork answer), event:<id> (that scripted event
## played in this attempt), ended (the session is over for good: won, stopped, or moved on
## after a death; M42), dash:<style> (the save's fork_dash answer, a style in
## Change.DASHES; classic while unanswered, M42.1), dash_aim:<aim|move> (the save's
## fork_dash_aim answer, in Change.DASH_AIMS; move while unanswered, M42.2),
## attempts:<n> (this is attempt n or later, n >= 1) and died_in:<session id> (the save
## has a retried death in that session, campaign.attempts) (PLAN v9 1.1, M43). Each is
## checked against a context dictionary (passes()); a key the context lacks fails the line.
## Any conditions join with "&" (all must hold): "dash:grapple&dash_aim:aim",
## "died&attempts:2". A leading "!" negates one condition ("!answer:path_auto"); it still
## fails when the context lacks that condition's key. M50.1b: fused / misfused (a fusion /
## the misfuse happened in this attempt, from the run log; Arsenal's S9). Cues and reactions share this
## (condition_problem(), condition_holds()).

const EXPRESSIONS: Array[StringName] = [&"idle", &"happy", &"proud", &"worried", &"surprised",
		&"guilty", &"thinking", &"panic"]
const OUTCOMES: Array[StringName] = [&"won", &"died", &"stopped"]
const PLAIN_CONDITIONS: Array[StringName] = [&"won", &"died", &"stopped", &"hit_none", &"hit_lots",
		&"first_try", &"retry", &"ended", &"fused", &"misfused", &"evolved"]
const PREFIX_CONDITIONS: Array[String] = ["mascot:", "answer:", "event:", "dash:", "dash_aim:",
		"attempts:", "died_in:"]
## The context key each condition reads (a "!" condition fails without it, too).
const KEYS := {"won": "outcome", "died": "outcome", "stopped": "outcome", "ended": "outcome",
		"hit_none": "hits", "hit_lots": "hits", "first_try": "attempt", "retry": "attempt",
		"attempts:": "attempt", "answer:": "shipped", "mascot:": "mascot", "event:": "events",
		"dash:": "dash", "dash_aim:": "dash_aim", "died_in:": "attempts_by_session",
		"fused": "fused", "misfused": "misfused", "evolved": "evolved"}
## Hits taken at or above this are "hit_lots".
const HIT_LOTS := 3

var text := ""
var expression: StringName = &"idle"
var when: StringName = &""
var problem := ""   ## why the source did not parse ("" = fine)


static func make(p_text: String, p_expression: StringName = &"idle", p_when: StringName = &"") -> Line:
	var l := Line.new()
	l.text = p_text
	l.expression = p_expression
	l.when = p_when
	return l


## "cond expression: text" (both optional). An unknown word before the colon is a
## problem, so a typo never silently becomes part of the text.
static func parse(source: String) -> Line:
	var l := Line.new()
	var s := source.strip_edges()
	var colon := s.find(": ")
	if colon < 0 and s.ends_with(":"):
		colon = s.length() - 1
	var head := s.left(colon).strip_edges() if colon >= 0 else ""
	# A head is one or two words with no spaces inside them; anything else is text.
	var words := head.split(" ", false) if head != "" else PackedStringArray()
	if colon >= 0 and words.size() in [1, 2] and _is_head(words):
		l.text = s.substr(colon + 1).strip_edges()
		for w in words:
			if StringName(w) in EXPRESSIONS:
				l.expression = StringName(w)
			else:
				l.when = StringName(w)
	else:
		l.text = s
	if l.text == "":
		l.problem = "empty line '%s'" % source
	else:
		l.problem = condition_problem(String(l.when), source)
		if l.problem == "":
			l.problem = InputSetup.keys_problem(l.text)
	return l


## Why a condition (Line syntax: one-word conditions joined by "&", "!" negating one) is
## wrong, or "" (the empty condition is fine: it always holds). source names it in the
## message (the line, cue or reaction it came from). died_in: session ids are checked by
## CampaignDB.problems(), which knows the campaign.
static func condition_problem(cond: String, source := "") -> String:
	if cond == "":
		return ""
	var where := source if source != "" else cond
	if not condition_known(StringName(cond)):
		return "unknown condition '%s' in '%s'" % [cond, where]
	for part in cond.split("&"):
		var c := part.trim_prefix("!")
		if c.begins_with("dash:") and not StringName(c.trim_prefix("dash:")) in Change.DASHES:
			return "unknown dash '%s' in '%s' (%s)" % [c.trim_prefix("dash:"), where, Change.DASHES]
		if c.begins_with("dash_aim:") and not StringName(c.trim_prefix("dash_aim:")) in Change.DASH_AIMS:
			return "unknown dash direction '%s' in '%s' (%s)" % [c.trim_prefix("dash_aim:"), where,
					Change.DASH_AIMS]
		if c.begins_with("attempts:"):
			var n := c.trim_prefix("attempts:")
			if not n.is_valid_int() or n.to_int() < 1:
				return "attempts needs a whole number >= 1 in '%s'" % where
	return ""


## Whether a condition holds in ctx ("" always does). Every "&" part must hold.
static func condition_holds(cond: String, ctx: Dictionary) -> bool:
	if cond == "":
		return true
	for c in cond.split("&"):
		if not _holds(StringName(c), ctx):
			return false
	return true


## The context key one condition (no "!", no "&") reads; "" when unknown.
static func context_key(cond: String) -> String:
	if KEYS.has(cond):
		return KEYS[cond]
	for p in PREFIX_CONDITIONS:
		if cond.begins_with(p):
			return KEYS.get(p, "")
	return ""


## The conditions an "&"-joined condition names, "!" stripped (the answer: guard test).
static func condition_parts(cond: String) -> Array[String]:
	var out: Array[String] = []
	if cond != "":
		for part in cond.split("&"):
			out.append(part.trim_prefix("!"))
	return out


## Every word is an expression or a condition, with at most one of each.
static func _is_head(words: PackedStringArray) -> bool:
	var expressions := 0
	var conditions := 0
	for w in words:
		if StringName(w) in EXPRESSIONS:
			expressions += 1
		elif _looks_like_condition(w):
			conditions += 1
		else:
			return false
	return expressions <= 1 and conditions <= 1


static func _looks_like_condition(w: String) -> bool:
	if "&" in w:
		var parts := w.split("&")
		return Array(parts).all(func(c: String) -> bool: return c != "" and _looks_like_condition(c))
	if w.begins_with("!"):
		w = w.substr(1)
	if StringName(w) in PLAIN_CONDITIONS:
		return true
	for p in PREFIX_CONDITIONS:
		if w.begins_with(p):
			return true
	return false


static func condition_known(c: StringName) -> bool:
	if "&" in String(c):
		return Array(String(c).split("&")).all(func(p: String) -> bool: return p != "" and condition_known(p))
	if String(c).begins_with("!"):
		c = StringName(String(c).substr(1))
	if c in PLAIN_CONDITIONS:
		return true
	for p in PREFIX_CONDITIONS:
		if String(c).begins_with(p) and String(c).length() > p.length():
			return true
	return false


static func parse_all(sources: PackedStringArray) -> Array[Line]:
	var out: Array[Line] = []
	for s in sources:
		if s.strip_edges() != "":
			out.append(parse(s))
	return out


## ctx keys: outcome (StringName), moved_on (bool), hits (int), attempt (int, 1 = first), mascot
## (StringName), shipped (Array of change ids), dash (StringName, the dash style), dash_aim
## (StringName, aim or move), attempts_by_session (Dictionary: session id -> retried deaths).
func passes(ctx: Dictionary) -> bool:
	return condition_holds(String(when), ctx)


static func _holds(cond: StringName, ctx: Dictionary) -> bool:
	var w := String(cond)
	if w.begins_with("!"):
		var rest := w.substr(1)
		var key := context_key(rest)
		return key != "" and ctx.has(key) and not _holds(StringName(rest), ctx)
	if cond in OUTCOMES:
		return ctx.has("outcome") and StringName(ctx.outcome) == cond
	match cond:
		&"hit_none":
			return ctx.has("hits") and int(ctx.hits) == 0
		&"hit_lots":
			return ctx.has("hits") and int(ctx.hits) >= HIT_LOTS
		&"first_try":
			return ctx.has("attempt") and int(ctx.attempt) <= 1
		&"retry":
			return ctx.has("attempt") and int(ctx.attempt) > 1
		&"ended":
			return ctx.has("outcome") and (StringName(ctx.outcome) in [&"won", &"stopped"]
					or bool(ctx.get("moved_on", false)))
		&"fused", &"misfused", &"evolved":   # M50.1b: a fusion / the misfuse; M50.4c1: an evolution
			return bool(ctx.get(String(cond), false))
	if w.begins_with("mascot:"):
		return ctx.has("mascot") and String(ctx.mascot) == w.trim_prefix("mascot:")
	if w.begins_with("answer:"):
		return ctx.has("shipped") and StringName(w.trim_prefix("answer:")) in (ctx.shipped as Array)
	if w.begins_with("event:"):
		return ctx.has("events") and w.trim_prefix("event:") in (ctx.events as Array)
	if w.begins_with("dash:"):
		return ctx.has("dash") and String(ctx.dash) == w.trim_prefix("dash:")
	if w.begins_with("dash_aim:"):
		return ctx.has("dash_aim") and String(ctx.dash_aim) == w.trim_prefix("dash_aim:")
	if w.begins_with("attempts:"):
		return ctx.has("attempt") and int(ctx.attempt) >= w.trim_prefix("attempts:").to_int()
	if w.begins_with("died_in:"):
		return ctx.has("attempts_by_session") and int((ctx.attempts_by_session as Dictionary).get(
				w.trim_prefix("died_in:"), 0)) > 0
	return false


## The lines of `lines` that pass ctx, in order.
static func passing(lines: Array[Line], ctx: Dictionary) -> Array[Line]:
	var out: Array[Line] = []
	for l in lines:
		if l.passes(ctx):
			out.append(l)
	return out

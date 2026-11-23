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
## played in this attempt). Each is checked against a
## context dictionary (passes()); a key the context lacks fails the line.

const EXPRESSIONS: Array[StringName] = [&"idle", &"happy", &"proud", &"worried", &"surprised",
		&"guilty", &"thinking", &"panic"]
const OUTCOMES: Array[StringName] = [&"won", &"died", &"stopped"]
const PLAIN_CONDITIONS: Array[StringName] = [&"won", &"died", &"stopped", &"hit_none", &"hit_lots",
		&"first_try", &"retry"]
const PREFIX_CONDITIONS: Array[String] = ["mascot:", "answer:", "event:"]
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
	elif l.when != &"" and not condition_known(l.when):
		l.problem = "unknown condition '%s' in '%s'" % [l.when, source]
	return l


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
	if StringName(w) in PLAIN_CONDITIONS:
		return true
	for p in PREFIX_CONDITIONS:
		if w.begins_with(p):
			return true
	return false


static func condition_known(c: StringName) -> bool:
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


## ctx keys: outcome (StringName), hits (int), attempt (int, 1 = first), mascot
## (StringName), shipped (Array of change ids).
func passes(ctx: Dictionary) -> bool:
	if when == &"":
		return true
	var w := String(when)
	if when in OUTCOMES:
		return ctx.has("outcome") and StringName(ctx.outcome) == when
	match when:
		&"hit_none":
			return ctx.has("hits") and int(ctx.hits) == 0
		&"hit_lots":
			return ctx.has("hits") and int(ctx.hits) >= HIT_LOTS
		&"first_try":
			return ctx.has("attempt") and int(ctx.attempt) <= 1
		&"retry":
			return ctx.has("attempt") and int(ctx.attempt) > 1
	if w.begins_with("mascot:"):
		return ctx.has("mascot") and String(ctx.mascot) == w.trim_prefix("mascot:")
	if w.begins_with("answer:"):
		return ctx.has("shipped") and StringName(w.trim_prefix("answer:")) in (ctx.shipped as Array)
	if w.begins_with("event:"):
		return ctx.has("events") and w.trim_prefix("event:") in (ctx.events as Array)
	return false


## The lines of `lines` that pass ctx, in order.
static func passing(lines: Array[Line], ctx: Dictionary) -> Array[Line]:
	var out: Array[Line] = []
	for l in lines:
		if l.passes(ctx):
			out.append(l)
	return out

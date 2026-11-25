class_name LanceLine
extends Line2D
## The lancer's telegraphed line (M48a): its colour comes from Palette's `lancer_line` role,
## so the lancer itself (a walker behaviour, kept off Palette and Skins by a lint) only sets
## how far the windup is. Presentation only. Tier 0 is the M47.2 colour exactly:
## Color(1.0, 0.3, 0.9, 0.25 + 0.55 * strength). The lancer sets strength on every windup
## tick, so a live look swap recolours the line on the next tick.

## The windup's progress, 0..1: the line's alpha is 0.25 + 0.55 * strength.
var strength := 0.0:
	set(v):
		strength = v
		default_color = Color(Palette.color(&"lancer_line"), 0.25 + 0.55 * strength)

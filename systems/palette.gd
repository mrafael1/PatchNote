class_name Palette
extends RefCounted
## Every colour a visual uses, by role (PLAN 1.7, M48a). Presentation only: no gameplay
## script reads it (a lint in test_pixel_skin.gd). `color(role)` is the live colour: the
## current look's (Skins.current, its art script's ROLES) when it names the role, else
## tier 0. Tier 0 is today's colours, unchanged, so the look off draws byte for byte what
## it drew before M48a.
##
## The constants below are the tier-0 values themselves, so a script that only ever draws
## tier 0 (the menus, the mascot bodies, the dev chat) can keep a `const` alias of one.
## The 14 roles of 1.7 come first; the rest are finer roles (one per colour that was
## hard-coded somewhere, so tier 0 stays exact). Role names avoid mutation ids (the
## mutation lint): `hunter_body`, `elite_ring`, `well_field`.

# --- 1.7's roles ------------------------------------------------------------------------
const BG := Color(0.09, 0.1, 0.13)                ## arena background
const GRID := Color(1, 1, 1, 0.035)               ## arena grid lines (no gravity)
const WALL := Color(0.42, 0.45, 0.52)             ## arena blocks
const PLAYER := Color(0.3, 0.85, 1, 1)            ## the player's body (player.tscn)
const PLAYER_SHOT := Color(1.0, 0.95, 0.5)        ## player projectiles and their trail
const ENEMY := Color(0.95, 0.3, 0.3, 1)           ## the base enemy (enemy_chaser.tscn)
const ENEMY_SHOT := Color(1.0, 0.55, 0.2)         ## enemy projectiles
const ELITE := Color(1.0, 0.85, 0.3)              ## the elite's shield ring
const PICKUP := Color(1.0, 0.85, 0.35)            ## ammo, heal, battery, weapon drops
const BLAST := Color(1.0, 0.7, 0.25)              ## explosions
const UI_TEXT := Color.WHITE                      ## plain UI text
const UI_PANEL := Color(0.1, 0.11, 0.16, 0.94)    ## a UI card's face (Arsenal's hand)
const ACCENT := Color(0.55, 1.0, 0.65)            ## the AI's terminal green
const DANGER := Color(1.0, 0.15, 0.1)             ## the danger rim around a body

# --- finer roles: the world --------------------------------------------------------------
const STANDABLE := Color(0.95, 0.97, 1.0)         ## the lit face you stand on (gravity)
const DEPTH := Color(0.0, 0.0, 0.0, 0.5)          ## the gravity shading
const SHADOW := Color(0, 0, 0)                    ## shadows and backs (alpha at the use)
const OUTLINE := Color.BLACK                      ## font outlines, a crate's edge
const GEM := Color(0.45, 0.95, 1.0)               ## Auto's XP gem and its level bar
const CRATE := Color(0.75, 0.55, 0.3)
const GATE := Color(0.35, 1.0, 0.6)               ## the exit gate and its arrow
const HUNTER_BODY := Color(0.75, 0.1, 0.25)
const ORBIT_SHARD := Color(0.55, 0.95, 1.0)
const WELL_FIELD := Color(0.6, 0.45, 1.0)
const BURN := Color(1.0, 0.45, 0.2)               ## a burn line on the floor
const LANCER_LINE := Color(1.0, 0.3, 0.9)         ## the lancer's telegraphed line
const DUST := Color(0.75, 0.78, 0.85)             ## landing dust, a fizzled dash
const HIT := Color(1.0, 0.35, 0.35)               ## the player-hit burst
const MUZZLE := Color(1.0, 0.95, 0.7)
const DASH := Color(0.4, 0.9, 1.0)                ## the dash, the hook, the teleport
const SPARK := Color(1.0, 0.75, 0.3)              ## an explosion's sparks
const PIP_BACK := Color(0.12, 0.08, 0.14)         ## the Pixel elite's pip backing
const VIGNETTE := Color(0.9, 0.05, 0.05)          ## the player-hit vignette
const TURN_PATH := Color(1.0, 0.8, 0.45, 0.8)     ## the turn grid's overlay
const TURN_DANGER := Color(1.0, 0.2, 0.2, 0.3)
const TURN_AIM := Color(1.0, 0.35, 0.3, 0.9)
const TURN_SHOT := Color(1.0, 0.6, 0.25, 0.95)
const TURN_REST := Color(0.65, 0.8, 1.0, 0.9)
const HINT := Color(1.0, 0.85, 0.3)               ## the inverted-controls hint
const MARKER := Color(1.0, 0.82, 0.3)             ## a rule edit's marker

# --- finer roles: the UI ----------------------------------------------------------------
const UI_DIM := Color(0.75, 0.75, 0.8)            ## a dimmed card, the stage number
const UI_SOFT := Color(0.85, 0.85, 0.9)           ## the stage card's "Building"
const CARD_LIT := Color(1.0, 0.95, 0.5)           ## the equipped card
const CARD_FLASH := Color(0.5, 0.5, 0.6, 0.94)    ## a card joining the hand
const CARD_BAR := Color(1.0, 0.85, 0.35)          ## the card meter
const CARD_RARE := Color(1.0, 0.78, 0.22)         ## M50.1a: a rare pack card's frame
const CARD_ITEM := Color(1.0, 0.62, 0.38)         ## M50.4b: a passive item's level-up card
const CARD_EVOLVE := Color(1.0, 0.85, 0.3)        ## M50.4c1: the EVOLVE choice's gold frame
const GAUGE := Color(0.55, 1.0, 0.7)              ## the HUD gauge and its banner
const SPINNER := Color(1.0, 0.85, 0.3)            ## the stage card's spinner
const BEAT_TEXT := Color(0.7, 0.9, 0.7)           ## the stage card's build lines
const LOCK := Color(1.0, 0.8, 0.45)               ## a lock icon, a patch-history tag
const INFO := Color(0.45, 0.95, 1.0)              ## the pick panel's line
const DEBUG_TEXT := Color(0.75, 1.0, 0.8)
const REWORK := Color(0.55, 0.85, 1.0)            ## the dev chat's rework card
const REWORK_BACK := Color(0.06, 0.1, 0.14)
const AGENDA := Color(1.0, 0.75, 0.55)            ## the agenda pick, highlighted
const KEEP := Color(0.45, 1.0, 0.55)              ## the report's keep
const LOSE := Color(1.0, 0.45, 0.4)               ## the report's cut and a loss
const SCRIM := Color(0.02, 0.03, 0.05)            ## full-screen dims (alpha at the use)
const SCRIM_TEAL := Color(0.0, 0.02, 0.03)
const SCRIM_PICK := Color(0.02, 0.02, 0.06)
const BAND := Color(0.0, 0.03, 0.02, 0.72)        ## the transition's band
const TITLE_BG := Color(0.03, 0.05, 0.06)
const CURTAIN := Color.BLACK                      ## the stage card's back

# --- finer roles: the mascot --------------------------------------------------------------
const MASCOT_INK := Color(0.08, 0.09, 0.13)
const MASCOT_EYE := Color(0.98, 0.98, 1.0)
const MASCOT_SWEAT := Color(0.55, 0.8, 1.0)
const MASCOT_BLUSH := Color(1.0, 0.45, 0.5)
const GLITCH_RED := Color(1.0, 0.25, 0.35, 0.55)
const GLITCH_CYAN := Color(0.25, 1.0, 1.0, 0.55)
const BUBBLE := Color(0.97, 0.97, 1.0, 0.96)
const BLOB_FILL := Color(0.38, 0.88, 0.7)
const BLOB_EDGE := Color(0.1, 0.42, 0.34)
const BLOB_CHEEK := Color(1.0, 0.5, 0.6, 0.6)
const CURSOR_FILL := Color(0.96, 0.97, 1.0)
const CURSOR_CARET := Color(0.2, 0.75, 1.0)
const WINDOW_BODY := Color(0.92, 0.94, 0.97)
const WINDOW_BAR := Color(0.24, 0.45, 0.95)
const WINDOW_PANIC := Color(0.86, 0.26, 0.28)
const WINDOW_GUILTY := Color(0.5, 0.53, 0.6)

# --- M47.5a: the raw dev terminal (always on, pre-UI; tier-0 constants, not look roles) ---
const TERM_BG := Color(0.039, 0.039, 0.047)       ## #0a0a0c, the terminal's back
const TERM_RULE := Color(0.32, 0.33, 0.36)        ## its 1 px left rule, the fork boxes' frame
const TERM_TEXT := Color(0.93, 0.93, 0.95)        ## a line the AI says
const TERM_DIM := Color(0.5, 0.52, 0.56)          ## headers, sys rows, thinking, chatter
const TERM_CMD := Color(0.35, 0.85, 0.95)         ## $ build / patch apply / hot-reload
const TERM_NOTE := Color(0.78, 0.79, 0.82)        ## the changelog rows
const TERM_CHOICE := Color(1.0, 0.85, 0.35)       ## [1] [2] [3]
const TERM_YOU := Color.WHITE                     ## you> _
const TERM_ERR := Color(1.0, 0.42, 0.4)

## 1.7's roles: every look must name each of these (test_pixel_skin).
const CORE: Array[StringName] = [&"bg", &"grid", &"wall", &"player", &"player_shot", &"enemy",
	&"enemy_shot", &"elite", &"pickup", &"blast", &"ui_text", &"ui_panel", &"accent", &"danger"]

## Tier 0: every role, today's colour.
const TIER_0 := {
	&"bg": BG, &"grid": GRID, &"wall": WALL, &"player": PLAYER, &"player_shot": PLAYER_SHOT,
	&"enemy": ENEMY, &"enemy_shot": ENEMY_SHOT, &"elite": ELITE, &"pickup": PICKUP,
	&"blast": BLAST, &"ui_text": UI_TEXT, &"ui_panel": UI_PANEL, &"accent": ACCENT,
	&"danger": DANGER,
	&"standable": STANDABLE, &"depth": DEPTH, &"shadow": SHADOW, &"outline": OUTLINE,
	&"gem": GEM, &"crate": CRATE, &"gate": GATE, &"hunter_body": HUNTER_BODY,
	&"orbit_shard": ORBIT_SHARD, &"well_field": WELL_FIELD, &"burn": BURN,
	&"lancer_line": LANCER_LINE, &"dust": DUST, &"hit": HIT, &"muzzle": MUZZLE, &"dash": DASH,
	&"spark": SPARK, &"pip_back": PIP_BACK, &"vignette": VIGNETTE, &"turn_path": TURN_PATH,
	&"turn_danger": TURN_DANGER, &"turn_aim": TURN_AIM, &"turn_shot": TURN_SHOT,
	&"turn_rest": TURN_REST, &"hint": HINT, &"marker": MARKER,
	&"ui_dim": UI_DIM, &"ui_soft": UI_SOFT, &"card_lit": CARD_LIT, &"card_flash": CARD_FLASH,
	&"card_bar": CARD_BAR, &"card_rare": CARD_RARE, &"card_item": CARD_ITEM, &"card_evolve": CARD_EVOLVE, &"gauge": GAUGE, &"spinner": SPINNER, &"beat_text": BEAT_TEXT,
	&"lock": LOCK, &"info": INFO, &"debug_text": DEBUG_TEXT, &"rework": REWORK,
	&"rework_back": REWORK_BACK, &"agenda": AGENDA, &"keep": KEEP, &"lose": LOSE,
	&"scrim": SCRIM, &"scrim_teal": SCRIM_TEAL, &"scrim_pick": SCRIM_PICK, &"band": BAND,
	&"title_bg": TITLE_BG, &"curtain": CURTAIN,
	&"mascot_ink": MASCOT_INK, &"mascot_eye": MASCOT_EYE, &"mascot_sweat": MASCOT_SWEAT,
	&"mascot_blush": MASCOT_BLUSH, &"glitch_red": GLITCH_RED, &"glitch_cyan": GLITCH_CYAN,
	&"bubble": BUBBLE, &"blob_fill": BLOB_FILL, &"blob_edge": BLOB_EDGE,
	&"blob_cheek": BLOB_CHEEK, &"cursor_fill": CURSOR_FILL, &"cursor_caret": CURSOR_CARET,
	&"window_body": WINDOW_BODY, &"window_bar": WINDOW_BAR, &"window_panic": WINDOW_PANIC,
	&"window_guilty": WINDOW_GUILTY,
}


## The live colour of `role`: the current look's, else tier 0 (magenta for an unknown
## role, so a typo shows on screen; test_pixel_skin checks every role used resolves).
static func color(role: StringName) -> Color:
	if Skins.role_on(role):   # M48b: the role's id is revealed (all, outside S9)
		var c: Variant = Skins.current.role(role)
		if c != null:
			return c
	return TIER_0.get(role, Color.MAGENTA)


## Tier 0's colour of `role` (no look).
static func tier_0(role: StringName) -> Color:
	return TIER_0.get(role, Color.MAGENTA)


static func has(role: StringName) -> bool:
	return TIER_0.has(role)

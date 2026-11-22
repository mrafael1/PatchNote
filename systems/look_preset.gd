class_name LookPreset
extends Resource
## One look (PLAN v5 1.7): how much juice the presentation adds on top of the
## readability layer (2.2), which every look keeps. Presentation only: no gameplay
## value reads a preset.

@export var tier := 0
@export var take: StringName = &""
@export var shake_scale := 1.0      ## multiplies every screen shake; 0 is none
@export var particle_scale := 1.0   ## multiplies every burst's particle count
@export var hit_stop := 0.0         ## real seconds of near-frozen time on a player hit (kills get a share)
@export var muzzle_flash := false   ## a flash at the player's muzzle on each shot
@export var kill_pop_scale := 1.0   ## the kill ring's size
@export var trail := false          ## player projectiles draw a streak behind them
@export var screen_flash := false   ## a short white flash on explosions
## 4 colours: background, walls, the player, accents. Tier 1 shares tier 0's (1.7).
@export var palette: Array[Color] = []

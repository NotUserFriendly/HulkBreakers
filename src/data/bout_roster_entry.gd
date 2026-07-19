class_name BoutRosterEntry
extends Resource

## taskblock-17 Pass D: "playstyle moves from per-team to per-bot — each
## entry carries its own." One row of a BoutSetup roster: which profile,
## and which playstyle THAT bot fights with — a typed pair instead of two
## parallel arrays a caller could desync by index.

@export var profile: BotPreset = null
@export var playstyle: StringName = &"AGGRESSIVE"


func _init(p_profile: BotPreset = null, p_playstyle: StringName = &"AGGRESSIVE") -> void:
	profile = p_profile
	playstyle = p_playstyle

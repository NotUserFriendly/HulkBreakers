class_name BoutRosterEntry
extends Resource

## taskblock-17 Pass D: "the AI choice moves from per-team to per-bot — each
## entry carries its own." One row of a BoutSetup roster: which profile,
## and which AI profile THAT bot fights with — a typed pair instead of two
## parallel arrays a caller could desync by index.

@export var profile: BotPreset = null
@export var ai_profile: StringName = &"aggressive"


func _init(p_profile: BotPreset = null, p_ai_profile: StringName = &"aggressive") -> void:
	profile = p_profile
	ai_profile = p_ai_profile

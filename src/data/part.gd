class_name Part
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var part_type: Enums.PartType = Enums.PartType.WEAPON
@export var slot_type: Enums.SlotType = Enums.SlotType.TORSO
@export var hp: int = 1
@export var max_hp: int = 1
@export var mass: float = 0.0
@export var volume: float = 0.0
@export var exposure_weight: float = 0.0
@export var stat_mods: Dictionary = {}
@export var is_container: bool = false
@export var max_volume: float = 0.0
@export var mass_multiplier: float = 1.0
@export var contents: Array[Part] = []
@export var is_destructible: bool = true  # false marks permanent terrain (e.g. cover that can never be destroyed)

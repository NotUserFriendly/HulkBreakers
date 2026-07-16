class_name ShellTemplate
extends Resource

## A shell's fixed skeleton, as data (docs/01 taskblock02 Pass B) — the
## structure `BodyAssembler` builds before any `Loadout` fills its
## discretionary sockets. `max_mass`/`max_ram` live here, not in a module
## constant, because a template IS the body they're budgeted for.

@export var root_part_id: StringName = &""
@export var mounts: Array[Mount] = []
@export var max_mass: float = 0.0
@export var max_ram: float = 0.0


func _init(
	p_root_part_id: StringName = &"",
	p_mounts: Array[Mount] = [],
	p_max_mass: float = 0.0,
	p_max_ram: float = 0.0
) -> void:
	root_part_id = p_root_part_id
	mounts = p_mounts
	max_mass = p_max_mass
	max_ram = p_max_ram

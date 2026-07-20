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
## taskblock-25 Pass F: this body's own `Shell.shell_reach` (docs/PLAN.md
## "Phase M — Melee") — how far it can lean to close melee distance. Lives
## here, not a module constant, for the same reason max_mass/max_ram do: a
## template IS the body it's budgeted for. 0.0 (default) is Pass A's own
## safe default — every existing template keeps its current (no melee
## lean) behavior until authored otherwise; a real balance number for
## real shell templates is unauthored content, not invented here.
@export var shell_reach: float = 0.0


func _init(
	p_root_part_id: StringName = &"",
	p_mounts: Array[Mount] = [],
	p_max_mass: float = 0.0,
	p_max_ram: float = 0.0,
	p_shell_reach: float = 0.0
) -> void:
	root_part_id = p_root_part_id
	mounts = p_mounts
	max_mass = p_max_mass
	max_ram = p_max_ram
	shell_reach = p_shell_reach

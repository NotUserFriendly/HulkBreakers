class_name Matrix
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var level: int = 1
@export var xp: int = 0
@export var perks: Array[StringName] = []
@export var recovery_state: Enums.RecoveryState = Enums.RecoveryState.RECOVERED
## Flag only — the penalty mechanic itself is a later tunable.
@export var pending_return_penalty: bool = false

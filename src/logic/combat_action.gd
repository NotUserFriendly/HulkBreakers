class_name CombatAction
extends RefCounted

## Base for all combat actions. Mutations flow only through apply() so combat
## stays a replayable action log (Appendix B: keeps the door open for a future
## networked layer without building any networking now).

func is_legal(_state: CombatState) -> bool:
	return false


func apply(_state: CombatState) -> void:
	pass


func describe() -> String:
	return "CombatAction"

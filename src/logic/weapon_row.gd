class_name WeaponRow
extends RefCounted

## runNotes.md: "a UI element... that just displays a list of weapons the
## unit has attached. Gray out 'inactive' weapons, with a 'why' attached."
## One row per damage-dealing part attached anywhere in the shell (socket
## tree only — a carried-but-unattached weapon can't fire regardless, same
## "sockets vs. contents" distinction InventoryRow already draws).

var part: Part
## True iff this exact weapon could actually be fired right now — the same
## PartGraph.can_operate() check DeepStrike.find_operable_weapon() runs,
## just evaluated per-weapon instead of stopping at the first match, so a
## unit dual-wielding two operable pistols sees both marked active.
var active: bool
## Empty when `active` — otherwise a short, human-readable reason: docs/10
## doesn't pin exact wording, a flagged placeholder like every other UI
## string in this panel, not a design decision.
var why: String


func _init(p_part: Part, p_active: bool, p_why: String = "") -> void:
	part = p_part
	active = p_active
	why = p_why

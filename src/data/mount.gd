class_name Mount
extends Resource

## One node of a `ShellTemplate`'s fixed skeleton (docs/01 taskblock02 Pass
## B): "attach `part_id` at `socket_id` on whatever part hosts this Mount,
## then recurse into `children` on the newly attached part." `socket_id` is
## exact — never "first free" — so a template's own declaration order can
## never silently change what gets attached where.
##
## Structural only. Discretionary fill (what weapon sits in an already-
## mounted hand's GRIP, say) is `Loadout`'s job, not a Mount node — see
## `BodyAssembler`.

@export var socket_id: StringName = &""
@export var part_id: StringName = &""
@export var children: Array[Mount] = []


func _init(
	p_socket_id: StringName = &"", p_part_id: StringName = &"", p_children: Array[Mount] = []
) -> void:
	socket_id = p_socket_id
	part_id = p_part_id
	children = p_children

class_name Socket
extends Resource

## Attachment is declared by the part, matched by the socket type — never
## keyed to a specific parent (docs/01):
##
##   legal(part, socket) := socket.socket_type in part.attaches_to
##                           and socket.occupant == null
##
## `socket_type` is an open StringName, never an enum — new content must
## never need a code edit.

@export var socket_type: StringName = &""
@export var occupant: Part = null

## The attachment frame, in the HOST part's own local space (docs/02/10,
## Phase 12.0): where and how the occupant sits relative to the part this
## socket lives on. Identity by default, so un-migrated content still
## composes correctly — the occupant simply sits at the host's own origin.
@export var transform: Transform3D = Transform3D.IDENTITY


func _init(
	p_socket_type: StringName = &"", p_transform: Transform3D = Transform3D.IDENTITY
) -> void:
	socket_type = p_socket_type
	transform = p_transform

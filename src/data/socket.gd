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


func _init(p_socket_type: StringName = &"") -> void:
	socket_type = p_socket_type

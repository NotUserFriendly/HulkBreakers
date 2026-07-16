class_name Loadout
extends Resource

## What fills a `ShellTemplate`'s discretionary sockets (docs/01 taskblock02
## Pass B) — `socket_id -> part_id` (e.g. `&"GRIP_R" -> &"rifle"`). Flat, so
## two sockets that a loadout must be able to fill independently (the left
## and right hand's own GRIP, say) need distinct `Socket.id`s authored on
## their templates — the id is what a loadout addresses, never a bare
## `socket_type` shared by both.
##
## `BodyAssembler` checks this against every Mount's own `socket_id` too
## (loadout wins on conflict with a Mount's default `part_id`), so the same
## template can be re-armed without touching its skeleton.

@export var entries: Dictionary = {}


func _init(p_entries: Dictionary = {}) -> void:
	entries = p_entries

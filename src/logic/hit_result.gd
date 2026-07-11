class_name HitResult
extends RefCounted

## Carries exactly one outcome of a resolved shot: a clean hit on `part`, a
## hit intercepted by `cover_object` (destructible — chip it down), or
## `blocked` (terrain soaked it, no damage). `cover_cell` locates the
## intercepting object for Cover.apply_damage_to_object.

var part: Part = null
var cover_object: Part = null
var cover_cell: Vector2i = Vector2i(-1, -1)
var blocked: bool = false

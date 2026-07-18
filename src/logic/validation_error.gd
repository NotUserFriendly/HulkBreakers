class_name ValidationError
extends RefCounted

## taskblock-10 Pass D: one row of `DataValidator.validate()`'s result — a
## named rejection, never a silent one ("an invalid file is rejected by
## name and does not silently vanish"). `resource_id` is the definition's
## own `id` (or its `.tres` path, if `id` itself is what's missing/blank).

var resource_id: StringName
var field: StringName
var message: String


func _init(p_resource_id: StringName, p_field: StringName, p_message: String) -> void:
	resource_id = p_resource_id
	field = p_field
	message = p_message


func _to_string() -> String:
	return "%s.%s: %s" % [resource_id, field, message]

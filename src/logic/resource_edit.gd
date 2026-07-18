class_name ResourceEdit
extends RefCounted

## taskblock-11 Pass C5: one recorded cell change — `ResourceEditStack`'s
## own unit. Split into its own file (CLAUDE.md: one class per file).

var resource: Resource
var field: StringName
var old_value: Variant
var new_value: Variant


func _init(
	p_resource: Resource, p_field: StringName, p_old_value: Variant, p_new_value: Variant
) -> void:
	resource = p_resource
	field = p_field
	old_value = p_old_value
	new_value = p_new_value

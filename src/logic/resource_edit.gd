class_name ResourceEdit
extends RefCounted

## taskblock-11 Pass C5: one recorded cell change — `ResourceEditStack`'s
## own unit. Split into its own file (CLAUDE.md: one class per file).

var resource: Resource
var field: StringName
var old_value: Variant
var new_value: Variant
## Optional — most edits are a plain `resource.set(field, value)`
## (the default, `setter` left invalid), but a `dt_curve` point isn't a
## `Resource` field at all (it's one `Vector2` inside an `Array`, a value
## type with no in-place setter) — `setter`, when valid, is called with
## the value to apply INSTEAD of `resource.set()`, so `ResourceEditStack`
## stays generic over both shapes without knowing either one exists.
var setter: Callable


func _init(
	p_resource: Resource,
	p_field: StringName,
	p_old_value: Variant,
	p_new_value: Variant,
	p_setter: Callable = Callable()
) -> void:
	resource = p_resource
	field = p_field
	old_value = p_old_value
	new_value = p_new_value
	setter = p_setter


func apply(value: Variant) -> void:
	if setter.is_valid():
		setter.call(value)
	else:
		resource.set(field, value)

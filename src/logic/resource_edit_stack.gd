class_name ResourceEditStack
extends RefCounted

## taskblock-11 Pass C5: "an edit stack of cell changes; undo reverts the
## last edit, cursor and all. Must survive across rows and across sort/
## filter changes (undo restores the VALUE, not the visual position)."
## Keyed by (resource, field) identity, never by row/column index — a
## sort or filter changing which TreeItem sits where never invalidates
## an entry here, because nothing here knows what a TreeItem is. Pure,
## headless-testable, same posture as every other controller-logic class
## in this codebase.

var _undo_stack: Array[ResourceEdit] = []
var _redo_stack: Array[ResourceEdit] = []


## Records an already-applied edit (the caller sets `resource.field =
## new_value` itself — this stack only remembers how to reverse it) and
## clears any redo history, the standard "a new edit forks off the undo
## branch" rule.
func record(resource: Resource, field: StringName, old_value: Variant, new_value: Variant) -> void:
	_undo_stack.append(ResourceEdit.new(resource, field, old_value, new_value))
	_redo_stack.clear()


## Reverts the last edit and returns it (so a caller can refresh whatever
## UI shows `edit.resource`/`edit.field`), or null if there's nothing to
## undo. Mutates `resource.field` back to `old_value` directly — the one
## place this class touches a resource itself, everything else is
## bookkeeping.
func undo() -> ResourceEdit:
	if _undo_stack.is_empty():
		return null
	var edit: ResourceEdit = _undo_stack.pop_back()
	edit.resource.set(edit.field, edit.old_value)
	_redo_stack.append(edit)
	return edit


func redo() -> ResourceEdit:
	if _redo_stack.is_empty():
		return null
	var edit: ResourceEdit = _redo_stack.pop_back()
	edit.resource.set(edit.field, edit.new_value)
	_undo_stack.append(edit)
	return edit


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()

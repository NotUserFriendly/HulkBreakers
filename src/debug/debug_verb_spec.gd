class_name DebugVerbSpec
extends RefCounted

## taskblock-30/31: one row in the debug control panel's own verb table
## (`DebugVerbs.all()`) — id/label/typed param list + the `Callable` that
## actually applies it. The panel builds its whole UI generically from
## the table instead of one hand-written form per verb, so a new verb is
## a new table row, not new UI code.

## OBJECT (taskblock-30 follow-up): never a manual-entry widget — resolves
## from the debug panel's own "active target" memory (the last thing a
## board click hit while the panel was open), the same hit-shaped
## `{kind, unit, cell}` dict `board_clicked` emits. A verb like
## `move_object` uses this instead of a UNIT param because its "object"
## can be a unit OR a cell's contents — one param type either way.
enum ParamType { UNIT, CELL, INT, FLOAT, STRING_NAME, BOOL, POSE, PRESET, OBJECT }

var id: StringName
var label: String
## Each entry: `{"name": StringName, "type": ParamType}` — built via
## `param()` below, never a hand-typed dictionary literal at the call
## site (keeps every entry's own shape identical).
var params: Array[Dictionary]
## `Callable(injector: BoutInjector, pool: Dictionary, args: Dictionary)
## -> bool` — `args` keys match `params`' own `name` entries, already
## resolved to real typed values by the panel (a UNIT param resolves to a
## real `Unit` via `CombatState.find_unit`, a CELL param to a `Vector2i`,
## ...) before this ever runs. Always a thin, one-line call into a real
## `BoutInjector` verb — never logic of its own (CLAUDE.md "no parallel
## systems": the panel, and this table, are pure wrappers).
var apply: Callable


func _init(
	p_id: StringName, p_label: String, p_params: Array[Dictionary], p_apply: Callable
) -> void:
	id = p_id
	label = p_label
	params = p_params
	apply = p_apply


static func param(name: StringName, type: ParamType) -> Dictionary:
	return {"name": name, "type": type}

class_name LogEvent
extends RefCounted

## One structured combat-log entry. `kind` is an open StringName vocabulary
## (e.g. &"shot_fired", &"deflection", &"matrix_ejected") — never an enum, so
## new event kinds never need a code edit. `text` is rendered by the
## description builder (Phase 2/docs/08) from `data`, so the log and the
## tooltips can never disagree — never hand-write `text` for a player-facing
## event.

var turn: int
var phase: Enums.Phase
var unit_id: int
var kind: StringName
var data: Dictionary
var text: String


func _init(
	p_turn: int,
	p_phase: Enums.Phase,
	p_unit_id: int,
	p_kind: StringName,
	p_data: Dictionary = {},
	p_text: String = ""
) -> void:
	turn = p_turn
	phase = p_phase
	unit_id = p_unit_id
	kind = p_kind
	data = p_data
	text = p_text


func _to_string() -> String:
	return "[T%d/%s] unit %d %s: %s" % [turn, Enums.Phase.keys()[phase], unit_id, kind, text]

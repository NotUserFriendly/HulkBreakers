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


## Deliberately drops `turn`/`phase`/`unit_id` — a scrolling per-line echo
## of "what turn/unit this is" is exactly the repetition the combat log
## used to drown in, when every unit's own turn already announces itself
## once via its own `turn_start` line (CombatState._start_turn). `kind` is
## the one label worth repeating per line — unlike turn/unit it actually
## varies line to line.
func _to_string() -> String:
	return "%s: %s" % [kind, text]

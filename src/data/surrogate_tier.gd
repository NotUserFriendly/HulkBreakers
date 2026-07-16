class_name SurrogateTier
extends Resource

## One node of the surrogate degradation DAG (docs/04) — a Resource with
## edges, not a hardcoded enum or a rank scalar, so new tiers or branches
## never need a code edit.
##
## docs/04 taskblock03 Pass A1 (correcting taskblock02 D2's "rank >= my
## rank," which was WRONG — it let a PERIPHERAL surrogate fit a
## SURROGATE_TORSIC socket, and they must be mutually exclusive):
## PERIPHERAL and TORSIC are two branches off the SAME stage (SPINAL), not
## neighbouring rungs of one line. `promotes_to` carries the graph;
## `attaches_to` is derived by transitive reachability through it
## (SurrogateLadder.derive_attaches_to), never a numeric comparison.

@export var id: StringName
@export var display_name: String = ""

## Which tier(s) this one can be regrown INTO (docs/04 taskblock02 D5's
## growth-item hook — still a seam, not built) — a DAG edge list.
## BRAIN_ONLY -> SPINAL -> {PERIPHERAL, TORSIC} -> FULL. "Any surrogate
## fits a larger box" survives Pass A1's correction: "larger" now means
## *downstream in this graph* rather than *higher in a line*.
@export var promotes_to: Array[StringName] = []

## docs/04 taskblock02 Pass D1: the socket type on a SHELL this tier's own
## surrogate Part attaches into — an explicit column on the ladder (not
## derived from `id`) so it can read `SURROGATE_BRAIN` rather than a
## mechanically-formatted `SURROGATE_BRAIN_ONLY`.
@export var socket_type: StringName = &""

## docs/04 taskblock02 Pass D3: what a docked surrogate at this tier lets
## the shell's own body-gated parts (`Part.body_requires`) actually do.
## Do NOT assume tiers nest supersets of a lower/higher tier's list —
## PERIPHERAL (limbs, hollow core) and TORSIC (organs, no limbs) may carry
## genuinely different sets, not merely more or fewer of the same tags.
@export var capabilities: Array[StringName] = []


func _init(
	p_id: StringName = &"",
	p_display_name: String = "",
	p_promotes_to: Array[StringName] = [],
	p_socket_type: StringName = &"",
	p_capabilities: Array[StringName] = []
) -> void:
	id = p_id
	display_name = p_display_name
	promotes_to = p_promotes_to
	socket_type = p_socket_type
	capabilities = p_capabilities

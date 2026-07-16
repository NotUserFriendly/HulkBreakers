class_name InventoryRow
extends RefCounted

## docs/10 taskblock03 H1: one row of the inventory panel's nested tree.
## `kind` is what makes a row honest about docs/01's "sockets and contents
## are different relationships" — a panel that flattened both into
## identical rows would lie about the model. `dt` is resolved here (a
## MaterialTable lookup), not left to the view, so InventoryRows.build() is
## the one place a row's numbers come from — never re-derived in the panel.

enum Kind { SOCKET, CONTENTS }

var part: Part
## How many levels deep in the panel's tree — the shell root is 0.
var depth: int
var kind: Kind
## The attaching Socket's own id (docs/01), or its socket_type as a
## fallback for un-migrated content whose id is still empty. Meaningless
## (empty) for a CONTENTS row — a contained item isn't socketed anywhere.
var socket_label: StringName
var dt: float
## docs/04 taskblock02 D3: requires the docked surrogate's capabilities and
## doesn't have them — present, carried, massed, shootable, but the unit
## can't actually use it right now.
var inert: bool


func _init(
	p_part: Part, p_depth: int, p_kind: Kind, p_socket_label: StringName, p_dt: float, p_inert: bool
) -> void:
	part = p_part
	depth = p_depth
	kind = p_kind
	socket_label = p_socket_label
	dt = p_dt
	inert = p_inert

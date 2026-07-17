class_name ApMpPips
extends RefCounted

## taskblock-07 Pass G: "above the action bar: pips, not numbers." Pure
## pip-state data — the view only ever renders what this hands it, same
## split as ActionCatalog/WeaponRows.
##
## AP has a natural ceiling (`max_ap`), so its row is a FIXED `max_ap`
## slots long — a spent pip renders dim, never disappears ("the total
## should stay readable"). MP has no such field anywhere on Unit (no
## `max_mp`) — its row's own length IS the current pool; there's nothing
## beyond it to render as "spent but still slotted."
##
## docs/09/taskblock-04 B1: MP is integral by design — `mp_pip_count`
## rounds only as a defensive last resort ("if anything ever produces a
## fractional MP, that's a bug in the economy, not a rendering problem" —
## Pass G's own words), never silently truncates a real fraction away.


## One entry per `unit.max_ap` slot — `true` (lit) for the first
## `unit.ap` of them, `false` (dim) for the rest. A unit with 0 AP still
## returns `max_ap` all-false entries, never an empty array — "a unit
## with 0 shows an empty row, not a missing one."
static func ap_pip_states(unit: Unit) -> Array[bool]:
	var states: Array[bool] = []
	for i in range(unit.max_ap):
		states.append(i < unit.ap)
	return states


## The current MP pool, as a whole number of lit pips. 0 is a legitimate,
## meaningful result (an empty row), never null/omitted.
static func mp_pip_count(unit: Unit) -> int:
	return int(round(unit.mp))

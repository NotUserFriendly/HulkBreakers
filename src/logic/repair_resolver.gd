class_name RepairResolver
extends RefCounted

## taskblock-22 Pass E: "power-bearing batteries, a welder that consumes
## power + scrap to heal." A repair's own three checks (is there an
## operable welder, does it have a charged battery, is the target
## actually damaged) live here, shared by RepairAction's own is_legal()
## and by any view that wants to show "greyed if no welder or no matching
## scrap" without re-deriving the same logic a second time.

const WELDER_TAG := &"WELDER"
## taskblock-22 Pass E2: "up to 3 HP for 4 AP." Flagged placeholders, not
## tuned design.
const REPAIR_AP_COST := 4
const MAX_HEAL_PER_USE := 3
## taskblock-22 Pass E3: "normalize 1 scrap -> 1 HP for now." A scrap
## resource id is the damaged part's own `material` (e.g. &"steel") —
## deliberately its own, separate resource namespace from the EXISTING
## salvage_yield categories (&"metals"/&"organics"/&"reactives", tb14):
## re-authoring every part's own salvage_yield to material-specific ids
## would be a much wider, invasive change this pass doesn't ask for.
## Flagged: no existing part's own salvage_yield yields a per-material
## scrap resource yet, so reaching a repair naturally through play (not
## just `mission.gather_resource()` called directly) needs a follow-up
## authoring pass — out of this pass's own scope, which only builds the
## mechanic itself.
const SCRAP_PER_HP := 1


## An operable Welder attached to `unit`, with a real, operable manipulator
## to hold it (`PartGraph.can_operate`, the same check every weapon
## already goes through) — or null if none exists.
static func find_operable_welder(unit: Unit) -> Part:
	var operable: Array[Part] = unit.shell.operable_parts()
	for part: Part in operable:
		if not part.tags.has(WELDER_TAG):
			continue
		var manipulators: Array[Part] = []
		for other: Part in operable:
			if other != part:
				manipulators.append(other)
		if PartGraph.can_operate(part, manipulators):
			return part
	return null


## The Tool Battery docked in `welder`'s own socket, or null if empty/
## missing — the welder's OWN dedicated reserve, never the shell-wide
## power system `PowerResolver` tracks (`PowerResolver.TOOL_BATTERY_TAG`
## excludes it for exactly this reason).
static func welder_battery(welder: Part) -> Part:
	if welder == null:
		return null
	for socket: Socket in welder.sockets:
		if socket.occupant != null and socket.occupant.battery_capacity > 0.0:
			return socket.occupant
	return null


## True once a unit has an operable welder AND that welder's own battery
## is alive with real charge left — "greyed if no welder" reads this
## directly rather than re-deriving it.
static func can_repair_with(unit: Unit) -> bool:
	var welder: Part = find_operable_welder(unit)
	var battery: Part = welder_battery(welder)
	return battery != null and battery.hp > 0 and battery.battery_charge > 0.0


## How much HP one repair use actually restores — capped at
## MAX_HEAL_PER_USE, and never more than the part is actually missing.
static func heal_amount_for(target: Part) -> int:
	return mini(MAX_HEAL_PER_USE, target.max_hp - target.hp)


## 1:1 with heal amount today (SCRAP_PER_HP) — its own function, not
## inlined, so a future non-1:1 rebalance is one number to change, not a
## re-derivation at every call site.
static func scrap_cost_for(target: Part) -> int:
	return heal_amount_for(target) * SCRAP_PER_HP


## The resource id repairing `target` actually draws from — its own
## material, e.g. &"steel" for a steel part.
static func scrap_resource_id_for(target: Part) -> StringName:
	return target.material


## Every damaged part in `unit`'s own shell that a repair could actually
## help — "prompts with all repairable damaged parts" (the action-bar
## path) reads this directly. Not gated on scrap availability or an
## operable welder — a caller shows the LIST regardless, then greys/costs
## each entry individually (`scrap_cost_for` + a mission's own resource
## count).
static func repairable_parts(unit: Unit) -> Array[Part]:
	var damaged: Array[Part] = []
	for part: Part in unit.shell.all_parts():
		if part.hp > 0 and part.hp < part.max_hp:
			damaged.append(part)
	return damaged

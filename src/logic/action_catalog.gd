class_name ActionCatalog
extends RefCounted

## taskblock-07 Pass E: the action bar's own data — pure and
## headless-testable (InventoryRows/WeaponRows's own precedent: the view
## only ever renders what this computes, it computes nothing itself).
##
## actions_for(unit) =
##       ∪ part.provides_actions   for each living, attached, non-inert part
##     ∪ ∪ perk.provides_actions   for each perk on unit.matrix   # EMPTY today
##     filtered by each ActionDef's `requires_action`
##
## Source-agnostic on purpose (E3): moving `&"overwatch"` off a gun's
## `provides_actions` and onto a future perk's is a data edit on the
## SOURCE, not a code edit here — this file unions whatever
## `Matrix.provides_actions()` returns exactly the same way it unions a
## part's own array, today or later.


## The full registry of authored actions. Not per-unit; `actions_for`
## filters this down to what a specific unit can actually use right now.
static func defs() -> Array[ActionDef]:
	return [
		ActionDef.new(&"shoot", "Shoot", "SH"),
		ActionDef.new(&"saw", "Saw", "SW"),
		# requires_action: only available if something else already
		# provides shoot — the instrument overwatch still needs even once
		# its provider moves off the gun and onto the matrix (E3).
		ActionDef.new(&"overwatch", "Overwatch", "OW", {}, &"shoot", false),
	]


## Every ActionDef this unit can use right now, in stable order: by the
## providing part's position in the socket tree (`Shell.all_parts()`'s own
## depth-first, socket-declaration order), then by action id within a
## single part's own array. Never reshuffles between frames for the same
## shell/matrix state.
static func actions_for(
	unit: Unit, ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
) -> Array[ActionDef]:
	var provided: Array[StringName] = _provided_ids(unit, ladder)
	var by_id: Dictionary = {}
	for def: ActionDef in defs():
		by_id[def.id] = def

	var result: Array[ActionDef] = []
	# Order comes from `provided` itself (tree-position, then action id
	# within a single part — see _provided_ids), never from this
	# registry's own declaration order.
	for id: StringName in provided:
		var def: ActionDef = by_id.get(id)
		if def == null:
			continue
		if def.requires_action != &"" and not def.requires_action in provided:
			continue
		result.append(def)
	return result


static func _provided_ids(unit: Unit, ladder: Array[SurrogateTier]) -> Array[StringName]:
	var ids: Array[StringName] = []
	if unit.shell.root == null:
		return ids
	var living: Array[Part] = unit.shell.living_parts()
	for part: Part in unit.shell.all_parts():
		if part.hp <= 0:
			continue
		if not unit.can_use_part(part, ladder):
			continue
		if not _is_operable(part, living):
			continue
		var own_ids: Array[StringName] = part.provides_actions.duplicate()
		_sort_by_id(own_ids)
		for id: StringName in own_ids:
			if not id in ids:
				ids.append(id)
	if unit.matrix != null:
		var perk_ids: Array[StringName] = unit.matrix.provides_actions().duplicate()
		_sort_by_id(perk_ids)
		for id: StringName in perk_ids:
			if not id in ids:
				ids.append(id)
	return ids


## taskblock-08 A1: "the armed action decides what a click means" — the
## specific living, operable part providing `action_id` right now, or null.
## SHOOT armed picks the part that actually provides &"shoot", SAW armed
## picks whichever part provides &"saw", never just "any weapon" — the
## same per-part gates `_provided_ids` applies (surrogate ladder + `_is_
## operable`), so this only ever returns a part the action bar would also
## list the action as coming from.
static func provider_for(
	unit: Unit,
	action_id: StringName,
	ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
) -> Part:
	var living: Array[Part] = unit.shell.living_parts()
	for part: Part in living:
		if not unit.can_use_part(part, ladder):
			continue
		if action_id in part.provides_actions and _is_operable(part, living):
			return part
	return null


## Plain Array.sort() on StringName does NOT compare lexicographically (it
## orders by StringName's own interning, not the string it names) — a
## String-cast custom comparator is what actually gives "then by action
## id" a human-legible, spec-literal meaning.
static func _sort_by_id(ids: Array[StringName]) -> void:
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))


## E2: "that part's `requires` are met by the shell's capabilities — the
## same check that makes a rifle unusable with two saw hands." A part with
## no `requires` (a saw hand, armor) is trivially operable; `provides_actions`
## being non-empty is what actually gates whether this check matters.
static func _is_operable(part: Part, living: Array[Part]) -> bool:
	if part.requires.is_empty():
		return true
	var manipulators: Array[Part] = []
	for other: Part in living:
		if other != part:
			manipulators.append(other)
	return PartGraph.can_operate(part, manipulators)

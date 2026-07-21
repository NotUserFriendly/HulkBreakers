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

## taskblock-24 Pass B: the ids `build_firing_action` backs with a plain
## `AttackAction` — shared here (not just duplicated as match-arm
## literals) so `AttackAction.is_legal`'s own provides_actions check can't
## quietly drift from what this file actually recognizes as "a single-pull
## shot," the same "one seam" invariant the rest of this pass exists to
## enforce. `&"saw"` is a different PROVIDING weapon, never a different
## resolution mechanic — it belongs on this list, not a second one.
const ATTACK_ACTION_IDS: Array[StringName] = [&"shoot", &"saw"]

## taskblock-25 Pass B: the melee counterpart of `ATTACK_ACTION_IDS` —
## `StabAction.is_legal`'s own `provides_actions` re-check reads this same
## list, so it can't quietly drift from what `build_firing_action` actually
## recognizes as a stab.
const MELEE_ACTION_IDS: Array[StringName] = [&"stab"]
## taskblock-25 Pass C: `SlashAction.is_legal`'s own re-check list —
## same posture as `MELEE_ACTION_IDS` above, its own list because a slash
## is a distinct action class, never folded into the stab check.
const SLASH_ACTION_IDS: Array[StringName] = [&"slash"]
## taskblock-25 Pass C: `GrindAction.is_legal`'s own re-check list — armed
## as `&"hold"`, the taskblock's own payload name (the CLASS is
## `GrindAction`; `HoldAction` already names taskblock-19's "defer to the
## next ally" turn action).
const GRIND_ACTION_IDS: Array[StringName] = [&"hold"]


## The full registry of authored actions. Not per-unit; `actions_for`
## filters this down to what a specific unit can actually use right now.
static func defs() -> Array[ActionDef]:
	return [
		ActionDef.new(&"shoot", "Shoot", "SH"),
		ActionDef.new(&"saw", "Saw", "SW"),
		# taskblock-25 Pass B: a point-payload melee strike, backed by
		# whichever weapon Part lists &"stab" in its own `provides_actions`
		# — same authoring convention as &"burst" above.
		ActionDef.new(&"stab", "Stab", "ST"),
		# taskblock-25 Pass C: a line-payload melee swing, backed by
		# whichever weapon Part lists &"slash"; a many-hit grind, backed by
		# whichever weapon Part lists &"hold" (class `GrindAction` — see
		# `GRIND_ACTION_IDS`'s own doc comment for the naming collision).
		ActionDef.new(&"slash", "Slash", "SL"),
		ActionDef.new(&"hold", "Hold", "HL"),
		# requires_action: only available if something else already
		# provides shoot — the instrument overwatch still needs even once
		# its provider moves off the gun and onto the matrix (E3).
		ActionDef.new(&"overwatch", "Overwatch", "OW", {}, &"shoot", false),
		# taskblock-13 Pass C: same shape as shoot — an aimed, target-armed
		# action, backed by whichever weapon Part lists &"burst" in its own
		# provides_actions (a data-authoring convention: only a Part whose
		# WeaponDef.burst_size > 1 should ever list it — BurstAction.is_legal
		# itself is the real runtime gate).
		ActionDef.new(&"burst", "Burst", "BR"),
		# taskblock-22 Pass E: requires_target=false, same posture as
		# overwatch — repair needs a PART picked from a list, never a board
		# click, so `arm_action`'s own click-driven flow doesn't apply. The
		# real UI call site (a popup listing repairable parts) lives in
		# SquadControlOverlay, mirroring overwatch's own still-flagged gap
		# rather than inventing a second armed-action shape here.
		ActionDef.new(&"repair", "Repair", "RP", {}, &"", false),
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


## taskblock-24 Pass A: the ONE place an action id becomes a real
## `CombatAction` instance — used by both the player's own click-to-fire
## confirm (`TacticsController.confirm_shot`/`_confirm_step_out`) and the
## AI's own firing helper (`UnitAI._firing_action_for`), so neither can
## silently drift from what a weapon actually provides. `&"burst"` is the
## one id backed by a distinct class. Returns null for any other id
## (never invents an action for one this file doesn't recognize) — a
## caller that gets null simply has nothing to enqueue, the same "no
## further action, no silent rollback" contract `ActionQueue.enqueue`
## itself already has.
static func build_firing_action(
	action_id: StringName,
	unit: Unit,
	weapon_id: StringName,
	target_cell: Vector2i,
	aim_offset: Vector2 = Vector2.ZERO,
	extra_sources: Array[ModSource] = [],
	mission: MissionState = null,
	orientation: StringName = &"horizontal"
) -> CombatAction:
	if action_id == &"burst":
		return BurstAction.new(unit, weapon_id, target_cell, aim_offset, extra_sources, mission)
	if action_id in ATTACK_ACTION_IDS:
		return AttackAction.new(unit, weapon_id, target_cell, aim_offset, extra_sources, mission)
	if action_id in MELEE_ACTION_IDS:
		return StabAction.new(unit, weapon_id, target_cell, aim_offset, extra_sources, mission)
	if action_id in SLASH_ACTION_IDS:
		return SlashAction.new(
			unit, weapon_id, target_cell, orientation, aim_offset, extra_sources, mission
		)
	if action_id in GRIND_ACTION_IDS:
		return GrindAction.new(unit, weapon_id, target_cell, aim_offset, extra_sources, mission)
	return null


## BR30.xx: the AP `action_id` actually charges from `provider` — almost
## always `provider.ap_cost` itself, except `&"burst"`, which authors its
## own distinct, usually-higher `weapon_def.burst_ap_cost` (many more
## trigger-pulls than a single shot) and only falls back to `ap_cost` when
## a weapon never authored one (`BurstAction._ap_cost`'s own original
## logic, moved here). The ONE seam both `ActionBar._can_afford`'s
## affordability check and `BurstAction`'s real AP deduction read, so
## neither can silently drift from what the other actually charges — the
## action bar previously read `provider.ap_cost` directly and showed BURST
## as affordable using the single-shot cost, letting a player arm (and
## then have silently rejected) a burst they couldn't actually pay for.
static func ap_cost_for(action_id: StringName, provider: Part) -> int:
	if (
		action_id == &"burst"
		and provider.weapon_def != null
		and provider.weapon_def.burst_ap_cost > 0
	):
		return provider.weapon_def.burst_ap_cost
	return provider.ap_cost


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

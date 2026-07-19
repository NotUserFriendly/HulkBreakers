class_name TooltipBuilder
extends RefCounted

## taskblock-07 Pass F1: the "whatever provides detail implements this"
## interface, as one builder module — see TooltipData's own doc comment
## for why this is a module, not a method scattered across Part/Unit/
## ActionDef. Pure and headless-testable, same split as InventoryRows/
## WeaponRows: the view only ever renders a TooltipData this hands it.
##
## No arithmetic anywhere here (Pass F/TESTS: "no tooltip computes a
## number locally") — every value is a raw field read, a MaterialTable/
## Shell lookup already responsible for that number elsewhere
## (InventoryRows' own precedent), or (docs/08) a StatResolver-backed
## value, never a locally invented calculation.


## docs/10 taskblock03 H2: the same "damaged" threshold InventoryPanel's
## own condition color uses for `changed` — a part whose hp has actually
## dropped is exactly the "differs from its own baseline" case `changed`
## exists to flag.
static func for_part(
	part: Part, material_table: MaterialTable, row: InventoryRow = null
) -> TooltipData:
	var title: String = part.display_name if part.display_name != "" else String(part.id)
	var data := TooltipData.new(title)
	data.add_row("condition", "%d/%d" % [part.hp, part.max_hp], part.hp < part.max_hp)
	var dt: float = row.dt if row != null else material_table.get_entry(part.material).dt
	data.add_row("material", "%s (DT %.1f)" % [String(part.material), dt])
	data.add_row("mass", "%.1f" % part.mass)
	data.add_row("bulk", "%.1f" % part.bulk)
	if row != null:
		if row.kind == InventoryRow.Kind.SOCKET and row.socket_label != &"":
			data.add_row("socket", String(row.socket_label))
		elif row.kind == InventoryRow.Kind.CONTENTS:
			data.add_row("attachment", "carried, not attached")
		if row.inert:
			data.add_row("inert", "requires unmet", true)
	if not part.salvage_yield.is_empty():
		var yields: Array[String] = []
		for resource_id: StringName in part.salvage_yield:
			yields.append("%s x%s" % [resource_id, part.salvage_yield[resource_id]])
		data.add_row("salvage", ", ".join(yields))
	return data


## taskblock-07 F1/TESTS: "hovering an enemy yields its status (no gating —
## taskblock-04 E1)" — every living part, any squad, exactly as InventoryRows
## already shows the player's own shell. F3: the taskblock itself flags this
## as potentially long; that's a known, deliberately deferred concern
## (pinning), not something to truncate here.
static func for_unit(unit: Unit, material_table: MaterialTable) -> TooltipData:
	var data := TooltipData.new("unit %d — squad %d" % [unit.id, unit.squad_id])
	if unit.shell.root == null:
		return data
	for row: InventoryRow in InventoryRows.build(unit, material_table):
		var part: Part = row.part
		var name: String = part.display_name if part.display_name != "" else String(part.id)
		data.add_row(name, "%d/%d" % [part.hp, part.max_hp], part.hp < part.max_hp)
	return data


static func for_action(action: ActionDef) -> TooltipData:
	var data := TooltipData.new(
		action.display_name if action.display_name != "" else String(action.id)
	)
	if not action.requires.is_empty():
		var needs: Array[String] = []
		for capability: StringName in action.requires:
			needs.append("%dx %s" % [int(action.requires[capability]), capability])
		data.add_row("requires", ", ".join(needs))
	if action.requires_action != &"":
		data.add_row("needs", String(action.requires_action))
	return data


## taskblock-07 Pass G: "pips are hoverable and provide a tooltip
## explaining the pool and the conversion" — every row is a raw field or
## `Unit.mp_per_ap()`'s own already-resolved (StatResolver-backed) value,
## never a locally recomputed one.
static func for_ap_pips(unit: Unit) -> TooltipData:
	var data := TooltipData.new("AP")
	data.add_row("available", "%d/%d" % [unit.ap, unit.max_ap])
	data.add_row("converts to", "%.1f MP per AP" % unit.mp_per_ap())
	return data


static func for_mp_pips(unit: Unit) -> TooltipData:
	var data := TooltipData.new("MP")
	data.add_row("available", str(ApMpPips.mp_pip_count(unit)))
	data.add_row("discarded", "not banked at end of turn")
	return data


static func for_queue_entry(entry: Dictionary) -> TooltipData:
	var data := TooltipData.new(String(entry.get("describe", "")))
	data.add_row("AP", str(entry.get("ap", 0)))
	data.add_row("MP", str(entry.get("mp", 0.0)))
	return data


## docs/10 taskblock04 E3/E1, taskblock-07 F1/TESTS: "hovering a tile fills
## the readout with what's on it" — a living unit's own status wins (its
## own tooltip, no gating by squad), then a field object's own detail,
## then terrain alone. Distinct branches rather than one merged blob:
## matches the three separate cases the taskblock's own TESTS name
## (terrain / enemy status / field object detail) rather than inventing a
## fourth "all three at once" shape nothing asks for.
static func for_tile(info: Dictionary, material_table: MaterialTable) -> TooltipData:
	if info.is_empty():
		return TooltipData.new()
	var unit: Variant = info.get("unit")
	if unit != null:
		return for_unit(unit as Unit, material_table)
	var field_object: Variant = info.get("field_object")
	if field_object != null:
		return for_part(field_object as Part, material_table)

	var cell: Vector2i = info.cell
	var data := TooltipData.new("cell (%d, %d)" % [cell.x, cell.y])
	data.add_row("terrain", Enums.TerrainType.keys()[info.terrain])
	# taskblock-16 Pass B2: no separate "cover" row here — a cell WITH
	# cover always has a `field_object`, and the branch above already
	# returns that object's own full tooltip (for_part) before this
	# terrain-only branch is ever reached. Object geometry is the one
	# source of truth now, never a parallel scalar shown alongside it.
	if info.get("visible_from_selected") != null:
		data.add_row("visible from selected", str(info.visible_from_selected))
	return data
